/// ============================================
/// Setup Complete Screen — ShopPOS
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/main/screens/main_shell_screen.dart';

class SetupCompleteScreen extends ConsumerWidget {
  const SetupCompleteScreen({super.key});

  Future<void> _goToDashboard(BuildContext context, WidgetRef ref) async {
    // Ensure the owner user is set in Riverpod session
    if (ref.read(currentUserProvider) == null) {
      try {
        final isar = ref.read(isarProvider);
        final allUsers = await isar.appUsers.where().findAll();
        final owner = allUsers.where((u) => u.role == 'owner').firstOrNull;
        if (owner != null) {
          ref.read(currentUserProvider.notifier).setUser(owner);
        }
      } catch (e) {
        debugPrint('[SetupComplete] Could not fetch owner: $e');
      }
    }

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShellScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Success Icon ──────────────────────
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 36, color: AppColors.success),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Title ─────────────────────────────
                  Text(
                    'Your store is ready!',
                    style: Theme.of(context).textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'All setup steps are complete. You are logged in as admin to manage your store.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Go to Dashboard ───────────────────
                  ElevatedButton(
                    onPressed: () => _goToDashboard(context, ref),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(240, 52)),
                    child: const Text('Go to dashboard'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

