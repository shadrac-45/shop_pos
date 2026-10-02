/// ============================================
/// Cashier Sales Screen — ShopPOS
/// ============================================
/// Touch-first point-of-sale interface featuring:
///   • Quick-tap product catalog grid (min 48x48 dp targets)
///   • Barcode scanner trigger
///   • Real-time search filter
///   • Skeleton loader on catalog fetch
///   • Interactive touch feedback & cart bar badge
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
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/shifts/providers/shift_provider.dart';
import 'package:shop_pos/features/shifts/screens/shift_screen.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/responsive/app_breakpoints.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';
import 'package:shop_pos/features/products/providers/product_provider.dart';
import 'package:shop_pos/features/products/services/csv_import_service.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/shared/widgets/app_empty_state.dart';
import 'package:shop_pos/features/shared/widgets/app_skeleton.dart';
import 'package:shop_pos/features/sales/widgets/checkout_bottom_sheet.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';
import 'package:shop_pos/features/sales/screens/cashier_history_screen.dart';
import 'package:shop_pos/features/sales/screens/mobile_scanner_screen.dart';

class CashierSalesScreen extends ConsumerStatefulWidget {
  const CashierSalesScreen({super.key});

  @override
  ConsumerState<CashierSalesScreen> createState() => _CashierSalesScreenState();
}

