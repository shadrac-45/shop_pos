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

  // Stable external identifier assigned on first catalog import. Lets a
  // re-import of the same spreadsheet update rows instead of duplicating
  // them, even when the product name is later edited by hand.
  String? importUuid;

  // Indexed so import can match a row by barcode/sku in O(log n) rather
  // than scanning every product. Isar indexes skip null values, so
  // products created without a barcode never collide here.
  @Index()
  String? barcode;

  @Index()
  String? sku;

  // Purchase cost per unit. Distinct from [price] (the selling price) and
  // only populated from spreadsheets that supply a cost column.
  double? costPrice;

  /// Stable ID used for sync and backups.
  @Index()
  String? uuid;

  /// Stock at or below this level counts as low stock (0 = no alert).
  int reorderLevel = 0;

  /// Archived products are hidden from the till and catalog but kept so
  /// past sales still resolve.
  @Index()
  bool isArchived = false;

  DateTime? updatedAt;
  bool isSynced = false;

  /// Photo on this device (absolute path in the app's documents folder).
  /// Not synced or included in backups.
  String? imagePath;

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

  /// Units that are not past their expiry date, i.e. sellable.
  @ignore
  int get sellableStock => batches
      .where((b) => b.quantity > 0 && !b.isExpired)
      .fold(0, (sum, b) => sum + b.quantity);

  @ignore
  bool get isLowStock => reorderLevel > 0 && totalStock <= reorderLevel;
}
