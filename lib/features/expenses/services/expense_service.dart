/// ============================================
/// Expense Service — ShopPOS
/// ============================================
library;

import 'package:isar/isar.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/utils/id_helpers.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/expenses/models/expense.dart';
import 'package:shop_pos/features/sales/services/sale_calculator.dart';
import 'package:shop_pos/features/shifts/services/shift_service.dart';

class ExpenseService {
  ExpenseService._();

  /// Records an expense. A till payout is linked to the user's open shift
  /// so the cash-up deducts it.
  static Future<Expense> add(
    Isar isar,
    AppUser? user, {
    required double amount,
    required String category,
    String description = '',
    bool paidFromTill = false,
    DateTime? at,
  }) async {
    Permissions.require(user, Permission.manageExpenses);
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be positive');
    }
    final shift =
        paidFromTill ? await ShiftService.currentShift(isar, user!.id) : null;
    final now = DateTime.now();
    final expense = Expense()
      ..uuid = IdHelpers.newUuid()
      ..amount = roundMoney(amount)
      ..category = category
      ..description = description.trim()
      ..paidFromTill = paidFromTill
      ..userId = user!.id
      ..shiftId = shift?.id
      ..timestamp = at ?? now
      ..updatedAt = now;
    await isar.writeTxn(() async {
      await isar.expenses.put(expense);
      await isar.activityLogs.put(ActivityLogService.entry(
          user,
          ActivityAction.expense,
          '${ExpenseCategory.label(category)} ${expense.amount.toStringAsFixed(2)}'
          '${paidFromTill ? ' (from till)' : ''}'));
    });
    return expense;
  }

  /// Soft-deletes an expense so it drops out of reports but can be synced.
  static Future<void> delete(Isar isar, AppUser? user, Expense expense) async {
    Permissions.require(user, Permission.manageExpenses);
    expense
      ..isDeleted = true
      ..updatedAt = DateTime.now()
      ..isSynced = false;
    await isar.writeTxn(() async {
      await isar.expenses.put(expense);
      await isar.activityLogs.put(ActivityLogService.entry(user,
          ActivityAction.expense, 'Deleted ${expense.amount.toStringAsFixed(2)}'));
    });
  }

  static Future<List<Expense>> inRange(Isar isar, DateTime from, DateTime to) =>
      isar.expenses
          .filter()
          .timestampBetween(from, to)
          .isDeletedEqualTo(false)
          .sortByTimestampDesc()
          .findAll();
}
