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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shop_pos/features/products/services/product_image_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/auth/permissions.dart';
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
import 'package:shop_pos/core/theme/app_theme.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/products/providers/product_provider.dart';
import 'package:shop_pos/features/products/services/csv_import_service.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/products/widgets/add_product_dialog.dart';
import 'package:shop_pos/features/products/widgets/csv_import_dialog.dart';
import 'package:shop_pos/features/shared/widgets/app_empty_state.dart';
import 'package:shop_pos/features/shared/widgets/app_skeleton.dart';
import 'package:shop_pos/features/products/widgets/edit_product_dialog.dart';
import 'package:shop_pos/features/products/widgets/restock_batch_dialog.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';
import 'package:shop_pos/features/products/models/product_status.dart';
import 'package:shop_pos/features/products/widgets/product_status_badges.dart';

class OwnerProductsScreen extends ConsumerStatefulWidget {
  const OwnerProductsScreen({super.key});

  @override
  ConsumerState<OwnerProductsScreen> createState() => _OwnerProductsScreenState();
}

enum _ProductFilter { all, lowStock, outOfStock, expiring, expired, archived }

class _OwnerProductsScreenState extends ConsumerState<OwnerProductsScreen> {
  int _expandedProductId = -1;
  _ProductFilter _filter = _ProductFilter.all;

  // Rules live in product_status.dart, shared with the till and alerts.
  bool _matchesFilter(Product p, _ProductFilter f) => switch (f) {
        _ProductFilter.all => !p.isArchived,
        _ProductFilter.lowStock => !p.isArchived && p.health.stock == StockLevel.low,
        _ProductFilter.outOfStock => !p.isArchived && p.health.stock == StockLevel.out,
        _ProductFilter.expiring => !p.isArchived && p.health.shelfExpiry == ExpiryState.soon,
        _ProductFilter.expired => !p.isArchived && p.health.shelfExpiry == ExpiryState.expired,
        _ProductFilter.archived => p.isArchived,
      };

  void _refreshProduct(Product product) {
    ref.invalidate(productServiceProvider);
    ref.invalidate(productBatchesProvider(product.id));
  }

  void _showAdjust(Product product) {
    showAppDialog<bool>(
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
    showAppDialog(
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
    showAppDialog(
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
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(canManage),
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
                          'No product is below $kLowStockBelow units (or its own reorder level).',
                        _ProductFilter.outOfStock => 'Every product has sellable stock.',
                        _ProductFilter.expiring =>
                          'No stock expires within $kExpiringSoonDays days.',
                        _ProductFilter.expired => 'No expired stock on the shelf.',
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
      floatingActionButton: !canManage ||
              MediaQuery.sizeOf(context).width >= AppBreakpoints.rail
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
          selectedColor: AppColors.primary,
          side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
          labelStyle: TextStyle(
            color: selected
                ? AppColors.textOnPrimary
                : (n > 0 && color != null ? color : AppColors.textPrimary),
            fontWeight: FontWeight.w600,
          ),
          showCheckmark: false,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
      child: Row(
        children: [
          chip(_ProductFilter.all, 'All'),
          chip(_ProductFilter.lowStock, 'Low stock', color: AppColors.warningDarkText),
          chip(_ProductFilter.outOfStock, 'Out of stock', color: AppColors.dangerDarkText),
          chip(_ProductFilter.expiring, 'Expiring soon', color: AppColors.warningDarkText),
          chip(_ProductFilter.expired, 'Expired', color: AppColors.dangerDarkText),
          chip(_ProductFilter.archived, 'Archived'),
        ],
      ),
    );
  }

  /// Search with the catalogue actions beside it. The shell already
  /// titles the page, so there is no separate header bar. On wide screens
  /// "Add product" lives here as the primary button; phones keep the FAB.
  Widget _buildHeader(bool canManage) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          return Row(
            children: [
              Expanded(child: _buildSearchBar()),
              if (canManage) ...[
                const SizedBox(width: AppSpacing.sm),
                if (compact)
                  IconButton(
                    onPressed: _showImportCsvDialog,
                    tooltip: 'Import CSV / Excel',
                    icon: const Icon(Icons.file_upload_outlined, size: 22),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.cardBg,
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      minimumSize: const Size(52, 52),
                    ),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: _showImportCsvDialog,
                    icon: const Icon(Icons.file_upload_outlined, size: 20),
                    label: const Text('Import'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton.icon(
                    onPressed: _showAddProduct,
                    icon: const Icon(Icons.add_rounded, size: 22),
                    label: const Text('Add product'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    ),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Search products or categories…',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'Clear search',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
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
        // One column, capped in width: tiles expand in place to show
        // batches, which a fixed-ratio grid cell cannot hold.
        final side = constraints.maxWidth > 1000
            ? (constraints.maxWidth - 1000) / 2
            : AppSpacing.md;
        final wide = constraints.maxWidth >= AppBreakpoints.rail;

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(side, AppSpacing.sm, side, wide ? AppSpacing.xl : 100),
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
    final health = product.health;
    final isExpanded = _expandedProductId == product.id;

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
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceBg,
                    borderRadius: AppSpacing.borderMd,
                  ),
                  child: ProductImageService.exists(product.imagePath)
                      ? Image.file(File(product.imagePath!), fit: BoxFit.cover)
                      : Center(
                    child: Text(
                      _avatarInitial(product.name),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
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
                              style: AppText.money(size: 14, weight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Flexible(
                            child: Text(
                              'Stock: ${health.sellable}'
                              '${health.expiredUnits > 0 ? ' (+${health.expiredUnits} expired)' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                color: stockTextColor(health.stock),
                                fontWeight: health.stock == StockLevel.normal
                                    ? FontWeight.normal
                                    : FontWeight.w700,
                                fontFeatures: AppText.tabular,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (hasProductAlert(product))
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: ProductStatusBadges(product: product),
                        ),
                    ],
                  ),
                ),
                // Next expiry as quiet information; alerts are the badges.
                if (health.daysToNextExpiry != null &&
                    health.shelfExpiry == ExpiryState.normal)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 3),
                        Text(
                          '${health.daysToNextExpiry}d',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                            fontFeatures: AppText.tabular,
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
            showAppDialog(
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
