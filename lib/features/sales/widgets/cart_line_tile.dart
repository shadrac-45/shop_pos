/// ============================================
/// Cart Line Tile — ShopPOS
/// ============================================
/// One line of the current sale, shared by the
/// till's cart panel and the checkout sheet:
/// name, unit price and discount, a quantity
/// stepper and the line total. At quantity 1 the
/// minus button becomes a red "remove" button so
/// taking an item off is explicit.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/theme/app_theme.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';
import 'package:shop_pos/features/sales/services/sale_calculator.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';

class CartLineTile extends StatelessWidget {
  final int index;
  final CartItem item;
  final CartNotifier cart;
  final bool canDiscount;

  const CartLineTile({
    super.key,
    required this.index,
    required this.item,
    required this.cart,
    required this.canDiscount,
  });

  Future<void> _editDiscount(BuildContext context) async {
    final v = await askDiscountAmount(
        context, 'Discount on ${item.product.name}', item.gross, item.discount);
    if (v != null) cart.setLineDiscount(index, v);
  }

  @override
  Widget build(BuildContext context) {
    final removing = item.quantity <= 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: AppSpacing.borderMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // The whole name area opens the discount dialog: a ≥ 48dp target,
          // where the small tag alone would be ~20dp.
          Expanded(
            child: Semantics(
              button: canDiscount,
              hint: canDiscount ? 'Set a discount on this line' : null,
              child: InkWell(
                onTap: canDiscount ? () => _editDiscount(context) : null,
                borderRadius: AppSpacing.borderSm,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.minTargetSize),
                  child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.25,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      '${CurrencyHelpers.formatCompact(item.product.price)} each',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontFeatures: AppText.tabular,
                      ),
                    ),
                    if (item.discount > 0)
                      _DiscountTag(label: '−${CurrencyHelpers.formatCompact(item.discount)}')
                    else if (canDiscount)
                      const _DiscountTag(label: 'Discount', add: true),
                  ],
                ),
              ],
            ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _Stepper(
            quantity: item.quantity,
            removing: removing,
            onMinus: () {
              HapticFeedback.selectionClick();
              cart.updateQuantity(index, -1);
            },
            onPlus: () {
              HapticFeedback.selectionClick();
              if (!cart.updateQuantity(index, 1)) {
                context.showErrorSnackbar(
                    'Only ${item.available} "${item.product.name}" in stock.');
              }
            },
          ),
          SizedBox(
            width: 78,
            child: Text(
              CurrencyHelpers.formatCompact(item.subtotal),
              textAlign: TextAlign.right,
              maxLines: 1,
              style: AppText.money(size: 15, weight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _DiscountTag extends StatelessWidget {
  final String label;
  final bool add;
  const _DiscountTag({required this.label, this.add = false});

  @override
  Widget build(BuildContext context) {
    // A discount is a reduction, not an error: green when applied,
    // neutral as an offer to add one.
    final color = add ? AppColors.textSecondary : AppColors.primaryDark;
    // Visual only: the surrounding line area is the tap target.
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: add ? AppColors.surfaceBg : AppColors.primarySoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(add ? Icons.add_rounded : Icons.local_offer_rounded, size: 12, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFeatures: AppText.tabular,
                  )),
            ),
          ],
        ),
    );
  }
}

/// − qty + in one pill, with 48dp buttons.
class _Stepper extends StatelessWidget {
  final int quantity;
  final bool removing;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _Stepper({
    required this.quantity,
    required this.removing,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceBg,
        borderRadius: AppSpacing.borderMd,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: removing ? Icons.delete_outline_rounded : Icons.remove_rounded,
            color: removing ? AppColors.danger : AppColors.textPrimary,
            tooltip: removing ? 'Remove item' : 'One less',
            onTap: onMinus,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 26),
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: AppText.money(size: 16, weight: FontWeight.w800),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            color: AppColors.primaryDark,
            tooltip: 'One more',
            onTap: onPlus,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _StepButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.borderMd,
        child: SizedBox(
          width: AppTouch.minTargetSize,
          height: AppTouch.minTargetSize,
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

/// Asks for a discount in money, with quick percentage chips. Returns the
/// amount (0 to remove), or null if cancelled.
Future<double?> askDiscountAmount(
        BuildContext context, String title, double max, double current) =>
    showAppDialog<double>(
      context: context,
      builder: (_) => _DiscountDialog(title: title, max: max < 0 ? 0 : max, current: current),
    );

/// Owns its text controller so it is disposed with the dialog.
class _DiscountDialog extends StatefulWidget {
  final String title;
  final double max;
  final double current;

  const _DiscountDialog({required this.title, required this.max, required this.current});

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  late final TextEditingController _ctrl = TextEditingController(
      text: widget.current > 0 ? widget.current.toStringAsFixed(2) : '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MoneyField(controller: _ctrl, label: 'Discount amount', autofocus: true),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final pct in [5, 10, 15, 20])
                ActionChip(
                  label: Text('$pct%'),
                  onPressed: () =>
                      _ctrl.text = roundMoney(widget.max * pct / 100).toStringAsFixed(2),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Up to ${CurrencyHelpers.format(widget.max)}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 0.0),
          style: TextButton.styleFrom(foregroundColor: AppColors.dangerDarkText),
          child: const Text('Remove discount'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(
              context, parseMoney(_ctrl.text).clamp(0, widget.max).toDouble()),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
