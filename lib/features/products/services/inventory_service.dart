/// ============================================
/// Inventory Service — ShopPOS
/// ============================================
/// Every change to stock goes through here, so
/// each one is permission-checked and leaves a
/// StockMovement (who, what, when, why).
///
/// Methods named `...InTxn` must be called inside
/// an existing `isar.writeTxn` (Isar transactions
/// can't nest); the rest open their own.
/// ============================================
library;

import 'package:isar/isar.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/utils/id_helpers.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/stock_movement.dart';

class InsufficientStockException implements Exception {
  final String productName;
  final int requested;
  final int available;
  InsufficientStockException(this.productName, this.requested, this.available);

  @override
  String toString() =>
      'Not enough "$productName" in stock: $requested requested, $available available.';
}

/// Input for creating or editing a product.
class ProductInput {
  final String name;
  final double price;
  final String category;
  final int quickButtonColor;
  final double? costPrice;
  final String? barcode;
  final String? sku;
  final int reorderLevel;

  const ProductInput({
    required this.name,
    required this.price,
    required this.category,
    required this.quickButtonColor,
    this.costPrice,
    this.barcode,
    this.sku,
    this.reorderLevel = 0,
  });
}

class InventoryService {
  InventoryService._();

  // ── Reading ─────────────────────────────────────────────────────────

  /// Batches with stock, soonest expiry first.
  static Future<List<Batch>> _stockedBatches(Isar isar, int productId) =>
      isar.batchs
          .filter()
          .productIdEqualTo(productId)
          .quantityGreaterThan(0)
          .sortByExpiryDate()
          .findAll();

  /// Units that can be sold now (excludes expired batches).
  static Future<int> sellableQuantity(Isar isar, int productId) async {
    final batches = await _stockedBatches(isar, productId);
    return batches
        .where((b) => !b.isExpired)
        .fold<int>(0, (sum, b) => sum + b.quantity);
  }

  static Future<List<StockMovement>> movementsFor(Isar isar, int productId) =>
      isar.stockMovements
          .filter()
          .productIdEqualTo(productId)
          .sortByTimestampDesc()
          .findAll();

  /// Products at or below their reorder level (archived ones excluded).
  /// [products] must have their batches loaded.
  static List<Product> lowStock(Iterable<Product> products) => products
      .where((p) => !p.isArchived && p.isLowStock)
      .toList()
    ..sort((a, b) => a.totalStock.compareTo(b.totalStock));

  // ── Deduction (sales, negative adjustments) ─────────────────────────

  /// Removes [quantity] of [productId] from its batches, soonest expiry
  /// first, and records one movement per batch touched. Expired batches
  /// are skipped unless [includeExpired]. Throws
  /// [InsufficientStockException] (writing nothing) if there isn't enough.
  static Future<List<StockMovement>> deductFefoInTxn(
    Isar isar, {
    required int productId,
    required String productName,
    required int quantity,
    required String type,
    required int userId,
    int? saleId,
    String? reason,
    String? note,
    bool includeExpired = false,
    DateTime? at,
  }) async {
    final batches = (await _stockedBatches(isar, productId))
        .where((b) => includeExpired || !b.isExpired)
        .toList();
    final available = batches.fold<int>(0, (s, b) => s + b.quantity);
    if (available < quantity) {
      throw InsufficientStockException(productName, quantity, available);
    }

    final now = at ?? DateTime.now();
    final movements = <StockMovement>[];
    var remaining = quantity;
    for (final batch in batches) {
      if (remaining == 0) break;
      final take = remaining < batch.quantity ? remaining : batch.quantity;
      batch
        ..quantity -= take
        ..updatedAt = now
        ..isSynced = false;
      await isar.batchs.put(batch);
      remaining -= take;
      movements.add(_movement(
        productId: productId,
        batchId: batch.id,
        change: -take,
        type: type,
        userId: userId,
        saleId: saleId,
        reason: reason,
        note: note,
        at: now,
      ));
    }
    await isar.stockMovements.putAll(movements);
    await _touchProduct(isar, productId, now);
    return movements;
  }

