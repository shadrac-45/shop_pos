/// ============================================
/// Pending MoMo Payments Screen — ShopPOS
/// ============================================
/// Reconciliation for Mobile Money charges that
/// didn't finish normally: the app timed out
/// waiting, or the customer paid but the sale
/// couldn't be saved. For each one you can check
/// its status with Paystack, record the sale if
/// it was paid, or dismiss it.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/reports/providers/report_provider.dart';
import 'package:shop_pos/features/sales/models/paystack_models.dart';
import 'package:shop_pos/features/sales/screens/sale_detail_screen.dart';
import 'package:shop_pos/features/sales/services/paystack_service.dart';
import 'package:shop_pos/features/sales/services/pending_momo_store.dart';
import 'package:shop_pos/features/sales/services/receipt_service.dart';
import 'package:shop_pos/features/sales/services/sale_service.dart';
import 'package:shop_pos/features/shared/widgets/app_empty_state.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';

class PendingMomoScreen extends ConsumerStatefulWidget {
  const PendingMomoScreen({super.key});

  @override
  ConsumerState<PendingMomoScreen> createState() => _PendingMomoScreenState();
}

class _PendingMomoScreenState extends ConsumerState<PendingMomoScreen> {
  List<PendingMomoPayment>? _payments;
  final Map<String, String> _statusText = {};
  String? _busyRef;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await PendingMomoStore.getAll();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (mounted) setState(() => _payments = list);
  }

  Future<void> _check(PendingMomoPayment p) async {
    setState(() => _busyRef = p.reference);
    final result = await ref.read(paystackServiceProvider).verifyStatus(p.reference);
    if (!mounted) return;
    switch (result.status) {
      case PaystackVerifyStatus.success:
        await PendingMomoStore.setStatus(p.reference, PendingMomoStatus.paidNotSaved);
        _statusText[p.reference] = 'PAID — record the sale below.';
      case PaystackVerifyStatus.failed:
      case PaystackVerifyStatus.abandoned:
        await PendingMomoStore.remove(p.reference);
        if (mounted) context.showSuccessSnackbar('Not paid, so nothing to record. Removed.');
      case PaystackVerifyStatus.pending:
        _statusText[p.reference] = 'Still waiting for the customer.';
      case PaystackVerifyStatus.networkError:
        _statusText[p.reference] = 'Could not reach the backend. Try again later.';
    }
    setState(() => _busyRef = null);
    await _load();
  }

  /// Records the sale for a payment Paystack confirmed.
  Future<void> _record(PendingMomoPayment p) async {
    setState(() => _busyRef = p.reference);
    final isar = ref.read(isarProvider);
    try {
      final lines = <CheckoutLine>[];
      for (final m in SaleItemsJson.decode(p.itemsJson)) {
        final product = await isar.products.get((m['productId'] as num).toInt());
        if (product == null) {
          throw SaleValidationException(
              '"${m['productName']}" no longer exists. Record this sale by hand.');
        }
        // Charge the price the customer was quoted, not today's price
        // (the change is not saved to the product).
        product.price = (m['price'] as num).toDouble();
        lines.add(CheckoutLine(
          product: product,
          quantity: (m['quantity'] as num).toInt(),
          discount: (m['discount'] as num?)?.toDouble() ?? 0,
        ));
      }
      final sale = await SaleService.completeSale(
        isar,
        ref.read(currentUserProvider),
        lines: lines,
        payments: [PaymentInput(AppConstants.paymentMomo, p.amountGhs, reference: p.reference)],
        tax: ref.read(taxConfigProvider),
        paystackReference: p.reference,
        momoProvider: p.provider,
        momoPhone: p.phone,
        cashierId: p.cashierId,
      );
      await PendingMomoStore.remove(p.reference);
      ref.read(reportProvider.notifier).refresh();
      if (!mounted) return;
      context.showSuccessSnackbar('Sale ${sale.receiptNumber} recorded.');
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SaleDetailScreen(saleId: sale.id)));
    } catch (e) {
      if (mounted) {
        context.showErrorSnackbar(
            '${errorMessage(e)} If it was a split payment, record it by hand.');
      }
    } finally {
      if (mounted) setState(() => _busyRef = null);
      await _load();
    }
  }

  Future<void> _dismiss(PendingMomoPayment p) async {
    final ok = await confirmDialog(
      context,
      title: 'Dismiss ${p.reference}?',
      message: p.status == PendingMomoStatus.paidNotSaved
          ? 'This payment WAS received. Only dismiss it if you have recorded the sale another way.'
          : 'Only dismiss it if you are sure the customer did not pay.',
      confirmLabel: 'Dismiss',
      destructive: true,
    );
    if (!ok) return;
    await PendingMomoStore.remove(p.reference);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final payments = _payments;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(title: const Text('Pending MoMo Payments'), backgroundColor: AppColors.cardBg),
      body: SafeArea(
        child: payments == null
            ? const Center(child: CircularProgressIndicator())
            : payments.isEmpty
                ? const AppEmptyState(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Nothing to reconcile',
                    description: 'Every Mobile Money charge has been resolved.',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        for (final p in payments)
                          Card(
                            margin: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(CurrencyHelpers.format(p.amountGhs),
                                            style: const TextStyle(
                                                fontSize: 18, fontWeight: FontWeight.w900)),
                                      ),
                                      StatusPill(
                                        p.status == PendingMomoStatus.paidNotSaved
                                            ? 'paid, not saved'
                                            : 'awaiting',
                                        color: p.status == PendingMomoStatus.paidNotSaved
                                            ? AppColors.danger
                                            : AppColors.warning,
                                      ),
                                    ],
                                  ),
                                  Text('${p.phone} · ${p.provider.toUpperCase()} · '
                                      '${DateHelpers.formatDateTime(p.createdAt)}'),
                                  SelectableText('Ref: ${p.reference}',
                                      style: const TextStyle(
                                          fontFamily: 'monospace', fontSize: 12)),
                                  if (_statusText[p.reference] != null)
                                    Text(_statusText[p.reference]!,
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: AppSpacing.sm),
                                  Wrap(
                                    spacing: AppSpacing.sm,
                                    children: [
                                      OutlinedButton(
                                        onPressed: _busyRef != null ? null : () => _check(p),
                                        child: const Text('Check status'),
                                      ),
                                      if (p.status == PendingMomoStatus.paidNotSaved)
                                        ElevatedButton(
                                          onPressed:
                                              _busyRef != null ? null : () => _record(p),
                                          child: const Text('Record sale'),
                                        ),
                                      TextButton(
                                        onPressed: _busyRef != null ? null : () => _dismiss(p),
                                        child: const Text('Dismiss',
                                            style: TextStyle(color: AppColors.danger)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
