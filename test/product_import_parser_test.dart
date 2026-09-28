/// ============================================
/// Product Import Parser Tests — ShopPOS
/// ============================================
/// Covers the numFmtId repair path, header alias
/// mapping, currency-tolerant numeric parsing, and
/// the friendly-error contract.
///
/// The xlsx fixture is generated at runtime rather than
/// committed, so the exact failure case is visible in
/// source and cannot drift from the package's parser.
///
/// Run: flutter test test/product_import_parser_test.dart
/// ============================================
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/features/products/services/product_import_parser.dart';

/// Wraps a Dart value in the [CellValue] variant the `excel` writer wants,
/// so test rows exercise the same int/double/text cell shapes that arrive
/// from real spreadsheets.
CellValue _cell(dynamic value) {
  if (value == null) return TextCellValue('');
  if (value is int) return IntCellValue(value);
  if (value is double) return DoubleCellValue(value);
  return TextCellValue(value.toString());
}

/// Builds a minimal but structurally valid .xlsx whose `xl/styles.xml`
/// declares `<numFmt numFmtId="42" .../>` — the accounting format that
/// makes `excel` 4.0.6 throw.
Uint8List buildNumFmt42Workbook({
  required List<List<dynamic>> rows,
}) {
  final excel = Excel.createExcel();
  final sheet = excel['Sheet1'];
  for (final row in rows) {
    sheet.appendRow(row.map(_cell).toList());
  }
  // Save a clean workbook first, then inject the offending numFmt so the
  // rest of the container is guaranteed to be something Excel accepts.
  final clean = excel.save() ?? const <int>[];

  final archive = ZipDecoder().decodeBytes(clean);
  for (final file in archive.files) {
    if (file.name.toLowerCase() != 'xl/styles.xml') continue;

    final xml = utf8.decode(file.content!);
    const reserved = '<numFmt numFmtId="42" '
        'formatCode="_(&quot;GH₵&quot; * #,##0.00_);'
        '_(&quot;GH₵\\* \\(#,##0.00\\);'
        '_(&quot;GH₵&quot; ??_);_(@_)"/>';

    // Insert just before the closing styleSheet tag.
    final patched = xml.replaceFirst(
      '</styleSheet>',
      '<numFmts count="1">$reserved</numFmts></styleSheet>',
    );

    final bytes = utf8.encode(patched);
    archive.addFile(ArchiveFile(file.name, bytes.length, bytes));
  }

  return Uint8List.fromList(ZipEncoder().encode(archive) ?? const <int>[]);
}

/// Same workbook, but with a clean styles part — the control case.
Uint8List buildPlainWorkbook({required List<List<dynamic>> rows}) {
  final excel = Excel.createExcel();
  final sheet = excel['Sheet1'];
  for (final row in rows) {
    sheet.appendRow(row.map(_cell).toList());
  }
  return Uint8List.fromList(excel.save() ?? const <int>[]);
}

