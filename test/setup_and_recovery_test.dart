// ============================================
// Setup wizard & admin recovery tests — ShopPOS
// ============================================

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/auth/services/admin_auth_service.dart';
import 'package:shop_pos/features/setup/providers/setup_wizard_provider.dart';
import 'package:shop_pos/features/setup/screens/setup_wizard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wizard rules', () {
    test('PIN rules', () {
      expect(SetupWizardNotifier.pinProblem('1234'), contains('default'));
      expect(SetupWizardNotifier.pinProblem('0000'), contains('default'));
      expect(SetupWizardNotifier.pinProblem('12'), isNotNull);
      expect(SetupWizardNotifier.pinProblem('1234567'), isNotNull);
      expect(SetupWizardNotifier.pinProblem('12a4'), isNotNull);
      expect(SetupWizardNotifier.pinProblem('4829'), isNull);
      expect(SetupWizardNotifier.pinProblem('482910'), isNull);
      expect(SetupWizardNotifier.ownerPinProblem('4829', '4828'), contains('match'));
      expect(SetupWizardNotifier.ownerPinProblem('4829', '4829'), isNull);
    });

    test('staff PINs must be unique and differ from the owner\'s', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(setupWizardProvider.notifier);
      n.update((s) => s.copyWith(ownerPin: '4829', staff: [
            WizardStaffEntry(name: 'Ama', pin: '4829'),
            WizardStaffEntry(name: 'Kofi', pin: '5566'),
            WizardStaffEntry(name: 'Esi', pin: '5566'),
            WizardStaffEntry(name: '', pin: ''), // blank row: skipped
            WizardStaffEntry(name: '', pin: '7788'),
          ]));
      final e = n.staffErrors();
      expect(e[0].pin, contains('owner PIN'));
      expect(e[1].isEmpty, isTrue);
      expect(e[2].pin, contains('staff member 2'));
      expect(e[3].isEmpty, isTrue);
      expect(e[4].name, isNotNull);
      expect(n.validateStaff(), startsWith('Staff member 1'));
    });
  });

  group('Wizard layout', () {
    Future<void> pumpWizard(WidgetTester tester, {double keyboard = 0}) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: SetupWizardScreen()),
      ));
    }

    Future<void> tapNext(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Next'));
      await tester.pumpAndSettle();
    }

    testWidgets('360 px wide: every step lays out without overflow; data survives Back',
        (tester) async {
      await pumpWizard(tester);

      // Step 1 blocks until the store name is filled, with the error on the field.
      await tapNext(tester);
      expect(find.text('Enter your store\'s name.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Store name'), 'Kofi Shop');
      await tapNext(tester);
      expect(find.text('Step 2 of 7'), findsOneWidget);
      expect(find.text('Business'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'VAT rate (%)'), '15');
      await tester.pumpAndSettle();
      expect(find.text('Yes, prices include VAT'), findsOneWidget);
      await tapNext(tester);
      await tapNext(tester); // payments

      // Owner PIN (security, on its own screen): mismatch is caught.
      expect(find.text('Security'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Owner PIN'), '4829');
      await tester.enterText(find.widgetWithText(TextField, 'Enter the PIN again'), '4820');
      await tapNext(tester);
      expect(find.text('The two PINs don\'t match.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Enter the PIN again'), '4829');
      await tapNext(tester);

      // Staff: stacked card with full-width fields, then add a second one.
      expect(find.text('Staff member 1'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Name').first, 'Ama');
      await tester.enterText(find.widgetWithText(TextField, 'Staff PIN').first, '4829');
      await tester.ensureVisible(find.text('Add staff member'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add staff member'));
      await tester.pumpAndSettle();
      expect(find.text('Staff member 2'), findsOneWidget);
      await tapNext(tester);
      expect(find.text('Same as your owner PIN. Every PIN must be different.'), findsOneWidget);

      // Role dropdown spans the card, so "Manager" is fully visible.
      final roleField = find.byType(DropdownButtonFormField<String>).first;
      expect(tester.getSize(roleField).width, greaterThan(250));

      // Back to step 1 and forward again: everything typed is still there.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.widgetWithText(OutlinedButton, 'Back'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Kofi Shop'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tapNext(tester);
      }
      expect(find.text('Ama'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with the numeric keyboard open, the staff step still fits', (tester) async {
      await pumpWizard(tester, keyboard: 300);
      await tester.enterText(find.widgetWithText(TextField, 'Store name'), 'Kofi Shop');
      await tapNext(tester);
      await tapNext(tester);
      await tapNext(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Owner PIN'), '4829');
      await tester.enterText(find.widgetWithText(TextField, 'Enter the PIN again'), '4829');
      await tapNext(tester);
      await tester.tap(find.widgetWithText(TextField, 'Staff PIN').first);
      await tester.pumpAndSettle();
      // The Next button stays on screen above the keyboard.
      final next = tester.getRect(find.widgetWithText(ElevatedButton, 'Next'));
      expect(next.bottom, lessThanOrEqualTo(640 - 300 + 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('Admin recovery', () {
    late Isar isar;
    late Directory dir;
    late AppUser owner;

    setUpAll(() async {
      try {
        await Isar.initializeIsarCore(libraries: {Abi.windowsX64: 'isar.dll'});
      } catch (_) {}
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('pos_recovery_');
      isar = await Isar.open(allSchemas, directory: dir.path, name: 'recovery');
      owner = AppUser()
        ..name = 'Owner'
        ..role = AppConstants.roleOwner
        ..email = 'owner@shop.com'
        ..pinHash = HashHelpers.hashPin('482910')
        ..passwordHash = HashHelpers.hashPassword('OldPass123');
      await isar.writeTxn(() => isar.appUsers.put(owner));
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      await dir.delete(recursive: true);
    });

    test('successful reset: new password works, old one does not, sessions end', () async {
      final check = await AdminAuthService.verifyRecoveryPin(isar,
          email: ' Owner@Shop.com ', ownerPin: '482910');
      expect(check.result, RecoveryPinResult.verified);

      await expectLater(
        AdminAuthService.completeRecovery(isar, ticket: check.ticket!, newPassword: 'short'),
        throwsArgumentError,
      );
      await AdminAuthService.completeRecovery(isar,
          ticket: check.ticket!, newPassword: 'NewPass456');

      expect(await AdminAuthService.login(isar, 'owner@shop.com', 'OldPass123'), isNull);
      final signedIn = await AdminAuthService.login(isar, 'owner@shop.com', 'NewPass456');
      expect(signedIn, isNotNull);
      expect(signedIn!.passwordHash, startsWith(r'$2')); // bcrypt, not plain text
      expect(signedIn.credentialVersion, owner.credentialVersion + 1);
    });

    test('5 wrong PINs lock recovery for 15 minutes, even for the right PIN', () async {
      for (var i = 1; i <= 4; i++) {
        final c = await AdminAuthService.verifyRecoveryPin(isar,
            email: 'owner@shop.com', ownerPin: '111111');
        expect(c.result, RecoveryPinResult.invalid);
        expect(c.attemptsLeft, 5 - i);
      }
      final fifth = await AdminAuthService.verifyRecoveryPin(isar,
          email: 'owner@shop.com', ownerPin: '111111');
      expect(fifth.result, RecoveryPinResult.lockedOut);

      final correct = await AdminAuthService.verifyRecoveryPin(isar,
          email: 'owner@shop.com', ownerPin: '482910');
      expect(correct.result, RecoveryPinResult.lockedOut);
      expect(correct.lockedFor.inMinutes, greaterThanOrEqualTo(14));
      expect(await AdminAuthService.recoveryLockRemaining(), greaterThan(Duration.zero));
    });

    test('unknown email and wrong PIN look identical; both count toward the lock', () async {
      final unknown = await AdminAuthService.verifyRecoveryPin(isar,
          email: 'nobody@shop.com', ownerPin: '482910');
      final wrongPin = await AdminAuthService.verifyRecoveryPin(isar,
          email: 'owner@shop.com', ownerPin: '999999');
      expect(unknown.result, RecoveryPinResult.invalid);
      expect(wrongPin.result, RecoveryPinResult.invalid);
      expect(wrongPin.attemptsLeft, 3);
    });

    test('a default owner PIN can never be used to recover', () async {
      owner.pinHash = HashHelpers.hashPin('1234');
      await isar.writeTxn(() => isar.appUsers.put(owner));
      final c = await AdminAuthService.verifyRecoveryPin(isar,
          email: 'owner@shop.com', ownerPin: '1234');
      expect(c.result, RecoveryPinResult.invalid);
    });

    test('admin account detection for the first-time-setup message', () async {
      expect(await AdminAuthService.adminAccountExists(isar), isTrue);
      await isar.writeTxn(() => isar.appUsers.clear());
      expect(await AdminAuthService.adminAccountExists(isar), isFalse);
    });

    test('password strength rules', () {
      expect(AdminAuthService.passwordProblem('abc12'), isNotNull); // short
      expect(AdminAuthService.passwordProblem('abcdefgh'), isNotNull); // no digit
      expect(AdminAuthService.passwordProblem('password1'), isNotNull); // common
      expect(AdminAuthService.passwordProblem('kofi2026x', email: 'kofi@shop.com'), isNotNull);
      expect(AdminAuthService.passwordProblem('Sunrise42'), isNull);
    });

    test('old SHA-256 PINs still sign in and are upgraded to bcrypt', () async {
      final cashier = AppUser()
        ..name = 'Kofi'
        ..role = AppConstants.roleCashier
        ..pinHash = HashHelpers.legacyPinHashForTest('5566');
      await isar.writeTxn(() => isar.appUsers.put(cashier));

      final container = ProviderContainer(overrides: [isarProvider.overrideWithValue(isar)]);
      addTearDown(container.dispose);
      final result = await container.read(currentUserProvider.notifier).login('5566');
      expect(result, LoginResult.success);
      expect((await isar.appUsers.get(cashier.id))!.pinHash, startsWith(r'$2'));

      // The upgraded hash still matches only the right PIN.
      container.read(currentUserProvider.notifier).logout();
      expect(await container.read(currentUserProvider.notifier).login('5567'),
          LoginResult.invalidPin);
      expect(await container.read(currentUserProvider.notifier).login('5566'),
          LoginResult.success);
    });

    test('a reset ends a session that was open before it', () async {
      final container = ProviderContainer(overrides: [isarProvider.overrideWithValue(isar)]);
      addTearDown(container.dispose);
      final auth = container.read(currentUserProvider.notifier);
      auth.setUser((await isar.appUsers.get(owner.id))!);
      expect(container.read(currentUserProvider), isNotNull);

      final check = await AdminAuthService.verifyRecoveryPin(isar,
          email: 'owner@shop.com', ownerPin: '482910');
      await AdminAuthService.completeRecovery(isar,
          ticket: check.ticket!, newPassword: 'NewPass456');

      auth.checkSessionStillValid();
      expect(container.read(currentUserProvider), isNull);
    });
  });
}
