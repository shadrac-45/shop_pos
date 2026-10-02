/// ============================================
/// Stock Alert Service — ShopPOS
/// ============================================
/// Finds products that are low on stock or
/// expiring soon, and raises a local notification
/// about them at most once a day.
/// ============================================
library;

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/services/notification_service.dart';
import 'package:shop_pos/features/products/models/product.dart';

class StockAlerts {
  final List<Product> lowStock;

  /// Products with stock in a batch that expires within
  /// [AppConstants.expiryUrgentDays] (or has already expired).
  final List<Product> expiringSoon;

  const StockAlerts({required this.lowStock, required this.expiringSoon});

  bool get isEmpty => lowStock.isEmpty && expiringSoon.isEmpty;

  /// Pure: works out alerts from products whose batches are loaded.
  static StockAlerts from(Iterable<Product> products) {
    final active = products.where((p) => !p.isArchived).toList();
    return StockAlerts(
      lowStock: active.where((p) => p.isLowStock).toList(),
      expiringSoon: active
          .where((p) => p.batches.any((b) =>
              b.quantity > 0 && b.daysUntilExpiry <= AppConstants.expiryUrgentDays))
          .toList(),
    );
  }

  String describe() {
    final parts = <String>[];
    if (expiringSoon.isNotEmpty) {
      parts.add('${expiringSoon.length} expiring soon or expired: '
          '${expiringSoon.take(3).map((p) => p.name).join(', ')}'
          '${expiringSoon.length > 3 ? '…' : ''}');
    }
    if (lowStock.isNotEmpty) {
      parts.add('${lowStock.length} low on stock: '
          '${lowStock.take(3).map((p) => p.name).join(', ')}'
          '${lowStock.length > 3 ? '…' : ''}');
    }
    return parts.join('. ');
  }
}

class StockAlertService {
  StockAlertService._();

  static const _lastAlertKey = 'stock_alert_last_day';

  static Future<StockAlerts> check(Isar isar) async {
    final products =
        await isar.products.filter().isArchivedEqualTo(false).findAll();
    for (final p in products) {
      await p.batches.load();
    }
    return StockAlerts.from(products);
  }

  /// Notifies about expiring / low-stock products once per calendar day.
  static Future<void> notifyIfDue(
      Isar isar, NotificationService notifications) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (prefs.getString(_lastAlertKey) == today) return;

      final alerts = await check(isar);
      if (alerts.isEmpty) return;
      await notifications.showExpiryAlert(
        expiringCount: alerts.expiringSoon.length + alerts.lowStock.length,
        title: alerts.expiringSoon.isEmpty
            ? '${alerts.lowStock.length} products low on stock'
            : null,
        body: alerts.describe(),
      );
      await prefs.setString(_lastAlertKey, today);
    } catch (e) {
      debugPrint('[StockAlerts] Could not raise alert: $e');
    }
  }
}
