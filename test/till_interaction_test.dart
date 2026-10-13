// ============================================
// Till Interaction Test — ShopPOS
// ============================================
// Behaviour of the redesigned till, checkout
// and shared UI: adding items, scanner search,
// category chips, the cart stepper, discounts,
// toasts above modals, inline checkout errors,
// sign-out confirmation and sold-out contrast.
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';
import 'package:shop_pos/features/sales/screens/cashier_sales_screen.dart';
import 'package:shop_pos/features/sales/widgets/cart_panel.dart';
import 'package:shop_pos/features/sales/widgets/checkout_bottom_sheet.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';
import 'package:shop_pos/features/shared/widgets/sign_out_button.dart';

import 'support/till_harness.dart';

const _phone = Size(400, 860);
const _tablet = Size(1180, 820);

List<CartItem> _cartOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
        .read(cartProvider);

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('Till', () {
    testWidgets('tapping a product adds it and the floating cart counts it', (tester) async {
      await setTestSize(tester, _phone);
      final h = TillHandles();
      await tester.pumpWidget(tillApp(handles: h));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Cart is empty'), findsOneWidget);

      await tester.tap(find.text('Fan Ice Vanilla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fan Ice Vanilla'));
      await tester.pumpAndSettle();

      expect(h.cart!.added, ['Fan Ice Vanilla', 'Fan Ice Vanilla']);
      expect(find.bySemanticsLabel(RegExp(r'^Cart, 2 items')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Fan Ice Vanilla.*2 in cart')), findsOneWidget);
    });

    testWidgets('Enter with a scanned barcode adds the product and clears search',
        (tester) async {
      await setTestSize(tester, _phone);
      final h = TillHandles();
      await tester.pumpWidget(tillApp(handles: h));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '5449000000996');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(h.cart!.added, ['Coca-Cola 500ml']);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('search filters after a short pause', (tester) async {
      await setTestSize(tester, _phone);
      await tester.pumpWidget(tillApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'milo');
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Sunlight Soap'), findsOneWidget, reason: 'still debouncing');

      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Milo Tin 400g'), findsOneWidget);
      expect(find.text('Sunlight Soap'), findsNothing);
    });

    testWidgets('category chips filter the grid and toggle off', (tester) async {
      await setTestSize(tester, _tablet);
      await tester.pumpWidget(tillApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dairy'));
      await tester.pumpAndSettle();
      expect(find.text('Peak Milk Powder'), findsOneWidget);
      expect(find.text('Ideal Milk'), findsOneWidget);
      expect(find.text('Sunlight Soap'), findsNothing);

      await tester.tap(find.text('Dairy'));
      await tester.pumpAndSettle();
      expect(find.text('Sunlight Soap'), findsOneWidget);
    });

    testWidgets('sold-out cards dim the picture only, not the text', (tester) async {
      await setTestSize(tester, _tablet);
      await tester.pumpWidget(tillApp());
      await tester.pumpAndSettle();

      // Test products have no batches, so every card is sold out.
      final dimmedAboveName = find
          .ancestor(of: find.text('Fan Ice Vanilla'), matching: find.byType(Opacity))
          .evaluate()
          .map((e) => (e.widget as Opacity).opacity)
          .where((o) => o < 1);
      expect(dimmedAboveName, isEmpty);
      expect(find.text('Sold out'), findsWidgets);
    });
  });

  group('Cart lines', () {
    testWidgets('minus at quantity 1 is a remove button', (tester) async {
      await setTestSize(tester, _tablet);
      await tester.pumpWidget(tillApp(cart: sampleCart()));
      await tester.pumpAndSettle();

      // Milo is the quantity-1 line.
      expect(find.byTooltip('Remove item'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove item'));
      await tester.pumpAndSettle();

      expect(_cartOf(tester).map((i) => i.product.name),
          ['Coca-Cola 500ml', 'Voltic Water 1.5L']);
    });

    testWidgets('tapping a line opens the discount dialog and applies it', (tester) async {
      await setTestSize(tester, _tablet);
      await tester.pumpWidget(tillApp(cart: sampleCart()));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
          of: find.byType(CartPanel), matching: find.text('Voltic Water 1.5L')));
      await tester.pumpAndSettle();
      expect(find.text('Discount on Voltic Water 1.5L'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '5');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull); // controller disposed cleanly
      expect(_cartOf(tester).last.discount, 5);
    });

    testWidgets('dialog action buttons sit side by side', (tester) async {
      await setTestSize(tester, _tablet);
      await tester.pumpWidget(tillApp(cart: sampleCart()));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(CartPanel), matching: find.text('Voltic Water 1.5L')));
      await tester.pumpAndSettle();

      final remove = tester.getCenter(find.text('Remove discount'));
      final apply = tester.getCenter(find.text('Apply'));
      expect((remove.dy - apply.dy).abs(), lessThan(4), reason: 'same row');
    });
  });

  group('Feedback', () {
    testWidgets('toasts show above an open dialog', (tester) async {
      await setTestSize(tester, _phone);
      await tester.pumpWidget(tillApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showAppDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    content: TextButton(
                      onPressed: () => dialogContext.showErrorSnackbar('Only 3 in stock.'),
                      child: const Text('Fail'),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fail'));
      await tester.pumpAndSettle();

      expect(find.text('Only 3 in stock.').hitTestable(), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Only 3 in stock.'), findsNothing);
    });

    testWidgets('checkout shows payment errors inline, above Pay', (tester) async {
      await setTestSize(tester, _phone);
      await tester.pumpWidget(tillApp(
        cart: sampleCart(),
        home: const Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: CheckoutBottomSheet()),
        ),
      ));
      await tester.pumpAndSettle();

      final cash = find.widgetWithText(TextFormField, 'Cash received (optional)');
      await tester.ensureVisible(cash);
      await tester.enterText(cash, '1');
      await tester.tap(find.textContaining('Complete sale'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Cash received is less than'), findsOneWidget);
      expect(_cartOf(tester), hasLength(3), reason: 'nothing was sold');
    });
  });

  group('Sign out', () {
    Widget host() => Scaffold(
          body: Center(
            child: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => confirmAndSignOut(context, ref),
                child: const Text('Leave'),
              ),
            ),
          ),
        );

    testWidgets('asks first when the cart has items', (tester) async {
      final h = TillHandles();
      await tester.pumpWidget(tillApp(cart: sampleCart(), home: host(), handles: h));

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out now?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.auth!.logouts, 0);

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(h.auth!.logouts, 1);
    });

    testWidgets('signs out straight away with an empty cart', (tester) async {
      final h = TillHandles();
      await tester.pumpWidget(tillApp(home: host(), handles: h));

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out now?'), findsNothing);
      expect(h.auth!.logouts, 1);
    });
  });

  testWidgets('till screen renders without the database', (tester) async {
    // Guards the harness itself: if this fails, the tests above are moot.
    await tester.pumpWidget(tillApp());
    await tester.pumpAndSettle();
    expect(find.byType(CashierSalesScreen), findsOneWidget);
  });
}
