/// ============================================
/// App Spacing & Touch Metrics — ShopPOS
/// ============================================
/// Standardized spacing constants and touch metrics
/// enforcing minimum 48x48 dp touch boundaries.
/// ============================================
library;

import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();

  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;

  // Insets
  static const EdgeInsets pagePadding = EdgeInsets.all(lg);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets tilePadding = EdgeInsets.symmetric(horizontal: md, vertical: sm);

  // Border Radii
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;

  static BorderRadius get borderSm => BorderRadius.circular(radiusSm);
  static BorderRadius get borderMd => BorderRadius.circular(radiusMd);
  static BorderRadius get borderLg => BorderRadius.circular(radiusLg);
  static BorderRadius get borderXl => BorderRadius.circular(radiusXl);
}

class AppTouch {
  AppTouch._();

  /// Touch-first workflow: minimum 48x48 dp touch targets
  static const double minTargetSize = 48.0;
  static const double buttonHeight = 52.0;
  static const double iconButtonSize = 48.0;
  static const BoxConstraints touchConstraints = BoxConstraints(
    minWidth: minTargetSize,
    minHeight: minTargetSize,
  );
}
