import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/product.dart';
import 'database_provider.dart';

final productServiceProvider = StreamProvider<List<Product>>((ref) {
  final isar = ref.watch(isarProvider);
  return isar.products.where().watch(fireImmediately: true);
});

final productByIdProvider = Provider.family<Product?, int>((ref, id) {
  final isar = ref.watch(isarProvider);
  return isar.products.getSync(id);
});
