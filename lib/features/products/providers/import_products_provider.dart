/// ============================================
/// Import Products State — ShopPOS
/// ============================================
/// Single source of truth for the Import Products screen. The screen is a
/// switch on [ImportStatus] and nothing else; every widget reads from this
/// state and calls the controller, so there is no local widget state to
/// keep in sync with the parse/import pipeline.
///
/// All parsing, validation and Isar work stays in [CsvImportService] and
/// [ProductImportParser]. This class only orchestrates them and holds the
/// bytes/text needed to re-parse after a column mapping is confirmed.
/// ============================================
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/features/products/services/csv_import_service.dart';
import 'package:shop_pos/features/products/services/product_import_parser.dart';

/// The distinct screens of the import flow.
enum ImportStatus {
  /// Nothing picked or pasted yet.
  empty,

  /// Reading/parsing a file. Buttons are disabled.
  loading,

  /// Parsed rows are on screen with the Accept bar.
  preview,

  /// The Isar transaction is running. Blocks navigation.
  importing,

  /// The transaction finished. The success dialog has not been dismissed.
  success,

  /// A friendly failure, with a Retry affordance.
  error,
}

/// Which slice of the parsed rows the preview list is showing.
enum ImportRowFilter { all, valid, issues }

enum ImportNoticeKind { info, success, error }

/// A one-shot message for the screen to surface as a snackbar. The screen
/// consumes it and calls [ImportProductsController.clearNotice] so the same
/// notice is not shown twice on rebuild.
@immutable
class ImportNotice {
  final String message;
  final ImportNoticeKind kind;

  const ImportNotice(this.message, this.kind);
}

/// Raised when the parser could not recognise the columns, so the owner
/// must confirm a mapping. The screen listens for this, shows the mapping
/// dialog, then calls [ImportProductsController.applyMapping].
@immutable
class ImportMappingRequest {
  final List<String> headerLabels;
  final List<List<String>> sampleRows;

  const ImportMappingRequest({
    required this.headerLabels,
    required this.sampleRows,
  });
}

@immutable
class ImportProductsState {
  final ImportStatus status;
  final ImportRowFilter filter;

  /// Name and size of the picked file, shown by the file card.
  final String? fileName;
  final int? fileSizeBytes;

  /// Retained so a confirmed column mapping can be re-applied without
  /// asking the owner to pick the file again.
  final Uint8List? fileBytes;

  /// Retained for the same reason on the Paste tab.
  final String? pastedText;

  final CsvParseResult? result;
  final ImportSummary? summary;

  /// Always a friendly, human-written message. Never an exception string.
  final String? errorMessage;

  final ImportNotice? notice;
  final ImportMappingRequest? mappingRequest;

  const ImportProductsState({
    this.status = ImportStatus.empty,
    this.filter = ImportRowFilter.all,
    this.fileName,
    this.fileSizeBytes,
    this.fileBytes,
    this.pastedText,
    this.result,
    this.summary,
    this.errorMessage,
    this.notice,
    this.mappingRequest,
  });

  bool get isBusy =>
      status == ImportStatus.loading || status == ImportStatus.importing;

  int get totalCount => result?.rows.length ?? 0;

  int get validCount => result?.validCount ?? 0;

  int get issueCount => result?.invalidCount ?? 0;

  /// Rows the Accept button will hand to the writer. Invalid rows are
  /// never passed, so they can never reach the database.
  List<CsvProductRow> get validRows => result?.validRows ?? const [];

  List<CsvProductRow> get issueRows => result?.invalidRows ?? const [];

  List<CsvProductRow> get visibleRows {
    switch (filter) {
      case ImportRowFilter.all:
        return result?.rows ?? const [];
      case ImportRowFilter.valid:
        return validRows;
      case ImportRowFilter.issues:
        return issueRows;
    }
  }

  /// Accept is only offered when at least one row would actually be saved.
  bool get canAccept => validCount > 0 && status != ImportStatus.importing;

  /// Rows the owner is told about but which will not be written: the ones
  /// rejected during parsing plus any that failed inside the transaction.
  int get skippedCount => issueCount + (summary?.skipped ?? 0);

  int get savedCount =>
      (summary?.imported ?? 0) + (summary?.updated ?? 0);

