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

  /// From here the app uses a side navigation rail instead of a bottom
  /// bar, and the till shows the cart beside the catalogue (Material's
  /// "expanded" window class).
  static const double rail = 840;

  // ── Convenience predicates ───────────────────

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

  /// PIN dot dimension based on available width (3 dots in ~280 dp).
  static double pinDotWidth(double availableWidth) =>
      (availableWidth / 6).clamp(44.0, 60.0);

  static double pinDotHeight(double availableWidth) =>
      (availableWidth / 5).clamp(52.0, 68.0);
}
