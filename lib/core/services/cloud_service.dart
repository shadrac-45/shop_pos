/// ============================================
/// Cloud Service — ShopPOS
/// ============================================
/// Identity and till registration with ShopPOS
/// Cloud (the backend's /api/auth endpoints).
///
///  • createShop: the owner creates the business
///    and its first shop from this till; the
///    till's own owner account becomes the cloud
///    owner, so local records line up.
///  • login → joinShop: someone signs in with
///    their own account (email or username +
///    password), picks one of THEIR shops, and
///    this till joins it. On a new install this
///    replaces the setup wizard: no local owner
///    and no new shop are created.
///  • passwordSignIn / pinSignIn: people signing
///    in on a till that already belongs to a
///    shop. Each person gets their own session
///    on this till (AppUser.cloudToken); their
///    changes are uploaded with it.
///  • signOut: ends that person's session.
///
/// The till stores: its device token (which
/// shop), each person's session, and their own
/// bcrypt PIN hash (offline PIN sign-in). No
/// server secret ever reaches the till.
/// ============================================
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/services/sync_service.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
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

/// A shop the signed-in person may work in.
class CloudShop {
  final String id;
  final String name;
  const CloudShop(this.id, this.name);
}

/// Result of [CloudService.login]: who signed in and their shops.
class CloudLogin {
  final String? error;
  final String? field;
  final String token;
  final Map<String, dynamic> user;
  final List<CloudShop> shops;
  final String url;
  const CloudLogin._(this.error, this.field, this.token, this.user, this.shops, this.url);
  factory CloudLogin.failed(String error, {String? field}) =>
      CloudLogin._(error, field, '', const {}, const [], '');
  bool get ok => error == null;
}

/// Result of signing in on a till.
class CloudSignIn {
  final AppUser? user;
  final String? error;

  /// True when the cloud couldn't be reached (fall back to offline PIN).
  final bool offline;

  /// True when the cloud answered "wrong credentials".
  final bool rejected;
  const CloudSignIn._(this.user, this.error, {this.offline = false, this.rejected = false});
  bool get ok => user != null;
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

