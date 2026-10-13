// ============================================
// Cloud Session Test — ShopPOS
// ============================================
// After a PIN sign-in on a cloud till, several
// parts of the app (sign-in, the sync watcher,
// the alerts summary, notifications) each want
// the person's cloud session at the same moment.
// They must share ONE request to the cloud, not
// send one each.
// ============================================

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding fakes all HTTP; this test talks to a real local server.
  HttpOverrides.global = null;

  late Isar isar;
  late Directory dir;
  late HttpServer cloud;
  late ProviderContainer container;
  var pinLogins = 0;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(libraries: {Abi.windowsX64: 'isar.dll'});
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    pinLogins = 0;
    // A slow cloud that is briefly unavailable: every request overlaps
    // the others, and none of them hands out a session.
    cloud = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    cloud.listen((req) async {
      if (req.uri.path.endsWith('/auth/pin-login')) pinLogins++;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      req.response
        ..statusCode = 503
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': false, 'error': 'unavailable', 'message': 'Try again.'}));
      await req.response.close();
    });

    dir = await Directory.systemTemp.createTemp('pos_cloud_session_');
    isar = await Isar.open(allSchemas, directory: dir.path, name: 'cloud_session');
    await isar.writeTxn(() async {
      await isar.storeSettings.put(StoreSettings()
        ..deviceId = 'till-1'
        ..setupCompleted = true
        ..cloudUrl = 'http://127.0.0.1:${cloud.port}/api'
        ..cloudDeviceToken = 'device-token'
        ..cloudShopId = '11111111-1111-4111-8111-111111111111');
      await isar.appUsers.put(AppUser()
        ..name = 'Kofi'
        ..role = AppConstants.roleCashier
        ..pinHash = HashHelpers.hashPin('7392'));
    });
    container = ProviderContainer(overrides: [isarProvider.overrideWithValue(isar)]);
  });

  tearDown(() async {
    container.dispose();
    await cloud.close(force: true);
    await isar.close(deleteFromDisk: true);
    await dir.delete(recursive: true);
  });

  test('everyone asking for the session at once shares one request', () async {
    final auth = container.read(currentUserProvider.notifier);
    // Signs in on the till and starts fetching the cloud session.
    expect(await auth.login('7392'), LoginResult.success);
    // The sync watcher, the alerts summary and notifications ask too.
    final results = await Future.wait([
      auth.ensureCloudSession(),
      auth.ensureCloudSession(),
      auth.ensureCloudSession(),
    ]);
    expect(results, everyElement(isFalse), reason: 'the cloud gave no session');
    expect(pinLogins, 1);
  });

  test('a later attempt, after the first one finished, asks again', () async {
    final auth = container.read(currentUserProvider.notifier);
    expect(await auth.login('7392'), LoginResult.success);
    await auth.ensureCloudSession();
    expect(pinLogins, 1);
    // The cloud was unavailable, so the PIN is kept and a retry is allowed.
    await auth.ensureCloudSession();
    expect(pinLogins, 2);
  });
}
