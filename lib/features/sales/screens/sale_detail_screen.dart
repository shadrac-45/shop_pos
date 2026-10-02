/// ============================================
/// Sale Detail / Receipt Screen — ShopPOS
/// ============================================
/// Shows a sale as a receipt, with:
///   • Print (system print dialog) and Share (PDF)
///   • Void (whole sale) and Refund (some items),
///     for roles allowed to
/// Opened after every sale and from sales history.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:printing/printing.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/reports/providers/report_provider.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/models/sale_item.dart';
import 'package:shop_pos/features/sales/services/bluetooth_printer_service.dart';
import 'package:shop_pos/features/sales/services/escpos.dart';
import 'package:shop_pos/features/sales/services/receipt_service.dart';
import 'package:shop_pos/features/sales/services/sale_service.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';

class SaleDetailScreen extends ConsumerStatefulWidget {
  final int saleId;

  /// True right after checkout: shows change due prominently and, if a
  /// printer is enabled in settings, opens the print dialog.
  final bool justCompleted;

  const SaleDetailScreen({
    super.key,
    required this.saleId,
    this.justCompleted = false,
  });

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  ReceiptData? _receipt;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load(autoPrint: widget.justCompleted);
  }

  Future<void> _load({bool autoPrint = false}) async {
    final isar = ref.read(isarProvider);
    final sale = await isar.sales.get(widget.saleId);
    if (!mounted) return;
    if (sale == null) {
      setState(() => _error = 'Sale not found.');
      return;
    }
    final receipt =
        await ReceiptData.load(isar, sale, ref.read(storeSettingsProvider));
    if (!mounted) return;
    setState(() => _receipt = receipt);
    if (autoPrint) _afterSale(receipt);
  }

  /// Right after checkout: print if auto-print is on, and open the cash
  /// drawer for sales that took cash.
  Future<void> _afterSale(ReceiptData r) async {
    final store = r.store;
    final tookCash = r.sale.effectivePayments
        .any((p) => p.method == AppConstants.paymentCash && p.amount > 0);
    final kickDrawer =
        store.cashDrawerEnabled && tookCash && store.printerAddress.isNotEmpty;
    if (store.printerEnabled) {
      await _print(openDrawer: kickDrawer);
    } else if (kickDrawer) {
      try {
        await BluetoothPrinterService.send(
            store.printerAddress, (EscPosBuilder()..openDrawer()).build());
      } catch (e) {
        if (mounted) context.showErrorSnackbar('Cash drawer: ${errorMessage(e)}');
      }
    }
  }

  /// Prints on the chosen Bluetooth printer, or through the Android print
  /// dialog when none is set up.
  Future<void> _print({bool openDrawer = false}) async {
    final r = _receipt;
    if (r == null) return;
    if (r.store.printerAddress.isNotEmpty) {
      try {
        await BluetoothPrinterService.send(
          r.store.printerAddress,
          EscPosReceipt.build(r, paperMm: r.store.printerPaperMm, openDrawer: openDrawer),
        );
      } catch (e) {
        if (!mounted) return;
        final useDialog = await confirmDialog(
          context,
          title: 'Printer problem',
          message: '${errorMessage(e)}\n\nPrint through the Android print dialog instead?',
          confirmLabel: 'Use Print Dialog',
        );
        if (useDialog) await _printWithDialog();
      }
      return;
    }
    await _printWithDialog();
  }

  Future<void> _printWithDialog() async {
    final r = _receipt;
    if (r == null) return;
    try {
      await Printing.layoutPdf(
        name: 'Receipt ${r.sale.receiptNumber}',
        onLayout: (_) => ReceiptService.buildPdf(r),
      );
    } catch (e) {
      if (mounted) context.showErrorSnackbar('Could not print: ${errorMessage(e)}');
    }
  }

  Future<void> _share() async {
    final r = _receipt;
    if (r == null) return;
    try {
      await Printing.sharePdf(
        bytes: await ReceiptService.buildPdf(r),
        filename: 'receipt-${r.sale.receiptNumber}.pdf',
      );
    } catch (e) {
      if (mounted) context.showErrorSnackbar('Could not share: ${errorMessage(e)}');
    }
  }

  Future<void> _void() async {
    final reason = await _askReason(
      title: 'Void ${_receipt!.sale.receiptNumber}?',
      message: 'Every item goes back into stock and the full '
          '${CurrencyHelpers.format(_receipt!.sale.totalAmount)} is refunded '
          'the way it was paid. This cannot be undone.',
      confirmLabel: 'Void Sale',
    );
    if (reason == null) return;
    await _run(() => SaleService.voidSale(
          ref.read(isarProvider),
          ref.read(currentUserProvider),
          sale: _receipt!.sale,
          reason: reason,
        ), 'Sale voided.');
  }

  Future<void> _refund() async {
    final isar = ref.read(isarProvider);
    final items = await SaleService.itemsFor(isar, widget.saleId);
    if (!mounted) return;
    if (items.isEmpty) {
      context.showErrorSnackbar(
          'This sale was recorded before item-level refunds were supported. Use Void instead.');
      return;
    }
    final request = await showDialog<_RefundRequest>(
      context: context,
      builder: (_) => _RefundDialog(sale: _receipt!.sale, items: items),
    );
    if (request == null) return;
    await _run(() async {
      final amount = await SaleService.refund(
        isar,
        ref.read(currentUserProvider),
        sale: _receipt!.sale,
        quantities: request.quantities,
        reason: request.reason,
        method: request.method,
        returnToStock: request.returnToStock,
      );
      if (mounted) {
        context.showSuccessSnackbar(
            'Refunded ${CurrencyHelpers.format(amount)} by ${AppConstants.paymentLabel(request.method)}.');
      }
    }, null);
  }

  Future<void> _run(Future<void> Function() action, String? success) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.read(reportProvider.notifier).refresh();
      if (mounted && success != null) context.showSuccessSnackbar(success);
      await _load();
    } catch (e) {
      if (mounted) context.showErrorSnackbar(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason (required)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final r = _receipt;
    final canRefund = Permissions.can(user, Permission.voidAndRefund);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(r == null ? 'Receipt' : 'Receipt ${r.sale.receiptNumber}'),
        backgroundColor: AppColors.cardBg,
      ),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : r == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      if (widget.justCompleted) _buildCompletedBanner(r.sale),
                      _ReceiptCard(receipt: r),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _print,
                              icon: const Icon(Icons.print_rounded),
                              label: const Text('Print'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _share,
                              icon: const Icon(Icons.share_rounded),
                              label: const Text('Share'),
                            ),
                          ),
                        ],
                      ),
                      if (canRefund && !r.sale.isVoided) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            if (r.sale.status != SaleStatus.refunded)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _busy ? null : _refund,
                                  icon: const Icon(Icons.undo_rounded),
                                  label: const Text('Refund Items'),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.warning),
                                ),
                              ),
                            if (r.sale.status == SaleStatus.completed) ...[
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _busy ? null : _void,
                                  icon: const Icon(Icons.block_rounded),
                                  label: const Text('Void Sale'),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.danger),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (widget.justCompleted) ...[
                        const SizedBox(height: AppSpacing.lg),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.add_shopping_cart_rounded),
                          label: const Text('New Sale'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, AppTouch.buttonHeight),
                          ),
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _buildCompletedBanner(Sale sale) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: AppSpacing.borderLg,
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 40),
          const SizedBox(height: AppSpacing.sm),
          Text('Sale complete — ${CurrencyHelpers.format(sale.totalAmount)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (sale.amountTendered != null) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text('Change due',
                style: TextStyle(color: AppColors.textSecondary)),
            Text(CurrencyHelpers.format(sale.changeDue),
                style: const TextStyle(
                    fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.primary)),
          ],
        ],
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  final ReceiptData receipt;
  const _ReceiptCard({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final s = receipt.sale;
    const muted = TextStyle(color: AppColors.textSecondary, fontSize: 13);

    Widget row(String left, String right, {bool bold = false, Color? color}) {
      final style = TextStyle(
        fontSize: bold ? 16 : 13,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        color: color ?? AppColors.textPrimary,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(left, style: style)),
            Text(right, style: style),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: AppSpacing.borderLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(receipt.storeName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          if (receipt.store.storeAddress.isNotEmpty)
            Text(receipt.store.storeAddress, textAlign: TextAlign.center, style: muted),
          if (receipt.store.storePhone.isNotEmpty)
            Text(receipt.store.storePhone, textAlign: TextAlign.center, style: muted),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${s.receiptNumber} · ${DateHelpers.formatDateTime(s.timestamp)} · ${receipt.cashierName}',
            textAlign: TextAlign.center,
            style: muted,
          ),
          if (s.status != SaleStatus.completed) ...[
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: StatusPill(
                s.status.replaceAll('_', ' '),
                color: s.isVoided ? AppColors.danger : AppColors.warning,
              ),
            ),
            if (s.statusReason != null)
              Text('Reason: ${s.statusReason}', textAlign: TextAlign.center, style: muted),
          ],
          const Divider(height: 24),
          for (final l in receipt.lines) ...[
            row(l.name, CurrencyHelpers.format(l.total)),
            Text(
              '  ${l.quantity} × ${CurrencyHelpers.format(l.unitPrice)}'
              '${l.discount > 0 ? '   discount −${CurrencyHelpers.format(l.discount)}' : ''}'
              '${l.refundedQty > 0 ? '   (${l.refundedQty} returned)' : ''}',
              style: muted,
            ),
            const SizedBox(height: 4),
          ],
          const Divider(height: 24),
          row('Subtotal', CurrencyHelpers.format(s.effectiveSubtotal)),
          if (s.discountAmount > 0)
            row('Discounts', '−${CurrencyHelpers.format(s.discountAmount)}'),
          if (s.taxAmount > 0)
            row(
                'VAT ${s.taxRate % 1 == 0 ? s.taxRate.toInt() : s.taxRate}%'
                '${receipt.store.pricesIncludeTax ? ' (included)' : ''}',
                CurrencyHelpers.format(s.taxAmount)),
          row('Total', CurrencyHelpers.format(s.totalAmount), bold: true),
          const SizedBox(height: AppSpacing.sm),
          for (final p in s.effectivePayments)
            row('Paid by ${AppConstants.paymentLabel(p.method)}'
                '${p.reference != null && p.reference!.isNotEmpty ? ' (${p.reference})' : ''}',
                CurrencyHelpers.format(p.amount)),
          if (s.amountTendered != null) ...[
            row('Cash tendered', CurrencyHelpers.format(s.amountTendered!)),
            row('Change', CurrencyHelpers.format(s.changeDue)),
          ],
          if (s.refundedAmount > 0)
            row('Refunded', '−${CurrencyHelpers.format(s.refundedAmount)}',
                color: AppColors.danger),
          if (receipt.store.receiptFooter.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(receipt.store.receiptFooter, textAlign: TextAlign.center, style: muted),
          ],
        ],
      ),
    );
  }
}

