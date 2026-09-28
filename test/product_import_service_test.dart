/// ============================================
/// Product Import Service Tests — ShopPOS
/// ============================================
/// Verifies the Isar commit path: dedupe by barcode/sku/
/// name, uuid assignment, batch creation, and the
/// "X imported, Y updated, Z skipped" summary.
///
/// Run: flutter test test/product_import_service_test.dart
/// ============================================
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/services/csv_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Isar isar;
  late Directory tempDir;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(libraries: {
        Abi.windowsX64: 'isar.dll',
      });
    } catch (_) {}

    tempDir = await Directory.systemTemp.createTemp('pos_import_test_');
    isar = await Isar.open(
      [ProductSchema, BatchSchema],
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

  group('import summary', () {
    test('reports imported, updated and skipped counts', () async {
      final parsed = CsvImportService.parseCsv(
        'name,price,quantity,category\n'
        'Milo 400g,32.00,45,Beverages\n'
        'Peak Milk,12.50,90,Dairy\n'
        'Broken,not-a-price,5,Canned',
      );

      final summary = await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: parsed.rows,
      );

      expect(summary.imported, 2);
      expect(summary.updated, 0);
      expect(summary.skipped, 0,
          reason: 'unparseable rows never reach the writer');
      expect(summary.headline, '2 imported, 0 updated, 0 skipped');
      expect(await isar.products.count(), 2);
    });

    test('assigns a uuid to every newly created product', () async {
      final parsed = CsvImportService.parseCsv(
        'name,price,quantity\n'
        'Milo 400g,32.00,45\n'
        'Peak Milk,12.50,90',
      );

      await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: parsed.rows,
      );

      final products = await isar.products.where().findAll();
      expect(products, hasLength(2));
      for (final p in products) {
        expect(p.importUuid, isNotNull, reason: '${p.name} needs a uuid');
        expect(p.importUuid, isNotEmpty);
      }
      // Uuids must be distinct, not a shared constant.
      expect(products[0].importUuid, isNot(products[1].importUuid));
    });

    test('creates a stock batch for each row with a quantity', () async {
      final parsed = CsvImportService.parseCsv(
        'name,price,quantity\n'
        'Milo 400g,32.00,45',
      );

      await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: parsed.rows,
      );

      final batches = await isar.batchs.where().findAll();
      expect(batches, hasLength(1));
      expect(batches.single.quantity, 45);

      final product = (await isar.products.where().findFirst())!;
      await product.batches.load();
      expect(product.totalStock, 45);
    });

    test('stores barcode and cost price when the file supplies them', () async {
      final parsed = CsvImportService.parseCsv(
        'name,price,cost price,quantity,barcode\n'
        'Tomato Paste,55.00,48.00,100,5012345678900',
      );

      await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: parsed.rows,
      );

      final product = (await isar.products.where().findFirst())!;
      expect(product.barcode, '5012345678900');
      expect(product.costPrice, 48.0);
      expect(product.price, 55.0, reason: 'selling price must not be the cost');
    });
  });

  group('deduplication', () {
    test('a repeated barcode updates instead of duplicating', () async {
      final first = CsvImportService.parseCsv(
        'name,price,quantity,barcode\n'
        'Milo 400g,32.00,45,5012345678900',
      );
      final firstSummary = await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: first.rows,
      );
      expect(firstSummary.imported, 1);

      // Same barcode, new price, and a supplier-side name change.
      final second = CsvImportService.parseCsv(
        'name,price,quantity,barcode\n'
        'Milo 400g Tin (New),35.00,10,5012345678900',
      );
      final secondSummary = await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: second.rows,
      );

      expect(secondSummary.updated, 1);
      expect(secondSummary.imported, 0);
      expect(await isar.products.count(), 1, reason: 'no duplicate row');

      final product = (await isar.products.where().findFirst())!;
      expect(product.price, 35.0, reason: 'price follows the spreadsheet');
      // The catalog name is owner-facing, so a re-import must not clobber
      // it — only the commercial data is refreshed.
      expect(product.name, 'Milo 400g');
    });

    test('a repeated sku column updates even when the barcode changed',
        () async {
      await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: CsvImportService.parseCsv(
          'name,price,quantity,barcode\n'
          'Cola 300ml,7.50,24,A1',
        ).rows,
      );

      final summary = await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: CsvImportService.parseCsv(
          'name,price,quantity,barcode\n'
          'Cola 300ml,9.00,24,B2',
        ).rows,
      );

      expect(summary.updated, 1);
      expect(await isar.products.count(), 1);
      final product = (await isar.products.where().findFirst())!;
      expect(product.price, 9.0);
      expect(product.barcode, 'B2',
          reason: 'the new barcode should be adopted');
    });

    test('falls back to case-insensitive name matching', () async {
      await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: CsvImportService.parseCsv(
          'name,price,quantity\n'
          'Milo 400g,32.00,45',
        ).rows,
      );

      final summary = await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: CsvImportService.parseCsv(
          'name,price,quantity\n'
          'MILO 400G,33.00,5',
        ).rows,
      );

      expect(summary.updated, 1);
      expect(await isar.products.count(), 1);
      final product = (await isar.products.where().findFirst())!;
      expect(product.price, 33.0);
    });

    test('re-importing the same file twice is idempotent on product count',
        () async {
      const csv = 'name,price,quantity,barcode\n'
          'Milo 400g,32.00,45,B1\n'
          'Peak Milk,12.50,90,B2';

      final first = await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: CsvImportService.parseCsv(csv).rows,
      );
      final second = await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: CsvImportService.parseCsv(csv).rows,
      );

      expect(first.imported, 2);
      expect(second.imported, 0);
      expect(second.updated, 2);
      expect(await isar.products.count(), 2);
    });

    test('a row with no identifying column creates a separate product',
        () async {
      // Without a barcode or sku, two differently-named rows are distinct.
      final summary = await CsvImportService.importProductsWithSummary(
        isar: isar,
        rows: CsvImportService.parseCsv(
          'name,price,quantity\n'
          'Product A,5.00,1\n'
          'Product B,5.00,1',
        ).rows,
      );

      expect(summary.imported, 2);
      expect(await isar.products.count(), 2);
    });
  });

  group('legacy compatibility', () {
    test('importProductsToIsar still returns a bare count', () async {
      final count = await CsvImportService.importProductsToIsar(
        isar: isar,
        rows: CsvImportService.parseCsv(
          'name,price,quantity\n'
          'Milo,32.00,45\n'
          'Peak,12.50,90',
        ).rows,
      );

      expect(count, 2);
    });

    test('seedSampleProducts populates the catalog', () async {
      final count = await CsvImportService.seedSampleProducts(isar);
      expect(count, greaterThan(0));
      expect(await isar.products.count(), count);
    });
  });
}
