/// ============================================
/// Add Cashier Dialog — ShopPOS
/// ============================================
/// Owner-only dialog to create a new cashier account.
/// Requires: Name + 4-digit PIN.
/// Enforces global PIN uniqueness across all accounts.
/// PIN is hashed with SHA-256 before storage.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/settings/providers/staff_provider.dart';

class AddCashierDialog extends ConsumerStatefulWidget {
  const AddCashierDialog({super.key});

  @override
  ConsumerState<AddCashierDialog> createState() => _AddCashierDialogState();
}

class _AddCashierDialogState extends ConsumerState<AddCashierDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _obscurePin = true;
  String _role = AppConstants.roleCashier;
  bool _isCreating = false;
  String? _pinError;

  String _lastCheckedPin = '';
  bool? _lastPinAvailable;

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _suggestRandomPin() async {
    HapticFeedback.selectionClick();
    final service = ref.read(staffProvider);
    final suggested = await service.generateSuggestedPin();
    if (mounted) {
      setState(() {
        _pinController.text = suggested;
        _confirmPinController.text = suggested;
        _pinError = null;
        _lastPinAvailable = true;
        _lastCheckedPin = suggested;
      });
    }
  }

  Future<void> _checkPinUniqueness(String value) async {
    final trimmed = value.trim();
    if (trimmed.length < 4 || trimmed == _lastCheckedPin) return;

    _lastCheckedPin = trimmed;
    final service = ref.read(staffProvider);
    final taken = await service.isPinTaken(trimmed);

    if (mounted && _pinController.text.trim() == trimmed) {
      setState(() {
        _lastPinAvailable = !taken;
        _pinError = taken ? 'This PIN is already assigned to another staff member' : null;
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final pin = _pinController.text.trim();
    if (_lastPinAvailable != true || _lastCheckedPin != pin) {
      await _checkPinUniqueness(pin);
      if (_pinError != null) return;
    }

    setState(() => _isCreating = true);
    HapticFeedback.mediumImpact();

    final service = ref.read(staffProvider);
    final result = await service.createCashier(
      name: _nameController.text,
      pin: pin,
      role: _role,
    );

    if (!mounted) return;
    setState(() => _isCreating = false);

    switch (result) {
      case StaffOperationResult.success:
        HapticFeedback.mediumImpact();
        Navigator.pop(context, true);
      case StaffOperationResult.pinAlreadyExists:
        setState(() {
          _pinError = 'This PIN is already assigned to another staff member';
          _lastPinAvailable = false;
        });
      case StaffOperationResult.invalidPin:
        setState(() {
          _pinError = 'PIN must be 4 to 6 digits and not a default PIN';
        });
      case StaffOperationResult.unauthorized:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unauthorized: Only the shop owner can create staff accounts.'),
            backgroundColor: AppColors.danger,
          ),
        );
      case StaffOperationResult.weakPin:
      case StaffOperationResult.userNotFound:
      case StaffOperationResult.error:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create account. Please check the inputs.'),
            backgroundColor: AppColors.danger,
          ),
        );
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    IconData? prefixIcon,
    Widget? suffix,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 20, color: AppColors.textSecondary)
          : null,
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
                        Icons.person_add_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add New Cashier',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Assign a unique 4-digit PIN for login',
                            style: TextStyle(
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

                // Cashier Name
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  textCapitalization: TextCapitalization.words,
                  decoration: _fieldDecoration(
                    label: 'Cashier Name',
                    hint: 'e.g. Ama Mensah',
                    prefixIcon: Icons.badge_rounded,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter the cashier\'s name';
                    }
                    if (v.trim().length < 2) {
                      return 'Name must be at least 2 characters';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.md),

                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: _fieldDecoration(
                    label: 'Role',
                    hint: '',
                    prefixIcon: Icons.work_outline_rounded,
                  ),
                  items: [
                    for (final r in AppConstants.staffRoles)
                      DropdownMenuItem(value: r, child: Text(AppConstants.roleLabel(r))),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? _role),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    switch (_role) {
                      AppConstants.roleManager =>
                        'Sells, discounts, voids/refunds, manages stock and products, sees reports and expenses.',
                      AppConstants.roleStockClerk =>
                        'Restocks and adjusts stock only. Cannot sell or see reports.',
                      _ => 'Sells and sees their own sales history.',
                    },
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // Cashier PIN
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
                    label: 'Assigned PIN',
                    hint: 'e.g. 5555',
                    prefixIcon: Icons.lock_rounded,
                    errorText: _pinError,
                    suffix: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_lastPinAvailable == true)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(Icons.check_circle_rounded,
                                color: AppColors.success, size: 20),
                          ),
                        IconButton(
                          icon: Icon(
                            _obscurePin
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePin = !_obscurePin),
                        ),
                      ],
                    ),
                  ),
                  onChanged: (v) {
                    if (_pinError != null) {
                      setState(() {
                        _pinError = null;
                        _lastPinAvailable = null;
                      });
                    }
                    if (v.trim().length >= 4) {
                      _checkPinUniqueness(v);
                    }
                  },
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please assign a PIN';
                    }
                    if (v.trim().length < 4) {
                      return 'PIN must be at least 4 digits';
                    }
                    if (AppConstants.defaultPins.contains(v.trim())) {
                      return 'Default PINs are not allowed';
                    }
                    return _pinError;
                  },
                ),

                // Suggest PIN Button
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
                  controller: _confirmPinController,
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
                    label: 'Confirm PIN',
                    hint: 'Re-enter PIN',
                    prefixIcon: Icons.lock_outline_rounded,
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please confirm the PIN';
                    }
                    if (v != _pinController.text) {
                      return 'PINs do not match';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.sm),
                const Text(
                  '🔒 PIN is stored hashed & required for login.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),

                const SizedBox(height: AppSpacing.xl),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _isCreating ? null : () => Navigator.pop(context),
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
                        onPressed: _isCreating ? null : _submit,
                        icon: _isCreating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.textOnPrimary,
                                ),
                              )
                            : const Icon(Icons.person_add_rounded),
                        label: Text(_isCreating ? 'Creating…' : 'Create Account'),
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
