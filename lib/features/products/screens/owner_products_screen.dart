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

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/responsive/app_breakpoints.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/products/providers/product_provider.dart';
import 'package:shop_pos/features/products/services/csv_import_service.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/core/utils/expiry_helpers.dart';
import 'package:shop_pos/features/products/widgets/add_product_dialog.dart';
import 'package:shop_pos/features/products/widgets/csv_import_dialog.dart';
import 'package:shop_pos/features/shared/widgets/app_empty_state.dart';
import 'package:shop_pos/features/shared/widgets/app_skeleton.dart';
import 'package:shop_pos/features/products/widgets/edit_product_dialog.dart';
import 'package:shop_pos/features/products/widgets/restock_batch_dialog.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';

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

  void _showImportCsvDialog() {
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CsvImportDialog(),
    ).then((count) {
      if (count != null && count > 0) {
        ref.invalidate(productServiceProvider);
      }
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

  Future<void> _loadSampleProducts() async {
    HapticFeedback.mediumImpact();
    final isar = ref.read(isarProvider);
    final count = await CsvImportService.seedSampleProducts(isar);
    if (!mounted) return;
    context.showSuccessSnackbar('Loaded $count sample products into catalog!');
    ref.invalidate(productServiceProvider);
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
      // The header adapts to the width it is actually given rather than
      // assuming a tablet. On a 360dp phone the avatar, the title and
      // two full-width buttons do not fit, so the action collapses to an
      // icon that still meets the 48dp touch minimum.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 400;

          return Row(
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ownerName,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text(
                      'Inventory & Stock Management',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (compact)
                IconButton(
                  onPressed: _showImportCsvDialog,
                  tooltip: 'Import CSV / Excel',
                  icon: const Icon(Icons.file_upload_outlined, size: 20),
                  color: AppColors.primary,
                  style: IconButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size(AppTouch.minTargetSize, AppTouch.minTargetSize),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: _showImportCsvDialog,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Import CSV / Excel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: const Size(0, AppTouch.minTargetSize),
                  ),
                ),
            ],
          );
        },
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
      if (_searchQuery.isNotEmpty) {
        return AppEmptyState(
          icon: Icons.search_off_rounded,
          title: 'No Matching Products',
          description: 'No product matches "$_searchQuery".',
          actionLabel: 'Clear Search',
          onAction: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          },
        );
      }

      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Your Inventory is Empty',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Populate your catalog instantly with 8 retail products, import from CSV or Excel, or create items manually.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton.icon(
                onPressed: _showAddProduct,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text(
                  'Add Product',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(270, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppSpacing.borderMd,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _showImportCsvDialog,
                icon: const Icon(Icons.file_upload_outlined, size: 20),
                label: const Text('Import from CSV File'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  minimumSize: const Size(270, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppSpacing.borderMd,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: _loadSampleProducts,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Load Sample Demo Products (8 Items)'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  minimumSize: const Size(270, 44),
                ),
              ),
            ],
          ),
        ),
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

  /// First character shown in the tile avatar. Guards against an empty
  /// or whitespace-only name, which would throw on a bare substring, and
  /// reads runes rather than code units so an emoji or accented leading
  /// character renders as one whole glyph instead of half a surrogate.
  static String _avatarInitial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCodes(trimmed.runes.take(1)).toUpperCase();
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
                      _avatarInitial(product.name),
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
