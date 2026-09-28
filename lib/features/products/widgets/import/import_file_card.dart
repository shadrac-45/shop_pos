/// ============================================
/// Import File Card — ShopPOS
/// ============================================
/// The upload surface for the Pick File tab. Renders three shapes from one
/// widget so the card never jumps between states:
///   • empty   — cloud icon, prompt, supported types, Browse button
///   • loading — file name, size, linear progress, "Reading file..."
///   • preview — compact: green check, name, size, "Choose another file"
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';

/// Card radius used across the import flow. The design calls for 16px.
const double kImportCardRadius = 16.0;

/// Below this width the compact file card stacks its button onto a second
/// line. 360dp is the narrowest phone we support.
const double _compactBreakpoint = 330.0;

/// Shared by every card in this flow so they read as one system.
const double kImportCardPadding = AppSpacing.lg;

BoxDecoration importCardDecoration({
  required Color border,
  Color? fill,
  double borderWidth = 1.5,
}) {
  return BoxDecoration(
    color: fill,
    borderRadius: BorderRadius.circular(kImportCardRadius),
    border: Border.all(color: border, width: borderWidth),
  );
}

/// Human readable byte count, e.g. "12.4 KB".
String formatImportFileSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class ImportFileCard extends StatelessWidget {
  final String? fileName;
  final int? fileSizeBytes;
  final bool isLoading;

  /// True once rows are parsed and this collapses to the compact form.
  final bool isCompact;

  final bool isError;
  final VoidCallback? onBrowse;
  final VoidCallback? onChooseAnother;

  const ImportFileCard({
    super.key,
    required this.fileName,
    required this.fileSizeBytes,
    required this.isLoading,
    required this.isCompact,
    required this.isError,
    this.onBrowse,
    this.onChooseAnother,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (isCompact) {
      return _buildCompact(context, theme, cs);
    }
    return _buildPrompt(context, theme, cs);
  }

  /// Parsed: a single quiet line confirming what will be imported, with a
  /// way back to the picker.
  ///
  /// At 360dp the file name and a full "Choose another file" label do not
  /// fit side by side, so below [compactBreakpoint] the button drops to
  /// its own right-aligned line instead of overflowing.
  Widget _buildCompact(BuildContext context, ThemeData theme, ColorScheme cs) {
    final size = formatImportFileSize(fileSizeBytes);
    final name = fileName ?? 'Pasted CSV data';

    final icon = Semantics(
      label: 'File ready: $name',
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: const Icon(Icons.check_circle_rounded,
            color: AppColors.success, size: 22),
      ),
    );

    final details = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (size.isNotEmpty)
            Text(
              size,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );

    final chooseAnother = Semantics(
      button: true,
      label: 'Choose another file',
      child: TextButton(
        onPressed: onChooseAnother,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(0, AppTouch.minTargetSize),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        ),
        child: const Text('Choose another file'),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: importCardDecoration(
        border: AppColors.primary.withValues(alpha: 0.45),
        fill: cs.surface,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (onChooseAnother == null) {
            return Row(children: [icon, const SizedBox(width: AppSpacing.md), details]);
          }
          if (constraints.maxWidth < _compactBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: AppSpacing.md),
                    details,
                  ],
                ),
                Align(alignment: Alignment.centerRight, child: chooseAnother),
              ],
            );
          }
          return Row(
            children: [
              icon,
              const SizedBox(width: AppSpacing.md),
              details,
              const SizedBox(width: AppSpacing.sm),
              chooseAnother,
            ],
          );
        },
      ),
    );
  }

  /// Empty or loading: the drop-zone style prompt.
  Widget _buildPrompt(BuildContext context, ThemeData theme, ColorScheme cs) {
    final borderColor =
        isError ? cs.error : (isLoading ? AppColors.primary : cs.outlineVariant);
    final hasFile = fileName != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(kImportCardPadding),
      decoration: importCardDecoration(
        border: borderColor,
        fill: cs.surface,
        borderWidth: 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isLoading) ...[
            Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Reading file...',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Linear, determinate-looking progress. We cannot report real
            // bytes for an isolate parse, so this is an honest indeterminate
            // bar rather than a fake percentage.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const LinearProgressIndicator(minHeight: 5),
            ),
            if (hasFile) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                fileName!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (fileSizeBytes != null)
                Text(
                  formatImportFileSize(fileSizeBytes),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ] else ...[
            Semantics(
              label: 'Select a CSV or Excel file. Supported types: '
                  '.csv, .xlsx, .xls',
              child: Column(
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 48,
                    color: isError ? cs.error : AppColors.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Select a CSV or Excel file',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isError ? cs.error : cs.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Supported: .csv, .xlsx, .xls',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: kImportCardPadding),
            Semantics(
              button: true,
              label: 'Browse Files',
              child: SizedBox(
                height: AppTouch.buttonHeight,
                child: FilledButton.icon(
                  onPressed: onBrowse,
                  icon: const Icon(Icons.folder_open_rounded, size: 20),
                  label: const Text('Browse Files'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
