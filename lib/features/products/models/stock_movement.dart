/// ============================================
/// StockMovement — ShopPOS Isar Model
/// ============================================
/// Append-only ledger of every change to stock:
/// sales, restocks, adjustments, refunds, voids,
/// imports. Batch quantities are still updated in
/// place for speed; this ledger is the audit trail
/// of who changed what, when and why.
/// ============================================
library;

import 'package:isar/isar.dart';

part 'stock_movement.g.dart';

class StockMovementType {
  StockMovementType._();

  static const sale = 'sale';
  static const restock = 'restock';
  static const adjustment = 'adjustment';
  static const refund = 'refund';
  static const voidSale = 'void';
  static const import = 'import';
  static const initial = 'initial';

  static String label(String type) => switch (type) {
        sale => 'Sale',
        restock => 'Restock',
        adjustment => 'Adjustment',
        refund => 'Refund',
        voidSale => 'Void',
        import => 'Import',
        initial => 'Opening stock',
        _ => type,
      };
}

/// Why stock was adjusted by hand.
class AdjustmentReason {
  AdjustmentReason._();

  static const damage = 'damage';
  static const loss = 'loss';
  static const theft = 'theft';
  static const expired = 'expired';
  static const countCorrection = 'count_correction';
  static const other = 'other';

  static const all = [damage, loss, theft, expired, countCorrection, other];

  static String label(String reason) => switch (reason) {
        damage => 'Damaged',
        loss => 'Lost',
        theft => 'Theft',
        expired => 'Expired write-off',
        countCorrection => 'Stock count correction',
        other => 'Other',
        _ => reason,
      };
}

@Collection()
class StockMovement {
  Id id = Isar.autoIncrement;

  @Index()
  String? uuid;

  @Index()
  late int productId;

  /// Batch the change applied to (null when the batch was later removed).
  int? batchId;

  /// Signed change: negative removes stock, positive adds it.
  late int quantityChange;

  /// One of [StockMovementType].
  late String type;

  /// One of [AdjustmentReason], for adjustments.
  String? reason;

  String? note;

  /// Staff member who made the change (0 = system).
  int userId = 0;

  /// Related sale, for sale / refund / void movements.
  int? saleId;

  @Index()
  late DateTime timestamp;

  bool isSynced = false;
}
