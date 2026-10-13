/// ============================================
/// Notification store — ShopPOS
/// ============================================
/// Keeps the signed-in person's notifications on
/// this device:
///  • refresh(): downloads their notifications
///    from ShopPOS Cloud (after each sync and at
///    sign-in) and stores them locally;
///  • markRead(): marks them read here at once
///    and tells the cloud when online (queued
///    while offline).
/// The notification centre and the header bell
/// read only from this local store.
/// ============================================
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/providers/sync_provider.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/cloud/screens/alerts_screens.dart';
import 'package:shop_pos/features/cloud/screens/cloud_dashboard_screen.dart' show CloudApi;
import 'package:shop_pos/features/notifications/models/app_notification.dart';

/// Notifications of the signed-in person, newest first (live).
final notificationsProvider = StreamProvider.autoDispose<List<AppNotification>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user?.uuid == null) return Stream.value(const []);
  return ref
      .watch(isarProvider)
      .appNotifications
      .filter()
      .userUuidEqualTo(user!.uuid!)
      .sortByCreatedAtDesc()
      .watch(fireImmediately: true);
});

/// Unread count for the header bell (live).
final unreadNotificationsProvider = Provider.autoDispose<int>((ref) {
  final list = ref.watch(notificationsProvider).valueOrNull ?? const [];
  return list.where((n) => !n.read).length;
});

final notificationStoreProvider = Provider<NotificationStore>((ref) {
  final store = NotificationStore(ref);
  // Fresh notifications after every sync (the long-poll triggers a sync
  // as soon as the cloud raises an alert) and at sign-in.
  ref.listen(syncProvider.select((s) => s.last?.at), (_, __) => unawaited(store.refresh()));
  ref.listen(currentUserProvider, (_, user) {
    if (user != null) unawaited(store.refresh());
  }, fireImmediately: true);
  return store;
});

class NotificationStore {
  final Ref ref;
  NotificationStore(this.ref);
  bool _busy = false;

  bool get _allowed => Permissions.can(ref.read(currentUserProvider), Permission.viewReports);

  /// Downloads the person's latest notifications into the local store and
  /// uploads read marks made offline. Silent when offline.
  Future<void> refresh() async {
    if (_busy || !_allowed) return;
    final user = ref.read(currentUserProvider);
    if (user?.uuid == null) return;
    _busy = true;
    try {
      final api = await _apiOrNull();
      if (api == null) return;
      final isar = ref.read(isarProvider);

      // Read marks made offline go up first.
      final pending = await isar.appNotifications
          .filter()
          .userUuidEqualTo(user!.uuid!)
          .readPendingUploadEqualTo(true)
          .findAll();
      if (pending.isNotEmpty) {
        await api.call('POST', '/notifications/read', body: {'ids': [for (final n in pending) n.cloudId]});
        await isar.writeTxn(() async {
          for (final n in pending) {
            n.readPendingUpload = false;
          }
          await isar.appNotifications.putAll(pending);
        });
      }

      final r = await api.call('GET', '/notifications', query: {'limit': 200});
      final remote = r['notifications'] as List;
      await isar.writeTxn(() async {
        for (final m in remote) {
          final cloudId = m['id'] as String;
          final existing = await isar.appNotifications.filter().cloudIdEqualTo(cloudId).findFirst();
          final n = existing ?? AppNotification()
            ..cloudId = cloudId
            ..userUuid = user.uuid!;
          n
            ..shopId = m['shopId'] as String? ?? ''
            ..shopName = m['shopName'] as String? ?? ''
            ..type = m['type'] as String? ?? ''
            ..severity = m['severity'] as String? ?? 'info'
            ..title = m['title'] as String? ?? ''
            ..body = m['body'] as String? ?? ''
            ..createdAt = DateTime.tryParse(m['createdAt'] as String? ?? '')?.toLocal() ?? DateTime.now()
            // Read anywhere (another device) counts as read here; a local
            // read not yet uploaded stays read.
            ..read = (m['read'] == true) || (existing?.read ?? false);
          await isar.appNotifications.put(n);
        }
      });
    } catch (e) {
      debugPrint('[Notifications] refresh skipped: $e');
    } finally {
      _busy = false;
    }
  }

  Future<CloudApi?> _apiOrNull() async {
    try {
      return await cloudApiForRef(ref);
    } catch (_) {
      return null;
    }
  }

  /// Marks [items] read now; tells the cloud when possible.
  Future<void> markRead(List<AppNotification> items) async {
    final unread = items.where((n) => !n.read).toList();
    if (unread.isEmpty) return;
    final isar = ref.read(isarProvider);
    await isar.writeTxn(() async {
      for (final n in unread) {
        n
          ..read = true
          ..readPendingUpload = true;
      }
      await isar.appNotifications.putAll(unread);
    });
    unawaited(refresh()); // uploads the read marks if online
  }

  /// Removes read notifications older than [age] from this device.
  Future<int> clearOldRead({Duration age = const Duration(days: 30)}) async {
    final user = ref.read(currentUserProvider);
    if (user?.uuid == null) return 0;
    final isar = ref.read(isarProvider);
    return isar.writeTxn(() => isar.appNotifications
        .filter()
        .userUuidEqualTo(user!.uuid!)
        .readEqualTo(true)
        .readPendingUploadEqualTo(false)
        .createdAtLessThan(DateTime.now().subtract(age))
        .deleteAll());
  }
}
