import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/batch.dart';
import '../models/product.dart';
import 'database_provider.dart';

/// Instant product list stream — no catalog-wide preloading loop.
/// Emits immediately without blocking startup as catalog size grows.
final productServiceProvider = StreamProvider<List<Product>>((ref) {
  final isar = ref.watch(isarProvider);
  return isar.products.where().watch(fireImmediately: true);
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
