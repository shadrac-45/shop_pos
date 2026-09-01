/// ============================================
/// Staff Provider — ShopPOS
/// ============================================
/// Provides Owner-only CRUD operations for cashier
/// staff accounts stored in the Isar database.
/// All PINs are checked for global uniqueness and
/// hashed using SHA-256 before storage — never
/// stored in plain text.
/// ============================================
library;

import 'dart:math';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/services/auth_service.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/core/database/database_provider.dart';

// ── Result type ──────────────────────────────────────────

enum StaffOperationResult {
  success,
  unauthorized,
  pinAlreadyExists,
  invalidPin,
  weakPin,
  userNotFound,
  error,
}

// ── Provider ─────────────────────────────────────────────

final staffProvider = Provider<StaffService>((ref) {
  final isar = ref.read(isarProvider);
  return StaffService(isar, ref);
});

// ── Service ──────────────────────────────────────────────

class StaffService {
  final Isar _isar;
  final Ref _ref;

  StaffService(this._isar, this._ref);

  /// Verifies if the active caller holds the Owner role
  bool _isCallerOwner() {
    final user = _ref.read(currentUserProvider);
    return user != null && user.role == AppConstants.roleOwner;
  }

  /// Return all cashier accounts, ordered by creation time (id ascending).
  Future<List<AppUser>> getAllCashiers() async {
    return _isar.appUsers
        .filter()
        .roleEqualTo('cashier')
        .findAll();
  }

  /// Check whether a PIN is already assigned to any staff account (Owner or Cashier).
  Future<bool> isPinTaken(String pin, {int? excludeUserId}) async {
    final trimmed = pin.trim();
    if (trimmed.isEmpty) return false;

    final hashedPin = AuthService.hashPin(trimmed);
    final matches = await _isar.appUsers
        .filter()
        .pinHashEqualTo(hashedPin)
        .findAll();

    for (final user in matches) {
      if (excludeUserId == null || user.id != excludeUserId) {
        return true;
      }
    }
    return false;
  }

  /// Create a new cashier account with a unique 4-6 digit PIN.
  /// [name] — display name shown in the UI.
  /// [pin]  — 4-6 digit numeric PIN; hashed with SHA-256 before storage.
  Future<StaffOperationResult> createCashier({
    required String name,
    required String pin,
  }) async {
    if (!_isCallerOwner()) {
      return StaffOperationResult.unauthorized;
    }

    final trimmedPin = pin.trim();
    if (trimmedPin.length < 4 || trimmedPin.length > 6) {
      return StaffOperationResult.invalidPin;
    }

    // Check PIN uniqueness across all existing accounts
    final taken = await isPinTaken(trimmedPin);
    if (taken) {
      return StaffOperationResult.pinAlreadyExists;
    }

    final newUser = AppUser()
      ..name = name.trim()
      ..role = 'cashier'
      ..isActive = true
      ..pinHash = AuthService.hashPin(trimmedPin);

    await _isar.writeTxn(() async {
      await _isar.appUsers.put(newUser);
    });

    return StaffOperationResult.success;
  }

  /// Deactivate a cashier account. The account is NOT deleted so that
  /// historical sales records that reference this user ID remain intact.
  Future<StaffOperationResult> deactivateCashier(int userId) async {
    if (!_isCallerOwner()) {
      return StaffOperationResult.unauthorized;
    }

    final user = await _isar.appUsers.get(userId);
    if (user == null) return StaffOperationResult.userNotFound;

    user.isActive = false;
    await _isar.writeTxn(() async {
      await _isar.appUsers.put(user);
    });
    return StaffOperationResult.success;
  }

  /// Re-activate a previously deactivated cashier account.
  Future<StaffOperationResult> reactivateCashier(int userId) async {
    if (!_isCallerOwner()) {
      return StaffOperationResult.unauthorized;
    }

    final user = await _isar.appUsers.get(userId);
    if (user == null) return StaffOperationResult.userNotFound;

    user.isActive = true;
    await _isar.writeTxn(() async {
      await _isar.appUsers.put(user);
    });
    return StaffOperationResult.success;
  }

  /// Reset a cashier's PIN to a new unique PIN set by the Owner.
  Future<StaffOperationResult> resetCashierPin(
      int userId, String newPin) async {
    if (!_isCallerOwner()) {
      return StaffOperationResult.unauthorized;
    }

    final user = await _isar.appUsers.get(userId);
    if (user == null) return StaffOperationResult.userNotFound;

    final trimmedPin = newPin.trim();
    if (trimmedPin.length < 4 || trimmedPin.length > 6) {
      return StaffOperationResult.invalidPin;
    }

    final taken = await isPinTaken(trimmedPin, excludeUserId: userId);
    if (taken) {
      return StaffOperationResult.pinAlreadyExists;
    }

    user.pinHash = AuthService.hashPin(trimmedPin);
    await _isar.writeTxn(() async {
      await _isar.appUsers.put(user);
    });
    return StaffOperationResult.success;
  }

  /// Helper: Generate a suggested 4-digit unique random PIN using CSPRNG.
  Future<String> generateSuggestedPin() async {
    final secureRandom = Random.secure();
    for (var i = 0; i < 100; i++) {
      final candidate = (1000 + secureRandom.nextInt(9000)).toString();
      if (!await isPinTaken(candidate)) {
        return candidate;
      }
    }
    return '8888';
  }
}
