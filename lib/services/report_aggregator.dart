/// ============================================
/// Report Aggregator — ShopPOS
/// ============================================
/// Pure functions for aggregating and crunching
/// sales data. Decouples complex data transformations
/// from Riverpod state management.
/// ============================================
library;

import 'dart:convert';
import 'package:isar/isar.dart';
import '../models/app_user.dart';
import '../models/sale.dart';

// ── Models ────────────────────────────────────────────────

/// Aggregated per-cashier stats for a given reporting period.
class CashierSummary {
  final int cashierId;
  final String cashierName;
  final double totalRevenue;
  final int transactionCount;
  final List<Sale> sales;

  const CashierSummary({
    required this.cashierId,
    required this.cashierName,
    required this.totalRevenue,
    required this.transactionCount,
    required this.sales,
  });
}

/// Aggregated per-product stats for a given reporting period.
class ProductSummary {
  final String productName;
  final int totalQty;
  final double totalRevenue;

  const ProductSummary({
    required this.productName,
    required this.totalQty,
    required this.totalRevenue,
  });
}

// ── Aggregator Logic ──────────────────────────────────────

class ReportAggregator {
  ReportAggregator._();

  static double computeTotalRevenue(List<Sale> sales) {
    return sales.fold(0.0, (sum, sale) => sum + sale.totalAmount);
  }

  static Map<String, double> computeBreakdown(List<Sale> sales) {
    double cash = 0.0;
    double momo = 0.0;
    for (var sale in sales) {
      if (sale.paymentType == 'cash') cash += sale.totalAmount;
      if (sale.paymentType == 'momo' || sale.paymentType == 'mobile_money') {
        momo += sale.totalAmount;
      }
    }
    return {'cash': cash, 'momo': momo};
  }

  static List<ProductSummary> computeProductSummaries(List<Sale> sales) {
    final Map<String, ({int qty, double revenue})> agg = {};

    for (final sale in sales) {
      try {
        final List<dynamic> items = json.decode(sale.itemsJson);
        for (final item in items) {
          final name = item['productName'] as String? ?? 'Unknown';
          final qty = (item['quantity'] as num?)?.toInt() ?? 0;
          final price = (item['price'] as num?)?.toDouble() ?? 0.0;
          final existing = agg[name] ?? (qty: 0, revenue: 0.0);
          agg[name] = (
            qty: existing.qty + qty,
            revenue: existing.revenue + price * qty
          );
        }
      } catch (_) {}
    }

    final list = agg.entries
        .map((e) => ProductSummary(
              productName: e.key,
              totalQty: e.value.qty,
              totalRevenue: e.value.revenue,
            ))
        .toList()
      ..sort((a, b) => b.totalQty.compareTo(a.totalQty));

    return list;
  }

  static Future<List<CashierSummary>> buildCashierSummaries(
      Isar isar, List<Sale> sales) async {
    // Group sales by cashierId
    final Map<int, List<Sale>> grouped = {};
    for (final sale in sales) {
      grouped.putIfAbsent(sale.cashierId, () => []).add(sale);
    }

    // Resolve cashierId → name from AppUser table
    final summaries = <CashierSummary>[];
    for (final entry in grouped.entries) {
      final userId = entry.key;
      final userSales = entry.value;

      String name;
      if (userId == 0) {
        // Legacy record
        name = 'Unknown Cashier';
      } else {
        final user = await isar.appUsers.get(userId);
        name = user?.name ?? 'Unknown Cashier';
      }

      final revenue = userSales.fold(0.0, (sum, s) => sum + s.totalAmount);
      summaries.add(CashierSummary(
        cashierId: userId,
        cashierName: name,
        totalRevenue: revenue,
        transactionCount: userSales.length,
        sales: userSales..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
      ));
    }

    // Sort highest revenue first
    summaries.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    return summaries;
  }
}
