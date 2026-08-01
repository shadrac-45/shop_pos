/// ============================================
/// Edit Product Dialog — ShopPOS
/// ============================================
/// Dialog for owners to edit an existing product.
/// Inherits all shared form helpers from
/// BaseProductDialogState (label, inputDecoration,
/// colorPicker, dialogButtons). Only Edit-specific
/// initialisation and save logic live here.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../models/product.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/product_provider.dart';
import 'base_product_dialog.dart';

class EditProductDialog extends BaseProductDialog {
  final Product product;

  const EditProductDialog({super.key, required this.product});

  @override
  ConsumerState<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState
    extends BaseProductDialogState<EditProductDialog> {
  // ── Controllers ──────────────────────────────────────────────────
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _categoryController;

  // ── Local state ───────────────────────────────────────────────────
  late int _selectedColorIndex;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _nameController = TextEditingController(text: product.name);
    _priceController =
        TextEditingController(text: product.price.toString());
    _categoryController = TextEditingController(text: product.category);

    // Find the matching palette index for the stored color value.
    final matchingIndex = AppConstants.quickButtonPalette
        .indexWhere((c) => c.toARGB32() == product.quickButtonColor);
    _selectedColorIndex = matchingIndex >= 0 ? matchingIndex : 0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  // ── BaseProductDialogState overrides ──────────────────────────────

  @override
  String get submitLabel => 'Save Changes';

  @override
  Widget buildDialogTitle() {
    return const Row(
      children: [
        Icon(Icons.edit_rounded, color: AppColors.primary, size: 24),
        SizedBox(width: 10),
        Text(
          'Edit Product',
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

      const SizedBox(height: 10),
    ];
  }

  // ── Save logic ────────────────────────────────────────────────────

  @override
  Future<void> onSubmit() async {
    if (!formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    final isar = ref.read(isarProvider);

    try {
      await isar.writeTxn(() async {
        widget.product.name = _nameController.text.trim();
        widget.product.price =
            double.parse(_priceController.text.trim());
        widget.product.category = _categoryController.text.trim().isEmpty
            ? 'General'
            : _categoryController.text.trim();
        widget.product.quickButtonColor =
            AppConstants.quickButtonPalette[_selectedColorIndex].toARGB32();

        await isar.products.put(widget.product);
      });

      if (!mounted) return;

      // Refresh product stream
      ref.invalidate(productServiceProvider);
      HapticFeedback.heavyImpact();
      Navigator.of(context).pop();
      context.showSuccessSnackbar(
          '${widget.product.name} updated successfully!');
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      context.showErrorSnackbar('Error: $e');
    }
  }
}