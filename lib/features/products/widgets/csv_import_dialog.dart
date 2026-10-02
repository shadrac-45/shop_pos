/// ============================================
/// Import Products Screen — ShopPOS
/// ============================================
/// Full-screen import surface for the product catalog.
///
/// This file is presentation only. All parsing, validation and Isar work
/// stays in `CsvImportService` / `ProductImportParser`; the screen is a
/// switch on [ImportStatus] and every widget below it is stateless. All
/// state lives in `importProductsProvider`.
///
/// Layout: the Scaffold AppBar owns the status bar inset. The sticky
/// action bar is a sibling at the bottom of the body — never an AppBar
/// action — and wraps itself in SafeArea so it always clears the system
/// navigation bar. Exactly one [Expanded] holds the scrolling content.
///
/// Import is restricted to the OWNER role.
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/products/providers/import_products_provider.dart';
import 'package:shop_pos/features/products/providers/product_provider.dart';
import 'package:shop_pos/features/products/services/invalid_rows_export.dart';
import 'package:shop_pos/features/products/widgets/column_mapping_dialog.dart';
import 'package:shop_pos/features/products/widgets/import/import_action_bar.dart';
import 'package:shop_pos/features/products/widgets/import/import_file_card.dart';
import 'package:shop_pos/features/products/widgets/import/import_filter_bar.dart';
import 'package:shop_pos/features/products/widgets/import/import_row_tile.dart';
import 'package:shop_pos/features/products/widgets/import/import_summary_chips.dart';

class CsvImportDialog extends ConsumerStatefulWidget {
  const CsvImportDialog({super.key});

  @override
  ConsumerState<CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends ConsumerState<CsvImportDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _textController = TextEditingController();

  /// Owners and managers may import (Permission.manageProducts).
  bool get _isOwner =>
      Permissions.can(ref.watch(currentUserProvider), Permission.manageProducts);

  ImportProductsController get _controller =>
      ref.read(importProductsProvider.notifier);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  // ── Side effects driven by state changes ─────────
  //
  // The controller has no BuildContext, so dialogs and snackbars are
  // triggered from here by watching the state.

