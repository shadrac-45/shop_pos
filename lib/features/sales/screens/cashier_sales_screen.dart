/// ============================================
/// Cashier Sales Screen — ShopPOS
/// ============================================
/// The till. Touch-first and built to be scanned
/// mid-transaction:
///   • Search (also takes keyboard-wedge barcode
///     scanners: type/scan + Enter adds the item)
///   • Category chips
///   • Product cards: name, price, stock, and how
///     many are already in the cart
///   • Tablets/desktops: the cart stays open in a
///     glass panel beside the catalogue
///   • Phones: a floating glass cart button
/// ============================================
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/responsive/app_breakpoints.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_motion.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/theme/app_theme.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/providers/product_provider.dart';
import 'package:shop_pos/features/products/services/csv_import_service.dart';
import 'package:shop_pos/features/products/services/product_image_service.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';
import 'package:shop_pos/features/sales/screens/cashier_history_screen.dart';
import 'package:shop_pos/features/sales/screens/mobile_scanner_screen.dart';
import 'package:shop_pos/features/sales/widgets/cart_panel.dart';
import 'package:shop_pos/features/sales/widgets/checkout_bottom_sheet.dart';
import 'package:shop_pos/features/shared/widgets/app_empty_state.dart';
import 'package:shop_pos/features/shared/widgets/app_skeleton.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';
import 'package:shop_pos/features/shifts/providers/shift_provider.dart';
import 'package:shop_pos/features/shifts/screens/shift_screen.dart';
import 'package:shop_pos/features/products/models/product_status.dart';
import 'package:shop_pos/features/products/widgets/product_status_badges.dart';
import 'package:shop_pos/features/sales/widgets/floating_cart_button.dart';

/// Width of the till area from which the cart sits beside the catalogue.
const double _splitWidth = 860;

class CashierSalesScreen extends ConsumerStatefulWidget {
  const CashierSalesScreen({super.key});

  @override
  ConsumerState<CashierSalesScreen> createState() => _CashierSalesScreenState();
}

