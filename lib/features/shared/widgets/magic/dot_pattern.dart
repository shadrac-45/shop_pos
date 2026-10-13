/// ============================================
/// DotPattern — ShopPOS
/// ============================================
/// A grid of small dots for textured backgrounds
/// (Magic UI dot-pattern). With [fadeCenter] the
/// dots are strongest there and fade out away
/// from it.
/// ============================================
library;

import 'package:flutter/material.dart';

class DotPattern extends StatelessWidget {
  final Color color;
  final double spacing;
  final double radius;

  /// Where the dots are fully visible; null means no fade.
  final Alignment? fadeCenter;

  const DotPattern({
    super.key,
    required this.color,
    this.spacing = 16,
    this.radius = 1,
    this.fadeCenter,
  });

  @override
  Widget build(BuildContext context) {
    Widget dots = CustomPaint(
      painter: _DotPainter(color: color, spacing: spacing, radius: radius),
      size: Size.infinite,
    );
    final center = fadeCenter;
    if (center != null) {
      dots = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => RadialGradient(
          center: center,
          radius: 1.2,
          colors: const [Colors.white, Color(0x00FFFFFF)],
        ).createShader(bounds),
        child: dots,
      );
    }
    return IgnorePointer(child: RepaintBoundary(child: dots));
  }
}

class _DotPainter extends CustomPainter {
  final Color color;
  final double spacing;
  final double radius;

  _DotPainter({required this.color, required this.spacing, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.color != color || old.spacing != spacing || old.radius != radius;
}
