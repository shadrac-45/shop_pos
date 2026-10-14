/// ============================================
/// Cloud Dashboard — ShopPOS
/// ============================================
/// Owners and managers, from anywhere with
/// internet: today's figures, sales, low stock,
/// MoMo payments, activity, tills and staff of
/// any shop they are authorized for (the cloud
/// decides which; the shop picker only lists
/// those). Reads the cloud directly with the
/// signed-in person's own session.
/// ============================================
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/providers/sync_provider.dart';
import 'package:shop_pos/core/services/cloud_service.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/cloud/screens/alerts_screens.dart';
import 'package:shop_pos/features/notifications/notification_center.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';

/// Thin client for the management API, as the signed-in person.
class CloudApi {
  final Dio _dio;
  final String token;
  CloudApi(String baseUrl, this.token)
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (_) => true,
        ));

  Future<Map<String, dynamic>> call(String method, String path,
      {String? shopId, Map<String, dynamic>? query, Object? body}) async {
    final r = await _dio.request<Object>(path,
        data: body,
        queryParameters: query,
        options: Options(method: method, headers: {
          'authorization': 'Bearer $token',
          if (shopId != null) 'x-shop-id': shopId,
        }));
    final data = r.data;
    if (data is Map && (r.statusCode ?? 500) < 300) return Map<String, dynamic>.from(data);
    throw CloudApiException(
        data is Map ? (data['message'] as String? ?? 'Error ${r.statusCode}') : 'Error ${r.statusCode}',
        r.statusCode ?? 0);
  }
}

class CloudApiException implements Exception {
  final String message;
  final int status;
  CloudApiException(this.message, this.status);
  @override
  String toString() => message;
}

class CloudDashboardScreen extends ConsumerStatefulWidget {
  const CloudDashboardScreen({super.key});

  @override
  ConsumerState<CloudDashboardScreen> createState() => _CloudDashboardScreenState();
}

class _CloudDashboardScreenState extends ConsumerState<CloudDashboardScreen> {
  CloudApi? _api;
  List<Map<String, dynamic>> _shops = const [];

