/// ============================================
/// Pending MoMo Store — ShopPOS
/// ============================================
/// Persists every MoMo charge the app has sent
/// until it is resolved (sale saved, or the charge
/// declined), so a payment that is approved late,
/// or approved but not saved, is never forgotten.
///
/// Entries left here need reconciling against the
/// Paystack dashboard by their reference.
/// ============================================
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PendingMomoStatus {
  /// Charge sent; the customer had not approved it when last checked.
  awaitingApproval,

  /// Paystack confirmed the payment, but the sale could not be saved.
  paidNotSaved,
}

class PendingMomoPayment {
  final String reference;
  final double amountGhs;
  final String provider;
  final String phone;
  final int cashierId;
  final String itemsJson;
  final DateTime createdAt;
  final PendingMomoStatus status;

  const PendingMomoPayment({
    required this.reference,
    required this.amountGhs,
    required this.provider,
    required this.phone,
    required this.cashierId,
    required this.itemsJson,
    required this.createdAt,
    this.status = PendingMomoStatus.awaitingApproval,
  });

  PendingMomoPayment withStatus(PendingMomoStatus status) => PendingMomoPayment(
        reference: reference,
        amountGhs: amountGhs,
        provider: provider,
        phone: phone,
        cashierId: cashierId,
        itemsJson: itemsJson,
        createdAt: createdAt,
        status: status,
      );

  Map<String, dynamic> toJson() => {
        'reference': reference,
        'amountGhs': amountGhs,
        'provider': provider,
        'phone': phone,
        'cashierId': cashierId,
        'itemsJson': itemsJson,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
      };

  factory PendingMomoPayment.fromJson(Map<String, dynamic> json) =>
      PendingMomoPayment(
        reference: json['reference'] as String,
        amountGhs: (json['amountGhs'] as num).toDouble(),
        provider: json['provider'] as String,
        phone: json['phone'] as String,
        cashierId: json['cashierId'] as int,
        itemsJson: json['itemsJson'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        status: PendingMomoStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => PendingMomoStatus.awaitingApproval,
        ),
      );
}

class PendingMomoStore {
  PendingMomoStore._();

  static const _key = 'pending_momo_payments';

  static Future<List<PendingMomoPayment>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => PendingMomoPayment.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[PendingMomoStore] Failed to read: $e\n$st');
      return [];
    }
  }

  /// Adds [payment], replacing any entry with the same reference.
  static Future<void> save(PendingMomoPayment payment) async {
    final all = await getAll()
      ..removeWhere((p) => p.reference == payment.reference);
    await _write([...all, payment]);
  }

  static Future<void> setStatus(
      String reference, PendingMomoStatus status) async {
    final all = await getAll();
    final updated = [
      for (final p in all) p.reference == reference ? p.withStatus(status) : p,
    ];
    await _write(updated);
  }

  static Future<void> remove(String reference) async {
    final all = await getAll()..removeWhere((p) => p.reference == reference);
    await _write(all);
  }

  static Future<void> _write(List<PendingMomoPayment> payments) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(payments.map((p) => p.toJson()).toList()),
      );
    } catch (e, st) {
      debugPrint('[PendingMomoStore] Failed to write: $e\n$st');
    }
  }
}
