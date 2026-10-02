/// ============================================
/// ActivityLog — ShopPOS Isar Model
/// ============================================
/// Append-only record of what staff did: logins,
/// logouts, sales, voids, refunds, stock changes,
/// staff and settings changes.
/// ============================================
library;

import 'package:isar/isar.dart';

part 'activity_log.g.dart';

class ActivityAction {
  ActivityAction._();

  static const login = 'login';
  static const logout = 'logout';
  static const sessionTimeout = 'session_timeout';
  static const loginFailed = 'login_failed';
  static const sale = 'sale';
  static const voidSale = 'void_sale';
  static const refund = 'refund';
  static const restock = 'restock';
  static const stockAdjustment = 'stock_adjustment';
  static const productCreated = 'product_created';
  static const productEdited = 'product_edited';
  static const productArchived = 'product_archived';
  static const productRestored = 'product_restored';
  static const expense = 'expense';
  static const shiftOpened = 'shift_opened';
  static const shiftClosed = 'shift_closed';
  static const staffChanged = 'staff_changed';
  static const pinChanged = 'pin_changed';
  static const passwordReset = 'password_reset';
  static const settingsChanged = 'settings_changed';
  static const backup = 'backup';
  static const restore = 'restore';
  static const sync = 'sync';

  static String label(String action) => switch (action) {
        login => 'Signed in',
        logout => 'Signed out',
        sessionTimeout => 'Signed out (inactive)',
        loginFailed => 'Failed sign-in',
        sale => 'Sale',
        voidSale => 'Voided sale',
        refund => 'Refund',
        restock => 'Restock',
        stockAdjustment => 'Stock adjustment',
        productCreated => 'Product added',
        productEdited => 'Product edited',
        productArchived => 'Product archived',
        productRestored => 'Product restored',
        expense => 'Expense',
        shiftOpened => 'Shift opened',
        shiftClosed => 'Shift closed',
        staffChanged => 'Staff change',
        pinChanged => 'PIN changed',
        passwordReset => 'Password reset',
        settingsChanged => 'Settings changed',
        backup => 'Backup',
        restore => 'Restore',
        sync => 'Sync',
        _ => action,
      };
}

@Collection()
class ActivityLog {
  Id id = Isar.autoIncrement;

  @Index()
  int userId = 0;

  String userName = '';

  /// One of [ActivityAction].
  @Index()
  late String action;

  String details = '';

  @Index()
  late DateTime timestamp;
}