  /// Adds [quantity] back to the given batch, or to the latest-expiring
  /// batch if it no longer exists, creating one if the product has none.
  static Future<StockMovement> addToBatchInTxn(
    Isar isar, {
    required int productId,
    required int quantity,
    required String type,
    required int userId,
    int? batchId,
    int? saleId,
    String? reason,
    String? note,
  }) async {
    final now = DateTime.now();
    Batch? batch = batchId == null ? null : await isar.batchs.get(batchId);
    batch ??= await isar.batchs
        .filter()
        .productIdEqualTo(productId)
        .sortByExpiryDateDesc()
        .findFirst();

    if (batch == null) {
      final product = await isar.products.get(productId);
      batch = Batch()
        ..productId = productId
        ..quantity = 0
        ..expiryDate = now.add(const Duration(days: 365))
        ..restockDate = now
        ..uuid = IdHelpers.newUuid();
      await isar.batchs.put(batch);
      if (product != null) {
        batch.product.value = product;
        await batch.product.save();
      }
    }

    batch
      ..quantity += quantity
      ..updatedAt = now
      ..isSynced = false;
    await isar.batchs.put(batch);

    final movement = _movement(
      productId: productId,
      batchId: batch.id,
      change: quantity,
      type: type,
      userId: userId,
      saleId: saleId,
      reason: reason,
      note: note,
      at: now,
    );
    await isar.stockMovements.put(movement);
    await _touchProduct(isar, productId, now);
    return movement;
  }

  // ── Products ────────────────────────────────────────────────────────

  /// Barcodes and SKUs must identify one product, or scanning is ambiguous.
  static Future<void> _checkUniqueCodes(Isar isar, ProductInput input, {int? excludeId}) async {
    final barcode = input.barcode?.trim();
    if (barcode != null && barcode.isNotEmpty) {
      final other = await isar.products.filter().barcodeEqualTo(barcode).findFirst();
      if (other != null && other.id != excludeId) {
        throw ArgumentError('Barcode $barcode is already used by "${other.name}".');
      }
    }
    final sku = input.sku?.trim();
    if (sku != null && sku.isNotEmpty) {
      final other = await isar.products.filter().skuEqualTo(sku).findFirst();
      if (other != null && other.id != excludeId) {
        throw ArgumentError('SKU $sku is already used by "${other.name}".');
      }
    }
  }

  static Future<Product> createProduct(
    Isar isar,
    AppUser? user,
    ProductInput input, {
    int initialQuantity = 0,
    DateTime? expiryDate,
    String? supplierNote,
  }) async {
    Permissions.require(user, Permission.manageProducts);
    await _checkUniqueCodes(isar, input);
    final now = DateTime.now();
    final product = Product()..uuid = IdHelpers.newUuid();
    _apply(product, input, now);

    await isar.writeTxn(() async {
      await isar.products.put(product);
      if (initialQuantity > 0) {
        await _newBatchInTxn(
          isar,
          product: product,
          quantity: initialQuantity,
          expiryDate: expiryDate ?? now.add(const Duration(days: 365)),
          supplierNote: supplierNote,
          unitCost: input.costPrice,
          type: StockMovementType.initial,
          userId: user?.id ?? 0,
        );
      }
      await isar.activityLogs.put(ActivityLogService.entry(
          user, ActivityAction.productCreated, product.name));
    });
    return product;
  }

  static Future<void> updateProduct(
    Isar isar,
    AppUser? user,
    Product product,
    ProductInput input,
  ) async {
    Permissions.require(user, Permission.manageProducts);
    await _checkUniqueCodes(isar, input, excludeId: product.id);
    final before = '${product.name} @ ${product.price}';
    _apply(product, input, DateTime.now());
    await isar.writeTxn(() async {
      await isar.products.put(product);
      await isar.activityLogs.put(ActivityLogService.entry(
          user,
          ActivityAction.productEdited,
          '$before → ${product.name} @ ${product.price}'));
    });
  }

