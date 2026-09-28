/// ============================================
/// Context Extensions — ShopPOS
/// ============================================
/// Convenient extensions on BuildContext for
/// accessing theme, sizes, and showing dialogs.
/// ============================================
library;

import 'package:flutter/material.dart';

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
  void showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(this).hideCurrentSnackBar();
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2EA043),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void showErrorSnackbar(String message) {
    ScaffoldMessenger.of(this).hideCurrentSnackBar();
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFF85149),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Neutral-toned notice, used for guidance rather than success or
  /// failure (e.g. pointing the user at another tab).
  void showInfoSnackbar(String message) {
    ScaffoldMessenger.of(this).hideCurrentSnackBar();
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
