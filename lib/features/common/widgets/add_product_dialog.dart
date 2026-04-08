/// ============================================
/// Add Product Dialog — ShopPOS
/// ============================================
/// Dialog for owners to add a new product with
/// name, price, category, color selection, and
/// optional initial batch.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/product.dart';
import '../../../models/batch.dart';
import '../../../providers/database_provider.dart';
import '../../../utils/date_helpers.dart';

class AddProductDialog extends ConsumerStatefulWidget {
  const AddProductDialog({super.key});

  @override
  ConsumerState<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends ConsumerState<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _categoryController = TextEditingController();
  final _qtyController = TextEditingController();
  final _noteController = TextEditingController();

  int _selectedColorIndex = 0;
  DateTime _selectedExpiry = DateTime.now().add(const Duration(days: 90));
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
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

    setState(() => _isLoading = true);

    final isar = ref.read(isarProvider);

    try {
      await isar.writeTxn(() async {
        final product = Product()
          ..name = _nameController.text.trim()
          ..price = double.parse(_priceController.text.trim())
          ..category = _categoryController.text.trim().isEmpty ? 'General' : _categoryController.text.trim()
          ..quickButtonColor = AppConstants.quickButtonPalette[_selectedColorIndex].toARGB32();

        final productId = await isar.products.put(product);

        final qtyText = _qtyController.text.trim();
        if (qtyText.isNotEmpty) {
          final quantity = int.parse(qtyText);
          if (quantity > 0) {
            final batch = Batch()
              ..productId = productId
              ..quantity = quantity
              ..expiryDate = _selectedExpiry
              ..restockDate = DateTime.now()
              ..supplierNote = _noteController.text.trim().isEmpty ? null : _noteController.text.trim();

            await isar.batchs.put(batch);
          }
        }
      });

      // Fixed: tight mounted check + block before using BuildContext after async
      if (mounted) {
        HapticFeedback.heavyImpact();
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_nameController.text.trim()} added successfully!'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.add_box_rounded, color: AppColors.primary, size: 24),
                  SizedBox(width: 10),
                  Text('Add New Product', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),

              const SizedBox(height: 20),

              _buildLabel('Product Name *'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: _inputDecoration(hint: 'e.g., Pure Water'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                textCapitalization: TextCapitalization.words,
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Price (GH₵) *'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _priceController,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: _inputDecoration(hint: '0.00'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            if (double.tryParse(v.trim()) == null) return 'Invalid';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Category'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _categoryController,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: _inputDecoration(hint: 'e.g., Food'),
                          textCapitalization: TextCapitalization.words,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              _buildLabel('Button Color'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(AppConstants.quickButtonPalette.length, (index) {
                  final color = AppConstants.quickButtonPalette[index];
                  final isSelected = _selectedColorIndex == index;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColorIndex = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 3),
                        boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)] : null,
                      ),
                      child: isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                    ),
                  );
                }),
              ),

              const SizedBox(height: 20),
              const Divider(color: AppColors.border),
              const SizedBox(height: 8),

              const Text('Initial Stock (optional)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Quantity'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _qtyController,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: _inputDecoration(hint: '0'),
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Expiry Date'),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: _pickExpiryDate,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.textMuted),
                                const SizedBox(width: 6),
                                Text(DateHelpers.formatShort(_selectedExpiry), style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              _buildLabel('Supplier Note'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _noteController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: _inputDecoration(hint: 'Optional note...'),
                maxLines: 2,
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textOnPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnPrimary))
                          : const Text('Add Product', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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

  Widget _buildLabel(String text) {
    return Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary));
  }

  InputDecoration _inputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
      filled: true,
      fillColor: AppColors.surfaceBg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}