/// ============================================
/// Cart Provider — ShopPOS
/// ============================================
/// The till's current cart: lines, line and sale
/// discounts, and completing the sale through
/// [SaleService].
/// ============================================
library;

import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/services/inventory_service.dart';
import 'package:shop_pos/features/reports/providers/report_provider.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/services/sale_calculator.dart';
import 'package:shop_pos/features/sales/services/sale_service.dart';

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier(ref);
});

/// Discount on the whole sale (money, not percent).
final cartSaleDiscountProvider = StateProvider<double>((ref) => 0);

/// Live totals for the cart, including VAT and discounts.
final cartTotalsProvider = Provider<SaleTotals>((ref) {
  final cart = ref.watch(cartProvider);
  return SaleService.totalsFor(
    [for (final i in cart) i.toCheckoutLine()],
    saleDiscount: ref.watch(cartSaleDiscountProvider),
    tax: ref.watch(taxConfigProvider),
  );
});

enum AddItemResult { success, notFound, outOfStock, expired, archived }

class CartItem {
  final Product product;
  final int quantity;

  /// Discount on the whole line.
  final double discount;

  /// Sellable units across all unexpired batches when the item was last
  /// added; caps the quantity (the sale itself re-checks live stock).
  final int available;

  CartItem({
    required this.product,
    required this.quantity,
    required this.available,
    this.discount = 0,
  });

  double get gross => roundMoney(product.price * quantity);
  double get subtotal => roundMoney(gross - discount.clamp(0, gross));

  CheckoutLine toCheckoutLine() =>
      CheckoutLine(product: product, quantity: quantity, discount: discount);

  CartItem copyWith({int? quantity, double? discount, int? available}) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
      discount: discount ?? this.discount,
      available: available ?? this.available,
    );
  }
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  final Ref ref;

  CartNotifier(this.ref) : super([]);

  /// Adds [quantity] of [product], allowing up to the total sellable stock
  /// across every unexpired batch.
  Future<AddItemResult> addItem(Product product, int quantity) async {
    final isar = ref.read(isarProvider);

    final freshProduct = await isar.products.get(product.id);
    if (freshProduct == null) return AddItemResult.notFound;
    if (freshProduct.isArchived) return AddItemResult.archived;
    await freshProduct.batches.load();

    final available = await InventoryService.sellableQuantity(isar, freshProduct.id);
    if (available <= 0) {
      return freshProduct.totalStock > 0
          ? AddItemResult.expired
          : AddItemResult.outOfStock;
    }

    final existingIndex =
        state.indexWhere((item) => item.product.id == freshProduct.id);
    final currentQty = existingIndex >= 0 ? state[existingIndex].quantity : 0;
    final requested = currentQty + quantity;
    if (requested > available) return AddItemResult.outOfStock;

    if (existingIndex >= 0) {
      final updated = [...state];
      updated[existingIndex] = updated[existingIndex]
          .copyWith(quantity: requested, available: available);
      state = updated;
    } else {
      state = [
        ...state,
        CartItem(product: freshProduct, quantity: quantity, available: available),
      ];
    }
    return AddItemResult.success;
  }

  /// Changes a line's quantity by [delta]. Returns false if that would
  /// exceed available stock.
  bool updateQuantity(int index, int delta) {
    if (index < 0 || index >= state.length) return false;
    final item = state[index];
    final newQty = item.quantity + delta;
    if (newQty <= 0) {
      removeItem(index);
      return true;
    }
    if (delta > 0 && newQty > item.available) return false;
    final updated = [...state];
    updated[index] = item.copyWith(
      quantity: newQty,
      // Keep the discount within the (possibly smaller) line value.
      discount: item.discount.clamp(0, item.product.price * newQty).toDouble(),
    );
    state = updated;
    return true;
  }

  void setLineDiscount(int index, double discount) {
    if (index < 0 || index >= state.length) return;
    final item = state[index];
    final updated = [...state];
    updated[index] =
        item.copyWith(discount: roundMoney(discount.clamp(0, item.gross).toDouble()));
    state = updated;
  }

  void removeItem(int index) {
    if (index < 0 || index >= state.length) return;
    state = [...state]..removeAt(index);
    if (state.isEmpty) ref.read(cartSaleDiscountProvider.notifier).state = 0;
  }

  void clearCart() {
    state = [];
    ref.read(cartSaleDiscountProvider.notifier).state = 0;
  }

  double get totalAmount => ref.read(cartTotalsProvider).total;

  /// The cart lines as JSON, for records kept outside the database
  /// (pending MoMo payments).
  String get itemsJson => jsonEncode([
        for (final e in state)
          {
            'productId': e.product.id,
            'productName': e.product.name,
            'quantity': e.quantity,
            'price': e.product.price,
            'discount': e.discount,
          }
      ]);

  /// Records the sale and empties the cart. Throws
  /// [SaleValidationException], [InsufficientStockException] or
  /// a PermissionDeniedException with a message for the cashier.
  Future<Sale> completeSale({
    required List<PaymentInput> payments,
    double? amountTendered,
    String? paystackReference,
    String? momoProvider,
    String? momoPhone,
    int? cashierId,
  }) async {
    final sale = await SaleService.completeSale(
      ref.read(isarProvider),
      ref.read(currentUserProvider),
      lines: [for (final i in state) i.toCheckoutLine()],
      payments: payments,
      saleDiscount: ref.read(cartSaleDiscountProvider),
      tax: ref.read(taxConfigProvider),
      amountTendered: amountTendered,
      paystackReference: paystackReference,
      momoProvider: momoProvider,
      momoPhone: momoPhone,
      cashierId: cashierId,
    );
    clearCart();
    ref.read(reportProvider.notifier).refresh();
    return sale;
  }
}
