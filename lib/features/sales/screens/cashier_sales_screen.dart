/// ============================================
/// Cashier Sales Screen — ShopPOS
/// ============================================
/// Main sales interface for cashiers:
/// - Search bar + barcode scan button
/// - Quick-sale product grid
/// - Bottom cart summary with checkout
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/product.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/sales_provider.dart';
import '../../../utils/currency_helpers.dart';
import '../../auth/screens/login_screen.dart';
import 'checkout_screen.dart';

class CashierSalesScreen extends ConsumerStatefulWidget {
  const CashierSalesScreen({super.key});

  @override
  ConsumerState<CashierSalesScreen> createState() =>
      _CashierSalesScreenState();
}

class _CashierSalesScreenState extends ConsumerState<CashierSalesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Add product to cart after validating expiry status (FEFO check).
  Future<void> _addToCart(Product product) async {
    final productService = ref.read(productServiceProvider);
    final check = await productService.checkProductSellable(product.id);
    if (!mounted) return;

    // Block sale if soonest batch is expired
    if (!check.canSell) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  check.reason ?? 'Cannot sell this product',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    ref.read(cartProvider.notifier).addItem(
          productId: product.id,
          name: product.name,
          price: product.price,
        );

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${product.name} added to cart',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Handle logout.
  void _logout() {
    ref.read(authServiceProvider).logout();
    ref.read(cartProvider.notifier).clearCart();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  /// Open checkout bottom sheet.
  void _openCheckout() {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cart is empty. Add items first.'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CheckoutScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final cartItems = ref.watch(cartProvider);
    final cartTotal = ref.watch(cartTotalProvider);
    final cartCount = ref.watch(cartItemCountProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Header ────────────────────────────
            _buildHeader(currentUser?.name ?? 'Cashier'),

            // ── Expiry Alert Banner ───────────────────
            _buildExpiryBanner(),

            // ── Search Bar + Scan ─────────────────────
            _buildSearchBar(),

            // ── Product Grid (Expanded) ───────────────
            Expanded(
              child: _buildProductGrid(),
            ),

            // ── Bottom Cart Summary ───────────────────
            if (cartItems.isNotEmpty)
              _buildCartSummary(cartTotal, cartCount),
          ],
        ),
      ),
    );
  }

  /// Header with cashier name, sales today, and logout.
  Widget _buildHeader(String cashierName) {
    final todaysRevenue = ref.watch(todaysRevenueProvider);

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
          // Cashier avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppColors.textOnPrimary,
              size: 22,
            ),
          ),

          const SizedBox(width: 12),

          // Cashier name & today's sales
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cashierName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                todaysRevenue.when(
                  data: (revenue) => Text(
                    'Today: ${CurrencyHelpers.format(revenue)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  loading: () => const Text(
                    'Loading...',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  error: (_, __) => const Text(
                    'Today: --',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
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
            tooltip: 'Logout',
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

  /// Displays a banner if any products are expiring soon.
  Widget _buildExpiryBanner() {
    final expiringAsync = ref.watch(expiringProductsProvider);

    return expiringAsync.when(
      data: (products) {
        if (products.isEmpty) return const SizedBox.shrink();

        final hasAlreadyExpired = products.any((p) => p.soonestExpiry!.isBefore(DateTime.now()));

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: hasAlreadyExpired ? AppColors.danger.withValues(alpha: 0.15) : AppColors.warning.withValues(alpha: 0.15),
            border: Border.all(color: hasAlreadyExpired ? AppColors.danger : AppColors.warning),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                hasAlreadyExpired ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                color: hasAlreadyExpired ? AppColors.danger : AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasAlreadyExpired
                      ? '${products.length} product(s) have expired stock!'
                      : '${products.length} product(s) expiring soon',
                  style: TextStyle(
                    color: hasAlreadyExpired ? AppColors.danger : AppColors.warning,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  /// Search bar with barcode scan button.
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          // Search input
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search products...',
                  hintStyle: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 15,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppColors.textMuted,
                    size: 22,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Scan barcode button
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: IconButton(
              onPressed: () {
                // TODO: Implement barcode scanner with mobile_scanner
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Barcode scanner coming soon!'),
                    backgroundColor: AppColors.info,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                );
              },
              icon: const Icon(
                Icons.qr_code_scanner_rounded,
                color: AppColors.textOnPrimary,
                size: 24,
              ),
              tooltip: 'Scan Barcode',
            ),
          ),
        ],
      ),
    );
  }

  /// Product quick-sale grid.
  Widget _buildProductGrid() {
    // Use search if query is not empty, otherwise load all
    final productsAsync = _searchQuery.isEmpty
        ? ref.watch(productsProvider)
        : ref.watch(productSearchProvider(_searchQuery));

    return productsAsync.when(
      data: (products) {
        if (products.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _searchQuery.isEmpty
                      ? Icons.inventory_2_outlined
                      : Icons.search_off_rounded,
                  size: 64,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isEmpty
                      ? 'No products yet'
                      : 'No products found',
                  style: const TextStyle(
                    fontSize: 18,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          physics: const BouncingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.85,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) {
            return _buildProductCard(products[index]);
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (err, _) => Center(
        child: Text(
          'Error: $err',
          style: const TextStyle(color: AppColors.danger),
        ),
      ),
    );
  }

  /// Individual product quick-sale card.
  Widget _buildProductCard(Product product) {
    final color = Color(product.quickButtonColor);
    final cartQty = ref.watch(cartProvider).fold(
          0,
          (sum, item) =>
              item.productId == product.id ? sum + item.qty : sum,
        );

    // Check if the product's soonest batch is expired (has stock but expired)
    final hasExpiredStock = product.totalStock > 0 &&
        product.soonestExpiry != null &&
        product.soonestExpiry!.isBefore(DateTime.now());

    return GestureDetector(
      onTap: product.totalStock > 0 ? () => _addToCart(product) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: product.totalStock > 0
                ? [color.withValues(alpha: 0.85), color]
                : [
                    AppColors.elevatedBg,
                    AppColors.surfaceBg,
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: product.totalStock > 0
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            // Main product info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Product name
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: product.totalStock > 0
                          ? Colors.white
                          : AppColors.textMuted,
                      height: 1.2,
                    ),
                  ),

                  const Spacer(),

                  // Price
                  Text(
                    CurrencyHelpers.formatCompact(product.price),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: product.totalStock > 0
                          ? Colors.white
                          : AppColors.textMuted,
                    ),
                  ),

                  const SizedBox(height: 2),

                  // Stock info
                  Text(
                    product.totalStock > 0
                        ? '${product.totalStock} left'
                        : 'Out of stock',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: product.totalStock > 0
                          ? Colors.white.withValues(alpha: 0.8)
                          : AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),

            // Cart quantity badge
            if (cartQty > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '$cartQty',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),

            // Out of stock overlay
            if (product.totalStock <= 0)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.block_rounded,
                      color: AppColors.danger,
                      size: 32,
                    ),
                  ),
                ),
              ),

            // Expired stock badge — warn cashier visually
            if (hasExpiredStock)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'EXPIRED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Bottom cart summary bar.
  Widget _buildCartSummary(double total, int itemCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Cart icon and count
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.shopping_cart_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$itemCount',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Total
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    CurrencyHelpers.format(total),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Checkout button
            ElevatedButton(
              onPressed: _openCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Checkout',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
