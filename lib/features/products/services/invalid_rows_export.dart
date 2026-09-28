/// ============================================
/// Invalid Rows Export — ShopPOS
/// ============================================
/// Writes the rows the importer rejected, plus the reason, to a CSV the
/// owner can open in Excel and fix. This is the escape hatch for the
/// rows an import skipped, so nothing is lost and the owner is not left
/// guessing which line numbers were dropped.
/// ============================================
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shop_pos/features/products/services/csv_import_service.dart';

abstract class InvalidRowsExport {
  InvalidRowsExport._();

  /// Returns the path written, or null when there is nothing to export.
  static Future<String?> write(
    List<CsvProductRow> invalidRows, {
    String sourceName = 'import',
  }) async {
    if (invalidRows.isEmpty) return null;

    final buffer = StringBuffer()
      ..writeln('Row,Name,Price,Stock,Category,Barcode,Reason');

    for (final row in invalidRows) {
      final name = row.name.trim().isEmpty ? '' : row.name.trim();
      buffer.writeln([
        row.rowNumber,
        _quote(name),
        _quote(row.rawPriceForExport),
        _quote(row.rawStockForExport),
        _quote(row.category),
        _quote(row.barcode ?? ''),
        _quote(row.errorMessage ?? 'Invalid row'),
      ].join(','));
    }

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/invalid_rows_$stamp.csv');
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  static String _quote(String value) {
    final v = value.replaceAll('"', '""');
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"$v"';
    }
    return v;
  }
}
