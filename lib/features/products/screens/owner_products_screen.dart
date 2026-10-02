/// ============================================
/// Owner Products Screen — ShopPOS
/// ============================================
/// Touch-first product management interface:
///   • Structured product card list with stock & expiry indicators
///   • Expandable batch details with restock & edit actions
///   • Filters: all / low stock / expiring / archived
///   • Stock adjustments, history, expired write-offs, archiving
///   • Actions shown according to the user's role
///   • Skeleton loader placeholder & rich empty states
/// ============================================
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/screens/stock_history_screen.dart';
import 'package:shop_pos/features/products/services/inventory_service.dart';
import 'package:shop_pos/features/products/widgets/stock_adjust_dialog.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';
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

enum _ProductFilter { all, lowStock, expiring, archived }

class _OwnerProductsScreenState extends ConsumerState<OwnerProductsScreen> {
  int _expandedProductId = -1;
  _ProductFilter _filter = _ProductFilter.all;

  static bool _isExpiring(Product p) => p.batches.any(
      (b) => b.quantity > 0 && b.daysUntilExpiry <= AppConstants.expiryUrgentDays);

  bool _matchesFilter(Product p, _ProductFilter f) => switch (f) {
        _ProductFilter.all => !p.isArchived,
        _ProductFilter.lowStock => !p.isArchived && p.isLowStock,
        _ProductFilter.expiring => !p.isArchived && _isExpiring(p),
        _ProductFilter.archived => p.isArchived,
      };

  void _refreshProduct(Product product) {
    ref.invalidate(productServiceProvider);
    ref.invalidate(productBatchesProvider(product.id));
  }

  void _showAdjust(Product product) {
    showDialog<bool>(
      context: context,
      builder: (_) => StockAdjustDialog(product: product),
    ).then((_) => _refreshProduct(product));
  }

