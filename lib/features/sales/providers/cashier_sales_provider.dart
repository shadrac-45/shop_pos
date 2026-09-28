/// ============================================
/// Cashier Sales Provider — ShopPOS
/// ============================================
/// Reactive stream and statistics for sales made
/// by the currently logged-in cashier.
/// Auto-updates in real time as sales are completed.
/// ============================================
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/sales/models/sale.dart';

/// Time period filter for the cashier sales history
enum CashierSalesPeriod {
  today,
  week,
  all,
}

/// Active period filter provider (defaults to 'today')
final cashierSalesPeriodProvider = StateProvider<CashierSalesPeriod>((ref) {
  return CashierSalesPeriod.today;
});

/// Aggregated stats computed from the cashier's filtered sales
class CashierSalesStats {
  final double totalRevenue;
  final int totalCount;
  final double cashRevenue;
  final int cashCount;
  final double momoRevenue;
  final int momoCount;
  final double averageSale;

  const CashierSalesStats({
    required this.totalRevenue,
    required this.totalCount,
    required this.cashRevenue,
    required this.cashCount,
    required this.momoRevenue,
    required this.momoCount,
    required this.averageSale,
  });

  factory CashierSalesStats.empty() {
    return const CashierSalesStats(
      totalRevenue: 0.0,
      totalCount: 0,
      cashRevenue: 0.0,
      cashCount: 0,
      momoRevenue: 0.0,
      momoCount: 0,
      averageSale: 0.0,
    );
  }

  factory CashierSalesStats.fromSales(List<Sale> sales) {
    double total = 0.0;
    double cash = 0.0;
    double momo = 0.0;
    int cCount = 0;
    int mCount = 0;

    for (final s in sales) {
      total += s.totalAmount;
      if (s.paymentType == 'cash') {
        cash += s.totalAmount;
        cCount++;
      } else {
        momo += s.totalAmount;
        mCount++;
      }
    }

    return CashierSalesStats(
      totalRevenue: total,
      totalCount: sales.length,
      cashRevenue: cash,
      cashCount: cCount,
      momoRevenue: momo,
      momoCount: mCount,
      averageSale: sales.isNotEmpty ? (total / sales.length) : 0.0,
    );
  }
}

/// Reactive real-time stream of sales made by the current cashier
final cashierSalesStreamProvider =
    StreamProvider.autoDispose<List<Sale>>((ref) {
  final isar = ref.watch(isarProvider);
  final currentUser = ref.watch(currentUserProvider);
  final period = ref.watch(cashierSalesPeriodProvider);

  final now = DateTime.now();
  final DateTime? startOfPeriod;
  final endOfPeriod = DateHelpers.endOfDay(now);

  switch (period) {
    case CashierSalesPeriod.today:
      startOfPeriod = DateHelpers.startOfDay(now);
      break;
    case CashierSalesPeriod.week:
      startOfPeriod =
          DateHelpers.startOfDay(now.subtract(const Duration(days: 7)));
      break;
    case CashierSalesPeriod.all:
      startOfPeriod = null;
      break;
  }

  final currentCashierId = currentUser?.id ?? 0;

  final Stream<List<Sale>> rawStream;
  if (startOfPeriod != null) {
    rawStream = isar.sales
        .filter()
        .timestampBetween(startOfPeriod, endOfPeriod)
        .sortByTimestampDesc()
        .watch(fireImmediately: true);
  } else {
    rawStream = isar.sales
        .where()
        .sortByTimestampDesc()
        .watch(fireImmediately: true);
  }

  return rawStream.map((sales) {
    if (currentCashierId > 0) {
      // Find sales strictly tagged with this cashier's ID
      final userSales =
          sales.where((s) => s.cashierId == currentCashierId).toList();
      if (userSales.isNotEmpty) {
        return userSales;
      }
      // If none are tagged with this ID yet, include legacy/unattributed sales (cashierId == 0)
      return sales
          .where(
              (s) => s.cashierId == currentCashierId || s.cashierId == 0)
          .toList();
    }
    return sales;
  });
});

/// Reactive derived statistics for the cashier's filtered sales
final cashierSalesStatsProvider =
    Provider.autoDispose<CashierSalesStats>((ref) {
  final salesAsync = ref.watch(cashierSalesStreamProvider);
  final sales = salesAsync.valueOrNull ?? [];
  return CashierSalesStats.fromSales(sales);
});
