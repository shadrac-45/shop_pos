// Sync server is separate from the payment server.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shop_pos/core/services/sync_service.dart';

class _Reply implements HttpClientAdapter {
  final int status;
  final String body;
  _Reply(this.status, this.body);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async =>
      ResponseBody.fromString(body, status, headers: {
        Headers.contentTypeHeader: [body.startsWith('{') ? 'application/json' : 'text/html'],
      });

  @override
  void close({bool force = false}) {}
}

Future<String?> _test(int status, String body) {
  final dio = Dio(BaseOptions(baseUrl: 'http://x/api', validateStatus: (_) => true))
    ..httpClientAdapter = _Reply(status, body);
  return SyncService.testServer('http://x/api', 'key', dio: dio);
}

void main() {
  test('a real sync server is accepted', () async {
    expect(await _test(200, jsonEncode({'success': true, 'products': []})), isNull);
  });

  test('the payment server is not accepted as the sync server', () async {
    // The Express payment server: 404 for unknown /api routes...
    expect(await _test(404, jsonEncode({'success': false, 'error': 'not_found_route'})),
        contains('not a ShopPOS sync server'));
    // ...and the "Request body is too large" reply seen on the phone.
    expect(await _test(413, jsonEncode({'success': false, 'error': 'too_large'})),
        contains('not a ShopPOS sync server'));
    expect(await _test(404, '<html>Cannot GET</html>'), contains('not a ShopPOS sync server'));
  });

  test('a wrong key is reported as such', () async {
    expect(await _test(401, jsonEncode({'success': false})), contains('rejected the key'));
  });
}
