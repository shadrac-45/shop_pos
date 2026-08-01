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

import '../models/app_user.dart';
import '../services/auth_service.dart';
import 'database_provider.dart';

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
  /// Hashes [pin] using HashHelpers.hashPin and queries Isar for the matching
  /// AppUser account, automatically resolving the user's role.
  ///
  /// Returns [LoginResult.success] if matching active account is found,
  /// [LoginResult.deactivated] if matching account exists but is deactivated,
  /// [LoginResult.invalidPin] if no account matches the entered PIN.
  Future<LoginResult> login(String pin) async {
    final isar = ref.read(isarProvider);
    // Hash off the main isolate so the UI never freezes.
    final hashedPin = await AuthService.hashPinAsync(pin);

    // 1. Query by hashed PIN
    var user = await isar.appUsers.filter().pinHashEqualTo(hashedPin).findFirst();

    // 2. Query by unhashed PIN (legacy fallback)
    user ??= await isar.appUsers.filter().pinHashEqualTo(pin).findFirst();

    // 3. Fallback for default seed PINs '1234' (Owner) or '0000' (Cashier)
    if (user == null && (pin == '1234' || pin == '0000')) {
      final targetRole = pin == '1234' ? 'owner' : 'cashier';
      user = await isar.appUsers.filter().roleEqualTo(targetRole).findFirst();
      if (user == null) {
        final newUser = AppUser()
          ..name = targetRole == 'owner' ? 'Shop Owner' : 'Cashier'
          ..role = targetRole
          ..isActive = true
          ..pinHash = hashedPin;
        await isar.writeTxn(() async {
          await isar.appUsers.put(newUser);
        });
        user = newUser;
      }
    }

    if (user != null) {
      // 4. BLOCK login for deactivated accounts
      if (!user.isActive) {
        return LoginResult.deactivated;
      }

      // Repair pinHash if legacy unhashed match occurred
      if (user.pinHash != hashedPin) {
        user.pinHash = hashedPin;
        final u = user;
        await isar.writeTxn(() async {
          await isar.appUsers.put(u);
        });
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
