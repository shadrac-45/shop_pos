/// ============================================
/// Welcome Screen — ShopPOS
/// ============================================
/// First launch on a device: either set up a new
/// shop (the setup wizard) or join a shop that
/// already exists in ShopPOS Cloud (no new shop,
/// no new owner — the device downloads the shop).
/// ============================================
library;

import 'package:flutter/material.dart';

import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/screens/admin_login_screen.dart';
import 'package:shop_pos/features/cloud/screens/join_shop_screen.dart';
import 'package:shop_pos/features/shared/widgets/auth_scaffold.dart';
import 'package:shop_pos/features/shared/widgets/magic/magic.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BlurFade(
            child: AuthHeader(
              title: 'Welcome to ShopPOS',
              subtitle: 'How will you use this device?',
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          BlurFade.staggered(
            index: 2,
            child: RoleTile(
              icon: Icons.add_business_rounded,
              title: 'Create a new shop',
              subtitle: 'First device of a new business',
              color: AppColors.primary,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminLoginScreen(setupAlreadyDone: false),
              )),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          BlurFade.staggered(
            index: 3,
            child: RoleTile(
              icon: Icons.cloud_download_rounded,
              title: 'Join an existing shop',
              subtitle: 'Sign in with your ShopPOS account',
              color: AppColors.textSecondary,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const JoinShopScreen(),
              )),
            ),
          ),
        ],
      ),
    );
  }
}
