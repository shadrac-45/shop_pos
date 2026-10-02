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

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/services/sale_calculator.dart';

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
  /// Net of refunds; voided sales count for nothing.
  final double totalRevenue;
  final int totalCount;
  final double cashRevenue;
  final int cashCount;

  /// Everything not paid in cash (MoMo, card, QR).
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

  factory CashierSalesStats.empty() => CashierSalesStats.fromSales(const []);

  factory CashierSalesStats.fromSales(List<Sale> sales) {
    double total = 0.0;
    double cash = 0.0;
    double other = 0.0;
    int cCount = 0;
    int oCount = 0;
    int count = 0;

    for (final s in sales.where((s) => !s.isVoided)) {
      count++;
      total += s.netAmount;
      // Split the net amount across methods in proportion to what was paid.
      final scale = s.totalAmount == 0 ? 0.0 : s.netAmount / s.totalAmount;
      var hadCash = false;
      var hadOther = false;
      for (final p in s.effectivePayments) {
        if (p.method == AppConstants.paymentCash) {
          cash += p.amount * scale;
          hadCash = true;
        } else {
          other += p.amount * scale;
          hadOther = true;
        }
      }
      if (hadCash) cCount++;
      if (hadOther) oCount++;
    }

    return CashierSalesStats(
      totalRevenue: roundMoney(total),
      totalCount: count,
      cashRevenue: roundMoney(cash),
      cashCount: cCount,
      momoRevenue: roundMoney(other),
      momoCount: oCount,
      averageSale: count > 0 ? roundMoney(total / count) : 0.0,
    );
  }
}

/// Live list of sales rung up by the signed-in user in the chosen period.
/// Only that user's own sales: never other staff's, never unattributed.
final cashierSalesStreamProvider =
    StreamProvider.autoDispose<List<Sale>>((ref) {
  final isar = ref.watch(isarProvider);
  final currentUser = ref.watch(currentUserProvider);
  final period = ref.watch(cashierSalesPeriodProvider);
  if (currentUser == null) return Stream.value(const []);

  final now = DateTime.now();
  final DateTime start = switch (period) {
    CashierSalesPeriod.today => DateHelpers.startOfDay(now),
    CashierSalesPeriod.week =>
      DateHelpers.startOfDay(now.subtract(const Duration(days: 6))),
    CashierSalesPeriod.all => DateTime(2000),
  };

  return isar.sales
      .filter()
      .cashierIdEqualTo(currentUser.id)
      .timestampBetween(start, DateHelpers.endOfDay(now))
      .sortByTimestampDesc()
      .watch(fireImmediately: true);
});

/// Reactive derived statistics for the cashier's filtered sales
final cashierSalesStatsProvider =
    Provider.autoDispose<CashierSalesStats>((ref) {
  final salesAsync = ref.watch(cashierSalesStreamProvider);
  final sales = salesAsync.valueOrNull ?? [];
  return CashierSalesStats.fromSales(sales);
});
