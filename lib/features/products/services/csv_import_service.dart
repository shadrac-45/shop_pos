/// ============================================
/// CSV Import Service — ShopPOS
/// ============================================
/// Thin adapter that keeps the historical
/// `CsvImportService.parseCsv` / `importProductsToIsar`
/// surface used by the seeding paths, while delegating
/// all file reading to [ProductImportParser], which owns
/// the numFmtId repair pipeline.
/// ============================================
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/services/product_import_parser.dart';

/// Supported file extensions for product catalog import.
abstract class ImportFileExtensions {
  static const csv = 'csv';
  static const xlsx = 'xlsx';
  static const xls = 'xls';
  static const doc = 'doc';
  static const docx = 'docx';
  static const pdf = 'pdf';

  static const allProductImportable = [csv, xlsx, xls];
  static const unsupported = [doc, docx, pdf];

  static const pickerAllowed = [csv, xlsx, xls, doc, docx, pdf];
}

/// Friendly message shown when the user picks an unsupported file type.
const String kUnsupportedImportFormatMessage =
    'Word and PDF files aren\'t supported for product import — '
    'please use a CSV or Excel file with columns: name, price, quantity, category.';

class CsvProductRow {
  final String name;
  final double price;
  final int quantity;
  final String category;
  final String? barcode;
  final String? sku;
  final double? costPrice;
  final DateTime? expiryDate;
  final bool isValid;
  final String? errorMessage;
  final int rowNumber;

  const CsvProductRow({
    required this.name,
    required this.price,
    required this.quantity,
    required this.category,
    this.barcode,
    this.sku,
    this.costPrice,
    this.expiryDate,
    required this.isValid,
    this.errorMessage,
    this.rowNumber = 0,
  });
}

class CsvParseResult {
  final List<CsvProductRow> rows;
  final String? generalError;

  const CsvParseResult({
    required this.rows,
    this.generalError,
  });

  int get validCount => rows.where((r) => r.isValid).length;
  int get invalidCount => rows.where((r) => !r.isValid).length;
  bool get hasValidRows => validCount > 0;
}

/// Outcome of committing rows to Isar, so the UI can report
/// "X imported, Y updated, Z skipped" instead of a bare count.
class ImportSummary {
  final int imported;
  final int updated;
  final int skipped;
  final List<String> skipReasons;

  const ImportSummary({
    this.imported = 0,
    this.updated = 0,
    this.skipped = 0,
    this.skipReasons = const [],
  });

  int get total => imported + updated + skipped;

  String get headline =>
      '$imported imported, $updated updated, $skipped skipped';
}

class CsvImportService {
  CsvImportService._();

  static const Uuid _uuid = Uuid();

  /// Standard sample CSV template for shops
  static const String sampleCsv = '''name,price,quantity,category
Milo 400g Tin,32.00,45,Beverages
Peak Evaporated Milk,12.50,90,Dairy
Ideal Milk 390g,11.00,80,Dairy
Voltic Natural Water 750ml,4.50,120,Beverages
Gari 1kg Bag,18.00,35,Food Cupboard
Tasty Tom Tomato Paste 70g,5.00,100,Canned Goods
Geisha Mackerel in Tomato Sauce,14.50,60,Canned Goods
This Way Chocolate Drink,2.50,150,Beverages''';

  /// Parses raw CSV text. Delegates to [ProductImportParser] and adapts
  /// the result to the legacy [CsvParseResult] shape.
  static CsvParseResult parseCsv(String rawCsv) {
    final parsed = ProductImportParser.parseCsvText(rawCsv);

    final rows = <CsvProductRow>[
      for (final row in parsed.rows)
        CsvProductRow(
          name: row.name,
          price: row.price,
          quantity: row.quantity,
          category: row.category,
          barcode: row.barcode,
          sku: row.sku,
          costPrice: row.costPrice,
          isValid: true,
          rowNumber: row.rowNumber,
        ),
    ];

    for (final issue in parsed.issues) {
      rows.add(CsvProductRow(
        name: '[Row ${issue.rowNumber}]',
        price: 0.0,
        quantity: 0,
        category: 'General',
        isValid: false,
        errorMessage: issue.reason,
        rowNumber: issue.rowNumber,
      ));
    }

    return CsvParseResult(
      rows: rows,
      generalError: parsed.userMessage,
    );
  }

  /// Parses spreadsheet bytes via the resilient pipeline (direct Excel
  /// decode, then styles.xml repair, then CSV fallback). Runs on a
  /// background isolate.
  static Future<CsvParseResult> parseExcelBytesAsync(
    Uint8List bytes, {
    String fileName = '',
  }) async {
    final parsed = await ProductImportParser.parseFile(bytes, fileName: fileName);

    final rows = <CsvProductRow>[
      for (final row in parsed.rows)
        CsvProductRow(
          name: row.name,
          price: row.price,
          quantity: row.quantity,
          category: row.category,
          barcode: row.barcode,
          sku: row.sku,
          costPrice: row.costPrice,
          isValid: true,
          rowNumber: row.rowNumber,
        ),
    ];

    for (final issue in parsed.issues) {
      rows.add(CsvProductRow(
        name: '[Row ${issue.rowNumber}]',
        price: 0.0,
        quantity: 0,
        category: 'General',
        isValid: false,
        errorMessage: issue.reason,
        rowNumber: issue.rowNumber,
      ));
    }

    return CsvParseResult(
      rows: rows,
      generalError: parsed.userMessage,
    );
  }

