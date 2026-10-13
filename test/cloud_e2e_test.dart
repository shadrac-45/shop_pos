// ============================================
// ShopPOS Cloud end-to-end: several devices, shops and people
// ============================================
// The app's real CloudService / SyncService / SaleService on three
// separate local databases (three "devices") against the real backend
// (../backend, in-memory Postgres with RLS, fake Paystack). Nothing is
// shared between devices except the cloud — like phones on different
// networks.
//
//   Device A — owner (created the business, Shop A)
//   Device B — Shop A till, joined by a cashier (new install)
//   Device C — Shop B till, joined by Shop B's cashier (new install)
//
// Skipped if Node or the backend folder isn't available
// (SHOPPOS_BACKEND_DIR overrides ../backend).

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/services/cloud_service.dart';
import 'package:shop_pos/core/services/sync_service.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/core/utils/id_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/services/auth_service.dart';
import 'package:shop_pos/features/cloud/screens/cloud_dashboard_screen.dart';
import 'package:shop_pos/features/customers/models/customer.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/services/inventory_service.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/services/sale_service.dart';

const _password = 'Cloud-Pass-2026';

Future<int> stockOf(Isar isar, String productUuid) async {
  final p = await isar.products.filter().uuidEqualTo(productUuid).findFirst();
  final batches = await isar.batchs.filter().productIdEqualTo(p!.id).findAll();
  return batches.fold<int>(0, (s, b) => s + b.quantity);
}

