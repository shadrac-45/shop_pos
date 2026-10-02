/// ============================================
/// Checkout Bottom Sheet — ShopPOS
/// ============================================
/// Touch-first checkout drawer:
///   • Cart lines with quantity steppers and,
///     for managers/owners, line discounts
///   • Sale discount, VAT and total breakdown
///   • Payment by any method the store enables
///     (Cash / MoMo / Card / QR), or split across
///     several
///   • Cash received → change due
/// On success it opens the receipt.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/services/session_manager.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';
import 'package:shop_pos/features/sales/screens/momo_payment_screen.dart';
import 'package:shop_pos/features/sales/screens/sale_detail_screen.dart';
import 'package:shop_pos/features/sales/services/sale_calculator.dart';
import 'package:shop_pos/features/sales/services/sale_service.dart';
import 'package:shop_pos/features/sales/widgets/payment_option_button.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';

/// One editable payment row in split mode.
class _SplitRow {
  String method;
  final TextEditingController amount = TextEditingController();
  final TextEditingController reference = TextEditingController();
  _SplitRow(this.method);

  void dispose() {
    amount.dispose();
    reference.dispose();
  }
}

class CheckoutBottomSheet extends ConsumerStatefulWidget {
  const CheckoutBottomSheet({super.key});

  @override
  ConsumerState<CheckoutBottomSheet> createState() => _CheckoutBottomSheetState();
}

class _CheckoutBottomSheetState extends ConsumerState<CheckoutBottomSheet> {
  String? _selectedMethod;
  bool _split = false;
  final List<_SplitRow> _splitRows = [];
  final _tenderedCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  bool _isCompleting = false;

  @override
  void dispose() {
    _tenderedCtrl.dispose();
    _referenceCtrl.dispose();
    for (final r in _splitRows) {
      r.dispose();
    }
    super.dispose();
  }

  // ── Payment assembly ────────────────────────────────────────────────

  /// Cash portion of the payment (what the till keeps, before change).
  double _cashDue(double total) {
    if (!_split) {
      return _selectedMethod == AppConstants.paymentCash ? total : 0;
    }
    return roundMoney(_splitRows
        .where((r) => r.method == AppConstants.paymentCash)
        .fold(0.0, (s, r) => s + parseMoney(r.amount.text)));
  }

  double _splitPaid() =>
      roundMoney(_splitRows.fold(0.0, (s, r) => s + parseMoney(r.amount.text)));

  void _toggleSplit(List<String> methods, double total) {
    setState(() {
      _split = !_split;
      for (final r in _splitRows) {
        r.dispose();
      }
      _splitRows.clear();
      if (_split) {
        final first = _SplitRow(AppConstants.paymentCash)..amount.text = '';
        final second = _SplitRow(methods.firstWhere(
            (m) => m != AppConstants.paymentCash,
            orElse: () => AppConstants.paymentCash));
        _splitRows.addAll([first, second]);
      }
    });
  }

