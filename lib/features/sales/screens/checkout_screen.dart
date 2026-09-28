/// ============================================
/// Checkout Screen — ShopPOS
/// ============================================
/// Full-screen checkout route for payment
/// processing. Supports Cash, MoMo, and Split.
/// Uses [PaymentOptionButton] for method selection
/// and [ContextExtension] for snackbars.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/responsive/app_breakpoints.dart';
import 'package:shop_pos/core/services/session_manager.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/sales/widgets/payment_option_button.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _selectedPayment = AppConstants.paymentCash;
  bool _isProcessing = false;
  bool _showSuccessReceipt = false;

  final TextEditingController _cashController = TextEditingController();
  final TextEditingController _momoController = TextEditingController();

  /// Data-driven payment options — adding a new payment type requires
  /// only one entry here, not changes to the rendering logic.
  static const _paymentOptions = [
    (type: AppConstants.paymentCash, icon: Icons.payments_rounded, label: 'Cash'),
    (type: AppConstants.paymentMomo, icon: Icons.phone_android_rounded, label: 'MoMo'),
    (type: AppConstants.paymentSplit, icon: Icons.call_split_rounded, label: 'Split'),
  ];

  @override
  void dispose() {
    _cashController.dispose();
    _momoController.dispose();
    super.dispose();
  }

  // ── Sale processing ───────────────────────────────────────────────

  Future<void> _processSale() async {
    if (_isProcessing) return;

    final total = ref.read(cartProvider.notifier).totalAmount;

    // Validate split amounts sum to total
    if (_selectedPayment == AppConstants.paymentSplit) {
      final cashAmt = double.tryParse(_cashController.text.trim()) ?? 0;
      final momoAmt = double.tryParse(_momoController.text.trim()) ?? 0;

      if ((cashAmt + momoAmt - total).abs() > 0.01) {
        context.showErrorSnackbar('Split amounts must equal the total exactly.');
        return;
      }
    }

    setState(() => _isProcessing = true);

    try {
      final currentUser = ref.read(currentUserProvider);

      ref.read(sessionManagerProvider).recordActivity();

      final success = await ref
          .read(cartProvider.notifier)
          .completeSale(_selectedPayment,
              cashierId: currentUser?.id ?? 0);

      if (!mounted) return;

      if (success) {
        HapticFeedback.heavyImpact();
        setState(() {
          _showSuccessReceipt = true;
          _isProcessing = false;
        });

        // Auto-close after the success animation
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop();
        }
      } else {
        setState(() => _isProcessing = false);
        context.showErrorSnackbar(
            'Failed to complete sale. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      context.showErrorSnackbar('Error: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final total = ref
        .watch(cartProvider.notifier.select((n) => n.totalAmount));

    if (cartItems.isEmpty && !_showSuccessReceipt) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: const Center(child: Text('Cart is empty')),
      );
    }

    final ctaPad = AppBreakpoints.ctaVerticalPadding(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: _showSuccessReceipt
          ? null
          : AppBar(
              title: const Text('Checkout',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: AppColors.cardBg,
            ),
      body: Stack(
        children: [
          // ── Main content ──────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Grand total display ───────────────────
                        Center(
                          child: Column(
                            children: [
                              const Text(
                                'Grand Total',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              // FittedBox prevents the large price from
                              // overflowing on small or high-dpi screens.
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  return SizedBox(
                                    width: constraints.maxWidth,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        CurrencyHelpers.format(total),
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 40,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 30),

                        // ── Items summary ─────────────────────────
                        const Text(
                          'Items Summary',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 12),
                        _buildItemsSummary(cartItems),

                        const SizedBox(height: 30),

                        // ── Payment method selection ───────────────
                        const Text(
                          'Payment Method',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 12),

                        // Data-driven row of PaymentOptionButtons
                        Row(
                          children: _paymentOptions.map((opt) {
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: opt == _paymentOptions.last
                                      ? 0
                                      : 12,
                                ),
                                child: PaymentOptionButton(
                                  type: opt.type,
                                  icon: opt.icon,
                                  label: opt.label,
                                  isSelected:
                                      _selectedPayment == opt.type,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    setState(() =>
                                        _selectedPayment = opt.type);
                                  },
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        // ── Split amount fields ───────────────────
                        if (_selectedPayment ==
                            AppConstants.paymentSplit) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              children: [
                                _buildSplitField(
                                    'Cash Amount', _cashController),
                                const SizedBox(height: 12),
                                _buildSplitField(
                                    'MoMo Amount', _momoController),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── Complete sale CTA ─────────────────────────────
                // Padding shrinks in landscape to recover vertical space.
                Container(
                  padding: EdgeInsets.all(ctaPad),
                  decoration: const BoxDecoration(
                    color: AppColors.cardBg,
                    border: Border(
                        top: BorderSide(color: AppColors.border)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _processSale,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        minimumSize: const Size(double.infinity, 56),
                      ),
                      child: _isProcessing
                          ? const CircularProgressIndicator(
                              color: Colors.white)
                          : const Text(
                              'COMPLETE SALE',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  color: Colors.white),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Success overlay ───────────────────────────────────────
          if (_showSuccessReceipt) _buildSuccessOverlay(),
        ],
      ),
    );
  }

  // ── Private helper builders ───────────────────────────────────────

  Widget _buildItemsSummary(List<CartItem> cartItems) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: cartItems.length,
        separatorBuilder: (_, __) =>
            const Divider(color: AppColors.border, height: 1),
        itemBuilder: (_, i) {
          final item = cartItems[i];
          return ListTile(
            dense: true,
            title: Text(item.product.name,
                style:
                    const TextStyle(color: AppColors.textPrimary)),
            subtitle: Text(
              '${CurrencyHelpers.format(item.product.price)} × ${item.quantity}',
              style:
                  const TextStyle(color: AppColors.textSecondary),
            ),
            trailing: Text(
              CurrencyHelpers.format(item.subtotal),
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  fontSize: 14),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSplitField(
      String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        prefixText: '${AppConstants.currencySymbol} ',
        prefixStyle: const TextStyle(
            color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        filled: true,
        fillColor: AppColors.surfaceBg,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    return Positioned.fill(
      child: Container(
        color: AppColors.scaffoldBg,
        child: Center(
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, _) => Transform.scale(
              scale: value,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SuccessIcon(),
                  SizedBox(height: 24),
                  Text(
                    'Payment Successful!',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Receipt saved and stock deducted.',
                    style: TextStyle(
                        fontSize: 16, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Encapsulated success icon widget — size is driven by screen size
/// so it stays proportional in landscape on short devices.
class _SuccessIcon extends StatelessWidget {
  const _SuccessIcon();

  @override
  Widget build(BuildContext context) {
    // Cap the icon at 100 dp but shrink proportionally on short screens
    final size = (MediaQuery.sizeOf(context).shortestSide * 0.22)
        .clamp(64.0, 100.0);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.success,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.check_rounded,
          color: Colors.white, size: size * 0.6),
    );
  }
}