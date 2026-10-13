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
import 'package:shop_pos/features/shared/widgets/auth_scaffold.dart';
import 'package:shop_pos/features/shared/widgets/magic/magic.dart';

class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BlurFade(
            child: AuthHeader(
              title: 'ShopPOS',
              subtitle: 'Who is logging in?',
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // ── Admin Tile ────────────────────────────
          BlurFade.staggered(
            index: 2,
            child: RoleTile(
              icon: Icons.admin_panel_settings_rounded,
              title: 'Admin / Owner',
              subtitle: 'Email or username & password',
              color: AppColors.primary,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminLoginScreen(setupAlreadyDone: true),
              )),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Cashier Tile ──────────────────────────
          BlurFade.staggered(
            index: 3,
            child: RoleTile(
              icon: Icons.point_of_sale_rounded,
              title: 'Staff',
              subtitle: '4–6 digit PIN',
              color: AppColors.textSecondary,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LoginScreen(),
              )),
            ),
          ),
        ],
      ),
    );
  }
}
