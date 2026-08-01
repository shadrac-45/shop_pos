/// ============================================
/// Add Product Dialog — ShopPOS
/// ============================================
/// Dialog for owners to add a new product.
/// Inherits all shared form helpers from
/// BaseProductDialogState (label, inputDecoration,
/// colorPicker, dialogButtons). Only the Add-specific
/// fields and save logic live here.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../models/batch.dart';
import '../../../models/product.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../utils/date_helpers.dart';
import 'base_product_dialog.dart';

class AddProductDialog extends BaseProductDialog {
  const AddProductDialog({super.key});

  @override
  ConsumerState<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState
    extends BaseProductDialogState<AddProductDialog> {
  // ── Controllers ──────────────────────────────────────────────────
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _categoryController = TextEditingController();
  final _qtyController = TextEditingController();
  final _noteController = TextEditingController();

  // ── Local state ───────────────────────────────────────────────────
  int _selectedColorIndex = 0;
  DateTime _selectedExpiry = DateTime.now().add(const Duration(days: 90));

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ── BaseProductDialogState overrides ──────────────────────────────

  @override
  String get submitLabel => 'Add Product';

  @override
  Widget buildDialogTitle() {
    return const Row(
      children: [
        Icon(Icons.add_box_rounded, color: AppColors.primary, size: 24),
        SizedBox(width: 10),
        Text(
          'Add New Product',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  @override
  List<Widget> buildFormFields() {
    return [
      // Product name
      buildLabel('Product Name *'),
      const SizedBox(height: 6),
      TextFormField(
        controller: _nameController,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: inputDecoration(hint: 'e.g., Pure Water'),
        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        textCapitalization: TextCapitalization.words,
      ),

      const SizedBox(height: 14),

      // Price + Category (side by side)
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildLabel('Price (GH₵) *'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _priceController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: inputDecoration(hint: '0.00'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
                buildLabel('Category'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _categoryController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: inputDecoration(hint: 'e.g., Food'),
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ),
          ),
        ],
      ),

      const SizedBox(height: 14),

      // Color picker (inherited from base)
      buildLabel('Button Color'),
      const SizedBox(height: 8),
      buildColorPicker(
        selectedIndex: _selectedColorIndex,
        onSelect: (index) => setState(() => _selectedColorIndex = index),
      ),

      const SizedBox(height: 20),
      const Divider(color: AppColors.border),
      const SizedBox(height: 8),

      const Text(
        'Initial Stock (optional)',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 12),

      // Quantity + Expiry Date (side by side)
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildLabel('Quantity'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _qtyController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: inputDecoration(hint: '0'),
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
                buildLabel('Expiry Date'),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _pickExpiryDate,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 16, color: AppColors.textMuted),
                        const SizedBox(width: 6),
                        Text(
                          DateHelpers.formatShort(_selectedExpiry),
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13),
                        ),
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

      // Supplier note
      buildLabel('Supplier Note'),
      const SizedBox(height: 6),
      TextFormField(
        controller: _noteController,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: inputDecoration(hint: 'Optional note...'),
        maxLines: 2,
      ),
    ];
  }

  // ── Private helpers ───────────────────────────────────────────────

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedExpiry,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _selectedExpiry = picked);
  }

  // ── Save logic ────────────────────────────────────────────────────

  @override
  Future<void> onSubmit() async {
    if (!formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    final isar = ref.read(isarProvider);
    final productName = _nameController.text.trim();

    try {
      await isar.writeTxn(() async {
        final product = Product()
          ..name = productName
          ..price = double.parse(_priceController.text.trim())
          ..category = _categoryController.text.trim().isEmpty
              ? 'General'
              : _categoryController.text.trim()
          ..quickButtonColor =
              AppConstants.quickButtonPalette[_selectedColorIndex].toARGB32();

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
              ..supplierNote = _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim();
            await isar.batchs.put(batch);
            batch.product.value = product;
            await batch.product.save();
          }
        }
      });

      if (mounted) {
        // Refresh product stream
        ref.invalidate(productServiceProvider);
        HapticFeedback.heavyImpact();
        Navigator.of(context).pop();
        context.showSuccessSnackbar('$productName added successfully!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        context.showErrorSnackbar('Error: $e');
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }
}