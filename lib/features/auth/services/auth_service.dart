/// ============================================
/// Auth Service — ShopPOS
/// ============================================
/// Facade for authentication domain logic:
/// PIN hashing, verification and lookup.
/// Centralizes the dependency on HashHelpers.
/// ============================================
library;

import 'package:isar/isar.dart';

import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';

class AuthService {
  AuthService._();

  /// Hash a raw PIN string synchronously.
  static String hashPin(String pin) => HashHelpers.hashPin(pin);

  /// Hash a raw PIN string asynchronously (off-thread via compute).
  static Future<String> hashPinAsync(String pin) =>
      HashHelpers.hashPinAsync(pin);

  /// Verify if a raw PIN matches a stored hash.
  static bool verifyPin(String raw, String hash) =>
      HashHelpers.verifyPin(raw, hash);

  /// The account whose PIN is [pin], or null. Each account's hash has its
  /// own salt, so the PIN is checked against every account (off-thread).
  /// [excludeUserId] skips one account (e.g. the one changing its PIN).
  static Future<AppUser?> findUserByPin(Isar isar, String pin, {int? excludeUserId}) async {
    final users = (await isar.appUsers.where().findAll())
        .where((u) => u.id != excludeUserId)
        .toList();
    if (users.isEmpty) return null;
    final index = await HashHelpers.findPinMatch(pin, [for (final u in users) u.pinHash]);
    return index < 0 ? null : users[index];
  }

  /// Replaces an old-format hash with bcrypt now that the PIN is known.
  static Future<void> upgradePinHashIfNeeded(Isar isar, AppUser user, String pin) async {
    if (!HashHelpers.needsRehash(user.pinHash)) return;
    user.pinHash = await HashHelpers.hashPinAsync(pin);
    await isar.writeTxn(() => isar.appUsers.put(user));
  }
}
