/// ============================================
/// Context Extensions — ShopPOS
/// ============================================
/// Convenient extensions on BuildContext for
/// accessing theme, sizes, and showing dialogs.
/// ============================================
library;

import 'package:flutter/material.dart';

import 'package:shop_pos/features/shared/widgets/glass.dart';

extension ContextExtension on BuildContext {
  // ── Theme Access ────────────────────────────
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => Theme.of(this).textTheme;
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  // ── Screen Size ─────────────────────────────
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  EdgeInsets get padding => MediaQuery.of(this).padding;

  bool get isSmallScreen => screenHeight < 700;
  bool get isMediumScreen => screenHeight >= 700 && screenHeight < 900;
  bool get isLargeScreen => screenHeight >= 900;

  // ── Snackbar Helpers ────────────────────────
  // Dark-glass toasts in the root overlay, above dialogs and sheets;
  // see [showGlassToast].

  void _toast(String message, ToastKind kind) => showGlassToast(this, message, kind);

  void showSuccessSnackbar(String message) => _toast(message, ToastKind.success);

  void showErrorSnackbar(String message) => _toast(message, ToastKind.error);

  /// Neutral-toned notice, used for guidance rather than success or
  /// failure (e.g. pointing the user at another tab).
  void showInfoSnackbar(String message) => _toast(message, ToastKind.info);
}
