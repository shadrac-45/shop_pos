/// ============================================
/// Notification centre + header bell — ShopPOS
/// ============================================
/// Reads the notifications stored on this device
/// (works offline). Pull down to fetch the latest.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/cloud/screens/alerts_screens.dart';
import 'package:shop_pos/features/notifications/models/app_notification.dart';
import 'package:shop_pos/features/notifications/notification_store.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';

const _color = {
  'critical': AppColors.danger,
  'warning': AppColors.warning,
  'info': AppColors.info,
};

/// Bell for the app header, with the unread count. Owners/managers only.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Permissions.can(ref.watch(currentUserProvider), Permission.viewReports)) {
      return const SizedBox.shrink();
    }
    ref.watch(notificationStoreProvider); // keeps notifications refreshing
    final unread = ref.watch(unreadNotificationsProvider);
    return IconButton(
      tooltip: unread == 0 ? 'Notifications' : '$unread unread notifications',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
            color: unread > 0 ? AppColors.primary : AppColors.textSecondary),
      ),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationCenterScreen())),
    );
  }
}

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, AppNotification n) async {
    await ref.read(notificationStoreProvider).markRead([n]);
    if (!context.mounted) return;
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n.title),
        content: SingleChildScrollView(
          child: Text('${n.body}\n\n${n.shopName} · ${DateHelpers.formatDateTime(n.createdAt)}'),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(notificationsProvider);
    final store = ref.read(notificationStoreProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'read':
                  await store.markRead(list.valueOrNull ?? const []);
                case 'clear':
                  final n = await store.clearOldRead(age: Duration.zero);
                  if (context.mounted) context.showSuccessSnackbar('Removed $n read notification(s) from this device.');
                case 'telegram':
                  final api = await cloudApiFor(ref);
                  if (!context.mounted) return;
                  if (api == null) {
                    context.showErrorSnackbar('Connect to ShopPOS Cloud and sign in online first.');
                  } else {
                    await connectTelegram(context, api);
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'read', child: Text('Mark all as read')),
              PopupMenuItem(value: 'clear', child: Text('Clear read notifications')),
              PopupMenuItem(value: 'telegram', child: Text('Get alerts on Telegram')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('$e'))]),
          data: (items) {
            if (items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Icon(Icons.notifications_none_rounded, size: 56, color: AppColors.textMuted),
                SizedBox(height: 12),
                Center(child: Text('No notifications yet.', style: TextStyle(color: AppColors.textSecondary))),
                Center(child: Text('Pull down to check.', style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
              ]);
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final n = items[i];
                return ListTile(
                  leading: Icon(
                    n.read ? Icons.drafts_outlined : Icons.mark_email_unread_rounded,
                    color: n.read ? AppColors.textMuted : (_color[n.severity] ?? AppColors.primary),
                  ),
                  title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.w400 : FontWeight.w700)),
                  subtitle: Text(
                    '${n.body.split('\n').first}\n${n.shopName} · ${DateHelpers.formatDateTime(n.createdAt)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  onTap: () => _open(context, ref, n),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
