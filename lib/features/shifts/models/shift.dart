/// ============================================
/// Shift — ShopPOS Isar Model
/// ============================================
/// A till session: opened with a cash float,
/// closed with a cash count. The cash-up compares
/// expected cash (float + cash sales − cash
/// refunds − till payouts) with what was counted.
/// ============================================
library;

import 'package:isar/isar.dart';

part 'shift.g.dart';

@Collection()
class Shift {
  Id id = Isar.autoIncrement;

  @Index()
  String? uuid;

  @Index()
  late int userId;

  @Index()
  late DateTime openedAt;
  DateTime? closedAt;

  late double openingFloat;

  // Filled in when the shift is closed.
  double cashSales = 0;
  double cashRefunds = 0;
  double tillPayouts = 0;
  double? expectedCash;
  double? countedCash;
  String? closingNote;

  bool isSynced = false;

  @ignore
  bool get isOpen => closedAt == null;

  /// Counted minus expected: negative means cash is short.
  @ignore
  double? get variance => (countedCash != null && expectedCash != null)
      ? countedCash! - expectedCash!
      : null;
}
