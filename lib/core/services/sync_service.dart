/// ============================================
/// Sync Service — ShopPOS
/// ============================================
/// Cloud sync with the ShopPOS backend
/// (backend/server.js), so several tills share
/// one shop:
///
///  • push: every record changed here since the
///    last sync goes up (sales and their lines,
///    stock movements, batches, products,
///    expenses, shifts, staff names/roles,
///    activity log).
///  • pull: what other devices pushed comes down
///    and is merged:
///      – products, staff, sales, expenses:
///        newest edit wins (by updatedAt)
///      – batches: created here if new
///      – stock movements: each one is applied to
///        its batch exactly once, so every device
///        ends up with the same stock levels.
///    Remote sales never move stock themselves;
///    their stock movements do.
///
/// Two servers are supported:
///  • ShopPOS Cloud (backend/ Express API, when
///    this till is connected): device token,
///    change-feed cursor, chunked pushes, and
///    staff bcrypt PIN hashes so staff can sign
///    in on any of the shop's tills.
///  • the legacy sync server (API key): PIN and
///    password hashes are never sent there.
/// Owner/admin passwords never leave the device.
///
/// Every record carries its own UUID, so a push
/// that is retried (timeout, crash, lost reply)
/// is stored once: a sale is never duplicated.
/// ============================================
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
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

  /// Records the cloud refused (e.g. invalid, or belonging to another
  /// shop), and notes such as an unverified MoMo payment.
  final int conflicts;
  final int warnings;

  /// True when the till has been disconnected from the cloud and must be
  /// signed in again.
  final bool unauthorized;

  const SyncResult({
    required this.pushed,
    required this.pulled,
    this.error,
    required this.at,
    this.conflicts = 0,
    this.warnings = 0,
    this.unauthorized = false,
  });

  bool get ok => error == null;
}

/// Order in which collections are pushed: referenced records first.
const cloudPushOrder = [
  'users',
  'products',
  'batches',
  'sales',
  'saleItems',
  'stockMovements',
  'expenses',
  'shifts',
  'activityLogs',
];

/// Records per cloud push request (the server accepts up to 2000).
const cloudChunkSize = 400;

/// Collections a device downloads from the others.
const pulledCollections = [
  'products',
  'users',
  'batches',
  'sales',
  'saleItems',
  'stockMovements',
  'expenses',
];

class SyncService {
  SyncService._();

