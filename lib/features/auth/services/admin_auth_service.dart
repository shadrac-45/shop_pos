/// ============================================
/// AdminAuthService — ShopPOS
/// ============================================
/// Email + password authentication for the
/// admin (owner) account, password rules, and
/// password recovery.
///
/// Recovery (the app is offline-first, so there
/// is no email service):
///   1. enter the admin email
///   2. prove identity with the owner PIN
///   3. set a new password (twice)
/// Five wrong PINs lock recovery for 15 minutes,
/// and messages never reveal whether an email
/// belongs to an account.
///
/// TODO(email-reset): when the backend gains an
/// email service, add an emailed one-time code
/// (single use, expires after 15 minutes) as a
/// second recovery route.
/// ============================================
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';

/// Proof that the owner PIN was entered correctly, needed to set the new
/// password. Only [AdminAuthService.verifyRecoveryPin] creates one.
class RecoveryTicket {
  final int ownerId;
  final DateTime issuedAt;
  RecoveryTicket._(this.ownerId, this.issuedAt);

  static const validFor = Duration(minutes: 10);
  bool get isExpired => DateTime.now().difference(issuedAt) > validFor;
}

enum RecoveryPinResult { verified, invalid, lockedOut }

class RecoveryCheck {
  final RecoveryPinResult result;
  final RecoveryTicket? ticket;

  /// Wrong PINs still allowed before recovery locks.
  final int attemptsLeft;

  /// How long recovery stays locked.
  final Duration lockedFor;

  const RecoveryCheck(this.result,
      {this.ticket, this.attemptsLeft = 0, this.lockedFor = Duration.zero});
}

class AdminAuthService {
  AdminAuthService._();

  static const minPasswordLength = 8;
  static const maxRecoveryAttempts = 5;
  static const recoveryLockout = Duration(minutes: 15);

  static const _kFailed = 'recovery_failed_attempts';
  static const _kLockedUntil = 'recovery_locked_until_ms';

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static const _commonPasswords = {
    'password', 'password1', 'password123', '12345678', '123456789',
    '1234567890', 'qwerty123', 'qwertyuiop', 'abc12345', 'abcd1234',
    'iloveyou', 'admin123', 'welcome1', 'letmein1', '11111111',
    '00000000', 'shoppos1', 'shoppos123',
  };

  // ── Validation ─────────────────────────────────────────────────────

  static String? emailProblem(String email) {
    final e = email.trim();
    if (e.isEmpty) return 'Enter your email address.';
    if (!_emailPattern.hasMatch(e)) return 'Enter a valid email address.';
    return null;
  }

  /// Why [password] is too weak, or null if it is acceptable: at least
  /// [minPasswordLength] characters with a letter and a number, not a
  /// common password, and not containing the email name.
  static String? passwordProblem(String password, {String email = ''}) {
    if (password.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters.';
    }
    if (utf8.encode(password).length > HashHelpers.maxSecretBytes) {
      return 'Use at most ${HashHelpers.maxSecretBytes} characters.';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(password) || !RegExp(r'\d').hasMatch(password)) {
      return 'Include at least one letter and one number.';
    }
    if (_commonPasswords.contains(password.toLowerCase())) {
      return 'That password is too common. Choose another.';
    }
    final name = email.trim().toLowerCase().split('@').first;
    if (name.length >= 4 && password.toLowerCase().contains(name)) {
      return 'Don\'t use your email name in the password.';
    }
    return null;
  }