class _CashierSalesScreenState extends ConsumerState<CashierSalesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';
  Timer? _searchDebounce;

  /// Selected category chip; null = all. If the category disappears from
  /// the catalogue, the build treats it as "all" without mutating this.
  String? _category;

  /// Catalogue index, rebuilt only when the product stream emits a new
  /// list — not on every keystroke or cart change.
  List<Product>? _indexedFrom;
  List<Product> _sellable = const [];
  List<String> _categories = const [];
  final Expando<String> _searchKey = Expando<String>('searchKey');

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  /// Typing filters after a short pause, so a fast typist or a keyboard-
  /// wedge scanner doesn't rebuild the grid once per character.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _searchQuery = value.trim());
    });
  }

  void _indexCatalog(List<Product> products) {
    if (identical(products, _indexedFrom)) return;
    _indexedFrom = products;
    _sellable = products.where((p) => !p.isArchived).toList(growable: false);
    _categories = {
      for (final p in _sellable)
        if (p.category.trim().isNotEmpty) p.category,
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// Lower-cased name/category/barcode/SKU, built once per product.
  String _keyFor(Product p) => _searchKey[p] ??= [
        p.name,
        p.category,
        p.barcode ?? '',
        p.sku ?? '',
      ].join('\u0000').toLowerCase();

  /// Adds one unit. Success is shown on the card (in-cart badge) and in
  /// the cart itself, so only problems raise a toast — a toast per tap
  /// buries the screen during a busy sale.
  Future<void> _onAddProductToCart(Product product) async {
    final result = await ref.read(cartProvider.notifier).addItem(product, 1);
    if (!mounted) return;
    switch (result) {
      case AddItemResult.success:
        HapticFeedback.lightImpact();
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
      case AddItemResult.cancelled:
        break; // signed out mid-add; the cart was already replaced
    }
  }

  /// Barcode, then SKU, then exact name: the first that matches wins.
  Product? _matchCode(List<Product> products, String code) {
    final normalizedCode = code.trim().toLowerCase();
    if (normalizedCode.isEmpty) return null;
    for (final match in <bool Function(Product)>[
      (p) => p.barcode?.trim().toLowerCase() == normalizedCode,
      (p) => p.sku?.trim().toLowerCase() == normalizedCode,
      (p) => p.name.toLowerCase() == normalizedCode,
    ]) {
      final found = products.where((p) => !p.isArchived).where(match).firstOrNull;
      if (found != null) return found;
    }
    return null;
  }

  Future<void> _handleBarcodeScan(List<Product> products) async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const MobileScannerScreen()),
    );

    if (scannedCode == null || scannedCode.isEmpty || !mounted) return;

    final matchedProduct = _matchCode(products, scannedCode);
    if (matchedProduct != null) {
      await _onAddProductToCart(matchedProduct);
    } else if (mounted) {
      context.showErrorSnackbar('No product found for barcode: "$scannedCode"');
    }
  }

  /// Enter in the search box: USB/Bluetooth barcode scanners type the
  /// code and press Enter. An exact code match — or a search that leaves
  /// a single product — goes straight into the cart.
  Future<void> _onSearchSubmitted(List<Product> products, String? category) async {
    final code = _searchController.text;
    // Filter on the text as typed now: the debounced query may lag behind
    // a scanner that types the code and presses Enter at once.
    final visible = _filter(category, code.trim());
    final product = _matchCode(products, code) ?? (visible.length == 1 ? visible.first : null);
    if (product == null) {
      if (code.trim().isNotEmpty) {
        context.showErrorSnackbar('No product matches "${code.trim()}"');
      }
    } else {
      await _onAddProductToCart(product);
      if (!mounted) return;
      _clearSearch();
    }
    _searchFocus.requestFocus();
  }

  void _openCheckout({required bool split}) {
    HapticFeedback.mediumImpact();
    if (split) {
      // The cart is already on screen: payment opens as a focused modal.
      showAppDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(AppSpacing.xl),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: const CheckoutBottomSheet(showLines: false),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const CheckoutBottomSheet(),
      );
    }
  }

  List<Product> _filter(String? category, String query) {
    final q = query.toLowerCase();
    if (category == null && q.isEmpty) return _sellable;
    return _sellable.where((p) {
      if (category != null && p.category != category) return false;
      return q.isEmpty || _keyFor(p).contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productServiceProvider);

    return LayoutBuilder(builder: (context, constraints) {
      final split = constraints.maxWidth >= _splitWidth;
      final catalog = _buildCatalog(productsAsync, split: split);

      if (split) {
        final cartWidth = (constraints.maxWidth * 0.36).clamp(340.0, 420.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: catalog),
            SizedBox(
              width: cartWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
                child: CartPanel(onCharge: () => _openCheckout(split: true)),
              ),
            ),
          ],
        );
      }

      // Phones and narrow tablets: the cart floats over the catalogue.
      return Stack(
        children: [
          Positioned.fill(child: catalog),
          Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: FloatingCartButton(onOpen: () => _openCheckout(split: false)),
          ),
        ],
      );
    });
  }

  Widget _buildCatalog(AsyncValue<List<Product>> productsAsync, {required bool split}) {
    final products = productsAsync.valueOrNull ?? const <Product>[];
    _indexCatalog(products);
    final categories = _categories;
    // A category that vanished from the catalogue reads as "all"; the
    // user's choice is left intact in state.
    final category = categories.contains(_category) ? _category : null;
    final visible = _filter(category, _searchQuery);

    return Column(
      children: [
        const _ShiftBanner(),
        // ── Search & Scan ─────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _onSearchSubmitted(products, category),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search or scan a barcode…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            tooltip: 'Clear search',
                            onPressed: _clearSearch,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ToolButton(
                icon: Icons.qr_code_scanner_rounded,
                tooltip: 'Scan barcode',
                primary: true,
                onPressed: () => _handleBarcodeScan(products),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ToolButton(
                icon: Icons.receipt_long_rounded,
                tooltip: 'Sales history',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CashierHistoryScreen()),
                  );
                },
              ),
            ],
          ),
        ),

        // ── Category chips ────────────────────────────────
        if (categories.length > 1)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                _CategoryChip(
                  label: 'All',
                  selected: category == null,
                  onTap: () => setState(() => _category = null),
                ),
                for (final c in categories)
                  _CategoryChip(
                    label: c,
                    selected: category == c,
                    onTap: () => setState(() => _category = category == c ? null : c),
                  ),
              ],
            ),
          ),

        // ── Product grid ──────────────────────────────────
        Expanded(
          child: productsAsync.when(
            data: (_) {
              if (visible.isEmpty) {
                final filtering = _searchQuery.isNotEmpty || category != null;
                return AppEmptyState(
                  icon: filtering ? Icons.search_off_rounded : Icons.inventory_2_outlined,
                  title: filtering ? 'No products found' : 'Catalog is empty',
                  description: _searchQuery.isNotEmpty
                      ? 'Nothing matches "$_searchQuery". Try another word or clear the search.'
                      : category != null
                          ? 'No products in "$category".'
                          : 'There are no products to sell yet. Ask the owner or a '
                              'manager to add products.',
                  actionLabel: filtering
                      ? 'Clear filters'
                      : (kDebugMode ? 'Load Sample Products (debug)' : null),
                  onAction: filtering
                      ? () {
                          _clearSearch();
                          setState(() => _category = null);
                        }
                      // Demo data never reaches a real shop's database.
                      : !kDebugMode
                          ? null
                          : () async {
                              HapticFeedback.mediumImpact();
                              final isar = ref.read(isarProvider);
                              final count = await CsvImportService.seedSampleProducts(isar);
                              if (mounted) {
                                context.showSuccessSnackbar('Loaded $count sample products into catalog!');
                                ref.invalidate(productServiceProvider);
                              }
                            },
                );
              }

              return LayoutBuilder(builder: (context, constraints) {
                final cols = AppBreakpoints.salesGridColumns(
                  constraints.maxWidth,
                  landscape: AppBreakpoints.isLandscape(context),
                );
                return _ProductGrid(
                  products: visible,
                  columns: cols,
                  onTap: _onAddProductToCart,
                  // Keep the last row clear of the floating cart.
                  bottomPadding: split ? AppSpacing.lg : kFloatingCartClearance,
                );
              });
            },
            loading: () => LayoutBuilder(
              builder: (context, constraints) => ProductGridSkeleton(
                crossAxisCount: AppBreakpoints.salesGridColumns(
                  constraints.maxWidth,
                  landscape: AppBreakpoints.isLandscape(context),
                ),
              ),
            ),
            error: (error, _) => AppEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Error Loading Catalog',
              description: error.toString(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Square icon button beside the search field.
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool primary;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 24),
      style: IconButton.styleFrom(
        minimumSize: const Size(52, 52),
        backgroundColor: primary ? AppColors.primary : AppColors.cardBg,
        foregroundColor: primary ? AppColors.textOnPrimary : AppColors.textPrimary,
        side: primary ? null : const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderMd),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? AppColors.primary : AppColors.cardBg,
          shape: StadiumBorder(
            side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
          ),
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            customBorder: const StadiumBorder(),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppTouch.minTargetSize),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.textOnPrimary : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductGrid extends ConsumerWidget {
  final List<Product> products;
  final int columns;
  final ValueChanged<Product> onTap;
  final double bottomPadding;

  const _ProductGrid({
    required this.products,
    required this.columns,
    required this.onTap,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // How many of each product are already rung up, for the card badges.
    final inCart = {
      for (final item in ref.watch(cartProvider)) item.product.id: item.quantity,
    };
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, bottomPadding),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 0.84,
        crossAxisSpacing: AppSpacing.sm + 2,
        mainAxisSpacing: AppSpacing.sm + 2,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return _ProductCard(
          product: product,
          inCart: inCart[product.id] ?? 0,
          onTap: () => onTap(product),
        );
      },
    );
  }
}

