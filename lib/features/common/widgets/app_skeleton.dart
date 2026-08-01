/// ============================================
/// App Skeleton Loader — ShopPOS
/// ============================================
/// Smooth shimmer/pulse animation used while data
/// is loading instead of generic circular spinners.
/// ============================================
library;

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

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
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.surfaceBg.withValues(alpha: _animation.value),
            borderRadius: widget.borderRadius ?? AppSpacing.borderMd,
          ),
        );
      },
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
        childAspectRatio: 0.9,
      ),
      itemCount: count,
      itemBuilder: (_, __) => const AppSkeletonLoader.card(height: double.infinity),
    );
  }
}
