import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../sales/screens/cashier_sales_screen.dart';
import '../../products/screens/owner_products_screen.dart';
import '../../../providers/auth_provider.dart';

class MainShellScreen extends ConsumerWidget {
  const MainShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isOwner = user?.role == "owner";

    return Scaffold(
      appBar: AppBar(
        title: const Text('ShopPOS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(currentUserProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: isOwner ? const OwnerProductsScreen() : const CashierSalesScreen(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.point_of_sale),
            label: 'Sales',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory),
            label: 'Products',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Reports',
          ),
        ],
        onTap: (index) {
          // Navigation logic can be expanded later
        },
      ),
    );
  }
}
