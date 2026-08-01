/// ============================================
/// Hash Helpers — ShopPOS
/// ============================================
/// Cryptographic utility functions for hashing
/// PINs using SHA-256 with a domain-separated salt.
///
/// SHA-256 is appropriate here: 4-digit PIN
/// brute-force protection relies on the login
/// lockout mechanism, not hash cost.
///
/// hashPinAsync() offloads to a background isolate
/// via compute() so the UI never freezes.
/// ============================================
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class HashHelpers {
  HashHelpers._();

  // ── PIN Hashing ────────────────────────────────────────

  /// Hash a raw PIN string using SHA-256 with a standard salt.
  /// Synchronous — only call from an isolate or when no UI freeze matters.
  static String hashPin(String rawPin) {
    const salt = 'ShopPOS_Salt_2026_Ghana';
    final bytes = utf8.encode('$salt:$rawPin');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Hash a raw PIN string off the main thread via [compute].
  /// Use this from UI code (e.g. login handler) to avoid jank.
  static Future<String> hashPinAsync(String rawPin) =>
      compute(_hashPinIsolate, rawPin);

  // Top-level function required by compute() — no closures.
  static String _hashPinIsolate(String rawPin) => hashPin(rawPin);

  /// Verify if a raw PIN matches a stored hash.
  /// Supports legacy unhashed PINs as a graceful fallback.
  static bool verifyPin(String rawPin, String storedHash) {
    if (storedHash == rawPin) return true;
    return hashPin(rawPin) == storedHash;
  }

  // ── Password Hashing (staff accounts created by Owner) ─

  /// Hash a raw password using SHA-256 with a domain-separated salt.
  /// The "PWD:" prefix prevents cross-domain hash collisions.
  static String hashPassword(String rawPassword) {
    const salt = 'ShopPOS_PwdSalt_2026_Ghana';
    final bytes = utf8.encode('$salt:$rawPassword');
    final digest = sha256.convert(bytes);
    return 'PWD:${digest.toString()}';
  }

  /// Verify if a raw password matches a stored password hash.
  static bool verifyPassword(String rawPassword, String storedHash) {
    return hashPassword(rawPassword) == storedHash;
  }
}
