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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/responsive/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/product.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../utils/currency_helpers.dart';
import '../../common/widgets/app_empty_state.dart';
import '../../common/widgets/app_skeleton.dart';
import '../../common/widgets/checkout_bottom_sheet.dart';
import '../../common/widgets/touchable_card.dart';
import 'mobile_scanner_screen.dart';

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
        context.showErrorSnackbar('"${product.name}" is expired!');
        break;
      case AddItemResult.notFound:
        context.showErrorSnackbar('Product not found!');
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

    Product? matchedProduct;
    for (final p in products) {
      if (p.name.toLowerCase() == normalizedCode ||
          p.id.toString() == normalizedCode ||
          p.category.toLowerCase() == normalizedCode) {
        matchedProduct = p;
        break;
      }
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
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 28),
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
                final filteredProducts = _searchQuery.isEmpty
                    ? products
                    : products
                        .where((p) =>
                            p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                            p.category.toLowerCase().contains(_searchQuery.toLowerCase()))
                        .toList();

                if (filteredProducts.isEmpty) {
                  return AppEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No Products Found',
                    description: _searchQuery.isNotEmpty
                        ? 'No item matching "$_searchQuery". Try clearing your search.'
                        : 'Your product catalog is empty.',
                    actionLabel: _searchQuery.isNotEmpty ? 'Clear Search' : null,
                    onAction: _searchQuery.isNotEmpty
                        ? () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          }
                        : null,
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
                        final isOutOfStock = product.totalStock <= 0;
                        final tileBg = Color(product.quickButtonColor);

                        return TouchableCard(
                          onTap: () => _onAddProductToCart(product),
                          backgroundColor: tileBg,
                          borderColor: AppColors.border,
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          child: Opacity(
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
                                    isOutOfStock ? 'OUT OF STOCK' : 'Stock: ${product.totalStock.toInt()}',
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
