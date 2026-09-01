import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/features/reports/providers/report_provider.dart';

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier(ref);
});

enum AddItemResult { success, notFound, outOfStock, expired }

class CartItem {
  final Product product;
  final Batch batch;
  final int quantity;

  CartItem({
    required this.product,
    required this.batch,
    required this.quantity,
  });

  double get subtotal => product.price * quantity;

  CartItem copyWith({int? quantity}) {
    return CartItem(
      product: product,
      batch: batch,
      quantity: quantity ?? this.quantity,
    );
  }
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  final Ref ref;

  CartNotifier(this.ref) : super([]);

  /// Add item to cart using FEFO (First Expired, First Out)
  Future<AddItemResult> addItem(Product product, int quantity) async {
    final isar = ref.read(isarProvider);

    final freshProduct = await isar.products.get(product.id);
    if (freshProduct == null) return AddItemResult.notFound;

    await freshProduct.batches.load();

    if (freshProduct.isExpired) {
      return AddItemResult.expired;
    }

    final soonestBatch = freshProduct.soonestExpiryBatch;

    // Check existing item in cart
    final existingIndex = state.indexWhere((item) => item.product.id == freshProduct.id);
    final currentQtyInCart = existingIndex >= 0 ? state[existingIndex].quantity : 0;
    final totalRequestedQty = currentQtyInCart + quantity;

    if (soonestBatch == null || soonestBatch.quantity < totalRequestedQty) {
      return AddItemResult.outOfStock;
    }

    if (existingIndex >= 0) {
      final updatedList = [...state];
      updatedList[existingIndex] = updatedList[existingIndex].copyWith(
        quantity: totalRequestedQty,
      );
      state = updatedList;
    } else {
      final newItem = CartItem(
        product: freshProduct,
        batch: soonestBatch,
        quantity: quantity,
      );
      state = [...state, newItem];
    }

    return AddItemResult.success;
  }

  /// Update item quantity by delta (+1 or -1)
  void updateQuantity(int index, int delta) {
    if (index < 0 || index >= state.length) return;

    final newQty = state[index].quantity + delta;
    if (newQty <= 0) {
      removeItem(index);
    } else {
      // Check batch capacity before increasing
      if (delta > 0 && state[index].batch.quantity < newQty) {
        return; // Exceeds available batch stock
      }
      final updatedList = [...state];
      updatedList[index] = updatedList[index].copyWith(quantity: newQty);
      state = updatedList;
    }
  }

  void removeItem(int index) {
    if (index < 0 || index >= state.length) return;
    state = [...state]..removeAt(index);
  }

  void clearCart() {
    state = [];
  }

  double get totalAmount => state.fold(0.0, (sum, item) => sum + item.subtotal);

  // ── Private Helpers ─────────────────────────────────────

  String _serializeCartItems() {
    final itemsList = state
        .map((e) => {
              'productId': e.product.id,
              'productName': e.product.name,
              'quantity': e.quantity,
              'price': e.product.price,
            })
        .toList();
    return jsonEncode(itemsList);
  }

  Future<void> _deductStock(Isar isar) async {
    for (var item in state) {
      final batchToUpdate = await isar.batchs.get(item.batch.id);
      if (batchToUpdate != null) {
        batchToUpdate.quantity -= item.quantity;
        await isar.batchs.put(batchToUpdate);
      }
    }
  }

  // ── Sale Completion ─────────────────────────────────────

  /// Complete the sale and deduct stock from batches.
  /// [cashierId] is the AppUser.id of the logged-in staff member (0 = unknown).
  Future<bool> completeSale(
    String paymentType, {
    int cashierId = 0,
  }) async {
    final isar = ref.read(isarProvider);

    try {
      await isar.writeTxn(() async {
        await _deductStock(isar);

        final sale = Sale()
          ..timestamp = DateTime.now()
          ..cashierId = cashierId
          ..totalAmount = totalAmount
          ..paymentType = paymentType
          ..itemsJson = _serializeCartItems()
          ..isSynced = false;

        await isar.sales.put(sale);
      });

      clearCart();
      ref.read(reportProvider.notifier).loadTodaySales(force: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Complete a Mobile Money sale via Paystack charge.
  /// [cashierId] is the AppUser.id of the logged-in staff member (0 = unknown).
  Future<bool> completeSaleMomo({
    required String paystackReference,
    required String provider,
    required String phone,
    int cashierId = 0,
  }) async {
    final isar = ref.read(isarProvider);

    try {
      await isar.writeTxn(() async {
        await _deductStock(isar);

        final sale = Sale()
          ..timestamp = DateTime.now()
          ..cashierId = cashierId
          ..totalAmount = totalAmount
          ..paymentType = AppConstants.paymentMomoPaystack
          ..itemsJson = _serializeCartItems()
          ..isSynced = false
          ..paystackReference = paystackReference
          ..momoProvider = provider
          ..momoPhone = phone;

        await isar.sales.put(sale);
      });

      clearCart();
      // Force refresh the report provider state so reports reflect the new sale immediately
      ref.read(reportProvider.notifier).loadTodaySales(force: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}