  /// Hides a product from the till and catalog, or brings it back.
  static Future<void> setArchived(
    Isar isar,
    AppUser? user,
    Product product,
    bool archived,
  ) async {
    Permissions.require(user, Permission.manageProducts);
    product
      ..isArchived = archived
      ..updatedAt = DateTime.now()
      ..isSynced = false;
    await isar.writeTxn(() async {
      await isar.products.put(product);
      await isar.activityLogs.put(ActivityLogService.entry(
          user,
          archived
              ? ActivityAction.productArchived
              : ActivityAction.productRestored,
          product.name));
    });
  }

  // ── Stock in ────────────────────────────────────────────────────────

  static Future<Batch> restock(
    Isar isar,
    AppUser? user, {
    required Product product,
    required int quantity,
    required DateTime expiryDate,
    String? supplierNote,
    double? unitCost,
  }) async {
    Permissions.require(user, Permission.restock);
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'must be positive');
    }
    late Batch batch;
    await isar.writeTxn(() async {
      batch = await _newBatchInTxn(
        isar,
        product: product,
        quantity: quantity,
        expiryDate: expiryDate,
        supplierNote: supplierNote,
        unitCost: unitCost,
        type: StockMovementType.restock,
        userId: user?.id ?? 0,
      );
      if (unitCost != null) {
        // The latest purchase cost becomes the product's cost price.
        product
          ..costPrice = unitCost
          ..updatedAt = DateTime.now()
          ..isSynced = false;
        await isar.products.put(product);
      }
      await isar.activityLogs.put(ActivityLogService.entry(
          user, ActivityAction.restock, '${product.name} +$quantity'));
    });
    return batch;
  }

  // ── Adjustments ─────────────────────────────────────────────────────

  /// Removes stock for [reason] (damage, loss, theft, expiry…) or adds
  /// found stock. A negative [quantityChange] removes from [batchId] if
  /// given, else from batches soonest-expiry first (expired included).
  static Future<void> adjust(
    Isar isar,
    AppUser? user, {
    required Product product,
    required int quantityChange,
    required String reason,
    String? note,
    int? batchId,
  }) async {
    Permissions.require(user, Permission.adjustStock);
    if (quantityChange == 0) return;
    final userId = user?.id ?? 0;

    await isar.writeTxn(() async {
      if (quantityChange > 0) {
        await addToBatchInTxn(
          isar,
          productId: product.id,
          quantity: quantityChange,
          type: StockMovementType.adjustment,
          userId: userId,
          batchId: batchId,
          reason: reason,
          note: note,
        );
      } else if (batchId != null) {
        await _removeFromBatchInTxn(isar,
            batchId: batchId,
            productName: product.name,
            quantity: -quantityChange,
            reason: reason,
            note: note,
            userId: userId);
      } else {
        await deductFefoInTxn(
          isar,
          productId: product.id,
          productName: product.name,
          quantity: -quantityChange,
          type: StockMovementType.adjustment,
          userId: userId,
          reason: reason,
          note: note,
          includeExpired: true,
        );
      }
      await isar.activityLogs.put(ActivityLogService.entry(
          user,
          ActivityAction.stockAdjustment,
          '${product.name} ${quantityChange > 0 ? '+' : ''}$quantityChange '
          '(${AdjustmentReason.label(reason)})'));
    });
  }

  /// Sets total stock to what was physically counted.
  static Future<int> setCountedStock(
    Isar isar,
    AppUser? user, {
    required Product product,
    required int countedQuantity,
    String? note,
  }) async {
    if (countedQuantity < 0) {
      throw ArgumentError.value(countedQuantity, 'countedQuantity');
    }
    final batches = await isar.batchs
        .filter()
        .productIdEqualTo(product.id)
        .findAll();
    final current = batches.fold<int>(0, (s, b) => s + b.quantity);
    final diff = countedQuantity - current;
    await adjust(
      isar,
      user,
      product: product,
      quantityChange: diff,
      reason: AdjustmentReason.countCorrection,
      note: note ?? 'Counted $countedQuantity (system had $current)',
    );
    return diff;
  }

  /// Removes everything left in an (expired) batch.
  static Future<void> writeOffBatch(
    Isar isar,
    AppUser? user, {
    required Product product,
    required Batch batch,
    String reason = AdjustmentReason.expired,
  }) async {
    if (batch.quantity <= 0) return;
    await adjust(
      isar,
      user,
      product: product,
      quantityChange: -batch.quantity,
      reason: reason,
      batchId: batch.id,
      note: 'Batch expiring ${batch.expiryDate.toIso8601String().substring(0, 10)}',
    );
  }

  // ── Internals ───────────────────────────────────────────────────────

  static void _apply(Product product, ProductInput input, DateTime now) {
    String? blankToNull(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();
    product
      ..name = input.name.trim()
      ..price = input.price
      ..category =
          input.category.trim().isEmpty ? 'General' : input.category.trim()
      ..quickButtonColor = input.quickButtonColor
      ..costPrice = input.costPrice
      ..barcode = blankToNull(input.barcode)
      ..sku = blankToNull(input.sku)
      ..reorderLevel = input.reorderLevel < 0 ? 0 : input.reorderLevel
      ..updatedAt = now
      ..isSynced = false;
    product.uuid ??= IdHelpers.newUuid();
  }

  static Future<Batch> _newBatchInTxn(
    Isar isar, {
    required Product product,
    required int quantity,
    required DateTime expiryDate,
    required String type,
    required int userId,
    String? supplierNote,
    double? unitCost,
  }) async {
    final now = DateTime.now();
    final batch = Batch()
      ..productId = product.id
      ..quantity = quantity
      ..expiryDate = expiryDate
      ..restockDate = now
      ..supplierNote =
          (supplierNote == null || supplierNote.trim().isEmpty) ? null : supplierNote.trim()
      ..unitCost = unitCost
      ..uuid = IdHelpers.newUuid()
      ..updatedAt = now;
    await isar.batchs.put(batch);
    batch.product.value = product;
    await batch.product.save();
    await isar.stockMovements.put(_movement(
      productId: product.id,
      batchId: batch.id,
      change: quantity,
      type: type,
      userId: userId,
      note: batch.supplierNote,
      at: now,
    ));
    return batch;
  }

  static Future<void> _removeFromBatchInTxn(
    Isar isar, {
    required int batchId,
    required String productName,
    required int quantity,
    required String reason,
    required int userId,
    String? note,
  }) async {
    final batch = await isar.batchs.get(batchId);
    if (batch == null || batch.quantity < quantity) {
      throw InsufficientStockException(
          productName, quantity, batch?.quantity ?? 0);
    }
    final now = DateTime.now();
    batch
      ..quantity -= quantity
      ..updatedAt = now
      ..isSynced = false;
    await isar.batchs.put(batch);
    await isar.stockMovements.put(_movement(
      productId: batch.productId,
      batchId: batch.id,
      change: -quantity,
      type: StockMovementType.adjustment,
      userId: userId,
      reason: reason,
      note: note,
      at: now,
    ));
    await _touchProduct(isar, batch.productId, now);
  }

  /// Re-saves the product so product watchers refresh stock figures.
  static Future<void> _touchProduct(Isar isar, int productId, DateTime now) async {
    final product = await isar.products.get(productId);
    if (product == null) return;
    product
      ..updatedAt = now
      ..isSynced = false;
    await isar.products.put(product);
  }

  static StockMovement _movement({
    required int productId,
    required int? batchId,
    required int change,
    required String type,
    required int userId,
    required DateTime at,
    int? saleId,
    String? reason,
    String? note,
  }) =>
      StockMovement()
        ..uuid = IdHelpers.newUuid()
        ..productId = productId
        ..batchId = batchId
        ..quantityChange = change
        ..type = type
        ..userId = userId
        ..saleId = saleId
        ..reason = reason
        ..note = note
        ..timestamp = at;
}
