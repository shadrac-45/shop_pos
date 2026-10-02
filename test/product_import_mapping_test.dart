/// ============================================
/// Product Import Mapping & Validation Tests
/// ============================================
/// Covers the defect that motivated this work: the old parser matched
/// headers by exact string and then silently fell back to positional
/// guessing, so a file led by a Category column showed "Rice & Grains"
/// in the Name column and imported product names as prices.
///
/// Also covers header normalisation, the mapping dialog contract, and
/// the guarantee that Accept imports only the valid rows.
///
/// Run: flutter test test/product_import_mapping_test.dart
/// ============================================
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/services/csv_import_service.dart';
import 'package:shop_pos/features/products/services/product_import_parser.dart';

void main() {
  group('header normalisation', () {
    test('strips a UTF-8 BOM from the first header', () {
      expect(
        ProductImportParser.normaliseHeader('\uFEFFName'),
        'name',
      );
    });

    test('strips quotes, collapses spaces and lowercases', () {
      expect(ProductImportParser.normaliseHeader('"Product Name"'),
          'product name');
      expect(ProductImportParser.normaliseHeader('  SELLING   PRICE  '),
          'selling price');
      expect(ProductImportParser.normaliseHeader('Selling_Price'),
          'selling price');
      expect(
          ProductImportParser.normaliseHeader("Owner's Name"), 'owners name');
    });

    test('a BOM-prefixed header row is still detected as the name column', () {
      final result = ProductImportParser.parseCsvText(
        '\uFEFFName,Price,Stock,Category\n'
        'Milo 400g,32.00,45,Beverages',
      );

      expect(result.needsMapping, isFalse);
      expect(result.rows.single.name, 'Milo 400g');
    });
  });

  group('the category-in-the-name-column defect', () {
    // This is the reported failure: a file whose first column holds
    // category text, with headers that match no known alias. The old
    // parser gave up on the headers and then guessed by position, so
    // "Rice & Grains" became a product named Rice & Grains and the
    // product name became its price.
    //
    // Note that this fixture deliberately uses headers that are NOT in
    // the alias list. A file whose headers *are* recognised must still
    // map automatically — that case is covered separately below.
    const shoppingList = '''Type of Goods,Article,Amount Charged,No. In Store
Rice & Grains,Adonko Rice 5kg,GH¢ 120.00,20
Beverages,Coca-Cola 350ml,GH¢ 12.50,48
Canned Goods,Heinz Beans 400g,GH¢ 35.00,30''';

    test('does not silently guess: it asks for a mapping instead', () {
      final result = ProductImportParser.parseCsvText(shoppingList);

      expect(
        result.needsMapping,
        isTrue,
        reason: 'no header matched, so the parser must not invent a mapping',
      );
      expect(result.userMessage, contains('could not tell which column'));
      expect(
        result.headerLabels,
        ['Type of Goods', 'Article', 'Amount Charged', 'No. In Store'],
      );
      // Sample rows let the owner recognise their own columns.
      expect(result.sampleRows, isNotEmpty);
    });

    test(
        'no category text leaks into the name column when mapping is asked for',
        () {
      final result = ProductImportParser.parseCsvText(shoppingList);

      // Nothing was parsed, so nothing can be wrong yet.
      expect(result.rows, isEmpty);
      expect(result.validRows, isEmpty);
    });

    test('a confirmed mapping reads the columns the owner chose', () {
      const mapping = ColumnMapping(
        name: 1, // Article
        price: 2, // Amount Charged
        stock: 3, // No. In Store
        category: 0, // Type of Goods
        cost: -1,
        barcode: -1,
        skipHeader: true,
        detected: false,
      );

      final result = ProductImportParser.parseCsvTextWithMapping(
        shoppingList,
        mapping,
      );

      expect(result.needsMapping, isFalse);
      expect(result.rows, hasLength(3));
      expect(result.validRows, hasLength(3));

      expect(result.rows[0].name, 'Adonko Rice 5kg');
      expect(result.rows[0].category, 'Rice & Grains');
      expect(result.rows[0].price, 120.0);
      expect(result.rows[0].quantity, 20);
    });

    test('a detectable header maps without prompting', () {
      final result = ProductImportParser.parseCsvText(
        'Category,Product,Price,Qty\n'
        'Rice & Grains,Adonko Rice 5kg,120.00,20',
      );

      expect(result.needsMapping, isFalse);
      expect(result.rows.single.name, 'Adonko Rice 5kg');
      expect(result.rows.single.category, 'Rice & Grains');
    });

    test('common shopping-list headers also map without prompting', () {
      // "Item Description", "Amount" and "In Stock" are all recognised,
      // so this file must NOT force the owner through a mapping dialog.
      final result = ProductImportParser.parseCsvText(
        'Category,Item Description,Amount,In Stock\n'
        'Rice & Grains,Adonko Rice 5kg,GH¢ 120.00,20',
      );

      expect(result.needsMapping, isFalse);
      expect(result.rows.single.name, 'Adonko Rice 5kg');
      expect(result.rows.single.category, 'Rice & Grains');
      expect(result.rows.single.price, 120.0);
      expect(result.rows.single.quantity, 20);
    });

    test('flags a mapping that points Name at the Category column', () {
      const wrong = ColumnMapping(
        name: 0, // Type of Goods — the mistake we are guarding against
        price: 2,
        stock: 3,
        category: 1,
        cost: -1,
        barcode: -1,
        skipHeader: true,
        detected: false,
      );

      final result = ProductImportParser.parseCsvTextWithMapping(
        shoppingList,
        wrong,
      );

      // Every row is caught rather than importing "Rice & Grains" as a
      // product with a price taken from the product name.
      expect(result.invalidRows, hasLength(3));
      expect(
        result.invalidRows.first.errorSummary,
        contains('looks like a category'),
      );
    });
  });

  group('one field per column', () {
    test('a column cannot feed two fields', () {
      const mapping = ColumnMapping(
        name: 0,
        price: 1,
        stock: 2,
        category: 1, // same column as price
        cost: -1,
        barcode: -1,
        skipHeader: true,
        detected: false,
      );

      expect(mapping.hasConflict, isTrue);
    });

    test('a clean mapping reports no conflict', () {
      const mapping = ColumnMapping(
        name: 0,
        price: 1,
        stock: 2,
        category: 3,
        cost: -1,
        barcode: -1,
        skipHeader: true,
        detected: false,
      );

      expect(mapping.hasConflict, isFalse);
    });

    test('"cost price" is not claimed as the selling price', () {
      final result = ProductImportParser.parseCsvText(
        'name,cost price,price,quantity\n'
        'Rice 5kg,45.00,52.00,20',
      );

      expect(result.rows.single.costPrice, 45.0);
      expect(result.rows.single.price, 52.0);
    });
  });

  group('price parsing', () {
    test('handles the documented Ghana formats', () {
      expect(ProductImportParser.parseNumeric('GH¢ 370.00'), 370.0);
      expect(ProductImportParser.parseNumeric('GH₵ 1,200.50'), 1200.5);
      expect(ProductImportParser.parseNumeric('GHC 370.00'), 370.0);
      expect(ProductImportParser.parseNumeric('1,200.50'), 1200.5);
      expect(ProductImportParser.parseNumeric('  \$45 '), 45.0);
      expect(ProductImportParser.parseNumeric('(25.00)'), -25.0);
      expect(ProductImportParser.parseNumeric(''), isNull);
      expect(ProductImportParser.parseNumeric('abc'), isNull);
    });

    test('a price that is actually a product name is rejected, not coerced',
        () {
      // This is what let the old import pass rows as "valid" with a
      // garbage price scraped out of the product name.
      final result = ProductImportParser.parseCsvText(
        'name,price,quantity\n'
        'Adonko Rice 5kg,Cola 350ml,20',
      );

      expect(result.validRows, isEmpty);
      expect(result.invalidRows, hasLength(1));
      expect(result.invalidRows.single.errorSummary, contains('not a number'));
    });
  });

  group('validation reasons', () {
    test('reports every problem on a row, not just the first', () {
      const mapping = ColumnMapping(
        name: 0,
        price: 1,
        stock: 2,
        category: 3,
        cost: -1,
        barcode: -1,
        skipHeader: true,
        detected: false,
      );

      final result = ProductImportParser.parseCsvTextWithMapping(
        'name,price,stock,category\n'
        ',not-a-price,-5,Food',
        mapping,
      );

      final row = result.invalidRows.single;
      expect(row.errors, contains('Missing name'));
      expect(row.errorSummary, contains('not a number'));
      expect(row.errorSummary, contains('cannot be negative'));
    });

    test('a blank stock defaults to zero rather than failing', () {
      final result = ProductImportParser.parseCsvText(
        'name,price,stock\n'
        'Milo 400g,32.00,',
      );

      expect(result.validRows.single.quantity, 0);
    });

    test('a blank category is allowed', () {
      final result = ProductImportParser.parseCsvText(
        'name,price,stock,category\n'
        'Milo 400g,32.00,45,',
      );

      expect(result.validRows.single.category, isEmpty);
    });

    test('a negative quantity is rejected instead of clamped', () {
      final result = ProductImportParser.parseCsvText(
        'name,price,stock\n'
        'Milo 400g,32.00,-5',
      );

      expect(result.invalidRows.single.errorSummary,
          contains('Quantity cannot be negative'));
    });

    test('a duplicate barcode in the same file is flagged', () {
      final result = ProductImportParser.parseCsvText(
        'name,price,stock,barcode\n'
        'Milo 400g,32.00,45,B1\n'
        'Peak Milk,12.50,90,B1\n'
        'Cola 300ml,7.50,24,B2',
      );

      expect(result.validRows, hasLength(2));
      expect(result.invalidRows, hasLength(1));

      final dup = result.invalidRows.single;
      expect(dup.errorSummary, contains('Duplicate barcode'));
      expect(dup.errorSummary, contains('row 2'),
          reason: 'should point at the first occurrence');
    });

    test('a fully empty row is skipped silently', () {
      final result = ProductImportParser.parseCsvText(
        'name,price,stock\n'
        'Milo 400g,32.00,45\n'
        ',,\n'
        '   ,   ,   \n'
        'Peak Milk,12.50,90',
      );

      expect(result.validRows, hasLength(2));
      expect(result.invalidRows, isEmpty);
    });
  });

  group('accept imports only the valid rows', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late Isar isar;
    late Directory tempDir;

    setUpAll(() async {
      try {
        await Isar.initializeIsarCore(libraries: {
          Abi.windowsX64: 'isar.dll',
        });
      } catch (_) {}

      tempDir = await Directory.systemTemp.createTemp('pos_map_test_');
      isar = await Isar.open(
        allSchemas,
        directory: tempDir.path,
      );
    });

    tearDownAll(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    setUp(() async {
      await isar.writeTxn(() async {
        await isar.batchs.clear();
        await isar.products.clear();
      });
    });

    test('only the valid rows reach the database', () async {
      final parsed = CsvImportService.parseCsv(
        'name,price,stock,barcode\n'
        'Milo 400g,32.00,45,B1\n'
        'Peak Milk,12.50,90,B2\n'
        'Broken,not-a-price,5,B3\n'
        ',50.00,5,B4',
      );

      expect(parsed.validRows, hasLength(2));
      expect(parsed.invalidRows, hasLength(2));

      final summary = await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: parsed.validRows,
      );

      expect(summary.imported, 2);
      expect(summary.updated, 0);
      expect(await isar.products.count(), 2);

      final names =
          (await isar.products.where().findAll()).map((p) => p.name).toSet();
      expect(names, {'Milo 400g', 'Peak Milk'});
    });

    test('a second import of the same file does not duplicate', () async {
      const csv = 'name,price,stock,barcode\n'
          'Milo 400g,32.00,45,B1\n'
          'Peak Milk,12.50,90,B2';

      final first = CsvImportService.parseCsv(csv);
      final firstSummary = await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: first.validRows,
      );
      expect(firstSummary.imported, 2);

      // Exactly what the Accept button does when the owner re-imports.
      final second = CsvImportService.parseCsv(csv);
      final secondSummary = await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: second.validRows,
      );

      expect(secondSummary.imported, 0, reason: 'nothing new to create');
      expect(secondSummary.updated, 2);
      expect(await isar.products.count(), 2,
          reason: 'the catalog must not double in size');
    });
  });
}