  Future<void> _complete(SaleTotals totals) async {
    if (_isCompleting) return;
    final total = totals.total;
    final List<PaymentInput> payments;

    if (_split) {
      final paid = _splitPaid();
      if ((paid - total).abs() > 0.005) {
        context.showErrorSnackbar(
            'Split payments add up to ${CurrencyHelpers.format(paid)}; the total is ${CurrencyHelpers.format(total)}.');
        return;
      }
      final momoRows =
          _splitRows.where((r) => r.method == AppConstants.paymentMomo).toList();
      if (momoRows.length > 1) {
        context.showErrorSnackbar('Use only one Mobile Money part per sale.');
        return;
      }
      payments = [
        for (final r in _splitRows)
          if (r.method != AppConstants.paymentMomo && parseMoney(r.amount.text) > 0)
            PaymentInput(r.method, parseMoney(r.amount.text),
                reference: r.reference.text.trim().isEmpty ? null : r.reference.text.trim()),
      ];
      if (momoRows.isNotEmpty && parseMoney(momoRows.first.amount.text) > 0) {
        return _goToMomo(parseMoney(momoRows.first.amount.text), payments, totals);
      }
    } else {
      final method = _selectedMethod;
      if (method == null) {
        context.showErrorSnackbar('Choose how the customer is paying.');
        return;
      }
      if (method == AppConstants.paymentMomo) {
        return _goToMomo(total, const [], totals);
      }
      payments = [
        PaymentInput(method, total,
            reference: _referenceCtrl.text.trim().isEmpty ? null : _referenceCtrl.text.trim()),
      ];
    }

    final tendered = _tenderedCtrl.text.trim().isEmpty ? null : parseMoney(_tenderedCtrl.text);
    final cashDue = _cashDue(total);
    if (tendered != null && tendered + 0.005 < cashDue) {
      context.showErrorSnackbar(
          'Cash received is less than the ${CurrencyHelpers.format(cashDue)} due in cash.');
      return;
    }

    setState(() => _isCompleting = true);
    ref.read(sessionManagerProvider).recordActivity();
    final navigator = Navigator.of(context);
    try {
      final sale = await ref.read(cartProvider.notifier).completeSale(
            payments: payments,
            amountTendered: cashDue > 0 ? tendered : null,
          );
      HapticFeedback.heavyImpact();
      navigator.pop();
      navigator.push(MaterialPageRoute(
        builder: (_) => SaleDetailScreen(saleId: sale.id, justCompleted: true),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCompleting = false);
      context.showErrorSnackbar(errorMessage(e));
    }
  }

  void _goToMomo(double momoAmount, List<PaymentInput> otherPayments, SaleTotals totals) {
    final tendered = _tenderedCtrl.text.trim().isEmpty ? null : parseMoney(_tenderedCtrl.text);
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(
      builder: (_) => MomoPaymentScreen(
        totalAmount: momoAmount,
        otherPayments: otherPayments,
        amountTendered: _cashDue(totals.total) > 0 ? tendered : null,
      ),
    ));
  }

  // ── Discounts ───────────────────────────────────────────────────────

  Future<double?> _askAmount(String title, double max, double current) async {
    final ctrl = TextEditingController(
        text: current > 0 ? current.toStringAsFixed(2) : '');
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MoneyField(controller: ctrl, label: 'Discount amount', autofocus: true),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: [
                for (final pct in [5, 10, 20])
                  ActionChip(
                    label: Text('$pct%'),
                    onPressed: () =>
                        ctrl.text = roundMoney(max * pct / 100).toStringAsFixed(2),
                  ),
              ],
            ),
            Text('Up to ${CurrencyHelpers.format(max)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 0.0), child: const Text('Remove')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, parseMoney(ctrl.text).clamp(0, max).toDouble()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final totals = ref.watch(cartTotalsProvider);
    final methods = ref.watch(enabledPaymentMethodsProvider);
    final canDiscount =
        Permissions.can(ref.watch(currentUserProvider), Permission.discount);

    if (cart.isEmpty && !_isCompleting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    }
    _selectedMethod ??= methods.isNotEmpty ? methods.first : null;

    final mediaQuery = MediaQuery.of(context);
    final total = totals.total;
    final cashDue = _cashDue(total);
    final tendered = parseMoney(_tenderedCtrl.text);
    final change = SaleCalculator.changeDue(tendered: tendered, cashDue: cashDue);

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: const BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.9),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Checkout', style: Theme.of(context).textTheme.headlineLarge),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                      constraints: AppTouch.touchConstraints,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Cart lines ────────────────────────────────
                for (var index = 0; index < cart.length; index++)
                  _buildLine(index, cart[index], cartNotifier, canDiscount),

