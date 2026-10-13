// ============================================
// Login Flow Test — ShopPOS
// ============================================
// PIN sign-in on a real database: the right
// account is found (accounts are checked in
// parallel), wrong, deactivated and default
// PINs are refused, and the phone banner's
// headline is never covered by its decorative
// receipt card.
// ============================================

import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/core/theme/app_theme.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/auth/screens/login_screen.dart';

import 'support/till_harness.dart';

late Isar isar;
late Directory dir;

Future<AppUser> _user(String name, String role, String pin, {bool active = true}) async {
  final u = AppUser()
    ..name = name
    ..role = role
    ..pinHash = HashHelpers.hashPin(pin)
    ..isActive = active;
  await isar.writeTxn(() => isar.appUsers.put(u));
  return u;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(libraries: {Abi.windowsX64: 'isar.dll'});
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('pos_login_flow_');
    isar = await Isar.open(allSchemas, directory: dir.path, name: 'login_flow');
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    await dir.delete(recursive: true);
  });

  group('PIN matching across parallel workers', () {
    final pins = [for (var i = 0; i < 9; i++) '${4100 + i}'];
    late List<String> hashes;
    setUpAll(() => hashes = [for (final p in pins) HashHelpers.hashPin(p)]);

    test('finds every account, including at chunk boundaries', () async {
      for (var i = 0; i < pins.length; i++) {
        expect(await HashHelpers.findPinMatch(pins[i], hashes), i, reason: pins[i]);
      }
    });

    test('a wrong PIN matches nobody; empty and legacy hashes still work', () async {
      expect(await HashHelpers.findPinMatch('9999', hashes), -1);
      final mixed = ['', HashHelpers.legacyPinHashForTest('7531'), ...hashes];
      expect(await HashHelpers.findPinMatch('7531', mixed), 1);
      expect(await HashHelpers.findPinMatch('4108', mixed), 10);
    });

    test('two accounts with the same PIN: the first one wins, as before', () async {
      final dup = [...hashes, HashHelpers.hashPin('4101')];
      expect(await HashHelpers.findPinMatch('4101', dup), 1);
    });
  });

  group('AuthNotifier', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer(overrides: [isarProvider.overrideWithValue(isar)]));
    tearDown(() => container.dispose());
    AuthNotifier auth() => container.read(currentUserProvider.notifier);

    test('owner and staff sign in; switching accounts signs in the right person', () async {
      await _user('Ama', AppConstants.roleOwner, '5821');
      for (var i = 0; i < 6; i++) {
        await _user('Staff $i', AppConstants.roleCashier, '${6300 + i}');
      }
      expect(await auth().login('5821'), LoginResult.success);
      expect(container.read(currentUserProvider)!.role, AppConstants.roleOwner);
      auth().logout();
      expect(await auth().login('6305'), LoginResult.success);
      expect(container.read(currentUserProvider)!.name, 'Staff 5');
      auth().logout();
      expect(container.read(currentUserProvider), isNull);
      expect(await auth().login('6302'), LoginResult.success);
      expect(container.read(currentUserProvider)!.name, 'Staff 2');
    });

    test('wrong PIN, deactivated account and default PIN are refused', () async {
      await _user('Kofi', AppConstants.roleCashier, '7392');
      await _user('Gone', AppConstants.roleCashier, '7393', active: false);
      await _user('Lazy', AppConstants.roleCashier, AppConstants.defaultPins.first);
      expect(await auth().login('1111'), LoginResult.invalidPin);
      expect(await auth().login('7393'), LoginResult.deactivated);
      expect(await auth().login(AppConstants.defaultPins.first), LoginResult.defaultPin);
      expect(container.read(currentUserProvider), isNull);
    });

    test('hasDefaultPin: false after a PIN sign-in; checked for email sign-in', () async {
      final kofi = await _user('Kofi', AppConstants.roleCashier, '7392');
      final owner = await _user('Ama', AppConstants.roleOwner, AppConstants.defaultPins.last);
      expect(await auth().login('7392'), LoginResult.success);
      expect(await auth().hasDefaultPin(), isFalse);
      auth().logout();
      auth().setUser(owner); // email + password sign-in: PIN unknown
      expect(await auth().hasDefaultPin(), isTrue);
      auth().logout();
      auth().setUser(kofi);
      expect(await auth().hasDefaultPin(), isFalse);
    });
  });

  for (final width in [320.0, 360.0, 375.0, 400.0, 430.0]) {
    testWidgets('phone banner headline is clear of the receipt card at $width px', (tester) async {
      await setTestSize(tester, Size(width, 860));
      await tester.pumpWidget(ProviderScope(
        overrides: [isarProvider.overrideWithValue(isar)],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const LoginScreen()),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);

      final headline = tester.getRect(find.text('Run your shop\nwith confidence.'));
      final card = tester.getRect(find
          .ancestor(of: find.text('Receipt #1042'), matching: find.byType(Container))
          .last);
      // The card is tilted 0.06 rad about its centre: use its rotated bounds.
      const a = 0.06;
      final tilted = Rect.fromCenter(
        center: card.center,
        width: card.width * math.cos(a) + card.height * math.sin(a),
        height: card.width * math.sin(a) + card.height * math.cos(a),
      );
      expect(headline.right, lessThanOrEqualTo(tilted.left),
          reason: 'headline $headline vs card $tilted');
    });
  }
}