/// Solid white card — product cards are never glass: price and stock
/// must read instantly. Every card shares one neutral style; the only
/// colour is green when the product is in the cart, and the stock dot
/// when stock needs attention. Photos keep their natural colours.
class _ProductCard extends StatelessWidget {
  final Product product;
  final int inCart;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.inCart, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Stock/expiry rules come from product_status.dart (shared with
    // inventory and alerts): low = under 5, expiring soon = ≤ 31 days.
    // `health` is computed once per product and cached.
    final h = product.health;
    final out = h.stock == StockLevel.out;
    final alert = h.alert(forTill: true);
    final hasImage = _hasImage(product);
    final selected = inCart > 0;
    final stockText = switch ((h.stock, h.tillExpiry)) {
      (StockLevel.out, ExpiryState.expired) => 'Expired',
      (StockLevel.out, _) => 'Out of stock',
      (StockLevel.low, _) => 'Low stock, ${h.sellable} left',
      _ => '${h.sellable} in stock',
    };
    // Screen readers get the expiry warning the badge shows.
    final expiryText = h.tillExpiry == ExpiryState.soon
        ? ', expiring soon, ${h.daysToNextExpiry != null && h.daysToNextExpiry! > 1 ? '${h.daysToNextExpiry} days' : '1 day'} left'
        : '';

    const radius = BorderRadius.all(Radius.circular(AppSpacing.radiusLg));

    return Semantics(
      button: true,
      label: '${product.name}, ${CurrencyHelpers.format(product.price)}, $stockText$expiryText'
          '${selected ? ', $inCart in cart' : ''}',
      excludeSemantics: true,
      child: TouchableCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        borderRadius: radius,
        borderColor: selected ? AppColors.primary : AppColors.border,
        borderWidth: selected ? 1.6 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: AppSpacing.borderMd,
                      child: Opacity(
                        opacity: out ? 0.4 : 1,
                        child: hasImage
                            ? Image.file(
                                File(product.imagePath!),
                                fit: BoxFit.cover,
                                // Decode at thumbnail size, not full resolution.
                                cacheWidth: 320,
                                errorBuilder: (_, __, ___) =>
                                    _Monogram(name: product.name, selected: selected),
                              )
                            : _Monogram(name: product.name, selected: selected),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: AnimatedSwitcher(
                          duration: AppMotion.fast,
                          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                          child: Container(
                            key: ValueKey(inCart),
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Text(
                              '$inCart',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                fontFeatures: AppText.tabular,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: out ? AppColors.textSecondary : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      CurrencyHelpers.format(product.price),
                      style: AppText.money(
                          size: 16,
                          weight: FontWeight.w800,
                          color: out ? AppColors.textSecondary : AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Healthy stock is a quiet gray caption; anything that
                  // needs attention becomes a small badge.
                  SizedBox(
                    height: 20,
                    child: alert
                        ? ProductStatusBadges(product: product, forTill: true, compact: true)
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${h.sellable} in stock',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textMuted,
                                fontFeatures: AppText.tabular,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether a product's photo exists on disk, checked once per product
/// object rather than on every rebuild.
final Expando<bool> _imageExists = Expando<bool>('imageExists');
bool _hasImage(Product p) => _imageExists[p] ??= ProductImageService.exists(p.imagePath);

/// Initials on a neutral tile (green wash once the product is in the cart).
class _Monogram extends StatelessWidget {
  final String name;
  final bool selected;
  const _Monogram({required this.name, required this.selected});

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      return words.first.substring(0, words.first.length.clamp(0, 2)).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? AppColors.primarySoft : AppColors.surfaceBg,
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              _initials,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: selected ? AppColors.primaryDark : AppColors.textMuted,
              ),
            ),
          ),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
      child: Material(
        color: AppTone.warning.tint,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderMd,
          side: BorderSide(color: AppTone.warning.border),
        ),
        child: InkWell(
          borderRadius: AppSpacing.borderMd,
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const ShiftScreen())),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
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
                Icon(Icons.chevron_right_rounded, color: AppColors.warningDarkText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
