/// ============================================
/// Auth Provider — ShopPOS
/// ============================================
/// Manages currently logged-in user state and
/// unified PIN-based authentication.
/// Blocks deactivated accounts from logging in.
/// Integrates session timeout management.
/// Includes brute-force PIN lockout protection.
/// ============================================
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/services/auth_service.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/services/session_manager.dart';

// ── Result enum ──────────────────────────────────────────

enum LoginResult {
  success,
  invalidPin,
  deactivated,
  lockedOut,
}

// ── Lockout config ────────────────────────────────────────

const int _maxFailedAttempts = 5;
const Duration _lockoutDuration = Duration(seconds: 30);

// ── Provider ─────────────────────────────────────────────

final currentUserProvider =
    StateNotifierProvider<AuthNotifier, AppUser?>((ref) {
  return AuthNotifier(ref);
});

// ── Notifier ─────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AppUser?> {
  final Ref ref;

  AuthNotifier(this.ref) : super(null);

  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  /// Seconds remaining on the current lockout, or 0 if not locked out.
  /// Useful for showing a countdown on the login screen.
  int get lockoutSecondsRemaining {
    final until = _lockedUntil;
    if (until == null) return 0;
    final remaining = until.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  bool get _isLockedOut {
    final until = _lockedUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      // Lockout expired — clear it.
      _lockedUntil = null;
      _failedAttempts = 0;
      return false;
    }
    return true;
  }

  /// Single PIN-based login for all staff accounts (Owner and Cashiers).
  /// Hashes [pin] using AuthService.hashPinAsync and queries Isar for the
  /// matching AppUser account, automatically resolving the user's role.
  ///
  /// Returns [LoginResult.success] if a matching active account is found,
  /// [LoginResult.deactivated] if the account exists but is deactivated,
  /// [LoginResult.invalidPin] if no account matches the entered PIN,
  /// [LoginResult.lockedOut] if too many recent failed attempts occurred —
  /// check [lockoutSecondsRemaining] for how long to wait.
  ///
  /// Security notes:
  ///  - Only hashed PIN lookup is supported; plaintext comparisons are removed.
  ///  - There is no runtime seeding or PIN-bypass fallback. Default accounts
  ///    are created once at startup in main.dart via _seedDefaultUsersIfEmpty().
  ///  - After _maxFailedAttempts consecutive failures, login is blocked for
  ///    _lockoutDuration regardless of which account is being targeted, since
  ///    a failed PIN lookup doesn't reveal which account was intended.
  Future<LoginResult> login(String pin) async {
    if (_isLockedOut) {
      return LoginResult.lockedOut;
    }

    final isar = ref.read(isarProvider);
    // Hash off the main isolate so the UI never freezes.
    final hashedPin = await AuthService.hashPinAsync(pin);

    // Query by hashed PIN — the only supported auth path.
    final user = await isar.appUsers.filter().pinHashEqualTo(hashedPin).findFirst();

    if (user != null) {
      // Block login for deactivated accounts.
      if (!user.isActive) {
        return LoginResult.deactivated;
      }

      // Successful login clears any accumulated failed attempts.
      _failedAttempts = 0;
      _lockedUntil = null;

      state = user;

      // Start session tracking and inactivity timeout
      ref.read(sessionManagerProvider).startSession();

      return LoginResult.success;
    }

    // No match — count this as a failed attempt.
    _failedAttempts++;
    if (_failedAttempts >= _maxFailedAttempts) {
      _lockedUntil = DateTime.now().add(_lockoutDuration);
    }

    return LoginResult.invalidPin;
  }

  /// Update logged-in user's own PIN.
  Future<void> updatePin(String newPin) async {
    final current = state;
    if (current == null) return;

    final isar = ref.read(isarProvider);
    final hashedPin = await AuthService.hashPinAsync(newPin);

    current.pinHash = hashedPin;
    await isar.writeTxn(() async {
      await isar.appUsers.put(current);
    });

    state = current;
  }

  /// Directly set the logged-in user (used by AdminLoginScreen after
  /// email+password verification).
  void setUser(AppUser user) {
    _failedAttempts = 0;
    _lockedUntil = null;
    state = user;
    ref.read(sessionManagerProvider).startSession();
  }

  void logout() {
    ref.read(sessionManagerProvider).endSession();
    state = null;
  }

  bool get isOwner => state?.role == 'owner';
  bool get isLoggedIn => state != null;
}
