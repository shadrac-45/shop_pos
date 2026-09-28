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

/// A product row that survived parsing, plus where it came from and
/// everything wrong with it.
///
/// A row is kept in the result even when it is invalid, so the preview
/// can show the owner exactly which rows failed and why. [errors] is empty
/// for a row that is safe to import.
class ParsedProductRow {
  final String name;
  final double price;
  final int quantity;
  final String category;
  final String? barcode;
  final double? costPrice;

  /// 1-based line number in the source file, so the owner can find the
  /// row in their spreadsheet.
  final int rowNumber;

  /// Original cell text, retained so the "download invalid rows" export
  /// can show what the file actually contained.
  final String rawName;
  final String rawPrice;
  final String rawStock;

  /// Every problem found on this row, not just the first.
  final List<String> errors;

  /// Set to false by a later pass when a duplicate barcode is detected
  /// further down the file, which cannot be known while reading the row.
  bool isValid;

  ParsedProductRow({
    required this.name,
    required this.price,
    required this.quantity,
    required this.category,
    required this.rowNumber,
    required this.rawName,
    required this.rawPrice,
    required this.rawStock,
    List<String> errors = const [],
    this.barcode,
    this.costPrice,
  })  : errors = List<String>.from(errors),
        isValid = errors.isEmpty;

  bool get hasErrors => errors.isNotEmpty;

  /// All reasons joined for display, e.g. "Missing name, Price is not a
  /// number".
  String get errorSummary => errors.join(', ');
}

/// Column index assignment chosen by header detection or by the owner in
/// the mapping dialog. A field index of -1 means "not mapped".
class ColumnMapping {
  final int name;
  final int price;
  final int stock;
  final int category;
  final int cost;
  final int barcode;

  /// True when the first row of the table is a header and must be skipped.
  final bool skipHeader;

  /// True when the mapping came from alias matching rather than a guess.
  final bool detected;

  const ColumnMapping({
    required this.name,
    required this.price,
    required this.stock,
    required this.category,
    required this.cost,
    required this.barcode,
    required this.skipHeader,
    required this.detected,
  });

  ColumnMapping copyWith({
    int? name,
    int? price,
    int? stock,
    int? category,
    int? cost,
    int? barcode,
    bool? skipHeader,
  }) {
    return ColumnMapping(
      name: name ?? this.name,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      category: category ?? this.category,
      cost: cost ?? this.cost,
      barcode: barcode ?? this.barcode,
      skipHeader: skipHeader ?? this.skipHeader,
      detected: detected,
    );
  }

  /// True when a column is assigned to more than one field, which would
  /// make the preview lie about the source data.
  bool get hasConflict {
    final used = <int>{
      if (name >= 0) name,
      if (price >= 0) price,
      if (stock >= 0) stock,
      if (category >= 0) category,
      if (cost >= 0) cost,
      if (barcode >= 0) barcode,
    };
    final total = [name, price, stock, category, cost, barcode]
        .where((i) => i >= 0)
        .length;
    return used.length != total;
  }
}

/// One problem found while reading a specific row.
class ImportRowIssue {
  /// 1-based row number as it appears in the source file.
  final int rowNumber;

  final String reason;

  const ImportRowIssue({required this.rowNumber, required this.reason});
}

/// Typed outcome of a parse attempt. Callers get either usable rows
/// or a user-facing message, never a thrown exception.
class ProductImportParseResult {
  /// Every row read, valid and invalid alike.
  final List<ParsedProductRow> rows;

  final String? userMessage;

  final ImportDecodeStrategy? strategy;

  /// True when the header row could not be matched and the owner must
  /// choose the columns before anything can be imported.
  final bool needsMapping;

  /// The file's own column labels, used to populate the mapping dialog.
  final List<String> headerLabels;

  /// A few sample data rows so the owner can recognise their columns.
  final List<List<String>> sampleRows;

  /// The mapping actually used to produce [rows].
  final ColumnMapping? mapping;

  const ProductImportParseResult({
    this.rows = const [],
    this.userMessage,
    this.strategy,
    this.needsMapping = false,
    this.headerLabels = const [],
    this.sampleRows = const [],
    this.mapping,
  });

  bool get isSuccess => userMessage == null && rows.isNotEmpty;

