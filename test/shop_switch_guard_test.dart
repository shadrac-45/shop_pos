// ============================================
// Shop Switch Guard Test — ShopPOS
// ============================================
// A till's local records belong to the shop it
// was connected to. Joining (or creating) a
// different shop must be refused before any
// network call, so Shop A's sales, stock and
// staff PINs can never be uploaded into or used
// in Shop B. Re-joining the same shop, and a
// till's first-ever connection, stay allowed.
// ============================================

import 'dart:ffi';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/services/cloud_service.dart';
import 'package:shop_pos/core/utils/id_helpers.dart';

late Isar isar;
late Directory dir;

const shopA = '11111111-1111-4111-8111-111111111111';
const shopB = '22222222-2222-4222-8222-222222222222';

Future<void> _settings({String cloudShopId = '', String cloudShopName = ''}) =>
    isar.writeTxn(() => isar.storeSettings.put(StoreSettings()
      ..deviceId = IdHelpers.newUuid()
      ..setupCompleted = true
      ..cloudShopId = cloudShopId
      ..cloudShopName = cloudShopName));

/// A Dio that records every request instead of sending it.
(Dio, List<String>) _recordingDio() {
  final calls = <String>[];
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9/api'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
    calls.add('${o.method} ${o.path}');
    h.reject(DioException(requestOptions: o, message: 'network disabled in test'));
  }));
  return (dio, calls);
}

void main() {
  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(libraries: {Abi.windowsX64: 'isar.dll'});
    } catch (_) {}
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos_shop_switch_');
    isar = await Isar.open(allSchemas, directory: dir.path, name: 'switch');
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    await dir.delete(recursive: true);
  });

  test('a till never connected to the cloud may join or create any shop', () async {
    await _settings();
    expect(await CloudService.shopSwitchBlocked(isar, targetShopId: shopB), isNull);
    expect(await CloudService.shopSwitchBlocked(isar), isNull);
  });

  test('re-joining the same shop is allowed', () async {
    await _settings(cloudShopId: shopA, cloudShopName: 'Kofi Shop');
    expect(await CloudService.shopSwitchBlocked(isar, targetShopId: shopA), isNull);
  });

  test('joining or creating a different shop is refused, naming the current one', () async {
    await _settings(cloudShopId: shopA, cloudShopName: 'Kofi Shop');
    final toB = await CloudService.shopSwitchBlocked(isar, targetShopId: shopB);
    expect(toB, contains('"Kofi Shop"'));
    expect(await CloudService.shopSwitchBlocked(isar), isNotNull, reason: 'creating a new shop');
  });

  test('disconnecting does not lift the guard', () async {
    await _settings(cloudShopId: shopA, cloudShopName: 'Kofi Shop');
    await CloudService.disconnect(isar);
    expect(await CloudService.shopSwitchBlocked(isar, targetShopId: shopB), isNotNull);
    expect(await CloudService.shopSwitchBlocked(isar, targetShopId: shopA), isNull);
  });

  test('joinShop refuses before any network call', () async {
    await _settings(cloudShopId: shopA, cloudShopName: 'Kofi Shop');
    final (dio, calls) = _recordingDio();
    await expectLater(
      CloudService.joinShop(isar, CloudLogin.failed('unused'), shopB, dio: dio),
      throwsA(isA<CloudJoinException>()),
    );
    expect(calls, isEmpty);
    expect((await isar.storeSettings.get(1))!.cloudShopId, shopA, reason: 'settings untouched');
  });

  test('createShop refuses before any network call', () async {
    await _settings(cloudShopId: shopA, cloudShopName: 'Kofi Shop');
    final (dio, calls) = _recordingDio();
    final result = await CloudService.createShop(isar,
        url: 'http://127.0.0.1:9', email: 'o@example.com', password: 'longpassword', dio: dio);
    expect(result.ok, isFalse);
    expect(result.error, contains('Kofi Shop'));
    expect(calls, isEmpty);
  });
}
