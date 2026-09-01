/// ============================================
/// Payment Option Button — ShopPOS
/// ============================================
/// Encapsulated, reusable payment method selector
/// button shared by CheckoutBottomSheet and
/// CheckoutScreen. Eliminates duplicated
/// _paymentButton / _buildPaymentOption builders.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:shop_pos/core/theme/app_colors.dart';

/// A single payment method option button (Cash / MoMo / Split).
///
/// Uses [AnimatedContainer] for smooth selection transitions.
/// Consumed polymorphically by any checkout UI surface.
class PaymentOptionButton extends StatelessWidget {
  /// The payment type string (e.g. 'cash', 'momo', 'split').
  final String type;

  /// Icon representing the payment method.
  final IconData icon;

  /// Human-readable label shown below the icon.
  final String label;

  /// Whether this option is currently selected.
  final bool isSelected;

  /// Callback when this option is tapped.
  final VoidCallback onTap;

  /// If true, renders in compact mode (smaller padding) for bottom sheets.
  final bool compact;

  const PaymentOptionButton({
    super.key,
    required this.type,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final verticalPadding = compact ? 12.0 : 16.0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surfaceBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color:
                    isSelected ? AppColors.primary : AppColors.textSecondary,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
