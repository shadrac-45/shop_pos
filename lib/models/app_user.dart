/// ============================================
/// AppUser Model — Isar Collection
/// ============================================
/// Represents a user (owner or cashier) of the
/// POS system. Authentication is via 4-digit PIN.
/// ============================================
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:isar/isar.dart';

part 'app_user.g.dart';

@collection
class AppUser {
  Id id = Isar.autoIncrement;

  /// Display name of the user.
  late String name;

  /// Role: "owner" or "cashier".
  @Index()
  late String role;

  /// SHA-256 hash of the 4-digit PIN.
  /// We never store the raw PIN.
  @Index(unique: true)
  late String pinHash;

  /// Whether this user account is active.
  bool isActive = true;

  /// When this user was created.
  DateTime createdAt = DateTime.now();

  // ── Computed Properties ──────────────────────

  /// Whether this user is an owner.
  @ignore
  bool get isOwner => role == 'owner';

  /// Whether this user is a cashier.
  @ignore
  bool get isCashier => role == 'cashier';

  // ── Static Helpers ──────────────────────────

  /// Hash a raw PIN string using SHA-256.
  /// Uses a salt prefix for basic security.
  static String hashPin(String pin) {
    const salt = 'ShopPOS_v1_salt_';
    final bytes = utf8.encode('$salt$pin');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify a raw PIN against a stored hash.
  static bool verifyPin(String rawPin, String storedHash) {
    return hashPin(rawPin) == storedHash;
  }

  @override
  String toString() => 'AppUser(id: $id, name: $name, role: $role)';
}