  /// Synchronous spreadsheet parse, retained for tests and the sample
  /// seeder. Prefer [parseExcelBytesAsync] from the UI.
  static CsvParseResult parseExcelBytes(List<int> bytes) {
    final parsed = ProductImportParser.parseBytesSync(Uint8List.fromList(bytes));
    final rows = <CsvProductRow>[
      for (final row in parsed.rows)
        CsvProductRow(
          name: row.name,
          price: row.price,
          quantity: row.quantity,
          category: row.category,
          barcode: row.barcode,
          sku: row.sku,
          costPrice: row.costPrice,
          isValid: true,
          rowNumber: row.rowNumber,
        ),
    ];
    for (final issue in parsed.issues) {
      rows.add(CsvProductRow(
        name: '[Row ${issue.rowNumber}]',
        price: 0.0,
        quantity: 0,
        category: 'General',
        isValid: false,
        errorMessage: issue.reason,
        rowNumber: issue.rowNumber,
      ));
    }
    return CsvParseResult(rows: rows, generalError: parsed.userMessage);
  }

  /// Convenience wrapper that reads a file from disk and delegates to
  /// [parseExcelBytes]. Returns a friendly error on failure.
  static CsvParseResult parseExcelFile(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      return parseExcelBytes(bytes);
    } catch (e) {
      return CsvParseResult(
        rows: const [],
        generalError: 'Failed to read Excel file: $e',
      );
    }
  }

  /// Commits valid rows into Isar in a single transaction.
  ///
  /// Deduplication order: importUuid, then barcode, then sku, then
  /// case-insensitive name. A match updates the existing product rather
  /// than creating a duplicate, and tops up stock with a new batch when
  /// the row carries a quantity.
  static Future<ImportSummary> importProductsWithSummary({
    required Isar isar,
    required List<CsvProductRow> rows,
  }) async {
    final validRows = rows.where((r) => r.isValid).toList();
    if (validRows.isEmpty) {
      return const ImportSummary(skipped: 0);
    }

    var imported = 0;
    var updated = 0;
    var skipped = 0;
    final skipReasons = <String>[];
    final farFuture = DateTime.now().add(const Duration(days: 365));
    final palette = AppConstants.quickButtonPalette;

    await isar.writeTxn(() async {
      for (final row in validRows) {
        try {
          Product? existing;
          var matchedOn = '';

          if (row.barcode != null && row.barcode!.isNotEmpty) {
            existing = await isar.products
                .filter()
                .barcodeEqualTo(row.barcode!, caseSensitive: false)
                .findFirst();
            matchedOn = 'barcode';
          }

          if (existing == null && row.sku != null && row.sku!.isNotEmpty) {
            existing = await isar.products
                .filter()
                .skuEqualTo(row.sku!, caseSensitive: false)
                .findFirst();
            matchedOn = 'sku';
          }

          if (existing == null) {
            existing = await isar.products
                .filter()
                .nameEqualTo(row.name, caseSensitive: false)
                .findFirst();
            matchedOn = 'name';
          }

          final int productId;
          final Product productToUse;

          if (existing != null) {
            existing.price = row.price;
            // The existing name is intentionally left alone. Shop owners
            // rename products for display, and a weekly re-import should
            // not silently undo that. Price, cost and stock always follow
            // the spreadsheet, which is the point of re-importing.
            if (row.category.isNotEmpty && row.category != 'General') {
              existing.category = row.category;
            }
            if (row.barcode != null && row.barcode!.isNotEmpty) {
              existing.barcode = row.barcode;
            }
            if (row.sku != null && row.sku!.isNotEmpty) {
              existing.sku = row.sku;
            }
            if (row.costPrice != null) {
              existing.costPrice = row.costPrice;
            }
            existing.importUuid ??= _uuid.v4();
            productId = await isar.products.put(existing);
            productToUse = existing;
            updated++;
            debugPrint('[CsvImportService] Updated "$row.name" matched on $matchedOn');
          } else {
            final product = Product()
              ..name = row.name
              ..price = row.price
              ..category = row.category
              ..barcode = row.barcode
              ..sku = row.sku
              ..costPrice = row.costPrice
              ..importUuid = _uuid.v4()
              ..quickButtonColor =
                  palette[imported % palette.length].toARGB32();

            productId = await isar.products.put(product);
            productToUse = product;
            imported++;
          }

          if (row.quantity > 0) {
            final batch = Batch()
              ..productId = productId
              ..quantity = row.quantity
              ..expiryDate = row.expiryDate ?? farFuture
              ..restockDate = DateTime.now()
              ..supplierNote = 'Imported';

            await isar.batchs.put(batch);
            batch.product.value = productToUse;
            await batch.product.save();
          }
        } catch (e) {
          skipped++;
          skipReasons.add('${row.name}: $e');
          debugPrint('[CsvImportService] Error importing row "${row.name}": $e');
        }
      }
    });

    return ImportSummary(
      imported: imported,
      updated: updated,
      skipped: skipped,
      skipReasons: skipReasons,
    );
  }

  /// Legacy count-returning wrapper kept for the existing call sites in
  /// `main.dart`, `owner_products_screen.dart`, and
  /// `cashier_sales_screen.dart`.
  static Future<int> importProductsToIsar({
    required Isar isar,
    required List<CsvProductRow> rows,
  }) async {
    final summary = await importProductsWithSummary(isar: isar, rows: rows);
    return summary.imported + summary.updated;
  }

  /// Convenience method to seed sample Ghana retail products with stock
  static Future<int> seedSampleProducts(Isar isar) async {
    final result = parseCsv(sampleCsv);
    return importProductsToIsar(isar: isar, rows: result.rows);
  }
}

