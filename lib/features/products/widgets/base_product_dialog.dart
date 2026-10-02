/// ============================================
/// Base Product Dialog — ShopPOS
/// ============================================
/// Abstract superclass for Add and Edit product
/// dialogs. Encapsulates all shared form helpers
/// (label builder, input decoration, color picker,
/// action button row) so subclasses can inherit
/// instead of duplicate.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/responsive/app_breakpoints.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/products/models/product.dart';

/// Abstract base [ConsumerStatefulWidget] for product form dialogs.
/// Subclasses must override [buildDialogTitle] and [buildFormFields].
abstract class BaseProductDialog extends ConsumerStatefulWidget {
  const BaseProductDialog({super.key});
}

/// Abstract base [ConsumerState] for product form dialogs.
///
/// Provides shared helpers:
///   - [buildLabel] — section label text
///   - [inputDecoration] — consistent dark-theme input styling
///   - [buildColorPicker] — animated color-swatch selector
///   - [buildDialogButtons] — cancel + submit action row
///
/// Concrete subclasses must implement:
///   - [buildDialogTitle] → Row with icon + title text
///   - [buildFormFields] → the unique fields for this dialog
///   - [onSubmit] → the async save/write logic
///   - [submitLabel] → button label string (e.g. "Add Product")
abstract class BaseProductDialogState<T extends BaseProductDialog>
    extends ConsumerState<T> {
  // ── Shared state ──────────────────────────────────────────────────
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  bool isLoading = false;

  // Fields shared by Add and Edit (see [buildInventoryFields]).
  final costController = TextEditingController();
  final barcodeController = TextEditingController();
  final skuController = TextEditingController();
  final reorderController = TextEditingController();

  @override
  void dispose() {
    costController.dispose();
    barcodeController.dispose();
    skuController.dispose();
    reorderController.dispose();
    super.dispose();
  }

  /// Fills the shared fields from an existing product.
  void loadInventoryFields(Product p) {
    costController.text = p.costPrice?.toStringAsFixed(2) ?? '';
    barcodeController.text = p.barcode ?? '';
    skuController.text = p.sku ?? '';
    reorderController.text = p.reorderLevel > 0 ? '${p.reorderLevel}' : '';
  }

  double? get costValue {
    final t = costController.text.trim();
    return t.isEmpty ? null : double.tryParse(t);
  }

  int get reorderValue => int.tryParse(reorderController.text.trim()) ?? 0;

  /// Cost price, barcode, SKU and reorder level.
  List<Widget> buildInventoryFields() {
    Widget half(String label, TextEditingController c, String hint,
            {TextInputType? keyboard, FormFieldValidator<String>? validator}) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildLabel(label),
              const SizedBox(height: 6),
              TextFormField(
                controller: c,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: inputDecoration(hint: hint),
                keyboardType: keyboard,
                validator: validator,
              ),
            ],
          ),
        );

    return [
      Row(
        children: [
          half('Cost price (${CurrencyHelpers.symbol})', costController, 'Optional',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => (v == null || v.trim().isEmpty || double.tryParse(v.trim()) != null)
                  ? null
                  : 'Invalid'),
          const SizedBox(width: 12),
          half('Low-stock alert at', reorderController, 'e.g. 10',
              keyboard: TextInputType.number,
              validator: (v) =>
                  (v == null || v.trim().isEmpty || int.tryParse(v.trim()) != null)
                      ? null
                      : 'Whole number'),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          half('Barcode', barcodeController, 'Scan or type'),
          const SizedBox(width: 12),
          half('SKU', skuController, 'Optional'),
        ],
      ),
    ];
  }

  // ── Abstract members subclasses must implement ────────────────────

  /// The icon + title row shown at the top of the dialog.
  Widget buildDialogTitle();

  /// The form fields unique to this dialog (below the shared title).
  List<Widget> buildFormFields();

  /// The async save operation. Called when the user taps Submit.
  Future<void> onSubmit();

  /// Label for the primary action button (e.g. "Add Product").
  String get submitLabel;

  // ── Shared helper builders ────────────────────────────────────────

  /// Renders a small section label.
  Widget buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }

  /// Consistent dark-themed [InputDecoration] used across all fields.
  InputDecoration inputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
      filled: true,
      fillColor: AppColors.surfaceBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  /// Animated color-swatch picker.
  ///
  /// [selectedIndex] — index of the currently selected color.
  /// [onSelect] — called with the new index when a swatch is tapped.
  Widget buildColorPicker({
    required int selectedIndex,
    required void Function(int index) onSelect,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(AppConstants.quickButtonPalette.length, (index) {
        final color = AppConstants.quickButtonPalette[index];
        final isSelected = selectedIndex == index;
        return GestureDetector(
          onTap: () => onSelect(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 3,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                : null,
          ),
        );
      }),
    );
  }

  /// Cancel + submit action row at the bottom of every dialog.
  ///
  /// [onCancel] defaults to `Navigator.of(context).pop()`.
  Widget buildDialogButtons({
    VoidCallback? onCancel,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed:
                onCancel ?? () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: isLoading ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.textOnPrimary),
                  )
                : Text(
                    submitLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
          ),
        ),
      ],
    );
  }

  // ── Shared scaffold ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalInset = AppBreakpoints.dialogHorizontalInset(screenWidth);

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding:
          EdgeInsets.symmetric(horizontal: horizontalInset, vertical: 40),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildDialogTitle(),
              const SizedBox(height: 20),
              ...buildFormFields(),
              const SizedBox(height: 20),
              buildDialogButtons(),
            ],
          ),
        ),
      ),
    );
  }
}
