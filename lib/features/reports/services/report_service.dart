/// ============================================
/// Report Service — ShopPOS
/// ============================================
/// Loads a period's sales, sale lines and
/// expenses, and turns them into a report.
///
/// Definitions (voided sales are excluded from
/// every money figure):
///   gross sales   = Σ sale totals
///   refunds       = Σ amounts refunded
///   net sales     = gross sales − refunds
///   tax           = VAT on net sales
///   cost of goods = Σ units kept × unit cost
///   gross profit  = net sales − tax − cost of goods
///   net profit    = gross profit − expenses
/// ============================================
library;

import 'package:isar/isar.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/expenses/models/expense.dart';
import 'package:shop_pos/features/reports/services/report_range.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/models/sale_item.dart';
import 'package:shop_pos/features/sales/services/sale_calculator.dart';

class ProductReportRow {
  final int productId;
  final String productName;
  final int quantity;
  final double revenue;

  /// Null when none of the units sold had a known cost.
  final double? cost;

  /// Units sold with no known cost (their profit can't be worked out).
  final int unitsWithoutCost;

  const ProductReportRow({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.revenue,
    required this.cost,
    required this.unitsWithoutCost,
  });

  double? get profit => cost == null ? null : roundMoney(revenue - cost!);
}

class CashierReportRow {
  final int cashierId;
  final String name;
  final int saleCount;
  final double netSales;
  final List<Sale> sales;

  const CashierReportRow({
    required this.cashierId,
    required this.name,
    required this.saleCount,
    required this.netSales,
    required this.sales,
  });
}

class ReportSummary {
  final ReportRange range;
  final List<Sale> sales;
  final List<SaleItem> items;
  final List<Expense> expenses;

  final int saleCount;
  final int voidCount;
  final double voidedAmount;
  final double grossSales;
  final double refunds;
  final double discounts;
  final double tax;
  final double costOfGoods;
  final int unitsWithoutCost;
  final double totalExpenses;

  /// Money collected per payment method (net of refunds by that method).
  final Map<String, double> byPaymentMethod;
  final List<ProductReportRow> products;
  final List<CashierReportRow> cashiers;

  const ReportSummary({
    required this.range,
    required this.sales,
    required this.items,
    required this.expenses,
    required this.saleCount,
    required this.voidCount,
    required this.voidedAmount,
    required this.grossSales,
    required this.refunds,
    required this.discounts,
    required this.tax,
    required this.costOfGoods,
    required this.unitsWithoutCost,
    required this.totalExpenses,
    required this.byPaymentMethod,
    required this.products,
    required this.cashiers,
  });

  double get netSales => roundMoney(grossSales - refunds);
  double get grossProfit => roundMoney(netSales - tax - costOfGoods);
  double get netProfit => roundMoney(grossProfit - totalExpenses);
  double get averageSale => saleCount == 0 ? 0 : roundMoney(netSales / saleCount);

