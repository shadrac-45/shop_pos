// ============================================
// MoMo client tests — ShopPOS
// ============================================
// How the POS reads the payment server's replies. The network is
// replaced by canned responses matching backend/src/app.js.
// ============================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shop_pos/features/sales/models/paystack_models.dart';
import 'package:shop_pos/features/sales/services/paystack_service.dart';

/// Replies with [status] and [body], or throws a connection error when
/// [status] is null. Records the last request.
class _FakeAdapter implements HttpClientAdapter {
  final int? status;
  final Object? body;
  RequestOptions? lastRequest;
  Object? lastBody;
  _FakeAdapter(this.status, [this.body]);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    lastBody = options.data;
    if (status == null) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    return ResponseBody.fromString(jsonEncode(body ?? {}), status!,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

PaystackService _service(_FakeAdapter adapter) => PaystackService(
    baseUrl: 'http://localhost:3001/api', apiKey: 'test-key-123', httpAdapter: adapter);

Future<PaystackVerifyResult> _verify(int? status, [Object? body]) =>
    _service(_FakeAdapter(status, body)).verifyStatus('shoppos_1727870000000_ab12cd34');

void main() {
  group('verify outcomes', () {
    test('success, failed, pending, amount mismatch', () async {
      final ok = await _verify(200, {'success': true, 'status': 'success', 'amount': 2550, 'currency': 'GHS'});
      expect(ok.status, PaystackVerifyStatus.success);
      expect(ok.amountPesewas, 2550);
      expect(ok.isFinal, isTrue);

      expect((await _verify(200, {'status': 'failed'})).status, PaystackVerifyStatus.failed);
      expect((await _verify(200, {'status': 'reversed'})).status, PaystackVerifyStatus.failed);
      expect((await _verify(200, {'status': 'abandoned'})).status, PaystackVerifyStatus.abandoned);

      final pending = await _verify(200, {'status': 'pending'});
      expect(pending.status, PaystackVerifyStatus.pending);
      expect(pending.isFinal, isFalse);

      final mismatch = await _verify(200, {'status': 'amount_mismatch', 'amount': 50});
      expect(mismatch.status, PaystackVerifyStatus.amountMismatch);
      expect(mismatch.isFinal, isTrue);
    });

    test('server errors are answers, not "network problems"', () async {
      final notFound = await _verify(404, {
        'success': false, 'error': 'not_found', 'status': 'not_found',
        'message': 'Paystack has no payment with this reference. Nothing was charged.',
      });
      expect(notFound.status, PaystackVerifyStatus.notFound);
      expect(notFound.isFinal, isTrue);

      final invalid = await _verify(400, {'success': false, 'error': 'invalid_reference', 'message': 'bad'});
      expect(invalid.status, PaystackVerifyStatus.invalidReference);
      expect(invalid.isFinal, isTrue);

      final unauthorized = await _verify(401, {'success': false, 'error': 'unauthorized'});
      expect(unauthorized.status, PaystackVerifyStatus.unauthorized);
      expect(unauthorized.isFinal, isFalse); // the payment itself is unknown

      final gateway = await _verify(502, {'success': false, 'error': 'paystack_error', 'message': 'Paystack down'});
      expect(gateway.status, PaystackVerifyStatus.gatewayError);
      expect(gateway.message, 'Paystack down');
      expect(gateway.isFinal, isFalse);

      // An HTML 404 from a different server on the wrong port: keep trying.
      final wrongServer = await _verify(404, '<html>Cannot GET</html>');
      expect(wrongServer.status, PaystackVerifyStatus.gatewayError);
    });

    test('no connection at all is a network error', () async {
      final r = await _verify(null);
      expect(r.status, PaystackVerifyStatus.networkError);
      expect(r.isFinal, isFalse);
    });
  });

  group('charge', () {
    Future<PaystackChargeResult> charge(_FakeAdapter a, {String? email}) => _service(a).initiateCharge(
        phone: '+233551234987', amountGhs: 25.5, provider: 'atl',
        reference: 'shoppos_1727870000000_ab12cd34', email: email);

    test('sends the API key, pesewas, provider code and optional email', () async {
      final a = _FakeAdapter(200, {'success': true, 'reference': 'r', 'status': 'pay_offline'});
      final r = await charge(a, email: ' ama@example.com ');
      expect(r.callSucceeded, isTrue);
      expect(a.lastRequest!.headers['x-api-key'], 'test-key-123');
      final body = a.lastBody as Map;
      expect(body['amount_pesewas'], 2550);
      expect(body['provider'], 'atl');
      expect(body['email'], 'ama@example.com');

      final noEmail = _FakeAdapter(200, {'success': true, 'status': 'pending'});
      await charge(noEmail);
      expect((noEmail.lastBody as Map).containsKey('email'), isFalse);
    });

    test('refusals are final; unreachable outcomes are not', () async {
      final validation = await charge(_FakeAdapter(400, {
        'success': false, 'error': 'validation_error', 'field': 'phone', 'message': 'Bad phone',
      }));
      expect(validation.callSucceeded, isFalse);
      expect(validation.outcomeUnknown, isFalse);
      expect(validation.errorMessage, 'Bad phone');

      final unauthorized = await charge(_FakeAdapter(401, {'error': 'unauthorized'}));
      expect(unauthorized.outcomeUnknown, isFalse);
      expect(unauthorized.errorMessage, contains('API key'));

      final declined = await charge(_FakeAdapter(400, {'error': 'charge_failed', 'message': 'Declined'}));
      expect(declined.outcomeUnknown, isFalse);

      // Paystack unreachable or erroring: the charge might exist, keep checking.
      expect((await charge(_FakeAdapter(504, {'error': 'paystack_unreachable'}))).outcomeUnknown, isTrue);
      expect((await charge(_FakeAdapter(502, {'error': 'paystack_error'}))).outcomeUnknown, isTrue);
      expect((await charge(_FakeAdapter(null))).outcomeUnknown, isTrue);
    });
  });
}
