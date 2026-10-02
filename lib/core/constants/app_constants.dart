/// ============================================
/// App Constants — ShopPOS
/// ============================================
library;

import 'package:flutter/material.dart';

import 'package:shop_pos/core/theme/app_colors.dart';

class AppConstants {
  AppConstants._();

  // ── App Info ────────────────────────────────
  static const String appName = 'ShopPOS';
  /// Keep in step with `version:` in pubspec.yaml.
  static const String appVersion = '1.3.0';

  // ── Database ────────────────────────────────
  static const String dbName = 'shop_pos_db';

  // ── Roles ───────────────────────────────────
  static const String roleOwner = 'owner';
  static const String roleCashier = 'cashier';
  static const String roleManager = 'manager';
  static const String roleStockClerk = 'stock_clerk';

  static const List<String> staffRoles = [
    roleCashier,
    roleManager,
    roleStockClerk,
  ];

  static String roleLabel(String role) => switch (role) {
        roleOwner => 'Owner',
        roleManager => 'Manager',
        roleStockClerk => 'Stock Clerk',
        _ => 'Cashier',
      };

  // ── Payment Types ───────────────────────────
  static const String paymentCash = 'cash';
  static const String paymentMomo = 'momo';
  static const String paymentSplit = 'split';
  static const String paymentCard = 'card';
  static const String paymentQr = 'qr';

  static String paymentLabel(String method) => switch (method) {
        paymentCash => 'Cash',
        paymentMomo || paymentMomoPaystack => 'MoMo',
        paymentCard => 'Card',
        paymentQr => 'QR',
        paymentSplit => 'Split',
        _ => method,
      };

  // ── PIN ─────────────────────────────────────
  static const int pinLength = 4;
  static const int minPinLength = 4;
  static const int maxPinLength = 6;

  /// PINs seeded on a fresh install. They are publicly known, so login
  /// with them is refused and they can't be chosen as a new PIN.
  static const List<String> defaultPins = ['1234', '0000'];

  // ── Expiry Thresholds (days) ────────────────
  static const int expiryUrgentDays = 7;
  static const int expirySoonDays = 30;

  // ── Currency ────────────────────────────────
  /// Defaults only; the store's own currency comes from StoreSettings via
  /// CurrencyHelpers.
  static const String currencySymbol = 'GH₵';
  static const String currencyCode = 'GHS';

  // ── Animation Durations (ms) ────────────────
  static const int animFast = 150;
  static const int animMedium = 300;
  static const int animSlow = 500;

  // ── Backend ─────────────────────────────────
  /// Used only when no URL is saved in StoreSettings: the Android emulator's
  /// address for a backend running on the development machine.
  static const String devBackendBaseUrl = 'http://10.0.2.2:3000/api';

  // ── UI Palette (delegated to AppColors for single source of truth) ─
  static List<Color> get quickButtonPalette => AppColors.quickButtonPalette;

  // ── Paystack Ghana MoMo Payment ─────────────
  /// Payment type stored on Sale for Paystack mobile money charges.
  static const String paymentMomoPaystack = 'mobile_money';

  /// Ghana MoMo provider codes as required by Paystack Charge API.
  static const String momoProviderMtn = 'mtn';
  static const String momoProviderVodafone = 'vod';
  static const String momoProviderAirtelTigo = 'atl'; // Paystack's code (not 'tgo')

  /// How often (seconds) the app polls the backend to check payment status.
  static const int momoPollingIntervalSec = 5;

  /// Maximum seconds to wait before declaring the payment timed out.
  static const int momoTimeoutSec = 90;
}