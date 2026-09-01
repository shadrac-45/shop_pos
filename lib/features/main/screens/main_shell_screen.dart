/// ============================================
/// Main Shell Screen — ShopPOS
/// ============================================
/// Navigation shell that switches between the
/// app's top-level destinations (Sales, Products,
/// Reports, Settings).
///
/// Uses [IndexedStack] so tab state (search queries,
/// scroll positions, loaded data) is preserved.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/constants/app_assets.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/auth/screens/login_screen.dart';
import 'package:shop_pos/features/products/screens/owner_products_screen.dart';
import 'package:shop_pos/features/reports/screens/daily_report_screen.dart';
import 'package:shop_pos/features/sales/screens/cashier_sales_screen.dart';
import 'package:shop_pos/features/settings/screens/settings_screen.dart';

class _NavDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget body;

  const _NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.body,
  });
}

class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  int _currentIndex = 0;

  static final _ownerDestinations = <_NavDestination>[
    const _NavDestination(
      label: 'Sales',
      icon: Icons.point_of_sale_outlined,
      selectedIcon: Icons.point_of_sale_rounded,
      body: CashierSalesScreen(),
    ),
    const _NavDestination(
      label: 'Products',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
      body: OwnerProductsScreen(),
    ),
    const _NavDestination(
      label: 'Reports',
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics_rounded,
      body: DailyReportScreen(),
    ),
    const _NavDestination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      body: SettingsScreen(),
    ),
  ];

  static final _cashierDestinations = <_NavDestination>[
    const _NavDestination(
      label: 'Sales',
      icon: Icons.point_of_sale_outlined,
      selectedIcon: Icons.point_of_sale_rounded,
      body: CashierSalesScreen(),
    ),
    const _NavDestination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      body: SettingsScreen(),
    ),
  ];

  void _logout() {
    ref.read(currentUserProvider.notifier).logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isOwner = user?.role == 'owner';

    final destinations = isOwner ? _ownerDestinations : _cashierDestinations;
    final safeIndex = _currentIndex.clamp(0, destinations.length - 1);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        leadingWidth: 52,
        leading: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.md, top: 8, bottom: 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppSpacing.borderSm,
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.all(4),
            child: Image.asset(
              AppAssets.shopposLogo,
              height: 28,
              fit: BoxFit.contain,
            ),
          ),
        ),
        title: Row(
          children: [
            Text(
              destinations[safeIndex].label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                fontSize: 18,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: AppSpacing.borderSm,
              ),
              child: Text(
                user?.role.toUpperCase() ?? 'POS',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.textSecondary),
            tooltip: 'Logout',
            constraints: AppTouch.touchConstraints,
            onPressed: _logout,
          ),
        ],
      ),
      body: IndexedStack(
        index: safeIndex,
        children: destinations.map((d) => d.body).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: destinations
            .map(
              (d) => NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
            )
            .toList(),
      ),
    );
  }
}
