// ============================================
// Multi-device, printing and reconciliation tests
// ============================================

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/migrations.dart';
import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/services/backup_service.dart';
import 'package:shop_pos/core/services/sync_service.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/expenses/models/expense.dart';
import 'package:shop_pos/features/expenses/services/expense_service.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/stock_movement.dart';
import 'package:shop_pos/features/products/services/inventory_service.dart';
import 'package:shop_pos/features/reports/services/report_range.dart';
import 'package:shop_pos/features/reports/services/report_service.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/services/escpos.dart';
import 'package:shop_pos/features/sales/services/pending_momo_store.dart';
import 'package:shop_pos/features/sales/services/receipt_service.dart';
import 'package:shop_pos/features/sales/services/sale_service.dart';

/// Server stand-in: what one device pushes becomes what the other pulls.
Future<void> syncInto(Isar from, Isar to) async {
  final changes = await SyncService.collectChanges(from);
  await SyncService.applyRemote(to, {
    for (final name in pulledCollections) name: changes.collections[name] ?? const [],
  });
}

Future<int> stockOf(Isar isar, String productUuid) async {
  final p = await isar.products.filter().uuidEqualTo(productUuid).findFirst();
  final batches = await isar.batchs.filter().productIdEqualTo(p!.id).findAll();
  return batches.fold<int>(0, (s, b) => s + b.quantity);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Isar a;
  late Isar b;
  late AppUser ownerA;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(libraries: {Abi.windowsX64: 'isar.dll'});
    } catch (_) {}
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos_multi_');
    a = await Isar.open(allSchemas, directory: dir.path, name: 'deviceA');
    b = await Isar.open(allSchemas, directory: dir.path, name: 'deviceB');
    ownerA = AppUser()
      ..name = 'Owner'
      ..role = AppConstants.roleOwner
      ..uuid = 'owner-uuid'
      ..pinHash = HashHelpers.hashPin('482910');
    await a.writeTxn(() => a.appUsers.put(ownerA));
  });

  tearDown(() async {
    await a.close(deleteFromDisk: true);
    await b.close(deleteFromDisk: true);
    await dir.delete(recursive: true);
  });

  group('Multi-device sync', () {
    test('stock, sales and expenses from one till reach the other', () async {
      final milo = await InventoryService.createProduct(
        a, ownerA,
        const ProductInput(name: 'Milo', price: 32, category: 'Drinks', quickButtonColor: 0, costPrice: 25),
        initialQuantity: 20,
        expiryDate: DateTime.now().add(const Duration(days: 200)),
      );
      await syncInto(a, b);
      expect(await stockOf(b, milo.uuid!), 20);

      // Device A sells 3, refunds 1, restocks 10, records an expense.
      final productA = (await a.products.get(milo.id))!;
      final sale = await SaleService.completeSale(a, ownerA,
          lines: [CheckoutLine(product: productA, quantity: 3)],
          payments: [const PaymentInput(AppConstants.paymentCash, 96)]);
      final item = (await SaleService.itemsFor(a, sale.id)).single;
      await SaleService.refund(a, ownerA, sale: sale, quantities: {item.id: 1}, reason: 'x');
      await InventoryService.restock(a, ownerA,
          product: productA, quantity: 10, expiryDate: DateTime.now().add(const Duration(days: 90)));
      await ExpenseService.add(a, ownerA, amount: 15, category: ExpenseCategory.transport);
      await syncInto(a, b);

      expect(await stockOf(a, milo.uuid!), 28);
      expect(await stockOf(b, milo.uuid!), 28);

      // Applying the same changes again changes nothing.
      await syncInto(a, b);
      expect(await stockOf(b, milo.uuid!), 28);

      final saleB = (await b.sales.filter().uuidEqualTo(sale.uuid).findFirst())!;
      expect(saleB.status, SaleStatus.partiallyRefunded);
      expect(saleB.refundedAmount, 32);
      final reportB = await ReportSummary.load(b, ReportRange.of(ReportPeriod.today));
      expect(reportB.netSales, 64);
      expect(reportB.totalExpenses, 15);
      expect(reportB.cashiers.single.name, 'Owner');

      // The owner from A shows up on B but can't sign in with any PIN.
      final ownerOnB = (await b.appUsers.filter().uuidEqualTo('owner-uuid').findFirst())!;
      expect(HashHelpers.verifyPin('482910', ownerOnB.pinHash), isFalse);
    });

    test('both tills selling the same product end up agreeing', () async {
      final p = await InventoryService.createProduct(
        a, ownerA,
        const ProductInput(name: 'Bread', price: 10, category: '', quickButtonColor: 0),
        initialQuantity: 10,
        expiryDate: DateTime.now().add(const Duration(days: 30)),
      );
      await syncInto(a, b);
      final ownerB = (await b.appUsers.where().findFirst())!..pinHash = HashHelpers.hashPin('555555');
      await b.writeTxn(() => b.appUsers.put(ownerB));

      await SaleService.completeSale(a, ownerA,
          lines: [CheckoutLine(product: (await a.products.get(p.id))!, quantity: 2)],
          payments: [const PaymentInput(AppConstants.paymentCash, 20)]);
      final onB = (await b.products.filter().uuidEqualTo(p.uuid).findFirst())!;
      await SaleService.completeSale(b, ownerB,
          lines: [CheckoutLine(product: onB, quantity: 3)],
          payments: [const PaymentInput(AppConstants.paymentCash, 30)]);

      await syncInto(a, b);
      await syncInto(b, a);
      expect(await stockOf(a, p.uuid!), 5);
      expect(await stockOf(b, p.uuid!), 5);
      expect(await a.sales.count(), 2);
      expect(await b.sales.count(), 2);
    });

    test('restoring a backup keeps this device’s own sync identity', () async {
      await a.writeTxn(() => a.storeSettings.put(StoreSettings()
        ..deviceId = 'device-a'
        ..lastSyncAt = DateTime(2026, 9, 1)));
      await b.writeTxn(() => b.storeSettings.put(StoreSettings()..deviceId = 'device-b'));
      final bytes = await BackupService.export(a, ownerA);
      await BackupService.restore(b, ownerA, bytes);
      final settings = (await b.storeSettings.get(1))!;
      expect(settings.deviceId, 'device-b');
      expect(settings.lastSyncAt, isNull);
    });

    test('older stock gets an opening-balance movement', () async {
      final p = Product()
        ..name = 'Legacy'
        ..price = 1
        ..category = 'x';
      await a.writeTxn(() async {
        await a.products.put(p);
        await a.batchs.put(Batch()
          ..productId = p.id
          ..quantity = 7
          ..expiryDate = DateTime.now().add(const Duration(days: 9))
          ..restockDate = DateTime.now());
      });
      await DataMigrations.run(a);
      await DataMigrations.run(a); // idempotent
      final movements = await a.stockMovements.filter().productIdEqualTo(p.id).findAll();
      expect(movements.single.quantityChange, 7);
      expect(movements.single.type, StockMovementType.initial);
    });
  });

  group('ESC/POS', () {
    test('receipt bytes: text, drawer pulse and cut', () async {
      final p = await InventoryService.createProduct(
        a, ownerA,
        const ProductInput(name: 'Peak Milk', price: 12.5, category: '', quickButtonColor: 0),
        initialQuantity: 5,
      );
      final sale = await SaleService.completeSale(a, ownerA,
          lines: [CheckoutLine(product: p, quantity: 2)],
          payments: [const PaymentInput(AppConstants.paymentCash, 25)],
          amountTendered: 30);
      final store = StoreSettings()
        ..storeName = 'Kofi’s Shop'
        ..receiptFooter = 'Thanks';
      final receipt = await ReceiptData.load(a, sale, store);
      final bytes = EscPosReceipt.build(receipt, paperMm: 58, openDrawer: true);
      final text = latin1.decode(bytes, allowInvalid: true);

      expect(bytes.sublist(0, 2), [0x1B, 0x40]); // reset
      expect(text, contains("Kofi's Shop")); // curly quote made ASCII
      expect(text, contains('Peak Milk'));
      expect(text, contains('Change'));
      expect(text, contains('5.00'));
      expect(_contains(bytes, [0x1B, 0x70, 0x00, 0x19, 0xFA]), isTrue); // drawer
      expect(_contains(bytes, [0x1D, 0x56, 0x42, 0x00]), isTrue); // cut
      // Every normal-size line fits the 32 columns of 58 mm paper. The
      // first line is the double-size store name; escape codes in front of
      // a line aren't printed.
      for (final line in text.split('\n').skip(1)) {
        final printable =
            line.replaceAll(RegExp(r'\x1B[\x40-\x7F].|\x1D[\x21-\x7F].|[\x00-\x1F]'), '');
        expect(printable.length <= 32, isTrue, reason: printable);
      }
    });

    test('rows fit the paper and non-ASCII is replaced', () {
      expect(EscPosBuilder.toAscii('₵5 – ok ✓'), 'GHS5 - ok ?');
      final p = EscPosBuilder(paperMm: 58);
      expect(p.width, 32);
      expect(EscPosBuilder(paperMm: 80).width, 48);
      expect(EscPosBuilder.wrap('a very long product name indeed', 10),
          ['a very', 'long', 'product', 'name', 'indeed']);
    });
  });

  test('pending split MoMo payments keep everything needed to record them', () async {
    SharedPreferences.setMockInitialValues({});
    await PendingMomoStore.save(PendingMomoPayment(
      reference: 'shoppos_1_x',
      amountGhs: 40,
      provider: 'mtn',
      phone: '+233551234987',
      cashierId: 3,
      itemsJson: '[]',
      createdAt: DateTime(2026, 10, 2),
      otherPayments: const [
        {'method': 'cash', 'amount': 60.0, 'reference': null}
      ],
      amountTendered: 100,
      saleDiscount: 5,
      taxRate: 12.5,
      pricesIncludeTax: false,
    ));
    await PendingMomoStore.setStatus('shoppos_1_x', PendingMomoStatus.paidNotSaved);
    final p = (await PendingMomoStore.getAll()).single;
    expect(p.status, PendingMomoStatus.paidNotSaved);
    expect(p.otherPayments.single['amount'], 60.0);
    expect(p.amountTendered, 100);
    expect(p.saleDiscount, 5);
    expect(p.pricesIncludeTax, isFalse);
  });
}

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}