  /// Whether this business may add shops (from the server; see GET /shops).
  bool _canAddShops = false;
  String? _shopId;
  String? _error;
  int _reload = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final settings = ref.read(storeSettingsProvider);
    final user = ref.read(currentUserProvider);
    final fresh = user == null ? null : await ref.read(isarProvider).appUsers.get(user.id);
    if (!CloudService.isConnected(settings)) {
      setState(() => _error = 'This till is not connected to ShopPOS Cloud.');
      return;
    }
    if (!CloudService.hasSession(fresh)) {
      final ok = await ref.read(currentUserProvider.notifier).ensureCloudSession();
      if (!ok) {
        setState(() => _error = 'Sign out and sign in again while online to see the cloud dashboard.');
        return;
      }
    }
    final me = await ref.read(isarProvider).appUsers.get(user!.id);
    _api = CloudApi(settings.cloudUrl, me!.cloudToken!);
    try {
      final r = await _api!.call('GET', '/shops');
      setState(() {
        _shops = [for (final s in r['shops'] as List) Map<String, dynamic>.from(s as Map)];
        // The server decides (owner + the platform allows branches).
        _canAddShops = r['canAddShops'] == true;
        _shopId = _shops.any((s) => s['id'] == settings.cloudShopId)
            ? settings.cloudShopId
            : (_shops.isEmpty ? null : _shops.first['id'] as String);
        _error = _shops.isEmpty ? 'Your account is not assigned to any shop.' : null;
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _addShop() async {
    final name = TextEditingController();
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a shop'),
        content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Shop name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      final r = await _api!.call('POST', '/shops', body: {'name': name.text.trim()});
      await _start();
      setState(() => _shopId = (r['shop'] as Map)['id'] as String);
      if (mounted) context.showSuccessSnackbar('Added ${name.text.trim()}.');
    } catch (e) {
      if (mounted) context.showErrorSnackbar('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    // New data arrived through sync: refresh what is on screen.
    ref.listen(syncProvider.select((s) => s.last?.at), (_, __) {
      if (mounted) setState(() => _reload++);
    });
    final canStaff = Permissions.can(user, Permission.manageStaff);
    final canTills = Permissions.can(user, Permission.manageSettings);
    final tabs = <(String, Widget Function())>[
      // Every shop at a glance; tapping one opens its alerts.
      ('Shops', () => ShopsOverviewTab(
            api: _api!,
            key: ValueKey('o$_reload'),
            onOpenShop: (id) {
              setState(() => _shopId = id);
              final tabCtx = _tabContext;
              if (tabCtx != null) DefaultTabController.of(tabCtx).animateTo(1);
            },
          )),
      ('Alerts', () => AlertsTab(
            api: _api!,
            shopId: _shopId!,
            canEditSettings: Permissions.can(user, Permission.manageSettings),
            key: ValueKey('al$_shopId$_reload'),
          )),
      ('Today', () => _TodayTab(api: _api!, shopId: _shopId!, key: ValueKey('t$_shopId$_reload'))),
      ('Sales', () => _SalesTab(api: _api!, shopId: _shopId!, key: ValueKey('s$_shopId$_reload'))),
      ('Low stock', () => _ListTab(api: _api!, shopId: _shopId!, path: '/reports/low-stock', field: 'products',
          tile: (p) => ListTile(
                leading: const Icon(Icons.inventory_2_outlined, color: AppColors.warning),
                title: Text('${p['name']}'),
                trailing: Text('${p['stock']} left (reorder at ${p['reorderLevel']})'),
              ),
          key: ValueKey('l$_shopId$_reload'))),
      ('Payments', () => _ListTab(api: _api!, shopId: _shopId!, path: '/payments', field: 'payments',
          tile: (p) => ListTile(
                leading: Icon(
                    p['status'] == 'success' ? Icons.check_circle_rounded : Icons.hourglass_bottom_rounded,
                    color: p['status'] == 'success' ? AppColors.success : AppColors.warning),
                title: Text('GHS ${((p['amountPesewas'] as num) / 100).toStringAsFixed(2)} · ${p['provider']}'.toUpperCase()),
                subtitle: Text('${p['status']}${p['saleId'] == null ? ' · no sale yet' : ''} · ${_when(p['createdAt'])}'),
              ),
          key: ValueKey('p$_shopId$_reload'))),
      ('Activity', () => _ListTab(api: _api!, shopId: _shopId!, path: '/audit', field: 'entries',
          tile: (e) => ListTile(
                dense: true,
                title: Text('${e['userName'] ?? 'System'} · ${e['action']}'),
                subtitle: Text('${e['details']}\n${_when(e['at'])}${e['deviceId'] != null ? ' · till ${e['deviceId']}' : ''}'),
                isThreeLine: true,
              ),
          key: ValueKey('a$_shopId$_reload'))),
      if (canTills)
        ('Tills', () => _TillsTab(
            api: _api!,
            shopId: _shopId!,
            thisDeviceId: ref.read(storeSettingsProvider).deviceId,
            key: ValueKey('d$_shopId$_reload'))),
      if (canStaff) ('Staff', () => _StaffTab(api: _api!, shopId: _shopId!, shops: _shops, me: user!, key: ValueKey('u$_shopId$_reload'))),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Builder(builder: (tabCtx) {
        _tabContext = tabCtx;
        return Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: _shops.length > 1
              ? DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _shopId,
                    items: [
                      for (final s in _shops)
                        DropdownMenuItem(value: s['id'] as String, child: Text('${s['name']}')),
                    ],
                    onChanged: (v) => setState(() => _shopId = v),
                  ),
                )
              : Text(_shops.isEmpty ? 'Cloud dashboard' : '${_shops.first['name']}'),
          actions: [
            const NotificationBell(),
            if (Permissions.can(user, Permission.manageShops) && _canAddShops && _api != null)
              IconButton(tooltip: 'Add a shop', icon: const Icon(Icons.add_business_rounded), onPressed: _addShop),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => setState(() => _reload++),
            ),
          ],
          bottom: _shopId == null || _api == null
              ? null
              : TabBar(isScrollable: true, tabs: [for (final t in tabs) Tab(text: t.$1)]),
        ),
        body: _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
            : _shopId == null || _api == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [for (final t in tabs) t.$2()]),
        );
      }),
    );
  }

  BuildContext? _tabContext;
}