  /// Pushes local changes, then pulls and merges other devices' changes.
  /// Never throws: a failure is reported in [SyncResult.error] and
  /// retried next time.
  static Future<SyncResult> syncNow(
    Isar isar, {
    required String baseUrl,
    Dio? dio,
    bool checkConnectivity = true,
  }) async {
    final now = DateTime.now();
    final settings = await isar.storeSettings.get(1) ?? StoreSettings();
    if (settings.cloudDeviceToken.isNotEmpty && settings.cloudUrl.isNotEmpty) {
      return cloudSync(isar, dio: dio, checkConnectivity: checkConnectivity);
    }
    if (baseUrl.isEmpty || settings.syncServerKey.isEmpty) {
      return SyncResult(
          pushed: 0, pulled: 0, at: now,
          error: 'Sync is not set up: enter the sync server URL and key.');
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
    final headers = {'x-api-key': settings.syncServerKey, 'x-device-id': deviceId};

    try {
      // ── Push ──
      final changes = await collectChanges(isar, since: settings.lastSyncAt);
      var pushed = 0;
      if (changes.total > 0) {
        await client.post<Map<String, dynamic>>(
          '/sync/push',
          data: {'collections': changes.collections},
          options: Options(headers: headers),
        );
        await _markSynced(isar, changes);
        pushed = changes.total;
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
      final data = response.data ?? const {};
      final remote = <String, List<Map<String, dynamic>>>{
        for (final name in pulledCollections)
          name: [
            for (final r in data[name] as List? ?? const [])
              Map<String, dynamic>.from(r as Map)
          ],
      };
      final pulled = await applyRemote(isar, remote);
      final serverTime = DateTime.tryParse(data['serverTime'] as String? ?? '') ?? now;

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
    } catch (e, st) {
      debugPrint('[Sync] failed: $e\n$st');
      return SyncResult(pushed: 0, pulled: 0, at: now, error: '$e');
    }
  }

  /// Sync with ShopPOS Cloud. Push: everything not yet synced, in chunks,
  /// in dependency order. Pull: the shop's change feed from [cloudCursor].
  /// Local records are only marked synced after the server stored them,
  /// and only if they weren't edited meanwhile. Never throws.
  static Future<SyncResult> cloudSync(
    Isar isar, {
    Dio? dio,
    bool checkConnectivity = true,
  }) async {
    final now = DateTime.now();
    final settings = await isar.storeSettings.get(1) ?? StoreSettings();
    if (checkConnectivity) {
      final status = await Connectivity().checkConnectivity();
      if (status.every((c) => c == ConnectivityResult.none)) {
        return SyncResult(pushed: 0, pulled: 0, at: now, error: 'No internet connection.');
      }
    }
    final client = dio ??
        Dio(BaseOptions(
          baseUrl: settings.cloudUrl.trim(),
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 90),
        ));
    final options = Options(headers: {'x-device-token': settings.cloudDeviceToken});

    try {
      // ── Push ──
      final changes = await collectChanges(isar, since: settings.lastSyncAt, forCloud: true);
      var pushed = 0, conflicts = 0, warnings = 0;
      for (final name in cloudPushOrder) {
        final rows = changes.collections[name] ?? const [];
        for (var i = 0; i < rows.length; i += cloudChunkSize) {
          final chunk = rows.sublist(i, i + cloudChunkSize > rows.length ? rows.length : i + cloudChunkSize);
          final r = await client.post<Map<String, dynamic>>(
            '/sync/push',
            data: {
              // Lets the server answer a repeat of this exact request from
              // its record instead of re-applying it.
              'batchId': IdHelpers.newUuid(),
              'collections': {name: chunk},
            },
            options: options,
          );
          final body = r.data ?? const {};
          conflicts += (body['conflicts'] as List? ?? const []).length;
          warnings += (body['warnings'] as List? ?? const []).length;
          for (final c in body['conflicts'] as List? ?? const []) {
            debugPrint('[Sync] refused by cloud: $c');
          }
          pushed += chunk.length;
        }
      }
      // Refused records are marked synced too, so one bad record can't
      // block the queue forever; the conflict count is shown to the user.
      await _markSynced(isar, changes);

      // ── Pull ──
      var cursor = settings.cloudCursor;
      var pulled = 0;
      Map<String, dynamic>? shop;
      for (var page = 0; page < 50; page++) {
        final response = await client.get<Map<String, dynamic>>(
          '/sync/pull',
          queryParameters: {'cursor': cursor},
          options: options,
        );
        final data = response.data ?? const {};
        final remote = <String, List<Map<String, dynamic>>>{
          for (final name in pulledCollections)
            name: [
              for (final r in data[name] as List? ?? const [])
                Map<String, dynamic>.from(r as Map)
            ],
        };
        pulled += await applyRemote(isar, remote);
        shop = data['shop'] is Map ? Map<String, dynamic>.from(data['shop'] as Map) : shop;
        cursor = data['cursor'] as String? ?? cursor;
        // Saved after every page, so a dropped connection resumes here.
        await isar.writeTxn(() async {
          final s = await isar.storeSettings.get(1);
          if (s != null) {
            s.cloudCursor = cursor;
            await isar.storeSettings.put(s);
          }
        });
        if (data['hasMore'] != true) break;
      }

      await isar.writeTxn(() async {
        final s = await isar.storeSettings.get(1);
        if (s == null) return;
        if (shop != null) _applyShop(s, shop);
        s.lastSyncAt = now;
        await isar.storeSettings.put(s);
      });
      return SyncResult(
          pushed: pushed, pulled: pulled, at: now, conflicts: conflicts, warnings: warnings);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      final message = status == 401
          ? 'This till is no longer connected to the cloud. Sign in again in Settings → Integrations.'
          : (body is Map ? body['message']?.toString() : null) ??
              'Could not reach ShopPOS Cloud. Will retry automatically.';
      debugPrint('[Sync] cloud: $message (${e.type})');
      return SyncResult(pushed: 0, pulled: 0, at: now, error: message, unauthorized: status == 401);
    } catch (e, st) {
      debugPrint('[Sync] cloud failed: $e\n$st');
      return SyncResult(pushed: 0, pulled: 0, at: now, error: 'Sync failed: $e');
    }
  }

  /// Applies the cloud shop's settings when they changed online.
  static void _applyShop(StoreSettings s, Map<String, dynamic> shop) {
    final updated = _date(shop['updatedAt']);
    if (updated == null ||
        (s.cloudShopUpdatedAt != null && !updated.isAfter(s.cloudShopUpdatedAt!))) {
      return;
    }
    s
      ..cloudShopUpdatedAt = updated
      ..cloudShopName = shop['name'] as String? ?? s.cloudShopName
      ..storeName = shop['name'] as String? ?? s.storeName
      ..currency = shop['currency'] as String? ?? s.currency
      ..vatRate = _num(shop['vatRate']) ?? s.vatRate
      ..pricesIncludeTax = shop['pricesIncludeTax'] as bool? ?? s.pricesIncludeTax;
    final extra = shop['settings'];
    if (extra is Map) {
      s
        ..storePhone = extra['storePhone'] as String? ?? s.storePhone
        ..storeAddress = extra['storeAddress'] as String? ?? s.storeAddress
        ..taxId = extra['taxId'] as String? ?? s.taxId
        ..receiptFooter = extra['receiptFooter'] as String? ?? s.receiptFooter
        ..enableCash = extra['enableCash'] as bool? ?? s.enableCash
        ..enableCard = extra['enableCard'] as bool? ?? s.enableCard
        ..enableMoMo = extra['enableMoMo'] as bool? ?? s.enableMoMo
        ..enableQr = extra['enableQr'] as bool? ?? s.enableQr;
    }
  }

  /// Fires when records that sync are written locally.
  static List<Stream<void>> localChangeStreams(Isar isar) => [
        isar.sales.watchLazy(),
        isar.stockMovements.watchLazy(),
        isar.products.watchLazy(),
        isar.batchs.watchLazy(),
        isar.expenses.watchLazy(),
        isar.appUsers.watchLazy(),
      ];

  /// Number of local records waiting to be synced.
  static Future<int> pendingCount(Isar isar) async {
    final counts = await Future.wait([
      isar.sales.filter().isSyncedEqualTo(false).count(),
      isar.stockMovements.filter().isSyncedEqualTo(false).count(),
      isar.products.filter().isSyncedEqualTo(false).count(),
      isar.batchs.filter().isSyncedEqualTo(false).count(),
      isar.expenses.filter().isSyncedEqualTo(false).count(),
      isar.appUsers.filter().isSyncedEqualTo(false).count(),
      isar.shifts.filter().isSyncedEqualTo(false).count(),
    ]);
    return counts.fold<int>(0, (s, c) => s + c);
  }

  /// Queues every local record for upload (after connecting to the cloud,
  /// so the shop's history goes up once). Safe: the cloud stores each
  /// record once however often it is sent.
  static Future<void> markAllUnsynced(Isar isar) async {
    await isar.writeTxn(() async {
      Future<void> all<T>(IsarCollection<T> col, void Function(T) set) async {
        final rows = await col.where().findAll();
        for (final r in rows) {
          set(r);
        }
        await col.putAll(rows);
      }

      await all<Product>(isar.products, (r) => r.isSynced = false);
      await all<Batch>(isar.batchs, (r) => r.isSynced = false);
      await all<Sale>(isar.sales, (r) => r.isSynced = false);
      await all<StockMovement>(isar.stockMovements, (r) => r.isSynced = false);
      await all<Expense>(isar.expenses, (r) => r.isSynced = false);
      await all<Shift>(isar.shifts, (r) => r.isSynced = false);
      await all<AppUser>(isar.appUsers, (r) => r.isSynced = false);
    });
  }

  /// Checks that [baseUrl] is a ShopPOS sync server that accepts [apiKey].
  /// Returns null if it is, or what's wrong.
  static Future<String?> testServer(String baseUrl, String apiKey, {Dio? dio}) async {
    final client = dio ??
        Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (_) => true,
        ));
    try {
      final r = await client.get<Object>('/sync/pull',
          queryParameters: {'since': DateTime.now().toUtc().toIso8601String()},
          options: Options(headers: {'x-api-key': apiKey, 'x-device-id': 'connection-test'}));
      final body = r.data;
      if (r.statusCode == 200 && body is Map && body['success'] == true) return null;
      if (r.statusCode == 401) return 'The sync server rejected the key.';
      if (r.statusCode == 404 || r.statusCode == 413 || body is! Map) {
        return 'That address is not a ShopPOS sync server (is it the payment server?).';
      }
      return (body['message'] as String?) ?? 'The sync server answered HTTP ${r.statusCode}.';
    } on DioException {
      return 'Could not reach the sync server.';
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // Pull: merging other devices' records
  // ════════════════════════════════════════════════════════════════════

  /// Merges records pulled from the server in one transaction. Returns how
  /// many local records were created or changed.
  static Future<int> applyRemote(
      Isar isar, Map<String, List<Map<String, dynamic>>> remote) async {
    var changed = 0;
    List<Map<String, dynamic>> rows(String name) => remote[name] ?? const [];

    await isar.writeTxn(() async {
      changed += await _applyProducts(isar, rows('products'));
      final users = await _applyUsers(isar, rows('users'));
      changed += users;
      changed += await _applyBatches(isar, rows('batches'));
      changed += await _applySales(isar, rows('sales'));
      changed += await _applySaleItems(isar, rows('saleItems'));
      changed += await _applyMovements(isar, rows('stockMovements'));
      changed += await _applyExpenses(isar, rows('expenses'));
    });
    return changed;
  }

  /// Back-compat entry point for catalog-only merges (used by tests).
  @visibleForTesting
  static Future<int> applyRemoteProducts(Isar isar, List<Map<String, dynamic>> remote) =>
      applyRemote(isar, {'products': remote});

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
  static double? _num(Object? v) => (v as num?)?.toDouble();

  /// True if the remote copy is newer than the local one.
  static bool _remoteWins(DateTime? local, Object? remoteUpdatedAt) {
    if (local == null) return true;
    final remote = _date(remoteUpdatedAt);
    return remote != null && remote.isAfter(local);
  }

  static Future<int> _applyProducts(Isar isar, List<Map<String, dynamic>> rows) async {
    var changed = 0;
    for (final r in rows) {
      final uuid = r['uuid'] as String?;
      if (uuid == null) continue;
      var product = await isar.products.filter().uuidEqualTo(uuid).findFirst();
      if (product != null && !_remoteWins(product.updatedAt, r['updatedAt'])) continue;
      product ??= Product()..uuid = uuid;
      product
        ..name = r['name'] as String? ?? product.name
        ..price = _num(r['price']) ?? 0
        ..category = r['category'] as String? ?? 'General'
        ..quickButtonColor = (r['quickButtonColor'] as num?)?.toInt() ?? product.quickButtonColor
        ..costPrice = _num(r['costPrice'])
        ..barcode = r['barcode'] as String?
        ..sku = r['sku'] as String?
        ..reorderLevel = (r['reorderLevel'] as num?)?.toInt() ?? 0
        ..isArchived = r['isArchived'] == true
        ..updatedAt = _date(r['updatedAt']) ?? DateTime.now()
        ..isSynced = true;
      await isar.products.put(product);
      changed++;
    }
    return changed;
  }

  /// Staff from other tills appear here. With ShopPOS Cloud their bcrypt
  /// PIN hash comes too, so they can sign in on this till; from the legacy
  /// sync server (no hash) they can't until the owner resets their PIN here.
  static Future<int> _applyUsers(Isar isar, List<Map<String, dynamic>> rows) async {
    var changed = 0;
    for (final r in rows) {
      final uuid = r['uuid'] as String?;
      if (uuid == null) continue;
      var user = await isar.appUsers.filter().uuidEqualTo(uuid).findFirst();
      if (user != null && !_remoteWins(user.updatedAt, r['updatedAt'])) continue;
      user ??= AppUser()
        ..uuid = uuid
        // Random, unguessable: no one can sign in until a PIN is set here.
        ..pinHash = HashHelpers.hashPin(IdHelpers.newUuid());
      final pinHash = r['pinHash'];
      if (pinHash is String && pinHash.startsWith(r'$2')) user.pinHash = pinHash;
      final version = (r['credentialVersion'] as num?)?.toInt();
      // A PIN reset elsewhere ends sessions here too.
      if (version != null && version > user.credentialVersion) user.credentialVersion = version;
      user
        ..name = r['name'] as String? ?? 'Staff'
        ..role = r['role'] as String? ?? 'cashier'
        ..isActive = r['isActive'] != false
        ..updatedAt = _date(r['updatedAt']) ?? DateTime.now()
        ..isSynced = true;
      await isar.appUsers.put(user);
      changed++;
    }
    return changed;
  }

  static Future<int> _localUserId(Isar isar, Object? uuid) async {
    if (uuid is! String) return 0;
    return (await isar.appUsers.filter().uuidEqualTo(uuid).findFirst())?.id ?? 0;
  }

  static Future<Product?> _localProduct(Isar isar, Object? uuid) async =>
      uuid is String ? isar.products.filter().uuidEqualTo(uuid).findFirst() : null;

  static Future<int> _applyBatches(Isar isar, List<Map<String, dynamic>> rows) async {
    var changed = 0;
    for (final r in rows) {
      final uuid = r['uuid'] as String?;
      if (uuid == null) continue;
      final product = await _localProduct(isar, r['productUuid']);
      if (product == null) continue;
      // Only new batches are created; quantity is never copied but rebuilt
      // from stock movements, and batch details don't change after restock.
      if (await isar.batchs.filter().uuidEqualTo(uuid).isNotEmpty()) continue;
      final expiry = _date(r['expiryDate']);
      if (expiry == null) continue;
      final batch = Batch()
        ..uuid = uuid
        ..productId = product.id
        ..quantity = 0
        ..expiryDate = expiry
        ..restockDate = _date(r['restockDate']) ?? DateTime.now()
        ..unitCost = _num(r['unitCost'])
        ..supplierNote = r['supplierNote'] as String?
        ..updatedAt = _date(r['updatedAt']) ?? DateTime.now()
        ..isSynced = true;
      await isar.batchs.put(batch);
      batch.product.value = product;
      await batch.product.save();
      changed++;
    }
    return changed;
  }

  static Future<int> _applySales(Isar isar, List<Map<String, dynamic>> rows) async {
    var changed = 0;
    for (final r in rows) {
      final uuid = r['uuid'] as String?;
      if (uuid == null) continue;
      var sale = await isar.sales.filter().uuidEqualTo(uuid).findFirst();
      if (sale != null && !_remoteWins(sale.updatedAt, r['updatedAt'])) continue;
      final isNew = sale == null;
      sale ??= Sale()
        ..uuid = uuid
        ..timestamp = _date(r['timestamp']) ?? DateTime.now()
        ..itemsJson = '[]';
      sale
        ..cashierId = await _localUserId(isar, r['cashierUuid'])
        ..paymentType = r['paymentType'] as String? ?? 'cash'
        ..subtotal = _num(r['subtotal'])
        ..discountAmount = _num(r['discountAmount']) ?? 0
        ..taxAmount = _num(r['taxAmount']) ?? 0
        ..taxRate = _num(r['taxRate']) ?? 0
        ..totalAmount = _num(r['totalAmount']) ?? 0
        ..amountTendered = _num(r['amountTendered'])
        ..changeDue = _num(r['changeDue']) ?? 0
        ..payments = [
          for (final p in r['payments'] as List? ?? const [])
            SalePayment()
              ..method = (p as Map)['method'] as String? ?? 'cash'
              ..amount = _num(p['amount']) ?? 0
              ..reference = p['reference'] as String?
        ]
        ..status = r['status'] as String? ?? SaleStatus.completed
        ..refundedAmount = _num(r['refundedAmount']) ?? 0
        ..refunds = [
          for (final f in r['refunds'] as List? ?? const [])
            SaleRefund()
              ..amount = _num((f as Map)['amount']) ?? 0
              ..method = f['method'] as String? ?? 'cash'
              ..at = _date(f['at'])
              ..reason = f['reason'] as String?
        ]
        ..statusReason = r['statusReason'] as String?
        ..paystackReference = r['paystackReference'] as String?
        ..momoProvider = r['momoProvider'] as String?
        ..momoPhone = r['momoPhone'] as String?
        ..updatedAt = _date(r['updatedAt']) ?? DateTime.now()
        ..isSynced = true;
      if (isNew) {
        // Two tills can't both have saved the same MoMo payment, but a
        // reconciled one might arrive twice: keep the first.
        final ref = sale.paystackReference;
        if (ref != null &&
            await isar.sales.filter().paystackReferenceEqualTo(ref).isNotEmpty()) {
          continue;
        }
      }
      await isar.sales.put(sale);
      changed++;
    }
    return changed;
  }

  static Future<int> _applySaleItems(Isar isar, List<Map<String, dynamic>> rows) async {
    var changed = 0;
    final itemsJsonDirty = <int>{};
    for (final r in rows) {
      final uuid = r['uuid'] as String?;
      final saleUuid = r['saleUuid'] as String?;
      if (uuid == null || saleUuid == null) continue;
      final sale = await isar.sales.filter().uuidEqualTo(saleUuid).findFirst();
      if (sale == null) continue;
      final product = await _localProduct(isar, r['productUuid']);
      var item = await isar.saleItems.filter().uuidEqualTo(uuid).findFirst();
      item ??= SaleItem()
        ..uuid = uuid
        ..saleId = sale.id
        ..productId = product?.id ?? -1
        ..timestamp = sale.timestamp
        ..cashierId = sale.cashierId;
      item
        ..productName = r['productName'] as String? ?? 'Item'
        ..quantity = (r['quantity'] as num?)?.toInt() ?? 0
        ..unitPrice = _num(r['unitPrice']) ?? 0
        ..unitCost = _num(r['unitCost'])
        ..discount = _num(r['discount']) ?? 0
        ..lineTotal = _num(r['lineTotal']) ?? 0
        ..refundedQty = (r['refundedQty'] as num?)?.toInt() ?? 0
        ..refundedAmount = _num(r['refundedAmount']) ?? 0;
      await isar.saleItems.put(item);
      itemsJsonDirty.add(sale.id);
      changed++;
    }
    // Keep the sale's item summary (used by history search) in step.
    for (final saleId in itemsJsonDirty) {
      final sale = await isar.sales.get(saleId);
      final items = await isar.saleItems.filter().saleIdEqualTo(saleId).findAll();
      if (sale == null) continue;
      sale.itemsJson = _itemsJson(items);
      await isar.sales.put(sale);
    }
    return changed;
  }

  static String _itemsJson(List<SaleItem> items) {
    final parts = items.map((i) => '{"productId":${i.productId},'
        '"productName":${_jsonString(i.productName)},"quantity":${i.quantity},'
        '"price":${i.unitPrice},"discount":${i.discount},"lineTotal":${i.lineTotal}}');
    return '[${parts.join(',')}]';
  }

  static String _jsonString(String s) =>
      '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';

  /// Applies each remote stock movement once, to the matching batch.
  static Future<int> _applyMovements(Isar isar, List<Map<String, dynamic>> rows) async {
    var changed = 0;
    final touchedProducts = <int>{};
    // Oldest first, so batches move through the same states as on the
    // device that made the changes.
    final sorted = [...rows]..sort((a, b) =>
        (a['timestamp'] as String? ?? '').compareTo(b['timestamp'] as String? ?? ''));
    for (final r in sorted) {
      final uuid = r['uuid'] as String?;
      if (uuid == null) continue;
      if (await isar.stockMovements.filter().uuidEqualTo(uuid).isNotEmpty()) continue;
      final product = await _localProduct(isar, r['productUuid']);
      if (product == null) continue;
      final change = (r['quantityChange'] as num?)?.toInt() ?? 0;

      Batch? batch;
      final batchUuid = r['batchUuid'];
      if (batchUuid is String) {
        batch = await isar.batchs.filter().uuidEqualTo(batchUuid).findFirst();
      }
      batch ??= await isar.batchs
          .filter()
          .productIdEqualTo(product.id)
          .sortByExpiryDateDesc()
          .findFirst();
      if (batch == null) {
        batch = Batch()
          ..uuid = batchUuid is String ? batchUuid : IdHelpers.newUuid()
          ..productId = product.id
          ..quantity = 0
          ..expiryDate = DateTime.now().add(const Duration(days: 365))
          ..restockDate = DateTime.now();
        await isar.batchs.put(batch);
        batch.product.value = product;
        await batch.product.save();
      }
      batch.quantity += change;
      await isar.batchs.put(batch);

      final saleUuid = r['saleUuid'];
      final sale = saleUuid is String
          ? await isar.sales.filter().uuidEqualTo(saleUuid).findFirst()
          : null;
      await isar.stockMovements.put(StockMovement()
        ..uuid = uuid
        ..productId = product.id
        ..batchId = batch.id
        ..quantityChange = change
        ..type = r['type'] as String? ?? StockMovementType.adjustment
        ..reason = r['reason'] as String?
        ..note = r['note'] as String?
        ..userId = await _localUserId(isar, r['userUuid'])
        ..saleId = sale?.id
        ..timestamp = _date(r['timestamp']) ?? DateTime.now()
        ..isSynced = true);
      touchedProducts.add(product.id);
      changed++;
    }
    // Re-save touched products so product watchers refresh stock figures.
    for (final id in touchedProducts) {
      final p = await isar.products.get(id);
      if (p != null) await isar.products.put(p);
    }
    return changed;
  }

  static Future<int> _applyExpenses(Isar isar, List<Map<String, dynamic>> rows) async {
    var changed = 0;
    for (final r in rows) {
      final uuid = r['uuid'] as String?;
      if (uuid == null) continue;
      var expense = await isar.expenses.filter().uuidEqualTo(uuid).findFirst();
      if (expense != null && !_remoteWins(expense.updatedAt, r['updatedAt'])) continue;
      expense ??= Expense()..uuid = uuid;
      expense
        ..amount = _num(r['amount']) ?? 0
        ..category = r['category'] as String? ?? ExpenseCategory.other
        ..description = r['description'] as String? ?? ''
        // A payout from another till's drawer isn't in this till.
        ..paidFromTill = r['paidFromTill'] == true
        ..shiftId = null
        ..userId = await _localUserId(isar, r['userUuid'])
        ..timestamp = _date(r['timestamp']) ?? DateTime.now()
        ..isDeleted = r['isDeleted'] == true
        ..updatedAt = _date(r['updatedAt']) ?? DateTime.now()
        ..isSynced = true;
      await isar.expenses.put(expense);
      changed++;
    }
    return changed;
  }

  // ════════════════════════════════════════════════════════════════════
  // Push: collecting local changes
  // ════════════════════════════════════════════════════════════════════

  @visibleForTesting
  static Future<SyncChangeSet> collectChanges(Isar isar,
      {DateTime? since, bool forCloud = false}) async {
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
    final userUuids = {
      for (final u in await isar.appUsers.where().findAll()) u.id: u.uuid,
    };
    final batchUuids = {
      for (final b in await isar.batchs.where().findAll()) b.id: b.uuid,
    };
    final saleUuids = <int, String?>{};
    Future<String?> saleUuid(int? id) async {
      if (id == null) return null;
      return saleUuids[id] ??= (await isar.sales.get(id))?.uuid;
    }

    final items = <SaleItem>[];
    for (final s in sales) {
      saleUuids[s.id] = s.uuid;
      items.addAll(await isar.saleItems.filter().saleIdEqualTo(s.id).findAll());
    }
    final settings = await isar.storeSettings.get(1);
    final device = settings?.deviceId ?? '';

    String? iso(DateTime? d) => d?.toUtc().toIso8601String();

    return SyncChangeSet(
      productIds: products.map((p) => p.id).toList(),
      batchIds: batches.map((b) => b.id).toList(),
      saleIds: sales.map((s) => s.id).toList(),
      movementIds: movements.map((m) => m.id).toList(),
      expenseIds: expenses.map((e) => e.id).toList(),
      shiftIds: shifts.map((s) => s.id).toList(),
      userIds: users.map((u) => u.id).toList(),
      stamps: {
        'products': {for (final p in products) p.id: p.updatedAt},
        'sales': {for (final s in sales) s.id: s.updatedAt},
        'expenses': {for (final e in expenses) e.id: e.updatedAt},
        'users': {for (final u in users) u.id: '${u.updatedAt}|${u.pinHash}|${u.isActive}'},
      },
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
              // For reference only: receivers rebuild quantity from movements.
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
              'cashierUuid': userUuids[s.cashierId],
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
              'uuid': i.uuid ?? '${saleUuids[i.saleId]}#${i.id}',
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
              'updatedAt': iso(saleUpdated(sales, i.saleId) ?? i.timestamp),
            }
        ],
        'stockMovements': [
          for (final m in movements)
            {
              'uuid': m.uuid,
              'productUuid': productUuids[m.productId],
              'batchUuid': batchUuids[m.batchId],
              'saleUuid': await saleUuid(m.saleId),
              'quantityChange': m.quantityChange,
              'type': m.type,
              'reason': m.reason,
              'note': m.note,
              'userUuid': userUuids[m.userId],
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
              'userUuid': userUuids[e.userId],
              'timestamp': iso(e.timestamp),
              'isDeleted': e.isDeleted,
              'updatedAt': iso(e.updatedAt ?? e.timestamp),
            }
        ],
        'shifts': [
          for (final s in shifts)
            {
              'uuid': s.uuid,
              'userUuid': userUuids[s.userId],
              'deviceId': device,
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
        // Names and roles; for the cloud also the bcrypt PIN hash (shop-wide
        // staff sign-in). Passwords never leave the device.
        'users': [
          for (final u in users)
            {
              'uuid': u.uuid,
              'name': u.name,
              'role': u.role,
              'isActive': u.isActive,
              if (forCloud && u.pinHash.startsWith(r'$2')) 'pinHash': u.pinHash,
              'updatedAt': iso(u.updatedAt ?? DateTime.now()),
            }
        ],
        'activityLogs': [
          for (final l in logs)
            {
              'uuid': '$device#${l.id}',
              'userUuid': userUuids[l.userId],
              'userName': l.userName,
              'action': l.action,
              'details': l.details,
              'timestamp': iso(l.timestamp),
            }
        ],
      },
    );
  }

