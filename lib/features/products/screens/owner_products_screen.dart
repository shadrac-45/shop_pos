/// ============================================
/// Owner Products Screen — ShopPOS
/// ============================================
/// Product management interface for the owner:
/// - List products with stock & expiry status
/// - Add new products
/// - Expand to view/manage batches
/// - Restock batch modal
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/theme/app_colors.dart';

import '../../../models/product.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../utils/currency_helpers.dart';
import '../../../utils/expiry_helpers.dart';
import '../../auth/screens/login_screen.dart';
import '../../common/widgets/add_product_dialog.dart';
import '../../common/widgets/edit_product_dialog.dart';
import '../../common/widgets/restock_batch_dialog.dart';

class OwnerProductsScreen extends ConsumerStatefulWidget {
  const OwnerProductsScreen({super.key});

  @override
  ConsumerState<OwnerProductsScreen> createState() =>
      _OwnerProductsScreenState();
}

class _OwnerProductsScreenState extends ConsumerState<OwnerProductsScreen> {
  int _expandedProductId = -1;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Toggle expansion of a product's batch list.
  void _toggleExpand(int productId) {
    HapticFeedback.selectionClick();
    setState(() {
      _expandedProductId = _expandedProductId == productId ? -1 : productId;
    });
  }

  /// Handle logout.
  void _logout() {
    ref.read(currentUserProvider.notifier).logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  /// Show add product dialog.
  void _showAddProduct() {
    showDialog(
      context: context,
      builder: (_) => const AddProductDialog(),
    ).then((_) {
      ref.invalidate(productServiceProvider);
    });
  }

  /// Show restock batch dialog.
  void _showRestockBatch(Product product) {
    showDialog(
      context: context,
      builder: (_) => RestockBatchDialog(product: product),
    ).then((_) {
      ref.invalidate(productServiceProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final productsAsync = ref.watch(productServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(currentUser?.name ?? 'Owner'),

            // Search Bar
            _buildSearchBar(),

            // Product List
            Expanded(
              child: productsAsync.when(
                data: (products) {
                  final filtered = _searchQuery.isEmpty
                      ? products
                      : products
                          .where((p) =>
                              p.name
                                  .toLowerCase()
                                  .contains(_searchQuery.toLowerCase()) ||
                              (p.category
                                  .toLowerCase()
                                  .contains(_searchQuery.toLowerCase())))
                          .toList();

                  return _buildProductList(filtered);
                },
                loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
                error: (err, _) => Center(
                  child: Text('Error: $err',
                      style: const TextStyle(color: AppColors.danger)),
                ),
              ),
            ),
          ],
        ),
      ),

      // FAB: Add Product
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProduct,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 4,
        icon: const Icon(Icons.add_rounded, size: 24),
        label: const Text(
          'Add Product',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildHeader(String ownerName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF9C27B0), Color(0xFFCE93D8)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.admin_panel_settings_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ownerName,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
                const Text('Product Management',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded,
                color: AppColors.textSecondary, size: 22),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surfaceBg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surfaceBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search products...',
            hintStyle:
                const TextStyle(color: AppColors.textMuted, fontSize: 15),
            prefixIcon: const Icon(Icons.search_rounded,
                color: AppColors.textMuted, size: 22),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded,
                        color: AppColors.textMuted, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildProductList(List<Product> products) {
    if (products.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 72, color: AppColors.textMuted),
            SizedBox(height: 16),
            Text('No products yet',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            SizedBox(height: 8),
            Text('Tap the + button to add your first product',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      physics: const BouncingScrollPhysics(),
      itemCount: products.length,
      itemBuilder: (context, index) => _buildProductTile(products[index]),
    );
  }

  Widget _buildProductTile(Product product) {
    final isExpanded = _expandedProductId == product.id;
    final expiryColor = ExpiryHelpers.getColor(product.daysUntilExpiry);
    final expiryIcon = ExpiryHelpers.getIcon(product.daysUntilExpiry);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
          width: isExpanded ? 2.0 : 1.0,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleExpand(product.id),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color(product.quickButtonColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        product.name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              CurrencyHelpers.formatCompact(product.price),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Stock: ${product.totalStock}',
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                        if (product.daysUntilExpiry != 0 &&
                            product.daysUntilExpiry <= 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text('EXPIRED – Remove!',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.danger)),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: expiryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(expiryIcon, size: 14, color: expiryColor),
                        const SizedBox(width: 4),
                        Text(
                          ExpiryHelpers.getChipText(product.daysUntilExpiry),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: expiryColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textMuted, size: 24),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) _buildBatchDetails(product),
        ],
      ),
    );
  }

  Widget _buildBatchDetails(Product product) {
    // Note: product.batches link needs to be preloaded or use a separate provider.
    // For simplicity we show a placeholder. You can enhance with productBatchesProvider later.
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Batches loading... (enhance with dedicated provider)',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showRestockBatch(product),
                    icon: const Icon(Icons.add_box_rounded, size: 18),
                    label: const Text('Restock Batch',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => EditProductDialog(product: product),
                      ).then((_) => ref.invalidate(productServiceProvider));
                    },
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit Product',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
