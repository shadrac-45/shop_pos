// ============================================
// Shop Address Test — ShopPOS
// ============================================
// A till that joined by an IP address moves to
// its shop's permanent address (https://<shop>.
// <domain>) once the cloud reports one, so it
// keeps working when that IP changes. It moves
// only when the new address answers as the SAME
// shop; anything else leaves the till as it was.
// ============================================

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/services/cloud_service.dart';

late Isar isar;
late Directory dir;

const shopA = '11111111-1111-4111-8111-111111111111';
const shopB = '22222222-2222-4222-8222-222222222222';
const lanUrl = 'http://192.168.100.150:3001/api';
const shopUrl = 'https://kofis-shop.pos.example.com';

/// A Dio that answers GET /shop-address with [answer] (or fails), and
/// records what was asked.
(Dio, List<String>) _cloud({Map<String, dynamic>? answer, bool fail = false}) {
  final calls = <String>[];
  final dio = Dio(BaseOptions(baseUrl: '$shopUrl/api', validateStatus: (_) => true));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
    calls.add('${o.method} ${o.uri}');
    if (fail) {
      h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionError));
      return;
    }
    h.resolve(Response(requestOptions: o, statusCode: 200, data: {'success': true, 'shop': answer}));
  }));
  return (dio, calls);
}

Future<String> _url() async => (await isar.storeSettings.get(1))!.cloudUrl;

void main() {
  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(libraries: {Abi.windowsX64: 'isar.dll'});
    } catch (_) {}
  });

  setUp(() async {
    CloudService.resetAddressRetryForTest();
    dir = await Directory.systemTemp.createTemp('pos_shop_address_');
    isar = await Isar.open(allSchemas, directory: dir.path, name: 'addr');
    await isar.writeTxn(() => isar.storeSettings.put(StoreSettings()
      ..deviceId = 'till-1'
      ..setupCompleted = true
      ..cloudUrl = lanUrl
      ..cloudShopId = shopA
      ..cloudShopName = "Kofi's Shop"));
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    await dir.delete(recursive: true);
  });

  test('moves to the shop address once it answers as the same shop', () async {
    final (dio, calls) = _cloud(answer: {'id': shopA, 'name': "Kofi's Shop"});
    await CloudService.adoptShopAddress(isar, {'id': shopA, 'url': shopUrl}, dio: dio);
    expect(calls, ['GET $shopUrl/api/shop-address']);
    expect(await _url(), '$shopUrl/api');
  });

  test('stays put when the address answers as another shop', () async {
    final (dio, _) = _cloud(answer: {'id': shopB, 'name': 'Someone else'});
    await CloudService.adoptShopAddress(isar, {'id': shopA, 'url': shopUrl}, dio: dio);
    expect(await _url(), lanUrl);
  });

  test("stays put when the address doesn't answer, and doesn't retry it on every sync", () async {
    final (dio, calls) = _cloud(fail: true);
    await CloudService.adoptShopAddress(isar, {'id': shopA, 'url': shopUrl}, dio: dio);
    await CloudService.adoptShopAddress(isar, {'id': shopA, 'url': shopUrl}, dio: dio);
    expect(await _url(), lanUrl);
    expect(calls, hasLength(1), reason: 'retried at most hourly');
  });

  test('ignores no address, plain-HTTP addresses and other shops', () async {
    final (dio, calls) = _cloud(answer: {'id': shopA});
    await CloudService.adoptShopAddress(isar, {'id': shopA, 'url': null}, dio: dio);
    await CloudService.adoptShopAddress(isar, {'id': shopA, 'url': 'http://kofis-shop.pos.example.com'}, dio: dio);
    await CloudService.adoptShopAddress(isar, {'id': shopB, 'url': shopUrl}, dio: dio);
    expect(calls, isEmpty);
    expect(await _url(), lanUrl);
  });

  test('a bare shop address typed at sign-in becomes its HTTPS API address', () {
    expect(CloudService.normaliseUrl('kofis-shop.pos.example.com'), '$shopUrl/api');
    expect(CloudService.normaliseUrl(' Kofis-Shop.pos.example.com/ '), 'https://Kofis-Shop.pos.example.com/api');
  });
}
