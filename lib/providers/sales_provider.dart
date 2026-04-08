import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/sale.dart';
import 'report_provider.dart'; // Added for cross-file reference

final reportFilterProvider = StateProvider<String>((ref) => 'today');

final reportKpisProvider = Provider((ref) {
  final sales = ref.watch(reportProvider); // Fixed undefined reference
  // Add your KPI logic here if needed
  return sales;
});

final topProductsProvider = Provider((ref) => <String, int>{});

final filteredSalesProvider = Provider((ref) => <Sale>[]);
