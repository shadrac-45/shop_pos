/// ============================================
/// Sales Provider — Riverpod
/// ============================================
/// Handles completing sales transactions:
/// saving to Isar, deducting stock via FEFO,
/// and querying sales history.
/// ============================================
library;

import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/sale.dart';
import 'database_provider.dart';
import 'product_provider.dart';
import 'cart_provider.dart';
import 'auth_provider.dart';

/// Provides the sales service.
final salesServiceProvider = Provider<SalesService>((ref) {
  return SalesService(ref.watch(isarProvider), ref);
});

/// Provides today's sales for display.
final todaysSalesProvider = FutureProvider<List<Sale>>((ref) async {
  final service = ref.watch(salesServiceProvider);
  return service.getTodaysSales();
});

/// Provides today's total revenue.
final todaysRevenueProvider = FutureProvider<double>((ref) async {
  final service = ref.watch(salesServiceProvider);
  final sales = await service.getTodaysSales();
  return sales.fold<double>(0.0, (sum, sale) => sum + sale.totalAmount);
});

/// Service class for sale operations.
class SalesService {
  final Isar _isar;
  final Ref _ref;

  SalesService(this._isar, this._ref);

  /// Complete a sale: save transaction, deduct stock (FEFO), clear cart.
  Future<Sale?> completeSale({
    required String paymentType,
    double amountCash = 0.0,
    double amountMomo = 0.0,
  }) async {
    final cart = _ref.read(cartProvider);
    final currentUser = _ref.read(currentUserProvider);
    final productService = _ref.read(productServiceProvider);

    if (cart.isEmpty || currentUser == null) return null;

    // Calculate total
    final total = cart.fold(0.0, (sum, item) => sum + item.subtotal);

    // Create the sale record
    final sale = Sale()
      ..timestamp = DateTime.now()
      ..cashierPin = currentUser.pinHash
      ..cashierName = currentUser.name
      ..totalAmount = total
      ..paymentType = paymentType
      ..amountCash = amountCash
      ..amountMomo = amountMomo
      ..itemsJson = jsonEncode(cart.map((e) => e.toJson()).toList());

    // Save sale and deduct stock in a single transaction
    await _isar.writeTxn(() async {
      await _isar.sales.put(sale);
    });

    // Deduct stock for each item using FEFO
    for (final item in cart) {
      await productService.deductStock(item.productId, item.qty);
    }

    // Clear the cart
    _ref.read(cartProvider.notifier).clearCart();

    return sale;
  }

  /// Get all sales from today.
  Future<List<Sale>> getTodaysSales() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _isar.sales
        .filter()
        .timestampBetween(startOfDay, endOfDay)
        .sortByTimestampDesc()
        .findAll();
  }

  /// Get sales for a specific date range.
  Future<List<Sale>> getSalesByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    return _isar.sales
        .filter()
        .timestampBetween(start, end)
        .sortByTimestampDesc()
        .findAll();
  }

  /// Get total revenue for today.
  Future<double> getTodaysRevenue() async {
    final sales = await getTodaysSales();
    return sales.fold<double>(0.0, (sum, sale) => sum + sale.totalAmount);
  }

  /// Get total number of sales today.
  Future<int> getTodaysSaleCount() async {
    final sales = await getTodaysSales();
    return sales.length;
  }

  /// Get all unsynced sales (for future MongoDB sync).
  Future<List<Sale>> getUnsyncedSales() async {
    return _isar.sales
        .filter()
        .isSyncedEqualTo(false)
        .findAll();
  }

  /// Mark sales as synced (for future MongoDB sync).
  Future<void> markAsSynced(List<int> saleIds) async {
    await _isar.writeTxn(() async {
      for (final id in saleIds) {
        final sale = await _isar.sales.get(id);
        if (sale != null) {
          sale.isSynced = true;
          await _isar.sales.put(sale);
        }
      }
    });
  }
}
