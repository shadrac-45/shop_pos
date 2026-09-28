/// ============================================
/// Product Import Parser — ShopPOS
/// ============================================
/// Resilient reader for spreadsheet files used by
/// product catalog import.
///
/// Why this exists instead of calling `Excel.decodeBytes`
/// directly: `excel` 4.0.6 throws
///     "custom numFmtId starts at 164 but found a value of 42"
/// whenever `xl/styles.xml` declares a `<numFmt>` below the
/// custom-format floor of 164. IDs 0-163 are reserved built-ins
/// per OOXML, but Excel and Google Sheets still emit them (42 is
/// the accounting format), so perfectly ordinary shopping lists
/// fail to parse. The package has no newer release, so the file is
/// repaired here instead.
///
/// Pipeline, cheapest first:
///   1. `Excel.decodeBytes(bytes)` — works for most files.
///   2. Repair `xl/styles.xml` (drop reserved `<numFmt>` entries),
///      re-zip, retry. Format codes are only used for display, so
///      discarding them costs nothing but cosmetic cell formatting.
///   3. CSV decoding, for files that are really delimited text but
///      carry an `.xls`/`.xlsx` extension.
/// Anything still unparsed yields a friendly, actionable message.
/// Never surfaces a raw exception string to the user.
///
/// Everything heavy runs inside a [compute] isolate so a large
/// spreadsheet cannot freeze the UI.
/// ============================================
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

/// How a product import file was ultimately read.
enum ImportDecodeStrategy {
  /// Straight `Excel.decodeBytes`, no repair needed.
  excelDirect,

  /// `styles.xml` had reserved `<numFmt>` entries; they were stripped
  /// and the file re-zipped before decoding.
  excelAfterStyleRepair,

  /// The bytes were not a real xlsx container and were read as
  /// delimited text instead.
  csvFallback,
}

/// One problem found while reading a specific row.
class ImportRowIssue {
  /// 1-based row number as it appears in the source file, so the user
  /// can find it in their spreadsheet.
  final int rowNumber;

  final String reason;

  const ImportRowIssue({required this.rowNumber, required this.reason});
}

/// A product row that survived parsing, plus where it came from.
class ParsedProductRow {
  final String name;
  final double price;
  final int quantity;
  final String category;
  final String? barcode;
  final String? sku;
  final double? costPrice;
  final int rowNumber;

  const ParsedProductRow({
    required this.name,
    required this.price,
    required this.quantity,
    required this.category,
    required this.rowNumber,
    this.barcode,
    this.sku,
    this.costPrice,
  });
}

/// Typed outcome of a parse attempt. Callers get either usable rows
/// or a user-facing message, never a thrown exception.
class ProductImportParseResult {
  final List<ParsedProductRow> rows;
  final List<ImportRowIssue> issues;
  final String? userMessage;
  final ImportDecodeStrategy? strategy;

  const ProductImportParseResult({
    this.rows = const [],
    this.issues = const [],
    this.userMessage,
    this.strategy,
  });

  bool get isSuccess => userMessage == null && rows.isNotEmpty;

  int get validCount => rows.length;

  int get skippedCount => issues.length;
}

/// Header aliases accepted by [ProductImportParser]. Keys are
/// normalised (`lowercase`, whitespace and punctuation removed), so
/// "Selling Price", "selling_price" and "SELLINGPRICE" all collapse
/// to `sellingprice` and match the same entry.
class _HeaderAliases {
  static const name = <String>{
    'name',
    'product',
    'productname',
    'item',
    'itemname',
    'title',
    'descriptionofitem',
  };

  static const price = <String>{
    'price',
    'sellingprice',
    'unitprice',
    'saleprice',
    'retailprice',
    'amount',
    'rate',
  };

  static const cost = <String>{'cost', 'costprice', 'buyingprice', 'purchaseprice'};

  static const stock = <String>{
    'stock',
    'quantity',
    'qty',
    'count',
    'units',
    'stocklevel',
    'onhand',
  };

  static const barcode = <String>{'barcode', 'barcodeno', 'ean', 'gtin'};

  static const sku = <String>{'sku', 'code', 'itemcode', 'productcode', 'ref'};

  static const category = <String>{
    'category',
    'cat',
    'dept',
    'department',
    'type',
    'group',
  };
}

/// Parses CSV / XLSX / XLS bytes into [ParsedProductRow]s.
abstract class ProductImportParser {
  ProductImportParser._();

