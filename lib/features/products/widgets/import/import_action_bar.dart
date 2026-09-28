/// ============================================
/// Import Action Bar — ShopPOS
/// ============================================
/// Sticky bottom bar. Always visible above the system navigation bar, so
/// the primary action never scrolls out of reach and never collides with
/// the system inset. The Accept button is disabled and greyed when there
/// is nothing valid to save, rather than disappearing, so the bar does not
/// jump between states.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';

class ImportActionBar extends StatelessWidget {
  final int validCount;
  final int issueCount;

  /// False while the Isar transaction runs, which greys the primary action.
  final bool enabled;

  final VoidCallback? onAccept;
  final VoidCallback? onCancel;
  final VoidCallback? onDownloadIssues;

  const ImportActionBar({
    super.key,
    required this.validCount,
    required this.issueCount,
    required this.enabled,
    this.onAccept,
    this.onCancel,
    this.onDownloadIssues,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canAccept = enabled && validCount > 0;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      // top: false — the AppBar already owns the status bar inset; this
      // only lifts the bar above the gesture/navigation bar.
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                enabled: canAccept,
                label: canAccept
                    ? 'Accept $validCount valid items'
                    : 'No valid items to import',
                child: SizedBox(
                  width: double.infinity,
                  height: AppTouch.buttonHeight,
                  child: FilledButton.icon(
                    onPressed: canAccept ? onAccept : null,
                    icon: const Icon(Icons.check_circle_outline_rounded,
                        size: 20),
                    label: Text(
                      'Accept $validCount valid item'
                      '${validCount == 1 ? '' : 's'}',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textOnPrimary,
                      // Explicitly greyed rather than relying on the
                      // disabled theme colour, so it reads as disabled on
                      // both light and dark surfaces.
                      disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
                      disabledForegroundColor:
                          cs.onSurface.withValues(alpha: 0.45),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              if (issueCount > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$issueCount row${issueCount == 1 ? '' : 's'} with issues '
                  'will be skipped',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.warningDarkText,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.xxs),
              // Wrap, not Row: two 48dp-minimum text buttons overflow a
              // 360dp bar side by side, and wrapping keeps them centred
              // instead of clipping.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: [
                  if (issueCount > 0 && onDownloadIssues != null)
                    TextButton(
                      onPressed: onDownloadIssues,
                      style: TextButton.styleFrom(
                        foregroundColor: cs.onSurfaceVariant,
                        minimumSize: const Size(0, AppTouch.minTargetSize),
                        padding:
                            const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      ),
                      child: const Text('Download issues'),
                    ),
                  TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                      minimumSize: const Size(0, AppTouch.minTargetSize),
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    ),
                    child: const Text('Cancel'),
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
