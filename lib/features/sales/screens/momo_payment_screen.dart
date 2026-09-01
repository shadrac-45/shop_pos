/// ============================================
/// Mobile Money (MoMo) Payment Screen — ShopPOS
/// ============================================
/// Implements Paystack Ghana Push-Payment Flow:
/// 1. Phone number & Provider selection form
/// 2. Initiate charge via local backend proxy
/// 3. Waiting state with spinner (polling Paystack every 5s up to 90s)
/// 4. Sale completion on success, retry/fallback options on fail/timeout
/// ============================================
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/features/sales/models/paystack_models.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';
import 'package:shop_pos/features/sales/services/paystack_service.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';

enum MomoFlowStep {
  form,
  charging,
  waiting,
  success,
  failed,
  timeout,
}

class MomoPaymentScreen extends ConsumerStatefulWidget {
  final double totalAmount;

  const MomoPaymentScreen({
    super.key,
    required this.totalAmount,
  });

  @override
  ConsumerState<MomoPaymentScreen> createState() => _MomoPaymentScreenState();
}

class _MomoPaymentScreenState extends ConsumerState<MomoPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneController = TextEditingController();

  String _selectedProvider = AppConstants.momoProviderMtn;
  MomoFlowStep _currentStep = MomoFlowStep.form;

  String? _currentReference;
  String? _errorMessage;
  int _secondsRemaining = AppConstants.momoTimeoutSec;

  Timer? _pollingTimer;
  Timer? _countdownTimer;

  static const _providers = [
    (code: AppConstants.momoProviderMtn, name: 'MTN Mobile Money', color: Color(0xFFFFCC00), icon: Icons.phone_android_rounded),
    (code: AppConstants.momoProviderVodafone, name: 'Vodafone Cash', color: Color(0xFFE60000), icon: Icons.phone_iphone_rounded),
    (code: AppConstants.momoProviderAirtelTigo, name: 'AirtelTigo Money', color: Color(0xFF003399), icon: Icons.cell_tower_rounded),
  ];

  @override
  void dispose() {
    _cancelTimers();
    _phoneController.dispose();
    super.dispose();
  }

  void _cancelTimers() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  // ── Initiate Charge ───────────────────────────────────────────────────────

  Future<void> _initiateCharge() async {
    if (!_formKey.currentState!.validate()) return;

    final rawPhone = _phoneController.text.trim();
    final normalisedPhone = normaliseGhanaPhone(rawPhone);
    if (normalisedPhone == null) {
      setState(() => _errorMessage = 'Invalid Ghana phone number format.');
      return;
    }

    final reference = 'shoppos_${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 8)}';

    setState(() {
      _currentStep = MomoFlowStep.charging;
      _currentReference = reference;
      _errorMessage = null;
    });

    final paystackService = ref.read(paystackServiceProvider);
    final result = await paystackService.initiateCharge(
      phone: normalisedPhone,
      amountGhs: widget.totalAmount,
      provider: _selectedProvider,
      reference: reference,
    );

    if (!mounted) return;

    if (result.callSucceeded) {
      _startWaitingAndPolling(reference);
    } else {
      setState(() {
        _currentStep = MomoFlowStep.failed;
        _errorMessage = result.errorMessage ?? 'Failed to send payment request.';
      });
    }
  }

  // ── Polling & Countdown ────────────────────────────────────────────────────

  void _startWaitingAndPolling(String reference) {
    setState(() {
      _currentStep = MomoFlowStep.waiting;
      _secondsRemaining = AppConstants.momoTimeoutSec;
    });

    // Countdown timer for 90s timeout
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        _cancelTimers();
        setState(() {
          _currentStep = MomoFlowStep.timeout;
          _errorMessage = 'Customer did not respond in time (90s timeout).';
        });
      } else {
        setState(() => _secondsRemaining--);
      }
    });

    // Polling timer every 5s
    _pollingTimer = Timer.periodic(
      const Duration(seconds: AppConstants.momoPollingIntervalSec),
      (_) => _checkPaymentStatus(reference),
    );

    // Initial check right away
    _checkPaymentStatus(reference);
  }

  Future<void> _checkPaymentStatus(String reference) async {
    final paystackService = ref.read(paystackServiceProvider);
    final verifyResult = await paystackService.verifyStatus(reference);

    if (!mounted || _currentStep != MomoFlowStep.waiting) return;

    switch (verifyResult.status) {
      case PaystackVerifyStatus.success:
        _cancelTimers();
        await _finalizeSaleSuccess(reference);
        break;

      case PaystackVerifyStatus.failed:
      case PaystackVerifyStatus.abandoned:
        _cancelTimers();
        setState(() {
          _currentStep = MomoFlowStep.failed;
          _errorMessage = verifyResult.gatewayResponse ?? 'Payment was declined by customer or system.';
        });
        break;

      case PaystackVerifyStatus.pending:
      case PaystackVerifyStatus.networkError:
        // Continue waiting and polling
        break;
    }
  }

  // ── Complete Sale on Success ──────────────────────────────────────────────

  Future<void> _finalizeSaleSuccess(String reference) async {
    final cartNotifier = ref.read(cartProvider.notifier);
    final currentUser = ref.read(currentUserProvider);

    final success = await cartNotifier.completeSaleMomo(
      paystackReference: reference,
      provider: _selectedProvider,
      phone: normaliseGhanaPhone(_phoneController.text.trim()) ?? _phoneController.text.trim(),
      cashierId: currentUser?.id ?? 0,
    );

    if (!mounted) return;

    if (success) {
      HapticFeedback.heavyImpact();
      setState(() => _currentStep = MomoFlowStep.success);
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.of(context).pop(true);
        context.showSuccessSnackbar('MoMo Sale completed successfully!');
      }
    } else {
      setState(() {
        _currentStep = MomoFlowStep.failed;
        _errorMessage = 'Payment received, but failed to save sale to local database.';
      });
    }
  }

  // ── Retry / Fallback ──────────────────────────────────────────────────────

  void _resetToForm() {
    _cancelTimers();
    setState(() {
      _currentStep = MomoFlowStep.form;
      _errorMessage = null;
    });
  }

  // ── UI Builders ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Mobile Money Payment'),
        backgroundColor: AppColors.cardBg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _currentStep == MomoFlowStep.waiting || _currentStep == MomoFlowStep.charging
              ? null
              : () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: switch (_currentStep) {
            MomoFlowStep.form => _buildFormStep(),
            MomoFlowStep.charging => _buildChargingStep(),
            MomoFlowStep.waiting => _buildWaitingStep(),
            MomoFlowStep.success => _buildSuccessStep(),
            MomoFlowStep.failed => _buildFailedStep(),
            MomoFlowStep.timeout => _buildTimeoutStep(),
          },
        ),
      ),
    );
  }

  Widget _buildFormStep() {
    // MediaQuery bottom inset ensures the "Send Payment Request" button
    // is never hidden behind the software keyboard on small phones.
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Total Amount Display Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  const Text('Amount to Charge',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      CurrencyHelpers.format(widget.totalAmount),
                      style: const TextStyle(
                          fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Provider Selector
            const Text('Select Mobile Network *',
                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Column(
              children: _providers.map((p) {
                final isSelected = _selectedProvider == p.code;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => setState(() => _selectedProvider = p.code),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surfaceBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isSelected ? AppColors.primary : AppColors.border,
                            width: isSelected ? 2 : 1),
                      ),
                      child: Row(
                        children: [
                          Icon(p.icon,
                              color: isSelected ? AppColors.primary : AppColors.textSecondary,
                              size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              p.name,
                              style: TextStyle(
                                color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle_rounded,
                                color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Phone Number Input
            const Text('Customer Phone Number *',
                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, letterSpacing: 1),
              decoration: InputDecoration(
                hintText: 'e.g. 0551234987',
                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 15),
                prefixIcon: const Icon(Icons.phone_rounded, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) => validateGhanaPhone(v ?? ''),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],

            const SizedBox(height: 32),

            // Confirm Button — always visible above the keyboard
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _initiateCharge,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Send Payment Request',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textOnPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChargingStep() {
    // SingleChildScrollView prevents vertical overflow in landscape / small phones.
    return const SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 24),
            Text(
              'Initiating Paystack MoMo Request...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text('Connecting to payment gateway',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    strokeWidth: 6,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  '${_secondsRemaining}s',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              'Payment Request Sent!',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Ask the customer to check their phone and enter their Mobile Money PIN to approve the transaction.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.4),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                'Ref: ${_currentReference ?? ''}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted, fontFamily: 'monospace'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessStep() {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 80),
            SizedBox(height: 24),
            Text(
              'Payment Approved!',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Sale successfully completed via MoMo',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 80),
            const SizedBox(height: 24),
            const Text(
              'Payment Failed',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _errorMessage ?? 'The payment request was declined or failed.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Use Other Method',
                      style: TextStyle(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _resetToForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textOnPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Try Again',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeoutStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_off_rounded, color: AppColors.warning, size: 80),
            const SizedBox(height: 24),
            const Text(
              'Payment Timed Out',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'The customer did not respond to the mobile money prompt within 90 seconds.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Cancel / Switch',
                      style: TextStyle(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _resetToForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textOnPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Retry Prompt',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
