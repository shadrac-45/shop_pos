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
import 'package:shop_pos/features/products/models/stock_movement.dart';
import 'package:shop_pos/features/sales/models/sale_item.dart';
import 'package:shop_pos/features/sales/models/sale.dart';

class DataMigrations {
  DataMigrations._();

  static Future<void> run(Isar isar) async {
    try {
      await _assignUuids(isar);
      await _openingBalances(isar);
      await _ensureDeviceId(isar);
      await _repairCloudFields(isar);
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
    final items = await isar.saleItems.filter().uuidIsNull().findAll();
    if (products.isEmpty &&
        batches.isEmpty &&
        sales.isEmpty &&
        users.isEmpty &&
        items.isEmpty) {
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

      // Matches the key older builds sent to the sync server.
      for (final i in items) {
        final sale = await isar.sales.get(i.saleId);
        i.uuid = '${sale?.uuid ?? 'sale-${i.saleId}'}#${i.id}';
      }
      await isar.saleItems.putAll(items);
    });
  }

  /// Stock that predates the movement ledger gets an "opening stock"
  /// movement, so the ledger fully explains every batch's quantity. Other
  /// devices rebuild stock from movements when syncing.
  static Future<void> _openingBalances(Isar isar) async {
    final batches = await isar.batchs.where().findAll();
    final now = DateTime.now();
    final fixes = <StockMovement>[];
    for (final b in batches) {
      // A batch from before the ledger may already have later movements
      // (e.g. sales), so top up only what the ledger doesn't explain.
      final movements =
          await isar.stockMovements.filter().batchIdEqualTo(b.id).findAll();
      final explained = movements.fold<int>(0, (s, m) => s + m.quantityChange);
      final gap = b.quantity - explained;
      if (gap == 0) continue;
      fixes.add(StockMovement()
        ..uuid = IdHelpers.newUuid()
        ..productId = b.productId
        ..batchId = b.id
        ..quantityChange = gap
        ..type = StockMovementType.initial
        ..note = 'Stock on hand when movement history began'
        ..timestamp = movements.isEmpty
            ? now
            : movements.map((m) => m.timestamp).reduce((a, c) => a.isBefore(c) ? a : c)
                .subtract(const Duration(seconds: 1)));
    }
    if (fixes.isEmpty) return;
    await isar.writeTxn(() => isar.stockMovements.putAll(fixes));
  }

  static Future<void> _ensureDeviceId(Isar isar) async {
    final settings = await isar.storeSettings.get(1);
    if (settings == null || settings.deviceId.isNotEmpty) return;
    settings.deviceId = IdHelpers.newUuid();
    await isar.writeTxn(() => isar.storeSettings.put(settings));
  }

  /// Settings saved before the ShopPOS Cloud fields existed read Isar's
  /// "missing" markers for the new non-nullable fields (the smallest int
  /// for receiptSeq, false for settingsSynced) instead of their defaults.
  /// That made the first cloud receipts "T1--9223…". Puts the defaults back
  /// and renumbers any receipts it broke, oldest first, in the same order
  /// the cloud repair uses.
  static final _validReceipt = RegExp(r'^T\d+-(\d+)$');
  static final _brokenReceipt = RegExp(r'^T\d+--');

  static Future<void> _repairCloudFields(Isar isar) async {
    final settings = await isar.storeSettings.get(1);
    if (settings == null) return;
    final broken = (await isar.sales.where().findAll())
        .where((s) => s.receiptNo != null && _brokenReceipt.hasMatch(s.receiptNo!))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final seqBroken = settings.receiptSeq < 0;
    final flagBroken = !settings.settingsSynced && settings.settingsUpdatedAt == null;
    if (broken.isEmpty && !seqBroken && !flagBroken) return;

    await isar.writeTxn(() async {
      final code = settings.cloudDeviceCode;
      var seq = 0;
      if (code.isNotEmpty) {
        for (final s in await isar.sales.where().findAll()) {
          final m = s.receiptNo == null ? null : _validReceipt.firstMatch(s.receiptNo!);
          if (m != null && s.receiptNo!.startsWith('$code-')) {
            final n = int.parse(m.group(1)!);
            if (n > seq) seq = n;
          }
        }
        for (final s in broken) {
          seq += 1;
          s.receiptNo = '$code-${seq.toString().padLeft(6, '0')}';
          await isar.sales.put(s);
        }
      }
      if (seqBroken || broken.isNotEmpty) settings.receiptSeq = seq < 0 ? 0 : seq;
      if (flagBroken) settings.settingsSynced = true;
      await isar.storeSettings.put(settings);
    });
    debugPrint('[Migrations] repaired cloud fields (${broken.length} receipts renumbered)');
  }
}
