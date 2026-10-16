// ============================================
// Manual MoMo Test — ShopPOS
// ============================================
// Besides MoMo through Paystack, a shop can take
// Mobile Money sent straight to its own MoMo
// number. The cashier picks "MoMo (manual)",
// the customer sends to the number shown, the
// cashier checks the money arrived, enters the
// amount and ticks a confirmation. The sale
// records who checked it and when: never as a
// Paystack (gateway) verification.
// ============================================

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shop_pos/features/sales/services/payment_proof.dart';
import 'package:shop_pos/features/sales/screens/momo_payment_screen.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/core/services/sync_service.dart';
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

    const checked = "I've checked this MoMo payment on the shop phone";
    final received = find.widgetWithText(TextFormField, 'Amount received');

    Future<FakeCart> manualSelected(WidgetTester tester) async {
      await setTestSize(tester, const Size(400, 900));
      final h = TillHandles();
      await tester.pumpWidget(tillApp(
        cart: sampleCart(),
        settings: _shop(),
        handles: h,
        home: const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: CheckoutBottomSheet())),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('MoMo (manual)'));
      await tester.tap(find.text('MoMo (manual)'));
      await tester.pumpAndSettle();
      return h.cart!;
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    Future<void> complete(WidgetTester tester) async {
      final pay = find.textContaining('Complete sale');
      await tester.ensureVisible(pay);
      await tester.tap(pay);
      await tester.pumpAndSettle();
    }

    double saleTotal(WidgetTester tester) {
      final label = tester.widget<Text>(find.textContaining('Complete sale')).data!;
      return double.parse(label.split(RegExp(r'\s+')).last.replaceAll(RegExp(r'[^0-9.]'), ''));
    }

    testWidgets('manual MoMo asks for the amount received and a confirmation, never Paystack', (tester) async {
      final cart = await manualSelected(tester);
      expect(received, findsOneWidget);
      expect(find.text(checked), findsOneWidget);
      final due = saleTotal(tester);

      await complete(tester);
      expect(find.text('Enter the amount you received on the shop phone.'), findsOneWidget);

      await tester.enterText(received, (due - 1).toStringAsFixed(2));
      await complete(tester);
      expect(find.textContaining('Ask for the rest, or use Split'), findsOneWidget);

      await tester.enterText(received, (due + 5).toStringAsFixed(2));
      await complete(tester);
      expect(find.textContaining("MoMo can't give change"), findsOneWidget);

      await tester.enterText(received, due.toStringAsFixed(2));
      await complete(tester);
      expect(find.text('Check the payment on the shop phone, then tick the box.'), findsOneWidget);
      expect(cart.completed, isEmpty, reason: 'nothing submitted until every check passes');

      await tapText(tester, checked);
      await complete(tester);
      expect(cart.completed, hasLength(1));
      final p = cart.completed.single.single;
      expect(p.method, AppConstants.paymentMomoManual);
      expect(p.amount, due);
      expect(p.confirmedReceived, isTrue);
      expect(find.byType(MomoPaymentScreen), findsNothing, reason: 'manual MoMo never starts a Paystack charge');
    });

    testWidgets('changing the payment method clears the confirmation and amount', (tester) async {
      await manualSelected(tester);
      await tester.enterText(received, '10');
      await tapText(tester, checked);
      await tapText(tester, 'Cash');
      await tapText(tester, 'MoMo (manual)');
      expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isFalse);
      expect(tester.widget<TextFormField>(received).controller!.text, isEmpty);
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
        ..uuid = '33333333-3333-4333-8333-333333333333'
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

    Future<int> stock() async => (await isar.batchs.where().findAll()).fold<int>(0, (t, b) => t + b.quantity);
    Future<int> sales() => isar.sales.count();

    test('a confirmed manual MoMo sale records who checked it and when, and is never gateway-verified', () async {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final sale = await SaleService.completeSale(isar, cashier,
          lines: [CheckoutLine(product: rice, quantity: 1)],
          payments: [
            const PaymentInput(AppConstants.paymentMomoManual, 150,
                reference: 'MP251013.1820.C41234', confirmedReceived: true),
          ]);
      final p = sale.payments.single;
      expect(sale.paymentType, AppConstants.paymentMomoManual);
      expect(p.amount, 150);
      expect(p.reference, 'MP251013.1820.C41234');
      expect(p.confirmedBy, cashier.uuid);
      expect(p.confirmedByName, 'Abena');
      expect(p.confirmedAt!.isAfter(before), isTrue);
      expect(sale.paystackReference, isNull, reason: 'never treated as a Paystack payment');
      expect(paymentProof(sale, p), startsWith('Checked manually by Abena'));
      expect(paymentProof(sale, p), isNot(contains('Paystack')));
      expect(AppConstants.paymentLabel(sale.paymentType), 'MoMo (manual)');
      expect(await stock(), 9, reason: 'stock goes down once, when the sale completes');
    });

    test('an unconfirmed manual MoMo payment is refused and changes nothing', () async {
      await expectLater(
        SaleService.completeSale(isar, cashier,
            lines: [CheckoutLine(product: rice, quantity: 1)],
            payments: [const PaymentInput(AppConstants.paymentMomoManual, 150)]),
        throwsA(isA<SaleValidationException>()),
      );
      expect(await sales(), 0);
      expect(await stock(), 10);
    });

    test('the amount must match the total: short or over is refused, nothing saved', () async {
      for (final amount in [100.0, 200.0]) {
        await expectLater(
          SaleService.completeSale(isar, cashier,
              lines: [CheckoutLine(product: rice, quantity: 1)],
              payments: [PaymentInput(AppConstants.paymentMomoManual, amount, confirmedReceived: true)]),
          throwsA(isA<SaleValidationException>()),
          reason: '$amount for a 150 sale',
        );
      }
      expect(await sales(), 0);
      expect(await stock(), 10);
    });

    test('works without a transaction ID, and as part of a split with cash', () async {
      final noId = await SaleService.completeSale(isar, cashier,
          lines: [CheckoutLine(product: rice, quantity: 1)],
          payments: [const PaymentInput(AppConstants.paymentMomoManual, 150, confirmedReceived: true)]);
      expect(noId.payments.single.reference, isNull);

      final split = await SaleService.completeSale(isar, cashier,
          lines: [CheckoutLine(product: rice, quantity: 1)],
          payments: [
            const PaymentInput(AppConstants.paymentCash, 50),
            const PaymentInput(AppConstants.paymentMomoManual, 100, reference: 'MP99', confirmedReceived: true),
          ]);
      expect(split.paymentType, AppConstants.paymentSplit);
      expect(split.payments.map((p) => p.method), [AppConstants.paymentCash, AppConstants.paymentMomoManual]);
      expect(split.payments.first.confirmedAt, isNull, reason: 'only the MoMo part is a manual check');
      expect(split.payments.last.confirmedAt, isNotNull);
      expect(await stock(), 8);
    });

    test('a Paystack MoMo sale keeps its reference, shows as verified by Paystack, and is never recorded twice', () async {
      // Saved only after the payment server verified it (MomoPaymentScreen).
      final sale = await SaleService.completeSale(isar, cashier,
          lines: [CheckoutLine(product: rice, quantity: 1)],
          payments: [const PaymentInput(AppConstants.paymentMomo, 150, reference: 'shoppos_1_abc')],
          paystackReference: 'shoppos_1_abc');
      final p = sale.payments.single;
      expect(sale.paymentType, AppConstants.paymentMomo);
      expect(p.confirmedAt, isNull, reason: 'a gateway payment is not a manual check');
      expect(paymentProof(sale, p), 'Verified by Paystack · shoppos_1_abc');

      final again = await SaleService.completeSale(isar, cashier,
          lines: [CheckoutLine(product: rice, quantity: 1)],
          payments: [const PaymentInput(AppConstants.paymentMomo, 150, reference: 'shoppos_1_abc')],
          paystackReference: 'shoppos_1_abc');
      expect(again.id, sale.id);
      expect(await sales(), 1);
      expect(await stock(), 9);
    });

    test('the confirmation reaches the other till with the sale', () async {
      final other = await Isar.open(allSchemas, directory: dir.path, name: 'manual_momo_other');
      try {
        await SaleService.completeSale(isar, cashier,
            lines: [CheckoutLine(product: rice, quantity: 1)],
            payments: [const PaymentInput(AppConstants.paymentMomoManual, 150, confirmedReceived: true)]);
        final changes = await SyncService.collectChanges(isar);
        await SyncService.applyRemote(other, {
          for (final name in pulledCollections) name: changes.collections[name] ?? const [],
        });
        final pulled = (await other.sales.where().findFirst())!;
        final p = pulled.payments.single;
        expect(p.method, AppConstants.paymentMomoManual);
        expect(p.confirmedBy, cashier.uuid);
        expect(p.confirmedByName, 'Abena');
        expect(p.confirmedAt, isNotNull);
      } finally {
        await other.close(deleteFromDisk: true);
      }
    });
  });
}
