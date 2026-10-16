/// ============================================
/// Payment Proof — ShopPOS
/// ============================================
/// How a payment on a sale was confirmed, worded
/// the same on every receipt and screen:
///   • Manual MoMo: checked by a person (who, when)
///   • Paystack MoMo: verified by the payment
///     server (its reference)
/// The two are never confused: a manual payment
/// is never described as verified by Paystack.
/// ============================================
library;

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/sales/models/sale.dart';

/// The line to show under payment [p] of [sale], or null if there is none.
String? paymentProof(Sale sale, SalePayment p) {
  if (p.method == AppConstants.paymentMomoManual) {
    // Sales from before the confirmation step: nothing was recorded.
    if (p.confirmedAt == null && p.confirmedByName == null) return null;
    final who = (p.confirmedByName ?? '').trim().isEmpty ? 'staff' : p.confirmedByName!.trim();
    final at = p.confirmedAt;
    return 'Checked manually by $who${at == null ? '' : ', ${DateHelpers.formatDateTime(at)}'}';
  }
  final isPaystack = p.method == AppConstants.paymentMomo || p.method == AppConstants.paymentMomoPaystack;
  final ref = (p.reference ?? sale.paystackReference ?? '').trim();
  if (isPaystack && (sale.paystackReference ?? '').isNotEmpty) {
    return 'Verified by Paystack · $ref';
  }
  return null;
}
