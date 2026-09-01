import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/core/database/database_provider.dart';

/// SyncHelper - Placeholder for future cloud sync (MongoDB)
class SyncHelper {
  final Ref ref;

  SyncHelper(this.ref);

  /// Sync pending sales to cloud (placeholder for now)
  Future<void> syncPendingSales() async {
    final isar = ref.read(isarProvider);
    final pendingSales = await isar.sales
        .filter()
        .isSyncedEqualTo(false)
        .findAll();

    // Pending sales ready for cloud sync
    if (pendingSales.isEmpty) return;
  }

  /// Placeholder for product sync
  Future<void> syncProducts() async {}

  /// Check if device is online (placeholder)
  Future<bool> isOnline() async {
    return true; // You can improve this with connectivity_plus later
  }
}

// Provider
final syncHelperProvider = Provider<SyncHelper>((ref) {
  return SyncHelper(ref);
});