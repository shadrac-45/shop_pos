/// ============================================
/// Auth Provider — ShopPOS
/// ============================================
/// Manages currently logged-in user state and
/// unified PIN-based authentication.
/// Blocks deactivated accounts from logging in.
/// Integrates session timeout management.
/// Includes brute-force PIN lockout protection.
///
/// The lockout lives only here (persisted to
/// SharedPreferences so restarting the app
/// can't bypass it); the login screen just
/// displays it.
/// ============================================
library;

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/services/auth_service.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/core/services/session_manager.dart';

// ── Result enum ──────────────────────────────────────────

enum LoginResult {
  success,
  invalidPin,
  deactivated,
  lockedOut,

  /// The PIN matched an account, but it is still a publicly known default
  /// PIN (see `AppConstants.defaultPins`), so PIN login is refused until
  /// it has been changed.
  defaultPin,
}

// ── Lockout config ────────────────────────────────────────

const int maxFailedPinAttempts = 5;
const Duration pinLockoutDuration = Duration(seconds: 30);

const _kFailedAttemptsKey = 'login_failed_attempts';
const _kLockoutExpiryKey = 'login_lockout_expiry_ms';

// ── Provider ─────────────────────────────────────────────

final currentUserProvider =
    StateNotifierProvider<AuthNotifier, AppUser?>((ref) {
  return AuthNotifier(ref);
});

// ── Notifier ─────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AppUser?> {
  final Ref ref;

  AuthNotifier(this.ref) : super(null) {
    _restoreLockout();
  }

  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  /// Seconds remaining on the current lockout, or 0 if not locked out.
  int get lockoutSecondsRemaining {
    final until = _lockedUntil;
    if (until == null) return 0;
    final remaining = until.difference(DateTime.now()).inMilliseconds;
    return remaining > 0 ? (remaining / 1000).ceil() : 0;
  }

  /// Wrong PINs allowed before the keypad locks.
  int get attemptsBeforeLockout => maxFailedPinAttempts - _failedAttempts;

  bool get isLockedOut {
    final until = _lockedUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      // Lockout expired — clear it.
      _lockedUntil = null;
      _failedAttempts = 0;
      _persistLockout();
      return false;
    }
    return true;
  }

  Future<void> _restoreLockout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _failedAttempts = prefs.getInt(_kFailedAttemptsKey) ?? 0;
      final expiryMs = prefs.getInt(_kLockoutExpiryKey) ?? 0;
      if (expiryMs > DateTime.now().millisecondsSinceEpoch) {
        _lockedUntil = DateTime.fromMillisecondsSinceEpoch(expiryMs);
      }
    } catch (e) {
      debugPrint('[Auth] Could not restore lockout state: $e');
    }
  }

  Future<void> _persistLockout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_failedAttempts == 0 && _lockedUntil == null) {
        await prefs.remove(_kFailedAttemptsKey);
        await prefs.remove(_kLockoutExpiryKey);
      } else {
        await prefs.setInt(_kFailedAttemptsKey, _failedAttempts);
        if (_lockedUntil != null) {
          await prefs.setInt(
              _kLockoutExpiryKey, _lockedUntil!.millisecondsSinceEpoch);
        }
      }
    } catch (e) {
      debugPrint('[Auth] Could not save lockout state: $e');
    }
  }

  /// Single PIN-based login for all staff accounts.
  /// Hashes [pin] using AuthService.hashPinAsync and queries Isar for the
  /// matching AppUser account, automatically resolving the user's role.
  ///
  /// After [maxFailedPinAttempts] consecutive failures, login is blocked
  /// for [pinLockoutDuration] regardless of which account is being
  /// targeted, since a failed PIN lookup doesn't reveal which account was
  /// intended. Check [lockoutSecondsRemaining] for how long to wait.
  Future<LoginResult> login(String pin) async {
    if (isLockedOut) {
      return LoginResult.lockedOut;
    }

    final isar = ref.read(isarProvider);
    // Hash off the main isolate so the UI never freezes.
    final hashedPin = await AuthService.hashPinAsync(pin);

    // Query by hashed PIN — the only supported auth path.
    final user =
        await isar.appUsers.filter().pinHashEqualTo(hashedPin).findFirst();

    if (user != null) {
      // Block login for deactivated accounts.
      if (!user.isActive) {
        return LoginResult.deactivated;
      }

      // Default PINs are printed in the source and README, so they prove
      // nothing. The owner must sign in with email + password and change
      // it; staff need the owner to reset theirs.
      if (HashHelpers.isDefaultPinHash(user.pinHash)) {
        return LoginResult.defaultPin;
      }

      // Successful login clears any accumulated failed attempts.
      _failedAttempts = 0;
      _lockedUntil = null;
      await _persistLockout();
      _signIn(user, 'PIN');
      return LoginResult.success;
    }

    // No match — count this as a failed attempt.
    _failedAttempts++;
    if (_failedAttempts >= maxFailedPinAttempts) {
      _lockedUntil = DateTime.now().add(pinLockoutDuration);
    }
    await _persistLockout();
    await ActivityLogService.log(isar, null, ActivityAction.loginFailed,
        'Wrong PIN ($_failedAttempts in a row)');

    return _lockedUntil != null ? LoginResult.lockedOut : LoginResult.invalidPin;
  }

  /// Update logged-in user's own PIN.
  Future<void> updatePin(String newPin) async {
    final current = state;
    if (current == null) return;

    final isar = ref.read(isarProvider);
    final hashedPin = await AuthService.hashPinAsync(newPin);

    current
      ..pinHash = hashedPin
      ..updatedAt = DateTime.now()
      ..isSynced = false;
    await isar.writeTxn(() async {
      await isar.appUsers.put(current);
      await isar.activityLogs.put(ActivityLogService.entry(
          current, ActivityAction.pinChanged, current.name));
    });

    state = current;
  }

  /// Directly set the logged-in user (used by AdminLoginScreen after
  /// email+password verification, and after the setup wizard).
  void setUser(AppUser user) {
    _failedAttempts = 0;
    _lockedUntil = null;
    _persistLockout();
    _signIn(user, 'email');
  }

  void _signIn(AppUser user, String method) {
    state = user;
    ref.read(sessionManagerProvider).startSession();
    ActivityLogService.log(
        ref.read(isarProvider), user, ActivityAction.login, 'via $method');
  }

  /// Signs out. Navigation back to the role picker is handled app-wide
  /// by ShopPOSApp when the user becomes null.
  void logout({bool timedOut = false}) {
    final user = state;
    ref.read(sessionManagerProvider).endSession();
    state = null;
    if (user != null) {
      ActivityLogService.log(ref.read(isarProvider), user,
          timedOut ? ActivityAction.sessionTimeout : ActivityAction.logout);
    }
  }

  /// Whether the logged-in user still has a default PIN and should be
  /// made to change it.
  bool get hasDefaultPin {
    final user = state;
    return user != null && HashHelpers.isDefaultPinHash(user.pinHash);
  }

  bool get isOwner => state?.role == 'owner';
  bool get isLoggedIn => state != null;
}
