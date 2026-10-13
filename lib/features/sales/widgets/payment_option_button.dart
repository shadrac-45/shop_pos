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
import 'package:shop_pos/core/theme/app_motion.dart';

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
    final fg = isSelected ? AppColors.successDarkText : AppColors.textPrimary;
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            height: compact ? 76 : 92,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primarySoft : AppColors.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          color: isSelected ? AppColors.primaryDark : AppColors.textSecondary,
                          size: 26),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            color: fg,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // A tick as well as the colour, so the choice never relies
                // on colour alone.
                if (isSelected)
                  const Positioned(
                    top: 6,
                    right: 0,
                    child: Icon(Icons.check_circle_rounded, size: 16, color: AppColors.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
