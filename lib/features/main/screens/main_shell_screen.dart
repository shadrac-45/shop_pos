/// ============================================
/// Main Shell Screen — ShopPOS
/// ============================================
/// Implements the main navigation scaffold with
/// an IndexedStack to preserve state across tabs.
/// Hides the Products tab for cashiers.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/product_provider.dart';
import '../../sales/screens/cashier_sales_screen.dart';
import '../../products/screens/owner_products_screen.dart';
import '../../reports/screens/daily_report_screen.dart';

class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkExpiryAlerts();
    });
  }

  Future<void> _checkExpiryAlerts() async {
    try {
      final expiringProducts = await ref.read(expiringProductsProvider.future);
      if (expiringProducts.isNotEmpty) {
        final notificationService = ref.read(notificationServiceProvider);
        await notificationService.showExpiryAlert(
          expiringCount: expiringProducts.length,
          body: 'Check the Sales or Products tab for details.',
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isOwner = user?.role == 'owner';

    // Construct the tabs based on role
    final List<Widget> screens = [
      const CashierSalesScreen(),
      if (isOwner) const OwnerProductsScreen(),
      const DailyReportScreen(),
      const Center(child: Text('Settings coming soon!', style: TextStyle(color: AppColors.textSecondary))),
    ];

    final List<BottomNavigationBarItem> navItems = [
      const BottomNavigationBarItem(
        icon: Icon(Icons.point_of_sale_rounded),
        label: 'Sales',
      ),
      if (isOwner)
        const BottomNavigationBarItem(
          icon: Icon(Icons.inventory_2_rounded),
          label: 'Products',
        ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.bar_chart_rounded),
        label: 'Reports',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.settings_rounded),
        label: 'Settings',
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBg,
          border: Border(
            top: BorderSide(color: AppColors.border, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textMuted,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          type: BottomNavigationBarType.fixed,
          items: navItems,
        ),
      ),
    );
  }
}
