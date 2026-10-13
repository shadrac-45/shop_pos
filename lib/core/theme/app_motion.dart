/// ============================================
/// App Motion — ShopPOS
/// ============================================
/// Shared durations and curves so animations
/// feel consistent, plus a reduced-motion check
/// that honours the OS accessibility setting.
/// ============================================
library;

import 'package:flutter/widgets.dart';

class AppMotion {
  AppMotion._();

  /// Press feedback, label swaps.
  static const Duration fast = Duration(milliseconds: 150);

  /// Entrances, panel changes.
  static const Duration medium = Duration(milliseconds: 300);

  /// Count-ups and other attention-drawing moves.
  static const Duration slow = Duration(milliseconds: 700);

  /// Gap between items that enter one after another.
  static const Duration stagger = Duration(milliseconds: 60);

  static const Curve curve = Curves.easeOutCubic;

  /// True when the user asked the OS to turn animations off.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
