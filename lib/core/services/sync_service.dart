/// ============================================
/// Sync Service — ShopPOS
/// ============================================
/// Cloud sync with the ShopPOS backend
/// (backend/server.js):
///
///  • push: every record changed since the last
///    sync (sales with their lines, stock
///    movements, expenses, shifts, products,
///    batches, staff names/roles, activity log)
///    goes up, so the shop's data survives a lost
///    phone and can be seen across devices.
///  • pull: product catalog edits (names, prices,
///    categories, codes, archiving) made on other
///    devices come down, newest edit winning.
///    Stock levels are NOT pulled: each device's
///    stock comes from its own sales and restocks.
///
/// PIN and password hashes are never sent.
/// ============================================
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/utils/id_helpers.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/expenses/models/expense.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/stock_movement.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/models/sale_item.dart';
import 'package:shop_pos/features/shifts/models/shift.dart';

class SyncResult {
  final int pushed;
  final int pulled;
  final String? error;
  final DateTime at;

  const SyncResult({required this.pushed, required this.pulled, this.error, required this.at});

  bool get ok => error == null;
}

class SyncService {
  SyncService._();

  /// Pushes local changes, then pulls catalog changes. Never throws: a
  /// failure is reported in [SyncResult.error] and retried next time.
  static Future<SyncResult> syncNow(
    Isar isar, {
    required String baseUrl,
    Dio? dio,
    bool checkConnectivity = true,
  }) async {
    final now = DateTime.now();
    final settings = await isar.storeSettings.get(1) ?? StoreSettings();
    if (baseUrl.isEmpty || settings.syncApiKey.isEmpty) {
      return SyncResult(
          pushed: 0, pulled: 0, at: now,
          error: 'Sync is not set up: enter the backend URL and sync key.');
    }
    if (checkConnectivity) {
      final status = await Connectivity().checkConnectivity();
      if (status.every((c) => c == ConnectivityResult.none)) {
        return SyncResult(pushed: 0, pulled: 0, at: now, error: 'No internet connection.');
      }
    }

    var deviceId = settings.deviceId;
    if (deviceId.isEmpty) {
      deviceId = IdHelpers.newUuid();
      settings.deviceId = deviceId;
      await isar.writeTxn(() => isar.storeSettings.put(settings));
    }

    final client = dio ??
        Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 60),
        ));
    final headers = {'x-api-key': settings.syncApiKey, 'x-device-id': deviceId};

    try {
      // ── Push ──
      final batch = await _collectChanges(isar, since: settings.lastSyncAt);
      var pushed = 0;
      if (batch.total > 0) {
        await client.post<Map<String, dynamic>>(
          '/sync/push',
          data: {'collections': batch.collections},
          options: Options(headers: headers),
        );
        await _markSynced(isar, batch);
        pushed = batch.total;
      }

      // ── Pull ──
      final response = await client.get<Map<String, dynamic>>(
        '/sync/pull',
        queryParameters: {
          if (settings.lastSyncAt != null)
            'since': settings.lastSyncAt!.toUtc().toIso8601String(),
        },
        options: Options(headers: headers),
      );
      final remote = (response.data?['products'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final pulled = await applyRemoteProducts(isar, remote);
      final serverTime =
          DateTime.tryParse(response.data?['serverTime'] as String? ?? '') ?? now;

      await isar.writeTxn(() async {
        final s = await isar.storeSettings.get(1);
        if (s != null) {
          s.lastSyncAt = serverTime;
          await isar.storeSettings.put(s);
        }
      });
      return SyncResult(pushed: pushed, pulled: pulled, at: now);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final message = status == 401
          ? 'The sync key was rejected by the server.'
          : (e.response?.data is Map
              ? (e.response!.data as Map)['message']?.toString()
              : null) ??
              'Could not reach the sync server.';
      debugPrint('[Sync] $message ($e)');
      return SyncResult(pushed: 0, pulled: 0, at: now, error: message);
    } catch (e) {
      debugPrint('[Sync] failed: $e');
      return SyncResult(pushed: 0, pulled: 0, at: now, error: '$e');
    }
  }

  /// Merges catalog records from the server. Returns how many changed.
  @visibleForTesting
  static Future<int> applyRemoteProducts(
      Isar isar, List<Map<String, dynamic>> remote) async {
    var changed = 0;
    await isar.writeTxn(() async {
      for (final r in remote) {
        final uuid = r['uuid'] as String?;
        if (uuid == null) continue;
        final remoteUpdated = DateTime.tryParse(r['updatedAt'] as String? ?? '');
        var product = await isar.products.filter().uuidEqualTo(uuid).findFirst();
        if (product != null &&
            product.updatedAt != null &&
            (remoteUpdated == null || !remoteUpdated.isAfter(product.updatedAt!))) {
          continue; // Local copy is as new or newer.
        }
        product ??= Product()..uuid = uuid;
        product
          ..name = r['name'] as String? ?? product.name
          ..price = (r['price'] as num?)?.toDouble() ?? 0
          ..category = r['category'] as String? ?? 'General'
          ..quickButtonColor = (r['quickButtonColor'] as num?)?.toInt() ?? product.quickButtonColor
          ..costPrice = (r['costPrice'] as num?)?.toDouble()
          ..barcode = r['barcode'] as String?
          ..sku = r['sku'] as String?
          ..reorderLevel = (r['reorderLevel'] as num?)?.toInt() ?? 0
          ..isArchived = r['isArchived'] == true
          ..updatedAt = remoteUpdated ?? DateTime.now()
          ..isSynced = true;
        await isar.products.put(product);
        changed++;
      }
    });
    return changed;
  }

  // ── Collecting changes ──────────────────────────────────────────────

  static Future<_ChangeSet> _collectChanges(Isar isar, {DateTime? since}) async {
    final products = await isar.products.filter().isSyncedEqualTo(false).findAll();
    final batches = await isar.batchs.filter().isSyncedEqualTo(false).findAll();
    final sales = await isar.sales.filter().isSyncedEqualTo(false).findAll();
    final movements = await isar.stockMovements.filter().isSyncedEqualTo(false).findAll();
    final expenses = await isar.expenses.filter().isSyncedEqualTo(false).findAll();
    final shifts = await isar.shifts.filter().isSyncedEqualTo(false).findAll();
    final users = await isar.appUsers.filter().isSyncedEqualTo(false).findAll();
    final logs = since == null
        ? await isar.activityLogs.where().findAll()
        : await isar.activityLogs.filter().timestampGreaterThan(since).findAll();

    final productUuids = {
      for (final p in await isar.products.where().findAll()) p.id: p.uuid,
    };
    final saleUuids = {for (final s in sales) s.id: s.uuid};
    final items = <SaleItem>[];
    for (final s in sales) {
      items.addAll(await isar.saleItems.filter().saleIdEqualTo(s.id).findAll());
    }
    final settings = await isar.storeSettings.get(1);
    final device = settings?.deviceId ?? '';

    String? iso(DateTime? d) => d?.toUtc().toIso8601String();

    return _ChangeSet(
      productIds: products.map((p) => p.id).toList(),
      batchIds: batches.map((b) => b.id).toList(),
      saleIds: sales.map((s) => s.id).toList(),
      movementIds: movements.map((m) => m.id).toList(),
      expenseIds: expenses.map((e) => e.id).toList(),
      shiftIds: shifts.map((s) => s.id).toList(),
      userIds: users.map((u) => u.id).toList(),
      collections: {
        'products': [
          for (final p in products)
            {
              'uuid': p.uuid,
              'name': p.name,
              'price': p.price,
              'category': p.category,
              'quickButtonColor': p.quickButtonColor,
              'costPrice': p.costPrice,
              'barcode': p.barcode,
              'sku': p.sku,
              'reorderLevel': p.reorderLevel,
              'isArchived': p.isArchived,
              'updatedAt': iso(p.updatedAt),
            }
        ],
        'batches': [
          for (final b in batches)
            {
              'uuid': b.uuid,
              'productUuid': productUuids[b.productId],
              'quantity': b.quantity,
              'expiryDate': iso(b.expiryDate),
              'restockDate': iso(b.restockDate),
              'unitCost': b.unitCost,
              'supplierNote': b.supplierNote,
              'updatedAt': iso(b.updatedAt),
            }
        ],
        'sales': [
          for (final s in sales)
            {
              'uuid': s.uuid,
              'receiptNumber': s.receiptNumber,
              'timestamp': iso(s.timestamp),
              'cashierId': s.cashierId,
              'paymentType': s.paymentType,
              'subtotal': s.effectiveSubtotal,
              'discountAmount': s.discountAmount,
              'taxAmount': s.taxAmount,
              'taxRate': s.taxRate,
              'totalAmount': s.totalAmount,
              'amountTendered': s.amountTendered,
              'changeDue': s.changeDue,
              'payments': [
                for (final p in s.effectivePayments)
                  {'method': p.method, 'amount': p.amount, 'reference': p.reference}
              ],
              'status': s.status,
              'refundedAmount': s.refundedAmount,
              'refunds': [
                for (final r in s.refunds)
                  {'amount': r.amount, 'method': r.method, 'at': iso(r.at), 'reason': r.reason}
              ],
              'statusReason': s.statusReason,
              'paystackReference': s.paystackReference,
              'momoProvider': s.momoProvider,
              'momoPhone': s.momoPhone,
              'updatedAt': iso(s.updatedAt ?? s.timestamp),
            }
        ],
        'saleItems': [
          for (final i in items)
            {
              'uuid': '${saleUuids[i.saleId]}#${i.id}',
              'saleUuid': saleUuids[i.saleId],
              'productUuid': productUuids[i.productId],
              'productName': i.productName,
              'quantity': i.quantity,
              'unitPrice': i.unitPrice,
              'unitCost': i.unitCost,
              'discount': i.discount,
              'lineTotal': i.lineTotal,
              'refundedQty': i.refundedQty,
              'refundedAmount': i.refundedAmount,
              'updatedAt': iso(i.timestamp),
            }
        ],
        'stockMovements': [
          for (final m in movements)
            {
              'uuid': m.uuid,
              'productUuid': productUuids[m.productId],
              'quantityChange': m.quantityChange,
              'type': m.type,
              'reason': m.reason,
              'note': m.note,
              'userId': m.userId,
              'timestamp': iso(m.timestamp),
              'updatedAt': iso(m.timestamp),
            }
        ],
        'expenses': [
          for (final e in expenses)
            {
              'uuid': e.uuid,
              'amount': e.amount,
              'category': e.category,
              'description': e.description,
              'paidFromTill': e.paidFromTill,
              'userId': e.userId,
              'timestamp': iso(e.timestamp),
              'isDeleted': e.isDeleted,
              'updatedAt': iso(e.updatedAt ?? e.timestamp),
            }
        ],
        'shifts': [
          for (final s in shifts)
            {
              'uuid': s.uuid,
              'userId': s.userId,
              'openedAt': iso(s.openedAt),
              'closedAt': iso(s.closedAt),
              'openingFloat': s.openingFloat,
              'cashSales': s.cashSales,
              'cashRefunds': s.cashRefunds,
              'tillPayouts': s.tillPayouts,
              'expectedCash': s.expectedCash,
              'countedCash': s.countedCash,
              'closingNote': s.closingNote,
              'updatedAt': iso(s.closedAt ?? s.openedAt),
            }
        ],
        // Names and roles only: credentials never leave the device.
        'users': [
          for (final u in users)
            {
              'uuid': u.uuid,
              'localId': u.id,
              'name': u.name,
              'role': u.role,
              'isActive': u.isActive,
              'updatedAt': iso(u.updatedAt),
            }
        ],
        'activityLogs': [
          for (final l in logs)
            {
              'uuid': '$device#${l.id}',
              'userId': l.userId,
              'userName': l.userName,
              'action': l.action,
              'details': l.details,
              'timestamp': iso(l.timestamp),
            }
        ],
      },
    );
  }

  static Future<void> _markSynced(Isar isar, _ChangeSet c) async {
    await isar.writeTxn(() async {
      Future<void> mark<T>(IsarCollection<T> col, List<int> ids, void Function(T) set) async {
        final rows = (await col.getAll(ids)).whereType<T>().toList();
        for (final r in rows) {
          set(r);
        }
        await col.putAll(rows);
      }

      await mark<Product>(isar.products, c.productIds, (r) => r.isSynced = true);
      await mark<Batch>(isar.batchs, c.batchIds, (r) => r.isSynced = true);
      await mark<Sale>(isar.sales, c.saleIds, (r) => r.isSynced = true);
      await mark<StockMovement>(isar.stockMovements, c.movementIds, (r) => r.isSynced = true);
      await mark<Expense>(isar.expenses, c.expenseIds, (r) => r.isSynced = true);
      await mark<Shift>(isar.shifts, c.shiftIds, (r) => r.isSynced = true);
      await mark<AppUser>(isar.appUsers, c.userIds, (r) => r.isSynced = true);
    });
  }
}

class _ChangeSet {
  final List<int> productIds, batchIds, saleIds, movementIds, expenseIds, shiftIds, userIds;
  final Map<String, List<Map<String, dynamic>>> collections;

  _ChangeSet({
    required this.productIds,
    required this.batchIds,
    required this.saleIds,
    required this.movementIds,
    required this.expenseIds,
    required this.shiftIds,
    required this.userIds,
    required this.collections,
  });

  int get total => collections.values.fold(0, (s, l) => s + l.length);
}
