/// ============================================
/// Auth Service — ShopPOS
/// ============================================
/// Facade for authentication domain logic,
/// specifically PIN hashing and verification.
/// Centralizes the dependency on HashHelpers.
/// ============================================
library;

import '../utils/hash_helpers.dart';

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
}
