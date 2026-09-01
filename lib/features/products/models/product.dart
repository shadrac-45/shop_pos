import 'package:isar/isar.dart';
import 'package:shop_pos/features/products/models/batch.dart';

part 'product.g.dart';

@Collection()
class Product {
  Id id = Isar.autoIncrement;

  late String name;
  late double price;
  late String category;
  int quickButtonColor = 0xFF4CAF50; // default green

  @Backlink(to: 'product')
  final IsarLinks<Batch> batches = IsarLinks<Batch>();

  // Computed properties
  // NOTE: These require the 'batches' link to be preloaded (or queried fresh).
  // Providers do NOT preload by default — see cart_provider.dart for fix.
  @ignore
  double get totalStock =>
      batches.fold(0.0, (sum, batch) => sum + batch.quantity);

  @ignore
  Batch? get soonestExpiryBatch {
    final activeBatches = batches.where((b) => b.quantity > 0).toList();
    if (activeBatches.isEmpty) return null;
    activeBatches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return activeBatches.first;
  }

  @ignore
  int get daysUntilExpiry {
    if (soonestExpiryBatch == null) return 999;
    final difference =
        soonestExpiryBatch!.expiryDate.difference(DateTime.now()).inDays;
    return difference;
  }

  @ignore
  bool get isExpired => daysUntilExpiry <= 0;
}
