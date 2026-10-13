// ============================================
// Till Layout Test — ShopPOS
// ============================================
// Renders the till, checkout and sign-in at
// phone, tablet and desktop widths and checks
// they lay out without overflow: cart panel on
// wide screens, floating cart on phones.
//
// Screenshots: flutter test test/till_layout_test.dart
//   --update-goldens --dart-define=TILL_PREVIEW=true
// writes PNGs to test/goldens/ (real Inter + icons).
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shop_pos/features/auth/screens/role_select_screen.dart';
import 'package:shop_pos/features/sales/widgets/cart_panel.dart';
import 'package:shop_pos/features/sales/widgets/checkout_bottom_sheet.dart';
import 'package:shop_pos/features/sales/widgets/floating_cart_button.dart';

import 'support/till_harness.dart';

const _preview = bool.fromEnvironment('TILL_PREVIEW');

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    if (_preview) await loadPreviewFonts();
  });

  for (final (name, size, split) in [
    ('phone', const Size(400, 860), false),
    ('tablet', const Size(1180, 820), true),
    ('desktop', const Size(1440, 900), true),
  ]) {
    testWidgets('till lays out on $name', (tester) async {
      await setTestSize(tester, size);
      await tester.pumpWidget(tillApp(cart: sampleCart()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Coca-Cola 500ml'), findsWidgets);
      expect(find.byType(CartPanel), split ? findsOneWidget : findsNothing);
      // Phones get the floating cart instead, showing the live item count.
      expect(find.byType(FloatingCartButton), split ? findsNothing : findsOneWidget);
      if (!split) {
        expect(find.bySemanticsLabel(RegExp(r'^Cart, 9 items')), findsOneWidget);
      }
      // The quantity badge on a product already in the cart.
      expect(find.bySemanticsLabel(RegExp(r'Voltic Water.*6 in cart')), findsOneWidget);

      if (_preview) {
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/till_$name.png'));
      }
    });
  }

  for (final (name, size) in [
    ('phone', const Size(400, 860)),
    ('desktop', const Size(1440, 900)),
  ]) {
    testWidgets('sign-in screen lays out on $name', (tester) async {
      await setTestSize(tester, size);
      await tester.pumpWidget(tillApp(home: const RoleSelectScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Admin / Owner'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
      if (_preview) {
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/signin_$name.png'));
      }
    });
  }

  testWidgets('checkout sheet lays out on a phone', (tester) async {
    await setTestSize(tester, const Size(400, 860));
    await tester.pumpWidget(tillApp(
      cart: sampleCart(),
      home: const Scaffold(
        backgroundColor: Colors.black54,
        body: Align(alignment: Alignment.bottomCenter, child: CheckoutBottomSheet()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Complete sale'), findsOneWidget);
    if (_preview) {
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/checkout_phone.png'));
    }
  });

  testWidgets('payment dialog lays out beside the tablet cart', (tester) async {
    await setTestSize(tester, const Size(1180, 820));
    await tester.pumpWidget(tillApp(
      cart: sampleCart(),
      home: const Scaffold(
        backgroundColor: Colors.black54,
        body: Center(
          child: SizedBox(width: 520, child: CheckoutBottomSheet(showLines: false)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Take payment'), findsOneWidget);
    if (_preview) {
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/checkout_tablet.png'));
    }
  });
}
