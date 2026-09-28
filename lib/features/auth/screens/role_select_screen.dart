/// ============================================
/// Role Select Screen — ShopPOS
/// ============================================
/// Shown to returning users (after setup is done).
/// Lets them choose Admin login (email+pass)
/// or Cashier login (PIN pad).
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/screens/admin_login_screen.dart';
import 'package:shop_pos/features/auth/screens/login_screen.dart';

class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14151D),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Logo ─────────────────────────────────
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: AppSpacing.borderMd,
                    ),
                    child: const Icon(Icons.shopping_cart_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text(
                    'ShopPOS',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Who is logging in?',
                    style: TextStyle(color: Color(0xFF8B8EA3), fontSize: 14),
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // ── Admin Tile ────────────────────────────
                  _RoleTile(
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'Admin / Owner',
                    subtitle: 'Email & password',
                    color: AppColors.primary,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          const AdminLoginScreen(setupAlreadyDone: true),
                    )),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── Cashier Tile ──────────────────────────
                  _RoleTile(
                    icon: Icons.point_of_sale_rounded,
                    title: 'Cashier',
                    subtitle: '4-digit PIN',
                    color: const Color(0xFF2563EB),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LoginScreen(),
                    )),
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

class _RoleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E2028),
      borderRadius: AppSpacing.borderLg,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.borderLg,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppSpacing.borderLg,
            border: Border.all(color: const Color(0xFF2A2C38)),
          ),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: AppSpacing.borderMd,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Color(0xFF8B8EA3), fontSize: 13)),
                  ]),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Color(0xFF8B8EA3), size: 16),
          ]),
        ),
      ),
    );
  }
}
