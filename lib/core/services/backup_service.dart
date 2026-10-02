/// ============================================
/// Backup Service — ShopPOS
/// ============================================
/// Whole-database backup to a single JSON file
/// the owner saves somewhere safe (Google Drive,
/// email, a USB stick), and restore from it.
/// ============================================
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:isar/isar.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/expenses/models/expense.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/stock_movement.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/models/sale_item.dart';
import 'package:shop_pos/features/shifts/models/shift.dart';

class BackupFormatException implements Exception {
  final String message;
  BackupFormatException(this.message);
  @override
  String toString() => message;
}

class BackupService {
  BackupService._();

  static const backupVersion = 1;
  static const _marker = 'ShopPOS backup';

  /// Every collection, by the name used in the backup file.
  static Map<String, IsarCollection<dynamic>> _collections(Isar isar) => {
        'products': isar.products,
        'batches': isar.batchs,
        'sales': isar.sales,
        'saleItems': isar.saleItems,
        'users': isar.appUsers,
        'storeSettings': isar.storeSettings,
        'stockMovements': isar.stockMovements,
        'expenses': isar.expenses,
        'shifts': isar.shifts,
        'activityLogs': isar.activityLogs,
      };

  /// Serialises the whole database. Contains PIN and password hashes, so
  /// the file must be kept private.
  static Future<Uint8List> export(Isar isar, AppUser? user) async {
    Permissions.require(user, Permission.manageSettings);
    final collections = <String, Object?>{};
    for (final entry in _collections(isar).entries) {
      // isar is pinned to 3.1.x, where buildQuery is stable in practice.
      // ignore: experimental_member_use
      collections[entry.key] = await entry.value.buildQuery<dynamic>().exportJson();
    }
    final json = jsonEncode({
      'format': _marker,
      'backupVersion': backupVersion,
      'appVersion': AppConstants.appVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'collections': collections,
    });

    await isar.writeTxn(() async {
      final settings = await isar.storeSettings.get(1);
      if (settings != null) {
        settings.lastBackupAt = DateTime.now();
        await isar.storeSettings.put(settings);
      }
      await isar.activityLogs
          .put(ActivityLogService.entry(user, ActivityAction.backup, 'Exported'));
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Checks a backup file and returns its record counts without changing
  /// anything, so the owner can confirm before restoring.
  static Map<String, int> inspect(Uint8List bytes) {
    final collections = _decode(bytes);
    return {for (final e in collections.entries) e.key: e.value.length};
  }

  /// Replaces ALL data with the backup's contents.
  static Future<Map<String, int>> restore(
      Isar isar, AppUser? user, Uint8List bytes) async {
    Permissions.require(user, Permission.manageSettings);
    final data = _decode(bytes);
    final targets = _collections(isar);

    await isar.writeTxn(() async {
      for (final c in targets.values) {
        await c.clear();
      }
      for (final entry in data.entries) {
        final target = targets[entry.key];
        if (target != null && entry.value.isNotEmpty) {
          await target.importJson(entry.value);
        }
      }

      // Links aren't part of exported JSON: reconnect batches to products
      // (product stock figures are read through this link).
      final products = {for (final p in await isar.products.where().findAll()) p.id: p};
      for (final batch in await isar.batchs.where().findAll()) {
        final product = products[batch.productId];
        if (product != null) {
          batch.product.value = product;
          await batch.product.save();
        }
      }
      await isar.activityLogs.put(ActivityLogService.entry(
          user, ActivityAction.restore, 'Restored from backup'));
    });
    return {for (final e in data.entries) e.key: e.value.length};
  }

  static Map<String, List<Map<String, dynamic>>> _decode(Uint8List bytes) {
    final Object? root;
    try {
      root = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw BackupFormatException('This file is not a ShopPOS backup.');
    }
    if (root is! Map || root['format'] != _marker) {
      throw BackupFormatException('This file is not a ShopPOS backup.');
    }
    if ((root['backupVersion'] as num? ?? 0) > backupVersion) {
      throw BackupFormatException(
          'This backup was made by a newer version of ShopPOS. Update the app first.');
    }
    final collections = root['collections'];
    if (collections is! Map) {
      throw BackupFormatException('The backup file is damaged.');
    }
    return {
      for (final e in collections.entries)
        e.key as String: [
          for (final r in e.value as List) Map<String, dynamic>.from(r as Map)
        ],
    };
  }
}
