// Repair of settings saved before the ShopPOS Cloud fields existed (Isar
// read its "missing" markers for the new fields), and of the receipt
// numbers that produced — as found on a real device.

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/migrations.dart';
import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/core/utils/id_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/services/inventory_service.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/services/sale_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Isar isar;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(libraries: {Abi.windowsX64: 'isar.dll'});
    } catch (_) {}
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos_repair_');
    isar = await Isar.open(allSchemas, directory: dir.path, name: 'repair');
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    await dir.delete(recursive: true);
  });

  test('broken receipt counter and receipts are repaired, then numbering continues', () async {
    const minInt = -9223372036854775807 - 1;
    final owner = AppUser()
      ..name = 'Owner'
      ..role = AppConstants.roleOwner
      ..uuid = IdHelpers.newUuid()
      ..pinHash = HashHelpers.hashPin('482910');
    await isar.writeTxn(() async {
      await isar.appUsers.put(owner);
      await isar.storeSettings.put(StoreSettings()
        ..deviceId = 'dev'
        ..cloudDeviceCode = 'T1'
        ..receiptSeq = minInt + 2 // after two sales from the corrupt start
        ..settingsSynced = false // Isar's "missing" bool
        ..settingsUpdatedAt = null);
      final t0 = DateTime(2026, 10, 3, 3, 38);
      for (final (i, receipt) in ['T1--9223372036854775806', 'T1--9223372036854775807'].indexed) {
        await isar.sales.put(Sale()
          ..uuid = IdHelpers.newUuid()
          ..timestamp = t0.add(Duration(minutes: 30 * i))
          ..paymentType = 'cash'
          ..totalAmount = 1
          ..itemsJson = '[]'
          ..receiptNo = receipt);
      }
    });

    await DataMigrations.run(isar);

    final sales = await isar.sales.where().sortByTimestamp().findAll();
    expect(sales.map((s) => s.receiptNumber), ['T1-000001', 'T1-000002'], reason: 'oldest first, like the cloud repair');
    final s = (await isar.storeSettings.get(1))!;
    expect(s.receiptSeq, 2);
    expect(s.settingsSynced, isTrue);

    // The next sale continues the sequence.
    final p = await InventoryService.createProduct(isar, owner,
        const ProductInput(name: 'Milo', price: 5, category: 'D', quickButtonColor: 0),
        initialQuantity: 5, expiryDate: DateTime.now().add(const Duration(days: 30)));
    final sale = await SaleService.completeSale(isar, owner,
        lines: [CheckoutLine(product: (await isar.products.get(p.id))!, quantity: 1)],
        payments: [const PaymentInput(AppConstants.paymentCash, 5)]);
    expect(sale.receiptNumber, 'T1-000003');

    // Running again changes nothing.
    await DataMigrations.run(isar);
    expect((await isar.storeSettings.get(1))!.receiptSeq, 3);
  });
}
