/// ============================================
/// Data Migrations — ShopPOS
/// ============================================
/// Small, idempotent fix-ups run at startup for
/// data written by older versions. New fields
/// themselves need no migration in Isar.
/// ============================================
library;

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/utils/id_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/sales/models/sale.dart';

class DataMigrations {
  DataMigrations._();

  static Future<void> run(Isar isar) async {
    try {
      await _assignUuids(isar);
      await _ensureDeviceId(isar);
    } catch (e, st) {
      debugPrint('[Migrations] failed: $e\n$st');
    }
  }

  /// Older rows have no stable uuid, which sync and backups key on.
  static Future<void> _assignUuids(Isar isar) async {
    final products = await isar.products.filter().uuidIsNull().findAll();
    final batches = await isar.batchs.filter().uuidIsNull().findAll();
    final sales = await isar.sales.filter().uuidIsNull().findAll();
    final users = await isar.appUsers.filter().uuidIsNull().findAll();
    if (products.isEmpty && batches.isEmpty && sales.isEmpty && users.isEmpty) {
      return;
    }
    await isar.writeTxn(() async {
      for (final p in products) {
        p.uuid = p.importUuid ?? IdHelpers.newUuid();
      }
      for (final b in batches) {
        b.uuid = IdHelpers.newUuid();
      }
      for (final s in sales) {
        s.uuid = IdHelpers.newUuid();
      }
      for (final u in users) {
        u.uuid = IdHelpers.newUuid();
      }
      await isar.products.putAll(products);
      await isar.batchs.putAll(batches);
      await isar.sales.putAll(sales);
      await isar.appUsers.putAll(users);
    });
  }

  static Future<void> _ensureDeviceId(Isar isar) async {
    final settings = await isar.storeSettings.get(1);
    if (settings == null || settings.deviceId.isNotEmpty) return;
    settings.deviceId = IdHelpers.newUuid();
    await isar.writeTxn(() => isar.storeSettings.put(settings));
  }
}
