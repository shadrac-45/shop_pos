/// ============================================
/// Product Model — Isar Collection
/// ============================================
/// Represents a product in the shop inventory.
/// Each product can have multiple Batch records
/// (for tracking expiry via FEFO).
/// ============================================
library;

import 'package:isar/isar.dart';

part 'product.g.dart';

@collection
class Product {
  Id id = Isar.autoIncrement;

  /// Display name of the product (e.g., "Pure Water")
  @Index(type: IndexType.value)
  late String name;

  /// Unit selling price in local currency (GH₵)
  late double price;

  /// Product category for filtering (e.g., "Beverages", "Food")
  @Index()
  late String category;

  /// ARGB color int for the quick-sale button on the cashier screen.
  /// Stored as int to avoid Isar serialization issues with Color.
  int quickButtonColor = 0xFF2196F3; // Default: blue

  /// Optional barcode string for scanner lookup.
  @Index(unique: false)
  String? barcode;

  /// Whether this product is active (soft delete support).
  bool isActive = true;

  /// ISO timestamp of when the product was created.
  DateTime createdAt = DateTime.now();

  /// ISO timestamp of last update.
  DateTime updatedAt = DateTime.now();

  // ── Computed Properties (ignored by Isar) ────────

  /// Total stock across all batches.
  /// Computed at read-time, not persisted.
  @ignore
  int totalStock = 0;

  /// The batch that expires soonest (for FEFO display).
  /// Set dynamically when loading product with batches.
  @ignore
  DateTime? soonestExpiry;

  /// Number of days until the soonest batch expires.
  @ignore
  int? get daysUntilExpiry {
    if (soonestExpiry == null) return null;
    return soonestExpiry!.difference(DateTime.now()).inDays;
  }

  /// Human-readable expiry status.
  @ignore
  String get expiryStatus {
    final days = daysUntilExpiry;
    if (days == null) return 'No stock';
    if (days < 0) return 'EXPIRED';
    if (days <= 7) return 'Expires in $days days';
    if (days <= 30) return 'Expires in $days days';
    return 'Good ($days days)';
  }

  @override
  String toString() => 'Product(id: $id, name: $name, price: $price)';
}