Future<SyncResult> sync(Isar isar, AppUser who) async {
  final r = await SyncService.syncNow(isar, baseUrl: '', checkConnectivity: false, signedInUserId: who.id);
  expect(r.error, isNull, reason: 'sync failed: ${r.error}');
  return r;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backendDir = Platform.environment['SHOPPOS_BACKEND_DIR'] ?? '../backend';
  final available = File('$backendDir/scripts/e2e-server.js').existsSync() &&
      Directory('$backendDir/node_modules').existsSync();

  Process? server;
  late String url;
  late Directory dir;
  late Isar a, b, c;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(libraries: {Abi.windowsX64: 'isar.dll'});
    } catch (_) {}
    if (!available) return;
    server = await Process.start('node', ['scripts/e2e-server.js'], workingDirectory: backendDir);
    final port = Completer<String>();
    server!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final m = RegExp(r'^PORT=(\d+)').firstMatch(line);
      if (m != null && !port.isCompleted) port.complete(m.group(1));
    });
    server!.stderr.transform(utf8.decoder).listen((e) => stderr.write('[backend] $e'));
    url = 'http://127.0.0.1:${await port.future.timeout(const Duration(seconds: 60))}/api';
  });

  tearDownAll(() async {
    await server?.stdin.close();
    server?.kill();
  });

  setUp(() async {
    // The test binding fakes all HTTP; these tests need the real backend.
    HttpOverrides.global = null;
    dir = await Directory.systemTemp.createTemp('pos_cloud_');
    a = await Isar.open(allSchemas, directory: dir.path, name: 'deviceA');
    b = await Isar.open(allSchemas, directory: dir.path, name: 'deviceB');
    c = await Isar.open(allSchemas, directory: dir.path, name: 'deviceC');
    // B and C are brand-new installs: no setup, no owner, nothing.
    for (final isar in [b, c]) {
      await isar.writeTxn(() => isar.storeSettings.put(StoreSettings()..deviceId = IdHelpers.newUuid()));
    }
  });

  tearDown(() async {
    for (final isar in [a, b, c]) {
      await isar.close(deleteFromDisk: true);
    }
    await dir.delete(recursive: true);
  });

  test('owner, cashiers and shops on separate devices share exactly the right data', () async {
    final ownerEmail = 'owner-${IdHelpers.newUuid().substring(0, 8)}@example.com';
    final tag = IdHelpers.newUuid().substring(0, 6);

    // ── Device A: an existing till set up with the wizard; owner creates the cloud business ──
    var owner = AppUser()
      ..name = 'Ama Owner'
      ..role = AppConstants.roleOwner
      ..uuid = IdHelpers.newUuid()
      ..pinHash = HashHelpers.hashPin('482910')
      ..updatedAt = DateTime.now();
    await a.writeTxn(() async {
      await a.appUsers.put(owner);
      await a.storeSettings.put(StoreSettings()
        ..storeName = 'Jakmob Shop A'
        ..setupCompleted = true
        ..deviceId = IdHelpers.newUuid());
    });
    final milo = await InventoryService.createProduct(
      a, owner,
      const ProductInput(name: 'Milo', price: 32, category: 'Drinks', quickButtonColor: 0, costPrice: 25),
      initialQuantity: 20,
      expiryDate: DateTime.now().add(const Duration(days: 200)),
    );
    final created = await CloudService.createShop(a, url: url, email: ownerEmail, password: _password);
    expect(created.error, isNull);
    owner = (await a.appUsers.get(owner.id))!;
    expect(CloudService.hasSession(owner), isTrue);
    expect((await a.storeSettings.get(1))!.cloudDeviceCode, 'T1');
    await sync(a, owner);
    expect(await SyncService.pendingCount(a), 0);

    // Owner (remotely, through the API the dashboard uses) adds Shop B and
    // creates one cashier per shop with their own sign-in.
    final api = CloudApi(url, owner.cloudToken!);
    final shopA = (await a.storeSettings.get(1))!.cloudShopId;
    final shopB = ((await api.call('POST', '/shops', body: {'name': 'Jakmob Shop B'}))['shop'] as Map)['id'] as String;
    await api.call('POST', '/users', shopId: shopA, body: {
      'name': 'Abena', 'role': 'cashier', 'username': 'abena$tag', 'password': _password, 'pin': '2468', 'shopIds': [shopA],
    });
    await api.call('POST', '/users', shopId: shopB, body: {
      'name': 'Bayo', 'role': 'cashier', 'username': 'bayo$tag', 'password': _password, 'pin': '1357', 'shopIds': [shopB],
    });

    // ── TEST 9/11: Device B, new install, cashier joins Shop A ──
    final loginB = await CloudService.login(url: url, identifier: 'abena$tag', password: _password);
    expect(loginB.error, isNull);
    expect(loginB.shops.map((s) => s.id), [shopA], reason: 'a cashier only sees their own shop');
    var abena = await CloudService.joinShop(b, loginB, shopA, fresh: true);
    expect(abena.role, AppConstants.roleCashier);
    final settingsB = (await b.storeSettings.get(1))!;
    expect(settingsB.setupCompleted, isTrue);
    expect(settingsB.cloudDeviceCode, 'T2');
    expect(await b.appUsers.filter().roleEqualTo(AppConstants.roleOwner).findAll(),
        everyElement(predicate<AppUser>((u) => u.uuid == owner.uuid)),
        reason: 'no new local owner on a joining device');
    expect((await api.call('GET', '/shops'))['shops'], hasLength(2), reason: 'no new shop either');
    // TEST 1: the same Shop A data on both devices.
    expect(await stockOf(b, milo.uuid!), 20);
    // Abena's PIN now works on Device B, even offline.
    expect((await AuthService.findUserByPin(b, '2468'))?.uuid, abena.uuid);

    // ── TEST 7/8/14: Device B offline sales, synced exactly once ──
    final productB = (await b.products.filter().uuidEqualTo(milo.uuid).findFirst())!;
    final s1 = await SaleService.completeSale(b, abena,
        lines: [CheckoutLine(product: productB, quantity: 2)], payments: [const PaymentInput(AppConstants.paymentCash, 64)]);
    final s2 = await SaleService.completeSale(b, abena,
        lines: [CheckoutLine(product: productB, quantity: 1)], payments: [const PaymentInput(AppConstants.paymentCash, 32)]);
    expect([s1.receiptNumber, s2.receiptNumber], ['T2-000001', 'T2-000002']);
    abena = (await b.appUsers.get(abena.id))!;
    await sync(b, abena);
    await SyncService.markAllUnsynced(b); // as if the replies had been lost
    await sync(b, abena);

    // ── TEST 2: Device A (owner, elsewhere) receives the sales ──
    await sync(a, owner);
    expect(await a.sales.filter().uuidEqualTo(s1.uuid).count(), 1);
    expect(await a.sales.filter().uuidEqualTo(s2.uuid).count(), 1, reason: 'no duplicate after the retry');
    expect((await a.sales.filter().uuidEqualTo(s1.uuid).findFirst())!.receiptNumber, 'T2-000001',
        reason: 'the same receipt number on every device');
    expect(await stockOf(a, milo.uuid!), 17);
    // Owner's own sale on Device A uses its own till code: no collision.
    final productA = (await a.products.get(milo.id))!;
    final s3 = await SaleService.completeSale(a, owner,
        lines: [CheckoutLine(product: productA, quantity: 1)], payments: [const PaymentInput(AppConstants.paymentCash, 32)]);
    expect(s3.receiptNumber, 'T1-000001');
    await sync(a, owner);
    await sync(b, abena);
    expect(await stockOf(b, milo.uuid!), 16);

    // ── A cashier's till can't change what a cashier may not change ──
    final pb = (await b.products.filter().uuidEqualTo(milo.uuid).findFirst())!;
    await b.writeTxn(() async {
      pb
        ..price = 0.5
        ..updatedAt = DateTime.now().add(const Duration(hours: 1))
        ..modifiedBy = abena.id
        ..isSynced = false;
      await b.products.put(pb);
    });
    final refused = await sync(b, abena);
    expect(refused.conflicts, 1);
    await sync(a, owner);
    expect((await a.products.get(milo.id))!.price, 32, reason: 'cashier price change refused by the cloud');

    // ── TEST 3/10: the owner signs in on Device B and restocks there ──
    final ownerOnB = await CloudService.passwordSignIn(b, identifier: ownerEmail, password: _password);
    expect(ownerOnB.error, isNull);
    final ownerB = ownerOnB.user!;
    expect(ownerB.uuid, owner.uuid, reason: 'the same account, not a new owner');
    final restockProduct = (await b.products.filter().uuidEqualTo(milo.uuid).findFirst())!;
    await InventoryService.restock(b, ownerB,
        product: restockProduct, quantity: 10, expiryDate: DateTime.now().add(const Duration(days: 90)));
    await sync(b, ownerB);
    await sync(a, owner);
    expect(await stockOf(a, milo.uuid!), 26);

    // ── TEST 4: Device C (Shop B cashier) never sees Shop A ──
    final loginC = await CloudService.login(url: url, identifier: 'bayo$tag', password: _password);
    expect(loginC.shops.map((s) => s.id), [shopB]);
    final bayo = await CloudService.joinShop(c, loginC, shopB, fresh: true);
    expect(await c.products.filter().uuidEqualTo(milo.uuid).count(), 0);
    expect(await c.sales.count(), 0);
    expect((await c.storeSettings.get(1))!.cloudDeviceCode, 'T1', reason: 'till codes are per shop');
    // …and can't put this till into Shop A.
    expect(() => CloudService.joinShop(c, loginC, shopA), throwsA(isA<CloudJoinException>()));

    // ── TEST 12: sign out and back in repeatedly (no restart) ──
    for (var i = 0; i < 3; i++) {
      await CloudService.signOut(c, (await c.appUsers.get(bayo.id))!);
      expect(CloudService.hasSession(await c.appUsers.get(bayo.id)), isFalse);
      final again = await CloudService.pinSignIn(c, '1357');
      expect(again.ok, isTrue);
      await sync(c, again.user!);
    }

    // ── Customers sync both ways ──
    await c.writeTxn(() => c.customers.put(Customer()
      ..uuid = IdHelpers.newUuid()
      ..name = 'Kofi B'
      ..updatedAt = DateTime.now()
      ..modifiedBy = bayo.id));
    final cust = Customer()
      ..uuid = IdHelpers.newUuid()
      ..name = 'Efua A'
      ..updatedAt = DateTime.now()
      ..modifiedBy = abena.id;
    await b.writeTxn(() => b.customers.put(cust));
    await sync(c, (await c.appUsers.get(bayo.id))!);
    await sync(b, (await b.appUsers.get(abena.id))!);
    await sync(a, owner);
    expect(await a.customers.filter().nameEqualTo('Efua A').count(), 1);
    expect(await a.customers.filter().nameEqualTo('Kofi B').count(), 0, reason: 'Shop B customer stays in Shop B');

    // ── TEST 15: the cloud knows who did it, where and on which till ──
    final sales = (await api.call('GET', '/sales', shopId: shopA, query: {
      'from': DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
      'to': DateTime.now().add(const Duration(minutes: 5)).toUtc().toIso8601String(),
    }))['sales'] as List;
    final cloudS1 = sales.firstWhere((s) => s['id'] == s1.uuid) as Map;
    final users = (await api.call('GET', '/users', shopId: shopA))['users'] as List;
    final abenaId = (users.firstWhere((u) => u['name'] == 'Abena') as Map)['id'];
    expect(cloudS1['cashierId'], abenaId);
    expect(cloudS1['deviceId'], settingsB.deviceId);
    expect(cloudS1['receiptNumber'], 'T2-000001');
    final audit = (await api.call('GET', '/audit', shopId: shopA))['entries'] as List;
    expect(audit.any((e) => e['action'] == 'device_registered' && '${e['details']}'.contains('Abena')), isTrue);
  }, skip: available ? false : 'backend not found at $backendDir', timeout: const Timeout(Duration(minutes: 4)));
}
