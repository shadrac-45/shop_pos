/// ============================================
/// Payment Gateway Interface — ShopPOS
/// ============================================
/// Abstract contract for payment processing.
/// Decouples UI and business logic from specific
/// gateways (e.g. Paystack, Hubtel).
/// ============================================
library;

import 'package:shop_pos/features/sales/models/paystack_models.dart';

abstract class PaymentGateway {
  /// Initiates a Mobile Money charge.
  /// [email] is the customer's email if they gave one; the backend uses
  /// the shop's configured address otherwise.
  Future<PaystackChargeResult> initiateCharge({
    required String phone,
    required double amountGhs,
    required String provider,
    required String reference,
    String? email,
  });

  /// Polls or checks if a transaction has been approved.
  Future<PaystackVerifyResult> verifyStatus(String reference);

  /// Health check endpoint verification to validate backend connectivity immediately.
  Future<bool> testConnection([String? targetUrl]);
}
