/// ============================================
/// Product Provider — Riverpod
/// ============================================
/// Manages product and batch data: CRUD operations,
/// stock calculations, FEFO ordering, and search.
/// ============================================
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/product.dart';
import '../models/batch.dart';
import '../core/constants/app_constants.dart';
import 'database_provider.dart';

/// Provides the product service for CRUD operations.
final productServiceProvider = Provider<ProductService>((ref) {
  return ProductService(ref.watch(isarProvider));
});

/// Holds the currently selected product (for editing/restocking workflows).
final selectedProductProvider = StateProvider<Product?>((ref) => null);

/// Provides the list of all active products with computed stock/expiry.
/// Auto-refreshes when products change.
final productsProvider = FutureProvider<List<Product>>((ref) async {
  final service = ref.watch(productServiceProvider);
  return service.getAllProductsWithStock();
});

/// Provides batches for a specific product, sorted by FEFO.
final productBatchesProvider =
    FutureProvider.family<List<Batch>, int>((ref, productId) async {
  final service = ref.watch(productServiceProvider);
  return service.getBatchesForProduct(productId);
});

/// Search results provider — filters products by name.
final productSearchProvider =
    FutureProvider.family<List<Product>, String>((ref, query) async {
  final service = ref.watch(productServiceProvider);
  return service.searchProducts(query);
});

/// Provides products that have batches expiring within the warning threshold or already expired.
final expiringProductsProvider = FutureProvider<List<Product>>((ref) async {
  final products = await ref.watch(productsProvider.future);
  final now = DateTime.now();
  final threshold = now.add(const Duration(days: AppConstants.expirySoonDays));
  
  return products.where((p) {
    if (p.totalStock <= 0 || p.soonestExpiry == null) return false;
    return p.soonestExpiry!.isBefore(threshold);
  }).toList();
});

/// Service class for all product-related database operations.
class ProductService {
  final Isar _isar;

  ProductService(this._isar);

  /// Get all active products with computed totalStock and soonestExpiry.
  Future<List<Product>> getAllProductsWithStock() async {
    final products = await _isar.products
        .filter()
        .isActiveEqualTo(true)
        .findAll();

    // Compute stock and expiry for each product
    for (final product in products) {
      final batches = await _isar.batchs
          .filter()
          .productIdEqualTo(product.id)
          .quantityGreaterThan(0)
          .sortByExpiryDate()
          .findAll();

      product.totalStock = batches.fold(0, (sum, b) => sum + b.quantity);

      if (batches.isNotEmpty) {
        product.soonestExpiry = batches.first.expiryDate;
      }
    }

    return products;
  }

  /// Get batches for a product, sorted by expiry (FEFO).
  Future<List<Batch>> getBatchesForProduct(int productId) async {
    return _isar.batchs
        .filter()
        .productIdEqualTo(productId)
        .quantityGreaterThan(0)
        .sortByExpiryDate()
        .findAll();
  }

  /// Search products by name (case-insensitive contains).
  Future<List<Product>> searchProducts(String query) async {
    if (query.isEmpty) return getAllProductsWithStock();

    final lowerQuery = query.toLowerCase();
    final products = await _isar.products
        .filter()
        .isActiveEqualTo(true)
        .nameContains(lowerQuery, caseSensitive: false)
        .findAll();

    // Also compute stock for search results
    for (final product in products) {
      final batches = await _isar.batchs
          .filter()
          .productIdEqualTo(product.id)
          .quantityGreaterThan(0)
          .sortByExpiryDate()
          .findAll();

      product.totalStock = batches.fold(0, (sum, b) => sum + b.quantity);

      if (batches.isNotEmpty) {
        product.soonestExpiry = batches.first.expiryDate;
      }
    }

    return products;
  }

  /// Find a product by barcode.
  Future<Product?> findByBarcode(String barcode) async {
    return _isar.products
        .filter()
        .barcodeEqualTo(barcode)
        .isActiveEqualTo(true)
        .findFirst();
  }

  /// Create a new product.
  Future<Product> createProduct({
    required String name,
    required double price,
    required String category,
    int? colorValue,
    String? barcode,
  }) async {
    final product = Product()
      ..name = name
      ..price = price
      ..category = category
      ..barcode = barcode;

    if (colorValue != null) {
      product.quickButtonColor = colorValue;
    }

    await _isar.writeTxn(() async {
      await _isar.products.put(product);
    });

    return product;
  }

  /// Update an existing product.
  Future<void> updateProduct(Product product) async {
    product.updatedAt = DateTime.now();
    await _isar.writeTxn(() async {
      await _isar.products.put(product);
    });
  }

  /// Soft-delete a product.
  Future<void> deleteProduct(int productId) async {
    await _isar.writeTxn(() async {
      final product = await _isar.products.get(productId);
      if (product != null) {
        product.isActive = false;
        product.updatedAt = DateTime.now();
        await _isar.products.put(product);
      }
    });
  }

  /// Add a new batch to a product.
  Future<Batch> addBatch({
    required int productId,
    required int quantity,
    required DateTime expiryDate,
    String? supplierNote,
  }) async {
    final batch = Batch()
      ..productId = productId
      ..quantity = quantity
      ..expiryDate = expiryDate
      ..restockDate = DateTime.now()
      ..supplierNote = supplierNote;

    await _isar.writeTxn(() async {
      await _isar.batchs.put(batch);
    });

    return batch;
  }

  /// Deduct stock from a product using FEFO (First Expired, First Out).
  /// Skips expired batches — only sells from non-expired stock.
  /// Returns true if sufficient non-expired stock was available.
  Future<bool> deductStock(int productId, int quantity) async {
    return _isar.writeTxn(() async {
      final now = DateTime.now();

      // Get batches sorted by expiry (earliest first = FEFO)
      final batches = await _isar.batchs
          .filter()
          .productIdEqualTo(productId)
          .quantityGreaterThan(0)
          .sortByExpiryDate()
          .findAll();

      // FEFO with expiry guard: skip expired batches entirely
      final sellable =
          batches.where((b) => !b.expiryDate.isBefore(now)).toList();

      int remaining = quantity;

      for (final batch in sellable) {
        if (remaining <= 0) break;

        if (batch.quantity >= remaining) {
          batch.quantity -= remaining;
          remaining = 0;
        } else {
          remaining -= batch.quantity;
          batch.quantity = 0;
        }

        await _isar.batchs.put(batch);
      }

      return remaining <= 0;
    });
  }

  /// Pre-sale check: verify the product has sellable (non-expired) stock.
  /// Returns a record with canSell flag and an optional reason string.
  Future<({bool canSell, String? reason})> checkProductSellable(
    int productId,
  ) async {
    final batches = await _isar.batchs
        .filter()
        .productIdEqualTo(productId)
        .quantityGreaterThan(0)
        .sortByExpiryDate()
        .findAll();

    if (batches.isEmpty) {
      return (canSell: false, reason: 'Out of stock');
    }

    // FEFO: the first batch is the soonest-expiring.
    // If it is expired, block the sale so the owner can handle removal.
    if (batches.first.expiryDate.isBefore(DateTime.now())) {
      return (
        canSell: false,
        reason: 'EXPIRED \u2013 Remove expired stock before selling!',
      );
    }

    return (canSell: true, reason: null);
  }

  /// Get all unique categories.
  Future<List<String>> getAllCategories() async {
    final products = await _isar.products
        .filter()
        .isActiveEqualTo(true)
        .findAll();

    final categories = products
        .map((p) => p.category)
        .toSet()
        .toList()
      ..sort();

    return categories;
  }
}
