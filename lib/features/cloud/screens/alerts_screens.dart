/// ============================================
/// Monitoring screens — ShopPOS
/// ============================================
/// Multi-shop overview (one card per shop the
/// person may see), per-shop alert drill-down,
/// the notification centre, the login summary,
/// and connecting Telegram. All figures are
/// calculated by the cloud per shop; the app
/// only shows them.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/services/cloud_service.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/cloud/screens/cloud_dashboard_screen.dart';
import 'package:shop_pos/features/notifications/notification_center.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';

const _severityColor = {
  'critical': AppColors.danger,
  'warning': AppColors.warning,
  'info': AppColors.info,
};
const _typeLabel = {
  'OUT_OF_STOCK': 'Out of stock',
  'LOW_STOCK': 'Low stock',
  'EXPIRED': 'Expired',
  'EXPIRING_SOON': 'Expiring soon',
  'SYNC_FAILURE': 'Till not syncing',
  'PAYMENT_ISSUE': 'Payment issue',
};

String _money(Object? v) => 'GHS ${((v as num?) ?? 0).toStringAsFixed(2)}';
String _when(Object? iso) {
  final d = iso is String ? DateTime.tryParse(iso)?.toLocal() : null;
  return d == null ? '—' : DateHelpers.formatDateTime(d);
}

/// A cloud API client as the signed-in person, or null (not connected,
/// or no session on this till yet).
Future<CloudApi?> cloudApiFor(WidgetRef ref) async {
  final settings = ref.read(storeSettingsProvider);
  final user = ref.read(currentUserProvider);
  if (!CloudService.isConnected(settings) || user == null) return null;
  var me = await ref.read(isarProvider).appUsers.get(user.id);
  if (!CloudService.hasSession(me)) {
    if (!await ref.read(currentUserProvider.notifier).ensureCloudSession()) return null;
    me = await ref.read(isarProvider).appUsers.get(user.id);
  }
  return CloudApi(settings.cloudUrl, me!.cloudToken!);
}

/// Same as [cloudApiFor], from a provider (Ref).
Future<CloudApi?> cloudApiForRef(Ref ref) async {
  final settings = ref.read(storeSettingsProvider);
  final user = ref.read(currentUserProvider);
  if (!CloudService.isConnected(settings) || user == null) return null;
  var me = await ref.read(isarProvider).appUsers.get(user.id);
  if (!CloudService.hasSession(me)) {
    if (!await ref.read(currentUserProvider.notifier).ensureCloudSession()) return null;
    me = await ref.read(isarProvider).appUsers.get(user.id);
  }
  return CloudApi(settings.cloudUrl, me!.cloudToken!);
}

// ════════════════════════════════════════════════════════════════════════
// Overview: one card per shop
// ════════════════════════════════════════════════════════════════════════

class ShopsOverviewTab extends StatelessWidget {
  final CloudApi api;
  final void Function(String shopId) onOpenShop;
  const ShopsOverviewTab({required this.api, required this.onOpenShop, super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: api.call('GET', '/alerts/overview'),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final shops = [for (final s in snap.data!['shops'] as List) Map<String, dynamic>.from(s as Map)];
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [for (final s in shops) _ShopCard(shop: s, onTap: () => onOpenShop(s['id'] as String))],
        );
      },
    );
  }
}