  /// Minimum preview rows shown to the user before committing.
  static const int previewRowLimit = 5;

  /// Entry point for the UI. Dispatches to a background isolate and
  /// returns a typed result. Never throws.
  static Future<ProductImportParseResult> parseFile(
    Uint8List bytes, {
    String fileName = '',
  }) async {
    if (bytes.isEmpty) {
      return const ProductImportParseResult(
        userMessage: 'That file is empty. Please choose a file with data in it.',
      );
    }

    try {
      return await compute(_parseInIsolate, _ParseRequest(bytes, fileName));
    } catch (e) {
      return ProductImportParseResult(
        userMessage: _friendlyMessage(e, fileName: fileName),
      );
    }
  }

  /// Synchronous variant used by tests and by the paste tab, which
  /// already has a decoded string in hand.
  static ProductImportParseResult parseCsvText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const ProductImportParseResult(
        userMessage: 'No data to import yet — paste some CSV or pick a file first.',
      );
    }
    return _rowsFromTable(_tableFromDelimitedText(trimmed));
  }

  /// Synchronous spreadsheet parse that runs the same three-stage
  /// pipeline as [parseFile] on the calling isolate.
  ///
  /// Intended for tests and for the sample-data seeder. UI code should
  /// await [parseFile] so a large workbook cannot block a frame.
  static ProductImportParseResult parseBytesSync(Uint8List bytes) {
    if (bytes.isEmpty) {
      return const ProductImportParseResult(
        userMessage: 'That file is empty. Please choose a file with data in it.',
      );
    }
    try {
      return _parseInIsolate(_ParseRequest(bytes, ''));
    } catch (e) {
      return ProductImportParseResult(userMessage: _friendlyMessage(e, fileName: ''));
    }
  }

  /// Isolate entry point. Must be a top-level function.
  static ProductImportParseResult _parseInIsolate(_ParseRequest request) {
    final bytes = request.bytes;

    // A real xlsx always starts with the ZIP local-file-header magic
    // "PK". Anything else is treated as delimited text, which avoids a
    // confusing failure for files that were renamed.
    final looksLikeZip = bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;

    if (!looksLikeZip) {
      try {
        final result = parseCsvText(_decodeText(bytes));
        if (result.isSuccess) {
          return _withStrategy(result, ImportDecodeStrategy.csvFallback);
        }
        // A non-zip file that yields nothing usable is almost certainly
        // not a spreadsheet at all (a PDF, an image, or a corrupt file
        // mislabelled .xls). Steer the user to CSV rather than reporting
        // a generic "no rows found".
        return ProductImportParseResult(
          userMessage: _friendlyMessage(null, fileName: request.fileName),
        );
      } catch (_) {
        return ProductImportParseResult(
          userMessage: _friendlyMessage(null, fileName: request.fileName),
        );
      }
    }

    // Path 1: try the untouched file first.
    try {
      final rows = _rowsFromExcel(Excel.decodeBytes(bytes));
      return _withStrategy(rows, ImportDecodeStrategy.excelDirect);
    } catch (firstError) {
      final isNumFmtError = _isNumFmtError(firstError);
      if (!isNumFmtError) {
        // A different failure. Repairing styles.xml will not help, so
        // fall through to the delimited-text attempt below.
        final csvAttempt = _tryCsvFallback(bytes, request.fileName);
        return csvAttempt;
      }

      // Path 2: strip reserved <numFmt> entries, then retry.
      try {
        final repaired = _repairStylesAndRezip(bytes);
        final rows = _rowsFromExcel(Excel.decodeBytes(repaired));
        return _withStrategy(rows, ImportDecodeStrategy.excelAfterStyleRepair);
      } catch (repairError) {
        return ProductImportParseResult(
          userMessage: _friendlyMessage(repairError, fileName: request.fileName),
        );
      }
    }
  }

  /// Re-encodes a zip archive with any reserved `<numFmt>` removed.
  ///
  /// Cell format codes control display only, so dropping them is safe:
  /// the underlying numeric values in `sheet1.xml` are untouched.
  static Uint8List _repairStylesAndRezip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    final styles = archive.files
        .where((f) => f.name.toLowerCase() == 'xl/styles.xml')
        .toList();

    if (styles.isEmpty) {
      throw const FormatException('Workbook has no styles part to repair.');
    }

    for (final file in styles) {
      final raw = file.content;
      if (raw == null) continue;
      final xml = utf8.decode(raw);
      final repaired = stripReservedNumFmts(xml);
      // ArchiveFile.content is final in archive 3.x, so the repaired part
      // is written as a replacement member. addFile() swaps out any
      // existing entry with the same path.
      final bytes = utf8.encode(repaired);
      archive.addFile(ArchiveFile(file.name, bytes.length, bytes));
    }

    final encoded = ZipEncoder().encode(archive) ?? const <int>[];
    return Uint8List.fromList(encoded);
  }

  /// Removes every `<numFmt .../>` element whose numFmtId is below 164.
  ///
  /// Deliberately implemented with a regex rather than the `xml` package:
  /// we only ever delete self-closing attribute bags, so there is no
  /// entity expansion or namespace resolution to worry about, and this
  /// keeps the fix working inside a plain isolate without extra setup.
  static String stripReservedNumFmts(String xml) {
    return xml.replaceAllMapped(
      RegExp(r'<numFmt\b[^>]*?/>'),
      (match) {
        final tag = match.group(0)!;
        final idMatch = RegExp(r'numFmtId\s*=\s*"(\d+)"').firstMatch(tag);
        if (idMatch == null) return tag;
        final id = int.tryParse(idMatch.group(1)!);
        if (id == null || id < 164) return '';
        return tag;
      },
    );
  }

  /// Detects the `excel` package's reserved-numFmt failure specifically.
  static bool _isNumFmtError(Object? error) {
    final text = error.toString();
    return text.contains('numFmtId') && text.contains('164');
  }

  /// Extracts rows from a decoded workbook.
  static ProductImportParseResult _rowsFromExcel(Excel excel) {
    if (excel.tables.isEmpty) {
      return const ProductImportParseResult(
        userMessage: 'That workbook has no sheets.',
      );
    }

    final sheet = excel.tables.values.firstWhere(
      (s) => s.rows.isNotEmpty,
      orElse: () => excel.tables.values.first,
    );

    if (sheet.rows.isEmpty) {
      return const ProductImportParseResult(
        userMessage: 'That sheet is empty.',
      );
    }

    final table = sheet.rows.indexed
        .map((entry) => _SourceRow(
              entry.$2.map((cell) => _cellToString(cell?.value)).toList(),
              // +1 because sheet rows are 0-indexed but humans count from 1.
              entry.$1 + 1,
            ))
        .toList();

    return _rowsFromTable(table);
  }

  /// Attempts to read zip bytes as plain delimited text.
  static ProductImportParseResult _tryCsvFallback(
    Uint8List bytes,
    String fileName,
  ) {
    try {
      final result = _rowsFromTable(_tableFromDelimitedText(_decodeText(bytes)));
      if (result.isSuccess) {
        return _withStrategy(result, ImportDecodeStrategy.csvFallback);
      }
    } catch (_) {}
    return ProductImportParseResult(
      userMessage: _friendlyMessage(null, fileName: fileName),
    );
  }

  /// Maps a raw string table onto [ParsedProductRow]s using header
  /// detection, then validates and coerces each row.
  static ProductImportParseResult _rowsFromTable(List<_SourceRow> table) {
    final nonEmpty =
        table.where((r) => r.cells.any((c) => c.trim().isNotEmpty)).toList();

    if (nonEmpty.isEmpty) {
      return const ProductImportParseResult(
        userMessage: 'No data rows were found in that file.',
      );
    }

    final header = nonEmpty.first.cells;
    final columns = _matchHeaders(header);
    // A header is only assumed when at least one column was *recognised*.
    // Positional fallbacks are applied afterwards, otherwise a file with
    // no header row would have its first data row silently eaten.
    final hasHeader = columns.matched;

    final rows = <ParsedProductRow>[];
    final issues = <ImportRowIssue>[];

    // Map each logical field onto a column index, filling gaps from the
    // conventional order only when we are reading below a header.
    final nameIdx = hasHeader ? (columns.name >= 0 ? columns.name : 0) : 0;
    final priceIdx =
        hasHeader ? (columns.price >= 0 ? columns.price : (header.length > 1 ? 1 : -1)) : (header.length > 1 ? 1 : -1);
    final stockIdx =
        hasHeader ? (columns.stock >= 0 ? columns.stock : (header.length > 2 ? 2 : -1)) : (header.length > 2 ? 2 : -1);
    final categoryIdx = hasHeader
        ? (columns.category >= 0 ? columns.category : (header.length > 3 ? 3 : -1))
        : (header.length > 3 ? 3 : -1);

    for (var i = hasHeader ? 1 : 0; i < nonEmpty.length; i++) {
      final source = nonEmpty[i];
      final row = source.cells;

      final name = _cellAt(row, nameIdx);
      final rawPrice = _cellAt(row, priceIdx);
      final rawStock = _cellAt(row, stockIdx);
      final category = _cellAt(row, categoryIdx);
      final barcode = _cellAt(row, columns.barcode);
      final sku = _cellAt(row, columns.sku);
      final rawCost = _cellAt(row, columns.cost);

      if (name.isEmpty) {
        issues.add(ImportRowIssue(
          rowNumber: source.line,
          reason: 'Missing a product name',
        ));
        continue;
      }

      final price = parseNumeric(rawPrice);
      if (price == null || price < 0) {
        issues.add(ImportRowIssue(
          rowNumber: source.line,
          reason: rawPrice.isEmpty
              ? 'Missing a price for "$name"'
              : 'Could not read the price "${rawPrice.trim()}" for "$name"',
        ));
        continue;
      }

      final stock = parseNumeric(rawStock)?.round() ?? 0;
      final cost = rawCost.isEmpty ? null : parseNumeric(rawCost);

      rows.add(ParsedProductRow(
        name: name,
        price: price,
        quantity: stock < 0 ? 0 : stock,
        category: category.isEmpty ? 'General' : category,
        barcode: barcode.isEmpty ? null : barcode,
        sku: sku.isEmpty ? null : sku,
        costPrice: (cost != null && cost >= 0) ? cost : null,
        rowNumber: source.line,
      ));
    }

    if (rows.isEmpty) {
      return ProductImportParseResult(
        issues: issues,
        userMessage: issues.isEmpty
            ? 'No product rows were found in that file.'
            : 'None of the ${issues.length} rows could be read. '
                'Check that there is a name and a price column.',
      );
    }

    return ProductImportParseResult(rows: rows, issues: issues);
  }

  /// Resolves which columns each field maps to by header name.
  /// Returns indices of -1 where no header matched.
  static _ColumnMap _matchHeaders(List<String> header) {
    var name = -1;
    var price = -1;
    var cost = -1;
    var stock = -1;
    var barcode = -1;
    var sku = -1;
    var category = -1;

    for (var i = 0; i < header.length; i++) {
      final key = _normaliseHeader(header[i]);
      if (key.isEmpty) continue;

      // "cost" is tested before "price" so a "costprice" column is not
      // claimed as the selling price.
      if (name == -1 && _HeaderAliases.name.contains(key)) {
        name = i;
      } else if (cost == -1 && _HeaderAliases.cost.contains(key)) {
        cost = i;
      } else if (price == -1 && _HeaderAliases.price.contains(key)) {
        price = i;
      } else if (stock == -1 && _HeaderAliases.stock.contains(key)) {
        stock = i;
      } else if (barcode == -1 && _HeaderAliases.barcode.contains(key)) {
        barcode = i;
      } else if (sku == -1 && _HeaderAliases.sku.contains(key)) {
        sku = i;
      } else if (category == -1 && _HeaderAliases.category.contains(key)) {
        category = i;
      }
    }

    return _ColumnMap(
      name: name,
      price: price,
      cost: cost,
      stock: stock,
      barcode: barcode,
      sku: sku,
      category: category,
      matched: name >= 0 || price >= 0,
    );
  }

  /// Lowercase and drop whitespace plus punctuation so
  /// "Selling Price (GH₵)" and "selling_price" normalise alike.
  static String _normaliseHeader(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String _cellAt(List<String> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  /// Parses a money or quantity cell that may arrive as `int`,
  /// `double`, or a decorated `String` such as `"GH₵ 1,200.50"`.
  ///
  /// Handles thousands separators, currency symbols and whitespace.
  /// Parenthesised values are read as negative, matching the
  /// accounting convention Excel writes for credits.
  @visibleForTesting
  static double? parseNumeric(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    var negative = false;
    if (text.startsWith('(') && text.endsWith(')')) {
      negative = true;
      text = text.substring(1, text.length - 1);
    }

    // Keep only digits and a single decimal separator, which drops
    // currency symbols (GH₵, $, €), spaces and thousands separators.
    final buffer = StringBuffer();
    var seenDot = false;
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      // 0-9
      if (code >= 0x30 && code <= 0x39) {
        buffer.writeCharCode(code);
      } else if (code == 0x2E /* . */ && !seenDot) {
        seenDot = true;
        buffer.write('.');
      } else if (code == 0x2D /* - */) {
        negative = true;
      }
    }

    final cleaned = buffer.toString();
    if (cleaned.isEmpty || cleaned == '.') return null;

    final value = double.tryParse(cleaned);
    if (value == null) return null;
    return negative ? -value : value;
  }

  /// Flattens an Excel cell into display text.
  static String _cellToString(CellValue? value) {
    if (value == null) return '';
    if (value is TextCellValue) return value.value.text ?? '';
    if (value is DoubleCellValue) {
      final d = value.value;
      return d == d.truncateToDouble() ? d.toStringAsFixed(0) : d.toString();
    }
    if (value is IntCellValue) return value.value.toString();
    if (value is DateCellValue) return value.asDateTimeLocal().toIso8601String();
    if (value is DateTimeCellValue) return value.asDateTimeLocal().toIso8601String();
    if (value is TimeCellValue) return value.toString();
    if (value is BoolCellValue) return value.value.toString();
    return value.toString();
  }

  /// Decodes bytes as text, tolerating a UTF-8 BOM and falling back to
  /// Latin-1 when the content is not valid UTF-8.
  static String _decodeText(Uint8List bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  /// Splits delimited text into rows, carrying the 1-based line number
  /// each row came from so issues can point at the real file position
  /// even after blank lines are filtered out.
  static List<_SourceRow> _tableFromDelimitedText(String text) {
    final firstLine = text.split(RegExp(r'\r?\n')).firstWhere(
          (l) => l.trim().isNotEmpty,
          orElse: () => ',',
        );

    var delimiter = ',';
    if (firstLine.contains('\t')) {
      delimiter = '\t';
    } else if (firstLine.contains(';') && !firstLine.contains(',')) {
      delimiter = ';';
    }

    final rows = <_SourceRow>[];
    var current = <String>[];
    var line = 1;
    var rowStartLine = 1;
    final field = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == delimiter && !inQuotes) {
        current.add(field.toString().trim());
        field.clear();
      } else if ((ch == '\n' || ch == '\r') && !inQuotes) {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        current.add(field.toString().trim());
        field.clear();
        rows.add(_SourceRow(current, rowStartLine));
        current = <String>[];
        line++;
        rowStartLine = line;
      } else {
        field.write(ch);
      }
    }

    current.add(field.toString().trim());
    if (current.any((c) => c.isNotEmpty)) {
      rows.add(_SourceRow(current, rowStartLine));
    }

    return rows;
  }

  static ProductImportParseResult _withStrategy(
    ProductImportParseResult result,
    ImportDecodeStrategy strategy,
  ) {
    return ProductImportParseResult(
      rows: result.rows,
      issues: result.issues,
      userMessage: result.userMessage,
      strategy: strategy,
    );
  }

  /// Builds a message a shop owner can act on. The underlying
  /// exception text is deliberately never shown to the user.
  static String _friendlyMessage(Object? error, {required String fileName}) {
    if (_isNumFmtError(error)) {
      return 'This spreadsheet uses an Excel formatting style we could not repair. '
          'Please save it as CSV and try again, or paste the data into the '
          '"Paste CSV Data" tab.';
    }
    return 'We could not read ${fileName.isEmpty ? 'that file' : '"$fileName"'}. '
        'Please save it as CSV and try again, or paste the data into the '
        '"Paste CSV Data" tab.';
  }
}

/// Column indices resolved from a header row. A field that no header
/// matched keeps an index of -1.
class _ColumnMap {
  final int name;
  final int price;
  final int cost;
  final int stock;
  final int barcode;
  final int sku;
  final int category;

  /// True when at least one header was recognised, which is what tells us
  /// the first row is a header rather than data.
  final bool matched;

  const _ColumnMap({
    required this.name,
    required this.price,
    required this.cost,
    required this.stock,
    required this.barcode,
    required this.sku,
    required this.category,
    required this.matched,
  });
}

/// One row of source data plus the line it came from, so that skipping
/// blank lines never shifts the row numbers reported to the user.
class _SourceRow {
  final List<String> cells;
  final int line;

  const _SourceRow(this.cells, this.line);
}

/// Payload handed to the parse isolate. Must be sendable across the
/// isolate boundary, so it holds only primitives and a byte buffer.
class _ParseRequest {
  final Uint8List bytes;
  final String fileName;

  const _ParseRequest(this.bytes, this.fileName);
}