  void _listen(ImportProductsState state) {
    final notice = state.notice;
    if (notice != null) {
      switch (notice.kind) {
        case ImportNoticeKind.success:
          context.showSuccessSnackbar(notice.message);
        case ImportNoticeKind.error:
          context.showErrorSnackbar(notice.message);
        case ImportNoticeKind.info:
          context.showInfoSnackbar(notice.message);
      }
      _controller.clearNotice();
      return;
    }

    final mapping = state.mappingRequest;
    if (mapping != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _runMappingDialog(mapping);
      });
      return;
    }

    if (state.status == ImportStatus.success) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _showSuccessDialog(state);
      });
    }
  }

  Future<void> _runMappingDialog(ImportMappingRequest request) async {
    final mapping = await ColumnMappingDialog.show(
      context,
      headerLabels: request.headerLabels,
      sampleRows: request.sampleRows,
    );
    if (!mounted) return;

    if (mapping == null) {
      _controller.cancelMapping();
      return;
    }
    await _controller.applyMapping(mapping);
  }

  Future<void> _showSuccessDialog(ImportProductsState state) async {
    final summary = state.summary;
    if (summary == null) return;

    final saved = state.savedCount;
    final skipped = state.skippedCount;
    final total = state.totalCount;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded,
            color: AppColors.success, size: 48),
        title: const Text('Import complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$saved imported (${summary.imported} new, ${summary.updated} '
              'updated). $skipped skipped.',
              style: Theme.of(ctx).textTheme.bodyLarge,
            ),
            if (summary.skipped > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'A few rows could not be saved. Open Import again to retry '
                'them.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: AppColors.warningDarkText,
                    ),
              ),
            ],
            if (skipped == 0 && total > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Every row in the file was imported.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: AppColors.successDarkText,
                    ),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    _controller.finishSuccess();
    // Refresh the Products list, then return to it.
    ref.invalidate(productServiceProvider);
    Navigator.of(context).pop();
  }

  Future<void> _confirmAndAccept(ImportProductsState state) async {
    final valid = state.validCount;
    final issues = state.issueCount;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Import $valid valid item${valid == 1 ? '' : 's'}?'),
        content: Text(
          issues == 0
              ? 'All $valid rows will be added to your catalog.'
              : '$issues row${issues == 1 ? '' : 's'} with issues will be '
                  'skipped.',
          style: Theme.of(ctx).textTheme.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _controller.accept();
  }

  Future<void> _downloadIssues(ImportProductsState state) async {
    final issues = state.issueRows;
    if (issues.isEmpty) return;
    try {
      final path = await InvalidRowsExport.write(
        issues,
        sourceName: state.fileName ?? 'import',
      );
      if (!mounted) return;
      if (path == null) {
        context.showInfoSnackbar('There are no issues to download.');
      } else {
        context.showSuccessSnackbar('Saved skipped rows to $path');
      }
    } catch (e) {
      debugPrint('[ImportProducts] export failed: $e');
      if (mounted) context.showErrorSnackbar('We could not write that file.');
    }
  }

  // ── Build ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importProductsProvider);
    ref.listen<ImportProductsState>(
      importProductsProvider,
      (previous, next) {
        if (previous?.status != next.status ||
            previous?.notice != next.notice ||
            previous?.mappingRequest != next.mappingRequest) {
          _listen(next);
        }
      },
    );

    return Dialog.fullscreen(
      child: PopScope(
        // Block back navigation mid-write so the owner cannot leave a
        // transaction half-applied.
        canPop: state.status != ImportStatus.importing,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: state.status == ImportStatus.importing
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
            // The Accept action lives at the bottom, so the AppBar has no
            // actions at all. The title must never share a row with a
            // button, which is what previously pushed it off-screen.
            title: const Text(
              'Import Products',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: SafeArea(
            top: false,
            child: !_isOwner
                ? _buildOwnerGate(context)
                : Column(
                    children: [
                      Expanded(child: _buildStatusBody(context, state)),
                      if (state.status == ImportStatus.preview ||
                          state.status == ImportStatus.importing)
                        ImportActionBar(
                          validCount: state.validCount,
                          issueCount: state.issueCount,
                          enabled: state.status != ImportStatus.importing,
                          onAccept: state.canAccept
                              ? () => _confirmAndAccept(state)
                              : null,
                          onCancel: () => Navigator.of(context).pop(),
                          onDownloadIssues: () => _downloadIssues(state),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// The screen body, chosen purely by status.
  Widget _buildStatusBody(BuildContext context, ImportProductsState state) {
    switch (state.status) {
      case ImportStatus.empty:
      case ImportStatus.loading:
      case ImportStatus.error:
        return _buildInputState(context, state);

      case ImportStatus.preview:
      case ImportStatus.importing:
        return _buildPreview(context, state);

      case ImportStatus.success:
        // The success dialog is modal over the preview, which is still the
        // correct thing to show behind it.
        return _buildPreview(context, state);
    }
  }

  // ── Input states: empty, loading, error ───────────

  Widget _buildInputState(BuildContext context, ImportProductsState state) {
    final showTabs = state.status != ImportStatus.loading;

    return Column(
      children: [
        if (showTabs)
          TabBar(
            controller: _tabController,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'Pick CSV / Excel File'),
              Tab(text: 'Paste CSV Data'),
            ],
          ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildFileTab(context, state),
              _buildPasteTab(context, state),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFileTab(BuildContext context, ImportProductsState state) {
    final isLoading = state.status == ImportStatus.loading;
    final hasText = state.pastedText != null;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        ImportFileCard(
          fileName: hasText ? null : state.fileName,
          fileSizeBytes: hasText ? null : state.fileSizeBytes,
          isLoading: isLoading,
          isCompact: false,
          isError: state.status == ImportStatus.error,
          // Disabled while loading, per the loading spec.
          onBrowse: isLoading ? null : _controller.browseForFile,
        ),
        if (state.status == ImportStatus.error) ...[
          const SizedBox(height: AppSpacing.lg),
          _buildErrorCard(context, state),
        ],
      ],
    );
  }

  Widget _buildPasteTab(BuildContext context, ImportProductsState state) {
    final isLoading = state.status == ImportStatus.loading;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          'Paste CSV Data',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Paste rows straight from a spreadsheet. The first line must be the '
          'header row.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          textField: true,
          label: 'Paste CSV data. Expected header: '
              'name, category, price, cost, stock, barcode',
          child: TextField(
            controller: _textController,
            enabled: !isLoading,
            // 8 lines is the floor the spec asks for, so the expected
            // header plus a few rows are visible without scrolling.
            minLines: 8,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.none,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'name, category, price, cost, stock, barcode\n'
                  'Milo 400g, Beverages, 32.00, 28.00, 45, 5012345678900',
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kImportCardRadius),
              ),
              filled: true,
              fillColor: cs.surface,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          button: true,
          label: 'Parse pasted CSV data',
          child: SizedBox(
            height: AppTouch.buttonHeight,
            child: FilledButton.icon(
              onPressed: isLoading
                  ? null
                  : () => _controller.parsePastedText(_textController.text),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Parse'),
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
        if (state.status == ImportStatus.error) ...[
          const SizedBox(height: AppSpacing.lg),
          _buildErrorCard(context, state),
        ],
      ],
    );
  }

  /// Friendly failure with a Retry and a pointer at the other input.
  Widget _buildErrorCard(BuildContext context, ImportProductsState state) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(kImportCardPadding),
      decoration: importCardDecoration(
        border: cs.error,
        fill: cs.error.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, color: cs.error, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                // errorMessage is always text written in this feature; the
                // raw exception never reaches it.
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    state.errorMessage ?? 'Something went wrong.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.dangerDarkText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Semantics(
                button: true,
                label: 'Retry',
                child: OutlinedButton.icon(
                  onPressed: _controller.retry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size(0, AppTouch.minTargetSize),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Switch to the Paste CSV Data tab',
                child: OutlinedButton.icon(
                  onPressed: () => _tabController.animateTo(1),
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Paste CSV instead'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    side: BorderSide(color: cs.outline),
                    minimumSize: const Size(0, AppTouch.minTargetSize),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Preview ──────────────────────────────────────

  Widget _buildPreview(BuildContext context, ImportProductsState state) {
    final rows = state.visibleRows;
    final isImporting = state.status == ImportStatus.importing;

    return Stack(
      // expand gives the Column a tight, bounded height so its Expanded
      // list can lay out. With the default loose fit the Column is
      // unbounded and the list throws.
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                children: [
                  ImportFileCard(
                    fileName: state.fileName,
                    fileSizeBytes: state.fileSizeBytes,
                    isLoading: false,
                    isCompact: true,
                    isError: false,
                    onChooseAnother: isImporting
                        ? null
                        : _controller.chooseAnotherFile,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ImportSummaryChips(
                    total: state.totalCount,
                    valid: state.validCount,
                    issues: state.issueCount,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ImportFilterBar(
                    selected: state.filter,
                    totalCount: state.totalCount,
                    validCount: state.validCount,
                    issueCount: state.issueCount,
                    enabled: !isImporting,
                    onChanged: _controller.setFilter,
                  ),
                ],
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? _buildEmptyFilter(context, state)
                  : ListView.separated(
                      // Room for the sticky bar, so the last row is never
                      // trapped underneath it.
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xs,
                        AppSpacing.lg,
                        AppSpacing.xxl,
                      ),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (_, index) => ImportRowTile(row: rows[index]),
                    ),
            ),
          ],
        ),
        if (isImporting) _buildImportingOverlay(context, state),
      ],
    );
  }

  Widget _buildEmptyFilter(BuildContext context, ImportProductsState state) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          'No rows in this filter',
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  /// Full-screen modal progress. Sits above everything, including the
  /// action bar, so nothing can be tapped mid-write.
  Widget _buildImportingOverlay(
      BuildContext context, ImportProductsState state) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: AbsorbPointer(
        // Swallows every tap so nothing underneath can be pressed while the
        // transaction runs.
        child: ColoredBox(
          color: Colors.black54,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(AppSpacing.xl),
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: importCardDecoration(
                border: Colors.transparent,
                fill: theme.colorScheme.surface,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppSpacing.lg),
                  Semantics(
                    liveRegion: true,
                    label: 'Importing ${state.validCount} items, please wait',
                    child: Text(
                      'Importing ${state.validCount} item'
                      '${state.validCount == 1 ? '' : 's'}...',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Owner gate ───────────────────────────────────

  Widget _buildOwnerGate(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Owner access required',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Only the shop owner can import products. Ask the owner to sign '
              'in and do it from Settings.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
