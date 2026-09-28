/// ============================================
/// CSV Import Dialog — ShopPOS
/// ============================================
/// Full-screen, touch-first import surface for the
/// product catalog. Two tabs: pick a CSV/Excel file,
/// or paste CSV text directly.
///
/// Layout note: the preview table lives *inside* each tab's
/// scroll view rather than as a second Expanded sibling of
/// the TabBarView. Two Expanded widgets in one Column is an
/// unsatisfiable constraint and was what pushed the AppBar
/// title into the Import button and close button.
///
/// Import is restricted to the OWNER role; staff accounts
/// see a read-only explanation instead of the tabs.
/// ============================================
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/products/providers/product_provider.dart';
import 'package:shop_pos/features/products/services/csv_import_service.dart';

class CsvImportDialog extends ConsumerStatefulWidget {
  const CsvImportDialog({super.key});

  @override
  ConsumerState<CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends ConsumerState<CsvImportDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _textController = TextEditingController();

  String? _pickedFileName;
  int? _pickedFileSize;
  CsvParseResult? _parseResult;
  bool _isImporting = false;
  bool _isParsing = false;
  String? _fileError;

  bool get _isOwner =>
      ref.watch(currentUserProvider)?.role == AppConstants.roleOwner;

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

  void _onTextChanged(String text) {
    if (text.trim().isEmpty) {
      setState(() => _parseResult = null);
      return;
    }
    // Debounced so a large paste does not re-parse on every keystroke.
    _debounceParse(text);
  }

  Timer? _parseDebounce;