class _RefundRequest {
  final Map<int, int> quantities;
  final String reason;
  final String method;
  final bool returnToStock;
  const _RefundRequest(this.quantities, this.reason, this.method, this.returnToStock);
}

class _RefundDialog extends StatefulWidget {
  final Sale sale;
  final List<SaleItem> items;
  const _RefundDialog({required this.sale, required this.items});

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  late final Map<int, int> _qty = {for (final i in widget.items) i.id: 0};
  final _reasonCtrl = TextEditingController();
  late String _method = widget.sale.effectivePayments.first.method ==
          AppConstants.paymentMomoPaystack
      ? AppConstants.paymentMomo
      : widget.sale.effectivePayments.first.method;
  bool _returnToStock = true;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  double get _estimate => widget.items.fold(0.0, (sum, i) {
        final q = _qty[i.id] ?? 0;
        return q == 0 ? sum : sum + i.lineTotal * q / i.quantity;
      });

  @override
  Widget build(BuildContext context) {
    final methods = <String>{
      AppConstants.paymentCash,
      for (final p in widget.sale.effectivePayments)
        p.method == AppConstants.paymentMomoPaystack ? AppConstants.paymentMomo : p.method,
    }.toList();

    return AlertDialog(
      title: const Text('Refund Items'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final i in widget.items)
                Builder(builder: (_) {
                  final left = i.quantity - i.refundedQty;
                  final q = _qty[i.id] ?? 0;
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${i.productName}\n$left of ${i.quantity} refundable',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        onPressed: q > 0 ? () => setState(() => _qty[i.id] = q - 1) : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$q', style: const TextStyle(fontWeight: FontWeight.w800)),
                      IconButton(
                        onPressed: q < left ? () => setState(() => _qty[i.id] = q + 1) : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  );
                }),
              const Divider(),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(labelText: 'Refund paid by'),
                items: [
                  for (final m in methods)
                    DropdownMenuItem(value: m, child: Text(AppConstants.paymentLabel(m))),
                ],
                onChanged: (v) => setState(() => _method = v ?? _method),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _returnToStock,
                onChanged: (v) => setState(() => _returnToStock = v ?? true),
                title: const Text('Put items back into stock'),
                subtitle: const Text('Untick for damaged or unsellable returns'),
              ),
              TextField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(labelText: 'Reason (required)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('About ${CurrencyHelpers.format(_estimate)} will be refunded.',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_qty.values.every((q) => q == 0)) {
              setState(() => _error = 'Choose at least one item.');
              return;
            }
            if (_reasonCtrl.text.trim().isEmpty) {
              setState(() => _error = 'Enter a reason.');
              return;
            }
            Navigator.pop(
              context,
              _RefundRequest(
                {for (final e in _qty.entries) if (e.value > 0) e.key: e.value},
                _reasonCtrl.text.trim(),
                _method,
                _returnToStock,
              ),
            );
          },
          child: const Text('Refund'),
        ),
      ],
    );
  }
}
