/// ============================================
/// Daily Report Screen — ShopPOS
/// ============================================
/// Owner-only analytics dashboard with 5 sections:
///  1. Filter strip (Today / This Week) + refresh
///  2. KPI summary cards (Revenue, Cash, MoMo, Transactions)
///  3. Sales by Cashier — per-staff attribution with expandable sale detail
///  4. What's Selling — ranked product list (qty + revenue + visual bar)
///  5. All Recent Transactions — enriched with cashier name, items, MoMo phone
/// ============================================
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:isar/isar.dart';

import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/reports/services/report_aggregator.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/features/reports/providers/report_provider.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/shared/widgets/app_empty_state.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';

class DailyReportScreen extends ConsumerStatefulWidget {
  const DailyReportScreen({super.key});

  @override
  ConsumerState<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends ConsumerState<DailyReportScreen> {
  // Track which cashier cards are expanded
  final Set<int> _expandedCashiers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reportProvider.notifier).loadSalesForFilter('today', force: true);
    });
  }

  // ── Filter chip ───────────────────────────────────────

  Widget _buildFilterChip(String filterKey, String label) {
    final currentFilter = ref.watch(reportProvider.notifier).currentFilter;
    final isSelected = currentFilter == filterKey;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          HapticFeedback.selectionClick();
          setState(() => _expandedCashiers.clear());
          ref.read(reportProvider.notifier).loadSalesForFilter(filterKey, force: true);
        }
      },
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.cardBg,
      labelStyle: TextStyle(
        color: isSelected ? AppColors.textOnPrimary : AppColors.textPrimary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderLg,
        side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
      ),
      showCheckmark: false,
    );
  }

  // ── KPI card ─────────────────────────────────────────

  Widget _buildKpiCard(String label, String value, IconData icon, Color accent) {
    return TouchableCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: AppSpacing.borderMd,
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section header ────────────────────────────────────

  Widget _buildSectionHeader(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        if (subtitle != null)
          Text(subtitle,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }

  // ── Cashier summary card ──────────────────────────────

  Widget _buildCashierCard(CashierSummary summary) {
    final isExpanded = _expandedCashiers.contains(summary.cashierId);
    final initial = summary.cashierName.isNotEmpty
        ? summary.cashierName[0].toUpperCase()
        : '?';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: AppSpacing.borderLg,
        border: Border.all(
          color: isExpanded ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border,
          width: isExpanded ? 1.5 : 1.0,
        ),
        boxShadow: isExpanded
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: Column(
        children: [
          // Header row — always visible
          InkWell(
            borderRadius: AppSpacing.borderLg,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (isExpanded) {
                  _expandedCashiers.remove(summary.cashierId);
                } else {
                  _expandedCashiers.add(summary.cashierId);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(initial,
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Name + stats
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(summary.cashierName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          '${summary.transactionCount} sale${summary.transactionCount == 1 ? '' : 's'} • ${CurrencyHelpers.format(summary.totalRevenue)}',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  // Revenue badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyHelpers.format(summary.totalRevenue),
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 15),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expanded: individual sales with item breakdown
          if (isExpanded) ...[
            const Divider(color: AppColors.border, height: 1),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: summary.sales.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppColors.divider, height: 1),
              itemBuilder: (context, i) {
                final sale = summary.sales[i];
                return _buildSaleDetailTile(sale);
              },
            ),
          ],
        ],
      ),
    );
  }

  // ── Individual sale detail tile ───────────────────────

  Widget _buildSaleDetailTile(Sale sale) {
    List<dynamic> items = [];
    try {
      items = jsonDecode(sale.itemsJson);
    } catch (_) {}

    final isMomo = sale.paymentType != 'cash';
    final payColor = isMomo ? AppColors.momoColor : AppColors.cashColor;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sale header: time + payment + total
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: payColor.withValues(alpha: 0.12),
                  borderRadius: AppSpacing.borderSm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMomo ? Icons.phone_android_rounded : Icons.money_rounded,
                      size: 12,
                      color: payColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isMomo ? 'MOMO' : 'CASH',
                      style: TextStyle(
                          color: payColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  DateHelpers.formatDateTime(sale.timestamp),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
              Text(
                CurrencyHelpers.format(sale.totalAmount),
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14),
              ),
            ],
          ),
          // MoMo phone number
          if (isMomo && sale.momoPhone != null && sale.momoPhone!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.phone_rounded,
                    size: 12, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  '${sale.momoPhone}${sale.momoProvider != null ? ' (${sale.momoProvider!.toUpperCase()})' : ''}',
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ],
          // Item list
          if (items.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...items.map((item) {
              final name = item['productName'] as String? ?? 'Unknown';
              final qty = (item['quantity'] as num?)?.toInt() ?? 0;
              final price = (item['price'] as num?)?.toDouble() ?? 0.0;
              return Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    const Icon(Icons.circle,
                        size: 5, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                    ),
                    Text(
                      'x$qty  ${CurrencyHelpers.format(price * qty)}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ── Product summary section ───────────────────────────

  Widget _buildProductSummariesSection(List<ProductSummary> products) {
    if (products.isEmpty) {
      return const AppEmptyState(
        icon: Icons.bar_chart_rounded,
        title: 'No Products Sold Yet',
        description: 'Completed sales will surface product rankings here.',
      );
    }

    final maxQty = products.first.totalQty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: AppSpacing.borderLg,
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: products.take(8).length,
        separatorBuilder: (_, __) =>
            const Divider(color: AppColors.border, height: 1),
        itemBuilder: (ctx, i) {
          final p = products[i];
          final fraction = maxQty > 0 ? p.totalQty / maxQty : 0.0;
          final rankColor = i == 0
              ? AppColors.warning
              : i == 1
                  ? AppColors.textSecondary
                  : AppColors.textMuted;

          return Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Rank badge
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: rankColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${i + 1}',
                            style: TextStyle(
                                color: rankColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(p.productName,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${p.totalQty} sold',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                        Text(CurrencyHelpers.format(p.totalRevenue),
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Visual fraction bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 5,
                    backgroundColor: AppColors.surfaceBg,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Main build ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final reportState = ref.watch(reportProvider);
    final notifier = ref.read(reportProvider.notifier);
    final breakdown = notifier.todayBreakdown;
    final products = ref.watch(productSummariesProvider);
    final cashierAsync = ref.watch(cashierSummariesProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            await notifier.loadSalesForFilter(notifier.currentFilter, force: true);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Section 1: Filter strip ────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _buildFilterChip('today', 'Today'),
                        const SizedBox(width: AppSpacing.sm),
                        _buildFilterChip('week', 'This Week'),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded,
                          color: AppColors.primary),
                      tooltip: 'Refresh',
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        notifier.loadSalesForFilter(notifier.currentFilter,
                            force: true);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── Section 2: KPI Cards ───────────────────
                _buildKpiCard(
                  'Total Revenue',
                  CurrencyHelpers.format(notifier.todayTotal),
                  Icons.account_balance_wallet_rounded,
                  AppColors.primary,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _buildKpiCard(
                        'Cash',
                        CurrencyHelpers.formatCompact(
                            breakdown['cash'] ?? 0.0),
                        Icons.money_rounded,
                        AppColors.cashColor,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _buildKpiCard(
                        'MoMo',
                        CurrencyHelpers.formatCompact(
                            breakdown['momo'] ?? 0.0),
                        Icons.phone_android_rounded,
                        AppColors.momoColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _buildKpiCard(
                  'Total Transactions',
                  '${reportState.length}',
                  Icons.receipt_rounded,
                  AppColors.info,
                ),
                const SizedBox(height: AppSpacing.xxl),

                // ── Section 3: Sales by Cashier ────────────
                _buildSectionHeader(
                  'Sales by Cashier',
                  subtitle: 'Tap a cashier to see their individual transactions',
                ),
                const SizedBox(height: AppSpacing.md),

                if (reportState.isEmpty)
                  AppEmptyState(
                    icon: Icons.analytics_outlined,
                    title: 'No sales recorded yet for this period',
                    description:
                        'Completed sales on the POS screen will automatically populate staff revenue and product rankings here.',
                    actionLabel: 'Generate Demo Sales',
                    onAction: () async {
                      HapticFeedback.mediumImpact();
                      await notifier.seedSampleSales();
                      if (context.mounted) {
                        context.showSuccessSnackbar(
                            'Demo sales generated! Tap a cashier to expand.');
                      }
                    },
                  )
                else
                  cashierAsync.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: CircularProgressIndicator(
                            color: AppColors.primary),
                      ),
                    ),
                    error: (e, _) => Text('Error loading cashier data: $e'),
                    data: (summaries) => Column(
                      children: summaries
                          .map((s) => _buildCashierCard(s))
                          .toList(),
                    ),
                  ),

                const SizedBox(height: AppSpacing.xxl),

                // ── Section 4: What's Selling ──────────────
                _buildSectionHeader(
                  "What's Selling",
                  subtitle: 'Ranked by units sold for the selected period',
                ),
                const SizedBox(height: AppSpacing.md),
                _buildProductSummariesSection(products),
                const SizedBox(height: AppSpacing.xxl),

                // ── Section 5: All Recent Transactions ──────
                _buildSectionHeader('All Recent Transactions'),
                const SizedBox(height: AppSpacing.md),

                if (reportState.isEmpty)
                  AppEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No Transactions Found',
                    description:
                        'Completed transactions appear here in reverse chronological order.',
                    actionLabel: 'Generate Demo Sales',
                    onAction: () async {
                      HapticFeedback.mediumImpact();
                      await notifier.seedSampleSales();
                      if (context.mounted) {
                        context.showSuccessSnackbar('Demo sales generated!');
                      }
                    },
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount:
                        reportState.length > 30 ? 30 : reportState.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (ctx, i) {
                      final sale = reportState[i];
                      return Consumer(
                        builder: (context, ref, _) {
                          final isar = ref.read(isarProvider);
                          return FutureBuilder<String>(
                            future: _resolveCashierName(isar, sale.cashierId),
                            builder: (context, snap) {
                              final cashierName = snap.data ?? '…';
                              return _buildTransactionCard(sale, cashierName);
                            },
                          );
                        },
                      );
                    },
                  ),

                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Transaction card (All Recent Transactions) ────────

  Widget _buildTransactionCard(Sale sale, String cashierName) {
    List<dynamic> items = [];
    try {
      items = jsonDecode(sale.itemsJson);
    } catch (_) {}

    final isMomo = sale.paymentType != 'cash';
    final payColor = isMomo ? AppColors.momoColor : AppColors.cashColor;

    return TouchableCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: payColor.withValues(alpha: 0.15),
                  borderRadius: AppSpacing.borderMd,
                ),
                child: Icon(
                  isMomo ? Icons.phone_android_rounded : Icons.money_rounded,
                  color: payColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            cashierName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: payColor.withValues(alpha: 0.12),
                            borderRadius: AppSpacing.borderSm,
                          ),
                          child: Text(
                            isMomo ? 'MOMO' : 'CASH',
                            style: TextStyle(
                                color: payColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      DateHelpers.formatDateTime(sale.timestamp),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                CurrencyHelpers.format(sale.totalAmount),
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: AppColors.primary),
              ),
            ],
          ),

          // MoMo phone
          if (isMomo && sale.momoPhone != null && sale.momoPhone!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 42),
                const Icon(Icons.phone_rounded,
                    size: 12, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  '${sale.momoPhone}${sale.momoProvider != null ? ' · ${sale.momoProvider!.toUpperCase()}' : ''}',
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ],

          // Item breakdown
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 6),
            ...items.map((item) {
              final name = item['productName'] as String? ?? 'Unknown';
              final qty = (item['quantity'] as num?)?.toInt() ?? 0;
              final price = (item['price'] as num?)?.toDouble() ?? 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const SizedBox(width: 42),
                    const Icon(Icons.circle, size: 5, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                    ),
                    Text(
                      'x$qty  ${CurrencyHelpers.format(price * qty)}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ── Resolve cashier name (used per-card outside notifier) ─

Future<String> _resolveCashierName(Isar isar, int cashierId) async {
  if (cashierId == 0) return 'Unknown Cashier';
  final user = await isar.appUsers.get(cashierId);
  return user?.name ?? 'Unknown Cashier';
}