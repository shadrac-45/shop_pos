/// ============================================
/// App Color Palette — ShopPOS
/// ============================================
/// All colors are defined centrally here.
/// Use these instead of raw Color() values.
/// ============================================
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._(); // Prevent instantiation

  // ── Primary Brand Colors ──────────────────────
  static const Color primary = Color(0xFF00C853);       // Vibrant green
  static const Color primaryDark = Color(0xFF009624);
  static const Color primaryLight = Color(0xFF5EFC82);
  static const Color accent = Color(0xFF00E676);

  // ── Background & Surface ──────────────────────
  static const Color scaffoldBg = Color(0xFF0D1117);    // Deep dark
  static const Color cardBg = Color(0xFF161B22);        // Slightly lighter
  static const Color surfaceBg = Color(0xFF21262D);     // Card/input bg
  static const Color elevatedBg = Color(0xFF30363D);    // Elevated surface

  // ── Text Colors ───────────────────────────────
  static const Color textPrimary = Color(0xFFF0F6FC);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF6E7681);
  static const Color textOnPrimary = Color(0xFF0D1117);

  // ── Status Colors ─────────────────────────────
  static const Color success = Color(0xFF2EA043);
  static const Color warning = Color(0xFFD29922);
  static const Color danger = Color(0xFFF85149);
  static const Color info = Color(0xFF58A6FF);

  // ── Expiry Status Colors ──────────────────────
  static const Color expiryGood = Color(0xFF2EA043);    // > 30 days
  static const Color expirySoon = Color(0xFFD29922);    // 7-30 days
  static const Color expiryUrgent = Color(0xFFF85149);  // < 7 days

  // ── Border & Divider ──────────────────────────
  static const Color border = Color(0xFF30363D);
  static const Color divider = Color(0xFF21262D);

  // ── Quick Button Palette (for product grid) ───
  static const List<Color> quickButtonPalette = [
    Color(0xFF2196F3), // Blue
    Color(0xFFFF9800), // Orange
    Color(0xFF4CAF50), // Green
    Color(0xFFFF5722), // Deep Orange
    Color(0xFF9C27B0), // Purple
    Color(0xFFE91E63), // Pink
    Color(0xFFFFC107), // Amber
    Color(0xFF00BCD4), // Cyan
    Color(0xFF3F51B5), // Indigo
    Color(0xFF795548), // Brown
    Color(0xFF607D8B), // Blue Grey
    Color(0xFFCDDC39), // Lime
  ];

  // ── Payment Type Colors ───────────────────────
  static const Color cashColor = Color(0xFF4CAF50);
  static const Color momoColor = Color(0xFFFFC107);
}
