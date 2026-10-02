/// ============================================
/// Paystack Result Models — ShopPOS
/// ============================================
/// Plain Dart (non-Isar) models for Paystack
/// API responses. These are transient — they're
/// never persisted to the database directly;
/// only the reference and status are stored on
/// the Sale record after a successful payment.
/// ============================================
library;

// ── Charge Result ─────────────────────────────────────────────────────────────

enum PaystackChargeStatus {
  /// Customer has been sent a prompt on their phone. Poll to confirm.
  pending,

  /// Payment succeeded (unusual at charge time — possible for some providers).
  success,

  /// Charge request itself failed (bad phone, provider down, etc.).
  failed,

  /// Unknown status returned by the backend.
  unknown,
}

/// Result from [PaystackService.chargeGhanaMomo].
class PaystackChargeResult {
  /// Whether the backend HTTP call itself succeeded.
  final bool callSucceeded;

  /// The Paystack transaction reference to use for polling.
  final String? reference;

  /// Status returned by Paystack at charge initiation.
  final PaystackChargeStatus status;

  /// Human-readable message to display if the call failed.
  final String? errorMessage;

  /// The backend's error code (e.g. "validation_error", "unauthorized",
  /// "charge_failed"), when it gave one.
  final String? errorCode;

  /// True when we can't tell whether Paystack received the charge (no
  /// reply, or Paystack unreachable): the customer may still be prompted,
  /// so the payment must be checked rather than forgotten.
  final bool outcomeUnknown;

  const PaystackChargeResult({
    required this.callSucceeded,
    this.reference,
    this.status = PaystackChargeStatus.unknown,
    this.errorMessage,
    this.errorCode,
    this.outcomeUnknown = false,
  });

  factory PaystackChargeResult.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] as String?)?.toLowerCase() ?? '';
    final status = switch (rawStatus) {
      'pending' || 'send_otp' || 'send_pin' || 'pay_offline' => PaystackChargeStatus.pending,
      'success' => PaystackChargeStatus.success,
      'failed' => PaystackChargeStatus.failed,
      _ => PaystackChargeStatus.pending, // treat unknown as pending (keep polling)
    };

    return PaystackChargeResult(
      callSucceeded: json['success'] == true,
      reference: json['reference'] as String?,
      status: status,
      errorMessage: json['message'] as String?,
    );
  }

  factory PaystackChargeResult.error(String message,
      {String? code, bool outcomeUnknown = false}) {
    return PaystackChargeResult(
      callSucceeded: false,
      status: PaystackChargeStatus.failed,
      errorMessage: message,
      errorCode: code,
      outcomeUnknown: outcomeUnknown,
    );
  }
}

// ── Verify Result ─────────────────────────────────────────────────────────────

enum PaystackVerifyStatus {
  /// Payment confirmed — deduct stock and mark sale paid.
  success,

  /// Customer declined or payment failed — do not record sale.
  failed,

  /// Still waiting for customer to respond on their phone.
  pending,

  /// Transaction abandoned or expired on Paystack's side.
  abandoned,

  /// Could not reach the backend to check status. Keep checking.
  networkError,

  /// Paystack has no payment with this reference: nothing was charged.
  notFound,

  /// The backend refused the reference as malformed.
  invalidReference,

  /// The backend rejected our API key: a setup problem, not a payment
  /// result. The payment may still be approved, so it must be rechecked.
  unauthorized,

  /// Paystack reports success, but for a different amount or currency than
  /// this sale. Never recorded as a sale automatically.
  amountMismatch,

  /// Paystack or the backend had a temporary problem. Keep checking.
  gatewayError,
}

/// Result from [PaystackService.verifyTransaction].
class PaystackVerifyResult {
  final PaystackVerifyStatus status;

  /// Paystack's descriptive response, e.g. "Approved" or "Declined".
  final String? gatewayResponse;

  /// Amount in pesewas as confirmed by Paystack.
  final int? amountPesewas;

  /// Currency as confirmed by Paystack (should be GHS).
  final String? currency;

  /// Explanation from the backend for error outcomes.
  final String? message;

  const PaystackVerifyResult({
    required this.status,
    this.gatewayResponse,
    this.amountPesewas,
    this.currency,
    this.message,
  });

  /// True for outcomes that will never change: stop checking.
  bool get isFinal => switch (status) {
        PaystackVerifyStatus.success ||
        PaystackVerifyStatus.failed ||
        PaystackVerifyStatus.abandoned ||
        PaystackVerifyStatus.notFound ||
        PaystackVerifyStatus.invalidReference ||
        PaystackVerifyStatus.amountMismatch =>
          true,
        _ => false,
      };

  factory PaystackVerifyResult.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] as String?)?.toLowerCase() ?? '';
    final status = switch (rawStatus) {
      'success' => PaystackVerifyStatus.success,
      'failed' || 'reversed' => PaystackVerifyStatus.failed,
      'abandoned' => PaystackVerifyStatus.abandoned,
      'amount_mismatch' => PaystackVerifyStatus.amountMismatch,
      'not_found' => PaystackVerifyStatus.notFound,
      _ => PaystackVerifyStatus.pending,
    };

    return PaystackVerifyResult(
      status: status,
      gatewayResponse: json['gateway_response'] as String?,
      amountPesewas: (json['amount'] as num?)?.toInt(),
      currency: json['currency'] as String?,
      message: json['message'] as String?,
    );
  }

  /// Maps a non-200 reply from the backend's verify route.
  factory PaystackVerifyResult.fromError(int httpStatus, Object? body) {
    final map = body is Map ? body : const {};
    final code = map['error'] as String?;
    final message = map['message'] as String?;
    final status = switch ((httpStatus, code)) {
      (401, _) => PaystackVerifyStatus.unauthorized,
      (404, 'not_found') => PaystackVerifyStatus.notFound,
      (400, 'invalid_reference') => PaystackVerifyStatus.invalidReference,
      (400, _) => PaystackVerifyStatus.invalidReference,
      // 404 from a different server (wrong URL), 429, 5xx: temporary.
      _ => PaystackVerifyStatus.gatewayError,
    };
    return PaystackVerifyResult(status: status, message: message ?? 'HTTP $httpStatus');
  }

  factory PaystackVerifyResult.networkError() {
    return const PaystackVerifyResult(status: PaystackVerifyStatus.networkError);
  }
}
