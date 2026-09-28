/// ============================================
/// Import Row Tile — ShopPOS
/// ============================================
/// One row in the preview list.
///
/// Valid row : name (bold), category (small grey), price, "Qty n".
/// Issue row : a red left border, the source row number, the raw text the
///             file actually contained, and the reason(s) in small red.
///             The raw text matters — an owner fixing their spreadsheet
///             needs to see what was there, not what we failed to parse.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/products/services/csv_import_service.dart';

class ImportRowTile extends StatelessWidget {
  final CsvProductRow row;

  const ImportRowTile({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasIssue = !row.isValid;
    final reason = row.errorMessage ?? 'This row could not be imported';

    return Semantics(
      label: hasIssue
          ? 'Row ${row.rowNumber}, issue: $reason'
          : '${row.name}, ${CurrencyHelpers.format(row.price)}, '
              'quantity ${row.quantity}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          // The red left border is the fastest signal in the list.
          border: hasIssue
              ? Border(
                  left: BorderSide(color: cs.error, width: 3),
                )
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasIssue)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm, top: 1),
                child: Text(
                  'Row ${row.rowNumber}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(top: 7, right: AppSpacing.sm),
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _displayName,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!hasIssue && row.category.isNotEmpty)
                    Text(
                      row.category,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (hasIssue)
                    Text(
                      reason,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  CurrencyHelpers.format(row.price),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Qty ${row.quantity}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Falls back to the untouched cell text when the name cell was blank,
  /// so an issue row is never a nameless grey box.
  String get _displayName {
    final parsed = row.name.trim();
    if (parsed.isNotEmpty) return parsed;
    final raw = row.rawName.trim();
    if (raw.isNotEmpty) return '"$raw"';
    return '(no name)';
  }
}
