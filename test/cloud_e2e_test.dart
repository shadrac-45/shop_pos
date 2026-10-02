// ============================================
// ShopPOS Cloud end-to-end sync test
// ============================================
// The app's real CloudService and SyncService (two tills, two Isar
// databases) against the real backend (../backend, started with an
// in-memory Postgres and a fake Paystack). Skipped if Node or the
// backend folder isn't available. Override the folder with
// SHOPPOS_BACKEND_DIR.

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

Future<SyncResult> sync(Isar isar) async {
  final r = await SyncService.syncNow(isar, baseUrl: '', checkConnectivity: false);
  expect(r.error, isNull, reason: 'sync failed: ${r.error}');
  expect(r.conflicts, 0);
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
  late Isar a;
  late Isar b;
  late AppUser owner;

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
    // The test binding fakes all HTTP; this test needs the real backend.
    HttpOverrides.global = null;
    dir = await Directory.systemTemp.createTemp('pos_cloud_');
    a = await Isar.open(allSchemas, directory: dir.path, name: 'tillA');
    b = await Isar.open(allSchemas, directory: dir.path, name: 'tillB');
    owner = AppUser()
      ..name = 'Ama Owner'
      ..role = AppConstants.roleOwner
      ..uuid = IdHelpers.newUuid()
      ..pinHash = HashHelpers.hashPin('482910')
      ..updatedAt = DateTime.now();
    await a.writeTxn(() async {
      await a.appUsers.put(owner);
      await a.storeSettings.put(StoreSettings()
        ..storeName = 'Jakmob Mini Mart'
        ..deviceId = IdHelpers.newUuid());
    });
    await b.writeTxn(() => b.storeSettings.put(StoreSettings()..deviceId = IdHelpers.newUuid()));
  });

  tearDown(() async {
    await a.close(deleteFromDisk: true);
    await b.close(deleteFromDisk: true);
    await dir.delete(recursive: true);
  });

  test('two tills share one cloud shop; offline sales sync once, even when retried', () async {
    final email = 'owner-${IdHelpers.newUuid().substring(0, 8)}@example.com';

    // ── Till A has a shop already; the owner creates the cloud shop. ──
    final milo = await InventoryService.createProduct(
      a, owner,
      const ProductInput(name: 'Milo', price: 32, category: 'Drinks', quickButtonColor: 0, costPrice: 25),
      initialQuantity: 20,
      expiryDate: DateTime.now().add(const Duration(days: 200)),
    );
    final created = await CloudService.createShop(a, url: url, email: email, password: _password);
    expect(created.error, isNull);
    expect(created.shopName, 'Jakmob Mini Mart');
    final settingsA = (await a.storeSettings.get(1))!;
    expect(settingsA.cloudDeviceToken, isNotEmpty);
    final first = await sync(a);
    expect(first.pushed, greaterThan(0));
    expect(await SyncService.pendingCount(a), 0);

    // ── Till B joins and receives products, stock and staff. ──
    final joined = await CloudService.signIn(b, url: url, email: email, password: 'wrong-password1');
    expect(joined.ok, isFalse);
    expect((await CloudService.signIn(b, url: url, email: email, password: _password)).error, isNull);
    await sync(b);
    expect(await stockOf(b, milo.uuid!), 20);
    // Shop-wide staff accounts: the owner's PIN works on till B.
    final ownerOnB = await AuthService.findUserByPin(b, '482910');
    expect(ownerOnB?.uuid, owner.uuid);

    // ── Till A sells offline; its first push "loses" the reply. ──
    final productA = (await a.products.get(milo.id))!;
    final sale = await SaleService.completeSale(a, owner,
        lines: [CheckoutLine(product: productA, quantity: 3)],
        payments: [const PaymentInput(AppConstants.paymentCash, 96)]);
    expect(await SyncService.pendingCount(a), greaterThan(0), reason: 'queued while offline');
    await sync(a);
    // Pretend the reply never arrived: everything is sent again.
    await SyncService.markAllUnsynced(a);
    final retry = await sync(a);
    expect(retry.pushed, greaterThan(0));

    await sync(b);
    expect(await stockOf(b, milo.uuid!), 17, reason: 'stock moved once, not twice');
    expect(await b.sales.filter().uuidEqualTo(sale.uuid).count(), 1, reason: 'no duplicate sale');

    // ── Till B sells too; both tills converge. ──
    final productB = (await b.products.filter().uuidEqualTo(milo.uuid).findFirst())!;
    await SaleService.completeSale(b, ownerOnB,
        lines: [CheckoutLine(product: productB, quantity: 2)],
        payments: [const PaymentInput(AppConstants.paymentCash, 64)]);
    await sync(b);
    await sync(a);
    expect(await stockOf(a, milo.uuid!), 15);
    expect(await stockOf(b, milo.uuid!), 15);
    expect(await a.sales.count(), 2);
    expect(await b.sales.count(), 2);

    // ── A disconnected till gets a clear error, and keeps its data. ──
    await a.writeTxn(() async {
      final s = (await a.storeSettings.get(1))!..cloudDeviceToken = 'revoked-or-forged';
      await a.storeSettings.put(s);
    });
    final denied = await SyncService.syncNow(a, baseUrl: '', checkConnectivity: false);
    expect(denied.unauthorized, isTrue);
    expect(await a.sales.count(), 2);
  }, skip: available ? false : 'backend not found at $backendDir', timeout: const Timeout(Duration(minutes: 3)));
}
