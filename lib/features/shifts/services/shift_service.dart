/// ============================================
/// Shift Service — ShopPOS
/// ============================================
/// Opening and closing till shifts, and the
/// end-of-shift cash-up:
///   expected cash = opening float
///                 + cash taken for sales
///                 − cash refunded
///                 − cash paid out of the till
/// ============================================
library;

import 'package:isar/isar.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/utils/id_helpers.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/expenses/models/expense.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/services/sale_calculator.dart';
import 'package:shop_pos/features/shifts/models/shift.dart';

class ShiftStateException implements Exception {
  final String message;
  ShiftStateException(this.message);
  @override
  String toString() => message;
}

class ShiftSummary {
  final double openingFloat;
  final double cashSales;
  final double cashRefunds;
  final double tillPayouts;
  final int saleCount;

  const ShiftSummary({
    required this.openingFloat,
    required this.cashSales,
    required this.cashRefunds,
    required this.tillPayouts,
    required this.saleCount,
  });

  double get expectedCash =>
      roundMoney(openingFloat + cashSales - cashRefunds - tillPayouts);
}

class ShiftService {
  ShiftService._();

  static Future<Shift?> currentShift(Isar isar, int userId) => isar.shifts
      .filter()
      .userIdEqualTo(userId)
      .closedAtIsNull()
      .findFirst();

  static Future<Shift> openShift(
    Isar isar,
    AppUser? user, {
    required double openingFloat,
  }) async {
    Permissions.require(user, Permission.runShift);
    if (openingFloat < 0) {
      throw ShiftStateException('Opening float cannot be negative.');
    }
    if (await currentShift(isar, user!.id) != null) {
      throw ShiftStateException('You already have an open shift.');
    }
    final shift = Shift()
      ..uuid = IdHelpers.newUuid()
      ..userId = user.id
      ..openedAt = DateTime.now()
      ..openingFloat = roundMoney(openingFloat);
    await isar.writeTxn(() async {
      await isar.shifts.put(shift);
      await isar.activityLogs.put(ActivityLogService.entry(user,
          ActivityAction.shiftOpened, 'Float ${shift.openingFloat.toStringAsFixed(2)}'));
    });
    return shift;
  }

  static Future<ShiftSummary> summarize(Isar isar, Shift shift) async {
    final sales = await isar.sales.filter().shiftIdEqualTo(shift.id).findAll();
    final cashSales = sales.fold<double>(
      0,
      (sum, s) =>
          sum +
          s.effectivePayments
              .where((p) => p.method == AppConstants.paymentCash)
              .fold<double>(0, (a, p) => a + p.amount),
    );

    // Refunds made during this shift, possibly on sales from earlier shifts.
    final refundedSales = await isar.sales
        .filter()
        .refundsElement((r) => r.shiftIdEqualTo(shift.id))
        .findAll();
    final cashRefunds = refundedSales.fold<double>(
      0,
      (sum, s) =>
          sum +
          s.refunds
              .where((r) =>
                  r.shiftId == shift.id && r.method == AppConstants.paymentCash)
              .fold<double>(0, (a, r) => a + r.amount),
    );

    final payouts = await isar.expenses
        .filter()
        .shiftIdEqualTo(shift.id)
        .paidFromTillEqualTo(true)
        .isDeletedEqualTo(false)
        .findAll();
    final tillPayouts = payouts.fold<double>(0, (s, e) => s + e.amount);

    return ShiftSummary(
      openingFloat: shift.openingFloat,
      cashSales: roundMoney(cashSales),
      cashRefunds: roundMoney(cashRefunds),
      tillPayouts: roundMoney(tillPayouts),
      saleCount: sales.length,
    );
  }

  /// Closes [shift] with the cash [countedCash] found in the till.
  /// The shift's own user, a manager or the owner may close it.
  static Future<Shift> closeShift(
    Isar isar,
    AppUser? user, {
    required Shift shift,
    required double countedCash,
    String? note,
  }) async {
    Permissions.require(user, Permission.runShift);
    if (shift.userId != user!.id &&
        !Permissions.can(user, Permission.viewReports)) {
      throw PermissionDeniedException(Permission.runShift, user.role);
    }
    if (!shift.isOpen) throw ShiftStateException('This shift is already closed.');
    if (countedCash < 0) {
      throw ShiftStateException('Counted cash cannot be negative.');
    }

    final summary = await summarize(isar, shift);
    shift
      ..closedAt = DateTime.now()
      ..cashSales = summary.cashSales
      ..cashRefunds = summary.cashRefunds
      ..tillPayouts = summary.tillPayouts
      ..expectedCash = summary.expectedCash
      ..countedCash = roundMoney(countedCash)
      ..closingNote = (note == null || note.trim().isEmpty) ? null : note.trim()
      ..isSynced = false;

    await isar.writeTxn(() async {
      await isar.shifts.put(shift);
      await isar.activityLogs.put(ActivityLogService.entry(
          user,
          ActivityAction.shiftClosed,
          'Expected ${summary.expectedCash.toStringAsFixed(2)}, '
          'counted ${shift.countedCash!.toStringAsFixed(2)}'));
    });
    return shift;
  }

  static Future<List<Shift>> recentShifts(Isar isar, {int? userId, int limit = 50}) {
    final q = isar.shifts.filter().idGreaterThan(0);
    return (userId == null ? q : q.userIdEqualTo(userId))
        .sortByOpenedAtDesc()
        .limit(limit)
        .findAll();
  }
}
