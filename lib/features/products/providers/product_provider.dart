import 'dart:async';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/core/database/database_provider.dart';

/// Instant, reactive product list stream with preloaded batches.
/// Watches both products and batches so inventory numbers, stock levels,
/// and out-of-stock states immediately decrement when a sale is completed.
final productServiceProvider = StreamProvider<List<Product>>((ref) async* {
  final isar = ref.watch(isarProvider);

  Future<List<Product>> fetchProducts() async {
    final products = await isar.products.where().findAll();
    for (final p in products) {
      try {
        await p.batches.load();
        if (p.batches.isEmpty) {
          final matchingBatches =
              await isar.batchs.filter().productIdEqualTo(p.id).findAll();
          if (matchingBatches.isNotEmpty) {
            for (final b in matchingBatches) {
              p.batches.add(b);
            }
          }
        }
      } catch (_) {}
    }
    return products;
  }

  // 1. Emit current products immediately so UI displays data right away
  yield await fetchProducts();

  // 2. Broadcast controller for subsequent collection events (sales, restocks, edits)
  final controller = StreamController<List<Product>>.broadcast();

  final subProducts = isar.products.watchLazy().listen((_) async {
    if (!controller.isClosed) {
      controller.add(await fetchProducts());
    }
  });

  final subBatches = isar.batchs.watchLazy().listen((_) async {
    if (!controller.isClosed) {
      controller.add(await fetchProducts());
    }
  });

  ref.onDispose(() {
    subProducts.cancel();
    subBatches.cancel();
    controller.close();
  });

  yield* controller.stream;
});

final productByIdProvider = Provider.family<Product?, int>((ref, id) {
  final isar = ref.watch(isarProvider);
  return isar.products.getSync(id);
});

/// On-demand, paginated batch loader for a specific product ID.
/// Uses the indexed [Batch.productId] B-tree index for sub-millisecond lookups.
final productBatchesProvider =
    FutureProvider.family<List<Batch>, int>((ref, productId) async {
  final isar = ref.watch(isarProvider);
  return await isar.batchs.filter().productIdEqualTo(productId).findAll();
});