class _ShopCard extends StatelessWidget {
  final Map<String, dynamic> shop;
  final VoidCallback onTap;
  const _ShopCard({required this.shop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, int n, Color color) => Container(
          margin: const EdgeInsets.only(right: 6, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (n > 0 ? color : AppColors.textMuted).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$label $n',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: n > 0 ? color : AppColors.textMuted)),
        );
    final critical = shop['critical'] as int? ?? 0;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.storefront_rounded, color: critical > 0 ? AppColors.danger : AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('${shop['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              if ((shop['unread'] as int? ?? 0) > 0)
                Badge(label: Text('${shop['unread']}'), child: const Icon(Icons.notifications_rounded, size: 20)),
              const Icon(Icons.chevron_right_rounded),
            ]),
            const SizedBox(height: 6),
            Text('Sales today: ${_money(shop['salesToday'])} · ${shop['salesCount']} sale(s)',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Wrap(children: [
              chip('Low stock', shop['lowStock'] as int, AppColors.warning),
              chip('Out of stock', shop['outOfStock'] as int, AppColors.danger),
              chip('Expiring', shop['expiringSoon'] as int, AppColors.warning),
              chip('Expired', shop['expired'] as int, AppColors.danger),
              if ((shop['syncIssues'] as int) > 0) chip('Tills offline', shop['syncIssues'] as int, AppColors.warning),
              if ((shop['paymentIssues'] as int) > 0) chip('Payments', shop['paymentIssues'] as int, AppColors.warning),
            ]),
            Text('${shop['activeAlerts']} active alert(s)', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Drill-down: the selected shop's alerts
// ════════════════════════════════════════════════════════════════════════

class AlertsTab extends StatefulWidget {
  final CloudApi api;
  final String shopId;
  final bool canEditSettings;
  const AlertsTab({required this.api, required this.shopId, required this.canEditSettings, super.key});

  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> {
  String? _type;
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() => Future.wait([
        widget.api.call('GET', '/alerts', shopId: widget.shopId, query: {if (_type != null) 'type': _type}),
        widget.api.call('GET', '/alerts/settings', shopId: widget.shopId),
      ]);

  Future<void> _editDays(int current) async {
    final c = TextEditingController(text: '$current');
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Expiry warning'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Warn this many days before expiry', suffixText: 'days'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final days = int.tryParse(c.text.trim());
    if (ok != true || days == null) return;
    try {
      await widget.api.call('PUT', '/alerts/settings', shopId: widget.shopId, body: {'expiryWarningDays': days});
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) context.showErrorSnackbar('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final alerts = snap.data![0]['alerts'] as List;
        final days = snap.data![1]['expiryWarningDays'] as int;
        return Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
            child: Row(children: [
              for (final t in [null, ..._typeLabel.keys])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t == null ? 'All' : _typeLabel[t]!),
                    selected: _type == t,
                    onSelected: (_) => setState(() {
                      _type = t;
                      _future = _load();
                    }),
                  ),
                ),
            ]),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.event_note_rounded),
            title: Text('Expiry warning: $days days before'),
            trailing: widget.canEditSettings ? const Icon(Icons.edit_rounded, size: 18) : null,
            onTap: widget.canEditSettings ? () => _editDays(days) : null,
          ),
          const Divider(height: 1),
          Expanded(
            child: alerts.isEmpty
                ? const Center(child: Text('No active alerts. 👍'))
                : ListView.separated(
                    itemCount: alerts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = alerts[i] as Map;
                      final color = _severityColor[a['severity']] ?? AppColors.textMuted;
                      return ListTile(
                        leading: Icon(Icons.circle, size: 14, color: color),
                        title: Text('${a['message']}'),
                        subtitle: Text('${_typeLabel[a['type']] ?? a['type']} · since ${_when(a['firstSeenAt'])}'),
                      );
                    },
                  ),
          ),
        ]);
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Telegram
// ════════════════════════════════════════════════════════════════════════

Future<void> connectTelegram(BuildContext context, CloudApi api) async {
  try {
    final channels = await api.call('GET', '/notify/channels');
    if (channels['telegramAvailable'] != true) {
      if (context.mounted) {
        context.showErrorSnackbar('Telegram alerts are not set up on the server yet (TELEGRAM_BOT_TOKEN).');
      }
      return;
    }
    final linked = (channels['channels'] as List).any((c) => c['provider'] == 'telegram' && c['enabled'] == true);
    final link = await api.call('POST', '/notify/telegram/link');
    if (!context.mounted) return;
    final bot = link['botUsername'] as String?;
    final command = '/start ${link['code']}';
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(linked ? 'Telegram is connected' : 'Get alerts on Telegram'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (linked) const Text('To move alerts to another Telegram chat, send this there instead:\n'),
          Text('1. Open Telegram and find ${bot == null ? 'the ShopPOS bot' : '@$bot'}.'),
          const Text('2. Send it this message (valid 10 minutes):'),
          const SizedBox(height: 8),
          SelectableText(command, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (link['deepLink'] != null) ...[
            const SizedBox(height: 8),
            SelectableText('${link['deepLink']}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: command));
              ctx.showSuccessSnackbar('Copied');
            },
            child: const Text('Copy'),
          ),
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  } catch (e) {
    if (context.mounted) context.showErrorSnackbar('$e');
  }
}

// ════════════════════════════════════════════════════════════════════════
// Login summary
// ════════════════════════════════════════════════════════════════════════

/// After an owner/manager signs in: if they have unread alerts, show the
/// most important ones, e.g. "🔴 Shop B — 3 products have expired".
Future<void> showLoginAlertSummary(BuildContext context, WidgetRef ref) async {
  final user = ref.read(currentUserProvider);
  if (!Permissions.can(user, Permission.viewReports)) return;
  final api = await cloudApiFor(ref);
  if (api == null) return;
  Map<String, dynamic> summary;
  try {
    summary = await api.call('GET', '/alerts/summary');
  } catch (_) {
    return; // offline: nothing to show
  }
  final items = summary['items'] as List;
  if (items.isEmpty || !context.mounted) return;
  final open = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${summary['unread']} new alert${summary['unread'] == 1 ? '' : 's'}'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(shrinkWrap: true, children: [
          for (final i in items.take(6))
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${(i as Map)['title']}')),
          if (items.length > 6) Text('…and ${items.length - 6} more'),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('View')),
      ],
    ),
  );
  if (open == true && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationCenterScreen()));
  }
}