  void _showHistory(Product product) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StockHistoryScreen(product: product),
    ));
  }

  Future<void> _toggleArchive(Product product) async {
    final archiving = !product.isArchived;
    final ok = await confirmDialog(
      context,
      title: archiving ? 'Archive ${product.name}?' : 'Restore ${product.name}?',
      message: archiving
          ? 'It will be hidden from the till and catalog. Past sales are kept, '
              'and you can restore it from the Archived filter.'
          : 'It will appear on the till again.',
      confirmLabel: archiving ? 'Archive' : 'Restore',
      destructive: archiving,
    );
    if (!ok) return;
    try {
      await InventoryService.setArchived(
          ref.read(isarProvider), ref.read(currentUserProvider), product, archiving);
      if (!mounted) return;
      setState(() => _expandedProductId = -1);
      context.showSuccessSnackbar(
          archiving ? '${product.name} archived.' : '${product.name} restored.');
      _refreshProduct(product);
    } catch (e) {
      if (mounted) context.showErrorSnackbar(errorMessage(e));
    }
  }

  Future<void> _writeOff(Product product, Batch batch) async {
    final ok = await confirmDialog(
      context,
      title: 'Write off ${batch.quantity} × ${product.name}?',
      message: 'This batch expired on ${DateHelpers.formatShort(batch.expiryDate)}. '
          'Its remaining stock will be removed and recorded as an expired write-off.',
      confirmLabel: 'Write Off',
      destructive: true,
    );
    if (!ok) return;
    try {
      await InventoryService.writeOffBatch(
          ref.read(isarProvider), ref.read(currentUserProvider),
          product: product, batch: batch);
      if (!mounted) return;
      context.showSuccessSnackbar('Expired stock written off.');
      _refreshProduct(product);
    } catch (e) {
      if (mounted) context.showErrorSnackbar(errorMessage(e));
    }
  }
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
    final canManage = Permissions.can(currentUser, Permission.manageProducts);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(currentUser?.name ?? 'Owner', canManage),
            _buildSearchBar(),
            _buildFilterChips(productsAsync.valueOrNull ?? const []),
            Expanded(
              child: productsAsync.when(
                data: (all) {
                  final products = all.where((p) => _matchesFilter(p, _filter));
                  final filtered = _searchQuery.isEmpty
                      ? products.toList()
                      : products
                          .where((p) =>
                              p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                              p.category.toLowerCase().contains(_searchQuery.toLowerCase()))
                          .toList();

                  if (filtered.isEmpty && _filter != _ProductFilter.all && _searchQuery.isEmpty) {
                    return AppEmptyState(
                      icon: Icons.filter_alt_off_rounded,
                      title: 'Nothing here',
                      description: switch (_filter) {
                        _ProductFilter.lowStock =>
                          'No product is at or below its low-stock level. Set a level in Edit Product.',
                        _ProductFilter.expiring =>
                          'No stock expires within ${AppConstants.expiryUrgentDays} days.',
                        _ => 'No archived products.',
                      },
                      actionLabel: 'Show all',
                      onAction: () => setState(() => _filter = _ProductFilter.all),
                    );
                  }
                  return _buildProductList(filtered, canManage);
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
      floatingActionButton: !canManage
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddProduct,
              icon: const Icon(Icons.add_rounded, size: 24),
              label: const Text(
                'Add Product',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
    );
  }

  Widget _buildFilterChips(List<Product> products) {
    int count(_ProductFilter f) => products.where((p) => _matchesFilter(p, f)).length;
    Widget chip(_ProductFilter f, String label, {Color? color}) {
      final n = count(f);
      final selected = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: ChoiceChip(
          label: Text(f == _ProductFilter.all ? label : '$label ($n)'),
          selected: selected,
          onSelected: (_) => setState(() {
            _filter = f;
            _expandedProductId = -1;
          }),
          selectedColor: color ?? AppColors.primary,
          labelStyle: TextStyle(
            color: selected
                ? Colors.white
                : (n > 0 && color != null ? color : AppColors.textPrimary),
            fontWeight: FontWeight.w600,
          ),
          showCheckmark: false,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, 0),
      child: Row(
        children: [
          chip(_ProductFilter.all, 'All'),
          chip(_ProductFilter.lowStock, 'Low stock', color: AppColors.warning),
          chip(_ProductFilter.expiring, 'Expiring', color: AppColors.danger),
          chip(_ProductFilter.archived, 'Archived', color: AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _buildHeader(String ownerName, bool canManage) {
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
              if (!canManage)
                const SizedBox.shrink()
              else if (compact)
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

  Widget _buildProductList(List<Product> products, bool canManage) {
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
              Text(
                canManage
                    ? 'Add products one by one, or import your catalog from a CSV or Excel file.'
                    : 'Ask the owner or a manager to add products.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              if (canManage) ...[
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
              ],
              // Demo data is for development only: it must never land in
              // a real shop's stock or reports.
              if (kDebugMode && canManage) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: _loadSampleProducts,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('Load Sample Products (debug only)'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    minimumSize: const Size(270, 44),
                  ),
                ),
              ],
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
                              'Stock: ${product.totalStock.toInt()}'
                              '${product.isLowStock ? ' · LOW' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                color: product.isLowStock
                                    ? AppColors.warning
                                    : AppColors.textSecondary,
                                fontWeight: product.isLowStock
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (product.batches.any((b) => b.quantity > 0 && b.isExpired))
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            'Has expired stock – write it off',
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

  /// Buttons for what the signed-in user's role may do with [product].
  Widget _buildActions(Product product) {
    final user = ref.watch(currentUserProvider);
    Widget action(String label, IconData icon, VoidCallback onPressed, {Color? color}) {
      final c = color ?? AppColors.textSecondary;
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: color == null ? AppColors.border : c),
          minimumSize: const Size(0, AppTouch.minTargetSize),
        ),
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (!product.isArchived && Permissions.can(user, Permission.restock))
          action('Restock', Icons.add_box_rounded, () => _showRestockBatch(product),
              color: AppColors.primary),
        if (Permissions.can(user, Permission.adjustStock))
          action('Adjust Stock', Icons.tune_rounded, () => _showAdjust(product)),
        if (Permissions.can(user, Permission.manageProducts))
          action('Edit', Icons.edit_rounded, () {
            showDialog(
              context: context,
              builder: (_) => EditProductDialog(product: product),
            ).then((_) => ref.invalidate(productServiceProvider));
          }),
        action('History', Icons.history_rounded, () => _showHistory(product)),
        if (Permissions.can(user, Permission.manageProducts))
          action(
            product.isArchived ? 'Restore' : 'Archive',
            product.isArchived ? Icons.unarchive_rounded : Icons.archive_rounded,
            () => _toggleArchive(product),
            color: product.isArchived ? AppColors.primary : AppColors.danger,
          ),
      ],
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
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${batch.isExpired ? 'Expired' : 'Expires'}: '
                              '${DateHelpers.formatShort(batch.expiryDate)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: batch.isExpired
                                    ? AppColors.danger
                                    : AppColors.textSecondary,
                              ),
                            ),
                            if (batch.isExpired &&
                                batch.quantity > 0 &&
                                Permissions.can(ref.read(currentUserProvider),
                                    Permission.adjustStock))
                              TextButton(
                                onPressed: () => _writeOff(product, batch),
                                child: const Text('Write off',
                                    style: TextStyle(color: AppColors.danger)),
                              ),
                          ],
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
            child: _buildActions(product),
          ),
        ],
      ),
    );
  }
}
