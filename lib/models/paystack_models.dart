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

  const PaystackChargeResult({
    required this.callSucceeded,
    this.reference,
    this.status = PaystackChargeStatus.unknown,
    this.errorMessage,
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

  factory PaystackChargeResult.error(String message) {
    return PaystackChargeResult(
      callSucceeded: false,
      status: PaystackChargeStatus.failed,
      errorMessage: message,
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

  /// Could not reach the backend to check status.
  networkError,
}

/// Result from [PaystackService.verifyTransaction].
class PaystackVerifyResult {
  final PaystackVerifyStatus status;

  /// Paystack's descriptive response, e.g. "Approved" or "Declined".
  final String? gatewayResponse;

  /// Amount in pesewas as confirmed by Paystack.
  final int? amountPesewas;

  const PaystackVerifyResult({
    required this.status,
    this.gatewayResponse,
    this.amountPesewas,
  });

  factory PaystackVerifyResult.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] as String?)?.toLowerCase() ?? '';
    final status = switch (rawStatus) {
      'success' => PaystackVerifyStatus.success,
      'failed' => PaystackVerifyStatus.failed,
      'abandoned' => PaystackVerifyStatus.abandoned,
      _ => PaystackVerifyStatus.pending,
    };

    return PaystackVerifyResult(
      status: status,
      gatewayResponse: json['gateway_response'] as String?,
      amountPesewas: (json['amount'] as num?)?.toInt(),
    );
  }

  factory PaystackVerifyResult.networkError() {
    return const PaystackVerifyResult(status: PaystackVerifyStatus.networkError);
  }
}
