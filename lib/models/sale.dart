/// ============================================
/// Sale Model — Isar Collection
/// ============================================
/// Represents a completed sale transaction.
/// Items are stored as JSON string for flexibility
/// and to avoid complex nested Isar relations.
/// ============================================
library;

import 'dart:convert';
import 'package:isar/isar.dart';

part 'sale.g.dart';

@collection
class Sale {
  Id id = Isar.autoIncrement;

  /// Timestamp when the sale was completed.
  @Index()
  late DateTime timestamp;

  /// PIN hash of the cashier who processed the sale.
  late String cashierPin;

  /// Name of the cashier (denormalized for fast display).
  late String cashierName;

  /// Total sale amount in local currency.
  late double totalAmount;

  /// Payment method: "cash", "momo", or "split".
  @Index()
  late String paymentType;

  /// Amount paid in cash (useful for split payments).
  double amountCash = 0.0;

  /// Amount paid in momo (useful for split payments).
  double amountMomo = 0.0;

  /// JSON string encoding the list of items sold.
  /// Format: [{"productId": 1, "name": "...", "price": 5.0, "qty": 2}, ...]
  late String itemsJson;

  /// Whether this sale has been synced to the remote server.
  bool isSynced = false;

  // ── Computed Properties ──────────────────────

  /// Decode itemsJson into a list of maps.
  @ignore
  List<Map<String, dynamic>> get items {
    try {
      final decoded = jsonDecode(itemsJson) as List;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Total number of individual items in this sale.
  @ignore
  int get totalItems {
    int count = 0;
    for (final item in items) {
      count += (item['qty'] as num?)?.toInt() ?? 0;
    }
    return count;
  }

  @override
  String toString() =>
      'Sale(id: $id, total: $totalAmount, items: ${items.length})';
}

/// Helper class representing a single item in a sale.
/// Used for building the items list before encoding to JSON.
class SaleItem {
  final int productId;
  final String name;
  final double price;
  int qty;

  SaleItem({
    required this.productId,
    required this.name,
    required this.price,
    this.qty = 1,
  });

  double get subtotal => price * qty;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'price': price,
        'qty': qty,
      };

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
        productId: json['productId'] as int,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
        qty: (json['qty'] as num).toInt(),
      );

  @override
  String toString() => 'SaleItem($name x$qty @ $price)';
}
