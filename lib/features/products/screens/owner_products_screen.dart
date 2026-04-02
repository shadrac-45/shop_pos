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
import '../../../core/constants/app_constants.dart';
import '../../../models/product.dart';
import '../../../models/batch.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../utils/currency_helpers.dart';
import '../../../utils/date_helpers.dart';
import '../../auth/screens/login_screen.dart';
import '../../sales/screens/cashier_sales_screen.dart';
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
  final int _currentNavIndex = 1; // 0=Sales, 1=Products, 2=Reports, 3=Settings
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
      _expandedProductId =
          _expandedProductId == productId ? -1 : productId;
    });
  }

  /// Handle logout.
  void _logout() {
    ref.read(authServiceProvider).logout();
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
      // Refresh products after dialog closes
      ref.invalidate(productsProvider);
    });
  }

  /// Show restock batch dialog.
  void _showRestockBatch(Product product) {
    showDialog(
      context: context,
      builder: (_) => RestockBatchDialog(product: product),
    ).then((_) {
      // Refresh products after dialog closes
      ref.invalidate(productsProvider);
      ref.invalidate(productBatchesProvider(product.id));
    });
  }

  /// Get expiry color based on days remaining.
  Color _getExpiryColor(int? days) {
    if (days == null) return AppColors.textMuted;
    if (days < 0) return AppColors.danger;
    if (days <= AppConstants.expiryUrgentDays) return AppColors.expiryUrgent;
    if (days <= AppConstants.expirySoonDays) return AppColors.expirySoon;
    return AppColors.expiryGood;
  }

  /// Get expiry icon based on days remaining.
  IconData _getExpiryIcon(int? days) {
    if (days == null) return Icons.inventory_2_outlined;
    if (days < 0) return Icons.error_rounded;
    if (days <= AppConstants.expiryUrgentDays) return Icons.warning_rounded;
    if (days <= AppConstants.expirySoonDays) return Icons.schedule_rounded;
    return Icons.check_circle_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final productsAsync = ref.watch(productsProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────
            _buildHeader(currentUser?.name ?? 'Owner'),

            // ── Search Bar ────────────────────────────
            _buildSearchBar(),

            // ── Product List ──────────────────────────
            Expanded(
              child: productsAsync.when(
                data: (products) {
                  // Local filter by name or barcode
                  final filtered = _searchQuery.isEmpty
                      ? products
                      : products
                          .where((p) =>
                              p.name
                                  .toLowerCase()
                                  .contains(_searchQuery.toLowerCase()) ||
                              (p.barcode
                                      ?.toLowerCase()
                                      .contains(_searchQuery.toLowerCase()) ??
                                  false))
                          .toList();
                  return _buildProductList(filtered);
                },
                loading: () => const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (err, _) => Center(
                  child: Text('Error: $err',
                      style: const TextStyle(color: AppColors.danger)),
                ),
              ),
            ),
          ],
        ),
      ),

      // ── FAB: Add Product ───────────────────────
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

  /// Short text for the expiry chip badge.
  String _getExpiryText(int? days) {
    if (days == null) return 'No stock';
    if (days <= 0) return 'EXPIRED';
    if (days <= AppConstants.expiryUrgentDays) return '${days}d left';
    return '${days}d';
  }

  /// Search bar for filtering products.
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
            hintText: 'Search products or barcode...',
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

  /// Header with owner name and logout.
  Widget _buildHeader(String ownerName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Owner avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF9C27B0), Color(0xFFCE93D8)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),

          const SizedBox(width: 12),

          // Owner name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ownerName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Text(
                  'Product Management',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Logout button
          IconButton(
            onPressed: _logout,
            icon: const Icon(
              Icons.logout_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surfaceBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Product list with expandable batch details.
  Widget _buildProductList(List<Product> products) {
    if (products.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 72,
              color: AppColors.textMuted,
            ),
            SizedBox(height: 16),
            Text(
              'No products yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Tap the + button to add your first product',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
              ),
            ),
            SizedBox(height: 80), // Space for FAB
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      physics: const BouncingScrollPhysics(),
      itemCount: products.length,
      itemBuilder: (context, index) {
        return _buildProductTile(products[index]);
      },
    );
  }

  /// Individual product tile with expiry indicator.
  Widget _buildProductTile(Product product) {
    final isExpanded = _expandedProductId == product.id;
    final expiryColor = _getExpiryColor(product.daysUntilExpiry);
    final expiryIcon = _getExpiryIcon(product.daysUntilExpiry);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border,
          width: isExpanded ? 2.0 : 1.0,
        ),
      ),
      child: Column(
        children: [
          // Product row
          InkWell(
            onTap: () => _toggleExpand(product.id),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Color indicator
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
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Product info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              CurrencyHelpers.formatCompact(product.price),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Stock: ${product.totalStock}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        // Red "EXPIRED – Remove!" warning for expired products
                        if (product.daysUntilExpiry != null &&
                            product.daysUntilExpiry! <= 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              'EXPIRED \u2013 Remove!',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Expiry indicator
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
                          _getExpiryText(product.daysUntilExpiry),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: expiryColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Expand arrow
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textMuted,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded batch details
          if (isExpanded) _buildBatchDetails(product),
        ],
      ),
    );
  }

  /// Expanded section showing batches + restock button.
  Widget _buildBatchDetails(Product product) {
    final batchesAsync = ref.watch(productBatchesProvider(product.id));

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Batch list
          batchesAsync.when(
            data: (batches) {
              if (batches.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No active batches',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                    ),
                  ),
                );
              }

              return Column(
                children: batches.map((batch) {
                  return _buildBatchRow(batch);
                }).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $err',
                  style: const TextStyle(color: AppColors.danger)),
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Row(
              children: [
                // Restock button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showRestockBatch(product),
                    icon: const Icon(Icons.add_box_rounded, size: 18),
                    label: const Text(
                      'Restock Batch',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Edit button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => EditProductDialog(product: product),
                      ).then((_) {
                        ref.invalidate(productsProvider);
                      });
                    },
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text(
                      'Edit Product',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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

  /// Individual batch row.
  Widget _buildBatchRow(Batch batch) {
    final batchExpiryColor = _getExpiryColor(batch.daysUntilExpiry);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Batch quantity
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${batch.quantity}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Expiry date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exp: ${DateHelpers.formatShort(batch.expiryDate)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: batchExpiryColor,
                  ),
                ),
                if (batch.supplierNote != null &&
                    batch.supplierNote!.isNotEmpty)
                  Text(
                    batch.supplierNote!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Days until expiry
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: batchExpiryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              batch.isExpired
                  ? 'EXPIRED'
                  : '${batch.daysUntilExpiry}d left',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: batchExpiryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }


}
