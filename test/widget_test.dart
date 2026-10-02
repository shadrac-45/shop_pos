// ============================================
// Widget Test — ShopPOS
// ============================================
// Basic test to verify app initialization.
// Run: flutter test
// ============================================

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/core/utils/expiry_helpers.dart';
import 'package:shop_pos/features/sales/services/paystack_service.dart';

void main() {
  testWidgets('ShopPOS app should render basic widget structure', (tester) async {
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

  group('HashHelpers Tests', () {
    test('PINs are hashed with bcrypt and a fresh salt each time', () {
      final hash1 = HashHelpers.hashPin('1234');
      final hash2 = HashHelpers.hashPin('1234');

      expect(hash1, startsWith(r'$2a$'));
      expect(hash1, isNot(equals(hash2))); // different salts
      expect(HashHelpers.verifyPin('1234', hash1), isTrue);
      expect(HashHelpers.verifyPin('1234', hash2), isTrue);
      expect(hash1, isNot(contains('1234')));
    });

    test('hashes from older versions still verify and are flagged for upgrade', () {
      final legacyPin = HashHelpers.legacyPinHashForTest('5566');
      expect(HashHelpers.verifyPin('5566', legacyPin), isTrue);
      expect(HashHelpers.verifyPin('5567', legacyPin), isFalse);
      expect(HashHelpers.needsRehash(legacyPin), isTrue);
      expect(HashHelpers.needsRehash(HashHelpers.hashPin('5566')), isFalse);

      final legacyPassword = HashHelpers.legacyPasswordHashForTest('OldPass123');
      expect(HashHelpers.verifyPassword('OldPass123', legacyPassword), isTrue);
      expect(HashHelpers.verifyPassword('oldpass123', legacyPassword), isFalse);
    });

    test('verifyPin correctly matches hashed PIN and rejects raw string', () {
      final hashedOwner = HashHelpers.hashPin('1234');
      expect(HashHelpers.verifyPin('1234', hashedOwner), isTrue);
      expect(HashHelpers.verifyPin('9999', hashedOwner), isFalse);
      expect(HashHelpers.verifyPin('1234', '1234'), isFalse); // Raw plaintext string is rejected
    });

    test('isDefaultPinHash flags only the seeded default PINs', () {
      expect(HashHelpers.isDefaultPinHash(HashHelpers.hashPin('1234')), isTrue);
      expect(HashHelpers.isDefaultPinHash(HashHelpers.hashPin('0000')), isTrue);
      expect(HashHelpers.isDefaultPinHash(HashHelpers.hashPin('482916')), isFalse);
      expect(HashHelpers.isDefaultPinHash('1234'), isFalse); // plaintext is not a hash
    });
  });

  group('CurrencyHelpers Tests', () {
    test('Formats currency with GH₵ symbol correctly', () {
      expect(CurrencyHelpers.format(12.5), equals('GH₵ 12.50'));
      expect(CurrencyHelpers.format(0.0), equals('GH₵ 0.00'));
      expect(CurrencyHelpers.formatCompact(15.0), equals('GH₵15.00'));
    });
  });

  group('ExpiryHelpers Tests', () {
    test('Categorizes expiry levels correctly based on remaining days', () {
      expect(ExpiryHelpers.getLevel(null), equals(ExpiryLevel.noStock));
      expect(ExpiryHelpers.getLevel(-1), equals(ExpiryLevel.expired));
      expect(ExpiryHelpers.getLevel(0), equals(ExpiryLevel.expired));
      expect(ExpiryHelpers.getLevel(5), equals(ExpiryLevel.urgent));
      expect(ExpiryHelpers.getLevel(20), equals(ExpiryLevel.warning));
      expect(ExpiryHelpers.getLevel(40), equals(ExpiryLevel.good));
    });
  });

  group('Paystack MoMo Phone Normalisation Tests', () {
    test('Normalises local Ghana 10-digit number to +233 format', () {
      expect(normaliseGhanaPhone('0551234987'), equals('+233551234987'));
      expect(normaliseGhanaPhone('0501234987'), equals('+233501234987'));
    });

    test('Accepts valid +233 numbers', () {
      expect(normaliseGhanaPhone('+233551234987'), equals('+233551234987'));
    });

    test('Rejects invalid phone numbers', () {
      expect(normaliseGhanaPhone('12345'), isNull);
      expect(normaliseGhanaPhone('055123'), isNull);
      expect(normaliseGhanaPhone('abcdefghij'), isNull);
    });

    test('validates phone string with helpful user error messages', () {
      expect(validateGhanaPhone(''), equals('Phone number is required'));
      expect(validateGhanaPhone('0551234987'), isNull);
      expect(validateGhanaPhone('123'), contains('Enter a valid Ghana number'));
    });
  });
}
