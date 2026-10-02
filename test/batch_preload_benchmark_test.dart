import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/batch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Isar isar;
  late Directory tempDir;

  setUpAll(() async {
    await Isar.initializeIsarCore(libraries: {
      Abi.windowsX64: 'isar.dll',
    });
    tempDir = await Directory.systemTemp.createTemp('isar_batch_preload_test_');
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

  test('Benchmark Catalog-Wide Preload vs On-Demand Batch Loading', () async {
    const productCount = 1000;
    print('====================================================');
    print('  BATCH LOADING BENCHMARK: 1,000 PRODUCTS CATALOG');
    print('====================================================');

    print('Seeding $productCount products with 2 batches each...');
    await isar.writeTxn(() async {
      for (int i = 1; i <= productCount; i++) {
        final product = Product()
          ..name = 'Product #$i'
          ..price = 10.0 + i
          ..category = 'Category ${i % 5}'
          ..quickButtonColor = 0xFF4CAF50;

        final productId = await isar.products.put(product);

        final batch1 = Batch()
          ..productId = productId
          ..quantity = 50
          ..expiryDate = DateTime.now().add(Duration(days: 30 + i))
          ..restockDate = DateTime.now();

        final batch2 = Batch()
          ..productId = productId
          ..quantity = 30
          ..expiryDate = DateTime.now().add(Duration(days: 90 + i))
          ..restockDate = DateTime.now();

        await isar.batchs.putAll([batch1, batch2]);
      }
    });

    final allProducts = await isar.products.where().findAll();
    expect(allProducts.length, productCount);

    // ── BEFORE: Catalog-wide asyncMap preloading all 1,000 products ──
    final beforeSw = Stopwatch()..start();
    for (var product in allProducts) {
      await product.batches.load();
    }
    beforeSw.stop();
    print('BEFORE (Catalog-wide preload of 1,000 products):');
    print('  Total Time: ${beforeSw.elapsedMilliseconds} ms (${beforeSw.elapsedMicroseconds} µs)');

    // ── AFTER: On-demand loading for visible page items (e.g. 20 items) ──
    final afterSw = Stopwatch()..start();
    final visibleProducts = allProducts.take(20).toList();
    for (var product in visibleProducts) {
      final batches = await isar.batchs
          .filter()
          .productIdEqualTo(product.id)
          .findAll();
      expect(batches.length, 2);
    }
    afterSw.stop();
    print('AFTER (On-demand loading for 20 visible items on viewport):');
    print('  Total Time: ${(afterSw.elapsedMicroseconds / 1000.0).toStringAsFixed(3)} ms (${afterSw.elapsedMicroseconds} µs)');

    final speedupFactor = beforeSw.elapsedMicroseconds / afterSw.elapsedMicroseconds;
    print('----------------------------------------------------');
    print('⚡ Initial Load Latency Reduction: ${speedupFactor.toStringAsFixed(1)}x FASTER startup!');
    print('====================================================');
  });
}
