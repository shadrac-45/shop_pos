import 'package:isar/isar.dart';

part 'app_user.g.dart';

@Collection()
class AppUser {
  Id id = Isar.autoIncrement;

  late String pinHash;
  late String role; // "owner" or "cashier"
  late String name;

  /// Optional username for staff accounts created by the Owner.
  /// Null for legacy PIN-only accounts (e.g., the seeded owner/cashier).
  @Index(unique: true, replace: true)
  String? username;

  /// Whether this account is active. Owners can deactivate cashier accounts
  /// without deleting them (preserving sales history references).
  bool isActive = true;
}