String _when(Object? iso) {
  final d = iso is String ? DateTime.tryParse(iso)?.toLocal() : null;
  return d == null ? '—' : DateHelpers.formatDateTime(d);
}

String _money(Object? v) => 'GHS ${((v as num?) ?? 0).toStringAsFixed(2)}';

DateTime _startOfToday() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Loads [path] and shows a list of [field].
class _ListTab extends StatelessWidget {
  final CloudApi api;
  final String shopId;
  final String path;
  final String field;
  final Widget Function(Map<String, dynamic>) tile;
  const _ListTab({required this.api, required this.shopId, required this.path, required this.field, required this.tile, super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: api.call('GET', path, shopId: shopId, query: {
        'from': DateTime.now().subtract(const Duration(days: 30)).toUtc().toIso8601String(),
        'to': DateTime.now().add(const Duration(minutes: 1)).toUtc().toIso8601String(),
        'limit': 200,
      }),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = [for (final r in snap.data![field] as List) Map<String, dynamic>.from(r as Map)];
        if (rows.isEmpty) return const Center(child: Text('Nothing here yet.'));
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => tile(rows[i]),
        );
      },
    );
  }
}

class _TodayTab extends StatelessWidget {
  final CloudApi api;
  final String shopId;
  const _TodayTab({required this.api, required this.shopId, super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: api.call('GET', '/reports/summary', shopId: shopId, query: {
        'from': _startOfToday().toUtc().toIso8601String(),
        'to': DateTime.now().add(const Duration(minutes: 1)).toUtc().toIso8601String(),
      }),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final r = snap.data!;
        Widget stat(String label, String value, {Color? color}) => Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
                  ]),
                ),
              ),
            );
        return ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [
          Row(children: [stat('Net sales today', _money(r['netSales'])), stat('Sales', '${r['salesCount']}')]),
          Row(children: [
            stat('Gross profit', _money(r['grossProfit'])),
            stat('Expenses', _money(r['expenses'])),
          ]),
          if ((r['unverifiedMomoSales'] as num? ?? 0) > 0)
            Card(
              color: AppColors.warning.withValues(alpha: 0.1),
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                title: Text('${r['unverifiedMomoSales']} MoMo sale(s) not confirmed by Paystack'),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          const Text('By payment method', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final m in r['byPaymentMethod'] as List)
            ListTile(dense: true, title: Text('${m['method']}'.toUpperCase()), trailing: Text('${_money(m['amount'])} · ${m['count']}')),
          const SizedBox(height: AppSpacing.md),
          const Text('Top products', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final p in r['topProducts'] as List)
            ListTile(dense: true, title: Text('${p['name']}'), trailing: Text('${p['quantity']} · ${_money(p['revenue'])}')),
        ]);
      },
    );
  }
}

