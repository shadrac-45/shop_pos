/// ============================================
/// Daily Report Screen — ShopPOS
/// ============================================
/// Shows sales metrics, payment split, and top
/// items. Also itemizes past transactions.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/report_provider.dart';
import '../../../utils/currency_helpers.dart';
import '../../../utils/date_helpers.dart';

class DailyReportScreen extends ConsumerWidget {
  const DailyReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final kpisAsync = ref.watch(reportKpisProvider);
    final topProductsAsync = ref.watch(topProductsProvider);
    final salesAsync = ref.watch(filteredSalesProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Reports', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.cardBg,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Filter Buttons ──
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(ref, ReportFilter.today, 'Today', filter),
                    const SizedBox(width: 8),
                    _buildFilterChip(ref, ReportFilter.thisWeek, 'This Week', filter),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── KPIs Header ──
              kpisAsync.when(
                data: (kpis) => Column(
                  children: [
                    _buildKpiCard('Total Revenue', CurrencyHelpers.format(kpis.revenue), Icons.account_balance_wallet_rounded, AppColors.success),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildKpiCard('Cash', CurrencyHelpers.formatCompact(kpis.cashAmt), Icons.money_rounded, AppColors.primary)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKpiCard('MoMo', CurrencyHelpers.formatCompact(kpis.momoAmt), Icons.phone_android_rounded, AppColors.warning)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildKpiCard('Transactions', '${kpis.transactions}', Icons.receipt_rounded, AppColors.info),
                  ],
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error loading data: $e')),
              ),

              const SizedBox(height: 32),

              // ── Top Products ──
              const Text('Top Products Sold', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              topProductsAsync.when(
                data: (products) {
                  if (products.isEmpty) return const Text('No sales yet', style: TextStyle(color: AppColors.textSecondary));
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const Divider(color: AppColors.border, height: 1),
                      itemBuilder: (ctx, i) {
                        final p = products[i];
                        return ListTile(
                          leading: CircleAvatar(backgroundColor: AppColors.surfaceBg, child: Text('#${i + 1}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13))),
                          title: Text(p.name, style: const TextStyle(color: AppColors.textPrimary)),
                          trailing: Text('${p.qty} sold', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const SizedBox(),
              ),

              const SizedBox(height: 32),

              // ── Recent Transactions ──
              const Text('Recent Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              salesAsync.when(
                data: (sales) {
                  if (sales.isEmpty) return const Text('No transactions match the filter', style: TextStyle(color: AppColors.textSecondary));
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sales.length > 20 ? 20 : sales.length, // Limit to 20 for preview
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final sale = sales[i];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${sale.totalItems} items', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text(DateHelpers.formatShort(sale.timestamp), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(CurrencyHelpers.format(sale.totalAmount), style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.cardBg,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    sale.paymentType.toUpperCase(),
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const SizedBox(),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(WidgetRef ref, ReportFilter filterVal, String label, ReportFilter currentFilter) {
    final isSelected = filterVal == currentFilter;
    return InkWell(
      onTap: () => ref.read(reportFilterProvider.notifier).state = filterVal,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              ],
            ),
          )
        ],
      ),
    );
  }
}
