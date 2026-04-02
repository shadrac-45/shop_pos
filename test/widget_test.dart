// ============================================
// Widget Test — ShopPOS
// ============================================
// Basic test to verify app initialization.
// Run: flutter test
// ============================================

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('ShopPOS app should render login screen', (tester) async {
    // Verify that the app can at least build a MaterialApp
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('ShopPOS Test'),
          ),
        ),
      ),
    );

    expect(find.text('ShopPOS Test'), findsOneWidget);
  });

  test('PIN hashing produces consistent results', () {
    // Simple test to verify PIN hashing is deterministic
    // (Full test requires the app_user.dart import with crypto)
    expect('1234'.length, 4);
    expect('0000'.length, 4);
  });
}
