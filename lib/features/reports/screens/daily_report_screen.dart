/// ============================================
/// Reports Screen — ShopPOS
/// ============================================
/// Owner/manager analytics for any period:
///  1. Period picker (today, yesterday, this week,
///     last 7 days, this/last month, any date
///     range) + CSV export
///  2. Money summary: net sales, profit, VAT,
///     discounts, refunds, expenses, voids
///  3. Takings by payment method
///  4. Sales by cashier
///  5. Products: units, revenue, profit
///  6. Every transaction (tap for the receipt)
/// ============================================
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/core/utils/file_export.dart';
import 'package:shop_pos/features/reports/providers/report_provider.dart';
import 'package:shop_pos/features/reports/services/report_csv.dart';
import 'package:shop_pos/features/reports/services/report_range.dart';
import 'package:shop_pos/features/reports/services/report_service.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/screens/sale_detail_screen.dart';
import 'package:shop_pos/features/shared/widgets/app_empty_state.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';

class DailyReportScreen extends ConsumerStatefulWidget {
  const DailyReportScreen({super.key});

  @override
  ConsumerState<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends ConsumerState<DailyReportScreen> {
  final Set<int> _expandedCashiers = {};
  int _transactionsShown = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reportProvider.notifier).refresh();
    });
  }

  void _setRange(ReportRange range) {
    HapticFeedback.selectionClick();
    setState(() {
      _expandedCashiers.clear();
      _transactionsShown = 30;
    });
    ref.read(reportProvider.notifier).setRange(range);
  }

  Future<void> _pickCustomRange() async {
    final current = ref.read(reportProvider.notifier).range;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: current.start,
        end: current.lastDay.isAfter(DateTime.now()) ? DateTime.now() : current.lastDay,
      ),
    );
    if (picked != null) _setRange(ReportRange.custom(picked.start, picked.end));
  }

  Future<void> _export(ReportSummary report) async {
    final store = ref.read(storeSettingsProvider);
    final csv = ReportCsv.build(report, storeName: store.storeName);
    String d(DateTime t) => t.toIso8601String().substring(0, 10);
    final name = 'shoppos-report-${d(report.range.start)}_to_${d(report.range.lastDay)}.csv';
    try {
      final path = await FileExport.save(
        fileName: name,
        // BOM so Excel opens the file as UTF-8.
        bytes: Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]),
        dialogTitle: 'Save report',
        mimeType: 'text/csv',
        allowedExtensions: ['csv'],
      );
      if (path != null && mounted) context.showSuccessSnackbar('Report saved: $name');
    } catch (e) {
      if (mounted) context.showErrorSnackbar('Could not save report: ${errorMessage(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(reportProvider);
    final notifier = ref.read(reportProvider.notifier);
    final range = notifier.range;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: notifier.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _buildPeriodBar(range, reportAsync.valueOrNull),
              const SizedBox(height: AppSpacing.md),
              reportAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => AppEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load the report',
                  description: '$e',
                  actionLabel: 'Retry',
                  onAction: notifier.refresh,
                ),
                data: _buildReport,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodBar(ReportRange range, ReportSummary? report) {
    Widget chip(ReportPeriod p, String label) {
      final selected = range.period == p;
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => _setRange(ReportRange.of(p)),
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(
            color: selected ? AppColors.textOnPrimary : AppColors.textPrimary,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
          showCheckmark: false,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip(ReportPeriod.today, 'Today'),
              chip(ReportPeriod.yesterday, 'Yesterday'),
              chip(ReportPeriod.thisWeek, 'This week'),
              chip(ReportPeriod.last7Days, 'Last 7 days'),
              chip(ReportPeriod.thisMonth, 'This month'),
              chip(ReportPeriod.lastMonth, 'Last month'),
              ActionChip(
                avatar: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(range.period == ReportPeriod.custom ? range.label : 'Pick dates'),
                onPressed: _pickCustomRange,
                backgroundColor: range.period == ReportPeriod.custom
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                '${range.label}: ${DateHelpers.formatShort(range.start)}'
                '${DateHelpers.isSameDay(range.start, range.lastDay) ? '' : ' – ${DateHelpers.formatShort(range.lastDay)}'}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            IconButton(
              tooltip: 'Export CSV',
              icon: const Icon(Icons.download_rounded, color: AppColors.primary),
              onPressed: report == null ? null : () => _export(report),
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
              onPressed: () => ref.read(reportProvider.notifier).refresh(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReport(ReportSummary r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bigKpi('Net sales', r.netSales,
            subtitle: '${r.saleCount} sale${r.saleCount == 1 ? '' : 's'} · '
                'average ${CurrencyHelpers.format(r.averageSale)}'),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(child: _kpi('Gross profit', r.grossProfit, Icons.trending_up_rounded,
                r.grossProfit >= 0 ? AppColors.success : AppColors.danger)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: _kpi('Net profit', r.netProfit, Icons.savings_rounded,
                r.netProfit >= 0 ? AppColors.success : AppColors.danger)),
          ],
        ),
        if (r.unitsWithoutCost > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              '${r.unitsWithoutCost} unit${r.unitsWithoutCost == 1 ? '' : 's'} sold had no '
              'cost price, so profit is overstated. Add cost prices in Edit Product or Restock.',
              style: const TextStyle(color: AppColors.warning, fontSize: 12),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        TouchableCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              _line('Gross sales', r.grossSales),
              _line('Discounts given', r.discounts, muted: true),
              _line('Refunds', -r.refunds),
              _line('Net sales', r.netSales, bold: true),
              _line('VAT collected', -r.tax),
              _line('Cost of goods sold', -r.costOfGoods),
              _line('Gross profit', r.grossProfit, bold: true),
              _line('Expenses', -r.totalExpenses),
              _line('Net profit', r.netProfit, bold: true),
              if (r.voidCount > 0) ...[
                const Divider(),
                _line('Voided sales (${r.voidCount})', r.voidedAmount, muted: true),
              ],
            ],
          ),
        ),

        const SectionLabel('Takings by payment method'),
        if (r.byPaymentMethod.isEmpty)
          const Text('No payments in this period.',
              style: TextStyle(color: AppColors.textSecondary))
        else
          TouchableCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                for (final e in r.byPaymentMethod.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(paymentIcon(e.key), color: paymentColor(e.key), size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(AppConstants.paymentLabel(e.key))),
                        Text(CurrencyHelpers.format(e.value),
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

        const SectionLabel('Sales by cashier'),
        if (r.cashiers.isEmpty)
          const AppEmptyState(
            icon: Icons.analytics_outlined,
            title: 'No sales in this period',
            description: 'Completed sales appear here, grouped by the staff member who made them.',
          )
        else
          for (final c in r.cashiers) _buildCashierCard(c),

        const SectionLabel('Products sold'),
        _buildProducts(r.products),

        if (r.expenses.isNotEmpty) ...[
          const SectionLabel('Expenses'),
          TouchableCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                for (final e in r.expenses.take(20))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.description.isEmpty ? e.category : e.description),
                    subtitle: Text(DateHelpers.formatDateTime(e.timestamp)),
                    trailing: Text(CurrencyHelpers.format(e.amount),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        ],

        const SectionLabel('Transactions'),
        if (r.sales.isEmpty)
          const Text('No transactions in this period.',
              style: TextStyle(color: AppColors.textSecondary))
        else ...[
          for (final s in r.sales.take(_transactionsShown))
            _buildTransactionTile(s, r.cashiers),
          if (r.sales.length > _transactionsShown)
            TextButton(
              onPressed: () => setState(() => _transactionsShown += 50),
              child: Text('Show more (${r.sales.length - _transactionsShown} left)'),
            ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _bigKpi(String label, double value, {required String subtitle}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppSpacing.borderLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(CurrencyHelpers.format(value),
                style: const TextStyle(
                    color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
          ),
          Text(subtitle, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _kpi(String label, double value, IconData icon, Color color) {
    return TouchableCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(CurrencyHelpers.format(value),
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, double amount, {bool bold = false, bool muted = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: muted ? AppColors.textSecondary : AppColors.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            amount < 0
                ? '−${CurrencyHelpers.format(-amount)}'
                : CurrencyHelpers.format(amount),
            style: style,
          ),
        ],
      ),
    );
  }

  Widget _buildCashierCard(CashierReportRow c) {
    final expanded = _expandedCashiers.contains(c.cashierId);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${c.saleCount} sale${c.saleCount == 1 ? '' : 's'}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(CurrencyHelpers.format(c.netSales),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, color: AppColors.primary)),
                Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded),
              ],
            ),
            onTap: () => setState(() {
              expanded ? _expandedCashiers.remove(c.cashierId) : _expandedCashiers.add(c.cashierId);
            }),
          ),
          if (expanded)
            for (final s in c.sales) _buildTransactionTile(s, const [], dense: true),
        ],
      ),
    );
  }

  Widget _buildProducts(List<ProductReportRow> products) {
    if (products.isEmpty) {
      return const Text('No products sold in this period.',
          style: TextStyle(color: AppColors.textSecondary));
    }
    final maxQty = products.first.quantity;
    return TouchableCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: [
          for (var i = 0; i < products.length && i < 20; i++)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                      ),
                      Expanded(
                        child: Text(products[i].productName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${products[i].quantity} sold · ${CurrencyHelpers.format(products[i].revenue)}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text(
                            products[i].profit == null
                                ? 'profit: no cost price'
                                : 'profit ${CurrencyHelpers.format(products[i].profit!)}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: maxQty > 0 ? products[i].quantity / maxQty : 0,
                    minHeight: 4,
                    backgroundColor: AppColors.surfaceBg,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(Sale s, List<CashierReportRow> cashiers, {bool dense = false}) {
    final cashier = cashiers.where((c) => c.cashierId == s.cashierId).firstOrNull?.name;
    return Card(
      margin: EdgeInsets.only(bottom: dense ? 0 : AppSpacing.sm),
      elevation: dense ? 0 : null,
      child: ListTile(
        dense: dense,
        leading: Icon(paymentIcon(s.paymentType), color: paymentColor(s.paymentType)),
        title: Row(
          children: [
            Text(s.receiptNumber, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            if (s.status != SaleStatus.completed)
              StatusPill(s.status.replaceAll('_', ' '),
                  color: s.isVoided ? AppColors.danger : AppColors.warning),
          ],
        ),
        subtitle: Text([
          DateHelpers.formatDateTime(s.timestamp),
          if (cashier != null) cashier,
          AppConstants.paymentLabel(s.paymentType),
        ].join(' · ')),
        trailing: Text(
          CurrencyHelpers.format(s.isVoided ? s.totalAmount : s.netAmount),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            decoration: s.isVoided ? TextDecoration.lineThrough : null,
          ),
        ),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: s.id)))
            .then((_) => ref.read(reportProvider.notifier).refresh()),
      ),
    );
  }
}
