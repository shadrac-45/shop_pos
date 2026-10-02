/// ============================================
/// UI Helpers — ShopPOS
/// ============================================
/// Small shared pieces used by the sales,
/// inventory, expense and settings screens.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';

/// Upper-case grey label above a group of settings or cards.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// Text field for money amounts in the store currency.
class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;

  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.autofocus = false,
    this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint ?? '0.00',
        prefixText: '${CurrencyHelpers.symbol} ',
      ),
    );
  }
}

/// Parses a money field, treating blank as 0.
double parseMoney(String text) => double.tryParse(text.trim()) ?? 0;

IconData paymentIcon(String method) => switch (method) {
      AppConstants.paymentCash => Icons.payments_rounded,
      AppConstants.paymentMomo ||
      AppConstants.paymentMomoPaystack =>
        Icons.phone_android_rounded,
      AppConstants.paymentCard => Icons.credit_card_rounded,
      AppConstants.paymentQr => Icons.qr_code_2_rounded,
      AppConstants.paymentSplit => Icons.call_split_rounded,
      _ => Icons.receipt_rounded,
    };

Color paymentColor(String method) => switch (method) {
      AppConstants.paymentCash => AppColors.cashColor,
      AppConstants.paymentMomo ||
      AppConstants.paymentMomoPaystack =>
        AppColors.momoColor,
      AppConstants.paymentCard => AppColors.info,
      AppConstants.paymentQr => const Color(0xFF7C3AED),
      _ => AppColors.textSecondary,
    };

/// Small coloured pill, e.g. a payment method or sale status.
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const StatusPill(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppSpacing.borderSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            text.toUpperCase(),
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Yes/no confirmation. Returns true only if confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive
              ? ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

/// Readable message for an exception thrown by a service.
String errorMessage(Object error) {
  final text = error.toString();
  for (final prefix in ['Exception: ', 'Bad state: ', 'Invalid argument(s): ']) {
    if (text.startsWith(prefix)) return text.substring(prefix.length);
  }
  return text;
}
