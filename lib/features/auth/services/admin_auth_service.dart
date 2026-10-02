/// ============================================
/// AdminAuthService — ShopPOS
/// ============================================
/// Handles email + password authentication for
/// the admin (owner) account.
/// ============================================
library;

import 'package:isar/isar.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';

enum PasswordResetResult {
  success,

  /// No active owner account with that email, or the PIN didn't match.
  /// (One result for both, so the form doesn't reveal which emails exist.)
  invalidCredentials,

  /// The owner's PIN is still a default PIN, which proves nothing.
  defaultPin,

  weakPassword,
}

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

  static const minPasswordLength = 8;

  /// Lets an owner who forgot their password set a new one by proving
  /// identity with their (non-default) owner PIN. The app is offline, so
  /// there is no email-based reset.
  static Future<PasswordResetResult> resetPasswordWithPin(
    Isar isar, {
    required String email,
    required String ownerPin,
    required String newPassword,
  }) async {
    if (newPassword.length < minPasswordLength) {
      return PasswordResetResult.weakPassword;
    }
    final owner = await isar.appUsers
        .filter()
        .emailEqualTo(email.trim().toLowerCase())
        .roleEqualTo(AppConstants.roleOwner)
        .isActiveEqualTo(true)
        .findFirst();
    if (owner == null || !HashHelpers.verifyPin(ownerPin.trim(), owner.pinHash)) {
      await ActivityLogService.log(isar, null, ActivityAction.loginFailed,
          'Failed password reset for ${email.trim()}');
      return PasswordResetResult.invalidCredentials;
    }
    if (HashHelpers.isDefaultPinHash(owner.pinHash)) {
      return PasswordResetResult.defaultPin;
    }

    owner
      ..passwordHash = HashHelpers.hashPassword(newPassword)
      ..updatedAt = DateTime.now()
      ..isSynced = false;
    await isar.writeTxn(() async {
      await isar.appUsers.put(owner);
      await isar.activityLogs.put(ActivityLogService.entry(
          owner, ActivityAction.passwordReset, 'Reset with owner PIN'));
    });
    return PasswordResetResult.success;
  }

  /// Changes the signed-in owner's password. Returns false if
  /// [currentPassword] is wrong.
  static Future<bool> changePassword(
    Isar isar,
    AppUser user, {
    required String currentPassword,
    required String newPassword,
  }) async {
    if (user.passwordHash == null ||
        !HashHelpers.verifyPassword(currentPassword, user.passwordHash!)) {
      return false;
    }
    if (newPassword.length < minPasswordLength) {
      throw ArgumentError('Password must be at least $minPasswordLength characters.');
    }
    user
      ..passwordHash = HashHelpers.hashPassword(newPassword)
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