  ImportProductsState copyWith({
    ImportStatus? status,
    ImportRowFilter? filter,
    String? fileName,
    int? fileSizeBytes,
    Uint8List? fileBytes,
    String? pastedText,
    CsvParseResult? result,
    ImportSummary? summary,
    String? errorMessage,
    ImportNotice? notice,
    ImportMappingRequest? mappingRequest,
    bool clearFile = false,
    bool clearPastedText = false,
    bool clearError = false,
    bool clearNotice = false,
    bool clearMapping = false,
    bool clearSummary = false,
  }) {
    return ImportProductsState(
      status: status ?? this.status,
      filter: filter ?? this.filter,
      fileName: clearFile ? null : (fileName ?? this.fileName),
      fileSizeBytes: clearFile ? null : (fileSizeBytes ?? this.fileSizeBytes),
      fileBytes: clearFile ? null : (fileBytes ?? this.fileBytes),
      pastedText: clearPastedText ? null : (pastedText ?? this.pastedText),
      result: result ?? this.result,
      summary: clearSummary ? null : (summary ?? this.summary),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      notice: clearNotice ? null : (notice ?? this.notice),
      mappingRequest:
          clearMapping ? null : (mappingRequest ?? this.mappingRequest),
    );
  }
}

final importProductsProvider =
    NotifierProvider<ImportProductsController, ImportProductsState>(
  ImportProductsController.new,
);

/// Orchestrates the import flow. Every failure is converted to a written,
/// friendly sentence before it reaches the UI; the raw exception is only
/// ever sent to [debugPrint] so it can never be shown to a shop owner.
class ImportProductsController extends Notifier<ImportProductsState> {
  @override
  ImportProductsState build() => const ImportProductsState();

  /// Bytes of a picked file, or null when the platform only handed back a
  /// name (which happens on some web/managed configurations).
  static Uint8List? _readBytes(String? path) {
    if (path == null) return null;
    try {
      return File(path).readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  /// Prefers the on-disk length and falls back to the byte count we read.
  static int _sizeOf(String? path, int fallback) {
    if (path != null) {
      try {
        return File(path).lengthSync();
      } catch (_) {}
    }
    return fallback;
  }

  void _notice(String message, ImportNoticeKind kind) {
    state = state.copyWith(notice: ImportNotice(message, kind));
  }

  void clearNotice() => state = state.copyWith(clearNotice: true);

  // ── Input ───────────────────────────────────────

  void setFilter(ImportRowFilter filter) => state = state.copyWith(filter: filter);

  /// Clears the picked file and returns to the empty state, keeping the
  /// Paste tab's text so switching inputs does not lose work.
  void chooseAnotherFile() {
    state = state.copyWith(
      status: ImportStatus.empty,
      clearFile: true,
      clearPastedText: true,
      clearError: true,
      clearSummary: true,
    );
  }

  void dismissError() {
    state = state.copyWith(
      status: ImportStatus.empty,
      clearError: true,
    );
  }

  /// Opens the platform picker and parses whatever comes back.
  Future<void> browseForFile() async {
    if (state.isBusy) return;

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ImportFileExtensions.pickerAllowed,
      );
      if (files.isEmpty) return;

      final file = files.single;
      final ext = (file.name.split('.').last).toLowerCase();

      if (ImportFileExtensions.unsupported.contains(ext)) {
        state = state.copyWith(
          status: ImportStatus.error,
          fileName: file.name,
          errorMessage: kUnsupportedImportFormatMessage,
        );
        return;
      }

      if (!ImportFileExtensions.allProductImportable.contains(ext)) {
        state = state.copyWith(
          status: ImportStatus.error,
          fileName: file.name,
          errorMessage:
              '"${file.name}" is not a CSV or Excel file we can read. '
              'Save it as .csv or .xlsx and try again.',
        );
        return;
      }

      final bytes = _readBytes(file.path);
      if (bytes == null || bytes.isEmpty) {
        state = state.copyWith(
          status: ImportStatus.error,
          fileName: file.name,
          errorMessage: 'That file looks empty. Check the file and try again.',
        );
        return;
      }

      state = state.copyWith(
        status: ImportStatus.loading,
        fileName: file.name,
        fileSizeBytes: _sizeOf(file.path, bytes.length),
        fileBytes: bytes,
        clearError: true,
        clearSummary: true,
      );

      // Runs on a background isolate: a large workbook cannot freeze the UI.
      final result = await CsvImportService.parseExcelBytesAsync(
        bytes,
        fileName: file.name,
      );
      _applyResult(result);
    } catch (e) {
      debugPrint('[ImportProducts] file pick failed: $e');
      state = state.copyWith(
        status: ImportStatus.error,
        errorMessage:
            'We could not open that file. Check it opens correctly in Excel, '
            'or paste the rows on the "Paste CSV Data" tab instead.',
      );
    }
  }

