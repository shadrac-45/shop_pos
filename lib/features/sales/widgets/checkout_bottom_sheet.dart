/// ============================================
/// Checkout Bottom Sheet — ShopPOS
/// ============================================
/// Touch-first checkout drawer featuring:
///   • Enforced 48x48 dp touch boundaries for quantity buttons
///   • Clear payment option selectors (Cash vs MoMo)
///   • Prominent total display
///   • Direct "Complete Sale" action
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/sales/screens/momo_payment_screen.dart';
import 'package:shop_pos/features/sales/widgets/payment_option_button.dart';

class CheckoutBottomSheet extends ConsumerStatefulWidget {
  const CheckoutBottomSheet({super.key});

  @override
  ConsumerState<CheckoutBottomSheet> createState() => _CheckoutBottomSheetState();
}

class _CheckoutBottomSheetState extends ConsumerState<CheckoutBottomSheet> {
  String _selectedPayment = AppConstants.paymentCash;

  static const _paymentOptions = [
    (type: 'cash', icon: Icons.money_rounded, label: 'Cash'),
    (type: 'momo', icon: Icons.phone_android_rounded, label: 'Mobile Money'),
  ];

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final currentUser = ref.watch(currentUserProvider);

    if (cart.isEmpty) {
      Navigator.pop(context);
      return const SizedBox.shrink();
    }

    final total = cartNotifier.totalAmount;
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.85;

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: const BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle Bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Sheet Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Checkout Cart',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                      constraints: AppTouch.touchConstraints,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Cart Item List
                ...cart.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceBg,
                      borderRadius: AppSpacing.borderMd,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.product.name,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${CurrencyHelpers.formatCompact(item.product.price)} each',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),

                        // Quantity Control Strip (Touch Target Enforced)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.danger, size: 22),
                              constraints: AppTouch.touchConstraints,
                              onPressed: () => cartNotifier.updateQuantity(index, -1),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.cardBg,
                                borderRadius: AppSpacing.borderSm,
                              ),
                              child: Text(
                                '${item.quantity}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 22),
                              constraints: AppTouch.touchConstraints,
                              onPressed: () => cartNotifier.updateQuantity(index, 1),
                            ),
                          ],
                        ),
                        const SizedBox(width: AppSpacing.sm),

                        // Subtotal readout
                        SizedBox(
                          width: 70,
                          child: Text(
                            CurrencyHelpers.formatCompact(item.subtotal),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const Divider(height: 32),

                // Total Summary Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: AppSpacing.borderLg,
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Payable',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          CurrencyHelpers.format(total),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // Payment Options
                const Text(
                  'Select Payment Method',
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 14),
                ),
                const SizedBox(height: AppSpacing.md),

                Row(
                  children: _paymentOptions.map((opt) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: opt == _paymentOptions.last ? 0 : AppSpacing.md,
                        ),
                        child: PaymentOptionButton(
                          type: opt.type,
                          icon: opt.icon,
                          label: opt.label,
                          isSelected: _selectedPayment == opt.type,
                          onTap: () => setState(() => _selectedPayment = opt.type),
                          compact: true,
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: AppSpacing.xl),

                // Action Button
                ElevatedButton.icon(
                  onPressed: () => _completeSale(cartNotifier, total,
                      cashierId: currentUser?.id ?? 0),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('Complete Sale'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    minimumSize: const Size(double.infinity, AppTouch.buttonHeight),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _completeSale(
      CartNotifier cartNotifier, double totalAmount,
      {int cashierId = 0}) async {
    if (_selectedPayment == 'momo') {
      Navigator.pop(context);
      Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => MomoPaymentScreen(totalAmount: totalAmount),
        ),
      );
      return;
    }

    final success = await cartNotifier.completeSale(
      _selectedPayment,
      cashierId: cashierId,
    );

    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
      context.showSuccessSnackbar('Sale completed successfully!');
    } else {
      context.showErrorSnackbar('Failed to complete sale. Please try again.');
    }
  }
}
