/// ============================================
/// Checkout Screen — ShopPOS
/// ============================================
/// Full-screen checkout route for payment processing.
/// Supports Cash, MoMo, and Split Payments.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../utils/currency_helpers.dart';


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

  @override
  void dispose() {
    _cashController.dispose();
    _momoController.dispose();
    super.dispose();
  }

  /// Process the sale using the corrected CartNotifier
  Future<void> _processSale() async {
    if (_isProcessing) return;

    final total = ref.read(cartProvider.notifier).totalAmount;

    double cashAmt = 0;
    double momoAmt = 0;

    if (_selectedPayment == AppConstants.paymentSplit) {
      cashAmt = double.tryParse(_cashController.text.trim()) ?? 0;
      momoAmt = double.tryParse(_momoController.text.trim()) ?? 0;

      if ((cashAmt + momoAmt - total).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Split amounts must equal the total exactly.'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
    } else if (_selectedPayment == AppConstants.paymentCash) {
      cashAmt = total;
    } else if (_selectedPayment == AppConstants.paymentMomo) {
      momoAmt = total;
    }

    setState(() => _isProcessing = true);

    try {
      final currentUser = ref.read(currentUserProvider);
      final cashierPin = currentUser?.pinHash ?? '1234'; // fallback for testing

      final success = await ref.read(cartProvider.notifier).completeSale(
            _selectedPayment,
            cashierPin,
          );

      if (!context.mounted) return;

      if (success) {
        HapticFeedback.heavyImpact();
        setState(() {
          _showSuccessReceipt = true;
          _isProcessing = false;
        });

        // Auto close after success
        await Future.delayed(const Duration(seconds: 2));
        if (!context.mounted) return;
        Navigator.of(context).pop(); // back to sales screen
      } else {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to complete sale. Please try again.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final total = ref.watch(cartProvider.notifier.select((notifier) => notifier.totalAmount));

    if (cartItems.isEmpty && !_showSuccessReceipt) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: const Center(child: Text('Cart is empty')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: _showSuccessReceipt 
          ? null 
          : AppBar(
              title: const Text('Checkout', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: AppColors.cardBg,
            ),
      body: Stack(
        children: [
          // Main Content
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Grand Total
                        Center(
                          child: Column(
                            children: [
                              const Text(
                                'Grand Total',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                CurrencyHelpers.format(total),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),

                        // Items Summary
                        const Text(
                          'Items Summary',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: cartItems.length,
                            separatorBuilder: (_, __) => const Divider(color: AppColors.border, height: 1),
                            itemBuilder: (ctx, i) {
                              final item = cartItems[i];
                              return ListTile(
                                dense: true,
                                title: Text(item.product.name, style: const TextStyle(color: AppColors.textPrimary)),
                                subtitle: Text(
                                  '${CurrencyHelpers.format(item.product.price)} × ${item.quantity}',
                                  style: const TextStyle(color: AppColors.textSecondary),
                                ),
                                trailing: Text(
                                  CurrencyHelpers.format(item.subtotal),
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 14),
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 30),

                        // Payment Method
                        const Text(
                          'Payment Method',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _buildPaymentOption(AppConstants.paymentCash, Icons.payments_rounded, 'Cash')),
                            const SizedBox(width: 12),
                            Expanded(child: _buildPaymentOption(AppConstants.paymentMomo, Icons.phone_android_rounded, 'MoMo')),
                            const SizedBox(width: 12),
                            Expanded(child: _buildPaymentOption(AppConstants.paymentSplit, Icons.call_split_rounded, 'Split')),
                          ],
                        ),

                        // Split Payment Inputs
                        if (_selectedPayment == AppConstants.paymentSplit) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              children: [
                                _buildSplitField('Cash Amount', _cashController),
                                const SizedBox(height: 12),
                                _buildSplitField('MoMo Amount', _momoController),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Complete Sale Button
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: AppColors.cardBg,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _processSale,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      minimumSize: const Size(double.infinity, 60),
                    ),
                    child: _isProcessing
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'COMPLETE SALE',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          ),

          // Success Receipt Overlay
          if (_showSuccessReceipt)
            Positioned.fill(
              child: Container(
                color: AppColors.scaffoldBg,
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    tween: Tween(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: const BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_rounded, color: Colors.white, size: 60),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Payment Successful!',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Receipt saved and stock deducted.',
                              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSplitField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        prefixText: '${AppConstants.currencySymbol} ',
        prefixStyle: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        filled: true,
        fillColor: AppColors.surfaceBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildPaymentOption(String type, IconData icon, String label) {
    final isSelected = _selectedPayment == type;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedPayment = type);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surfaceBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? AppColors.primary : AppColors.textSecondary, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}