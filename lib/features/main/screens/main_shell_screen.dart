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

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/constants/app_assets.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/products/screens/owner_products_screen.dart';
import 'package:shop_pos/features/reports/screens/daily_report_screen.dart';
import 'package:shop_pos/features/sales/screens/cashier_history_screen.dart';
import 'package:shop_pos/features/sales/screens/cashier_sales_screen.dart';
import 'package:shop_pos/features/settings/screens/settings_screen.dart';
import 'package:shop_pos/features/settings/widgets/change_pin_dialog.dart';

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

  static const _sales = _NavDestination(
    label: 'Sales',
    icon: Icons.point_of_sale_outlined,
    selectedIcon: Icons.point_of_sale_rounded,
    body: CashierSalesScreen(),
  );
  static const _mySales = _NavDestination(
    label: 'My Sales',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
    body: CashierHistoryScreen(),
  );
  static const _products = _NavDestination(
    label: 'Products',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2_rounded,
    body: OwnerProductsScreen(),
  );
  static const _reports = _NavDestination(
    label: 'Reports',
    icon: Icons.analytics_outlined,
    selectedIcon: Icons.analytics_rounded,
    body: DailyReportScreen(),
  );
  static const _settings = _NavDestination(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    body: SettingsScreen(),
  );

  /// Tabs follow the role's permissions (see [Permissions]), so a manager
  /// gets the owner's screens and a stock clerk gets only Products.
  static List<_NavDestination> _destinationsFor(AppUser? user) {
    final canReport = Permissions.can(user, Permission.viewReports);
    final canStock = Permissions.can(user, Permission.restock) ||
        Permissions.can(user, Permission.manageProducts);
    return [
      if (Permissions.can(user, Permission.sell)) _sales,
      if (Permissions.can(user, Permission.sell) && !canReport) _mySales,
      if (canStock) _products,
      if (canReport) _reports,
      _settings,
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptIfDefaultPin());
  }

  /// A user who still has a default PIN (the owner, signing in by email)
  /// is asked to replace it straight away; PIN login refuses it anyway.
  Future<void> _promptIfDefaultPin() async {
    final auth = ref.read(currentUserProvider.notifier);
    final user = ref.read(currentUserProvider);
    if (!mounted || user == null || !auth.hasDefaultPin) return;

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangePinDialog(user: user),
    );
    if (!mounted) return;
    if (changed == true) {
      context.showSuccessSnackbar('Your PIN has been updated.');
    } else {
      context.showErrorSnackbar(
        'Your PIN is still a default PIN, so PIN login stays disabled for '
        'you. Change it in Settings → Change PIN.',
      );
    }
  }

  /// Navigation back to the role picker is handled app-wide in
  /// [ShopPOSApp] whenever the user becomes null.
  void _logout() => ref.read(currentUserProvider.notifier).logout();

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final storeName = ref.watch(storeSettingsProvider).storeName.trim();

    final destinations = _destinationsFor(user);
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
            if (storeName.isNotEmpty) ...[
              Flexible(
                child: Text(
                  storeName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Text(' · ', style: TextStyle(color: AppColors.textMuted)),
            ],
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
                user == null ? 'POS' : AppConstants.roleLabel(user.role).toUpperCase(),
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