  /// Pure aggregation, kept separate from Isar so it can be unit-tested.
  static ReportSummary compute({
    required ReportRange range,
    required List<Sale> sales,
    required List<SaleItem> items,
    required List<Expense> expenses,
    Map<int, String> userNames = const {},
  }) {
    final kept = sales.where((s) => !s.isVoided).toList();
    final voided = sales.where((s) => s.isVoided).toList();
    final keptIds = kept.map((s) => s.id).toSet();

    double sum(Iterable<double> xs) => roundMoney(xs.fold(0.0, (a, b) => a + b));

    final grossSales = sum(kept.map((s) => s.totalAmount));
    final refunds = sum(kept.map((s) => s.refundedAmount));
    final discounts = sum(kept.map((s) => s.discountAmount));
    // VAT scales down with whatever share of the sale was refunded.
    final tax = sum(kept.map((s) =>
        s.totalAmount == 0 ? 0.0 : s.taxAmount * s.netAmount / s.totalAmount));

    final byMethod = <String, double>{};
    for (final s in kept) {
      for (final p in s.effectivePayments) {
        final key = p.method == AppConstants.paymentMomoPaystack
            ? AppConstants.paymentMomo
            : p.method;
        byMethod[key] = roundMoney((byMethod[key] ?? 0) + p.amount);
      }
      for (final r in s.refunds) {
        final key = r.method == AppConstants.paymentMomoPaystack
            ? AppConstants.paymentMomo
            : r.method;
        byMethod[key] = roundMoney((byMethod[key] ?? 0) - r.amount);
      }
    }

    // ── Products (from indexed sale lines) ──
    final productAgg = <int, _ProductAgg>{};
    var costOfGoods = 0.0;
    var unitsWithoutCost = 0;
    for (final item in items.where((i) => keptIds.contains(i.saleId))) {
      final agg = productAgg.putIfAbsent(
          item.productId, () => _ProductAgg(item.productId, item.productName));
      final qty = item.netQuantity;
      agg.quantity += qty;
      agg.revenue += item.netLineTotal;
      if (item.unitCost != null) {
        final c = item.unitCost! * qty;
        agg.cost += c;
        agg.hasCost = true;
        costOfGoods += c;
      } else {
        agg.unitsWithoutCost += qty;
        unitsWithoutCost += qty;
      }
    }
    final products = productAgg.values
        .where((a) => a.quantity > 0)
        .map((a) => ProductReportRow(
              productId: a.productId,
              productName: a.name,
              quantity: a.quantity,
              revenue: roundMoney(a.revenue),
              cost: a.hasCost ? roundMoney(a.cost) : null,
              unitsWithoutCost: a.unitsWithoutCost,
            ))
        .toList()
      ..sort((a, b) => b.quantity.compareTo(a.quantity));

    // ── Cashiers ──
    final byCashier = <int, List<Sale>>{};
    for (final s in kept) {
      byCashier.putIfAbsent(s.cashierId, () => []).add(s);
    }
    final cashiers = byCashier.entries
        .map((e) => CashierReportRow(
              cashierId: e.key,
              name: userNames[e.key] ?? 'Unknown cashier',
              saleCount: e.value.length,
              netSales: sum(e.value.map((s) => s.netAmount)),
              sales: e.value..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
            ))
        .toList()
      ..sort((a, b) => b.netSales.compareTo(a.netSales));

    return ReportSummary(
      range: range,
      sales: [...sales]..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
      items: items,
      expenses: expenses,
      saleCount: kept.length,
      voidCount: voided.length,
      voidedAmount: sum(voided.map((s) => s.totalAmount)),
      grossSales: grossSales,
      refunds: refunds,
      discounts: discounts,
      tax: tax,
      costOfGoods: roundMoney(costOfGoods),
      unitsWithoutCost: unitsWithoutCost,
      totalExpenses: sum(expenses.map((e) => e.amount)),
      byPaymentMethod: byMethod,
      products: products,
      cashiers: cashiers,
    );
  }

  static Future<ReportSummary> load(Isar isar, ReportRange range) async {
    final sales = await isar.sales
        .filter()
        .timestampBetween(range.start, range.endInclusive)
        .findAll();
    final items = await isar.saleItems
        .filter()
        .timestampBetween(range.start, range.endInclusive)
        .findAll();
    final expenses = await isar.expenses
        .filter()
        .timestampBetween(range.start, range.endInclusive)
        .isDeletedEqualTo(false)
        .findAll();
    final users = await isar.appUsers.where().findAll();
    return compute(
      range: range,
      sales: sales,
      items: items,
      expenses: expenses,
      userNames: {for (final u in users) u.id: u.name},
    );
  }
}

class _ProductAgg {
  final int productId;
  final String name;
  int quantity = 0;
  double revenue = 0;
  double cost = 0;
  bool hasCost = false;
  int unitsWithoutCost = 0;
  _ProductAgg(this.productId, this.name);
}
