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
import 'package:shop_pos/core/utils/id_helpers.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';

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

  /// All staff accounts except the owner (cashiers, managers, stock
  /// clerks), ordered by creation time (id ascending).
  Future<List<AppUser>> getAllCashiers() async {
    return _isar.appUsers
        .filter()
        .not()
        .roleEqualTo(AppConstants.roleOwner)
        .findAll();
  }

  Future<void> _log(String details) => ActivityLogService.log(
      _isar, _ref.read(currentUserProvider), ActivityAction.staffChanged, details);

  /// The owner account can't be changed through staff management.
  Future<AppUser?> _staffMember(int userId) async {
    final user = await _isar.appUsers.get(userId);
    return (user == null || user.role == AppConstants.roleOwner) ? null : user;
  }

  /// Changes a staff member's role (cashier / manager / stock clerk).
  Future<StaffOperationResult> changeRole(int userId, String role) async {
    if (!_isCallerOwner()) return StaffOperationResult.unauthorized;
    if (!AppConstants.staffRoles.contains(role)) return StaffOperationResult.error;
    final user = await _staffMember(userId);
    if (user == null) return StaffOperationResult.userNotFound;
    final before = user.role;
    user
      ..role = role
      ..updatedAt = DateTime.now()
      ..isSynced = false;
    await _isar.writeTxn(() => _isar.appUsers.put(user));
    await _log('${user.name}: ${AppConstants.roleLabel(before)} → ${AppConstants.roleLabel(role)}');
    return StaffOperationResult.success;
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
    String role = AppConstants.roleCashier,
  }) async {
    if (!AppConstants.staffRoles.contains(role)) return StaffOperationResult.error;
    if (!_isCallerOwner()) {
      return StaffOperationResult.unauthorized;
    }

    final trimmedPin = pin.trim();
    if (trimmedPin.length < 4 ||
        trimmedPin.length > 6 ||
        AppConstants.defaultPins.contains(trimmedPin)) {
      return StaffOperationResult.invalidPin;
    }

    // Check PIN uniqueness across all existing accounts
    final taken = await isPinTaken(trimmedPin);
    if (taken) {
      return StaffOperationResult.pinAlreadyExists;
    }

    final newUser = AppUser()
      ..name = name.trim()
      ..role = role
      ..isActive = true
      ..pinHash = AuthService.hashPin(trimmedPin)
      ..uuid = IdHelpers.newUuid()
      ..updatedAt = DateTime.now();

    await _isar.writeTxn(() async {
      await _isar.appUsers.put(newUser);
    });
    await _log('Added ${AppConstants.roleLabel(role)} ${newUser.name}');

    return StaffOperationResult.success;
  }

  /// Deactivate a cashier account. The account is NOT deleted so that
  /// historical sales records that reference this user ID remain intact.
  Future<StaffOperationResult> deactivateCashier(int userId) async {
    if (!_isCallerOwner()) {
      return StaffOperationResult.unauthorized;
    }

    final user = await _staffMember(userId);
    if (user == null) return StaffOperationResult.userNotFound;

    user
      ..isActive = false
      ..updatedAt = DateTime.now()
      ..isSynced = false;
    await _isar.writeTxn(() async {
      await _isar.appUsers.put(user);
    });
    await _log('Deactivated ${user.name}');
    return StaffOperationResult.success;
  }

  /// Re-activate a previously deactivated cashier account.
  Future<StaffOperationResult> reactivateCashier(int userId) async {
    if (!_isCallerOwner()) {
      return StaffOperationResult.unauthorized;
    }

    final user = await _staffMember(userId);
    if (user == null) return StaffOperationResult.userNotFound;

    user
      ..isActive = true
      ..updatedAt = DateTime.now()
      ..isSynced = false;
    await _isar.writeTxn(() async {
      await _isar.appUsers.put(user);
    });
    await _log('Reactivated ${user.name}');
    return StaffOperationResult.success;
  }

  /// Reset a cashier's PIN to a new unique PIN set by the Owner.
  Future<StaffOperationResult> resetCashierPin(
      int userId, String newPin) async {
    if (!_isCallerOwner()) {
      return StaffOperationResult.unauthorized;
    }

    final user = await _staffMember(userId);
    if (user == null) return StaffOperationResult.userNotFound;

    final trimmedPin = newPin.trim();
    if (trimmedPin.length < 4 ||
        trimmedPin.length > 6 ||
        AppConstants.defaultPins.contains(trimmedPin)) {
      return StaffOperationResult.invalidPin;
    }

    final taken = await isPinTaken(trimmedPin, excludeUserId: userId);
    if (taken) {
      return StaffOperationResult.pinAlreadyExists;
    }

    user
      ..pinHash = AuthService.hashPin(trimmedPin)
      ..updatedAt = DateTime.now()
      ..isSynced = false;
    await _isar.writeTxn(() async {
      await _isar.appUsers.put(user);
    });
    await _log('Reset PIN for ${user.name}');
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
