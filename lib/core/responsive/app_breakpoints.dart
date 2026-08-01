/// ============================================
/// App Breakpoints — ShopPOS
/// ============================================
/// Central breakpoint & responsive-layout helpers.
/// Use these instead of raw MediaQuery calls
/// scattered across widgets so breakpoints can
/// be updated in a single place.
///
/// Breakpoints (logical pixels / dp):
///   small  — width < 360  (compact phones, e.g. iPhone SE)
///   phone  — 360 ≤ width < 600  (standard phones)
///   tablet — width ≥ 600  (tablets, large phones in landscape)
/// ============================================
library;

import 'package:flutter/material.dart';

class AppBreakpoints {
  AppBreakpoints._();

  // ── Width thresholds ─────────────────────────
  static const double small = 360;
  static const double tablet = 600;

  // ── Convenience predicates ───────────────────

  /// True when the device/window is tablet-width or wider.
  static bool isTablet(double width) => width >= tablet;

  /// True when the device/window is narrower than [small].
  static bool isSmallPhone(double width) => width < small;

  /// True when the current orientation is landscape.
  static bool isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  // ── Layout helpers ───────────────────────────

  /// Number of columns for the quick-sale product grid.
  ///   small phone  → 2
  ///   phone        → 3
  ///   tablet       → 4
  ///   tablet (land)→ 5
  static int salesGridColumns(double width, {bool landscape = false}) {
    if (width >= tablet) return landscape ? 5 : 4;
    if (width < small) return 2;
    return 3;
  }

  /// Horizontal inset for dialogs so they are never too wide on tablets.
  /// On tablets the dialog is capped at ~560 dp.
  static double dialogHorizontalInset(double screenWidth) {
    if (screenWidth > 600) {
      return ((screenWidth - 560) / 2).clamp(24.0, double.infinity);
    }
    return 20.0;
  }

  /// Vertical padding to use for the bottom CTA strip.
  /// Tighter in landscape to save vertical space.
  static double ctaVerticalPadding(BuildContext context) =>
      isLandscape(context) ? 10.0 : 20.0;

  /// Logo display height based on screen height.
  ///   very short (≤ 600) → 100
  ///   normal (≤ 800)     → 130
  ///   tall (> 800)       → 160
  static double logoHeight(double screenHeight) {
    if (screenHeight <= 600) return 100.0;
    if (screenHeight <= 800) return 130.0;
    return 160.0;
  }

  /// PIN dot dimension based on available width (3 dots in ~280 dp).
  static double pinDotWidth(double availableWidth) =>
      (availableWidth / 6).clamp(44.0, 60.0);

  static double pinDotHeight(double availableWidth) =>
      (availableWidth / 5).clamp(52.0, 68.0);
}