  @visibleForTesting
  static DateTime? saleUpdated(List<Sale> sales, int saleId) {
    for (final s in sales) {
      if (s.id == saleId) return s.updatedAt;
    }
    return null;
  }

  static Future<void> _markSynced(Isar isar, SyncChangeSet c) async {
    await isar.writeTxn(() async {
      // A record edited while the sync was running keeps isSynced = false,
      // so the newer version goes up next time.
      Future<void> mark<T>(IsarCollection<T> col, List<int> ids, void Function(T) set,
          {String? stampKey, Object? Function(T)? stamp, int Function(T)? id}) async {
        final before = stampKey == null ? null : c.stamps[stampKey];
        final rows = (await col.getAll(ids))
            .whereType<T>()
            .where((r) => before == null || before[id!(r)] == stamp!(r))
            .toList();
        for (final r in rows) {
          set(r);
        }
        await col.putAll(rows);
      }

      await mark<Product>(isar.products, c.productIds, (r) => r.isSynced = true,
          stampKey: 'products', stamp: (r) => r.updatedAt, id: (r) => r.id);
      await mark<Batch>(isar.batchs, c.batchIds, (r) => r.isSynced = true);
      await mark<Sale>(isar.sales, c.saleIds, (r) => r.isSynced = true,
          stampKey: 'sales', stamp: (r) => r.updatedAt, id: (r) => r.id);
      await mark<StockMovement>(isar.stockMovements, c.movementIds, (r) => r.isSynced = true);
      await mark<Expense>(isar.expenses, c.expenseIds, (r) => r.isSynced = true,
          stampKey: 'expenses', stamp: (r) => r.updatedAt, id: (r) => r.id);
      await mark<Shift>(isar.shifts, c.shiftIds, (r) => r.isSynced = true);
      await mark<AppUser>(isar.appUsers, c.userIds, (r) => r.isSynced = true,
          stampKey: 'users',
          stamp: (r) => '${r.updatedAt}|${r.pinHash}|${r.isActive}',
          id: (r) => r.id);
    });
  }
}

class SyncChangeSet {
  final List<int> productIds, batchIds, saleIds, movementIds, expenseIds, shiftIds, userIds;
  final Map<String, List<Map<String, dynamic>>> collections;

  /// Version of each record when it was collected, by collection and id.
  final Map<String, Map<int, Object?>> stamps;

  SyncChangeSet({
    this.stamps = const {},
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
