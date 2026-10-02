// ============================================
// Money & stock tests — ShopPOS
// ============================================
// Checkout maths, FEFO stock deduction, sales,
// refunds, voids, shifts, reports, permissions,
// stock adjustments, backups and sync merging,
// against a real (temporary) Isar database.
// ============================================

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/core/services/backup_service.dart';
import 'package:shop_pos/core/services/stock_alert_service.dart';
import 'package:shop_pos/core/services/sync_service.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/expenses/models/expense.dart';
import 'package:shop_pos/features/expenses/services/expense_service.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/stock_movement.dart';
import 'package:shop_pos/features/products/services/inventory_service.dart';
import 'package:shop_pos/features/reports/services/report_csv.dart';
import 'package:shop_pos/features/reports/services/report_range.dart';
import 'package:shop_pos/features/reports/services/report_service.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/models/sale_item.dart';
import 'package:shop_pos/features/sales/services/sale_calculator.dart';
import 'package:shop_pos/features/sales/services/sale_service.dart';
import 'package:shop_pos/features/shifts/services/shift_service.dart';

late Isar isar;
late Directory dir;
late AppUser owner;
late AppUser manager;
late AppUser cashier;
late AppUser clerk;

Future<AppUser> _user(String name, String role, String pin) async {
  final u = AppUser()
    ..name = name
    ..role = role
    ..pinHash = HashHelpers.hashPin(pin);
  await isar.writeTxn(() => isar.appUsers.put(u));
  return u;
}

/// A product with one batch per (quantity, days-to-expiry) pair.
Future<Product> _product(String name, double price,
    {double? cost, List<(int, int)> batches = const [], int reorderLevel = 0}) async {
  final p = Product()
    ..name = name
    ..price = price
    ..category = 'Test'
    ..costPrice = cost
    ..reorderLevel = reorderLevel;
  await isar.writeTxn(() async {
    await isar.products.put(p);
    for (final (qty, days) in batches) {
      final b = Batch()
        ..productId = p.id
        ..quantity = qty
        ..expiryDate = DateTime.now().add(Duration(days: days, hours: 1))
        ..restockDate = DateTime.now();
      await isar.batchs.put(b);
      b.product.value = p;
      await b.product.save();
    }
  });
  return p;
}

Future<List<int>> _batchQuantities(Product p) async => (await isar.batchs
        .filter()
        .productIdEqualTo(p.id)
        .sortByExpiryDate()
        .findAll())
    .map((b) => b.quantity)
    .toList();

