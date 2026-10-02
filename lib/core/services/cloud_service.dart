/// ============================================
/// Cloud Service — ShopPOS
/// ============================================
/// Connects this till to ShopPOS Cloud (the
/// backend's /api/auth endpoints):
///
///  • createShop: the owner creates the cloud
///    shop from this till. The till's own owner
///    account (id and bcrypt PIN hash) becomes
///    the cloud owner, so local records line up.
///  • signIn: the owner signs in to an existing
///    cloud shop to add this till to it.
///
/// Either way the server returns a device token
/// for this till, stored in StoreSettings. The
/// owner's password is sent once over the
/// connection and never stored; the short-lived
/// session token is signed out straight away.
/// No server secret (Paystack key, database
/// password) is ever sent to the till.
/// ============================================
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/services/sync_service.dart';
import 'package:shop_pos/core/utils/id_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';

class CloudConnectResult {
  final String? error;
  final String? field;
  final String? shopName;
  const CloudConnectResult.ok(this.shopName)
      : error = null,
        field = null;
  const CloudConnectResult.failed(this.error, {this.field}) : shopName = null;
  bool get ok => error == null;
}

class CloudService {
  CloudService._();

  /// Normalises what the owner typed into an API base URL ending in /api.
  /// Forgives common typing slips ("http:host", spaces, "Http://",
  /// trailing slashes). Returns '' if it still isn't a usable address.
  static String normaliseUrl(String raw) {
    var url = raw.replaceAll(RegExp(r'\s+'), '');
    final scheme = RegExp(r'^(https?):/*', caseSensitive: false).firstMatch(url);
    if (scheme != null) {
      url = '${scheme.group(1)!.toLowerCase()}://${url.substring(scheme.end)}';
    } else if (url.isNotEmpty) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isEmpty) return url;
    if (!url.endsWith('/api')) url = '$url/api';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || !uri.host.contains(RegExp(r'[.:]|localhost'))) {
      return '';
    }
    return url;
  }

  /// True for addresses that are only safe on a local network.
  static bool isInsecure(String url) =>
      url.startsWith('http://') &&
      !RegExp(r'^http://(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)')
          .hasMatch(url);

  static Future<CloudConnectResult> createShop(
    Isar isar, {
    required String url,
    required String email,
    required String password,
    String signupCode = '',
    Dio? dio,
  }) async {
    final settings = await isar.storeSettings.get(1) ?? StoreSettings();
    final owner = await isar.appUsers.filter().roleEqualTo('owner').findFirst();
    return _connect(
      isar,
      url: url,
      path: '/auth/register-shop',
      dio: dio,
      body: {
        'shopName': settings.storeName.isEmpty ? 'My Shop' : settings.storeName,
        'ownerName': owner?.name ?? 'Owner',
        'email': email.trim(),
        'password': password,
        if (signupCode.trim().isNotEmpty) 'signupCode': signupCode.trim(),
        if (owner?.uuid != null) 'ownerId': owner!.uuid,
        if (owner != null && owner.pinHash.startsWith(r'$2')) 'ownerPinHash': owner.pinHash,
        'vatRate': settings.vatRate,
        'currency': settings.currency,
        'pricesIncludeTax': settings.pricesIncludeTax,
      },
    );
  }

  static Future<CloudConnectResult> signIn(
    Isar isar, {
    required String url,
    required String email,
    required String password,
    Dio? dio,
  }) =>
      _connect(isar,
          url: url,
          path: '/auth/login',
          dio: dio,
          body: {'email': email.trim(), 'password': password});

  static Future<CloudConnectResult> _connect(
    Isar isar, {
    required String url,
    required String path,
    required Map<String, dynamic> body,
    Dio? dio,
  }) async {
    final base = normaliseUrl(url);
    if (base.isEmpty) {
      return const CloudConnectResult.failed(
          'That address is not valid. Example: http://192.168.1.10:3001',
          field: 'url');
    }

    var settings = await isar.storeSettings.get(1) ?? StoreSettings();
    if (settings.deviceId.isEmpty) settings.deviceId = IdHelpers.newUuid();

    final client = dio ??
        Dio(BaseOptions(
          baseUrl: base,
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (_) => true,
        ));
    try {
      final r = await client.post<Object>(path, data: {
        ...body,
        'device': {
          'id': settings.deviceId,
          'name': settings.storeName.isEmpty ? 'ShopPOS till' : '${settings.storeName} till',
        },
      }).timeout(const Duration(seconds: 45));
      final data = r.data;
      if (data is! Map) {
        return const CloudConnectResult.failed(
            'That address is not a ShopPOS Cloud server.', field: 'url');
      }
      if (r.statusCode != 200 && r.statusCode != 201) {
        return CloudConnectResult.failed(
            data['message'] as String? ?? 'The cloud answered HTTP ${r.statusCode}.',
            field: data['field'] as String?);
      }
      final deviceToken = data['deviceToken'] as String?;
      final shop = data['shop'] as Map?;
      if (deviceToken == null || shop == null) {
        return const CloudConnectResult.failed('The cloud did not register this till.');
      }

      // Only the device token is kept; the person's session isn't needed.
      final session = data['token'] as String?;
      if (session != null) {
        client
            .post<Object>('/auth/logout',
                options: Options(headers: {'authorization': 'Bearer $session'}))
            .catchError((Object _) => Response<Object>(requestOptions: RequestOptions()));
      }

      final switchingShop = settings.cloudShopId != shop['id'];
      settings = await isar.storeSettings.get(1) ?? settings;
      settings
        ..deviceId = settings.deviceId.isEmpty ? IdHelpers.newUuid() : settings.deviceId
        ..cloudUrl = base
        ..cloudDeviceToken = deviceToken
        ..cloudShopId = shop['id'] as String
        ..cloudShopName = shop['name'] as String? ?? '';
      if (switchingShop) {
        // Start the change feed from the beginning and send this till's
        // whole history once (the cloud keeps each record once).
        settings
          ..cloudCursor = ''
          ..cloudShopUpdatedAt = null
          ..lastSyncAt = null;
      }
      await isar.writeTxn(() => isar.storeSettings.put(settings));
      if (switchingShop) await SyncService.markAllUnsynced(isar);
      return CloudConnectResult.ok(settings.cloudShopName);
    } on DioException catch (e) {
      debugPrint('[Cloud] connect failed: ${e.type}');
      return const CloudConnectResult.failed(
          'Could not reach the cloud. Check the address and the internet connection.',
          field: 'url');
    } on TimeoutException {
      return const CloudConnectResult.failed(
          'The cloud did not answer. Check the address and that the server is running.',
          field: 'url');
    } catch (e) {
      // Never leave the button spinning.
      debugPrint('[Cloud] connect failed: $e');
      return CloudConnectResult.failed('Could not connect: $e', field: 'url');
    }
  }

  /// Forgets the cloud connection on this till. Local data is kept.
  static Future<void> disconnect(Isar isar) async {
    await isar.writeTxn(() async {
      final s = await isar.storeSettings.get(1);
      if (s == null) return;
      s
        ..cloudDeviceToken = ''
        ..cloudCursor = ''
        ..cloudShopUpdatedAt = null;
      await isar.storeSettings.put(s);
    });
  }
}
