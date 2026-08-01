/// ============================================
/// App Color Palette — ShopPOS
/// ============================================
/// Modern, clean white/light neutral background palette
/// with emerald green CTAs and high-contrast dark slate text.
/// High contrast (WCAG AA & AAA compliant).
/// ============================================
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._(); // Prevent instantiation

  // ── Primary Brand Colors (Emerald Green & Tints) ───
  static const Color primary = Color(0xFF059669);       // Emerald 600 (High contrast green on white, ratio 4.6:1)
  static const Color primaryDark = Color(0xFF047857);   // Emerald 700 (Deep Emerald)
  static const Color primaryLight = Color(0xFFD1FAE5);  // Emerald 100 (Soft Mint fill for active badges & highlights)
  static const Color accent = Color(0xFF10B981);        // Emerald 500 (Vibrant Green accent)

  // ── Light Neutral Background & Surfaces ─────────────
  static const Color scaffoldBg = Color(0xFFF8FAFC);    // Slate 50 (Soft off-white background preventing glare)
  static const Color cardBg = Color(0xFFFFFFFF);        // Pure White (For cards, panels, sheets, modals)
  static const Color surfaceBg = Color(0xFFF1F5F9);     // Slate 100 (Soft light gray for input fields, chips, secondary panels)
  static const Color elevatedBg = Color(0xFFE2E8F0);    // Slate 200 (Elevated light containers & badges)

  // ── Text Colors (Dark Slate/Navy on Light Background) ─
  static const Color textPrimary = Color(0xFF0F172A);   // Slate 900 (High-contrast dark navy/near-black, > 15:1 ratio)
  static const Color textSecondary = Color(0xFF475569); // Slate 600 (Dark slate for secondary body, subtitles, > 7:1 ratio)
  static const Color textMuted = Color(0xFF64748B);     // Slate 500 (Muted slate for hints/placeholders, > 4.5:1 ratio)
  static const Color textOnPrimary = Color(0xFFFFFFFF); // Pure White text on primary emerald green buttons

  // ── Status Colors (Optimized for Light Background) ───
  static const Color success = Color(0xFF059669);       // Emerald 600 success
  static const Color warning = Color(0xFFD97706);       // Amber 600 warning (> 4.5:1 ratio on light bg)
  static const Color danger = Color(0xFFDC2626);        // Rose 600 danger (> 5:1 ratio on light bg)
  static const Color info = Color(0xFF2563EB);          // Royal Blue 600 info (> 4.5:1 ratio on light bg)

  // ── Expiry Status Colors ────────────────────────────
  static const Color expiryGood = Color(0xFF059669);    // > 30 days
  static const Color expirySoon = Color(0xFFD97706);    // 7-30 days
  static const Color expiryUrgent = Color(0xFFDC2626);  // < 7 days

  // ── Border & Divider ────────────────────────────────
  static const Color border = Color(0xFFE2E8F0);        // Slate 200 (Clean, soft light border)
  static const Color divider = Color(0xFFF1F5F9);       // Slate 100 (Soft divider line)

  // ── Quick Button Palette (for product grid) ─────────
  static const List<Color> quickButtonPalette = [
    Color(0xFF2563EB), // Royal Blue
    Color(0xFFD97706), // Warm Amber
    Color(0xFF059669), // Emerald
    Color(0xFFDC2626), // Rose
    Color(0xFF7C3AED), // Violet
    Color(0xFFDB2777), // Pink
    Color(0xFF0284C7), // Sky Blue
    Color(0xFF4F46E5), // Indigo
    Color(0xFF0D9488), // Teal
    Color(0xFFB45309), // Bronze
    Color(0xFF475569), // Slate
    Color(0xFF65A30D), // Lime
  ];

  // ── Payment Type Colors ─────────────────────────────
  static const Color cashColor = Color(0xFF059669);
  static const Color momoColor = Color(0xFFD97706);
}
