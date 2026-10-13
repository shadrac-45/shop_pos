/// ============================================
/// App Colors — ShopPOS design tokens
/// ============================================
/// One strict palette: GREEN for the brand and
/// for action/active/positive, WHITE for content
/// surfaces, NEUTRAL GRAYS for structure and text.
/// Amber and red appear only to carry meaning
/// (warning, error/destructive) — never as
/// decoration. There is no blue, purple, etc.
///
///   Brand    primary · primaryDark · primaryLight · primarySoft
///   Neutral  scaffoldBg · cardBg · surfaceBg · elevatedBg
///            border · borderStrong · divider
///   Text     textPrimary · textSecondary · textMuted · textOnPrimary
///   Status   success · warning · danger (+ …DarkText, …Tint, …Border)
///   Dark     ink · inkRaised · inkBorder · onInk · onInkMuted
///   Glass    glassFill · glassFillStrong · glassStroke · glassHighlight
///
/// Status UI should use [AppTone] rather than
/// picking colours by hand. Grays carry a faint
/// green cast so neutrals and brand sit together.
/// All text pairs meet WCAG AA (most AAA).
/// ============================================
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._(); // Prevent instantiation

  // ── Brand: green ────────────────────────────────────
  /// Primary actions, active states, positive highlights. Emerald 700:
  /// white text on it is 5.5:1, so buttons pass AA at any size.
  static const Color primary = Color(0xFF047857);
  /// Pressed states and green text on light green tints (7.4:1 on white).
  static const Color primaryDark = Color(0xFF065F46);
  /// Selected fills (chips, the active nav item, chosen payment method).
  static const Color primaryLight = Color(0xFFD1FAE5);
  /// Faintest wash: selected cards, success panels, glass tint.
  static const Color primarySoft = Color(0xFFECFDF5);
  /// Alias of [primary]; kept so older call sites stay on-palette.
  static const Color accent = primary;

  // ── Neutral surfaces ────────────────────────────────
  static const Color scaffoldBg = Color(0xFFF4F6F5);    // App background: off-white, faint green cast
  static const Color cardBg = Color(0xFFFFFFFF);        // Surface: cards, panels, sheets, modals
  static const Color surfaceBg = Color(0xFFEEF1EF);     // Muted surface: steppers, placeholders, chips
  static const Color elevatedBg = Color(0xFFE3E7E5);    // Disabled fills, pressed neutral

  // ── Text: charcoal → gray ───────────────────────────
  static const Color textPrimary = Color(0xFF1A1F1C);   // Charcoal (16:1 on white)
  static const Color textSecondary = Color(0xFF4A524E); // Medium gray (8:1)
  static const Color textMuted = Color(0xFF5C6661);     // Hints, captions (5.9:1 on white, 5.2:1 on surfaceBg)
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ── Structure ───────────────────────────────────────
  static const Color border = Color(0xFFE3E7E5);        // Card and input hairlines
  static const Color borderStrong = Color(0xFFCDD3D0);  // Emphasised outlines, empty-state glyphs
  static const Color divider = Color(0xFFEEF1EF);

  // ── Status (meaning only) ───────────────────────────
  static const Color success = primary;
  /// Restrained amber: low stock, expiring, no shift open.
  static const Color warning = Color(0xFFB45309);
  /// Restrained red: errors, out of stock, destructive actions.
  static const Color danger = Color(0xFFB91C1C);
  /// Informational = neutral. Info is not a status that needs a hue.
  static const Color info = textSecondary;

  /// Text on the matching pale tint.
  static const Color successDarkText = primaryDark;
  static const Color warningDarkText = Color(0xFF92400E);
  static const Color dangerDarkText = Color(0xFF991B1B);

  static const Color successTint = primarySoft;
  static const Color warningTint = Color(0xFFFFFBEB);
  static const Color dangerTint = Color(0xFFFEF2F2);
  static const Color successBorder = primaryLight;
  static const Color warningBorder = Color(0xFFFDE68A);
  static const Color dangerBorder = Color(0xFFFECACA);

  // ── Dark slab (charcoal) ────────────────────────────
  /// Headline figures, toasts, tooltips and the sign-in backdrop.
  static const Color ink = Color(0xFF18201C);
  static const Color inkRaised = Color(0xFF232C27);    // Fields and cards on ink
  static const Color inkBorder = Color(0xFF36403B);    // Hairlines on ink
  static const Color onInk = Color(0xFFFFFFFF);
  static const Color onInkMuted = Color(0xFFA3ADA8);   // 7:1 on ink
  static const Color onInkSubtle = Color(0xFF7D8781);  // Placeholders on ink (4.6:1)
  static const Color successOnInk = Color(0xFF6EE7B7); // Green accents on ink
  static const Color dangerOnInk = Color(0xFFFCA5A5);  // Errors on ink
  static const Color warningOnInk = Color(0xFFFCD34D); // Warnings on ink / deep green

  // ── Glass (floating surfaces only) ──────────────────
  /// Frosted white with the faintest green cast. ≥ 72% opaque so dark
  /// text keeps AAA contrast whatever is behind it.
  static const Color glassFill = Color(0xBAFBFEFC);
  static const Color glassFillStrong = Color(0xE0FFFFFF);
  /// Hairline around glass: a whisper of green-gray.
  static const Color glassStroke = Color(0x1A1A3D2C);
  static const Color glassHighlight = Color(0x99FFFFFF);
  static const Color inkGlass = Color(0xE618201C);       // Dark glass for toasts
  static const Color scrim = Color(0x5218201C);          // Modal scrim (32%)

  // ── Ambient canvas ──────────────────────────────────
  /// Two faint green fields behind the app, so frosted panels have
  /// something to frost. Never strong enough to compete with content.
  static const Color ambientPrimary = Color(0x2210B981);
  static const Color ambientSoft = Color(0x1A6EE7B7);

  // ── Legacy product colours ──────────────────────────
  /// Values stored per product (`quickButtonColor`) by older versions and
  /// still synced. They are DATA only and are no longer drawn anywhere:
  /// product cards are one unified neutral style. Do not use for UI.
  static const List<Color> quickButtonPalette = [
    Color(0xFF2563EB),
    Color(0xFFD97706),
    Color(0xFF059669),
    Color(0xFFDC2626),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFF0284C7),
    Color(0xFF4F46E5),
    Color(0xFF0D9488),
    Color(0xFFB45309),
    Color(0xFF475569),
    Color(0xFF65A30D),
  ];
}

/// A status colour set: foreground (icons, text), tint (fill) and border.
/// Use these instead of choosing colours per widget, so every badge, pill,
/// banner and panel speaks the same language.
class AppTone {
  final Color fg;
  final Color text;
  final Color tint;
  final Color border;

  const AppTone._(this.fg, this.text, this.tint, this.border);

  /// Positive / active / done.
  static const success = AppTone._(
      AppColors.primary, AppColors.successDarkText, AppColors.successTint, AppColors.successBorder);

  /// Needs attention soon (low stock, expiring, no shift).
  static const warning = AppTone._(
      AppColors.warning, AppColors.warningDarkText, AppColors.warningTint, AppColors.warningBorder);

  /// Error, out of stock, destructive.
  static const danger = AppTone._(
      AppColors.danger, AppColors.dangerDarkText, AppColors.dangerTint, AppColors.dangerBorder);

  /// Informational or categorical: neutral gray.
  static const neutral = AppTone._(
      AppColors.textSecondary, AppColors.textPrimary, AppColors.surfaceBg, AppColors.border);
}