                if (canDiscount)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final current = ref.read(cartSaleDiscountProvider);
                        final value = await _askAmount(
                            'Discount on whole sale', totals.subtotal, current);
                        if (value != null) {
                          ref.read(cartSaleDiscountProvider.notifier).state = value;
                        }
                      },
                      icon: const Icon(Icons.local_offer_outlined, size: 18),
                      label: Text(totals.saleDiscount > 0
                          ? 'Sale discount: −${CurrencyHelpers.format(totals.saleDiscount)}'
                          : 'Add sale discount'),
                    ),
                  ),

                const Divider(height: 24),

                // ── Totals ────────────────────────────────────
                _totalRow('Subtotal', totals.grossSubtotal),
                if (totals.discountTotal > 0)
                  _totalRow('Discounts', -totals.discountTotal, color: AppColors.danger),
                if (totals.taxRate > 0)
                  _totalRow(
                    'VAT ${totals.taxRate % 1 == 0 ? totals.taxRate.toInt() : totals.taxRate}%'
                    '${totals.pricesIncludeTax ? ' (included)' : ''}',
                    totals.taxAmount,
                  ),
                const SizedBox(height: AppSpacing.sm),
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
                      const Text('Total Payable',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          CurrencyHelpers.format(total),
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // ── Payment ───────────────────────────────────
                Row(
                  children: [
                    const Expanded(
                      child: Text('Payment',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    if (methods.length > 1)
                      TextButton.icon(
                        onPressed: () => _toggleSplit(methods, total),
                        icon: Icon(_split ? Icons.close : Icons.call_split_rounded, size: 18),
                        label: Text(_split ? 'Single payment' : 'Split payment'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (methods.isEmpty)
                  const Text(
                    'No payment methods are enabled. Ask the owner to turn some on in Settings.',
                    style: TextStyle(color: AppColors.danger),
                  )
                else if (!_split)
                  _buildSinglePayment(methods, ref.watch(backendUrlProvider))
                else
                  _buildSplitPayments(methods, total),

                if (cashDue > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  MoneyField(
                    controller: _tenderedCtrl,
                    label: 'Cash received (optional)',
                    hint: CurrencyHelpers.formatRaw(cashDue),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final amount in _quickCashAmounts(cashDue))
                        ActionChip(
                          label: Text(CurrencyHelpers.formatCompact(amount)),
                          onPressed: () => setState(
                              () => _tenderedCtrl.text = amount.toStringAsFixed(2)),
                        ),
                    ],
                  ),
                  if (_tenderedCtrl.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        change >= 0
                            ? 'Change due: ${CurrencyHelpers.format(change)}'
                            : 'Short by ${CurrencyHelpers.format(-change)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: change >= 0 ? AppColors.primary : AppColors.danger,
                        ),
                      ),
                    ),
                ],

                const SizedBox(height: AppSpacing.xl),
                ElevatedButton.icon(
                  onPressed: _isCompleting || methods.isEmpty ? null : () => _complete(totals),
                  icon: _isCompleting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_rounded),
                  label: Text(_isCompleting
                      ? 'Completing Sale...'
                      : (!_split && _selectedMethod == AppConstants.paymentMomo)
                          ? 'Request MoMo Payment'
                          : 'Complete Sale'),
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

  /// Exact amount plus the next round notes above it.
  List<double> _quickCashAmounts(double due) {
    final options = <double>{roundMoney(due)};
    for (final note in [5, 10, 20, 50, 100, 200]) {
      final up = (due / note).ceil() * note.toDouble();
      if (up > due) options.add(up);
      if (options.length >= 4) break;
    }
    return options.toList()..sort();
  }

  Widget _totalRow(String label, double amount, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
          Text(
            amount < 0
                ? '−${CurrencyHelpers.format(-amount)}'
                : CurrencyHelpers.format(amount),
            style: TextStyle(fontWeight: FontWeight.w700, color: color ?? AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(int index, CartItem item, CartNotifier cartNotifier, bool canDiscount) {
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
            child: InkWell(
              onTap: canDiscount
                  ? () async {
                      final v = await _askAmount(
                          'Discount on ${item.product.name}', item.gross, item.discount);
                      if (v != null) cartNotifier.setLineDiscount(index, v);
                    }
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '${CurrencyHelpers.formatCompact(item.product.price)} each'
                    '${item.discount > 0 ? '  ·  −${CurrencyHelpers.formatCompact(item.discount)}' : ''}',
                    style: TextStyle(
                        color: item.discount > 0 ? AppColors.danger : AppColors.textSecondary,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.danger, size: 22),
            constraints: AppTouch.touchConstraints,
            onPressed: () => cartNotifier.updateQuantity(index, -1),
          ),
          Text('${item.quantity}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 22),
            constraints: AppTouch.touchConstraints,
            onPressed: () {
              if (!cartNotifier.updateQuantity(index, 1)) {
                context.showErrorSnackbar(
                    'Only ${item.available} "${item.product.name}" in stock.');
              }
            },
          ),
          SizedBox(
            width: 76,
            child: Text(
              CurrencyHelpers.formatCompact(item.subtotal),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSinglePayment(List<String> methods, String backendUrl) {
    final selected = _selectedMethod;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final m in methods)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: m == methods.last ? 0 : AppSpacing.sm),
                  child: PaymentOptionButton(
                    type: m,
                    icon: paymentIcon(m),
                    label: AppConstants.paymentLabel(m),
                    isSelected: selected == m,
                    onTap: () => setState(() {
                      _selectedMethod = m;
                      _tenderedCtrl.clear();
                    }),
                    compact: true,
                  ),
                ),
              ),
          ],
        ),
        if (selected == AppConstants.paymentMomo && backendUrl.isEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Mobile Money needs the backend URL set in Settings → Integrations.',
            style: TextStyle(color: AppColors.danger, fontSize: 12),
          ),
        ],
        if (selected == AppConstants.paymentCard || selected == AppConstants.paymentQr) ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _referenceCtrl,
            decoration: InputDecoration(
              labelText: selected == AppConstants.paymentCard
                  ? 'Card slip / approval code (optional)'
                  : 'QR transaction ID (optional)',
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Take the payment on your card machine or QR app first, then complete the sale here.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildSplitPayments(List<String> methods, double total) {
    final paid = _splitPaid();
    final remaining = roundMoney(total - paid);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in _splitRows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<String>(
                    initialValue: row.method,
                    isDense: true,
                    items: [
                      for (final m in methods)
                        DropdownMenuItem(value: m, child: Text(AppConstants.paymentLabel(m))),
                    ],
                    onChanged: (v) => setState(() => row.method = v ?? row.method),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: MoneyField(
                    controller: row.amount,
                    label: 'Amount',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  tooltip: 'Fill the remaining amount',
                  icon: const Icon(Icons.vertical_align_bottom_rounded),
                  onPressed: () => setState(() {
                    final others = paid - parseMoney(row.amount.text);
                    final rest = roundMoney(total - others);
                    row.amount.text = rest > 0 ? rest.toStringAsFixed(2) : '';
                  }),
                ),
                if (_splitRows.length > 2)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                    onPressed: () => setState(() {
                      _splitRows.remove(row);
                      row.dispose();
                    }),
                  ),
              ],
            ),
          ),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _splitRows.add(_SplitRow(methods.first))),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add payment'),
            ),
            const Spacer(),
            Text(
              remaining.abs() < 0.005
                  ? 'Fully covered'
                  : remaining > 0
                      ? 'Remaining ${CurrencyHelpers.format(remaining)}'
                      : 'Over by ${CurrencyHelpers.format(-remaining)}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: remaining.abs() < 0.005 ? AppColors.primary : AppColors.danger,
              ),
            ),
          ],
        ),
        if (_splitRows.any((r) => r.method == AppConstants.paymentMomo))
          const Text(
            'The Mobile Money part is charged next; the sale is saved once the customer approves it.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
      ],
    );
  }
}
