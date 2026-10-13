/// ============================================
/// App Theme — ShopPOS
/// ============================================
/// Minimalist, touch-first light theme for fast
/// till work, built only from the AppColors
/// tokens: green for action and active states,
/// white surfaces, neutral grays for structure. Frosted glass is reserved for
/// floating surfaces (see shared/widgets/glass.dart).
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';

class AppTheme {
  AppTheme._();

  /// Alias darkTheme to lightTheme for backward compatibility if referenced.
  static ThemeData get darkTheme => lightTheme;

  static const String fontFamily = 'Inter';

  static ThemeData get lightTheme {
    final hairline = OutlineInputBorder(
      borderRadius: AppSpacing.borderMd,
      borderSide: const BorderSide(color: AppColors.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,

      // ── Color Scheme ────────────────────────────
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.textOnPrimary,
        primaryContainer: AppColors.primaryLight,
        onPrimaryContainer: AppColors.successDarkText,
        secondary: AppColors.accent,
        surface: AppColors.cardBg,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        surfaceContainerLowest: AppColors.cardBg,
        surfaceContainerLow: AppColors.cardBg,
        surfaceContainer: AppColors.surfaceBg,
        surfaceContainerHigh: AppColors.surfaceBg,
        surfaceContainerHighest: AppColors.elevatedBg,
        outline: AppColors.borderStrong,
        outlineVariant: AppColors.border,
        error: AppColors.danger,
        scrim: AppColors.scrim,
      ),

      scaffoldBackgroundColor: AppColors.scaffoldBg,

      // ── AppBar (pushed screens) ─────────────────
      // Sits flush on the canvas: no fill, no shadow, just the title.
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.scaffoldBg,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        toolbarHeight: 60,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.4,
        ),
      ),

      // ── Typography Hierarchy ───────────────────
      textTheme: const TextTheme(
        // Display (Total Amounts, Large Keypad Display)
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          letterSpacing: -1.0,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.7,
        ),

