/// ============================================
/// Reset PIN Dialog — ShopPOS
/// ============================================
/// Owner-only dialog to reset a cashier's 4-digit PIN.
/// Validates length, confirm match, and uniqueness
/// before storing the hashed PIN.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/settings/providers/staff_provider.dart';

class ResetPinDialog extends ConsumerStatefulWidget {
  final AppUser cashier;
  const ResetPinDialog({super.key, required this.cashier});

  @override
  ConsumerState<ResetPinDialog> createState() => _ResetPinDialogState();
}

class _ResetPinDialogState extends ConsumerState<ResetPinDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePin = true;
  bool _isSaving = false;
  String? _pinError;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _suggestRandomPin() async {
    HapticFeedback.selectionClick();
    final service = ref.read(staffProvider);
    final suggested = await service.generateSuggestedPin();
    if (mounted) {
      setState(() {
        _pinController.text = suggested;
        _confirmController.text = suggested;
        _pinError = null;
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final pin = _pinController.text.trim();
    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    final service = ref.read(staffProvider);
    final result = await service.resetCashierPin(
      widget.cashier.id,
      pin,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    switch (result) {
      case StaffOperationResult.success:
        HapticFeedback.mediumImpact();
        Navigator.pop(context, true);
      case StaffOperationResult.pinAlreadyExists:
        setState(() {
          _pinError = 'This PIN is already assigned to another staff member';
        });
      case StaffOperationResult.invalidPin:
        setState(() {
          _pinError = 'PIN must be 4 to 6 digits and not a default PIN';
        });
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to reset PIN. Please try again.'),
            backgroundColor: AppColors.danger,
          ),
        );
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    Widget? suffix,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      suffixIcon: suffix,
      prefixIcon: const Icon(Icons.lock_rounded,
          size: 20, color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.surfaceBg,
      border: OutlineInputBorder(
        borderRadius: AppSpacing.borderMd,
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppSpacing.borderMd,
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppSpacing.borderMd,
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppSpacing.borderMd,
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderXl),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.15),
                      borderRadius: AppSpacing.borderMd,
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: AppColors.info,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Reset Cashier PIN',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'For ${widget.cashier.name}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),

              // New PIN
              TextFormField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                obscureText: _obscurePin,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  letterSpacing: 4,
                ),
                decoration: _fieldDecoration(
                  label: 'New 4-Digit PIN',
                  hint: 'e.g. 8888',
                  errorText: _pinError,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePin
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePin = !_obscurePin),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please enter a new PIN';
                  if (v.length < 4) {
                    return 'PIN must be at least 4 digits';
                  }
                  if (AppConstants.defaultPins.contains(v.trim())) {
                    return 'Default PINs are not allowed';
                  }
                  return _pinError;
                },
              ),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _suggestRandomPin,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: const Text(
                    'Auto-Generate PIN',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              // Confirm PIN
              TextFormField(
                controller: _confirmController,
                keyboardType: TextInputType.number,
                obscureText: _obscurePin,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  letterSpacing: 4,
                ),
                decoration: _fieldDecoration(
                  label: 'Confirm New PIN',
                  hint: 'Re-enter PIN',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Please confirm the new PIN';
                  }
                  if (v != _pinController.text) {
                    return 'PINs do not match';
                  }
                  return null;
                },
              ),

              const SizedBox(height: AppSpacing.xl),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isSaving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        foregroundColor: AppColors.textSecondary,
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _submit,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textOnPrimary,
                              ),
                            )
                          : const Icon(Icons.lock_reset_rounded),
                      label: Text(_isSaving ? 'Saving…' : 'Reset PIN'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.info,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