void main() {
  group('styles.xml numFmt repair', () {
    test('reproduces the numFmtId=42 failure on a naive decode', () {
      final bytes = buildNumFmt42Workbook(rows: [
        ['name', 'price', 'quantity', 'category'],
        ['Milo 400g', 32.0, 45, 'Beverages'],
      ]);

      // Confirms the fixture actually exercises the bug: decoding the
      // untouched bytes must throw the reported message.
      expect(
        () => Excel.decodeBytes(bytes),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('custom numFmtId starts at 164 but found a value of 42'),
          ),
        ),
      );
    });

    test('parses the same file after styles repair', () {
      final bytes = buildNumFmt42Workbook(rows: [
        ['name', 'price', 'quantity', 'category'],
        ['Milo 400g', 32.0, 45, 'Beverages'],
        ['Peak Milk', 12.5, 90, 'Dairy'],
      ]);

      final result = ProductImportParser.parseBytesSync(bytes);

      expect(
        result.userMessage,
        isNull,
        reason: 'numFmtId=42 must not block import',
      );
      expect(result.isSuccess, isTrue);
      expect(result.strategy, ImportDecodeStrategy.excelAfterStyleRepair);
      expect(result.rows, hasLength(2));

      expect(result.rows[0].name, 'Milo 400g');
      expect(result.rows[0].price, 32.0);
      expect(result.rows[0].quantity, 45);
      expect(result.rows[0].category, 'Beverages');
      expect(result.rows[0].rowNumber, 2);
    });

    test('a clean workbook still takes the direct path', () {
      final bytes = buildPlainWorkbook(rows: [
        ['name', 'price', 'quantity', 'category'],
        ['Gari 1kg', 18.0, 35, 'Food Cupboard'],
      ]);

      final result = ProductImportParser.parseBytesSync(bytes);

      expect(result.isSuccess, isTrue);
      expect(result.strategy, ImportDecodeStrategy.excelDirect);
      expect(result.rows.single.name, 'Gari 1kg');
    });

    test('stripReservedNumFmts removes only ids below 164', () {
      const xml = '<styleSheet>'
          '<numFmts>'
          '<numFmt numFmtId="42" formatCode="accounting"/>'
          '<numFmt numFmtId="163" formatCode="reserved"/>'
          '<numFmt numFmtId="164" formatCode="custom"/>'
          '<numFmt numFmtId="176" formatCode="custom2"/>'
          '</numFmts>'
          '</styleSheet>';

      final stripped = ProductImportParser.stripReservedNumFmts(xml);

      expect(stripped, isNot(contains('numFmtId="42"')));
      expect(stripped, isNot(contains('numFmtId="163"')));
      expect(stripped, contains('numFmtId="164"'));
      expect(stripped, contains('numFmtId="176"'));
      // The container itself must survive.
      expect(stripped, contains('<numFmts>'));
      expect(stripped, contains('</numFmts>'));
    });

    test('async parseFile resolves the same result off the UI isolate',
        () async {
      final bytes = buildNumFmt42Workbook(rows: [
        ['name', 'price', 'quantity', 'category'],
        ['Ideal Milk', 11.0, 80, 'Dairy'],
      ]);

      final result =
          await ProductImportParser.parseFile(bytes, fileName: 'list.xlsx');

      expect(result.isSuccess, isTrue);
      expect(result.strategy, ImportDecodeStrategy.excelAfterStyleRepair);
      expect(result.rows.single.name, 'Ideal Milk');
    });
  });

  group('header alias mapping', () {
    test('accepts the documented aliases, case- and space-insensitively', () {
      final result = ProductImportParser.parseCsvText(
        'Item,Selling Price,Stock,Dept,Barcode\n'
        'Tomato Paste,5.00,100,Canned Goods,111222333',
      );

      expect(result.isSuccess, isTrue);
      final row = result.rows.single;
      expect(row.name, 'Tomato Paste');
      expect(row.price, 5.0);
      expect(row.quantity, 100);
      expect(row.category, 'Canned Goods');
      expect(row.barcode, '111222333');
    });

    test('an sku header is a barcode alias, and only one wins', () {
      // "sku" is in the barcode alias list. A column is claimed once, so
      // when both barcode and sku headers are present, barcode takes it
      // and the sku column is left unmapped rather than double-feeding.
      final result = ProductImportParser.parseCsvText(
        'name,price,barcode,sku\n'
        'Tomato Paste,5.00,111222333,TP-001',
      );

      final row = result.rows.single;
      expect(row.barcode, '111222333');
    });

    test('a sku-only header still populates the barcode field', () {
      final result = ProductImportParser.parseCsvText(
        'name,price,sku\n'
        'Tomato Paste,5.00,TP-001',
      );

      expect(result.rows.single.barcode, 'TP-001');
    });

    test('maps cost and price to separate columns', () {
      final result = ProductImportParser.parseCsvText(
        'name,cost price,price,quantity\n'
        'Rice 5kg,45.00,52.00,20',
      );

      final row = result.rows.single;
      expect(row.costPrice, 45.0);
      expect(row.price, 52.0, reason: 'price must not be overwritten by cost');
    });

    test('falls back to column order when headers are absent', () {
      final result = ProductImportParser.parseCsvText(
        'Cola 300ml,7.50,24,Beverages',
      );

      final row = result.rows.single;
      expect(row.name, 'Cola 300ml');
      expect(row.price, 7.5);
      expect(row.quantity, 24);
      expect(row.category, 'Beverages');
    });
  });

  group('currency and number coercion', () {
    test('strips currency symbols and thousands separators', () {
      // Prices are quoted because they contain commas — an unquoted
      // "1,200.50" is two CSV fields, not one number.
      final result = ProductImportParser.parseCsvText(
        'name,price,quantity\n'
        '"Beaded Necklace","GH₵ 1,200.50",3\n'
        '"Ankara Cloth","\$ 45.00",10\n'
        '"Sandals","GH₵ 89.50",5',
      );

      expect(result.isSuccess, isTrue);
      expect(result.rows, hasLength(3));
      expect(result.rows[0].price, 1200.50);
      expect(result.rows[1].price, 45.0);
      expect(result.rows[2].price, 89.50);
    });

    test('parseNumeric handles the documented shapes', () {
      expect(ProductImportParser.parseNumeric('32.00'), 32.0);
      expect(ProductImportParser.parseNumeric('GH₵ 1,200.50'), 1200.50);
      expect(ProductImportParser.parseNumeric('  \$45 '), 45.0);
      expect(ProductImportParser.parseNumeric('(25.00)'), -25.0);
      expect(ProductImportParser.parseNumeric('-7.5'), -7.5);
      expect(ProductImportParser.parseNumeric(''), isNull);
      expect(ProductImportParser.parseNumeric('abc'), isNull);
      expect(ProductImportParser.parseNumeric('1.2.3'), 1.23,
          reason: 'only the first decimal point is kept');
    });

    test('reads numeric cells that arrive as int or double', () {
      final bytes = buildPlainWorkbook(rows: [
        ['name', 'price', 'quantity', 'category'],
        ['Whole Number', 45, 7, 'Canned'],
        ['Decimal Value', 12.75, 3, 'Canned'],
      ]);

      final result = ProductImportParser.parseBytesSync(bytes);
      expect(result.isSuccess, isTrue);
      expect(result.rows[0].price, 45.0);
      expect(result.rows[0].quantity, 7);
      expect(result.rows[1].price, 12.75);
    });
  });

  group('row validation and reporting', () {
    test('skips fully empty rows without reporting them', () {
      final result = ProductImportParser.parseCsvText(
        'name,price,quantity\n'
        'Milo,32.00,45\n'
        ',,\n'
        '   ,  ,   \n'
        'Peak,12.50,90',
      );

      expect(result.isSuccess, isTrue);
      expect(result.validRows, hasLength(2));
      expect(result.invalidRows, isEmpty);
    });

    test('reports skipped rows with their true line numbers', () {
      final result = ProductImportParser.parseCsvText(
        'name,price,quantity\n'
        'Good One,10.00,5\n'
        ',5.00,5\n'
        'Bad Price,not-a-number,5\n'
        'Also Good,20.00,2',
      );

      expect(result.validRows, hasLength(2));
      expect(result.invalidRows, hasLength(2));

      expect(result.invalidRows[0].rowNumber, 3, reason: 'the blank-name line');
      expect(result.invalidRows[0].errors, contains('Missing name'));

      expect(result.invalidRows[1].rowNumber, 4, reason: 'the bad price line');
      expect(result.invalidRows[1].errorSummary, contains('not-a-number'));
    });

    test('line numbers survive a blank line being skipped', () {
      final result = ProductImportParser.parseCsvText(
        'name,price,quantity\n'
        'Good One,10.00,5\n'
        '\n'
        ',,\n'
        'Bad Price,not-a-number,5',
      );

      expect(result.validRows, hasLength(1));
      expect(result.invalidRows, hasLength(1));
      // The bad row is physically the 5th line of the file.
      expect(result.invalidRows.single.rowNumber, 5);
    });

    test('never leaks a raw exception string to the user', () {
      // Bytes that are neither a zip nor parseable text.
      final junk = Uint8List.fromList([0x00, 0x01, 0x02, 0xFF, 0xFE]);
      final result = ProductImportParser.parseBytesSync(junk);

      expect(result.isSuccess, isFalse);
      expect(result.userMessage, isNotNull);
      expect(result.userMessage, contains('CSV'));
      expect(result.userMessage, isNot(contains('Exception')));
      expect(result.userMessage, isNot(contains('#0')));
    });

    test('empty input yields a friendly message, not a crash', () {
      final result = ProductImportParser.parseBytesSync(Uint8List(0));
      expect(result.isSuccess, isFalse);
      expect(result.userMessage, contains('empty'));
    });
  });

  group('delimited text fallbacks', () {
    test('reads semicolon-separated text', () {
      final result = ProductImportParser.parseCsvText(
        'name;price;quantity;category\n'
        'Cola;7.50;24;Beverages',
      );

      expect(result.isSuccess, isTrue);
      expect(result.rows.single.name, 'Cola');
      expect(result.rows.single.quantity, 24);
    });

    test('reads tab-separated text', () {
      final result = ProductImportParser.parseCsvText(
        'name\tprice\tquantity\n'
        'Cola\t7.50\t24',
      );

      expect(result.isSuccess, isTrue);
      expect(result.rows.single.price, 7.5);
    });

    test('honours quoted fields containing commas', () {
      final result = ProductImportParser.parseCsvText(
        'name,price,quantity,category\n'
        '"Milk, Evaporated",12.50,90,Dairy',
      );

      expect(result.isSuccess, isTrue);
      expect(result.rows.single.name, 'Milk, Evaporated');
      expect(result.rows.single.price, 12.5);
    });

    test('tolerates a UTF-8 byte order mark', () {
      final bom = Uint8List.fromList([0xEF, 0xBB, 0xBF]);
      final body = utf8.encode('name,price,quantity\nMilo,32.00,45');
      final bytes = Uint8List.fromList([...bom, ...body]);

      final result = ProductImportParser.parseBytesSync(bytes);
      expect(result.isSuccess, isTrue);
      expect(result.rows.single.name, 'Milo');
    });
  });
}
