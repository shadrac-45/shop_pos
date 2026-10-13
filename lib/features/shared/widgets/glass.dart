/// ============================================
/// Glass — ShopPOS
/// ============================================
/// The few frosted surfaces in the app: the
/// navigation, the cart panel, modals and toasts.
/// Everything else (product cards, prices, tables)
/// stays solid so it reads instantly at the till.
///
/// Glass falls back to an opaque fill when the OS
/// asks for high contrast, and blur stays modest so
/// it holds frame rate on budget Android tablets.
/// ============================================
library;

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_motion.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';

class AppGlass {
  AppGlass._();

  /// Blur for panels. Research on accessible glass puts the useful range
  /// at 12–20; past that it costs frames without looking better.
  static const double blur = 18;

  static const List<BoxShadow> shadow = [
    BoxShadow(color: Color(0x0F18201C), blurRadius: 32, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x0A18201C), blurRadius: 4, offset: Offset(0, 1)),
  ];

  /// True when glass should be drawn as a plain opaque surface.
  static bool solid(BuildContext context) =>
      MediaQuery.maybeHighContrastOf(context) ?? false;
}

/// A frosted panel: backdrop blur, translucent fill, hairline border and
/// a soft floating shadow.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Dark glass (toasts) instead of frosted white.
  final bool dark;

  /// More opaque fill, for panels that hold forms or long text.
  final bool strong;

  final bool shadow;

  /// Live backdrop blur. Off for panels that float over content that
  /// scrolls or animates (the blur would re-run every frame); they get a
  /// near-opaque fill instead, which reads the same over solid cards.
  final bool frosted;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppSpacing.radiusXl)),
    this.padding,
    this.dark = false,
    this.strong = false,
    this.shadow = true,
    this.frosted = true,
  });

  @override
  Widget build(BuildContext context) {
    final solid = AppGlass.solid(context);
    final blur = frosted && !solid;
    final Color fill;
    if (dark) {
      fill = solid ? AppColors.ink : AppColors.inkGlass;
    } else {
      fill = solid
          ? AppColors.cardBg
          : (strong || !frosted ? AppColors.glassFillStrong : AppColors.glassFill);
    }

    // The faint sheen along the top edge is part of the fill (a gradient
    // into the base tint), so it sits under the content, never over text.
    final sheen = !solid && !dark;
    final Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: sheen ? null : fill,
        gradient: sheen
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: const Alignment(0, -0.5),
                colors: [Color.alphaBlend(AppColors.glassHighlight, fill), fill],
              )
            : null,
        borderRadius: borderRadius,
        border: Border.all(
          color: dark ? AppColors.inkBorder : (solid ? AppColors.border : AppColors.glassStroke),
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    final clipped = ClipRRect(
      borderRadius: borderRadius,
      child: !blur
          ? surface
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: AppGlass.blur, sigmaY: AppGlass.blur),
              child: surface,
            ),
    );

    if (!shadow) return clipped;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: AppGlass.shadow),
      child: clipped,
    );
  }
}

/// The app canvas: the off-white base with a few faint colour fields, so
/// frosted panels on top read as glass rather than grey boxes. Static —
/// no animation, nothing to repaint.
class AmbientBackdrop extends StatelessWidget {
  final Widget child;
  const AmbientBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.scaffoldBg),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _AmbientPainter()),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter();

  void _blob(Canvas canvas, Offset center, double radius, Color color) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
            .createShader(rect),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.longestSide;
    _blob(canvas, Offset(0, size.height * 0.05), r * 0.45, AppColors.ambientPrimary);
    _blob(canvas, Offset(size.width, size.height * 0.6), r * 0.45, AppColors.ambientSoft);
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter oldDelegate) => false;
}

/// [showDialog] with the app's modal treatment: a charcoal scrim fades in
/// and the dialog scales up, so it is clearly the one thing to deal with.
/// Same arguments and result as [showDialog].
///
/// No full-screen backdrop blur: it would be recomposited every frame the
/// dialog is open (even for a blinking cursor), which budget tablets feel.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  final reduced = AppMotion.reduced(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    useRootNavigator: useRootNavigator,
    transitionDuration: reduced ? Duration.zero : const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) {
      // App-wide, Elevated/Outlined buttons default to full width. Inside a
      // dialog that pushes AlertDialog actions onto separate lines, so
      // dialogs get a compact minimum (explicit sizes and Expanded rows
      // still win).
      final theme = Theme.of(ctx);
      const compact = WidgetStatePropertyAll(Size(64, AppTouch.minTargetSize));
      return Theme(
        data: theme.copyWith(
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: (theme.elevatedButtonTheme.style ?? const ButtonStyle())
                .copyWith(minimumSize: compact),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
                .copyWith(minimumSize: compact),
          ),
        ),
        child: SafeArea(child: Builder(builder: builder)),
      );
    },
    transitionBuilder: (ctx, animation, _, child) {
      final t = CurvedAnimation(parent: animation, curve: AppMotion.curve);
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: t,
                child: const ColoredBox(color: AppColors.scrim),
              ),
            ),
          ),
          FadeTransition(
            opacity: t,
            child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(t),
              child: child,
            ),
          ),
        ],
      );
    },
  );
}

enum ToastKind { success, error, info }

/// Shows a dark-glass toast at the top of the screen, in the app's root
/// overlay — above every route, so it is never hidden behind a dialog or
/// a bottom sheet (a ScaffoldMessenger snackbar would be), and never
/// covering the Pay button or the cart at the bottom. Icon and text both
/// carry the meaning; screen readers hear it as a live region. Tap to
/// dismiss. A new toast replaces the current one.
void showGlassToast(BuildContext context, String message, ToastKind kind) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _ToastHost.show(overlay, message, kind);
}

class _ToastHost {
  _ToastHost._();

  static OverlayEntry? _current;

  static void show(OverlayState overlay, String message, ToastKind kind) {
    _current?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        kind: kind,
        onDone: () {
          if (_current == entry) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _ToastView extends StatefulWidget {
  final String message;
  final ToastKind kind;
  final VoidCallback onDone;

  const _ToastView({required this.message, required this.kind, required this.onDone});

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  bool _closing = false;
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _anim.forward();
    _hold = Timer(Duration(milliseconds: widget.kind == ToastKind.error ? 4000 : 2400), _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    await _anim.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (widget.kind) {
      ToastKind.success => (Icons.check_circle_rounded, AppColors.successOnInk),
      ToastKind.error => (Icons.error_rounded, AppColors.dangerOnInk),
      ToastKind.info => (Icons.info_rounded, AppColors.onInkMuted),
    };
    final reduced = AppMotion.reduced(context);
    final t = CurvedAnimation(parent: _anim, curve: AppMotion.curve);

    return Positioned(
      top: MediaQuery.paddingOf(context).top + AppSpacing.md,
      left: AppSpacing.md,
      right: AppSpacing.md,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: FadeTransition(
            opacity: t,
            child: SlideTransition(
              position: Tween(
                begin: reduced ? Offset.zero : const Offset(0, -0.4),
                end: Offset.zero,
              ).animate(t),
              child: Semantics(
                liveRegion: true,
                child: GestureDetector(
                  onTap: _close,
                  child: Material(
                    type: MaterialType.transparency,
                    child: GlassPanel(
                      dark: true,
                      borderRadius: AppSpacing.borderLg,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
                      child: Row(
                        children: [
                          Icon(icon, color: color, size: 20),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              widget.message,
                              style: const TextStyle(
                                color: AppColors.onInk,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
