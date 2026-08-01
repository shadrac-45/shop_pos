import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/batch.dart';
import 'package:shop_pos/models/app_user.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Isar isar;
  late Directory tempDir;

  setUpAll(() async {
    await Isar.initializeIsarCore(libraries: {
      Abi.windowsX64: 'isar.dll',
    });
    tempDir = await Directory.systemTemp.createTemp('isar_benchmark_test_');
    isar = await Isar.open(
      [SaleSchema, ProductSchema, BatchSchema, AppUserSchema],
      directory: tempDir.path,
    );
  });

  tearDownAll(() async {
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Benchmark 10,000+ Sale record queries with Isar indexes', () async {
    const totalRecords = 10000;
    print('====================================================');
    print('  ISAR BENCHMARK: 10,000+ SALE RECORDS QUERY TEST');
    print('====================================================');

    final random = Random(42);
    final now = DateTime.now();
    final paymentTypes = ['cash', 'momo', 'split'];
    final pins = ['1234', '5678', '9999'];

    print('Seeding $totalRecords sale records into Isar database...');
    final seedSw = Stopwatch()..start();

    await isar.writeTxn(() async {
      final sales = <Sale>[];
      for (int i = 0; i < totalRecords; i++) {
        // Distribute timestamps over the last 30 days
        final daysAgo = random.nextInt(30);
        final hoursAgo = random.nextInt(24);
        final minsAgo = random.nextInt(60);

        final timestamp = now.subtract(
          Duration(days: daysAgo, hours: hoursAgo, minutes: minsAgo),
        );

        final sale = Sale()
          ..timestamp = timestamp
          ..cashierPin = pins[random.nextInt(pins.length)]
          ..totalAmount = (random.nextDouble() * 200 + 5).roundToDouble()
          ..paymentType = paymentTypes[random.nextInt(paymentTypes.length)]
          ..itemsJson = '[{"productId":1,"name":"Water","qty":2,"price":3.50}]';

        sales.add(sale);
      }
      await isar.sales.putAll(sales);
    });

    seedSw.stop();
    print('✓ Seeding $totalRecords records took: ${seedSw.elapsedMilliseconds} ms');
    expect(await isar.sales.count(), totalRecords);

    // ── Test Query 1: Single-field timestamp range query ──
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    final q1Sw = Stopwatch()..start();
    final todaySales = await isar.sales
        .filter()
        .timestampBetween(startOfToday, endOfToday)
        .sortByTimestampDesc()
        .findAll();
    q1Sw.stop();
    print('----------------------------------------------------');
    print('Query 1: Today Sales (timestampBetween)');
    print('  Found: ${todaySales.length} records');
    print('  Execution Time: ${q1Sw.elapsedMicroseconds} µs (${(q1Sw.elapsedMicroseconds / 1000.0).toStringAsFixed(3)} ms)');

    // ── Test Query 2: Multi-field query (paymentType + timestamp) ──
    final q2Sw = Stopwatch()..start();
    final cashSalesToday = await isar.sales
        .filter()
        .paymentTypeEqualTo('cash')
        .timestampBetween(startOfToday, endOfToday)
        .sortByTimestampDesc()
        .findAll();
    q2Sw.stop();
    print('----------------------------------------------------');
    print('Query 2: Cash Sales Today (paymentType + timestampBetween)');
    print('  Found: ${cashSalesToday.length} records');
    print('  Execution Time: ${q2Sw.elapsedMicroseconds} µs (${(q2Sw.elapsedMicroseconds / 1000.0).toStringAsFixed(3)} ms)');

    // ── Test Query 3: Multi-field query (cashierPin + timestamp) ──
    final q3Sw = Stopwatch()..start();
    final cashierSalesToday = await isar.sales
        .filter()
        .cashierPinEqualTo('1234')
        .timestampBetween(startOfToday, endOfToday)
        .sortByTimestampDesc()
        .findAll();
    q3Sw.stop();
    print('----------------------------------------------------');
    print('Query 3: Cashier 1234 Sales Today (cashierPin + timestampBetween)');
    print('  Found: ${cashierSalesToday.length} records');
    print('  Execution Time: ${q3Sw.elapsedMicroseconds} µs (${(q3Sw.elapsedMicroseconds / 1000.0).toStringAsFixed(3)} ms)');

    // ── Test Query 4: 7-day range query with sorting ──
    final startOfWeek = startOfToday.subtract(const Duration(days: 7));
    final q4Sw = Stopwatch()..start();
    final weekSales = await isar.sales
        .filter()
        .timestampBetween(startOfWeek, endOfToday)
        .sortByTimestampDesc()
        .findAll();
    q4Sw.stop();
    print('----------------------------------------------------');
    print('Query 4: 7-Day Sales Range (timestampBetween 7 days)');
    print('  Found: ${weekSales.length} records');
    print('  Execution Time: ${q4Sw.elapsedMicroseconds} µs (${(q4Sw.elapsedMicroseconds / 1000.0).toStringAsFixed(3)} ms)');
    print('====================================================');
  });
}