class _SalesTab extends StatelessWidget {
  final CloudApi api;
  final String shopId;
  const _SalesTab({required this.api, required this.shopId, super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Future.wait([
        api.call('GET', '/sales', shopId: shopId, query: {
          'from': DateTime.now().subtract(const Duration(days: 7)).toUtc().toIso8601String(),
          'to': DateTime.now().add(const Duration(minutes: 1)).toUtc().toIso8601String(),
          'limit': 300,
        }),
        api.call('GET', '/users', shopId: shopId).catchError((_) => <String, dynamic>{'users': <Object>[]}),
      ]),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final names = {for (final u in snap.data![1]['users'] as List) u['id']: u['name']};
        final sales = snap.data![0]['sales'] as List;
        if (sales.isEmpty) return const Center(child: Text('No sales in the last 7 days.'));
        return ListView.separated(
          itemCount: sales.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = sales[i] as Map;
            final voided = s['status'] == 'voided';
            return ListTile(
              title: Text('${s['receiptNumber'] ?? '—'} · ${_money(s['totalAmount'])}',
                  style: TextStyle(decoration: voided ? TextDecoration.lineThrough : null)),
              subtitle: Text('${names[s['cashierId']] ?? 'Unknown'} · ${'${s['paymentType']}'.toUpperCase()} · '
                  '${_when(s['occurredAt'])}${voided ? ' · VOIDED' : ''}'),
              trailing: s['paymentVerified'] == false
                  ? const Tooltip(message: 'MoMo not confirmed', child: Icon(Icons.warning_amber_rounded, color: AppColors.warning))
                  : null,
            );
          },
        );
      },
    );
  }
}

class _StaffTab extends StatefulWidget {
  final CloudApi api;
  final String shopId;
  final List<Map<String, dynamic>> shops;
  final AppUser me;
  const _StaffTab({required this.api, required this.shopId, required this.shops, required this.me, super.key});

  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() => widget.api.call('GET', '/users', shopId: widget.shopId);

  List<String> get _roles => widget.me.role == 'owner'
      ? const ['cashier', 'manager', 'stock_clerk']
      : const ['cashier', 'stock_clerk'];

  Future<void> _add() async {
    final name = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    final pin = TextEditingController();
    var role = 'cashier';
    final shopIds = <String>{widget.shopId};
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('New staff account'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [for (final r in _roles) DropdownMenuItem(value: r, child: Text(r.replaceAll('_', ' ')))],
                onChanged: (v) => set(() => role = v ?? role),
              ),
              TextField(controller: username, autocorrect: false, decoration: const InputDecoration(labelText: 'Username (to sign in)')),
              TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password (10+ letters & numbers)')),
              TextField(controller: pin, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'PIN (4–6 digits)')),
              if (widget.shops.length > 1) ...[
                const Align(alignment: Alignment.centerLeft, child: Text('Shops')),
                for (final s in widget.shops)
                  CheckboxListTile(
                    dense: true,
                    value: shopIds.contains(s['id']),
                    title: Text('${s['name']}'),
                    onChanged: (v) => set(() => v == true ? shopIds.add(s['id'] as String) : shopIds.remove(s['id'])),
                  ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.call('POST', '/users', shopId: widget.shopId, body: {
        'name': name.text.trim(),
        'role': role,
        'username': username.text.trim(),
        'password': password.text,
        'pin': pin.text.trim(),
        'shopIds': shopIds.toList(),
      });
      if (!mounted) return;
      context.showSuccessSnackbar('Created ${name.text.trim()}. They can sign in on any till of their shop.');
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) context.showErrorSnackbar('$e');
    }
  }

  /// Sign-in name/password (so they can join a new device), PIN, or status.
  Future<void> _edit(Map<String, dynamic> u) async {
    final username = TextEditingController(text: u['username'] as String? ?? '');
    final password = TextEditingController();
    final pin = TextEditingController();
    var active = u['isActive'] == true;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('${u['name']}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: username,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Username (to sign in on a new device)')),
              TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'New password (leave empty to keep)', helperText: '10+ characters, letters and numbers')),
              TextField(
                  controller: pin,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: 'New PIN (leave empty to keep)')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: active,
                onChanged: (v) => set(() => active = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final body = <String, dynamic>{
      if (username.text.trim().isNotEmpty && username.text.trim() != u['username']) 'username': username.text.trim(),
      if (password.text.isNotEmpty) 'password': password.text,
      if (pin.text.trim().isNotEmpty) 'pin': pin.text.trim(),
      if (active != (u['isActive'] == true)) 'isActive': active,
    };
    if (body.isEmpty) return;
    if (body.containsKey('password') && (u['username'] == null && !body.containsKey('username'))) {
      if (mounted) context.showErrorSnackbar('Give them a username too, so they can sign in with the password.');
      return;
    }
    try {
      await widget.api.call('PATCH', '/users/${u['id']}', shopId: widget.shopId, body: body);
      if (!mounted) return;
      context.showSuccessSnackbar('Saved. Changed sign-in details end their current sessions.');
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) context.showErrorSnackbar('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _add, icon: const Icon(Icons.person_add_rounded), label: const Text('Add staff')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final users = snap.data!['users'] as List;
          return ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final u = users[i] as Map;
              final manageable = u['role'] != 'owner' &&
                  u['id'] != widget.me.uuid &&
                  (widget.me.role == 'owner' || u['role'] == 'cashier' || u['role'] == 'stock_clerk');
              return ListTile(
                leading: Icon(u['isActive'] == true ? Icons.person_rounded : Icons.person_off_rounded),
                title: Text('${u['name']}'),
                subtitle: Text('${'${u['role']}'.replaceAll('_', ' ')}'
                    '${u['username'] != null ? ' · ${u['username']}' : ' · no sign-in name yet'}'
                    '${u['email'] != null ? ' · ${u['email']}' : ''}'),
                trailing: manageable ? const Icon(Icons.edit_rounded) : null,
                onTap: manageable ? () => _edit(Map<String, dynamic>.from(u)) : null,
              );
            },
          );
        },
      ),
    );
  }
}