  static Dio _client(String base, {Dio? dio}) =>
      dio ??
      Dio(BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (_) => true,
      ));

  static Future<StoreSettings> _settings(Isar isar) async {
    final s = await isar.storeSettings.get(1) ?? StoreSettings();
    if (s.deviceId.isEmpty) {
      s.deviceId = IdHelpers.newUuid();
      await isar.writeTxn(() => isar.storeSettings.put(s));
    }
    return s;
  }

  static String _tillName(StoreSettings s) =>
      s.storeName.isEmpty ? 'ShopPOS till' : '${s.storeName} till';

  /// Creates/updates the local copy of a cloud account and stores its
  /// session for this till. Server data wins for role/status/name.
  static Future<AppUser> _upsertUser(Isar isar, Map user,
      {String? token, String? expiresAt, String? pinHash}) async {
    final uuid = user['id'] as String;
    late AppUser local;
    await isar.writeTxn(() async {
      final existing = await isar.appUsers.filter().uuidEqualTo(uuid).findFirst();
      local = existing ??
          (AppUser()
            ..uuid = uuid
            // Unusable until a real PIN hash arrives.
            ..pinHash = HashHelpers.hashPin(IdHelpers.newUuid())
            // Older than anything the cloud sends, so pulls update it.
            ..updatedAt = DateTime.fromMillisecondsSinceEpoch(0)
            ..isSynced = true);
      local
        ..name = user['name'] as String? ?? local.name
        ..role = user['role'] as String? ?? local.role
        ..isActive = user['isActive'] != false
        ..email = user['email'] as String? ?? local.email
        ..username = user['username'] as String? ?? local.username;
      final hash = pinHash ?? user['pinHash'] as String?;
      if (hash != null && hash.startsWith(r'$2') && local.isSynced) local.pinHash = hash;
      final version = (user['credentialVersion'] as num?)?.toInt();
      if (version != null && version > local.credentialVersion) local.credentialVersion = version;
      if (token != null) {
        local
          ..cloudToken = token
          ..cloudTokenExpiresAt = DateTime.tryParse(expiresAt ?? '')?.toLocal();
      }
      await isar.appUsers.put(local);
    });
    return local;
  }

  static String _message(Response r, String fallback) {
    final d = r.data;
    return d is Map && d['message'] is String ? d['message'] as String : fallback;
  }

  // ── Create a business (first till) ────────────────────────────────────
  static Future<CloudConnectResult> createShop(
    Isar isar, {
    required String url,
    required String email,
    required String password,
    String signupCode = '',
    Dio? dio,
  }) async {
    final base = normaliseUrl(url);
    if (base.isEmpty) {
      return const CloudConnectResult.failed(
          "That address is not valid. Use your shop's address (kofis-shop.example.com) or a local one (http://192.168.1.10:3001).",
          field: 'url');
    }
    final blocked = await shopSwitchBlocked(isar);
    if (blocked != null) return CloudConnectResult.failed(blocked);
    final settings = await _settings(isar);
    final owner = await isar.appUsers.filter().roleEqualTo('owner').findFirst();
    try {
      final r = await _client(base, dio: dio).post<Object>('/auth/register-shop', data: {
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
        'device': {'id': settings.deviceId, 'name': _tillName(settings)},
      }).timeout(const Duration(seconds: 45));
      final data = r.data;
      if (data is! Map) {
        return const CloudConnectResult.failed('That address is not a ShopPOS Cloud server.', field: 'url');
      }
      if (r.statusCode != 201 && r.statusCode != 200) {
        return CloudConnectResult.failed(_message(r, 'The cloud answered HTTP ${r.statusCode}.'),
            field: data['field'] as String?);
      }
      await _saveConnection(isar, base, data, fresh: false);
      if (owner != null) {
        await _upsertUser(isar, data['user'] as Map,
            token: data['token'] as String?, expiresAt: data['expiresAt'] as String?);
      }
      return CloudConnectResult.ok((data['shop'] as Map)['name'] as String?);
    } on DioException catch (e) {
      debugPrint('[Cloud] create failed: ${e.type}');
      return const CloudConnectResult.failed(
          'Could not reach the cloud. Check the address and the internet connection.', field: 'url');
    } on TimeoutException {
      return const CloudConnectResult.failed('The cloud did not answer. Is the server running?', field: 'url');
    }
  }

  // ── Join an existing shop ─────────────────────────────────────────────
  /// Signs in with the person's own account; returns their shops.
  static Future<CloudLogin> login({
    required String url,
    required String identifier,
    required String password,
    Dio? dio,
  }) async {
    final base = normaliseUrl(url);
    if (base.isEmpty) {
      return CloudLogin.failed(
          "That address is not valid. Use your shop's address (kofis-shop.example.com) or a local one (http://192.168.1.10:3001).",
          field: 'url');
    }
    try {
      final r = await _client(base, dio: dio).post<Object>('/auth/login', data: {
        'identifier': identifier.trim(),
        'password': password,
      }).timeout(const Duration(seconds: 45));
      final data = r.data;
      if (data is! Map) return CloudLogin.failed('That address is not a ShopPOS Cloud server.', field: 'url');
      if (r.statusCode != 200) return CloudLogin.failed(_message(r, 'Sign-in failed.'));
      return CloudLogin._(
        null,
        null,
        data['token'] as String,
        Map<String, dynamic>.from(data['user'] as Map),
        [for (final s in data['shops'] as List) CloudShop(s['id'] as String, s['name'] as String)],
        base,
      );
    } on DioException {
      return CloudLogin.failed('Could not reach the cloud. Check the address and the internet connection.',
          field: 'url');
    } on TimeoutException {
      return CloudLogin.failed('The cloud did not answer. Is the server running?', field: 'url');
    }
  }

  /// Puts this till into [shopId] (one of [login]'s shops) and signs the
  /// person in on it. On a new install ([fresh]) this also completes setup:
  /// the shop's data is downloaded and no local owner is created.
  /// Returns the local account of the person, or throws a message.
  static Future<AppUser> joinShop(Isar isar, CloudLogin login, String shopId,
      {bool fresh = false, Dio? dio}) async {
    final blocked = await shopSwitchBlocked(isar, targetShopId: shopId);
    if (blocked != null) throw CloudJoinException(blocked);
    final settings = await _settings(isar);
    final client = _client(login.url, dio: dio);
    final r = await client
        .post<Object>('/auth/join-device',
            data: {
              'shopId': shopId,
              'device': {'id': settings.deviceId, 'name': _tillName(settings)},
            },
            options: Options(headers: {'authorization': 'Bearer ${login.token}'}))
        .timeout(const Duration(seconds: 45));
    final data = r.data;
    if (data is! Map || r.statusCode != 201) {
      throw CloudJoinException(data is Map ? (data['message'] as String? ?? 'Could not join the shop.') : 'Could not join the shop.');
    }
    await _saveConnection(isar, login.url, data, fresh: fresh);
    final user = await _upsertUser(isar, data['user'] as Map,
        token: data['token'] as String?, expiresAt: data['expiresAt'] as String?);
    // Download the shop now, as this person.
    final result = await SyncService.cloudSync(isar, checkConnectivity: false, signedInUserId: user.id, dio: dio);
    if (!result.ok && fresh) throw CloudJoinException(result.error ?? 'Could not download the shop.');
    return (await isar.appUsers.get(user.id))!;
  }

  /// Why this till may not join [targetShopId] (null: a shop about to be
  /// created), or null if it may.
  ///
  /// A till's local records (sales, stock, customers, staff and their PINs)
  /// belong to the shop it was connected to; [disconnect] keeps that shop's
  /// id for exactly this check. Joining any other shop would upload them
  /// into it and leave the old shop's staff able to sign in there, so it
  /// is refused. A till never connected before (its records are meant to
  /// go up) and re-joining the same shop are both fine.
  static Future<String?> shopSwitchBlocked(Isar isar, {String? targetShopId}) async {
    final s = await isar.storeSettings.get(1);
    final current = s?.cloudShopId ?? '';
    if (current.isEmpty || current == targetShopId) return null;
    final name = s!.cloudShopName.trim().isEmpty ? 'another shop' : '"${s.cloudShopName.trim()}"';
    return 'This till holds the records of $name. It can only reconnect to that shop. '
        'To use it for a different shop, back up its data (Settings → Backup & Restore), '
        'then reinstall ShopPOS and join the other shop from the welcome screen.';
  }

  static Future<void> _saveConnection(Isar isar, String base, Map data, {required bool fresh}) async {
    final shop = data['shop'] as Map;
    await isar.writeTxn(() async {
      final s = await isar.storeSettings.get(1) ?? StoreSettings();
      final switchingShop = s.cloudShopId != shop['id'];
      s
        ..cloudUrl = base
        ..cloudDeviceToken = data['deviceToken'] as String
        ..cloudDeviceCode = data['deviceCode'] as String? ?? s.cloudDeviceCode
        ..cloudShopId = shop['id'] as String
        ..cloudBusinessId = shop['businessId'] as String? ?? ''
        ..cloudShopName = shop['name'] as String? ?? '';
      if (switchingShop) {
        // Start the change feed from the beginning; a till joining another
        // shop numbers its receipts afresh under its new till code.
        s
          ..cloudCursor = ''
          ..cloudCursorScope = ''
          ..cloudShopUpdatedAt = null
          ..lastSyncAt = null
          ..receiptSeq = 0;
      }
      if (fresh) {
        // A new install joining a shop: setup comes from the cloud.
        s
          ..storeName = shop['name'] as String? ?? s.storeName
          ..settingsSynced = true
          ..setupCompleted = true;
      }
      await isar.storeSettings.put(s);
    });
    final s = await isar.storeSettings.get(1);
    // A till that already had data sends its whole history once (the cloud
    // stores each record once). A new install has nothing to send.
    if (!fresh && s != null && s.lastSyncAt == null) await SyncService.markAllUnsynced(isar);
    // Joined by an IP address? Move to the shop's own address if it has one.
    unawaited(adoptShopAddress(isar, shop));
  }

  // ── Permanent shop address ───────────────────────────────────────────
  /// When the last attempt to move to the shop's address failed (memory
  /// only): retried at most hourly, so a domain that isn't live yet costs
  /// one quick request an hour, not one per sync.
  static DateTime? _addressTriedAt;

  @visibleForTesting
  static void resetAddressRetryForTest() => _addressTriedAt = null;

  /// Moves this till to its shop's permanent address
  /// (`https://<shop>.<domain>`) once the cloud reports one, so a till that
  /// joined by IP address keeps working when that IP changes. Only after
  /// the new address answers as the same shop; otherwise nothing changes.
  static Future<void> adoptShopAddress(Isar isar, Map shop, {Dio? dio}) async {
    final url = shop['url'];
    if (url is! String || !url.startsWith('https://')) return;
    final target = normaliseUrl(url);
    if (target.isEmpty) return;
    final s = await isar.storeSettings.get(1);
    if (s == null || s.cloudUrl == target || s.cloudShopId.isEmpty || s.cloudShopId != shop['id']) return;
    final tried = _addressTriedAt;
    if (tried != null && DateTime.now().difference(tried) < const Duration(hours: 1)) return;
    _addressTriedAt = DateTime.now();
    try {
      final r = await _client(target, dio: dio).get<Object>('/shop-address').timeout(const Duration(seconds: 10));
      final data = r.data;
      final found = data is Map && data['shop'] is Map ? (data['shop'] as Map)['id'] : null;
      if (r.statusCode != 200 || found != s.cloudShopId) return;
    } on DioException {
      return;
    } on TimeoutException {
      return;
    }
    await isar.writeTxn(() async {
      final fresh = await isar.storeSettings.get(1);
      if (fresh == null || fresh.cloudShopId != shop['id']) return;
      fresh.cloudUrl = target;
      await isar.storeSettings.put(fresh);
    });
    _addressTriedAt = null;
    debugPrint('[Cloud] now using the shop address $target');
  }

  // ── Signing in on a till of the shop ──────────────────────────────────
  static Future<CloudSignIn> passwordSignIn(Isar isar,
      {required String identifier, required String password, Dio? dio}) async {
    final s = await _settings(isar);
    try {
      final r = await _client(s.cloudUrl, dio: dio).post<Object>('/auth/login', data: {
        'identifier': identifier.trim(),
        'password': password,
        'device': {'id': s.deviceId},
      }).timeout(const Duration(seconds: 20));
      final data = r.data;
      if (data is! Map) return const CloudSignIn._(null, 'Unexpected reply from the cloud.', offline: true);
      if (r.statusCode != 200) {
        return CloudSignIn._(null, _message(r, 'Sign-in failed.'), rejected: r.statusCode == 401);
      }
      final user = await _upsertUser(isar, data['user'] as Map,
          token: data['token'] as String?, expiresAt: data['expiresAt'] as String?);
      return CloudSignIn._(user, null);
    } on DioException {
      return const CloudSignIn._(null, 'No connection to the cloud. Use your PIN instead.', offline: true);
    } on TimeoutException {
      return const CloudSignIn._(null, 'No connection to the cloud. Use your PIN instead.', offline: true);
    }
  }

  /// PIN sign-in checked by the cloud (anyone allowed in this till's
  /// shop). Gives the person a session on this till and their PIN hash.
  static Future<CloudSignIn> pinSignIn(Isar isar, String pin, {Dio? dio}) async {
    final s = await _settings(isar);
    try {
      final r = await _client(s.cloudUrl, dio: dio)
          .post<Object>('/auth/pin-login',
              data: {'pin': pin}, options: Options(headers: {'x-device-token': s.cloudDeviceToken}))
          .timeout(const Duration(seconds: 12));
      final data = r.data;
      if (data is! Map) return const CloudSignIn._(null, null, offline: true);
      if (r.statusCode != 200) {
        return CloudSignIn._(null, _message(r, 'PIN not recognised.'),
            rejected: r.statusCode == 401 || r.statusCode == 429, offline: r.statusCode! >= 500);
      }
      final user = await _upsertUser(isar, data['user'] as Map,
          token: data['token'] as String?, expiresAt: data['expiresAt'] as String?);
      return CloudSignIn._(user, null);
    } on DioException {
      return const CloudSignIn._(null, null, offline: true);
    } on TimeoutException {
      return const CloudSignIn._(null, null, offline: true);
    }
  }

  /// Ends [user]'s session on this till (best effort when offline).
  static Future<void> signOut(Isar isar, AppUser user, {Dio? dio}) async {
    final token = user.cloudToken;
    await isar.writeTxn(() async {
      final u = await isar.appUsers.get(user.id);
      if (u == null) return;
      u
        ..cloudToken = null
        ..cloudTokenExpiresAt = null;
      await isar.appUsers.put(u);
    });
    if (token == null) return;
    final s = await _settings(isar);
    try {
      await _client(s.cloudUrl, dio: dio)
          .post<Object>('/auth/logout', options: Options(headers: {'authorization': 'Bearer $token'}))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline: the session simply expires on the server.
    }
  }

  static bool isConnected(StoreSettings s) => s.cloudDeviceToken.isNotEmpty && s.cloudUrl.isNotEmpty;

  /// Whether [user] has a usable session on this till.
  static bool hasSession(AppUser? user) =>
      user != null &&
      (user.cloudToken ?? '').isNotEmpty &&
      (user.cloudTokenExpiresAt == null || user.cloudTokenExpiresAt!.isAfter(DateTime.now()));

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
      for (final u in await isar.appUsers.where().findAll()) {
        u
          ..cloudToken = null
          ..cloudTokenExpiresAt = null;
        await isar.appUsers.put(u);
      }
    });
  }
}

class CloudJoinException implements Exception {
  final String message;
  CloudJoinException(this.message);
  @override
  String toString() => message;
}