  void _debounceParse(String text) {
    _parseDebounce?.cancel();
    _parseDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final result = CsvImportService.parseCsv(text);
      setState(() => _parseResult = result);
    });
  }

  int? _getFileSize(PlatformFile file) {
    if (file.path != null) {
      try {
        return File(file.path!).lengthSync();
      } catch (_) {}
    }
    return null;
  }

  Uint8List? _getFileBytes(PlatformFile file) {
    if (file.path != null) {
      try {
        return File(file.path!).readAsBytesSync();
      } catch (_) {}
    }
    return null;
  }

  void _resetPickedFile() {
    _parseDebounce?.cancel();
    setState(() {
      _pickedFileName = null;
      _pickedFileSize = null;
      _parseResult = null;
      _fileError = null;
      _textController.clear();
    });
  }

  Future<void> _pickImportFile() async {
    if (!_isOwner) {
      context.showErrorSnackbar('Only the owner can import products.');
      return;
    }

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ImportFileExtensions.pickerAllowed,
      );

      if (files.isEmpty) return;

      final file = files.single;
      final ext = (file.name.split('.').last).toLowerCase();

      if (ImportFileExtensions.unsupported.contains(ext)) {
        setState(() {
          _fileError = kUnsupportedImportFormatMessage;
          _pickedFileName = file.name;
          _pickedFileSize = _getFileSize(file);
          _parseResult = null;
        });
        if (mounted) {
          context.showErrorSnackbar(kUnsupportedImportFormatMessage);
        }
        return;
      }

      if (!ImportFileExtensions.allProductImportable.contains(ext)) {
        setState(() => _fileError =
            '"${file.name}" is not a CSV or Excel file we can read.');
        return;
      }

      final bytes = _getFileBytes(file);
      if (bytes == null || bytes.isEmpty) {
        setState(() => _fileError = 'The selected file is empty.');
        return;
      }

      setState(() {
        _isParsing = true;
        _fileError = null;
        _pickedFileName = file.name;
        _pickedFileSize = _getFileSize(file);
      });

      // Runs on a background isolate, so a large workbook will not
      // freeze the dialog. Handles Excel decode, the numFmtId repair
      // fallback, and CSV text as needed.
      final result = await CsvImportService.parseExcelBytesAsync(
        bytes,
        fileName: file.name,
      );

      if (!mounted) return;

      setState(() {
        _isParsing = false;
        _parseResult = result;
        if (result.generalError != null) _fileError = result.generalError;
      });

      if (result.hasValidRows && mounted) {
        context.showSuccessSnackbar(
          'Loaded "${file.name}" — ${result.validCount} product(s) ready to import',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isParsing = false;
        _fileError = 'We could not open that file. Please try another one.';
      });
      debugPrint('[CsvImportDialog] file pick failed: $e');
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.trim().isEmpty) {
        if (mounted) context.showErrorSnackbar('Clipboard is empty.');
        return;
      }
      _textController.text = text;
      _debounceParse(text);
      if (mounted) context.showSuccessSnackbar('Pasted from clipboard');
    } catch (e) {
      if (mounted) context.showErrorSnackbar('Could not read the clipboard.');
      debugPrint('[CsvImportDialog] clipboard failed: $e');
    }
  }

  void _loadSampleTemplate() {
    const sample = '''name,price,quantity,category,sku,barcode
"Apple iPhone 15 Pro",999.99,10,Electronics,APL-15PRO-001,1234567890123
"Samsung Galaxy S24",849.99,15,Electronics,SAM-S24-002,1234567890124
"MacBook Air M3",1299.00,5,Computers,MBP-AIR-M3-003,1234567890125
"Sony WH-1000XM5",349.99,20,Audio,SNY-WH1000XM5-004,1234567890126
"Nike Air Max 270",129.99,30,Footwear,NKE-AM270-005,1234567890127''';
    _textController.text = sample;
    _debounceParse(sample);
  }

  Future<void> _commitImport() async {
    if (_parseResult == null || !_parseResult!.hasValidRows) {
      context.showErrorSnackbar('Nothing to import yet.');
      return;
    }
    if (!_isOwner) {
      context.showErrorSnackbar('Only the owner can import products.');
      return;
    }

    setState(() => _isImporting = true);

    try {
      final isar = ref.read(isarProvider);
      final summary = await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: _parseResult!.rows,
      );

      if (!mounted) return;

      // Make the Products screen reflect the new catalog immediately.
      ref.invalidate(productServiceProvider);

      if (summary.total == 0) {
        context.showErrorSnackbar('Nothing was imported — all rows failed.');
      } else {
        context.showSuccessSnackbar(summary.headline);
      }

      await _showSummarySheet(summary);
      _resetPickedFile();
    } catch (e) {
      if (mounted) {
        context.showErrorSnackbar('The import could not be completed.');
      }
      debugPrint('[CsvImportDialog] import failed: $e');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _showSummarySheet(ImportSummary summary) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Import complete',
                style: Theme.of(ctx).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  _summaryTile('Imported', summary.imported, AppColors.success),
                  const SizedBox(width: AppSpacing.sm),
                  _summaryTile('Updated', summary.updated, AppColors.info),
                  const SizedBox(width: AppSpacing.sm),
                  _summaryTile('Skipped', summary.skipped, AppColors.warning),
                ],
              ),
              if (summary.skipReasons.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Skipped rows',
                  style: Theme.of(ctx).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                ...summary.skipReasons.take(10).map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $r',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryTile(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  // ── File tab ────────────────────────────────────

  Widget _buildFileTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _buildDropZone(),
        if (_fileError != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _buildErrorBanner(),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isParsing ? null : _pickImportFile,
                icon: const Icon(Icons.folder_open),
                label: const Text('Browse Files'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
              ),
            ),
            if (_pickedFileName != null) ...[
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetPickedFile,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  ),
                ),
              ),
            ],
          ],
        ),
        // Preview lives inside the tab, not as a sibling Expanded.
        ..._buildPreviewSection(),
      ],
    );
  }

  Widget _buildDropZone() {
    final cs = context.colorScheme;
    final hasFile = _pickedFileName != null;

    return GestureDetector(
      onTap: _isParsing ? null : _pickImportFile,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: _fileError != null
                ? cs.error
                : hasFile
                    ? cs.primary
                    : cs.outline,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            if (_isParsing)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              )
            else
              Icon(
                hasFile ? Icons.check_circle_outline : Icons.cloud_upload_outlined,
                size: 48,
                color: _fileError != null
                    ? cs.error
                    : hasFile
                        ? cs.primary
                        : cs.onSurfaceVariant,
              ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _isParsing
                  ? 'Reading file…'
                  : _pickedFileName ?? 'Select a CSV or Excel file',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _fileError != null
                        ? cs.error
                        : hasFile
                            ? cs.primary
                            : cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Supports .csv, .xlsx and .xls',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            if (_pickedFileSize != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Size: ${_formatFileSize(_pickedFileSize!)}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    final cs = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: cs.error, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fileError!,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.onErrorContainer),
                ),
                const SizedBox(height: AppSpacing.sm),
                // Always offer a route forward instead of a dead end.
                OutlinedButton.icon(
                  onPressed: () {
                    _tabController.animateTo(1);
                    context.showInfoSnackbar(
                      'Open the "Paste CSV Data" tab and paste your rows.',
                    );
                  },
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('Paste CSV instead'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Paste tab ───────────────────────────────────

  Widget _buildPasteTab() {
    final cs = context.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          'Paste CSV Data',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Paste rows straight from a spreadsheet. The first row should '
          'contain headers such as name, price, stock, category.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _textController,
          maxLines: 10,
          minLines: 6,
          decoration: InputDecoration(
            hintText: 'name,price,stock,category\n'
                '"Milo 400g",GH₵ 32.00,45,Beverages',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
          ),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontFamily: 'monospace'),
          onChanged: _onTextChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pasteFromClipboard,
                icon: const Icon(Icons.paste),
                label: const Text('Clipboard'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loadSampleTemplate,
                icon: const Icon(Icons.description_outlined),
                label: const Text('Sample'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
              ),
            ),
          ],
        ),
        ..._buildPreviewSection(),
      ],
    );
  }

  // ── Preview + validation ────────────────────────

  List<Widget> _buildPreviewSection() {
    final result = _parseResult;
    if (result == null) return const [];

    return [
      const SizedBox(height: AppSpacing.lg),
      _buildValidationStrip(),
      const SizedBox(height: AppSpacing.md),
      _buildPreviewTable(),
    ];
  }

  Widget _buildValidationStrip() {
    final result = _parseResult!;
    final hasErrors = result.invalidCount > 0 || result.generalError != null;
    final cs = context.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: hasErrors
            ? cs.errorContainer
            : AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasErrors ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                color: hasErrors ? cs.error : AppColors.success,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  hasErrors ? 'Some rows need attention' : 'All rows look good',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: hasErrors ? cs.onErrorContainer : AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _buildStatChip('Ready', result.validCount.toString(), AppColors.success),
              const SizedBox(width: AppSpacing.sm),
              _buildStatChip('Skipped', result.invalidCount.toString(), cs.error),
            ],
          ),
          // Surface the specific reasons, with row numbers, rather than
          // just a count.
          if (result.invalidCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            ...result.rows
                .where((r) => !r.isValid)
                .take(6)
                .map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '• Row ${r.rowNumber}: ${r.errorMessage}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onErrorContainer,
                          ),
                    ),
                  ),
                ),
            if (result.invalidCount > 6)
              Text(
                '…and ${result.invalidCount - 6} more',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onErrorContainer),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTable() {
    final result = _parseResult!;
    if (!result.hasValidRows) {
      return Text(
        'No importable rows yet.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: context.colorScheme.onSurfaceVariant),
      );
    }

    final validRows = result.rows.where((r) => r.isValid).toList();
    // First 5 rows only, per spec — enough to confirm the mapping is
    // right without flooding a phone screen.
    final preview = validRows.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview — ${validRows.length} product(s) ready',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor:
                  WidgetStateProperty.all(context.colorScheme.surfaceContainerHighest),
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Price')),
                DataColumn(label: Text('Qty')),
                DataColumn(label: Text('Category')),
              ],
              rows: preview
                  .map(
                    (r) => DataRow(cells: [
                      DataCell(
                        Text(r.name, overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
                      DataCell(Text(CurrencyHelpers.format(r.price))),
                      DataCell(Text(r.quantity.toString())),
                      DataCell(
                        Text(
                          r.category.isEmpty ? '—' : r.category,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ]),
                  )
                  .toList(),
            ),
          ),
        ),
        if (validRows.length > 5) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Showing the first ${preview.length} of ${validRows.length} products.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ── Non-owner view ──────────────────────────────

  Widget _buildRestrictedView() {
    final cs = context.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Owner access required',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Only the shop owner can import products. Ask the owner to '
              'sign in and do it from Settings.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // SafeArea keeps the tabs and the preview clear of the system status
    // bar and any gesture inset on notched devices.
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Import Products'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            if (_isOwner)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: TextButton.icon(
                  onPressed: (_isImporting || _isParsing) ? null : _commitImport,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_isImporting ? 'Importing…' : 'Import'),
                ),
              ),
          ],
        ),
        body: !_isOwner
            ? _buildRestrictedView()
            : SafeArea(
                top: false,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Pick File'),
                        Tab(text: 'Paste CSV'),
                      ],
                      labelStyle: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    // Single Expanded only — the preview is rendered
                    // inside each tab's own scroll view.
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildFileTab(),
                          _buildPasteTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
