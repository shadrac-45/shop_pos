/// ============================================
/// App Skeleton Loader — ShopPOS
/// ============================================
/// Shimmer sweep used while data
/// is loading instead of generic circular spinners.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_motion.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';

class AppSkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const AppSkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  const AppSkeletonLoader.card({
    super.key,
    this.width = double.infinity,
    this.height = 100,
    this.borderRadius,
  });

  const AppSkeletonLoader.tile({
    super.key,
    this.width = double.infinity,
    this.height = 64,
    this.borderRadius,
  });

  @override
  State<AppSkeletonLoader> createState() => _AppSkeletonLoaderState();
}

class _AppSkeletonLoaderState extends State<AppSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: a still placeholder is enough.
    if (AppMotion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? AppSpacing.borderMd;
    // A soft highlight sweeps left to right across the block — the shimmer
    // from Magic UI's shiny-text, applied to a placeholder.
    return Semantics(
      label: 'Loading',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final x = -1.5 + _controller.value * 3;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment(x - 1, -0.3),
                end: Alignment(x + 1, 0.3),
                colors: const [
                  AppColors.surfaceBg,
                  AppColors.cardBg,
                  AppColors.surfaceBg,
                ],
                stops: const [0.25, 0.5, 0.75],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Product grid skeleton placeholder for Cashier Sales screen
class ProductGridSkeleton extends StatelessWidget {
  final int count;
  final int crossAxisCount;

  const ProductGridSkeleton({
    super.key,
    this.count = 8,
    this.crossAxisCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.82,
      ),
      itemCount: count,
      itemBuilder: (_, __) => const AppSkeletonLoader.card(height: double.infinity),
    );
  }
}
