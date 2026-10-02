/// ============================================
/// Sync Provider — ShopPOS
/// ============================================
/// Runs sync while someone is signed in and sync
/// is configured (ShopPOS Cloud, or the legacy
/// sync server):
///  • every [autoSyncInterval];
///  • [changeSyncDelay] after local changes are
///    queued (a sale, a restock, …);
///  • as soon as the device comes back online.
/// Failed syncs are retried with back-off; every
/// record keeps its id, so retries never create
/// duplicates.
///
/// [SyncState.status] drives the status chip:
/// Offline / Online / Syncing / Synced / Failed.
/// ============================================
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/services/sync_service.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';

const autoSyncInterval = Duration(minutes: 10);
const changeSyncDelay = Duration(seconds: 8);

enum SyncStatus { notConfigured, offline, online, syncing, synced, failed }

extension SyncStatusLabel on SyncStatus {
  String get label => switch (this) {
        SyncStatus.notConfigured => 'Sync off',
        SyncStatus.offline => 'Offline',
        SyncStatus.online => 'Online',
        SyncStatus.syncing => 'Syncing',
        SyncStatus.synced => 'Synced',
        SyncStatus.failed => 'Sync failed',
      };
}

class SyncState {
  final bool running;
  final SyncResult? last;
  final bool online;

  /// Local records waiting to be sent.
  final int pending;

  const SyncState({this.running = false, this.last, this.online = true, this.pending = 0});

  SyncState copyWith({bool? running, SyncResult? last, bool? online, int? pending}) => SyncState(
        running: running ?? this.running,
        last: last ?? this.last,
        online: online ?? this.online,
        pending: pending ?? this.pending,
      );

  SyncStatus statusFor({required bool configured}) {
    if (!configured) return SyncStatus.notConfigured;
    if (running) return SyncStatus.syncing;
    if (!online) return SyncStatus.offline;
    if (last != null && !last!.ok) return SyncStatus.failed;
    if (last != null && pending == 0) return SyncStatus.synced;
    return SyncStatus.online;
  }
}

final syncProvider = StateNotifierProvider<SyncController, SyncState>((ref) {
  return SyncController(ref);
});

/// Whether cloud or legacy sync has been set up. Sync never uses the
/// legacy payment server.
final syncConfiguredProvider = Provider<bool>((ref) {
  final s = ref.watch(storeSettingsProvider);
  final cloud = s.cloudDeviceToken.isNotEmpty && s.cloudUrl.trim().isNotEmpty;
  final legacy = s.syncServerUrl.trim().isNotEmpty && s.syncServerKey.trim().isNotEmpty;
  return cloud || legacy;
});

final syncStatusProvider = Provider<SyncStatus>((ref) {
  final configured = ref.watch(syncConfiguredProvider);
  return ref.watch(syncProvider).statusFor(configured: configured);
});

class SyncController extends StateNotifier<SyncState> {
  final Ref ref;
  Timer? _timer;
  Timer? _changeTimer;
  Timer? _retryTimer;
  int _failures = 0;
  final _subs = <StreamSubscription<Object?>>[];

  SyncController(this.ref) : super(const SyncState()) {
    // Sync while someone is signed in; stop when they sign out.
    ref.listen(currentUserProvider, (_, user) {
      _timer?.cancel();
      if (user != null) {
        _timer = Timer.periodic(autoSyncInterval, (_) => syncNow(quiet: true));
        syncNow(quiet: true);
      }
    }, fireImmediately: true);

    // Clear an old result when sync is switched on/off or reconfigured.
    ref.listen(syncConfiguredProvider, (_, __) {
      if (!state.running) state = SyncState(online: state.online, pending: state.pending);
      _refreshPending();
    });

    _subs.add(Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((c) => c != ConnectivityResult.none);
      final cameBack = online && !state.online;
      state = state.copyWith(online: online);
      if (cameBack) syncNow(quiet: true);
    }));
    Connectivity().checkConnectivity().then((results) {
      if (mounted) state = state.copyWith(online: results.any((c) => c != ConnectivityResult.none));
    });

    // Local changes → sync shortly after (debounced).
    final isar = ref.read(isarProvider);
    for (final stream in SyncService.localChangeStreams(isar)) {
      _subs.add(stream.listen((_) => _onLocalChange()));
    }
    _refreshPending();
  }

  void _onLocalChange() {
    _changeTimer?.cancel();
    _changeTimer = Timer(changeSyncDelay, () async {
      await _refreshPending();
      if (state.pending > 0 && ref.read(currentUserProvider) != null) syncNow(quiet: true);
    });
  }

  Future<void> _refreshPending() async {
    final pending = await SyncService.pendingCount(ref.read(isarProvider));
    if (mounted && pending != state.pending) state = state.copyWith(pending: pending);
  }

  /// Runs a sync unless one is already running or sync isn't set up.
  /// [quiet] syncs (automatic ones) aren't written to the activity log.
  Future<SyncResult?> syncNow({bool quiet = false}) async {
    if (state.running) return null;
    if (!ref.read(syncConfiguredProvider)) return null;

    _retryTimer?.cancel();
    state = state.copyWith(running: true);
    final isar = ref.read(isarProvider);
    final result = await SyncService.syncNow(
      isar,
      baseUrl: ref.read(storeSettingsProvider).syncServerUrl.trim(),
    );
    if (!mounted) return result;
    final pending = await SyncService.pendingCount(isar);
    state = SyncState(
      last: result,
      online: result.error == 'No internet connection.' ? false : state.online,
      pending: pending,
    );

    // Retry failures with back-off: 30 s, 1, 2, 4 … up to 10 minutes.
    // Not when the till was disconnected (needs the owner) or offline
    // (coming back online triggers a sync).
    if (result.ok) {
      _failures = 0;
    } else if (!result.unauthorized && state.online) {
      _failures++;
      final seconds = (30 * (1 << (_failures - 1).clamp(0, 5))).clamp(30, 600);
      _retryTimer = Timer(Duration(seconds: seconds), () => syncNow(quiet: true));
    }

    // Reload settings so the "last synced" time (and settings changed
    // online) show up.
    ref.invalidate(storeSettingsProvider);
    // Failures are logged once per run of failures, not on every retry.
    if (!quiet || (!result.ok && _failures <= 1 && state.online)) {
      await ActivityLogService.log(
        isar,
        ref.read(currentUserProvider),
        ActivityAction.sync,
        result.ok
            ? 'Sent ${result.pushed}, received ${result.pulled}'
                '${result.conflicts > 0 ? ', ${result.conflicts} refused' : ''}'
            : 'Failed: ${result.error}',
      );
    }
    return result;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _changeTimer?.cancel();
    _retryTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
