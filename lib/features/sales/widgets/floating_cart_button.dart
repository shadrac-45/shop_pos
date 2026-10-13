/// ============================================
/// Floating Cart Button — ShopPOS
/// ============================================
/// The phone / narrow-tablet cart: a frosted
/// pill floating over the catalogue, bottom-right,
/// so it stays in reach while browsing without a
/// full-width bar taking a row of products.
///
///   [🛒 ³]  GH₵ 97.00 · View cart
///
/// The green cart disc carries a count badge that
/// pops whenever an item is added; the total
/// slides in once there is something to pay for.
/// Tapping opens the cart/checkout sheet.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_motion.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/theme/app_theme.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';

/// Space to leave under scrolling content so the last row clears the
/// floating cart.
const double kFloatingCartClearance = 96;

class FloatingCartButton extends ConsumerStatefulWidget {
  final VoidCallback onOpen;
  const FloatingCartButton({super.key, required this.onOpen});

  @override
  ConsumerState<FloatingCartButton> createState() => _FloatingCartButtonState();
}

class _FloatingCartButtonState extends ConsumerState<FloatingCartButton>
    with SingleTickerProviderStateMixin {
  /// Drives the "item added" bump: a quick scale up and settle.
  late final AnimationController _bump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 65),
  ]).animate(_bump);

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(cartItemCountProvider);
    final total = ref.watch(cartTotalsProvider).total;
    final empty = count == 0;

    // Bump on every increase (adds); stay still on removals.
    ref.listen<int>(cartItemCountProvider, (prev, next) {
      if (next > (prev ?? 0) && !AppMotion.reduced(context)) _bump.forward(from: 0);
    });

    final disc = ScaleTransition(
      scale: _scale,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: AppMotion.fast,
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: empty ? AppColors.surfaceBg : AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.shopping_cart_rounded,
              size: 24,
              color: empty ? AppColors.textMuted : AppColors.textOnPrimary,
            ),
          ),
          if (!empty)
            Positioned(
              top: -4,
              right: -4,
              child: AnimatedSwitcher(
                duration: AppMotion.fast,
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Container(
                  key: ValueKey(count),
                  constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      fontFeatures: AppText.tabular,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: !empty,
      label: empty
          ? 'Cart is empty'
          : 'Cart, $count item${count == 1 ? '' : 's'}, ${CurrencyHelpers.format(total)}. Open cart',
      excludeSemantics: true,
      // Not frosted: it floats over the scrolling grid, where a live blur
      // would re-run every scroll frame.
      child: GlassPanel(
        frosted: false,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: empty
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    widget.onOpen();
                  },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: AnimatedSize(
                duration: AppMotion.medium,
                curve: AppMotion.curve,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    disc,
                    if (!empty) ...[
                      const SizedBox(width: AppSpacing.md),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            CurrencyHelpers.format(total),
                            style: AppText.money(size: 17, weight: FontWeight.w800),
                          ),
                          const Text(
                            'View cart',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.primaryDark),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
