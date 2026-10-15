/// ============================================
/// Product Status — ShopPOS
/// ============================================
/// The single source of truth for a product's
/// stock and expiry state. Product cards, the
/// inventory list, filters, reports and daily
/// alerts all read from here, so they can never
/// disagree.
///
/// Stock (sellable = unexpired units):
///   0        → out of stock
///   1 … 4    → low stock          (below [kLowStockBelow])
///   5 +      → normal
/// An owner's per-product reorder level can raise
/// the low threshold (e.g. "warn me at 10").
///
/// Expiry (days left on a batch that has stock):
///   > 31     → normal
///   1 … 31   → expiring soon      ([kExpiringSoonDays])
///   passed   → expired (same rule the till uses
///              to refuse the sale: [Batch.isExpired])
///
/// Requires the product's batches to be loaded.
/// ============================================
library;

import 'package:shop_pos/features/products/models/product.dart';

/// Stock strictly below this is low stock.
const int kLowStockBelow = 5;

/// Stock expiring within this many days is "expiring soon".
const int kExpiringSoonDays = 31;

/// Expiry for stock that has no date (imported or added without one, items
/// that don't expire): far enough ahead that it never shows as expiring.
/// Local time, as the database returns dates.
final DateTime kNoExpiryDate = DateTime(2099, 12, 31, 23, 59, 59);

enum StockLevel { normal, low, out }

enum ExpiryState { normal, soon, expired }

/// Everything about a product's stock and expiry, worked out in ONE pass
/// over its batches. UI reads the cached copy ([ProductStatus.health]) so
/// a product card, its badges and the filter chips never re-scan batches.
class ProductHealth {
  /// Unexpired units on hand.
  final int sellable;

  /// Units on hand that are past their date (still need writing off).
  final int expiredUnits;

  /// Days until the next sellable batch expires; null if none.
  final int? daysToNextExpiry;

  final StockLevel stock;

  /// Stock management view: any expired stock on the shelf counts.
  final ExpiryState shelfExpiry;

  /// Till view: "expired" only when every unit on hand is past its date.
  final ExpiryState tillExpiry;

  const ProductHealth._({
    required this.sellable,
    required this.expiredUnits,
    required this.daysToNextExpiry,
    required this.stock,
    required this.shelfExpiry,
    required this.tillExpiry,
  });

  factory ProductHealth.of(Product p) {
    var sellable = 0;
    var expired = 0;
    int? nextDays;
    for (final b in p.batches) {
      if (b.quantity <= 0) continue;
      if (b.isExpired) {
        expired += b.quantity;
      } else {
        sellable += b.quantity;
        final d = b.daysUntilExpiry;
        if (nextDays == null || d < nextDays) nextDays = d;
      }
    }

    final StockLevel stock;
    if (sellable <= 0) {
      stock = StockLevel.out;
    } else if (sellable < kLowStockBelow || (p.reorderLevel > 0 && sellable <= p.reorderLevel)) {
      stock = StockLevel.low;
    } else {
      stock = StockLevel.normal;
    }

    final soon = nextDays != null && nextDays <= kExpiringSoonDays;
    return ProductHealth._(
      sellable: sellable,
      expiredUnits: expired,
      daysToNextExpiry: nextDays,
      stock: stock,
      shelfExpiry: expired > 0
          ? ExpiryState.expired
          : (soon ? ExpiryState.soon : ExpiryState.normal),
      tillExpiry: sellable <= 0 && expired > 0
          ? ExpiryState.expired
          : (soon ? ExpiryState.soon : ExpiryState.normal),
    );
  }

  /// Whether a badge should show (low/out stock, or expiring/expired).
  bool alert({bool forTill = false}) =>
      stock != StockLevel.normal ||
      (forTill ? tillExpiry : shelfExpiry) != ExpiryState.normal;
}

/// Per-object cache: products from the database stream are fresh objects
/// on every change, so a cached snapshot can never go stale by more than
/// the stream itself.
final Expando<ProductHealth> _healthCache = Expando<ProductHealth>('ProductHealth');

extension ProductStatus on Product {
  /// Cached snapshot for UI. Logic that mutates batches and re-checks
  /// should use the uncached getters below.
  ProductHealth get health => _healthCache[this] ??= ProductHealth.of(this);

  StockLevel get stockLevel => ProductHealth.of(this).stock;

  bool get isLowStock => stockLevel == StockLevel.low;
  bool get isOutOfStock => stockLevel == StockLevel.out;

  /// Low or out: belongs on a restock list.
  bool get needsRestock => stockLevel != StockLevel.normal;

  /// Units on hand that are past their date (still need writing off).
  int get expiredUnits => ProductHealth.of(this).expiredUnits;

  /// Days until the next sellable batch expires; null if none.
  int? get daysToNextExpiry => ProductHealth.of(this).daysToNextExpiry;

  /// For stock management: anything past its date on the shelf is
  /// "expired", even if fresher stock exists too.
  ExpiryState get expiryState => ProductHealth.of(this).shelfExpiry;

  /// For the till: only what can be sold matters. "Expired" only when
  /// every unit on hand is past its date.
  ExpiryState get sellableExpiryState => ProductHealth.of(this).tillExpiry;
}
