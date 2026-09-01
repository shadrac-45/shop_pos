/// ============================================
/// Manage Staff Screen — ShopPOS
/// ============================================
/// Owner-only screen for creating, viewing, and
/// managing cashier accounts and their login PINs.
/// Cashiers CANNOT access this screen.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/settings/providers/staff_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';
import 'package:shop_pos/features/settings/widgets/add_cashier_dialog.dart';
import 'package:shop_pos/features/settings/widgets/reset_pin_dialog.dart';

class ManageStaffScreen extends ConsumerStatefulWidget {
  const ManageStaffScreen({super.key});

  @override
  ConsumerState<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends ConsumerState<ManageStaffScreen> {
  List<AppUser> _cashiers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCashiers();
  }

  Future<void> _loadCashiers() async {
    setState(() => _isLoading = true);
    final service = ref.read(staffProvider);
    final cashiers = await service.getAllCashiers();
    if (mounted) {
      setState(() {
        _cashiers = cashiers;
        _isLoading = false;
      });
    }
  }

  Future<void> _openAddCashierDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AddCashierDialog(),
    );
    if (result == true) {
      await _loadCashiers();
      if (mounted) context.showSuccessSnackbar('Cashier account created successfully!');
    }
  }

  Future<void> _toggleActivation(AppUser cashier) async {
    HapticFeedback.mediumImpact();
    final service = ref.read(staffProvider);
    final isCurrentlyActive = cashier.isActive;
    final action = isCurrentlyActive ? 'Deactivate' : 'Reactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderLg),
        title: Text(
          '$action ${cashier.name}?',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          isCurrentlyActive
              ? 'This cashier will not be able to log in with their PIN. Their sales history will be preserved.'
              : 'This cashier will be able to log in again with their assigned PIN.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isCurrentlyActive ? AppColors.danger : AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = isCurrentlyActive
        ? await service.deactivateCashier(cashier.id)
        : await service.reactivateCashier(cashier.id);

    if (result == StaffOperationResult.success) {
      await _loadCashiers();
      if (mounted) {
        context.showSuccessSnackbar(
          isCurrentlyActive ? '${cashier.name} deactivated.' : '${cashier.name} reactivated.',
        );
      }
    }
  }

  Future<void> _openResetPinDialog(AppUser cashier) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ResetPinDialog(cashier: cashier),
    );
    if (result == true && mounted) {
      context.showSuccessSnackbar('PIN reset for ${cashier.name}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Manage Staff'),
        backgroundColor: AppColors.cardBg,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            tooltip: 'Refresh',
            onPressed: _loadCashiers,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddCashierDialog,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text(
          'Add Cashier',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _cashiers.isEmpty
                ? _buildEmptyState()
                : _buildCashierList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.group_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'No cashier accounts yet',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Tap "Add Cashier" to assign a name and 4-digit PIN.\nCashiers log in immediately using their PIN.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxl),
            ElevatedButton.icon(
              onPressed: _openAddCashierDialog,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Add First Cashier'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashierList() {
    final active = _cashiers.where((c) => c.isActive).toList();
    final inactive = _cashiers.where((c) => !c.isActive).toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _buildStatsBanner(active.length, inactive.length),
        const SizedBox(height: AppSpacing.xl),

        if (active.isNotEmpty) ...[
          _buildSectionHeader('ACTIVE STAFF', active.length, AppColors.success),
          const SizedBox(height: AppSpacing.sm),
          ...active.map((c) => _buildCashierCard(c)),
        ],

        if (inactive.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          _buildSectionHeader('DEACTIVATED', inactive.length, AppColors.danger),
          const SizedBox(height: AppSpacing.sm),
          ...inactive.map((c) => _buildCashierCard(c)),
        ],

        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildStatsBanner(int active, int total) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: AppSpacing.borderLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: AppSpacing.borderMd,
            ),
            child: const Icon(Icons.people_rounded, color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$active Active ${active == 1 ? 'Cashier' : 'Cashiers'}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_cashiers.length} total staff accounts',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count, Color color) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.textSecondary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: AppSpacing.borderSm,
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCashierCard(AppUser cashier) {
    final isActive = cashier.isActive;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TouchableCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        borderColor: isActive
            ? AppColors.border
            : AppColors.danger.withValues(alpha: 0.3),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (isActive ? AppColors.primary : AppColors.textMuted)
                    .withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  cashier.name[0].toUpperCase(),
                  style: TextStyle(
                    color: isActive ? AppColors.primary : AppColors.textMuted,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          cashier.name,
                          style: TextStyle(
                            color: isActive
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isActive ? AppColors.success : AppColors.danger)
                              .withValues(alpha: 0.15),
                          borderRadius: AppSpacing.borderSm,
                        ),
                        child: Text(
                          isActive ? 'ACTIVE' : 'INACTIVE',
                          style: TextStyle(
                            color: isActive ? AppColors.success : AppColors.danger,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(Icons.pin_rounded, size: 12, color: AppColors.textMuted),
                      SizedBox(width: 4),
                      Text(
                        'PIN Login Protected',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Actions menu
            PopupMenuButton<_CashierAction>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.textSecondary),
              color: AppColors.cardBg,
              shape: RoundedRectangleBorder(
                  borderRadius: AppSpacing.borderMd,
                  side: const BorderSide(color: AppColors.border)),
              onSelected: (action) {
                switch (action) {
                  case _CashierAction.toggleActive:
                    _toggleActivation(cashier);
                  case _CashierAction.resetPin:
                    _openResetPinDialog(cashier);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _CashierAction.resetPin,
                  child: Row(
                    children: [
                      Icon(Icons.lock_reset_rounded,
                          size: 18, color: AppColors.info),
                      SizedBox(width: AppSpacing.sm),
                      Text('Reset PIN',
                          style: TextStyle(color: AppColors.textPrimary)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: _CashierAction.toggleActive,
                  child: Row(
                    children: [
                      Icon(
                        isActive
                            ? Icons.block_rounded
                            : Icons.check_circle_rounded,
                        size: 18,
                        color: isActive ? AppColors.danger : AppColors.success,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        isActive ? 'Deactivate' : 'Reactivate',
                        style: TextStyle(
                          color: isActive ? AppColors.danger : AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _CashierAction { toggleActive, resetPin }
