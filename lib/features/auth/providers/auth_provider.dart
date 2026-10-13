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
import 'dart:async';

import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/services/cloud_service.dart';
import 'package:shop_pos/core/services/sync_service.dart';

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
    final settings = await isar.storeSettings.get(1);
    final cloud = settings != null && CloudService.isConnected(settings);
    // Checked against each account's salted hash, off the main isolate.
    var user = await AuthService.findUserByPin(isar, pin);
    if (user == null && cloud) {
      // Not known on this till yet: ask the cloud (anyone assigned to this
      // till's shop can sign in here; the till then keeps their PIN hash).
      final online = await CloudService.pinSignIn(isar, pin);
      if (online.ok) user = online.user;
    }

    if (user != null) {
      // Block login for deactivated accounts.
      if (!user.isActive) {
        return LoginResult.deactivated;
      }

      // Default PINs are printed in the source and README, so they prove
      // nothing. The owner must sign in with email + password and change
      // it; staff need the owner to reset theirs. [pin] just matched this
      // account's hash, so comparing it is the same test as re-hashing
      // every default PIN against the hash — without the bcrypt work.
      if (AppConstants.defaultPins.contains(pin)) {
        return LoginResult.defaultPin;
      }

      // Successful login clears any accumulated failed attempts.
      _failedAttempts = 0;
      _lockedUntil = null;
      await _persistLockout();
      await AuthService.upgradePinHashIfNeeded(isar, user, pin);
      _signIn(user, 'PIN', defaultPin: false);
      if (cloud && !CloudService.hasSession(user)) {
        // Signed in offline (or session expired): get this person's cloud
        // session now, or as soon as the till is back online. The PIN is
        // only kept in memory, and only until then.
        _pendingCloudPin = pin;
        unawaited(ensureCloudSession());
      }
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
      ..credentialVersion += 1
      ..updatedAt = DateTime.now()
      ..modifiedBy = current.id
      ..isSynced = false;
    _signedInVersion = current.credentialVersion;
    _defaultPin = null;
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

  /// The signed-in account's [AppUser.credentialVersion] at sign-in.
  int? _signedInVersion;

  /// PIN of the signed-in person while their cloud session is still to be
  /// fetched (memory only; cleared on success, rejection or sign-out).
  String? _pendingCloudPin;

  /// Makes sure the signed-in person has a cloud session on this till.
  /// Returns true if they have one.
  Future<bool> ensureCloudSession() async {
    final user = state;
    if (user == null) return false;
    final isar = ref.read(isarProvider);
    final fresh = await isar.appUsers.get(user.id);
    if (CloudService.hasSession(fresh)) return true;
    final pin = _pendingCloudPin;
    if (pin == null) return false;
    final r = await CloudService.pinSignIn(isar, pin);
    if (r.ok && r.user!.id == user.id) {
      _pendingCloudPin = null;
      return true;
    }
    if (r.rejected) _pendingCloudPin = null; // PIN changed elsewhere: sign in again
    return false;
  }

  /// Ends the session if the signed-in account was deactivated or its
  /// password/PIN was reset since sign-in (e.g. through password recovery).
  /// Called on user activity, so a stale session can't keep working.
  void checkSessionStillValid() {
    final user = state;
    if (user == null) return;
    final fresh = ref.read(isarProvider).appUsers.getSync(user.id);
    if (fresh == null ||
        !fresh.isActive ||
        fresh.credentialVersion != _signedInVersion) {
      logout(timedOut: false);
    }
  }

  /// Whether the signed-in account's PIN is a default one, once known.
  bool? _defaultPin;

  void _signIn(AppUser user, String method, {bool? defaultPin}) {
    _signedInVersion = user.credentialVersion;
    _defaultPin = defaultPin;
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
    _pendingCloudPin = null;
    _defaultPin = null;
    state = null;
    if (user != null) {
      final isar = ref.read(isarProvider);
      final logged =
          ActivityLogService.log(isar, user, timedOut ? ActivityAction.sessionTimeout : ActivityAction.logout);
      final settings = isar.storeSettings.getSync(1);
      if (settings != null && CloudService.isConnected(settings)) {
        logged.then((_) => _endCloudSession(isar, user), onError: (_) {});
      }
    }
  }

  /// Sends the person's last changes, then ends their cloud session on
  /// this till. Offline, the session is kept until it can be used to send
  /// their changes (it expires on its own).
  Future<void> _endCloudSession(Isar isar, AppUser user) async {
    try {
      await _endCloudSessionUnsafe(isar, user);
    } catch (e) {
      // Best effort: the session expires on its own.
      debugPrint('[Auth] cloud sign-out skipped: $e');
    }
  }

  Future<void> _endCloudSessionUnsafe(Isar isar, AppUser user) async {
    if (!isar.isOpen) return;
    final settings = await isar.storeSettings.get(1);
    if (settings == null || !CloudService.isConnected(settings)) return;
    final fresh = await isar.appUsers.get(user.id);
    if (!CloudService.hasSession(fresh)) return;
    final result = await SyncService.syncNow(isar, baseUrl: '', signedInUserId: user.id)
        .timeout(const Duration(seconds: 30), onTimeout: () => SyncResult(pushed: 0, pulled: 0, at: DateTime.now(), error: 'timeout'));
    if (result.ok) await CloudService.signOut(isar, fresh!);
  }

  /// Whether the logged-in user still has a default PIN and should be
  /// made to change it. Known without work after a PIN sign-in (default
  /// PINs are refused); otherwise checked once, off the UI thread (it
  /// hashes each default PIN with bcrypt).
  Future<bool> hasDefaultPin() async {
    final user = state;
    if (user == null) return false;
    final known = _defaultPin;
    if (known != null) return known;
    final result = await compute(HashHelpers.isDefaultPinHash, user.pinHash);
    if (identical(state, user)) _defaultPin = result;
    return result;
  }

  bool get isOwner => state?.role == 'owner';
  bool get isLoggedIn => state != null;
}
