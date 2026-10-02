/// ============================================
/// Stock History Screen — ShopPOS
/// ============================================
/// Every stock movement for one product: who
/// changed it, when, by how much and why.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/stock_movement.dart';
import 'package:shop_pos/features/products/services/inventory_service.dart';
import 'package:shop_pos/features/sales/screens/sale_detail_screen.dart';
import 'package:shop_pos/features/shared/widgets/app_empty_state.dart';

class StockHistoryScreen extends ConsumerWidget {
  final Product product;
  const StockHistoryScreen({super.key, required this.product});

  Future<(List<StockMovement>, Map<int, String>)> _load(Isar isar) async {
    final movements = await InventoryService.movementsFor(isar, product.id);
    final users = await isar.appUsers.where().findAll();
    return (movements, {for (final u in users) u.id: u.name});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isar = ref.watch(isarProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text('Stock history — ${product.name}'),
        backgroundColor: AppColors.cardBg,
      ),
      body: FutureBuilder(
        future: _load(isar),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (movements, names) = snap.data!;
          if (movements.isEmpty) {
            return const AppEmptyState(
              icon: Icons.history_rounded,
              title: 'No stock movements yet',
              description:
                  'Sales, restocks and adjustments made from now on are listed here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: movements.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = movements[i];
              final positive = m.quantityChange > 0;
              final details = [
                StockMovementType.label(m.type),
                if (m.reason != null) AdjustmentReason.label(m.reason!),
                if (m.note != null && m.note!.isNotEmpty) m.note!,
              ].join(' · ');
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      (positive ? AppColors.success : AppColors.danger).withValues(alpha: 0.12),
                  child: Text(
                    '${positive ? '+' : ''}${m.quantityChange}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: positive ? AppColors.success : AppColors.danger,
                    ),
                  ),
                ),
                title: Text(details),
                subtitle: Text(
                  '${DateHelpers.formatDateTime(m.timestamp)} · '
                  '${m.userId == 0 ? 'System' : names[m.userId] ?? 'Staff #${m.userId}'}',
                ),
                trailing: m.saleId == null
                    ? null
                    : const Icon(Icons.receipt_long_rounded, color: AppColors.textSecondary),
                onTap: m.saleId == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => SaleDetailScreen(saleId: m.saleId!),
                        )),
              );
            },
          );
        },
      ),
    );
  }
}
