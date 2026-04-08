import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/product.dart';
import '../models/batch.dart';
import '../models/sale.dart';
import 'database_provider.dart';

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier(ref);
});

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
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  final Ref ref;

  CartNotifier(this.ref) : super([]);

  /// Add item to cart using FEFO (First Expired, First Out)
  Future<void> addItem(Product product, int quantity) async {
    final isar = ref.read(isarProvider);

    // CRITICAL FIX: Preload batches link so Product computed properties work
    final freshProduct = await isar.products.get(product.id);
    if (freshProduct == null) return;

    await freshProduct.batches.load(); // ← This was the missing fix

    final soonestBatch = freshProduct.soonestExpiryBatch;

    if (soonestBatch == null || soonestBatch.quantity < quantity) {
      // Not enough stock or item is expired
      return;
    }

    final newItem = CartItem(
      product: freshProduct, // use preloaded version
      batch: soonestBatch,
      quantity: quantity,
    );

    state = [...state, newItem];
  }

  void removeItem(int index) {
    if (index < 0 || index >= state.length) return;
    state = [...state]..removeAt(index);
  }

  void clearCart() {
    state = [];
  }

  double get totalAmount => state.fold(0.0, (sum, item) => sum + item.subtotal);

  /// Complete the sale and deduct stock from batches
  Future<bool> completeSale(String paymentType, String cashierPin) async {
    final isar = ref.read(isarProvider);

    try {
      await isar.writeTxn(() async {
        // Deduct stock from each batch
        for (var item in state) {
          final batchToUpdate = await isar.batchs.get(item.batch.id); // ← fixed accessor
          if (batchToUpdate != null) {
            batchToUpdate.quantity -= item.quantity;
            await isar.batchs.put(batchToUpdate); // ← fixed accessor
          }
        }

        // Create and save the Sale record
        final sale = Sale()
          ..timestamp = DateTime.now()
          ..cashierPin = cashierPin
          ..totalAmount = totalAmount
          ..paymentType = paymentType
          ..itemsJson = state
              .map((e) => {
                    'productId': e.product.id,
                    'productName': e.product.name,
                    'quantity': e.quantity,
                    'price': e.product.price,
                  })
              .toList()
              .toString();

        await isar.sales.put(sale);
      });

      clearCart();
      return true;
    } catch (e) {
      print('Error completing sale: $e');
      return false;
    }
  }
}