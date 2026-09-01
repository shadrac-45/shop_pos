/// ============================================
/// Auth Provider — ShopPOS
/// ============================================
/// Manages currently logged-in user state and
/// unified PIN-based authentication.
/// Blocks deactivated accounts from logging in.
/// ============================================
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/services/auth_service.dart';
import 'package:shop_pos/core/database/database_provider.dart';

// ── Result enum ──────────────────────────────────────────

enum LoginResult {
  success,
  invalidPin,
  deactivated,
}

// ── Provider ─────────────────────────────────────────────

final currentUserProvider =
    StateNotifierProvider<AuthNotifier, AppUser?>((ref) {
  return AuthNotifier(ref);
});

// ── Notifier ─────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AppUser?> {
  final Ref ref;

  AuthNotifier(this.ref) : super(null);

  /// Single PIN-based login for all staff accounts (Owner and Cashiers).
  /// Hashes [pin] using AuthService.hashPinAsync and queries Isar for the
  /// matching AppUser account, automatically resolving the user's role.
  ///
  /// Returns [LoginResult.success] if a matching active account is found,
  /// [LoginResult.deactivated] if the account exists but is deactivated,
  /// [LoginResult.invalidPin] if no account matches the entered PIN.
  ///
  /// Security notes:
  ///  - Only hashed PIN lookup is supported; plaintext comparisons are removed.
  ///  - There is no runtime seeding or PIN-bypass fallback. Default accounts
  ///    are created once at startup in main.dart via _seedDefaultUsers().
  Future<LoginResult> login(String pin) async {
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

      state = user;
      return LoginResult.success;
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

  void logout() => state = null;

  bool get isOwner => state?.role == 'owner';
  bool get isLoggedIn => state != null;
}