/// The shop's tills; old or lost ones can be disconnected.
class _TillsTab extends StatefulWidget {
  final CloudApi api;
  final String shopId;
  final String thisDeviceId;
  const _TillsTab({required this.api, required this.shopId, required this.thisDeviceId, super.key});

  @override
  State<_TillsTab> createState() => _TillsTabState();
}

class _TillsTabState extends State<_TillsTab> {
  late Future<Map<String, dynamic>> _future = _load();
  Future<Map<String, dynamic>> _load() => widget.api.call('GET', '/devices', shopId: widget.shopId);

  Future<void> _disconnect(Map d) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Disconnect till ${d['code']}?'),
        content: const Text(
            'It stops syncing at once and everyone signed in on it is signed out of the cloud. '
            'Its sales already in the cloud are kept. It can join again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.call('DELETE', '/devices/${d['id']}', shopId: widget.shopId);
      if (!mounted) return;
      context.showSuccessSnackbar('Till ${d['code']} disconnected.');
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) context.showErrorSnackbar('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final devices = snap.data!['devices'] as List;
        return ListView.separated(
          itemCount: devices.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final d = devices[i] as Map;
            final mine = d['id'] == widget.thisDeviceId;
            final active = d['status'] == 'active';
            return ListTile(
              leading: CircleAvatar(child: Text('${d['code'] ?? '?'}')),
              title: Text('${d['name'] ?? d['id']}${mine ? ' (this device)' : ''}'),
              subtitle: Text('${d['status']} · ${d['activeUser'] ?? 'nobody'} · last seen ${_when(d['lastSeenAt'])}'),
              trailing: active && !mine
                  ? IconButton(
                      tooltip: 'Disconnect',
                      icon: const Icon(Icons.link_off_rounded, color: AppColors.danger),
                      onPressed: () => _disconnect(d),
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}

/// Settings entry point helper: whether the dashboard makes sense here.
bool cloudDashboardAvailable(StoreSettings s, AppUser? user) =>
    CloudService.isConnected(s) && Permissions.can(user, Permission.viewReports);
