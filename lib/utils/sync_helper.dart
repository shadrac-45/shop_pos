import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';

import '../models/sale.dart';
import '../providers/database_provider.dart';   // ← Fixed import path

/// SyncHelper - Placeholder for future cloud sync (MongoDB)
class SyncHelper {
  final Ref ref;

  SyncHelper(this.ref);

  /// Sync pending sales to cloud (placeholder for now)
  Future<void> syncPendingSales() async {
    final isar = ref.read(isarProvider);
    final pendingSales = await isar.sales
        .filter()
        .timestampGreaterThan(DateTime.now().subtract(const Duration(days: 7)))
        .findAll();

    print('SyncHelper: ${pendingSales.length} sales ready for sync (placeholder)');
  }

  /// Placeholder for product sync
  Future<void> syncProducts() async {
    print('SyncHelper: Product sync called (placeholder)');
  }

  /// Check if device is online (placeholder)
  Future<bool> isOnline() async {
    return true; // You can improve this with connectivity_plus later
  }
}

// Provider
final syncHelperProvider = Provider<SyncHelper>((ref) {
  return SyncHelper(ref);
});