/// ============================================
/// Permissions — ShopPOS
/// ============================================
/// Single source of truth for what each role may
/// do. Screens use [can] to decide what to show;
/// services call [Permissions.require] before
/// writing, so a hidden button is never the only
/// thing stopping an action.
/// ============================================
library;

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';

enum Permission {
  /// Ring up sales.
  sell,

  /// Give line or whole-sale discounts at checkout.
  discount,

  /// See sales by every cashier (reports, all-sales history).
  viewReports,

  /// Add and edit products, prices and categories.
  manageProducts,

  /// Receive new stock (restock batches).
  restock,

  /// Adjust stock for damage, loss, theft, count corrections, write-offs.
  adjustStock,

  /// Void a sale or refund items.
  voidAndRefund,

  /// Record expenses and till payouts.
  manageExpenses,

  /// Create, deactivate and reset PINs for staff.
  manageStaff,

  /// Change store profile, tax, payment methods, backend, backups.
  manageSettings,

  /// Read the staff activity log.
  viewActivityLog,

  /// Open and close a till shift.
  runShift,
}

class PermissionDeniedException implements Exception {
  final Permission permission;
  final String? role;
  PermissionDeniedException(this.permission, this.role);

  @override
  String toString() =>
      'Your role (${role ?? 'signed out'}) is not allowed to ${permission.name}.';
}

class Permissions {
  Permissions._();

  static const Map<String, Set<Permission>> _byRole = {
    AppConstants.roleOwner: {...Permission.values},
    AppConstants.roleManager: {
      Permission.sell,
      Permission.discount,
      Permission.viewReports,
      Permission.manageProducts,
      Permission.restock,
      Permission.adjustStock,
      Permission.voidAndRefund,
      Permission.manageExpenses,
      Permission.viewActivityLog,
      Permission.runShift,
    },
    AppConstants.roleStockClerk: {
      Permission.restock,
      Permission.adjustStock,
    },
    AppConstants.roleCashier: {
      Permission.sell,
      Permission.runShift,
    },
  };

  static bool roleCan(String? role, Permission permission) =>
      _byRole[role]?.contains(permission) ?? false;

  /// True if [user] is signed in, active and allowed [permission].
  static bool can(AppUser? user, Permission permission) =>
      user != null && user.isActive && roleCan(user.role, permission);

  /// Throws [PermissionDeniedException] unless [user] may [permission].
  static void require(AppUser? user, Permission permission) {
    if (!can(user, permission)) {
      throw PermissionDeniedException(permission, user?.role);
    }
  }
}