class _CashierSalesScreenState extends ConsumerState<CashierSalesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onAddProductToCart(Product product) async {
    final result = await ref.read(cartProvider.notifier).addItem(product, 1);
    if (!mounted) return;
    switch (result) {
      case AddItemResult.success:
        HapticFeedback.lightImpact();
        context.showSuccessSnackbar('Added "${product.name}" to cart');
        break;
      case AddItemResult.outOfStock:
        context.showErrorSnackbar('"${product.name}" is out of stock!');
        break;
      case AddItemResult.expired:
        context.showErrorSnackbar(
            'All "${product.name}" in stock has expired and cannot be sold.');
        break;
      case AddItemResult.notFound:
        context.showErrorSnackbar('Product not found!');
        break;
      case AddItemResult.archived:
        context.showErrorSnackbar('"${product.name}" has been archived.');
        break;
    }
  }

  Future<void> _handleBarcodeScan(List<Product> products) async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const MobileScannerScreen()),
    );

    if (scannedCode == null || scannedCode.isEmpty || !mounted) return;
    final normalizedCode = scannedCode.trim().toLowerCase();

    // Barcode, then SKU, then exact name: the first that matches wins.
    Product? matchedProduct;
    for (final match in <bool Function(Product)>[
      (p) => p.barcode?.trim().toLowerCase() == normalizedCode,
      (p) => p.sku?.trim().toLowerCase() == normalizedCode,
      (p) => p.name.toLowerCase() == normalizedCode,
    ]) {
      matchedProduct = products.where((p) => !p.isArchived).where(match).firstOrNull;
      if (matchedProduct != null) break;
    }

    if (matchedProduct != null) {
      await _onAddProductToCart(matchedProduct);
    } else {
      if (mounted) {
        context.showErrorSnackbar('No product found for barcode: "$scannedCode"');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productServiceProvider);
    final cart = ref.watch(cartProvider);
    final totalAmount = cart.fold(0.0, (sum, item) => sum + item.subtotal);
    final totalQuantity = cart.fold(0, (sum, item) => sum + item.quantity);

    return SafeArea(
      child: Column(
        children: [
          const _ShiftBanner(),
          // ── Search & Scan Bar ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value.trim()),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search product or category...',
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
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filledTonal(
                  constraints: AppTouch.touchConstraints,
                  icon: const Icon(Icons.receipt_long_rounded, size: 24),
                  tooltip: 'Sales History',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.cardBg,
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CashierHistoryScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton.filledTonal(
                  constraints: AppTouch.touchConstraints,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 26),
                  tooltip: 'Scan Barcode',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.cardBg,
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  onPressed: () {
                    final products = productsAsync.valueOrNull ?? [];
                    _handleBarcodeScan(products);
                  },
                ),
              ],
            ),
          ),

          // ── Quick-Sale Catalog Grid ────────────────────────────
          Expanded(
            child: productsAsync.when(
              data: (products) {
                final sellable = products.where((p) => !p.isArchived);
                final filteredProducts = _searchQuery.isEmpty
                    ? sellable.toList()
                    : sellable
                        .where((p) =>
                            p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                            p.category.toLowerCase().contains(_searchQuery.toLowerCase()))
                        .toList();

                if (filteredProducts.isEmpty) {
                  return AppEmptyState(
                    icon: Icons.search_off_rounded,
                    title: _searchQuery.isNotEmpty ? 'No Products Found' : 'Catalog is Empty',
                    description: _searchQuery.isNotEmpty
                        ? 'No item matching "$_searchQuery". Try clearing your search.'
                        : 'There are no products to sell yet. Ask the owner or a '
                            'manager to add products.',
                    actionLabel: _searchQuery.isNotEmpty
                        ? 'Clear Search'
                        : (kDebugMode ? 'Load Sample Products (debug)' : null),
                    onAction: _searchQuery.isNotEmpty
                        ? () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          }
                        // Demo data never reaches a real shop's database.
                        : !kDebugMode
                            ? null
                            : () async {
                            HapticFeedback.mediumImpact();
                            final isar = ref.read(isarProvider);
                            final count = await CsvImportService.seedSampleProducts(isar);
                            if (context.mounted) {
                              context.showSuccessSnackbar('Loaded $count sample products into catalog!');
                              ref.invalidate(productServiceProvider);
                            }
                          },
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = AppBreakpoints.salesGridColumns(
                      constraints.maxWidth,
                      landscape: AppBreakpoints.isLandscape(context),
                    );

                    return GridView.builder(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        childAspectRatio: 1.05,
                        crossAxisSpacing: AppSpacing.sm,
                        mainAxisSpacing: AppSpacing.sm,
                      ),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];
                        final sellableStock = product.sellableStock;
                        final isOutOfStock = sellableStock <= 0;
                        final onlyExpired = isOutOfStock && product.totalStock > 0;
                        final tileBg = Color(product.quickButtonColor);

                        final hasImage = ProductImageService.exists(product.imagePath);
                        return TouchableCard(
                          onTap: () => _onAddProductToCart(product),
                          backgroundColor: tileBg,
                          borderColor: AppColors.border,
                          padding: hasImage ? EdgeInsets.zero : const EdgeInsets.all(AppSpacing.xs),
                          child: hasImage
                              ? _ImageTile(
                                  product: product,
                                  stockLabel: onlyExpired
                                      ? 'EXPIRED'
                                      : isOutOfStock
                                          ? 'OUT OF STOCK'
                                          : 'Stock: $sellableStock',
                                  dimmed: isOutOfStock,
                                )
                              : Opacity(
                            opacity: isOutOfStock ? 0.45 : 1.0,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  product.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  CurrencyHelpers.formatCompact(product.price),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isOutOfStock ? AppColors.danger : Colors.black38,
                                    borderRadius: AppSpacing.borderSm,
                                  ),
                                  child: Text(
                                    onlyExpired
                                        ? 'EXPIRED'
                                        : isOutOfStock
                                            ? 'OUT OF STOCK'
                                            : 'Stock: $sellableStock',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const ProductGridSkeleton(),
              error: (error, _) => AppEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Error Loading Catalog',
                description: error.toString(),
              ),
            ),
          ),

          // ── Persistent Cart Summary Bar ───────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: const BoxDecoration(
              color: AppColors.cardBg,
              border: Border(top: BorderSide(color: AppColors.border, width: 1.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    children: [
                      // Cart Item Badge
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: AppSpacing.borderMd,
                            ),
                            child: const Icon(Icons.shopping_cart_rounded, color: AppColors.primary),
                          ),
                          if (totalQuantity > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: const BoxDecoration(
                                  color: AppColors.accent,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$totalQuantity',
                                  style: const TextStyle(
                                    color: AppColors.textOnPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              cart.isEmpty ? 'Cart is Empty' : '$totalQuantity items in cart',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                CurrencyHelpers.format(totalAmount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                ElevatedButton.icon(
                  onPressed: cart.isEmpty
                      ? null
                      : () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const CheckoutBottomSheet(),
                          ),
                  icon: const Icon(Icons.payment_rounded),
                  label: const Text('Checkout'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(140, AppTouch.buttonHeight),
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
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

/// Product button showing the product photo, with name, price and stock
/// over a dark gradient so the text stays readable.
class _ImageTile extends StatelessWidget {
  final Product product;
  final String stockLabel;
  final bool dimmed;
  const _ImageTile({required this.product, required this.stockLabel, required this.dimmed});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: ClipRRect(
        borderRadius: AppSpacing.borderLg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(product.imagePath!), fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.35, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  Text('${CurrencyHelpers.formatCompact(product.price)} · $stockLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reminds staff who run a till to open a shift before selling.
class _ShiftBanner extends ConsumerWidget {
  const _ShiftBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!Permissions.can(user, Permission.runShift)) return const SizedBox.shrink();
    final shift = ref.watch(currentShiftProvider);
    if (shift.isLoading || shift.valueOrNull != null) return const SizedBox.shrink();

    return Material(
      color: AppColors.warning.withValues(alpha: 0.12),
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ShiftScreen())),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Icon(Icons.lock_clock_rounded, color: AppColors.warning, size: 20),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'No shift open — tap to count your float and open a shift.',
                  style: TextStyle(color: AppColors.warningDarkText, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.warning),
            ],
          ),
        ),
      ),
    );
  }
}
