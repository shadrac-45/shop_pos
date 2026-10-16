/// ============================================
/// Checkout Bottom Sheet — ShopPOS
/// ============================================
/// Touch-first checkout: a frosted bottom sheet
/// on phones, a payment dialog beside the cart
/// panel on tablets.
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
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/services/session_manager.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/theme/app_theme.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';
import 'package:shop_pos/features/sales/screens/momo_payment_screen.dart';
import 'package:shop_pos/features/sales/screens/sale_detail_screen.dart';
import 'package:shop_pos/features/sales/services/sale_calculator.dart';
import 'package:shop_pos/features/sales/services/sale_service.dart';
import 'package:shop_pos/features/sales/widgets/cart_line_tile.dart';
import 'package:shop_pos/features/sales/widgets/cart_panel.dart';
import 'package:shop_pos/features/sales/widgets/payment_option_button.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';
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
  /// Show the editable cart lines. Off when the cart is already on screen
  /// (the tablet cart panel) and this opens as a payment dialog.
  final bool showLines;

  const CheckoutBottomSheet({super.key, this.showLines = true});

  @override
  ConsumerState<CheckoutBottomSheet> createState() => _CheckoutBottomSheetState();
}

class _CheckoutBottomSheetState extends ConsumerState<CheckoutBottomSheet> {
  String? _selectedMethod;
  bool _split = false;
  final List<_SplitRow> _splitRows = [];
  final _tenderedCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();

  /// Manual MoMo: what the cashier saw arrive, and that they checked it.
  final _momoReceivedCtrl = TextEditingController();
  bool _momoChecked = false;
  bool _isCompleting = false;

  /// Problem with the payment, shown inside the sheet right above the
  /// Pay button — where the cashier is looking — rather than as a toast.
  String? _error;

  void _showError(String message) {
    HapticFeedback.vibrate();
    setState(() => _error = message);
  }

