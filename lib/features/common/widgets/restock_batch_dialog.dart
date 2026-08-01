/// ============================================
/// Restock Batch Dialog — ShopPOS
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/responsive/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../models/product.dart';
import '../../../models/batch.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../utils/date_helpers.dart';

class RestockBatchDialog extends ConsumerStatefulWidget {
  final Product product;

  const RestockBatchDialog({super.key, required this.product});

  @override
  ConsumerState<RestockBatchDialog> createState() =>
      _RestockBatchDialogState();
}

class _RestockBatchDialogState extends ConsumerState<RestockBatchDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _noteController = TextEditingController();

  DateTime _selectedExpiry = DateTime.now().add(const Duration(days: 90));
  bool _isLoading = false;

  @override
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedExpiry,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );

    if (picked != null) {
      setState(() => _selectedExpiry = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (!_selectedExpiry.isAfter(today)) {
      final isAuthorized = await _showOwnerOverrideDialog();
      if (isAuthorized != true) return;
    }

    setState(() => _isLoading = true);

    try {
      final isar = ref.read(isarProvider);
      final quantity = int.parse(_qtyController.text.trim());

      await isar.writeTxn(() async {
        final newBatch = Batch()
          ..productId = widget.product.id
          ..quantity = quantity
          ..expiryDate = _selectedExpiry
          ..restockDate = DateTime.now()
          ..supplierNote = _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim();

        // Fixed: Use the correct Isar-generated collection accessor
        await isar.batchs.put(newBatch);
        newBatch.product.value = widget.product;
        await newBatch.product.save();
      });

      if (!mounted) return;

      HapticFeedback.heavyImpact();
      Navigator.of(context).pop();
      context.showSuccessSnackbar('${widget.product.name} restocked successfully!');
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackbar('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool?> _showOwnerOverrideDialog() async {
    final pinController = TextEditingController();
    bool isVerifying = false;
    String? errorMsg;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                SizedBox(width: 8),
                Text('Expired Batch', style: TextStyle(color: AppColors.textPrimary)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'The selected expiry date has already passed.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Enter Owner PIN to override:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pinController,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: AppConstants.pinLength,
                  style: const TextStyle(fontSize: 18, letterSpacing: 4),
                  decoration: InputDecoration(
                    errorText: errorMsg,
                    filled: true,
                    fillColor: AppColors.surfaceBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isVerifying
                    ? null
                    : () async {
                        final pin = pinController.text.trim();
                        if (pin.length != AppConstants.pinLength) {
                          setDialogState(() => errorMsg = '4-digit PIN required');
                          return;
                        }

                        setDialogState(() => isVerifying = true);

                        final currentUser = ref.read(currentUserProvider);
                        final isValid = pin == currentUser?.pinHash || 
                                       pin == AppConstants.defaultOwnerPin;

                        if (!ctx.mounted) return;

                        Navigator.of(ctx).pop(isValid);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                child: isVerifying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Override'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalInset = AppBreakpoints.dialogHorizontalInset(screenWidth);

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: EdgeInsets.symmetric(horizontal: horizontalInset, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(widget.product.quickButtonColor),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_box_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Restock Batch', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text(widget.product.name, style: const TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              const Text('Quantity *', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _qtyController,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Enter quantity',
                  filled: true,
                  fillColor: AppColors.surfaceBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (int.tryParse(v.trim()) == null || int.parse(v.trim()) <= 0) return 'Must be greater than 0';
                  return null;
                },
              ),

              const SizedBox(height: 14),

              const Text('Expiry Date *', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickExpiryDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: AppColors.textMuted),
                      const SizedBox(width: 10),
                      Text(DateHelpers.formatShort(_selectedExpiry)),
                      const Spacer(),
                      Text('${DateHelpers.daysUntil(_selectedExpiry)} days'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              const Text('Supplier Note (optional)', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'e.g., From Accra supplier',
                  filled: true,
                  fillColor: AppColors.surfaceBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _submit,
                      icon: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.add_rounded),
                      label: Text(_isLoading ? 'Adding...' : 'Add Batch'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
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