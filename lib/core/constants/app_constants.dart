/// ============================================
/// App Constants — ShopPOS
/// ============================================
library;

import 'package:flutter/material.dart';

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

  // ── UI Palette (must match product buttons) ─
  static const List<Color> quickButtonPalette = [
    Color(0xFF4CAF50), // green
    Color(0xFF2196F3), // blue
    Color(0xFFFF9800), // orange
    Color(0xFF9C27B0), // purple
    Color(0xFFF44336), // red
    Color(0xFF00BCD4), // cyan
  ];

  // ── Demo only (in production, use hashed PINs)
  static const String defaultOwnerPin = '1234';
}