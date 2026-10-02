/// ============================================
/// Change PIN Dialog — ShopPOS
/// ============================================
/// Allows any logged-in staff member (Owner or Cashier)
/// to change their own login PIN.
/// Requires current PIN verification, length validation,
/// and global PIN uniqueness check.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/settings/providers/staff_provider.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';

class ChangePinDialog extends ConsumerStatefulWidget {
  final AppUser user;
  const ChangePinDialog({super.key, required this.user});

  @override
  ConsumerState<ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends ConsumerState<ChangePinDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _isSaving = false;
  String? _newPinError;

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final currentPin = _currentPinController.text.trim();
    final newPin = _newPinController.text.trim();

    // 1. Verify Current PIN
    if (!HashHelpers.verifyPin(currentPin, widget.user.pinHash)) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current PIN is incorrect.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    // 2. Check PIN Uniqueness across all other accounts
    final service = ref.read(staffProvider);
    final isTaken = await service.isPinTaken(newPin, excludeUserId: widget.user.id);

    if (isTaken) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _newPinError = 'This PIN is already assigned to another staff member.';
      });
      HapticFeedback.vibrate();
      return;
    }

    // 3. Update logged-in user's PIN hash
    await ref.read(currentUserProvider.notifier).updatePin(newPin);

    if (!mounted) return;
    setState(() => _isSaving = false);

    HapticFeedback.mediumImpact();
    Navigator.pop(context, true);
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
      prefixIcon: const Icon(Icons.lock_rounded, size: 20, color: AppColors.textSecondary),
      suffixIcon: suffix,
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
      child: SingleChildScrollView(
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
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: AppSpacing.borderMd,
                      ),
                      child: const Icon(
                        Icons.pin_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Change My PIN',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'For account ${widget.user.name}',
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

                // Current PIN
                TextFormField(
                  controller: _currentPinController,
                  keyboardType: TextInputType.number,
                  obscureText: _obscureCurrent,
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
                    label: 'Current PIN',
                    hint: 'Enter current PIN',
                    suffix: IconButton(
                      icon: Icon(
                        _obscureCurrent
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () =>
                          setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter your current PIN';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.md),

                // New PIN
                TextFormField(
                  controller: _newPinController,
                  keyboardType: TextInputType.number,
                  obscureText: _obscureNew,
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
                    label: 'New PIN (4-6 digits)',
                    hint: 'e.g. 5555',
                    errorText: _newPinError,
                    suffix: IconButton(
                      icon: Icon(
                        _obscureNew
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                  onChanged: (_) {
                    if (_newPinError != null) {
                      setState(() => _newPinError = null);
                    }
                  },
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter a new PIN';
                    }
                    if (v.trim().length < 4 || v.trim().length > 6) {
                      return 'PIN must be 4 to 6 digits';
                    }
                    if (AppConstants.defaultPins.contains(v.trim())) {
                      return 'Default PINs are not allowed';
                    }
                    if (v.trim() == _currentPinController.text.trim()) {
                      return 'New PIN must be different from current PIN';
                    }
                    return _newPinError;
                  },
                ),

                const SizedBox(height: AppSpacing.md),

                // Confirm New PIN
                TextFormField(
                  controller: _confirmPinController,
                  keyboardType: TextInputType.number,
                  obscureText: _obscureNew,
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
                    hint: 'Re-enter new PIN',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please confirm your new PIN';
                    }
                    if (v.trim() != _newPinController.text.trim()) {
                      return 'PINs do not match';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.sm),
                const Text(
                  '🔒 New PIN is stored hashed using SHA-256.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),

                const SizedBox(height: AppSpacing.xl),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _isSaving ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.border),
                          foregroundColor: AppColors.textSecondary,
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md),
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
                            : const Icon(Icons.check_circle_rounded),
                        label: Text(_isSaving ? 'Updating…' : 'Update PIN'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textOnPrimary,
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
