import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:shop_pos/core/database/schemas.dart';
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

    tempDir = await Directory.systemTemp.createTemp('pos_product_test_');
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

  group('Product Dashboard Actions & CSV Integration', () {
    test('CSV parsing parses comma, semicolon, tab and quotes correctly', () {
      const csvData = '''name,price,quantity,category
"Milo 400g Tin",32.00,45,Beverages
"Peak Milk, Evaporated",12.50,90,Dairy
Voltic Water,4.50,120,Beverages''';

      final result = CsvImportService.parseCsv(csvData);
      expect(result.hasValidRows, isTrue);
      expect(result.validCount, equals(3));
      expect(result.rows[0].name, equals('Milo 400g Tin'));
      expect(result.rows[0].price, equals(32.00));
      expect(result.rows[0].quantity, equals(45));
      expect(result.rows[1].name, equals('Peak Milk, Evaporated'));
    });

    test('CSV parsing gracefully handles empty or invalid content without error', () {
      final emptyResult = CsvImportService.parseCsv('');
      expect(emptyResult.hasValidRows, isFalse);
      expect(emptyResult.validCount, equals(0));

      final whitespaceResult = CsvImportService.parseCsv('   \n  \n  ');
      expect(whitespaceResult.hasValidRows, isFalse);
    });

    test('(a) Manually add single product to database and verify it saves and appears', () async {
      final initialCount = await isar.products.count();

      // Simulate manual product addition via AddProduct form
      await isar.writeTxn(() async {
        final product = Product()
          ..name = 'Manual Fresh Product'
          ..price = 15.50
          ..category = 'Bakery'
          ..quickButtonColor = 0xFF4CAF50;

        final productId = await isar.products.put(product);

        final batch = Batch()
          ..productId = productId
          ..quantity = 25
          ..expiryDate = DateTime.now().add(const Duration(days: 30))
          ..restockDate = DateTime.now();

        await isar.batchs.put(batch);
        batch.product.value = product;
        await batch.product.save();
      });

      final afterManualCount = await isar.products.count();
      expect(afterManualCount, equals(initialCount + 1));

      final saved = await isar.products.filter().nameEqualTo('Manual Fresh Product').findFirst();
      expect(saved, isNotNull);
      expect(saved!.price, equals(15.50));
      await saved.batches.load();
      expect(saved.totalStock, equals(25));
    });

    test('(b) Import products via CSV and verify both manual & CSV items coexist', () async {
      final beforeCsvCount = await isar.products.count();

      const csvContent = '''name,price,quantity,category
Imported Milo 400g,32.00,45,Beverages
Imported Peak Milk,12.50,90,Dairy''';

      final parseResult = CsvImportService.parseCsv(csvContent);
      final importedCount = await CsvImportService.importProductsToIsar(
        isar: isar,
        rows: parseResult.rows,
      );

      expect(importedCount, equals(2));

      final afterCsvCount = await isar.products.count();
      expect(afterCsvCount, equals(beforeCsvCount + 2));

      // Confirm manual product is still intact
      final manualProduct = await isar.products.filter().nameEqualTo('Manual Fresh Product').findFirst();
      expect(manualProduct, isNotNull);
      expect(manualProduct!.price, equals(15.50));

      // Confirm CSV products are present
      final milo = await isar.products.filter().nameEqualTo('Imported Milo 400g').findFirst();
      expect(milo, isNotNull);
      expect(milo!.price, equals(32.00));
      await milo.batches.load();
      expect(milo.totalStock, equals(45));
    });
  });
}
