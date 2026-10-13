/// ============================================
/// BorderBeam — ShopPOS
/// ============================================
/// A short bright streak that travels round the
/// child's border (Magic UI border-beam). Used as
/// a "work in progress" cue, so it only runs while
/// [active], and never under reduced motion.
/// ============================================
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_motion.dart';

class BorderBeam extends StatefulWidget {
  final Widget child;
  final bool active;
  final BorderRadius borderRadius;

  /// Length of the streak, in logical pixels along the border.
  final double size;

  /// Time for one lap.
  final Duration duration;

  final double borderWidth;
  final Color colorFrom;
  final Color colorTo;

  const BorderBeam({
    super.key,
    required this.child,
    this.active = true,
    this.borderRadius = BorderRadius.zero,
    this.size = 48,
    this.duration = const Duration(seconds: 2),
    this.borderWidth = 1.5,
    this.colorFrom = AppColors.primary,
    this.colorTo = AppColors.primaryLight,
  });

  @override
  State<BorderBeam> createState() => _BorderBeamState();
}

class _BorderBeamState extends State<BorderBeam>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  bool _reduced = false;

  bool get _running => widget.active && !_reduced;

  void _sync() {
    if (_running) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppMotion.reduced(context);
    _sync();
  }

  @override
  void didUpdateWidget(BorderBeam old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) _controller.duration = widget.duration;
    _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_running) return widget.child;
    return CustomPaint(
      foregroundPainter: _BeamPainter(
        progress: _controller,
        borderRadius: widget.borderRadius,
        size: widget.size,
        width: widget.borderWidth,
        colorFrom: widget.colorFrom,
        colorTo: widget.colorTo,
      ),
      child: widget.child,
    );
  }
}

class _BeamPainter extends CustomPainter {
  final Animation<double> progress;
  final BorderRadius borderRadius;
  final double size;
  final double width;
  final Color colorFrom;
  final Color colorTo;

  _BeamPainter({
    required this.progress,
    required this.borderRadius,
    required this.size,
    required this.width,
    required this.colorFrom,
    required this.colorTo,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size box) {
    final rect = (Offset.zero & box).deflate(width / 2);
    final rrect = borderRadius.toRRect(rect);
    // A sweep gradient that is clear except for one short arc, rotated
    // each frame. The arc's share of the circle approximates [size] as a
    // share of the perimeter.
    final perimeter = 2 * (rect.width + rect.height);
    final frac = perimeter <= 0 ? 0.1 : (size / perimeter).clamp(0.02, 0.5);
    final shader = SweepGradient(
      colors: [
        colorTo.withValues(alpha: 0),
        colorTo.withValues(alpha: 0),
        colorTo,
        colorFrom,
      ],
      stops: [0, 1 - frac, 1 - frac / 3, 1],
      transform: GradientRotation(2 * math.pi * progress.value),
    ).createShader(rect);
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_BeamPainter old) =>
      old.borderRadius != borderRadius ||
      old.size != size ||
      old.width != width ||
      old.colorFrom != colorFrom ||
      old.colorTo != colorTo;
}
