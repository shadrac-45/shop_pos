/// ============================================
/// Hash Helpers — ShopPOS
/// ============================================
/// PINs and passwords are stored as bcrypt
/// hashes (random salt per hash, deliberately
/// slow), never in plain text.
///
/// Hashes written by older versions (salted
/// SHA-256) still verify, and are upgraded to
/// bcrypt the next time the right PIN or
/// password is entered (see [needsRehash]).
///
/// Because every bcrypt hash has its own salt, a
/// PIN can't be found by looking its hash up:
/// use [findPinMatch] to test it against each
/// account instead.
///
/// The `...Async` variants run in a background
/// isolate so the UI never freezes.
/// ============================================
library;

import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shop_pos/core/constants/app_constants.dart';

class HashHelpers {
  HashHelpers._();

  /// bcrypt cost (2^n rounds). PINs are tried against every account at
  /// login, so they use a lower cost than passwords; a 4–6 digit PIN's real
  /// protection is the attempt lockout, not hash cost.
  static const pinLogRounds = 8;
  static const passwordLogRounds = 10;

  /// bcrypt only reads the first 72 bytes of its input.
  static const maxSecretBytes = 72;

  static bool _isBcrypt(String hash) => hash.startsWith(r'$2');

  /// True for hashes written by older versions, which should be replaced
  /// with bcrypt once the plain value is known (i.e. after a correct entry).
  static bool needsRehash(String storedHash) => !_isBcrypt(storedHash);

  // ── PINs ───────────────────────────────────────────────────────────

  static String hashPin(String rawPin) =>
      BCrypt.hashpw(rawPin, BCrypt.gensalt(logRounds: pinLogRounds));

  static Future<String> hashPinAsync(String rawPin) => compute(hashPin, rawPin);

  static bool verifyPin(String rawPin, String storedHash) {
    if (storedHash.isEmpty) return false;
    if (_isBcrypt(storedHash)) return _bcryptMatches(rawPin, storedHash);
    return _constantTimeEquals(_legacyPinHash(rawPin), storedHash);
  }

  /// True if [storedHash] is the hash of one of the publicly known
  /// default PINs seeded by older versions.
  static bool isDefaultPinHash(String storedHash) =>
      AppConstants.defaultPins.any((pin) => verifyPin(pin, storedHash));

  /// Index of the first hash in [hashes] that [rawPin] matches, or -1.
  /// Runs in a background isolate.
  static Future<int> findPinMatch(String rawPin, List<String> hashes) =>
      compute(_findPinMatch, (rawPin, hashes));

  static int _findPinMatch((String, List<String>) args) {
    final (pin, hashes) = args;
    for (var i = 0; i < hashes.length; i++) {
      if (verifyPin(pin, hashes[i])) return i;
    }
    return -1;
  }

  // ── Passwords ──────────────────────────────────────────────────────

  static String hashPassword(String rawPassword) =>
      BCrypt.hashpw(rawPassword, BCrypt.gensalt(logRounds: passwordLogRounds));

  static Future<String> hashPasswordAsync(String rawPassword) =>
      compute(hashPassword, rawPassword);

  static bool verifyPassword(String rawPassword, String storedHash) {
    if (storedHash.isEmpty) return false;
    if (utf8.encode(rawPassword).length > maxSecretBytes) return false;
    if (_isBcrypt(storedHash)) return _bcryptMatches(rawPassword, storedHash);
    return _constantTimeEquals(_legacyPasswordHash(rawPassword), storedHash);
  }

  static Future<bool> verifyPasswordAsync(String rawPassword, String storedHash) =>
      compute(_verifyPasswordArgs, (rawPassword, storedHash));

  static bool _verifyPasswordArgs((String, String) a) => verifyPassword(a.$1, a.$2);

  // ── Internals ──────────────────────────────────────────────────────

  static bool _bcryptMatches(String raw, String storedHash) {
    try {
      return _constantTimeEquals(BCrypt.hashpw(raw, storedHash), storedHash);
    } catch (_) {
      return false; // malformed hash or over-long input
    }
  }

  static bool _constantTimeEquals(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    var diff = x.length ^ y.length;
    for (var i = 0; i < x.length && i < y.length; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }

  /// Salted SHA-256 used before bcrypt; kept only to verify old hashes.
  static String _legacyPinHash(String rawPin) =>
      sha256.convert(utf8.encode('ShopPOS_Salt_2026_Ghana:$rawPin')).toString();

  static String _legacyPasswordHash(String rawPassword) =>
      'PWD:${sha256.convert(utf8.encode('ShopPOS_PwdSalt_2026_Ghana:$rawPassword'))}';

  /// For tests of the upgrade path only.
  @visibleForTesting
  static String legacyPinHashForTest(String rawPin) => _legacyPinHash(rawPin);

  @visibleForTesting
  static String legacyPasswordHashForTest(String raw) => _legacyPasswordHash(raw);
}