  @override
  void dispose() {
    _tenderedCtrl.dispose();
    _referenceCtrl.dispose();
    _momoReceivedCtrl.dispose();
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
    setState(() => _error = null);
    final total = totals.total;
    final List<PaymentInput> payments;

    if (_split) {
      final paid = _splitPaid();
      if ((paid - total).abs() > 0.005) {
        _showError(
            'Split payments add up to ${CurrencyHelpers.format(paid)}; the total is ${CurrencyHelpers.format(total)}.');
        return;
      }
      final momoRows =
          _splitRows.where((r) => r.method == AppConstants.paymentMomo).toList();
      if (momoRows.length > 1) {
        _showError('Use only one Mobile Money part per sale.');
        return;
      }
      final manualParts = _splitRows
          .where((r) => r.method == AppConstants.paymentMomoManual && parseMoney(r.amount.text) > 0);
      if (manualParts.isNotEmpty && !_momoChecked) {
        _showError('Check the MoMo payment on the shop phone, then tick the box.');
        return;
      }
      payments = [
        for (final r in _splitRows)
          if (r.method != AppConstants.paymentMomo && parseMoney(r.amount.text) > 0)
            PaymentInput(r.method, parseMoney(r.amount.text),
                reference: r.reference.text.trim().isEmpty ? null : r.reference.text.trim(),
                confirmedReceived: r.method == AppConstants.paymentMomoManual && _momoChecked),
      ];
      if (momoRows.isNotEmpty && parseMoney(momoRows.first.amount.text) > 0) {
        return _goToMomo(parseMoney(momoRows.first.amount.text), payments, totals);
      }
    } else {
      final method = _selectedMethod;
      if (method == null) {
        _showError('Choose how the customer is paying.');
        return;
      }
      if (method == AppConstants.paymentMomo) {
        return _goToMomo(total, const [], totals);
      }
      if (method == AppConstants.paymentMomoManual) {
        final problem = _manualMomoProblem(total);
        if (problem != null) {
          _showError(problem);
          return;
        }
        payments = [
          PaymentInput(method, total,
              reference: _referenceCtrl.text.trim().isEmpty ? null : _referenceCtrl.text.trim(),
              confirmedReceived: true),
        ];
      } else {
        payments = [
          PaymentInput(method, total,
              reference: _referenceCtrl.text.trim().isEmpty ? null : _referenceCtrl.text.trim()),
        ];
      }
    }

    final tendered = _tenderedCtrl.text.trim().isEmpty ? null : parseMoney(_tenderedCtrl.text);
    final cashDue = _cashDue(total);
    if (tendered != null && tendered + 0.005 < cashDue) {
      _showError(
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
      _showError(errorMessage(e));
    }
  }

  /// What is wrong with the manual MoMo entry, or null when it can be
  /// completed. Same rules as every payment: the total, exactly (only cash
  /// gives change; there are no part-payments).
  String? _manualMomoProblem(double total) {
    final raw = _momoReceivedCtrl.text.trim();
    if (raw.isEmpty) return 'Enter the amount you received on the shop phone.';
    final received = roundMoney(parseMoney(raw));
    final due = roundMoney(total);
    if (received <= 0) return 'Enter the amount you received on the shop phone.';
    if (received + 0.005 < due) {
      return 'Received ${CurrencyHelpers.format(received)}, but the total is ${CurrencyHelpers.format(due)}. '
          'Ask for the rest, or use Split to take the rest in cash.';
    }
    if (received > due + 0.005) {
      return 'Received ${CurrencyHelpers.format(received)}, more than the total of ${CurrencyHelpers.format(due)}. '
          'MoMo can\'t give change: send the extra back, then enter ${CurrencyHelpers.format(due)}.';
    }
    if (!_momoChecked) return 'Check the payment on the shop phone, then tick the box.';
    return null;
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

    // Granular lookups: rebuild only for the media values used here.
    final screenHeight = MediaQuery.sizeOf(context).height;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final total = totals.total;
    final cashDue = _cashDue(total);
    final tendered = parseMoney(_tenderedCtrl.text);
    final change = SaleCalculator.changeDue(tendered: tendered, cashDue: cashDue);
    final itemCount = cart.fold(0, (s, i) => s + i.quantity);
    final inSheet = widget.showLines;

    final content = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * (inSheet ? 0.92 : 0.86)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────
          if (inSheet)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: AppSpacing.sm),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.sm, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(inSheet ? 'Checkout' : 'Take payment',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      Text('$itemCount item${itemCount == 1 ? '' : 's'}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Cart lines (phones; tablets show them in the panel) ──
                  if (inSheet) ...[
                    for (var index = 0; index < cart.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: CartLineTile(
                          key: ValueKey(cart[index].product.id),
                          index: index,
                          item: cart[index],
                          cart: cartNotifier,
                          canDiscount: canDiscount,
                        ),
                      ),
                    if (canDiscount) SaleDiscountButton(totals: totals),
                  ],

                  // ── Totals ──────────────────────────────
                  Container(
                    margin: const EdgeInsets.only(top: AppSpacing.xs),
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: AppSpacing.borderLg,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: CartTotalsSummary(totals: totals),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // ── Payment ─────────────────────────────
                  Row(
                    children: [
                      const Expanded(child: Text('PAYMENT METHOD', style: AppText.overline)),
                      if (methods.length > 1)
                        TextButton.icon(
                          onPressed: () => _toggleSplit(methods, total),
                          icon: Icon(_split ? Icons.close_rounded : Icons.call_split_rounded, size: 18),
                          label: Text(_split ? 'Single payment' : 'Split payment'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (methods.isEmpty)
                    const Text(
                      'No payment methods are enabled. Ask the owner to turn some on in Settings.',
                      style: TextStyle(color: AppColors.dangerDarkText),
                    )
                  else if (!_split)
                    _buildSinglePayment(methods, ref.watch(backendUrlProvider))
                  else
                    _buildSplitPayments(methods, total),

                  if (cashDue > 0) ...[
                    const SizedBox(height: AppSpacing.lg),
                    MoneyField(
                      controller: _tenderedCtrl,
                      label: 'Cash received (optional)',
                      hint: CurrencyHelpers.formatRaw(cashDue),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final amount in _quickCashAmounts(cashDue))
                          ChoiceChip(
                            label: Text(
                              amount == roundMoney(cashDue)
                                  ? 'Exact ${CurrencyHelpers.formatCompact(amount)}'
                                  : CurrencyHelpers.formatCompact(amount),
                              style: const TextStyle(fontFeatures: AppText.tabular),
                            ),
                            selected: (parseMoney(_tenderedCtrl.text) - amount).abs() < 0.005 &&
                                _tenderedCtrl.text.trim().isNotEmpty,
                            onSelected: (_) => setState(
                                () => _tenderedCtrl.text = amount.toStringAsFixed(2)),
                          ),
                      ],
                    ),
                    if (_tenderedCtrl.text.trim().isNotEmpty)
                      _ChangeDue(change: change),
                  ],
                ],
              ),
            ),
          ),

          // ── Pay ───────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl,
                AppSpacing.lg + (inSheet ? safeBottom : 0)),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.glassStroke)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) _ErrorBanner(message: _error!),
                ElevatedButton.icon(
              onPressed: _isCompleting || methods.isEmpty ? null : () => _complete(totals),
              style: AppButtons.pay(),
              icon: _isCompleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_rounded),
              label: Text(_isCompleting
                  ? 'Completing sale…'
                  : (!_split && _selectedMethod == AppConstants.paymentMomo)
                      ? 'Request MoMo  ${CurrencyHelpers.format(total)}'
                      : 'Complete sale  ${CurrencyHelpers.format(total)}'),
            ),
              ],
            ),
          ),
        ],
      ),
    );

    final radius = inSheet
        ? const BorderRadius.vertical(top: Radius.circular(28))
        : const BorderRadius.all(Radius.circular(28));

    return Padding(
      // A bottom sheet must lift itself above the keyboard; a Dialog
      // already does, so adding it there would double the lift.
      padding: EdgeInsets.only(bottom: inSheet ? keyboard : 0),
      // Solid, not glass: this is the transaction itself, so every figure
      // must read cleanly. The frosted backdrop behind it supplies the depth.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: inSheet ? null : AppGlass.shadow,
        ),
        child: Material(
          color: AppColors.cardBg,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: const BorderSide(color: AppColors.glassStroke),
          ),
          child: content,
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

  Widget _buildSinglePayment(List<String> methods, String backendUrl) {
    final selected = _selectedMethod;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One row; more than four methods wrap to a second row so each
        // button stays readable on a phone.
        LayoutBuilder(builder: (context, c) {
          final perRow = methods.length > 4 ? 3 : methods.length;
          final width = (c.maxWidth - AppSpacing.sm * (perRow - 1)) / perRow;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final m in methods)
                SizedBox(
                  width: width,
                  child: PaymentOptionButton(
                    type: m,
                    icon: paymentIcon(m),
                    label: AppConstants.paymentLabel(m),
                    isSelected: selected == m,
                    onTap: () => setState(() {
                      _selectedMethod = m;
                      _tenderedCtrl.clear();
                      _momoReceivedCtrl.clear();
                      _momoChecked = false;
                    }),
                    compact: true,
                  ),
                ),
            ],
          );
        }),
        if (selected == AppConstants.paymentMomo && backendUrl.isEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Mobile Money needs the backend URL set in Settings → Integrations.',
            style: TextStyle(color: AppColors.danger, fontSize: 12),
          ),
        ],
        if (selected == AppConstants.paymentMomoManual) ...[
          const SizedBox(height: AppSpacing.md),
          _ManualMomoDetails(settings: ref.watch(storeSettingsProvider)),
          const SizedBox(height: AppSpacing.sm),
          MoneyField(
            controller: _momoReceivedCtrl,
            label: 'Amount received',
            hint: 'As shown on the shop phone',
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _referenceCtrl,
            decoration: const InputDecoration(
              labelText: 'MoMo transaction ID (optional)',
              hintText: 'From the MoMo confirmation message',
            ),
          ),
          _MomoCheckedBox(
            value: _momoChecked,
            onChanged: (v) => setState(() {
              _momoChecked = v;
              _error = null;
            }),
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
        if (_splitRows.any((r) => r.method == AppConstants.paymentMomoManual))
          _MomoCheckedBox(
            value: _momoChecked,
            onChanged: (v) => setState(() {
              _momoChecked = v;
              _error = null;
            }),
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

/// Change to hand back (or how much is still short), large enough to read
/// across the counter.
class _ChangeDue extends StatelessWidget {
  final double change;
  const _ChangeDue({required this.change});

  @override
  Widget build(BuildContext context) {
    final ok = change >= 0;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: ok ? AppTone.success.tint : AppTone.danger.tint,
        borderRadius: AppSpacing.borderLg,
        border: Border.all(color: ok ? AppTone.success.border : AppTone.danger.border),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.payments_rounded : Icons.error_outline_rounded,
              color: ok ? AppColors.primaryDark : AppColors.danger),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(ok ? 'Change due' : 'Short by',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ok ? AppColors.successDarkText : AppColors.dangerDarkText)),
          ),
          Text(
            CurrencyHelpers.format(ok ? change : -change),
            style: AppText.money(
                size: 22,
                weight: FontWeight.w800,
                color: ok ? AppColors.successDarkText : AppColors.dangerDarkText),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: AppTone.danger.tint,
          borderRadius: AppSpacing.borderMd,
          border: Border.all(color: AppTone.danger.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 20, color: AppTone.danger.fg),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(message,
                  style: TextStyle(
                      color: AppTone.danger.text, fontWeight: FontWeight.w600, height: 1.3)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the customer sends a manual MoMo payment: the shop's own number,
/// its network and the account name they should see before confirming.
class _ManualMomoDetails extends StatelessWidget {
  final StoreSettings settings;
  const _ManualMomoDetails({required this.settings});

  static const _networks = {'mtn': 'MTN MoMo', 'telecel': 'Telecel Cash', 'at': 'AT Money'};

  @override
  Widget build(BuildContext context) {
    final network = _networks[settings.momoNetwork] ?? settings.momoNetwork;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppTone.success.tint,
        borderRadius: AppSpacing.borderLg,
        border: Border.all(color: AppTone.success.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Customer sends to', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 2),
          SelectableText(
            settings.momoNumber,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
          const SizedBox(height: 2),
          Text(
            [network, if (settings.momoAccountName.trim().isNotEmpty) settings.momoAccountName.trim()].join(' · '),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// "I've checked this payment": a manual MoMo sale can't complete without it.
class _MomoCheckedBox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _MomoCheckedBox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      title: const Text("I've checked this MoMo payment on the shop phone"),
      subtitle: const Text('The money has arrived, for this amount.'),
    );
  }
}
