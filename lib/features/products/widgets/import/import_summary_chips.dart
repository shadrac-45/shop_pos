/// ============================================
/// Import Summary Chips — ShopPOS
/// ============================================
/// Three equal chips: Total, Valid, Issues.
///
/// Contrast rule: each chip uses a pale tint of its own colour as the
/// background and a DARKENED version of that same colour as the text. The
/// previous design put green text on a red container, which was close to
/// unreadable. Text on every chip here clears WCAG AA on its own tint:
/// Amber 600 on a 12% amber tint is only ~2.6:1, so the chips use the
/// 800-level status text colours instead.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';

class ImportSummaryChips extends StatelessWidget {
  final int total;
  final int valid;
  final int issues;

  const ImportSummaryChips({
    super.key,
    required this.total,
    required this.valid,
    required this.issues,
  });

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight gives the Row a bounded height so stretch can make
    // all three chips exactly equal height. Without it the chips size to
    // their own text and a taller label would misalign the row.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _chip(
            context,
            label: 'Total',
            value: total,
            color: AppColors.textSecondary,
            textColor: AppColors.textPrimary,
            semantics: '$total rows in total',
          ),
          _chip(
            context,
            label: 'Valid',
            value: valid,
            color: AppColors.success,
            textColor: AppColors.successDarkText,
            semantics: '$valid valid rows, ready to import',
          ),
          _chip(
            context,
            label: 'Issues',
            value: issues,
            color: AppColors.warning,
            textColor: AppColors.warningDarkText,
            semantics: '$issues rows with issues that will be skipped',
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required int value,
    required Color color,
    required Color textColor,
    required String semantics,
  }) {
    final theme = Theme.of(context);

    return Expanded(
      child: Semantics(
        label: semantics,
        excludeSemantics: true,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$value',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
