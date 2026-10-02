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

  /// BCrypt-style password hash for admin email+password login.
  /// Uses HashHelpers.hashPassword() (SHA-256 with domain salt).
  /// Null for cashier / staff accounts that use PIN only.
  String? passwordHash;

  /// Whether this account is active. Owners can deactivate cashier accounts
  /// without deleting them (preserving sales history references).
  bool isActive = true;

  /// Stable ID used for sync and backups.
  String? uuid;

  DateTime? updatedAt;
  bool isSynced = false;
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

  static Future<bool> isEmailTaken(
    Isar isar,
    String email, {
    int? excludeId,
  }) async {
    final existing =
        await isar.appUsers.filter().emailEqualTo(email).findFirst();
    return existing != null && existing.id != excludeId;
  }
}