        // Headlines (Screen Titles, Dialog Headers)
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
        headlineSmall: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),

        // Titles (Product Names, Card Headers)
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
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
          fontWeight: FontWeight.w600,
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

      // ── Buttons ─────────────────────────────────
      // Hierarchy: Elevated/Filled = the one primary action on a surface;
      // Outlined = secondary; Text = tertiary. See [AppButtons] for Pay
      // and destructive variants.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          disabledBackgroundColor: AppColors.elevatedBg,
          disabledForegroundColor: AppColors.textMuted,
          minimumSize: const Size(double.infinity, AppTouch.buttonHeight),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderMd),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          disabledBackgroundColor: AppColors.elevatedBg,
          disabledForegroundColor: AppColors.textMuted,
          minimumSize: const Size(64, AppTouch.minTargetSize),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderMd),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.cardBg,
          minimumSize: const Size(double.infinity, AppTouch.buttonHeight),
          side: const BorderSide(color: AppColors.border, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderMd),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          minimumSize: const Size(48, AppTouch.minTargetSize),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderMd),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          minimumSize: const Size(AppTouch.minTargetSize, AppTouch.minTargetSize),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderMd),
        ),
      ),

      // ── Cards: solid, bordered, flat ────────────
      cardTheme: CardThemeData(
        color: AppColors.cardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderLg,
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        minVerticalPadding: 12,
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),

      // ── Modals ──────────────────────────────────
      // Dialogs open over a frosted backdrop (showAppDialog); the dialog
      // itself stays solid so forms and figures read cleanly.
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shadowColor: const Color(0x3318201C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.glassStroke),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.cardBg,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: AppColors.scrim,
        showDragHandle: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.cardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: const Color(0x2618201C),
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderLg,
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.inkGlass,
          borderRadius: AppSpacing.borderSm,
        ),
        textStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.onInk,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        waitDuration: const Duration(milliseconds: 500),
      ),

      // ── Inputs: white field, hairline, emerald focus ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardBg,
        border: hairline,
        enabledBorder: hairline,
        disabledBorder: hairline.copyWith(
            borderSide: const BorderSide(color: AppColors.divider)),
        focusedBorder: hairline.copyWith(
            borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        errorBorder: hairline.copyWith(
            borderSide: const BorderSide(color: AppColors.danger)),
        focusedErrorBorder: hairline.copyWith(
            borderSide: const BorderSide(color: AppColors.danger, width: 2)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 14,
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        floatingLabelStyle: const TextStyle(
            color: AppColors.primaryDark, fontWeight: FontWeight.w600),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
      ),

      // ── Chips (category filters, quick amounts) ─
      chipTheme: const ChipThemeData(
        backgroundColor: AppColors.cardBg,
        selectedColor: AppColors.primaryLight,
        disabledColor: AppColors.surfaceBg,
        side: BorderSide(color: AppColors.border),
        shape: StadiumBorder(),
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.successDarkText,
        ),
        checkmarkColor: AppColors.successDarkText,
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.cardBg,
          selectedBackgroundColor: AppColors.primaryLight,
          selectedForegroundColor: AppColors.successDarkText,
          foregroundColor: AppColors.textSecondary,
          side: const BorderSide(color: AppColors.border),
          textStyle: const TextStyle(
              fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),

      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.primary,
        dividerColor: AppColors.border,
        labelStyle: TextStyle(
            fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: TextStyle(
            fontFamily: fontFamily, fontWeight: FontWeight.w500, fontSize: 14),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : AppColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary : AppColors.elevatedBg),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary : AppColors.borderStrong),
      ),

      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceBg,
      ),

      // ── Navigation ──────────────────────────────
      // The bar is drawn inside a glass panel by the shell, so it is
      // transparent itself.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: AppColors.primaryLight,
        indicatorShape: RoundedRectangleBorder(borderRadius: AppSpacing.borderMd),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primaryDark, size: 24);
          }
          return const IconThemeData(color: AppColors.textSecondary, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontFamily: fontFamily,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            );
          }
          return const TextStyle(
            fontFamily: fontFamily,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
            fontSize: 12,
          );
        }),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 2,
        highlightElevation: 0,
        extendedTextStyle: const TextStyle(
            fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
        sizeConstraints: const BoxConstraints.tightFor(width: 56, height: 56),
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderLg),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // ── Snackbar ────────────────────────────────
      // context.show*Snackbar draws its own glass toast; this covers any
      // plain SnackBar so it matches.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.inkGlass,
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.onInk,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: AppColors.successOnInk,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderLg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Button styles beyond the theme defaults, for the actions a cashier must
/// never miss (Pay) or never hit by accident (destructive).
class AppButtons {
  AppButtons._();

  /// Height of the till's money buttons (Charge, Complete sale).
  static const double payHeight = 60;

  /// The dominant call to action: Charge / Complete sale.
  static ButtonStyle pay({double? width}) => ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        disabledBackgroundColor: AppColors.elevatedBg,
        disabledForegroundColor: AppColors.textMuted,
        minimumSize: Size(width ?? double.infinity, payHeight),
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderLg),
        textStyle: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          fontFeatures: AppText.tabular,
        ),
        elevation: 0,
      );

  /// Solid red for confirming something that cannot be undone.
  static ButtonStyle danger() => ElevatedButton.styleFrom(
        backgroundColor: AppColors.danger,
        foregroundColor: Colors.white,
      );

  /// Quiet red outline for "remove" style secondary actions.
  static ButtonStyle dangerOutlined() => OutlinedButton.styleFrom(
        foregroundColor: AppColors.dangerDarkText,
        side: const BorderSide(color: AppColors.dangerBorder, width: 1.2),
      );
}

/// Text styles that sit outside the Material type scale.
class AppText {
  AppText._();

  /// Fixed-width digits so amounts line up and don't jitter while counting.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Small uppercase section label.
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
    color: AppColors.textMuted,
  );

  /// Currency figures: tabular digits, slightly tightened.
  static TextStyle money({
    double size = 16,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.textPrimary,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: -0.02 * size,
      fontFeatures: tabular,
    );
  }
}