Future<Sale> _cashSale(List<CheckoutLine> lines,
    {AppUser? by, TaxConfig tax = const TaxConfig(), double saleDiscount = 0}) {
  final total = SaleService.totalsFor(lines, tax: tax, saleDiscount: saleDiscount).total;
  return SaleService.completeSale(isar, by ?? cashier,
      lines: lines,
      payments: [PaymentInput(AppConstants.paymentCash, total)],
      tax: tax,
      saleDiscount: saleDiscount);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(libraries: {Abi.windowsX64: 'isar.dll'});
    } catch (_) {}
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos_sales_test_');
    isar = await Isar.open(allSchemas, directory: dir.path, name: 'test');
    owner = await _user('Owner', AppConstants.roleOwner, '482910');
    manager = await _user('Mia', AppConstants.roleManager, '5555');
    cashier = await _user('Kofi', AppConstants.roleCashier, '7777');
    clerk = await _user('Ama', AppConstants.roleStockClerk, '8888');
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    await dir.delete(recursive: true);
  });

  group('SaleCalculator', () {
    test('VAT included in prices is extracted, total unchanged', () {
      final t = SaleCalculator.calculate(
          [const CalcLine(unitPrice: 10, quantity: 3)],
          taxRate: 15, pricesIncludeTax: true);
      expect(t.total, 30);
      expect(t.taxAmount, 3.91); // 30 × 15/115
    });

    test('VAT added on top', () {
      final t = SaleCalculator.calculate(
          [const CalcLine(unitPrice: 10, quantity: 3)],
          taxRate: 15, pricesIncludeTax: false);
      expect(t.taxAmount, 4.5);
      expect(t.total, 34.5);
    });

    test('line and sale discounts are clamped and shared across lines', () {
      final t = SaleCalculator.calculate([
        const CalcLine(unitPrice: 10, quantity: 1, discount: 50), // clamped to 10
        const CalcLine(unitPrice: 3.33, quantity: 3),
      ], saleDiscount: 1);
      expect(t.lineDiscounts, 10);
      expect(t.subtotal, 9.99);
      expect(t.total, 8.99);
      expect(t.lineTotals.reduce((a, b) => a + b), closeTo(t.total, 1e-9));
    });

    test('change due', () {
      expect(SaleCalculator.changeDue(tendered: 50, cashDue: 34.5), 15.5);
      expect(SaleCalculator.changeDue(tendered: 20, cashDue: 34.5), -14.5);
    });
  });

  group('Stock', () {
    test('sellable quantity spans every unexpired batch (no one-batch cap)', () async {
      final p = await _product('Milk', 5, batches: [(2, 3), (10, 60), (4, -2)]);
      expect(await InventoryService.sellableQuantity(isar, p.id), 12);
    });

    test('a sale takes stock soonest-expiry first across batches', () async {
      final p = await _product('Milk', 5, batches: [(2, 3), (10, 60)]);
      final sale = await _cashSale([CheckoutLine(product: p, quantity: 5)]);
      expect(await _batchQuantities(p), [0, 7]);

      final movements =
          await isar.stockMovements.filter().saleIdEqualTo(sale.id).findAll();
      expect(movements.map((m) => m.quantityChange).toList()..sort(), [-3, -2]);
      expect(movements.every((m) => m.type == StockMovementType.sale), isTrue);
    });

    test('expired batches are never sold', () async {
      final p = await _product('Yogurt', 4, batches: [(5, -1), (1, 10)]);
      await expectLater(
        _cashSale([CheckoutLine(product: p, quantity: 2)]),
        throwsA(isA<InsufficientStockException>()),
      );
    });

    test('a failed sale writes nothing', () async {
      final a = await _product('A', 1, batches: [(5, 30)]);
      final b = await _product('B', 1, batches: [(1, 30)]);
      await expectLater(
        _cashSale([
          CheckoutLine(product: a, quantity: 2),
          CheckoutLine(product: b, quantity: 3),
        ]),
        throwsA(isA<InsufficientStockException>()),
      );
      expect(await isar.sales.count(), 0);
      expect(await _batchQuantities(a), [5]);
    });

    test('adjustments, stock counts and expired write-offs are recorded', () async {
      final p = await _product('Bread', 8, batches: [(4, -1), (10, 5)]);
      await InventoryService.adjust(isar, clerk,
          product: p, quantityChange: -3, reason: AdjustmentReason.damage);
      expect(await _batchQuantities(p), [1, 10]); // expired batch first

      final expired = (await isar.batchs.filter().productIdEqualTo(p.id).sortByExpiryDate().findFirst())!;
      await InventoryService.writeOffBatch(isar, clerk, product: p, batch: expired);
      expect(await _batchQuantities(p), [0, 10]);

      final diff = await InventoryService.setCountedStock(isar, manager,
          product: p, countedQuantity: 12);
      expect(diff, 2);
      expect((await _batchQuantities(p)).reduce((a, b) => a + b), 12);

      final reasons = (await InventoryService.movementsFor(isar, p.id)).map((m) => m.reason).toSet();
      expect(reasons, containsAll([AdjustmentReason.damage, AdjustmentReason.expired, AdjustmentReason.countCorrection]));
    });

    test('restock records cost and a movement', () async {
      final p = await _product('Rice', 140);
      await InventoryService.restock(isar, clerk,
          product: p, quantity: 20, expiryDate: DateTime.now().add(const Duration(days: 300)), unitCost: 110);
      expect(await _batchQuantities(p), [20]);
      expect((await isar.products.get(p.id))!.costPrice, 110);
      expect((await InventoryService.movementsFor(isar, p.id)).single.type, StockMovementType.restock);
    });

    test('low-stock and expiry alerts', () async {
      final low = await _product('Sugar', 10, reorderLevel: 5, batches: [(3, 100)]);
      await _product('Salt', 10, reorderLevel: 5, batches: [(30, 100)]);
      final soon = await _product('Fish', 10, batches: [(3, 2)]);
      final alerts = await StockAlertService.check(isar);
      expect(alerts.lowStock.map((p) => p.id), [low.id]);
      expect(alerts.expiringSoon.map((p) => p.id), [soon.id]);
    });

    test('archived products cannot be restocked into the till list', () async {
      final p = await _product('Old', 1, batches: [(1, 30)]);
      await InventoryService.setArchived(isar, owner, p, true);
      expect((await isar.products.get(p.id))!.isArchived, isTrue);
      expect(InventoryService.lowStock([p]), isEmpty);
    });
  });

  group('Sales', () {
    test('records lines, tax, discount, payments and change', () async {
      final p = await _product('Oil', 50, cost: 40, batches: [(10, 90)]);
      final lines = [CheckoutLine(product: p, quantity: 2, discount: 5)];
      const tax = TaxConfig(rate: 12.5, pricesIncludeTax: false);
      final total = SaleService.totalsFor(lines, tax: tax).total; // (100-5)*1.125
      expect(total, 106.88);
      final sale = await SaleService.completeSale(isar, manager,
          lines: lines,
          payments: [
            const PaymentInput(AppConstants.paymentCash, 60),
            PaymentInput(AppConstants.paymentCard, roundMoney(total - 60), reference: 'slip-1'),
          ],
          tax: tax,
          amountTendered: 100);
      expect(sale.paymentType, AppConstants.paymentSplit);
      expect(sale.changeDue, 40);
      expect(sale.taxAmount, 11.88);
      expect(sale.discountAmount, 5);
      final items = await SaleService.itemsFor(isar, sale.id);
      expect(items.single.unitCost, 40);
      expect(items.single.lineTotal, total);
    });

    test('payments must add up to the total', () async {
      final p = await _product('Oil', 50, batches: [(10, 90)]);
      await expectLater(
        SaleService.completeSale(isar, cashier,
            lines: [CheckoutLine(product: p, quantity: 1)],
            payments: [const PaymentInput(AppConstants.paymentCash, 40)]),
        throwsA(isA<SaleValidationException>()),
      );
    });

    test('cashiers cannot give discounts; managers can', () async {
      final p = await _product('Oil', 50, batches: [(10, 90)]);
      final lines = [CheckoutLine(product: p, quantity: 1, discount: 5)];
      await expectLater(
        SaleService.completeSale(isar, cashier,
            lines: lines, payments: [const PaymentInput(AppConstants.paymentCash, 45)]),
        throwsA(isA<PermissionDeniedException>()),
      );
      await SaleService.completeSale(isar, manager,
          lines: lines, payments: [const PaymentInput(AppConstants.paymentCash, 45)]);
    });

    test('a signed-out user cannot sell', () async {
      final p = await _product('Oil', 50, batches: [(10, 90)]);
      await expectLater(
        SaleService.completeSale(isar, null,
            lines: [CheckoutLine(product: p, quantity: 1)],
            payments: [const PaymentInput(AppConstants.paymentCash, 50)]),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('saving a MoMo payment twice records one sale', () async {
      final p = await _product('Oil', 50, batches: [(10, 90)]);
      Future<Sale> save() => SaleService.completeSale(isar, null,
          lines: [CheckoutLine(product: p, quantity: 1)],
          payments: [const PaymentInput(AppConstants.paymentMomo, 50, reference: 'shoppos_1_x')],
          paystackReference: 'shoppos_1_x',
          cashierId: cashier.id);
      final first = await save();
      final second = await save();
      expect(second.id, first.id);
      expect(await isar.sales.count(), 1);
      expect(await _batchQuantities(p), [9]);
      expect(first.cashierId, cashier.id);
    });
  });

  group('Refunds and voids', () {
    test('partial then full refund returns exact money and stock', () async {
      final p = await _product('Soap', 3.33, batches: [(1, 10), (10, 90)]);
      final sale = await _cashSale([CheckoutLine(product: p, quantity: 3)]);
      expect(await _batchQuantities(p), [0, 8]);
      final item = (await SaleService.itemsFor(isar, sale.id)).single;

      final first = await SaleService.refund(isar, manager,
          sale: sale, quantities: {item.id: 1}, reason: 'Damaged');
      expect(first, 3.33);
      expect(sale.status, SaleStatus.partiallyRefunded);

      final rest = await SaleService.refund(isar, manager,
          sale: sale, quantities: {item.id: 2}, reason: 'Changed mind');
      expect(roundMoney(first + rest), sale.totalAmount);
      expect(sale.status, SaleStatus.refunded);
      expect(sale.netAmount, 0);
      // Back into the batches they came from.
      expect(await _batchQuantities(p), [1, 10]);

      await expectLater(
        SaleService.refund(isar, manager, sale: sale, quantities: {item.id: 1}, reason: 'x'),
        throwsA(isA<SaleValidationException>()),
      );
    });

    test('refund without restocking leaves stock alone', () async {
      final p = await _product('Egg', 2, batches: [(10, 30)]);
      final sale = await _cashSale([CheckoutLine(product: p, quantity: 2)]);
      final item = (await SaleService.itemsFor(isar, sale.id)).single;
      await SaleService.refund(isar, owner,
          sale: sale, quantities: {item.id: 1}, reason: 'Broken', returnToStock: false);
      expect(await _batchQuantities(p), [8]);
    });

    test('void restores stock; cashiers cannot void', () async {
      final p = await _product('Tea', 6, batches: [(5, 30)]);
      final sale = await _cashSale([CheckoutLine(product: p, quantity: 4)]);
      await expectLater(
        SaleService.voidSale(isar, cashier, sale: sale, reason: 'oops'),
        throwsA(isA<PermissionDeniedException>()),
      );
      await SaleService.voidSale(isar, manager, sale: sale, reason: 'Wrong item');
      expect(sale.status, SaleStatus.voided);
      expect(await _batchQuantities(p), [5]);
      await expectLater(
        SaleService.voidSale(isar, manager, sale: sale, reason: 'again'),
        throwsA(isA<SaleValidationException>()),
      );
    });
  });

  group('Shifts', () {
    test('expected cash = float + cash sales − cash refunds − till payouts', () async {
      final p = await _product('Pen', 10, batches: [(50, 300)]);
      final shift = await ShiftService.openShift(isar, cashier, openingFloat: 100);
      await expectLater(ShiftService.openShift(isar, cashier, openingFloat: 5),
          throwsA(isA<ShiftStateException>()));

      final cashSale = await _cashSale([CheckoutLine(product: p, quantity: 3)]); // 30 cash
      await SaleService.completeSale(isar, cashier,
          lines: [CheckoutLine(product: p, quantity: 2)],
          payments: [const PaymentInput(AppConstants.paymentCard, 20)]); // not cash
      expect(cashSale.shiftId, shift.id);

      // Manager refunds 10 in cash while the cashier's shift is open: only
      // refunds made in this shift count, so give the manager none.
      final item = (await SaleService.itemsFor(isar, cashSale.id)).single;
      final mShift = await ShiftService.openShift(isar, manager, openingFloat: 0);
      await SaleService.refund(isar, manager, sale: cashSale, quantities: {item.id: 1}, reason: 'x');
      await ExpenseService.add(isar, manager,
          amount: 7, category: ExpenseCategory.transport, paidFromTill: true);

      final s = await ShiftService.summarize(isar, shift);
      expect(s.cashSales, 30);
      expect(s.expectedCash, 130);

      final m = await ShiftService.summarize(isar, mShift);
      expect(m.cashRefunds, 10);
      expect(m.tillPayouts, 7);
      expect(m.expectedCash, -17);

      final closed = await ShiftService.closeShift(isar, cashier, shift: shift, countedCash: 125);
      expect(closed.variance, -5);
      expect(await ShiftService.currentShift(isar, cashier.id), isNull);
    });
  });

  group('Reports', () {
    test('net sales, VAT, cost of goods, profit and voids', () async {
      final a = await _product('A', 115, cost: 60, batches: [(10, 90)]);
      final b = await _product('B', 20, batches: [(10, 90)]); // no cost
      const tax = TaxConfig(rate: 15, pricesIncludeTax: true);
      await _cashSale([CheckoutLine(product: a, quantity: 2)], tax: tax); // 230, VAT 30
      final voided = await _cashSale([CheckoutLine(product: b, quantity: 1)], tax: tax);
      await SaleService.voidSale(isar, owner, sale: voided, reason: 'test');
      await ExpenseService.add(isar, owner, amount: 50, category: ExpenseCategory.rent);

      final r = await ReportSummary.load(isar, ReportRange.of(ReportPeriod.today));
      expect(r.saleCount, 1);
      expect(r.voidCount, 1);
      expect(r.netSales, 230);
      expect(r.tax, 30);
      expect(r.costOfGoods, 120);
      expect(r.grossProfit, 80);
      expect(r.netProfit, 30);
      expect(r.byPaymentMethod[AppConstants.paymentCash], 230);
      expect(r.products.single.profit, 110); // revenue incl. VAT − cost
      expect(r.cashiers.single.name, 'Kofi');

      final csv = ReportCsv.build(r, storeName: 'Test, Shop');
      expect(csv, contains('"Test, Shop"'));
      expect(csv, contains('Net profit,30.00'));
    });

    test('report ranges', () {
      final wed = DateTime(2026, 10, 7, 15); // a Wednesday
      final week = ReportRange.of(ReportPeriod.thisWeek, now: wed);
      expect(week.start, DateTime(2026, 10, 5));
      expect(week.end, DateTime(2026, 10, 8));
      final lastMonth = ReportRange.of(ReportPeriod.lastMonth, now: wed);
      expect(lastMonth.start, DateTime(2026, 9, 1));
      expect(lastMonth.end, DateTime(2026, 10, 1));
      final custom = ReportRange.custom(DateTime(2026, 9, 20), DateTime(2026, 9, 10));
      expect(custom.start, DateTime(2026, 9, 10));
      expect(custom.lastDay, DateTime(2026, 9, 20));
    });
  });

  group('Permissions', () {
    test('role matrix', () {
      expect(Permissions.can(cashier, Permission.sell), isTrue);
      expect(Permissions.can(cashier, Permission.restock), isFalse);
      expect(Permissions.can(clerk, Permission.sell), isFalse);
      expect(Permissions.can(clerk, Permission.adjustStock), isTrue);
      expect(Permissions.can(manager, Permission.viewReports), isTrue);
      expect(Permissions.can(manager, Permission.manageStaff), isFalse);
      expect(Permissions.can(owner, Permission.manageSettings), isTrue);
      expect(Permissions.can(null, Permission.sell), isFalse);
      owner.isActive = false;
      expect(Permissions.can(owner, Permission.sell), isFalse);
    });

    test('services enforce it, not just the UI', () async {
      final p = await _product('X', 1, batches: [(5, 30)]);
      await expectLater(
        InventoryService.restock(isar, cashier,
            product: p, quantity: 1, expiryDate: DateTime.now().add(const Duration(days: 9))),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        InventoryService.createProduct(isar, clerk,
            const ProductInput(name: 'Y', price: 1, category: '', quickButtonColor: 0)),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        ExpenseService.add(isar, cashier, amount: 5, category: ExpenseCategory.other),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('duplicate barcodes are rejected', () async {
      const input = ProductInput(
          name: 'Milo', price: 32, category: '', quickButtonColor: 0, barcode: '501234');
      await InventoryService.createProduct(isar, owner, input);
      await expectLater(InventoryService.createProduct(isar, owner, input), throwsArgumentError);
    });
  });

  group('Backup and sync', () {
    test('backup round-trips into an empty database', () async {
      final p = await _product('Milo', 32, batches: [(7, 90)]);
      await _cashSale([CheckoutLine(product: p, quantity: 2)]);
      final bytes = await BackupService.export(isar, owner);
      expect(BackupService.inspect(bytes)['sales'], 1);
      await expectLater(BackupService.export(isar, manager),
          throwsA(isA<PermissionDeniedException>()));

      await BackupService.restore(isar, owner, bytes);
      final products = await isar.products.where().findAll();
      expect(products.single.name, 'Milo');
      await products.single.batches.load();
      expect(products.single.totalStock, 5); // batch link restored
      expect(await isar.saleItems.count(), 1);
      expect((await isar.sales.where().findFirst())!.payments.single.amount, 64);
    });

    test('a non-backup file is rejected', () {
      expect(() => BackupService.inspect(Uint8ListHelper.of('{"x":1}')),
          throwsA(isA<BackupFormatException>()));
    });

    test('remote catalog edits apply only when newer', () async {
      final p = await _product('Milo', 32);
      p
        ..uuid = 'p-1'
        ..updatedAt = DateTime.utc(2026, 10, 2);
      await isar.writeTxn(() => isar.products.put(p));

      final changed = await SyncService.applyRemoteProducts(isar, [
        {'uuid': 'p-1', 'name': 'Old Milo', 'price': 1, 'updatedAt': '2026-10-01T00:00:00Z'},
        {'uuid': 'p-2', 'name': 'Peak Milk', 'price': 12.5, 'updatedAt': '2026-10-02T00:00:00Z'},
      ]);
      expect(changed, 1);
      expect((await isar.products.get(p.id))!.name, 'Milo');
      final peak = await isar.products.filter().uuidEqualTo('p-2').findFirst();
      expect(peak!.price, 12.5);

      await SyncService.applyRemoteProducts(isar, [
        {'uuid': 'p-1', 'name': 'New Milo', 'price': 35, 'updatedAt': '2026-10-03T00:00:00Z'},
      ]);
      expect((await isar.products.get(p.id))!.price, 35);
    });
  });

  test('sale lines keep refunded amounts consistent', () {
    final item = SaleItem()
      ..quantity = 4
      ..lineTotal = 10
      ..refundedQty = 1;
    expect(item.netQuantity, 3);
    expect(item.netLineTotal, 7.5);
  });
}

class Uint8ListHelper {
  static Uint8List of(String s) => Uint8List.fromList(s.codeUnits);
}
