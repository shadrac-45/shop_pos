/// ============================================
/// StoreSettings Provider — ShopPOS
/// ============================================
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/models/store_settings.dart';

// ── Read: current StoreSettings ─────────────────────────────────
final storeSettingsProvider = FutureProvider<StoreSettings>((ref) async {
  final isar = ref.watch(isarProvider);
  final settings = await isar.storeSettings.get(1);
  return settings ?? StoreSettings();
});

// ── Write: update StoreSettings ─────────────────────────────────
final storeSettingsNotifierProvider =
    AsyncNotifierProvider<StoreSettingsNotifier, StoreSettings>(
  StoreSettingsNotifier.new,
);

class StoreSettingsNotifier extends AsyncNotifier<StoreSettings> {
  @override
  Future<StoreSettings> build() async {
    final isar = ref.watch(isarProvider);
    final settings = await isar.storeSettings.get(1);
    return settings ?? StoreSettings();
  }

  Future<void> save(StoreSettings updated) async {
    final isar = ref.read(isarProvider);
    await isar.writeTxn(() async => isar.storeSettings.put(updated));
    state = AsyncData(updated);
  }

  Future<void> markSetupCompleted() async {
    final current = state.valueOrNull ?? StoreSettings();
    current.setupCompleted = true;
    await save(current);
  }
}

// ── Convenience: is setup done? ──────────────────────────────────
final setupCompletedProvider = FutureProvider<bool>((ref) async {
  final isar = ref.watch(isarProvider);
  final settings = await isar.storeSettings.get(1);
  return settings?.setupCompleted ?? false;
});
