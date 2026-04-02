/// ============================================
/// Report Provider — Riverpod
/// ============================================
/// Fetches and computes data for analytics:
/// Revenue, Transaction counts, Payment splits,
/// and Top Products.
/// ============================================
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/sale.dart';
import 'sales_provider.dart';

/// Date range filter for reports
enum ReportFilter { today, thisWeek, custom }

final reportFilterProvider = StateProvider<ReportFilter>((ref) => ReportFilter.today);

/// Date range start & end
final reportDateRangeProvider = Provider<({DateTime start, DateTime end})>((ref) {
  final filter = ref.watch(reportFilterProvider);
  final now = DateTime.now();

  if (filter == ReportFilter.today) {
    return (
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  } else if (filter == ReportFilter.thisWeek) {
    // Start of week (Monday)
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    return (
      start: DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  } else {
    // Fallback or custom
    return (
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }
});

/// Provides the raw sales based on the filter.
final filteredSalesProvider = FutureProvider<List<Sale>>((ref) async {
  final range = ref.watch(reportDateRangeProvider);
  final salesService = ref.watch(salesServiceProvider);
  
  return salesService.getSalesByDateRange(range.start, range.end);
});

/// Computes top KPIs
final reportKpisProvider = FutureProvider<({double revenue, int transactions, double cashAmt, double momoAmt})>((ref) async {
  final sales = await ref.watch(filteredSalesProvider.future);
  
  double revenue = 0;
  double cashAmt = 0;
  double momoAmt = 0;

  for (final sale in sales) {
    revenue += sale.totalAmount;
    if (sale.paymentType == 'cash') {
      cashAmt += sale.totalAmount;
    } else if (sale.paymentType == 'momo') {
      momoAmt += sale.totalAmount;
    } else if (sale.paymentType == 'split') {
      cashAmt += sale.amountCash;
      momoAmt += sale.amountMomo;
    }
  }

  return (
    revenue: revenue,
    transactions: sales.length,
    cashAmt: cashAmt,
    momoAmt: momoAmt,
  );
});

/// Computes the top 5 sold products by quantity
final topProductsProvider = FutureProvider<List<({String name, int qty})>>((ref) async {
  final sales = await ref.watch(filteredSalesProvider.future);
  
  final Map<String, int> productCounts = {};

  for (final sale in sales) {
    for (final item in sale.items) {
      final name = item['name'] as String? ?? 'Unknown';
      final qty = (item['qty'] as num?)?.toInt() ?? 0;
      
      productCounts[name] = (productCounts[name] ?? 0) + qty;
    }
  }

  final sorted = productCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return sorted.take(5).map((e) => (name: e.key, qty: e.value)).toList();
});
