/// ============================================
/// Sync Provider — ShopPOS
/// ============================================
/// Runs cloud sync on demand and every
/// [autoSyncInterval] while someone is signed in
/// and sync is configured.
/// ============================================
library;

import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/services/sync_service.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';

const autoSyncInterval = Duration(minutes: 10);

class SyncState {
  final bool running;
  final SyncResult? last;
  const SyncState({this.running = false, this.last});
}

final syncProvider = StateNotifierProvider<SyncController, SyncState>((ref) {
  return SyncController(ref);
});

/// Whether the store has entered what sync needs.
final syncConfiguredProvider = Provider<bool>((ref) {
  final s = ref.watch(storeSettingsProvider);
  return s.backendUrl.trim().isNotEmpty && s.syncApiKey.trim().isNotEmpty;
});

class SyncController extends StateNotifier<SyncState> {
  final Ref ref;
  Timer? _timer;

  SyncController(this.ref) : super(const SyncState()) {
    // Sync while someone is signed in; stop when they sign out.
    ref.listen(currentUserProvider, (_, user) {
      _timer?.cancel();
      if (user != null) {
        _timer = Timer.periodic(autoSyncInterval, (_) => syncNow(quiet: true));
        syncNow(quiet: true);
      }
    }, fireImmediately: true);
  }

  /// Runs a sync unless one is already running or sync isn't set up.
  /// [quiet] syncs (automatic ones) aren't written to the activity log.
  Future<SyncResult?> syncNow({bool quiet = false}) async {
    if (state.running) return null;
    if (!ref.read(syncConfiguredProvider)) return null;

    state = SyncState(running: true, last: state.last);
    final isar = ref.read(isarProvider);
    final result = await SyncService.syncNow(
      isar,
      baseUrl: ref.read(backendUrlProvider),
    );
    if (!mounted) return result;
    state = SyncState(last: result);

    // Reload settings so the "last synced" time on screen updates.
    ref.invalidate(storeSettingsProvider);
    if (!quiet || !result.ok) {
      await ActivityLogService.log(
        isar,
        ref.read(currentUserProvider),
        ActivityAction.sync,
        result.ok
            ? 'Sent ${result.pushed}, received ${result.pulled}'
            : 'Failed: ${result.error}',
      );
    }
    return result;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
