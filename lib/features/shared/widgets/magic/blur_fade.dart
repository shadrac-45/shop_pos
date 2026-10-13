/// ============================================
/// BlurFade — ShopPOS
/// ============================================
/// Entrance animation after Magic UI's blur-fade:
/// the child fades in, un-blurs and rises a few
/// pixels once, when first built. Skipped when the
/// OS asks for reduced motion.
/// ============================================
library;

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:shop_pos/core/theme/app_motion.dart';

class BlurFade extends StatefulWidget {
  final Widget child;

  /// Wait before starting.
  final Duration delay;

  /// Position in a staggered sequence; adds [AppMotion.stagger] per step.
  final int index;

  final Duration duration;

  /// How far below its resting place the child starts.
  final double offset;

  /// Starting blur radius.
  final double blur;

  const BlurFade({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.medium,
    this.offset = 8,
    this.blur = 6,
  }) : index = 0;

  /// One of several items entering in order; [index] sets the delay.
  const BlurFade.staggered({
    super.key,
    required this.index,
    required this.child,
    this.duration = AppMotion.medium,
    this.offset = 8,
    this.blur = 6,
  }) : delay = Duration.zero;

  @override
  State<BlurFade> createState() => _BlurFadeState();
}

class _BlurFadeState extends State<BlurFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t =
      CurvedAnimation(parent: _controller, curve: AppMotion.curve);
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
      return;
    }
    final wait = widget.delay + AppMotion.stagger * widget.index;
    if (wait == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(wait, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final v = _t.value;
        if (v >= 1) return child!;
        final sigma = widget.blur * (1 - v);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - v)),
            child: sigma < 0.1
                ? child
                : ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: child,
                  ),
          ),
        );
      },
    );
  }
}
