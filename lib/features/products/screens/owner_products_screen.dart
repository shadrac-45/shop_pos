/// ============================================
/// Owner Products Screen — ShopPOS
/// ============================================
/// Touch-first product management interface:
///   • Structured product card list with stock & expiry indicators
///   • Expandable batch details with restock & edit actions
///   • Skeleton loader placeholder & rich empty states
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/responsive/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/product.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../utils/currency_helpers.dart';
import '../../../utils/date_helpers.dart';
import '../../../utils/expiry_helpers.dart';
import '../../common/widgets/add_product_dialog.dart';
import '../../common/widgets/app_empty_state.dart';
import '../../common/widgets/app_skeleton.dart';
import '../../common/widgets/edit_product_dialog.dart';
import '../../common/widgets/restock_batch_dialog.dart';
import '../../common/widgets/touchable_card.dart';

class OwnerProductsScreen extends ConsumerStatefulWidget {
  const OwnerProductsScreen({super.key});

  @override
  ConsumerState<OwnerProductsScreen> createState() => _OwnerProductsScreenState();
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

  void _toggleExpand(int productId) {
    HapticFeedback.selectionClick();
    setState(() {
      _expandedProductId = _expandedProductId == productId ? -1 : productId;
    });
  }

  void _showAddProduct() {
    showDialog(
      context: context,
      builder: (_) => const AddProductDialog(),
    ).then((_) {
      ref.invalidate(productServiceProvider);
    });
  }

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
            _buildHeader(currentUser?.name ?? 'Owner'),
            _buildSearchBar(),
            Expanded(
              child: productsAsync.when(
                data: (products) {
                  final filtered = _searchQuery.isEmpty
                      ? products
                      : products
                          .where((p) =>
                              p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                              p.category.toLowerCase().contains(_searchQuery.toLowerCase()))
                          .toList();

                  return _buildProductList(filtered);
                },
                loading: () => ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: 5,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, __) => const AppSkeletonLoader.card(height: 72),
                ),
                error: (err, _) => AppEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Error Loading Inventory',
                  description: err.toString(),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProduct,
        icon: const Icon(Icons.add_rounded, size: 24),
        label: const Text(
          'Add Product',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildHeader(String ownerName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: AppSpacing.borderMd,
            ),
            child: const Icon(Icons.inventory_2_rounded, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ownerName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Inventory & Stock Management',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search product catalog...',
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: AppColors.textSecondary, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildProductList(List<Product> products) {
    if (products.isEmpty) {
      return AppEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No Products Yet',
        description: _searchQuery.isNotEmpty
            ? 'No product matches "$_searchQuery".'
            : 'Tap the "+ Add Product" button below to add your first product.',
        actionLabel: _searchQuery.isNotEmpty ? 'Clear Search' : 'Add First Product',
        onAction: _searchQuery.isNotEmpty
            ? () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              }
            : _showAddProduct,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = AppBreakpoints.isTablet(constraints.maxWidth);

        if (isTablet) {
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 100),
            physics: const BouncingScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
              childAspectRatio: 3.5,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) => _buildProductTile(products[index]),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 100),
          physics: const BouncingScrollPhysics(),
          itemCount: products.length,
          itemBuilder: (context, index) => _buildProductTile(products[index]),
        );
      },
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
        borderRadius: AppSpacing.borderLg,
        border: Border.all(
          color: isExpanded ? AppColors.primary : AppColors.border,
          width: isExpanded ? 1.8 : 1.0,
        ),
      ),
      child: Column(
        children: [
          TouchableCard(
            onTap: () => _toggleExpand(product.id),
            backgroundColor: Colors.transparent,
            borderColor: Colors.transparent,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color(product.quickButtonColor),
                    borderRadius: AppSpacing.borderMd,
                  ),
                  child: Center(
                    child: Text(
                      product.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              CurrencyHelpers.formatCompact(product.price),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Flexible(
                            child: Text(
                              'Stock: ${product.totalStock}',
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (product.daysUntilExpiry != 0 && product.daysUntilExpiry <= 0)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            'EXPIRED – Remove!',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: expiryColor.withValues(alpha: 0.15),
                    borderRadius: AppSpacing.borderSm,
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
                          fontWeight: FontWeight.bold,
                          color: expiryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary, size: 24),
                ),
              ],
            ),
          ),
          if (isExpanded) _buildBatchDetails(product),
        ],
      ),
    );
  }

  Widget _buildBatchDetails(Product product) {
    final batchesAsync = ref.watch(productBatchesProvider(product.id));

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        children: [
          batchesAsync.when(
            data: (batches) {
              if (batches.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text('No batches restocked yet.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                itemCount: batches.length,
                separatorBuilder: (_, __) => const Divider(color: AppColors.border, height: 1),
                itemBuilder: (context, index) {
                  final batch = batches[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Qty: ${batch.quantity}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            if (batch.supplierNote != null && batch.supplierNote!.isNotEmpty)
                              Text(
                                batch.supplierNote!,
                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                              ),
                          ],
                        ),
                        Text(
                          'Expires: ${DateHelpers.formatShort(batch.expiryDate)}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text('Error loading batches: $err', style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showRestockBatch(product),
                    icon: const Icon(Icons.add_box_rounded, size: 18),
                    label: const Text('Restock Batch'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      minimumSize: const Size(double.infinity, AppTouch.buttonHeight),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => EditProductDialog(product: product),
                      ).then((_) => ref.invalidate(productServiceProvider));
                    },
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit Product'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      minimumSize: const Size(double.infinity, AppTouch.buttonHeight),
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
