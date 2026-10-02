import 'package:isar/isar.dart';
import 'package:shop_pos/features/products/models/product.dart';

part 'batch.g.dart';

@Collection()
class Batch {
  Id id = Isar.autoIncrement;

  @Index()
  late int productId;

  late int quantity;
  late DateTime expiryDate;
  late DateTime restockDate;
  String? supplierNote;

  /// Purchase cost per unit for this delivery, if known.
  double? unitCost;

  /// Stable ID used for sync and backups.
  @Index()
  String? uuid;

  DateTime? updatedAt;
  bool isSynced = false;

  // Link back to product
  final IsarLink<Product> product = IsarLink<Product>();

  @ignore
  int get daysUntilExpiry => expiryDate.difference(DateTime.now()).inDays;

  @ignore
  bool get isExpired => daysUntilExpiry <= 0;
}
