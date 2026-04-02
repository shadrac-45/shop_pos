/// ============================================
/// Sync Helper — MongoDB Sync Scaffold
/// ============================================
/// Handles syncing local Isar data to a remote
/// MongoDB instance via Dio.
/// Note: Endpoints and auth logic are placeholders
/// to be updated once backend details are available.
/// ============================================
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:isar/isar.dart';

class SyncHelper {
  SyncHelper._();

  // TODO: Replace with your actual backend URL
  static const String _baseUrl = 'http://10.0.2.2:3000/api';

  // Use a singleton Dio instance with base options
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      // headers: {'Authorization': 'Bearer YOUR_TOKEN_HERE'},
    ),
  );

  /// Check if the device has internet connectivity.
  static Future<bool> hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// Sync unsynced sales to remote MongoDB server.
  static Future<void> syncSales(Isar isar) async {
    final connected = await hasInternet();
    if (!connected) return;

    try {
      // 1. Query unsynced sales from Isar
      final unsyncedSales = await isar.sales.filter().isSyncedEqualTo(false).findAll();

      if (unsyncedSales.isEmpty) {
        print('[SyncHelper] No offline sales to sync.');
        return;
      }

      print('[SyncHelper] Attempting to sync ${unsyncedSales.length} sales...');

      // 2. Map sales to JSON payloads
      final payload = unsyncedSales.map((sale) {
        return {
          'localId': sale.id,
          'timestamp': sale.timestamp.toIso8601String(),
          'cashierName': sale.cashierName,
          'totalAmount': sale.totalAmount,
          'paymentType': sale.paymentType,
          'items': sale.items, // Already parsed as List<Map>
        };
      }).toList();

      // 3. POST batch to remote API
      final response = await _dio.post('/sales/sync', data: payload);

      // 4. Mark as synced on successful response
      if (response.statusCode == 200 || response.statusCode == 201) {
        await isar.writeTxn(() async {
          for (final sale in unsyncedSales) {
            sale.isSynced = true;
            await isar.sales.put(sale);
          }
        });
        print('[SyncHelper] Successfully synced ${unsyncedSales.length} sales.');
      } else {
        print('[SyncHelper] Sync failed with status: ${response.statusCode}');
      }
    } catch (e) {
      print('[SyncHelper] Error during syncSales: $e');
    }
  }

  /// Pull product updates from server.
  static Future<void> pullUpdates(Isar isar) async {
    final connected = await hasInternet();
    if (!connected) return;

    try {
      print('[SyncHelper] Pulling product updates...');

      // TODO: Replace with your actual GET endpoint
      // You may want to send a lastSyncTimestamp to only pull new records.
      final response = await _dio.get('/products');

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['products'] ?? [];

        await isar.writeTxn(() async {
          for (final _ in data) {
            // Note: This expects matching fields. ObjectId from Mongo will need
            // to map to Isar `Id`.
            // Example of inserting/updating a product:
            /*
            final product = Product()
              ..name = item['name']
              ..price = (item['price'] as num).toDouble()
              ..category = item['category']
              ..barcode = item['barcode'];
            await isar.products.put(product);
            */
          }
        });

        print('[SyncHelper] Pulled ${data.length} product updates.');
      }
    } catch (e) {
      print('[SyncHelper] Error during pullUpdates: $e');
    }
  }
}
