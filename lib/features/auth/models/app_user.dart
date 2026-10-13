import 'package:isar/isar.dart';

part 'app_user.g.dart';

@Collection()
class AppUser {
  Id id = Isar.autoIncrement;

  late String pinHash;
  late String role; // 'owner', 'cashier', 'manager', 'stock_clerk'
  late String name;

  /// Optional username for staff accounts created by the Owner.
  /// Null for legacy PIN-only accounts (e.g., the seeded owner/cashier).
  ///
  /// NOTE: intentionally NOT a unique index. Isar treats `null` as a real
  /// indexed value, so a `unique: true` index on a nullable field causes
  /// every null-username row to collide with each other. Combined with
  /// `replace: true`, each new user with a null username silently deleted
  /// the previous one. Uniqueness (when a username IS set) must instead be
  /// enforced in application code — see isUsernameTaken() usage below.
  @Index()
  String? username;

  /// Email address for admin (owner) accounts — used for email+password login.
  /// Null for cashier / staff accounts that use PIN only.
  ///
  /// NOTE: same reasoning as `username` above — indexed for fast lookup,
  /// but NOT unique at the DB level, to avoid the null-collision bug.
  @Index()
  String? email;

  /// bcrypt hash of the admin password (see HashHelpers.hashPassword).
  /// Null for cashier / staff accounts that use PIN only.
  String? passwordHash;

  /// Bumped whenever this account's password or PIN is reset or changed.
  /// A session started under an older version is ended (see
  /// AuthNotifier.checkSessionStillValid).
  int credentialVersion = 0;

  /// Whether this account is active. Owners can deactivate cashier accounts
  /// without deleting them (preserving sales history references).
  bool isActive = true;

  /// Stable ID used for sync and backups.
  String? uuid;

  DateTime? updatedAt;

  /// Local user id of whoever last changed this account (themselves for a
  /// PIN change; the owner/manager for staff changes).
  int? modifiedBy;
  bool isSynced = false;

  /// This person's ShopPOS Cloud session on THIS till (never synced).
  /// Their changes are uploaded with it, so the cloud knows who made them.
  String? cloudToken;
  DateTime? cloudTokenExpiresAt;
}

/// Application-level uniqueness helpers.
/// Call these before saving a user whenever `username` or `email` is set,
/// since the DB index no longer enforces uniqueness for you.
class AppUserUniqueness {
  AppUserUniqueness._();

  static Future<bool> isUsernameTaken(
    Isar isar,
    String username, {
    int? excludeId,
  }) async {
    final existing =
        await isar.appUsers.filter().usernameEqualTo(username).findFirst();
    return existing != null && existing.id != excludeId;
  }
}
