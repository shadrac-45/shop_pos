/// ============================================
/// App Constants — ShopPOS
/// ============================================
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppConstants {
  AppConstants._();

  // ── App Info ────────────────────────────────
  static const String appName = 'ShopPOS';
  static const String appVersion = '1.0.0';

  // ── Database ────────────────────────────────
  static const String dbName = 'shop_pos_db';

  // ── Roles ───────────────────────────────────
  static const String roleOwner = 'owner';
  static const String roleCashier = 'cashier';

  // ── Payment Types ───────────────────────────
  static const String paymentCash = 'cash';
  static const String paymentMomo = 'momo';
  static const String paymentSplit = 'split';

  // ── PIN ─────────────────────────────────────
  static const int pinLength = 4;

  // ── Expiry Thresholds (days) ────────────────
  static const int expiryUrgentDays = 7;
  static const int expirySoonDays = 30;

  // ── Currency ────────────────────────────────
  static const String currencySymbol = 'GH₵';
  static const String currencyCode = 'GHS';

  // ── Animation Durations (ms) ────────────────
  static const int animFast = 150;
  static const int animMedium = 300;
  static const int animSlow = 500;

  // ── Backend ─────────────────────────────────
  static const String backendBaseUrl = 'http://10.0.2.2:3000/api';

  // ── UI Palette (delegated to AppColors for single source of truth) ─
  static List<Color> get quickButtonPalette => AppColors.quickButtonPalette;

  // ── Demo only (in production, use hashed PINs)
  static const String defaultOwnerPin = '1234';

  // ── Paystack Ghana MoMo Payment ─────────────
  /// Payment type stored on Sale for Paystack mobile money charges.
  static const String paymentMomoPaystack = 'mobile_money';

  /// Ghana MoMo provider codes as required by Paystack Charge API.
  static const String momoProviderMtn = 'mtn';
  static const String momoProviderVodafone = 'vod';
  static const String momoProviderAirtelTigo = 'tgo';

  /// How often (seconds) the app polls the backend to check payment status.
  static const int momoPollingIntervalSec = 5;

  /// Maximum seconds to wait before declaring the payment timed out.
  static const int momoTimeoutSec = 90;
}