/// ============================================
/// App Empty State — ShopPOS
/// ============================================
/// Polished empty state with icon visual, headline,
/// description, and optional action CTA.
/// Handles both bounded screens and unbounded scrollable containers
/// without layout assertion failures.
/// ============================================
library;

import 'package:flutter/material.dart';

import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/shared/widgets/magic/blur_fade.dart';

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = BlurFade(child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon on two soft rings — reads as "nothing here yet" rather
          // than as an error.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppColors.primaryDark),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              description,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    ));

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight.isFinite && constraints.maxHeight > 100) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - AppSpacing.md * 2)
                    .clamp(0.0, double.infinity),
              ),
              child: Center(child: content),
            ),
          );
        }
        return Center(child: content);
      },
    );
  }
}
