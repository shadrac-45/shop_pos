/// ============================================
/// Batch Model — Isar Collection
/// ============================================
/// Represents a single batch/restock of a product.
/// Each batch has its own quantity and expiry date.
/// The system uses FEFO (First Expired First Out)
/// to automatically sell the soonest-expiring batch.
/// ============================================
library;

import 'package:isar/isar.dart';

part 'batch.g.dart';

@collection
class Batch {
  Id id = Isar.autoIncrement;

  /// Foreign key linking to the parent Product.
  @Index()
  late int productId;

  /// Number of units remaining in this batch.
  late int quantity;

  /// When this batch expires.
  @Index()
  late DateTime expiryDate;

  /// When this batch was received/restocked.
  late DateTime restockDate;

  /// Optional note about the supplier or batch details.
  String? supplierNote;

  /// Whether this batch still has usable stock.
  @ignore
  bool get hasStock => quantity > 0;

  /// Whether this batch is expired.
  @ignore
  bool get isExpired => expiryDate.isBefore(DateTime.now());

  /// Days until this batch expires (negative = already expired).
  @ignore
  int get daysUntilExpiry => expiryDate.difference(DateTime.now()).inDays;

  @override
  String toString() =>
      'Batch(id: $id, productId: $productId, qty: $quantity, '
      'expiry: $expiryDate)';
}
