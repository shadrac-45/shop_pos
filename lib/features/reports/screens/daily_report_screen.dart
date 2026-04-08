/// ============================================
/// Daily Report Screen — ShopPOS
/// ============================================
/// Shows sales metrics, payment split, and top
/// items. Also itemizes past transactions.
/// ============================================
library;

import 'dart:convert'; // For safe itemsJson parsing

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/report_provider.dart';
import '../../../providers/sales_provider.dart';   // ← FIXED: missing import for reportFilterProvider
import '../../../utils/currency_helpers.dart';
import '../../../utils/date_helpers.dart';

class DailyReportScreen extends ConsumerWidget {
  const DailyReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportState = ref.watch(reportProvider);
    final reportNotifier = ref.read(reportProvider.notifier);

    // Load today's sales when screen builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportNotifier.loadTodaySales();
    });

    final todayTotal = reportNotifier.todayTotal;
    final breakdown = reportNotifier.todayBreakdown;

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
              // Filter Buttons (Today / This Week - placeholder for future)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(ref, 'today', 'Today'),
                    const SizedBox(width: 8),
                    _buildFilterChip(ref, 'week', 'This Week'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // KPIs
              Column(
                children: [
                  _buildKpiCard(
                    'Total Revenue',
                    CurrencyHelpers.format(todayTotal),
                    Icons.account_balance_wallet_rounded,
                    AppColors.success,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildKpiCard(
                          'Cash',
                          CurrencyHelpers.formatCompact(breakdown['cash'] ?? 0.0),
                          Icons.money_rounded,
                          AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildKpiCard(
                          'MoMo',
                          CurrencyHelpers.formatCompact(breakdown['momo'] ?? 0.0),
                          Icons.phone_android_rounded,
                          AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildKpiCard(
                    'Transactions',
                    '${reportState.length}',
                    Icons.receipt_rounded,
                    AppColors.info,
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Top Products - Placeholder (can be enhanced later)
              const Text(
                'Top Products Sold',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'Top products feature coming soon...',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Recent Transactions
              const Text(
                'Recent Transactions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),

              if (reportState.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No transactions today yet',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: reportState.length > 20 ? 20 : reportState.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final sale = reportState[i];

                    // Fixed: Properly count items from the stored JSON string
                    int itemCount = 0;
                    try {
                      final List<dynamic> items = jsonDecode(sale.itemsJson);
                      itemCount = items.length;
                    } catch (_) {
                      itemCount = 0; // fallback
                    }

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
                              Text(
                                '$itemCount items',
                                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateHelpers.formatShort(sale.timestamp),
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                CurrencyHelpers.format(sale.totalAmount),
                                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  sale.paymentType.toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(WidgetRef ref, String value, String label) {
    final currentFilter = ref.watch(reportFilterProvider);
    final isSelected = currentFilter == value;

    return InkWell(
      onTap: () => ref.read(reportFilterProvider.notifier).state = value,
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
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}