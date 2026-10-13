// ============================================
// Manual MoMo Test — ShopPOS
// ============================================
// Besides MoMo through Paystack, a shop can take
// Mobile Money sent straight to its own MoMo
// number. The cashier picks "MoMo (manual)",
// the customer sends to the number shown, and
// the sale is recorded with the transaction ID
// from the customer's SMS (optional).
// ============================================

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/sales/services/sale_service.dart';
import 'package:shop_pos/features/sales/widgets/checkout_bottom_sheet.dart';

import 'support/till_harness.dart';

StoreSettings _shop({bool manual = true, String number = '0244123456'}) => StoreSettings()
  ..storeName = 'Jakmob Mini Mart'
  ..enableManualMoMo = manual
  ..momoNumber = number
  ..momoNetwork = 'mtn'
  ..momoAccountName = 'Jakmob Group';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('checkout', () {
    Widget sheet(StoreSettings settings) => tillApp(
          cart: sampleCart(),
          settings: settings,
          home: const Scaffold(
            body: Align(alignment: Alignment.bottomCenter, child: CheckoutBottomSheet()),
          ),
        );

    testWidgets('offers MoMo (manual) next to Paystack MoMo and shows where to send', (tester) async {
      await setTestSize(tester, const Size(400, 860));
      await tester.pumpWidget(sheet(_shop()));
      await tester.pumpAndSettle();

      expect(find.text('MoMo'), findsOneWidget, reason: 'Paystack MoMo stays');
      final manual = find.text('MoMo (manual)');
      expect(manual, findsOneWidget);
      await tester.ensureVisible(manual);
      await tester.tap(manual);
      await tester.pumpAndSettle();

      expect(find.text('0244123456'), findsOneWidget);
      expect(find.text('MTN MoMo · Jakmob Group'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'MoMo transaction ID (optional)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is not offered while switched off or without a number', (tester) async {
      await setTestSize(tester, const Size(400, 860));
      for (final s in [_shop(manual: false), _shop(number: '')]) {
        await tester.pumpWidget(sheet(s));
        await tester.pumpAndSettle();
        expect(find.text('MoMo (manual)'), findsNothing);
      }
    });

    testWidgets('five payment methods wrap onto two rows on a narrow phone', (tester) async {
      await setTestSize(tester, const Size(360, 780));
      await tester.pumpWidget(sheet(_shop()..enableQr = true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final cash = tester.getRect(find.text('Cash'));
      final qr = tester.getRect(find.text('QR'));
      expect(qr.top, greaterThan(cash.bottom), reason: 'QR sits on the second row');
    });
  });

  group('recording the sale', () {
    late Isar isar;
    late Directory dir;
    late AppUser cashier;
    late Product rice;

    setUpAll(() async {
      try {
        await Isar.initializeIsarCore(libraries: {Abi.windowsX64: 'isar.dll'});
      } catch (_) {}
    });

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('pos_manual_momo_');
      isar = await Isar.open(allSchemas, directory: dir.path, name: 'manual_momo');
      cashier = AppUser()
        ..name = 'Abena'
        ..role = AppConstants.roleCashier
        ..pinHash = HashHelpers.hashPin('2468');
      rice = Product()
        ..name = 'Jasmine Rice'
        ..price = 150
        ..category = 'Rice';
      await isar.writeTxn(() async {
        await isar.appUsers.put(cashier);
        await isar.products.put(rice);
        final b = Batch()
          ..productId = rice.id
          ..quantity = 10
          ..expiryDate = DateTime.now().add(const Duration(days: 200))
          ..restockDate = DateTime.now();
        await isar.batchs.put(b);
        b.product.value = rice;
        await b.product.save();
      });
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      await dir.delete(recursive: true);
    });

    test('a manual MoMo sale keeps its method and transaction ID, and no Paystack reference', () async {
      final sale = await SaleService.completeSale(isar, cashier,
          lines: [CheckoutLine(product: rice, quantity: 1)],
          payments: [const PaymentInput(AppConstants.paymentMomoManual, 150, reference: 'MP251013.1820.C41234')]);
      expect(sale.paymentType, AppConstants.paymentMomoManual);
      expect(sale.paystackReference, isNull);
      expect(sale.payments.single.method, AppConstants.paymentMomoManual);
      expect(sale.payments.single.reference, 'MP251013.1820.C41234');
      expect(AppConstants.paymentLabel(sale.paymentType), 'MoMo (manual)');
    });

    test('works without a transaction ID, and inside a split payment', () async {
      final noId = await SaleService.completeSale(isar, cashier,
          lines: [CheckoutLine(product: rice, quantity: 1)],
          payments: [const PaymentInput(AppConstants.paymentMomoManual, 150)]);
      expect(noId.payments.single.reference, isNull);

      final split = await SaleService.completeSale(isar, cashier,
          lines: [CheckoutLine(product: rice, quantity: 1)],
          payments: [
            const PaymentInput(AppConstants.paymentCash, 50),
            const PaymentInput(AppConstants.paymentMomoManual, 100, reference: 'MP99'),
          ]);
      expect(split.paymentType, AppConstants.paymentSplit);
      expect(split.payments.map((p) => p.method), [AppConstants.paymentCash, AppConstants.paymentMomoManual]);
    });
  });
}
