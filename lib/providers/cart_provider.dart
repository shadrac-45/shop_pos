/// ============================================
/// Cart Provider — Riverpod
/// ============================================
/// Manages the shopping cart state for the cashier
/// sales screen. Handles add/remove/update items
/// and total calculations.
/// ============================================
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/sale.dart';

/// Holds the current cart items as a list of SaleItem.
final cartProvider =
    StateNotifierProvider<CartNotifier, List<SaleItem>>((ref) {
  return CartNotifier();
});

/// Computed total amount of all items in the cart.
final cartTotalProvider = Provider<double>((ref) {
  final cart = ref.watch(cartProvider);
  return cart.fold(0.0, (sum, item) => sum + item.subtotal);
});

/// Computed total number of items in the cart.
final cartItemCountProvider = Provider<int>((ref) {
  final cart = ref.watch(cartProvider);
  return cart.fold(0, (sum, item) => sum + item.qty);
});

/// StateNotifier managing cart operations.
class CartNotifier extends StateNotifier<List<SaleItem>> {
  CartNotifier() : super([]);

  /// Add a product to the cart. If it already exists, increment quantity.
  void addItem({
    required int productId,
    required String name,
    required double price,
    int qty = 1,
  }) {
    final existingIndex =
        state.indexWhere((item) => item.productId == productId);

    if (existingIndex >= 0) {
      // Product already in cart — increment quantity
      final updated = List<SaleItem>.from(state);
      updated[existingIndex].qty += qty;
      state = updated;
    } else {
      // New product — add to cart
      state = [
        ...state,
        SaleItem(productId: productId, name: name, price: price, qty: qty),
      ];
    }
  }

  /// Remove a product from the cart entirely.
  void removeItem(int productId) {
    state = state.where((item) => item.productId != productId).toList();
  }

  /// Update the quantity of an item. Removes if qty <= 0.
  void updateQuantity(int productId, int newQty) {
    if (newQty <= 0) {
      removeItem(productId);
      return;
    }

    final updated = List<SaleItem>.from(state);
    final index = updated.indexWhere((item) => item.productId == productId);
    if (index >= 0) {
      updated[index].qty = newQty;
      state = updated;
    }
  }

  /// Increment quantity by 1.
  void increment(int productId) {
    final index = state.indexWhere((item) => item.productId == productId);
    if (index >= 0) {
      final updated = List<SaleItem>.from(state);
      updated[index].qty += 1;
      state = updated;
    }
  }

  /// Decrement quantity by 1. Removes if it reaches 0.
  void decrement(int productId) {
    final index = state.indexWhere((item) => item.productId == productId);
    if (index >= 0) {
      if (state[index].qty <= 1) {
        removeItem(productId);
      } else {
        final updated = List<SaleItem>.from(state);
        updated[index].qty -= 1;
        state = updated;
      }
    }
  }

  /// Clear all items from the cart.
  void clearCart() {
    state = [];
  }

  /// Get the quantity of a specific product in the cart.
  int getQuantity(int productId) {
    final index = state.indexWhere((item) => item.productId == productId);
    return index >= 0 ? state[index].qty : 0;
  }
}
