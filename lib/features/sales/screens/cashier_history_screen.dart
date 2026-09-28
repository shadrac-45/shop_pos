/// ============================================
/// Cashier History Screen — ShopPOS
/// ============================================
/// Dedicated sales history & totals dashboard for
/// cashiers to track all sales they have made.
/// Real-time auto updates, period filter, search,
/// and expandable item breakdown receipts.
/// ============================================
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/providers/cashier_sales_provider.dart';
import 'package:shop_pos/features/shared/widgets/app_empty_state.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';

class CashierHistoryScreen extends ConsumerStatefulWidget {
  const CashierHistoryScreen({super.key});

  @override
  ConsumerState<CashierHistoryScreen> createState() =>
      _CashierHistoryScreenState();
}

class _CashierHistoryScreenState extends ConsumerState<CashierHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<int> _expandedSaleIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleExpand(int saleId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_expandedSaleIds.contains(saleId)) {
        _expandedSaleIds.remove(saleId);
      } else {
        _expandedSaleIds.add(saleId);
      }
    });
  }

  // ── Period Choice Chip ──────────────────────────────────────────

  Widget _buildPeriodChip(CashierSalesPeriod period, String label) {
    final current = ref.watch(cashierSalesPeriodProvider);
    final isSelected = current == period;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          HapticFeedback.selectionClick();
          ref.read(cashierSalesPeriodProvider.notifier).state = period;
        }
      },
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.cardBg,
      labelStyle: TextStyle(
        color: isSelected ? AppColors.textOnPrimary : AppColors.textPrimary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderLg,
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
        ),
      ),
      showCheckmark: false,
    );
  }

  // ── KPI Summary Card ────────────────────────────────────────────

  Widget _buildKpiPill({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppSpacing.borderMd,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final salesAsync = ref.watch(cashierSalesStreamProvider);
    final stats = ref.watch(cashierSalesStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            // Force stream re-subscription
            ref.invalidate(cashierSalesStreamProvider);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Header Banner & Stats ─────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cashier Info Row
                      Row(
                        children: [
                          if (Navigator.of(context).canPop()) ...[
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded,
                                  color: AppColors.textPrimary),
                              tooltip: 'Back',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            const SizedBox(width: 4),
                          ],
                          CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.2),
                            child: const Icon(
                              Icons.person_rounded,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentUser?.name ?? 'Cashier',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Text(
                                  'My Sales History & Summary',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // Filter Strip
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildPeriodChip(
                                CashierSalesPeriod.today, 'Today'),
                            const SizedBox(width: 8),
                            _buildPeriodChip(
                                CashierSalesPeriod.week, 'This Week'),
                            const SizedBox(width: 8),
                            _buildPeriodChip(
                                CashierSalesPeriod.all, 'All Time'),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // ── Hero Total Sales Made Card ─────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: AppSpacing.borderLg,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'TOTAL SALES MADE',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: AppSpacing.borderSm,
                                  ),
                                  child: Text(
                                    '${stats.totalCount} sale${stats.totalCount == 1 ? '' : 's'}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                CurrencyHelpers.format(stats.totalRevenue),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.sm),

                      // ── Sub-KPIs: Cash vs MoMo ─────────────────
                      Row(
                        children: [
                          Expanded(
                            child: _buildKpiPill(
                              label: 'Cash (${stats.cashCount})',
                              value: CurrencyHelpers.formatCompact(
                                  stats.cashRevenue),
                              icon: Icons.payments_rounded,
                              color: AppColors.cashColor,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _buildKpiPill(
                              label: 'MoMo (${stats.momoCount})',
                              value: CurrencyHelpers.formatCompact(
                                  stats.momoRevenue),
                              icon: Icons.phone_android_rounded,
                              color: AppColors.momoColor,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // ── Search bar ─────────────────────────────
                      TextField(
                        controller: _searchController,
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.trim()),
                        style:
                            const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search sale ID, product, or payment...',
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: AppColors.textSecondary),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded,
                                      color: AppColors.textSecondary,
                                      size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ),

              // ── Sales History List ────────────────────────────
              salesAsync.when(
                data: (allSales) {
                  final filteredSales = allSales.where((s) {
                    if (_searchQuery.isEmpty) return true;
                    final q = _searchQuery.toLowerCase();
                    final idStr = '#${s.id}';
                    final paymentStr = s.paymentType.toLowerCase();
                    final itemsStr = s.itemsJson.toLowerCase();
                    final phoneStr = (s.momoPhone ?? '').toLowerCase();
                    return idStr.contains(q) ||
                        paymentStr.contains(q) ||
                        itemsStr.contains(q) ||
                        phoneStr.contains(q);
                  }).toList();

                  if (filteredSales.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: AppEmptyState(
                        icon: Icons.receipt_long_rounded,
                        title: _searchQuery.isNotEmpty
                            ? 'No Matching Sales'
                            : 'No Sales Recorded',
                        description: _searchQuery.isNotEmpty
                            ? 'No transactions found for "$_searchQuery".'
                            : 'You haven\'t made any sales in this period yet.',
                        actionLabel: _searchQuery.isNotEmpty
                            ? 'Clear Search'
                            : null,
                        onAction: _searchQuery.isNotEmpty
                            ? () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              }
                            : null,
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final sale = filteredSales[index];
                          final isExpanded =
                              _expandedSaleIds.contains(sale.id);
                          return _buildSaleCard(sale, isExpanded);
                        },
                        childCount: filteredSales.length,
                      ),
                    ),
                  );
                },
                loading: () => const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
                error: (err, _) => SliverFillRemaining(
                  child: AppEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Error Loading Sales',
                    description: err.toString(),
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 80),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sale Item Card ──────────────────────────────────────────────

  Widget _buildSaleCard(Sale sale, bool isExpanded) {
    List<dynamic> items = [];
    try {
      items = jsonDecode(sale.itemsJson);
    } catch (_) {}

    final isCash = sale.paymentType == 'cash';
    final payColor = isCash ? AppColors.cashColor : AppColors.momoColor;
    final totalItemsCount = items.fold<int>(
      0,
      (sum, item) => sum + ((item['quantity'] as num?)?.toInt() ?? 1),
    );

    return TouchableCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => _toggleExpand(sale.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Row
          Row(
            children: [
              // Icon Badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: payColor.withValues(alpha: 0.15),
                  borderRadius: AppSpacing.borderMd,
                ),
                child: Icon(
                  isCash
                      ? Icons.payments_rounded
                      : Icons.phone_android_rounded,
                  color: payColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // Title and timestamp
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Sale #${sale.id}',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: payColor.withValues(alpha: 0.15),
                            borderRadius: AppSpacing.borderSm,
                          ),
                          child: Text(
                            isCash ? 'CASH' : 'MOMO',
                            style: TextStyle(
                              color: payColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateHelpers.formatDateTime(sale.timestamp),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // Total Amount & Chevron
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyHelpers.format(sale.totalAmount),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$totalItemsCount item${totalItemsCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // ── Expanded Receipt Items ─────────────────────────────
          if (isExpanded) ...[
            const Divider(height: 20, color: AppColors.border),
            const Text(
              'Items Purchased:',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ...items.map((item) {
              final name = item['productName'] ?? 'Product';
              final qty = item['quantity'] ?? 1;
              final price = (item['price'] as num?)?.toDouble() ?? 0.0;
              final subtotal = qty * price;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${qty}x',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '$name',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      CurrencyHelpers.format(subtotal),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (sale.momoPhone != null && sale.momoPhone!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.phone_iphone_rounded,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Customer MoMo: ${sale.momoPhone}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
