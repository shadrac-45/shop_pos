import 'package:isar/isar.dart';
import 'product.dart';

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

  // Link back to product
  final IsarLink<Product> product = IsarLink<Product>();

  @ignore
  int get daysUntilExpiry => expiryDate.difference(DateTime.now()).inDays;

  @ignore
  bool get isExpired => daysUntilExpiry <= 0;
}