  /// 0–4: a rough strength score for the password meter.
  static int passwordScore(String password) {
    if (password.isEmpty) return 0;
    var score = 0;
    if (password.length >= minPasswordLength) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'\d').hasMatch(password) && RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    if (passwordProblem(password) != null) score = score.clamp(0, 1);
    return score;
  }

  // ── Sign-in ────────────────────────────────────────────────────────

  static Future<AppUser?> _activeOwnerByEmail(Isar isar, String email) => isar.appUsers
      .filter()
      .emailEqualTo(email.trim().toLowerCase())
      .roleEqualTo(AppConstants.roleOwner)
      .isActiveEqualTo(true)
      .findFirst();

  /// True if an admin account with email + password exists, i.e. "forgot
  /// password" can offer recovery rather than first-time setup.
  static Future<bool> adminAccountExists(Isar isar) => isar.appUsers
      .filter()
      .roleEqualTo(AppConstants.roleOwner)
      .emailIsNotNull()
      .passwordHashIsNotNull()
      .isNotEmpty();

  /// Attempt to login with [email] and [password].
  /// Returns the matching [AppUser] if credentials are valid, or null.
  static Future<AppUser?> login(
    Isar isar,
    String email,
    String password,
  ) async {
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty || password.isEmpty) return null;

    final user = await isar.appUsers
        .filter()
        .emailEqualTo(trimmedEmail)
        .isActiveEqualTo(true)
        .findFirst();

    if (user == null || user.passwordHash == null) return null;

    final valid = await HashHelpers.verifyPasswordAsync(password, user.passwordHash!);
    if (!valid) return null;

    if (HashHelpers.needsRehash(user.passwordHash!)) {
      user.passwordHash = await HashHelpers.hashPasswordAsync(password);
      await isar.writeTxn(() => isar.appUsers.put(user));
    }
    return user;
  }

  /// Create or update the owner account with email + password credentials.
  /// Called during first-run setup wizard completion.
  static Future<void> setAdminCredentials(
    Isar isar, {
    required int userId,
    required String email,
    required String password,
  }) async {
    final user = await isar.appUsers.get(userId);
    if (user == null) return;
    user.email = email.trim().toLowerCase();
    user.passwordHash = await HashHelpers.hashPasswordAsync(password);
    await isar.writeTxn(() async => isar.appUsers.put(user));
  }

  // ── Recovery ───────────────────────────────────────────────────────

  /// How long recovery is still locked, or zero.
  static Future<Duration> recoveryLockRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_kLockedUntil) ?? 0;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    if (left > 0) return Duration(milliseconds: left);
    if (until != 0) {
      await prefs.remove(_kLockedUntil);
      await prefs.remove(_kFailed);
    }
    return Duration.zero;
  }

  /// Step 2 of recovery: checks [ownerPin] for the owner account with
  /// [email]. Wrong email and wrong PIN give the same result, so the form
  /// can't be used to discover which emails exist. A default PIN (1234,
  /// 0000) never verifies: it is publicly known.
  static Future<RecoveryCheck> verifyRecoveryPin(
    Isar isar, {
    required String email,
    required String ownerPin,
  }) async {
    final locked = await recoveryLockRemaining();
    if (locked > Duration.zero) {
      return RecoveryCheck(RecoveryPinResult.lockedOut, lockedFor: locked);
    }

    final owner = await _activeOwnerByEmail(isar, email);
    final pin = ownerPin.trim();
    // Always do one PIN check, against a throwaway hash when the email is
    // unknown, so response time doesn't reveal whether the email exists.
    final pinMatches = await compute(
        _verifyPinArgs, (pin, owner?.pinHash ?? await _decoyHash()));
    final ok = owner != null &&
        owner.passwordHash != null &&
        !AppConstants.defaultPins.contains(pin) &&
        pinMatches;

    final prefs = await SharedPreferences.getInstance();
    if (ok) {
      await prefs.remove(_kFailed);
      await prefs.remove(_kLockedUntil);
      return RecoveryCheck(RecoveryPinResult.verified,
          ticket: RecoveryTicket._(owner.id, DateTime.now()));
    }

    final failed = (prefs.getInt(_kFailed) ?? 0) + 1;
    await ActivityLogService.log(isar, null, ActivityAction.loginFailed,
        'Password recovery: wrong email or owner PIN ($failed in a row)');
    if (failed >= maxRecoveryAttempts) {
      final until = DateTime.now().add(recoveryLockout);
      await prefs.setInt(_kLockedUntil, until.millisecondsSinceEpoch);
      await prefs.setInt(_kFailed, failed);
      return const RecoveryCheck(RecoveryPinResult.lockedOut, lockedFor: recoveryLockout);
    }
    await prefs.setInt(_kFailed, failed);
    return RecoveryCheck(RecoveryPinResult.invalid,
        attemptsLeft: maxRecoveryAttempts - failed);
  }

  static bool _verifyPinArgs((String, String) a) => HashHelpers.verifyPin(a.$1, a.$2);

  static String? _decoy;
  static Future<String> _decoyHash() async =>
      _decoy ??= await HashHelpers.hashPinAsync('decoy-${DateTime.now().microsecondsSinceEpoch}');

  /// Step 3 of recovery: sets the new password. Ends every existing
  /// session of the account (via its credential version). Throws
  /// [StateError] for an expired ticket and [ArgumentError] for a weak
  /// password.
  static Future<void> completeRecovery(
    Isar isar, {
    required RecoveryTicket ticket,
    required String newPassword,
  }) async {
    if (ticket.isExpired) {
      throw StateError('This reset took too long. Start again.');
    }
    final owner = await isar.appUsers.get(ticket.ownerId);
    if (owner == null || !owner.isActive) {
      throw StateError('This account can no longer be reset.');
    }
    final problem = passwordProblem(newPassword, email: owner.email ?? '');
    if (problem != null) throw ArgumentError(problem);

    final hash = await HashHelpers.hashPasswordAsync(newPassword);
    owner
      ..passwordHash = hash
      ..credentialVersion += 1
      ..updatedAt = DateTime.now()
      ..isSynced = false;
    await isar.writeTxn(() async {
      await isar.appUsers.put(owner);
      await isar.activityLogs.put(ActivityLogService.entry(
          owner, ActivityAction.passwordReset, 'Reset with owner PIN'));
    });
  }

  /// Changes the signed-in owner's password. Returns false if
  /// [currentPassword] is wrong. Throws [ArgumentError] for a weak one.
  static Future<bool> changePassword(
    Isar isar,
    AppUser user, {
    required String currentPassword,
    required String newPassword,
  }) async {
    if (user.passwordHash == null ||
        !await HashHelpers.verifyPasswordAsync(currentPassword, user.passwordHash!)) {
      return false;
    }
    final problem = passwordProblem(newPassword, email: user.email ?? '');
    if (problem != null) throw ArgumentError(problem);
    user
      ..passwordHash = await HashHelpers.hashPasswordAsync(newPassword)
      ..updatedAt = DateTime.now()
      ..isSynced = false;
    await isar.writeTxn(() async {
      await isar.appUsers.put(user);
      await isar.activityLogs.put(ActivityLogService.entry(
          user, ActivityAction.passwordReset, 'Changed in Settings'));
    });
    return true;
  }
}
