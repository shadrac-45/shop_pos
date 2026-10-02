/// ============================================
/// Expense — ShopPOS Isar Model
/// ============================================
/// Money spent by the shop: supplier payments,
/// transport, utilities, cash taken out of the
/// till, etc. Feeds net-profit reports and the
/// end-of-shift cash-up.
/// ============================================
library;

import 'package:isar/isar.dart';

part 'expense.g.dart';

class ExpenseCategory {
  ExpenseCategory._();

  static const stock = 'stock_purchase';
  static const transport = 'transport';
  static const utilities = 'utilities';
  static const rent = 'rent';
  static const wages = 'wages';
  static const supplies = 'supplies';
  static const other = 'other';

  static const all = [stock, transport, utilities, rent, wages, supplies, other];

  static String label(String category) => switch (category) {
        stock => 'Stock purchase',
        transport => 'Transport',
        utilities => 'Utilities',
        rent => 'Rent',
        wages => 'Wages',
        supplies => 'Shop supplies',
        other => 'Other',
        _ => category,
      };
}

@Collection()
class Expense {
  Id id = Isar.autoIncrement;

  @Index()
  String? uuid;

  late double amount;

  /// One of [ExpenseCategory].
  late String category;

  String description = '';

  /// True when the cash came out of the till (a payout). These reduce the
  /// cash expected at shift close.
  bool paidFromTill = false;

  int userId = 0;

  /// Shift that was open when a till payout was made.
  int? shiftId;

  @Index()
  late DateTime timestamp;

  bool isDeleted = false;
  bool isSynced = false;
  DateTime? updatedAt;
}
