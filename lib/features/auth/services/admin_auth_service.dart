/// ============================================
/// AdminAuthService — ShopPOS
/// ============================================
/// Handles email + password authentication for
/// the admin (owner) account.
/// ============================================
library;

import 'package:isar/isar.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';

class AdminAuthService {
  AdminAuthService._();

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

    if (user == null) return null;
    if (user.passwordHash == null) return null;

    final valid = HashHelpers.verifyPassword(password, user.passwordHash!);
    return valid ? user : null;
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
    user.passwordHash = HashHelpers.hashPassword(password);
    await isar.writeTxn(() async => isar.appUsers.put(user));
  }
}
