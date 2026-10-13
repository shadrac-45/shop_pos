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
import 'package:shop_pos/core/theme/app_theme.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';

/// Upper-case grey label above a group of settings or cards.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
      child: Semantics(
        header: true,
        child: Text(text.toUpperCase(), style: AppText.overline),
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
      AppConstants.paymentMomoManual => Icons.send_to_mobile_rounded,
      AppConstants.paymentCard => Icons.credit_card_rounded,
      AppConstants.paymentQr => Icons.qr_code_2_rounded,
      AppConstants.paymentSplit => Icons.call_split_rounded,
      _ => Icons.receipt_rounded,
    };

/// Payment methods are told apart by icon and label, not by hue: a
/// payment method is not a status, so it stays neutral.
Color paymentColor(String method) => AppColors.textSecondary;

/// Small coloured pill, e.g. a payment method or sale status.
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const StatusPill(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    // Mid-tone status colours are too light as text on their own 12% tint;
    // a darker shade of the same hue keeps it above 4.5:1.
    final ink = Color.lerp(color, Colors.black, 0.3)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: ink),
            const SizedBox(width: 4),
          ],
          // Shrinks (with "…") instead of overflowing when space is tight.
          Flexible(
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
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
  final result = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: destructive ? AppTone.danger.tint : AppTone.success.tint,
          shape: BoxShape.circle,
        ),
        child: Icon(
          destructive ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
          color: destructive ? AppColors.danger : AppColors.primaryDark,
          size: 28,
        ),
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: destructive ? AppButtons.danger() : null,
                child: Text(confirmLabel),
              ),
            ),
          ],
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
