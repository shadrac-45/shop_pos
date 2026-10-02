/// ============================================
/// SaleItem — ShopPOS Isar Model
/// ============================================
/// One row per product line of a sale. Lets
/// per-product reports query and index by
/// product instead of decoding Sale.itemsJson.
/// ============================================
library;

import 'package:isar/isar.dart';

part 'sale_item.g.dart';

@Collection()
class SaleItem {
  Id id = Isar.autoIncrement;

  @Index()
  late int saleId;

  @Index()
  late int productId;

  late String productName;
  late int quantity;

  /// Selling price per unit at the time of sale.
  late double unitPrice;

  /// Cost per unit at the time of sale, if the product had one.
  double? unitCost;

  /// Discount applied to this whole line.
  double discount = 0;

  /// quantity × unitPrice − discount.
  late double lineTotal;

  /// Units of this line returned through refunds or a void.
  int refundedQty = 0;

  /// Money refunded for this line so far.
  double refundedAmount = 0;

  /// Copied from the sale so date-range product reports can use an index.
  @Index()
  late DateTime timestamp;

  int cashierId = 0;

  @ignore
  int get netQuantity => quantity - refundedQty;

  /// Line revenue after refunds, pro rata.
  @ignore
  double get netLineTotal =>
      quantity == 0 ? 0 : lineTotal * netQuantity / quantity;
}