  /// Parses text pasted on the second tab into the same preview state.
  Future<void> parsePastedText(String text) async {
    if (state.isBusy) return;

    if (text.trim().isEmpty) {
      state = state.copyWith(
        status: ImportStatus.error,
        errorMessage:
            'Paste your CSV data first. The first row should be the headers, '
            'for example: name, category, price, cost, stock, barcode',
      );
      return;
    }

    state = state.copyWith(
      status: ImportStatus.loading,
      pastedText: text,
      fileName: null,
      fileSizeBytes: text.length,
      fileBytes: null,
      clearError: true,
      clearSummary: true,
    );

    try {
      // Yield once so the loading card paints before the parse blocks.
      await Future<void>.delayed(Duration.zero);
      _applyResult(CsvImportService.parseCsv(text));
    } catch (e) {
      debugPrint('[ImportProducts] paste parse failed: $e');
      state = state.copyWith(
        status: ImportStatus.error,
        errorMessage:
            'We could not read that pasted data. Check the rows are separated '
            'by commas and the header is on the first line.',
      );
    }
  }

  /// Re-runs the last attempt without making the owner pick the file again.
  Future<void> retry() async {
    final bytes = state.fileBytes;
    final name = state.fileName;
    if (bytes != null && name != null) {
      state = state.copyWith(status: ImportStatus.loading, clearError: true);
      try {
        final result =
            await CsvImportService.parseExcelBytesAsync(bytes, fileName: name);
        _applyResult(result);
      } catch (e) {
        debugPrint('[ImportProducts] retry failed: $e');
        state = state.copyWith(
          status: ImportStatus.error,
          errorMessage:
              'We still could not read that file. Try saving it as a plain '
              '.csv, or paste the rows on the "Paste CSV Data" tab.',
        );
      }
      return;
    }

    final text = state.pastedText;
    if (text != null) return parsePastedText(text);

    state = state.copyWith(status: ImportStatus.empty, clearError: true);
  }

  // ── Column mapping ──────────────────────────────

  void _applyResult(CsvParseResult result) {
    if (result.needsMapping) {
      state = state.copyWith(
        status: ImportStatus.empty,
        result: result,
        clearError: true,
        mappingRequest: ImportMappingRequest(
          headerLabels: result.headerLabels,
          sampleRows: result.sampleRows,
        ),
      );
      return;
    }

    if (result.rows.isEmpty) {
      state = state.copyWith(
        status: ImportStatus.error,
        result: result,
        errorMessage: result.generalError ??
            'No product rows were found in that file. Check the first row is '
                'the header line and there is data underneath it.',
      );
      return;
    }

    state = state.copyWith(
      status: ImportStatus.preview,
      filter: ImportRowFilter.all,
      result: result,
      clearError: true,
      clearMapping: true,
    );

    if (result.validCount > 0) {
      _notice(
        '${result.validCount} of ${result.rows.length} rows ready to import',
        ImportNoticeKind.success,
      );
    } else {
      _notice('No rows are valid. Fix the issues and import again.',
          ImportNoticeKind.info);
    }
  }

  /// Re-parses with the mapping the owner confirmed.
  Future<void> applyMapping(ColumnMapping mapping) async {
    final bytes = state.fileBytes;
    final text = state.pastedText;
    final name = state.fileName;

    state = state.copyWith(
      status: ImportStatus.loading,
      clearMapping: true,
    );

    try {
      final result = bytes != null
          ? await CsvImportService.parseBytesWithMappingAsync(
              bytes,
              mapping,
              fileName: name ?? '',
            )
          : CsvImportService.parseCsvWithMapping(
              text ?? '',
              mapping,
            );
      _applyResult(result);
    } catch (e) {
      debugPrint('[ImportProducts] mapping reparse failed: $e');
      state = state.copyWith(
        status: ImportStatus.error,
        errorMessage:
            'We could not read the file with that column mapping. Please try '
            'mapping the columns again.',
      );
    }
  }

  void cancelMapping() {
    state = state.copyWith(
      status: ImportStatus.empty,
      result: null,
      clearMapping: true,
    );
  }

  // ── Commit ──────────────────────────────────────

  /// Writes the valid rows. The caller is expected to have confirmed with
  /// the owner first; this method is the second half of that action.
  Future<void> accept() async {
    final rows = state.validRows;
    if (rows.isEmpty || state.status == ImportStatus.importing) return;

    state = state.copyWith(status: ImportStatus.importing, clearError: true);

    try {
      final isar = ref.read(isarProvider);
      final summary = await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: rows,
      );
      state = state.copyWith(
        status: ImportStatus.success,
        summary: summary,
      );
    } catch (e) {
      debugPrint('[ImportProducts] import failed: $e');
      // Nothing was committed: the writer uses a single transaction.
      state = state.copyWith(
        status: ImportStatus.error,
        errorMessage:
            'The import could not be completed, so nothing was saved. Please '
            'check you have storage space and try again.',
      );
    }
  }

  /// Closes the flow. The screen pops and refreshes the Products list.
  void finishSuccess() {
    state = state.copyWith(status: ImportStatus.empty, clearSummary: true);
  }
}
