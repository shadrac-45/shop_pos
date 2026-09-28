/// ============================================
/// Import Filter Bar — ShopPOS
/// ============================================
/// Segmented control over the preview list: All | Valid | Issues, each
/// carrying its own count. The counts matter more than the labels here —
/// the owner is deciding whether to accept a partial import, and needs to
/// see how many rows they are about to drop.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/products/providers/import_products_provider.dart';

class ImportFilterBar extends StatelessWidget {
  final ImportRowFilter selected;
  final int totalCount;
  final int validCount;
  final int issueCount;
  final ValueChanged<ImportRowFilter> onChanged;
  final bool enabled;

  const ImportFilterBar({
    super.key,
    required this.selected,
    required this.totalCount,
    required this.validCount,
    required this.issueCount,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: AppTouch.buttonHeight,
      child: SegmentedButton<ImportRowFilter>(
        segments: [
          ButtonSegment(
            value: ImportRowFilter.all,
            label: _countLabel(theme, 'All', totalCount),
            tooltip: 'Show all $totalCount rows',
          ),
          ButtonSegment(
            value: ImportRowFilter.valid,
            label: _countLabel(theme, 'Valid', validCount),
            tooltip: 'Show $validCount valid rows',
          ),
          ButtonSegment(
            value: ImportRowFilter.issues,
            label: _countLabel(theme, 'Issues', issueCount),
            tooltip: 'Show $issueCount rows with issues',
          ),
        ],
        selected: {selected},
        showSelectedIcon: false,
        onSelectionChanged: enabled
            ? (selection) => onChanged(selection.first)
            : null,
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(
            theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary.withValues(alpha: 0.14);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStatePropertyAll(theme.colorScheme.onSurface),
          side: WidgetStatePropertyAll(
            BorderSide(
              color: selected == ImportRowFilter.issues
                  ? AppColors.warning.withValues(alpha: 0.5)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _countLabel(ThemeData theme, String label, int count) {
    // Flexible so "Issues 108" cannot overflow the segment on a 360dp
    // phone once the three segments share the width.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text('$label $count'),
    );
  }
}
