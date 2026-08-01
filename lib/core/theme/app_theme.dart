/// ============================================
/// App Theme — ShopPOS
/// ============================================
/// Touch-first light off-white & emerald theme
/// optimized for high-speed POS usage.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_spacing.dart';

class AppTheme {
  AppTheme._();

  /// Alias darkTheme to lightTheme for backward compatibility if referenced.
  static ThemeData get darkTheme => lightTheme;

  /// The primary light off-white & emerald theme for ShopPOS.
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // ── Color Scheme ────────────────────────────
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.textOnPrimary,
        secondary: AppColors.accent,
        surface: AppColors.cardBg,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
      ),

      // ── Scaffold ────────────────────────────────
      scaffoldBackgroundColor: AppColors.scaffoldBg,

      // ── AppBar ──────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cardBg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark, // Dark status bar icons for Android
          statusBarBrightness: Brightness.light,    // Light status bar background for iOS
        ),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
      ),

      // ── Typography Hierarchy ───────────────────
      textTheme: const TextTheme(
        // Display (Total Amounts, Large Keypad Display)
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          letterSpacing: -0.8,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),

        // Headlines (Screen Titles, Dialog Headers)
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),

        // Titles (Product Names, Card Headers)
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),

        // Body (General info, Table content)
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),

        // Labels (Buttons, Badges, Chips)
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        labelMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
      ),

      // ── Elevated Button (Min 48dp Touch Target) ───
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          minimumSize: const Size(double.infinity, AppTouch.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderMd,
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
          elevation: 0,
        ),
      ),

      // ── Outlined Button ──────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(double.infinity, AppTouch.buttonHeight),
          side: const BorderSide(color: AppColors.border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderMd,
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Card Theme ──────────────────────────────
      cardTheme: CardThemeData(
        color: AppColors.cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderLg,
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Dialog Theme ────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderLg,
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),

      // ── Bottom Sheet Theme ──────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.cardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // ── Input Decoration Theme ──────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceBg,
        border: OutlineInputBorder(
          borderRadius: AppSpacing.borderMd,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderMd,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderMd,
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        hintStyle: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 14,
        ),
      ),

      // ── Navigation Bar Theme ─────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.cardBg,
        indicatorColor: AppColors.primaryLight,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primary, size: 24);
          }
          return const IconThemeData(color: AppColors.textSecondary, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            );
          }
          return const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
            fontSize: 12,
          );
        }),
      ),

      // ── Floating Action Button ─────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 2,
        sizeConstraints: const BoxConstraints.tightFor(width: 56, height: 56),
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderLg),
      ),

      // ── Divider ─────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // ── Snackbar ────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.cardBg,
        contentTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderMd,
          side: const BorderSide(color: AppColors.border),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