  List<ParsedProductRow> get validRows => rows.where((r) => r.isValid).toList();

  List<ParsedProductRow> get invalidRows =>
      rows.where((r) => !r.isValid).toList();

  /// Retained for callers that only need a count of unimportable rows.
  int get invalidCount => invalidRows.length;

  @Deprecated('Use validRows.length instead. Access to this will be removed.')
  int get validCount => validRows.length;

  int get skippedCount => invalidRows.length;
}

/// Header aliases accepted by [ProductImportParser]. Keys are alias keys
/// from [_aliasKey] (lowercase, punctuation removed, spaces removed), so
/// "Selling Price", "selling_price" and "SELLING PRICE" all collapse to
/// `sellingprice` and match the same entry.
abstract class HeaderAliases {
  static const name = <String>{
    'name',
    'product',
    'productname',
    'item',
    'itemname',
    'description',
    'productdescription',
    'itemdescription',
    'title',
    'goods',
  };

  static const price = <String>{
    'price',
    'sellingprice',
    'sellprice',
    'unitprice',
    'retailprice',
    'amount',
    'rate',
  };

  static const cost = <String>{
    'cost',
    'costprice',
    'buyingprice',
    'purchaseprice',
    'wholesaleprice',
  };

  static const stock = <String>{
    'stock',
    'stocklevel',
    'instock',
    'quantity',
    'qty',
    'count',
    'units',
    'onhand',
    'openingstock',
  };

  static const barcode = <String>{
    'barcode',
    'sku',
    'skucode',
    'code',
    'itemcode',
    'productcode',
  };

