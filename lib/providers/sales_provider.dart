import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'report_provider.dart';

final reportFilterProvider = StateProvider<String>((ref) => 'today');

final reportKpisProvider = Provider((ref) {
  final sales = ref.watch(reportProvider);
  return sales;
});

final topProductsProvider = Provider<Map<String, int>>((ref) {
  ref.watch(reportProvider);
  return ref.read(reportProvider.notifier).topProducts;
});
