/// ============================================
/// Cart Panel — ShopPOS
/// ============================================
/// The current sale, kept on screen beside the
/// catalogue on tablets and desktops (the split
/// layout Shopify POS and Square use), so the
/// cashier never has to open a sheet to check
/// what has been rung up. Frosted glass: it is
/// the one floating surface on the till.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/theme/app_theme.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';
import 'package:shop_pos/features/sales/services/sale_calculator.dart';
import 'package:shop_pos/features/sales/widgets/cart_line_tile.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';

class CartPanel extends ConsumerWidget {
  /// Opens payment for the current cart.
  final VoidCallback onCharge;

  const CartPanel({super.key, required this.onCharge});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final totals = ref.watch(cartTotalsProvider);
    final canDiscount = Permissions.can(ref.watch(currentUserProvider), Permission.discount);
    final count = ref.watch(cartItemCountProvider);

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.sm),
            child: Row(
              children: [
                const Text(
                  'Current sale',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        fontFeatures: AppText.tabular,
                      ),
                    ),
                  ),
                const Spacer(),
                if (cart.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Clear this sale?',
                        message: 'All $count item${count == 1 ? '' : 's'} will be taken off the cart.',
                        confirmLabel: 'Clear sale',
                        destructive: true,
                      );
                      if (ok) notifier.clearCart();
                    },
                    style: TextButton.styleFrom(foregroundColor: AppColors.dangerDarkText),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Clear'),
                  ),
              ],
            ),
          ),

          // ── Lines ───────────────────────────────
          Expanded(
            child: cart.isEmpty
                ? const _EmptyCart()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
                    itemCount: cart.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) => CartLineTile(
                      key: ValueKey(cart[i].product.id),
                      index: i,
                      item: cart[i],
                      cart: notifier,
                      canDiscount: canDiscount,
                    ),
                  ),
          ),

          // ── Totals + Charge ─────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.glassStroke)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canDiscount && cart.isNotEmpty)
                  SaleDiscountButton(totals: totals),
                CartTotalsSummary(totals: totals),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton(
                  onPressed: cart.isEmpty ? null : onCharge,
                  style: AppButtons.pay(),
                  child: Text(cart.isEmpty
                      ? 'Charge'
                      : 'Charge  ${CurrencyHelpers.format(totals.total)}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_basket_outlined, size: 40, color: AppColors.borderStrong),
            SizedBox(height: AppSpacing.md),
            Text(
              'No items yet',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
            ),
            SizedBox(height: 4),
            Text(
              'Tap a product or scan a barcode to start a sale.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Add sale discount" / "Sale discount −X" link above the totals.
class SaleDiscountButton extends ConsumerWidget {
  final SaleTotals totals;
  const SaleDiscountButton({super.key, required this.totals});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final has = totals.saleDiscount > 0;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () async {
          final current = ref.read(cartSaleDiscountProvider);
          final value =
              await askDiscountAmount(context, 'Discount on whole sale', totals.subtotal, current);
          if (value != null) ref.read(cartSaleDiscountProvider.notifier).state = value;
        },
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        ),
        icon: Icon(has ? Icons.local_offer_rounded : Icons.local_offer_outlined, size: 18),
        label: Text(has
            ? 'Sale discount −${CurrencyHelpers.format(totals.saleDiscount)}'
            : 'Add sale discount'),
      ),
    );
  }
}

/// Subtotal, discounts and VAT, then the total in large tabular figures.
class CartTotalsSummary extends StatelessWidget {
  final SaleTotals totals;
  final bool large;
  const CartTotalsSummary({super.key, required this.totals, this.large = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row('Subtotal', CurrencyHelpers.format(totals.grossSubtotal)),
        if (totals.discountTotal > 0)
          _row('Discounts', '−${CurrencyHelpers.format(totals.discountTotal)}'),
        if (totals.taxRate > 0)
          _row(
            'VAT ${totals.taxRate % 1 == 0 ? totals.taxRate.toInt() : totals.taxRate}%'
            '${totals.pricesIncludeTax ? ' (included)' : ''}',
            CurrencyHelpers.format(totals.taxAmount),
          ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text('Total',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  CurrencyHelpers.format(totals.total),
                  style: AppText.money(size: large ? 28 : 24, weight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ),
          Text(value,
              style: AppText.money(
                  size: 14, weight: FontWeight.w600, color: color ?? AppColors.textPrimary)),
        ],
      ),
    );
  }
}