  static const category = <String>{
    'category',
    'cat',
    'group',
    'type',
    'department',
    'dept',
    'subcategory',
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
        userMessage:
            'That file is empty. Please choose a file with data in it.',
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

  /// Re-runs the file with a mapping the owner confirmed, so the
  /// mapping dialog can hand its column choices back through the same
  /// isolate path.
  static Future<ProductImportParseResult> parseFileWithMapping(
    Uint8List bytes,
    ColumnMapping mapping, {
    String fileName = '',
  }) async {
    if (bytes.isEmpty) {
      return const ProductImportParseResult(
        userMessage:
            'That file is empty. Please choose a file with data in it.',
      );
    }
    try {
      return await compute(
        _parseWithMappingInIsolate,
        _ParseWithMappingRequest(bytes, fileName, mapping),
      );
    } catch (e) {
      return ProductImportParseResult(
        userMessage: _friendlyMessage(e, fileName: fileName),
      );
    }
  }

  /// Synchronous counterpart of [parseFileWithMapping], for tests.
  static ProductImportParseResult parseCsvTextWithMapping(
    String rawCsv,
    ColumnMapping mapping,
  ) {
    final trimmed = rawCsv.trim();
    if (trimmed.isEmpty) {
      return const ProductImportParseResult(
        userMessage:
            'No data to import yet — paste some CSV or pick a file first.',
      );
    }
    return _rowsFromTable(
      _tableFromDelimitedText(trimmed),
      overrideMapping: mapping,
    );
  }

  /// Isolate entry point for a confirmed mapping.
  static ProductImportParseResult _parseWithMappingInIsolate(
    _ParseWithMappingRequest request,
  ) {
    final bytes = request.bytes;
    final looksLikeZip =
        bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;

    if (!looksLikeZip) {
      try {
        return _rowsFromTable(
          _tableFromDelimitedText(_decodeText(bytes)),
          overrideMapping: request.mapping,
        );
      } catch (_) {
        return ProductImportParseResult(
          userMessage: _friendlyMessage(null, fileName: request.fileName),
        );
      }
    }

    List<_SourceRow> table;
    var strategy = ImportDecodeStrategy.excelDirect;
    try {
      table = _tableFromExcel(Excel.decodeBytes(bytes));
    } catch (firstError) {
      if (!_isNumFmtError(firstError)) {
        return ProductImportParseResult(
          userMessage: _friendlyMessage(firstError, fileName: request.fileName),
        );
      }
      try {
        table = _tableFromExcel(
          Excel.decodeBytes(_repairStylesAndRezip(bytes)),
        );
        strategy = ImportDecodeStrategy.excelAfterStyleRepair;
      } catch (repairError) {
        return ProductImportParseResult(
          userMessage:
              _friendlyMessage(repairError, fileName: request.fileName),
        );
      }
    }

    return _withStrategy(
      _rowsFromTable(table, overrideMapping: request.mapping),
      strategy,
    );
  }

  /// Synchronous variant used by tests and by the paste tab, which
  /// already has a decoded string in hand.
  static ProductImportParseResult parseCsvText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const ProductImportParseResult(
        userMessage:
            'No data to import yet — paste some CSV or pick a file first.',
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
        userMessage:
            'That file is empty. Please choose a file with data in it.',
      );
    }
    try {
      return _parseInIsolate(_ParseRequest(bytes, ''));
    } catch (e) {
      return ProductImportParseResult(
          userMessage: _friendlyMessage(e, fileName: ''));
    }
  }

  /// Isolate entry point. Must be a top-level function.
  static ProductImportParseResult _parseInIsolate(_ParseRequest request) {
    final bytes = request.bytes;

    // A real xlsx always starts with the ZIP local-file-header magic
    // "PK". Anything else is treated as delimited text, which avoids a
    // confusing failure for files that were renamed.
    final looksLikeZip =
        bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;

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
      final table = _tableFromExcel(Excel.decodeBytes(bytes));
      return _withStrategy(
        _rowsFromTable(table),
        ImportDecodeStrategy.excelDirect,
      );
    } catch (firstError) {
      final isNumFmtError = _isNumFmtError(firstError);
      if (!isNumFmtError) {
        // A different failure. Repairing styles.xml will not help, so
        // fall through to the delimited-text attempt below.
        return _tryCsvFallback(bytes, request.fileName);
      }

      // Path 2: strip reserved <numFmt> entries, then retry.
      try {
        final repaired = _repairStylesAndRezip(bytes);
        final table = _tableFromExcel(Excel.decodeBytes(repaired));
        return _withStrategy(
          _rowsFromTable(table),
          ImportDecodeStrategy.excelAfterStyleRepair,
        );
      } catch (repairError) {
        return ProductImportParseResult(
          userMessage:
              _friendlyMessage(repairError, fileName: request.fileName),
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

  /// Extracts rows from a decoded workbook, carrying line numbers.
  static List<_SourceRow> _tableFromExcel(Excel excel) {
    if (excel.tables.isEmpty) {
      throw const FormatException('Workbook has no sheets.');
    }

    final sheet = excel.tables.values.firstWhere(
      (s) => s.rows.isNotEmpty,
      orElse: () => excel.tables.values.first,
    );

    if (sheet.rows.isEmpty) {
      throw const FormatException('Sheet is empty.');
    }

    return sheet.rows.indexed
        .map((entry) => _SourceRow(
              entry.$2.map((cell) => _cellToString(cell?.value)).toList(),
              // +1 because sheet rows are 0-indexed but humans count from 1.
              entry.$1 + 1,
            ))
        .toList();
  }

  /// Attempts to read zip bytes as plain delimited text.
  static ProductImportParseResult _tryCsvFallback(
    Uint8List bytes,
    String fileName,
  ) {
    try {
      final result =
          _rowsFromTable(_tableFromDelimitedText(_decodeText(bytes)));
      if (result.isSuccess || result.needsMapping) {
        return _withStrategy(result, ImportDecodeStrategy.csvFallback);
      }
    } catch (_) {}
    return ProductImportParseResult(
      userMessage: _friendlyMessage(null, fileName: fileName),
    );
  }

  /// Maps a raw string table onto [ParsedProductRow]s.
  ///
  /// [overrideMapping] lets the owner correct the column assignment from
  /// the mapping dialog. When it is null and the header row does not
  /// identify a name column, this returns a [needsMapping] result rather
  /// than guessing — guessing is what caused category text to appear in
  /// the Name column.
  static ProductImportParseResult _rowsFromTable(
    List<_SourceRow> table, {
    ColumnMapping? overrideMapping,
  }) {
    final nonEmpty =
        table.where((r) => r.cells.any((c) => c.trim().isNotEmpty)).toList();

    if (nonEmpty.isEmpty) {
      return const ProductImportParseResult(
        userMessage: 'No data rows were found in that file.',
      );
    }

    final headerRow = nonEmpty.first.cells;
    final headerLabels = _buildHeaderLabels(headerRow);
    final hasHeaderRow = _looksLikeHeader(headerLabels);

    final ColumnMapping mapping;
    if (overrideMapping != null) {
      mapping = overrideMapping;
    } else if (!hasHeaderRow) {
      // No header row at all: the conventional order is the only sane
      // reading, and the owner still gets to confirm it.
      mapping = ColumnMapping(
        name: 0,
        price: headerRow.length > 1 ? 1 : -1,
        stock: headerRow.length > 2 ? 2 : -1,
        category: headerRow.length > 3 ? 3 : -1,
        cost: -1,
        barcode: -1,
        skipHeader: false,
        detected: false,
      );
    } else {
      final detected = _matchHeaders(headerRow);
      if (detected.name < 0) {
        // We know this is a header row, but we cannot tell which column
        // holds the product name. Stop and ask.
        return ProductImportParseResult(
          needsMapping: true,
          headerLabels: headerLabels,
          sampleRows: _sampleRows(nonEmpty, hasHeaderRow: true),
          userMessage: 'We could not tell which column holds the product name. '
              'Please choose the columns to import.',
        );
      }
      mapping = detected;
    }

    final rows = <ParsedProductRow>[];
    final startAt = mapping.skipHeader ? 1 : 0;

    for (var i = startAt; i < nonEmpty.length; i++) {
      final source = nonEmpty[i];
      rows.add(_buildRow(source, mapping));
    }

    // A second pass marks barcodes that collide inside the file, so the
    // owner sees the conflict instead of importing one of the two.
    _flagDuplicateBarcodes(rows);

    final valid = rows.where((r) => r.isValid).toList();

    if (rows.isEmpty) {
      return const ProductImportParseResult(
        userMessage: 'No product rows were found in that file.',
      );
    }

    if (valid.isEmpty) {
      return ProductImportParseResult(
        rows: rows,
        needsMapping: false,
        headerLabels: headerLabels,
        userMessage: 'None of the ${rows.length} rows could be read. '
            'Check the column mapping and the reported issues.',
      );
    }

    return ProductImportParseResult(
      rows: rows,
      needsMapping: false,
      headerLabels: headerLabels,
      mapping: mapping,
    );
  }

  /// Builds and validates a single [ParsedProductRow].
  ///
  /// Every problem found is appended to [row]'s error list rather than
  /// short-circuiting, so the owner sees all issues for a row at once.
  static ParsedProductRow _buildRow(
    _SourceRow source,
    ColumnMapping mapping,
  ) {
    final cells = source.cells;
    final errors = <String>[];

    final name = _cellAt(cells, mapping.name);
    final rawPrice = _cellAt(cells, mapping.price);
    final rawStock = _cellAt(cells, mapping.stock);
    final category = _cellAt(cells, mapping.category);
    final barcode = _cellAt(cells, mapping.barcode);
    final rawCost = _cellAt(cells, mapping.cost);

    if (name.isEmpty) {
      errors.add('Missing name');
    }

    // Price: required, numeric, non-negative.
    double price = 0;
    if (rawPrice.isEmpty) {
      if (name.isNotEmpty) errors.add('Missing price');
    } else {
      final parsed = parseNumeric(rawPrice);
      if (parsed == null) {
        errors.add('Price is not a number: "${rawPrice.trim()}"');
      } else if (parsed < 0) {
        errors.add('Price cannot be negative');
      } else {
        price = parsed;
      }
    }

    // Stock: optional, defaults to 0 when blank.
    int stock = 0;
    if (rawStock.isNotEmpty) {
      final parsed = parseNumeric(rawStock);
      if (parsed == null) {
        errors.add('Quantity is not a number: "${rawStock.trim()}"');
      } else if (parsed < 0) {
        errors.add('Quantity cannot be negative');
      } else {
        stock = parsed.round();
      }
    }

    double? cost;
    if (rawCost.isNotEmpty) {
      final parsed = parseNumeric(rawCost);
      if (parsed == null) {
        errors.add('Cost is not a number: "${rawCost.trim()}"');
      } else if (parsed < 0) {
        errors.add('Cost cannot be negative');
      } else {
        cost = parsed;
      }
    }

    // Guard against the exact failure that prompted this: a mapping that
    // points Name at the Category column would otherwise import happily.
    if (name.isNotEmpty && category.isNotEmpty && _looksLikeCategory(name)) {
      errors.add('This column looks like a category, not a product name');
    }

    return ParsedProductRow(
      name: name,
      price: price,
      quantity: stock,
      category: category,
      barcode: barcode.isEmpty ? null : barcode,
      costPrice: cost,
      rowNumber: source.line,
      rawName: name,
      rawPrice: rawPrice,
      rawStock: rawStock,
      errors: errors,
    );
  }

  /// Adds a "Duplicate barcode" error to the second and later rows that
  /// reuse a barcode, leaving the first occurrence importable.
  static void _flagDuplicateBarcodes(List<ParsedProductRow> rows) {
    final seen = <String, int>{};
    for (final row in rows) {
      final code = row.barcode;
      if (code == null || code.isEmpty) continue;
      final key = code.toLowerCase();
      final first = seen[key];
      if (first != null) {
        row.errors.add('Duplicate barcode "$code" (also on row $first)');
        row.isValid = false;
      } else {
        seen[key] = row.rowNumber;
      }
    }
  }

  /// Heuristic used only to warn, never to reject automatically: a value
  /// that matches a known category word while a category column is also
  /// mapped is very likely the wrong column being read as the name.
  static bool _looksLikeCategory(String value) {
    const categories = {
      'rice & grains',
      'rice and grains',
      'beverages',
      'dairy',
      'canned goods',
      'food cupboard',
      'snacks',
      'household',
      'toiletries',
      'stationery',
      'electronics',
      'clothing',
      'footwear',
      'general',
      'uncategorised',
      'uncategorized',
    };
    return categories.contains(value.trim().toLowerCase());
  }

  /// Human-readable labels for the header row, with the raw text kept so
  /// the mapping dialog can show exactly what the file contained.
  static List<String> _buildHeaderLabels(List<String> headerRow) {
    return List.generate(
      headerRow.length,
      (i) {
        final raw = headerRow[i].trim();
        return raw.isEmpty ? 'Column ${i + 1}' : raw;
      },
      growable: false,
    );
  }

  /// Decides whether the first non-empty row is a header. A row is a
  /// header if it has no cell that parses as a number and at least one
  /// cell is non-empty text.
  static bool _looksLikeHeader(List<String> labels) {
    final cells = labels.where((l) => l.trim().isNotEmpty).toList();
    if (cells.isEmpty) return false;
    // If any cell in the first row is numeric, it is data, not a header.
    final anyNumeric = cells.any((c) => parseNumeric(c) != null);
    return !anyNumeric;
  }

  static List<List<String>> _sampleRows(
    List<_SourceRow> nonEmpty, {
    required bool hasHeaderRow,
  }) {
    final start = hasHeaderRow ? 1 : 0;
    return nonEmpty.skip(start).take(5).map((r) => r.cells).toList();
  }

  /// Resolves which columns each field maps to, by header name.
  ///
  /// Each column is consumed by at most one field, so a single column can
  /// never feed two fields.
  static ColumnMapping _matchHeaders(List<String> headerRow) {
    var name = -1;
    var price = -1;
    var cost = -1;
    var stock = -1;
    var barcode = -1;
    var category = -1;

    // Columns already claimed, so no column feeds two fields.
    final claimed = <int>{};

    for (var i = 0; i < headerRow.length; i++) {
      final key = _aliasKey(headerRow[i]);
      if (key.isEmpty || claimed.contains(i)) continue;

      // Cost is tested before price so a "cost price" column is not
      // claimed as the selling price.
      if (name < 0 && HeaderAliases.name.contains(key)) {
        name = i;
        claimed.add(i);
      } else if (cost < 0 && HeaderAliases.cost.contains(key)) {
        cost = i;
        claimed.add(i);
      } else if (price < 0 && HeaderAliases.price.contains(key)) {
        price = i;
        claimed.add(i);
      } else if (stock < 0 && HeaderAliases.stock.contains(key)) {
        stock = i;
        claimed.add(i);
      } else if (barcode < 0 && HeaderAliases.barcode.contains(key)) {
        barcode = i;
        claimed.add(i);
      } else if (category < 0 && HeaderAliases.category.contains(key)) {
        category = i;
        claimed.add(i);
      }
    }

    return ColumnMapping(
      name: name,
      price: price,
      stock: stock,
      category: category,
      cost: cost,
      barcode: barcode,
      skipHeader: true,
      detected: true,
    );
  }

  /// Header normalisation: strips a UTF-8 BOM, removes surrounding and
  /// doubled quotes, turns underscores into spaces, lowercases, and drops
  /// remaining punctuation so "Selling Price (GH)" and "selling_price"
  /// normalise identically.
  static String normaliseHeader(String value) {
    var v = value.replaceAll('\uFEFF', '').trim();
    // Strip wrapping quotes, then any quotes left inside.
    v = v.replaceAll('"', '').replaceAll("'", '');
    v = v.replaceAll('_', ' ').toLowerCase();
    // Drop punctuation but keep spaces as word separators.
    v = v.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return v.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// The alias → field lookup key for [normaliseHeader]: spaces removed so
  /// "selling price" and "sellingprice" are the same key.
  static String _aliasKey(String value) {
    return normaliseHeader(value).replaceAll(' ', '');
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

    // Strip currency tokens. These are the only letters permitted to
    // appear in a numeric cell — anything else is prose, and a cell like
    // "Cola 350ml" must be rejected rather than silently coerced to 350.
    for (final token in _currencyTokens) {
      text = text.replaceAll(RegExp(token, caseSensitive: false), '');
    }
    text = text.replaceAll(RegExp(r'\s'), '');

    // What remains must be nothing but a number. Rejecting early here is
    // what stops a product name in the price column from being accepted.
    if (!RegExp(r'^[+-]?[\d.,]+$').hasMatch(text)) return null;

    if (text.startsWith('-')) {
      negative = true;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    }

    // Keep only digits and a single decimal separator, which drops the
    // thousands separators.
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
      }
    }

    final cleaned = buffer.toString();
    if (cleaned.isEmpty || cleaned == '.') return null;

    final value = double.tryParse(cleaned);
    if (value == null) return null;
    return negative ? -value : value;
  }

  /// Currency prefixes tolerated in a numeric cell. Deliberately short:
  /// an unrecognised word means the cell is not a number.
  static const _currencyTokens = <String>[
    r'GHS',
    r'GHC',
    r'GH₵',
    r'GH¢',
    r'₵',
    r'₦',
    r'NGN',
    r'₩',
    r'CNY',
    r'RM',
    r'USD',
    r'EUR',
    r'GBP',
    r'ZAR',
    r'KES',
    r'UGX',
    r'TZS',
    r'\$',
    r'€',
    r'£',
    r'₱',
  ];

  /// Flattens an Excel cell into display text.
  static String _cellToString(CellValue? value) {
    if (value == null) return '';
    if (value is TextCellValue) return value.value.text ?? '';
    if (value is DoubleCellValue) {
      final d = value.value;
      return d == d.truncateToDouble() ? d.toStringAsFixed(0) : d.toString();
    }
    if (value is IntCellValue) return value.value.toString();
    if (value is DateCellValue) {
      return value.asDateTimeLocal().toIso8601String();
    }
    if (value is DateTimeCellValue) {
      return value.asDateTimeLocal().toIso8601String();
    }
    if (value is TimeCellValue) return value.toString();
    if (value is BoolCellValue) return value.value.toString();
    return value.toString();
  }

  /// Decodes bytes as text, tolerating a UTF-8 BOM and falling back to
  /// Latin-1 when the content is not valid UTF-8.
  static String _decodeText(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
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
      userMessage: result.userMessage,
      strategy: strategy,
      needsMapping: result.needsMapping,
      headerLabels: result.headerLabels,
      sampleRows: result.sampleRows,
      mapping: result.mapping,
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

/// Payload for a re-parse using a mapping the owner confirmed. Also
/// isolate-safe: only primitives plus the byte buffer.
class _ParseWithMappingRequest {
  final Uint8List bytes;
  final String fileName;
  final ColumnMapping mapping;

  const _ParseWithMappingRequest(this.bytes, this.fileName, this.mapping);
}
