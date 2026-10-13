/// ============================================
/// NumberTicker — ShopPOS
/// ============================================
/// A figure that counts up to its value (Magic UI
/// number-ticker). When the value changes it rolls
/// from the old figure to the new one. Jumps
/// straight to the value under reduced motion.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:shop_pos/core/theme/app_motion.dart';

class NumberTicker extends StatelessWidget {
  final double value;

  /// Where the first count starts.
  final double startValue;

  /// Turns the running number into text, e.g. a currency formatter.
  final String Function(double)? format;

  final TextStyle? style;
  final Duration duration;

  const NumberTicker({
    super.key,
    required this.value,
    this.startValue = 0,
    this.format,
    this.style,
    this.duration = AppMotion.slow,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = format ?? (v) => v.round().toString();
    // Screen readers get the final figure, not every frame of the count.
    return Semantics(
      label: fmt(value),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: startValue, end: value),
        duration: AppMotion.reduced(context) ? Duration.zero : duration,
        curve: AppMotion.curve,
        builder: (context, v, _) => Text(fmt(v), style: style),
      ),
    );
  }
}
