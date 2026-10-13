/// ============================================
/// Cloud Section — ShopPOS
/// ============================================
/// Integrations → ShopPOS Cloud. The owner
/// connects this till to the cloud by creating
/// the cloud shop (first till) or signing in to
/// it (more tills). Once connected, the cloud
/// handles sync and Mobile Money for this till.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/providers/sync_provider.dart';
import 'package:shop_pos/core/services/cloud_service.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/cloud/widgets/shop_picker.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';
import 'package:shop_pos/features/shared/widgets/magic/border_beam.dart';

class CloudSection extends ConsumerStatefulWidget {
  const CloudSection({super.key});

  @override
  ConsumerState<CloudSection> createState() => _CloudSectionState();
}

class _CloudSectionState extends ConsumerState<CloudSection> {
  late final _url = TextEditingController(text: ref.read(storeSettingsProvider).cloudUrl);
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _createShop = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _errorField;

  @override
  void dispose() {
    for (final c in [_url, _email, _password, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    final url = CloudService.normaliseUrl(_url.text);
    if (_url.text.trim().isEmpty || _email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter the cloud address, email and password.');
      return;
    }
    if (url.isEmpty) {
      setState(() {
        _error = "That address is not valid. Use your shop's address (kofis-shop.example.com) or a local one (http://192.168.1.10:3001).";
        _errorField = 'url';
      });
      return;
    }
    // Show the cleaned-up address so the owner sees what is used.
    _url.text = url.replaceFirst(RegExp(r'/api$'), '');
    setState(() {
      _busy = true;
      _error = null;
      _errorField = null;
    });
    final isar = ref.read(isarProvider);
    final CloudConnectResult result;
    if (_createShop) {
      result = await CloudService.createShop(isar,
          url: url, email: _email.text, password: _password.text, signupCode: _code.text);
    } else {
      result = await _join(isar, url);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
      _errorField = result.field;
    });
    if (!result.ok) return;
    _password.clear();
    ref.invalidate(storeSettingsProvider);
    await ActivityLogService.log(isar, ref.read(currentUserProvider), ActivityAction.settingsChanged,
        'Till connected to ShopPOS Cloud (${result.shopName})');
    if (!mounted) return;
    context.showSuccessSnackbar('Connected to ${result.shopName}. Uploading this till\'s records…');
    await ref.read(syncProvider.notifier).syncNow();
  }

  /// Joins one of the signed-in person's shops; they become the person
  /// signed in on this till.
  Future<CloudConnectResult> _join(Isar isar, String url) async {
    final login = await CloudService.login(url: url, identifier: _email.text, password: _password.text);
    if (!login.ok) return CloudConnectResult.failed(login.error!, field: login.field);
    if (!mounted) return const CloudConnectResult.failed('Cancelled.');
    final shop = await pickShop(context, login.shops);
    if (shop == null) return const CloudConnectResult.failed('Choose a shop to join.');
    try {
      final user = await CloudService.joinShop(isar, login, shop.id);
      ref.read(currentUserProvider.notifier).setUser(user);
      return CloudConnectResult.ok(shop.name);
    } on CloudJoinException catch (e) {
      return CloudConnectResult.failed(e.message);
    } catch (e) {
      return CloudConnectResult.failed('Could not join: $e');
    }
  }

  Future<void> _disconnect() async {
    final isar = ref.read(isarProvider);
    await CloudService.disconnect(isar);
    ref.invalidate(storeSettingsProvider);
    await ActivityLogService.log(isar, ref.read(currentUserProvider), ActivityAction.settingsChanged,
        'Till disconnected from ShopPOS Cloud');
    if (mounted) context.showSuccessSnackbar('Disconnected. Sales stay on this till.');
  }

  Future<void> _syncNow() async {
    final result = await ref.read(syncProvider.notifier).syncNow();
    if (!mounted || result == null) return;
    if (result.ok) {
      context.showSuccessSnackbar('Synced: sent ${result.pushed}, received ${result.pulled}'
          '${result.conflicts > 0 ? ' · ${result.conflicts} refused' : ''}.');
    } else {
      context.showErrorSnackbar(result.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(storeSettingsProvider);
    final connected = s.cloudDeviceToken.isNotEmpty && s.cloudUrl.isNotEmpty;
    final sync = ref.watch(syncProvider);
    final status = ref.watch(syncStatusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('ShopPOS Cloud'),
        const Text(
          'Backs up this till, shares sales, stock, products and staff with the shop\'s '
          'other tills, and takes Mobile Money. Sales still work offline and are sent '
          'automatically when the internet returns.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        TouchableCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: connected ? _connected(s, sync, status) : _connectForm(),
        ),
      ],
    );
  }

  Widget _connected(dynamic s, SyncState sync, SyncStatus status) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.cloud_done_rounded, color: AppColors.success),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('Connected to ${s.cloudShopName}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SyncStatusChip(),
          ],
        ),
        const SizedBox(height: 4),
        Text(s.cloudUrl as String, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          [
            s.lastSyncAt == null
                ? 'Not synced yet'
                : 'Last synced ${DateHelpers.formatDateTime((s.lastSyncAt as DateTime).toLocal())}',
            if (sync.pending > 0) '${sync.pending} waiting to send',
          ].join(' · '),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        if (sync.last != null && !sync.last!.ok)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(sync.last!.error!, style: const TextStyle(color: AppColors.danger)),
          ),
        if (sync.last != null && sync.last!.ok && sync.last!.conflicts > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${sync.last!.conflicts} records were refused by the cloud (see Activity log).',
                style: const TextStyle(color: AppColors.warning)),
          ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: sync.running ? null : _syncNow,
                icon: const Icon(Icons.sync_rounded),
                label: Text(sync.running ? 'Syncing…' : 'Sync Now'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton(
                onPressed: sync.running ? null : _disconnect,
                child: const Text('Disconnect', style: TextStyle(color: AppColors.danger)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _connectForm() {
    final insecure = CloudService.isInsecure(CloudService.normaliseUrl(_url.text));
    String? fieldError(String f) => _errorField == f ? _error : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Join my cloud shop')),
            ButtonSegment(value: true, label: Text('Create cloud shop')),
          ],
          selected: {_createShop},
          onSelectionChanged: (v) => setState(() => _createShop = v.first),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _createShop
              ? 'First till only: creates the shop online with this till\'s products, staff and sales.'
              : 'Adds this till to a shop already in the cloud. Best on a new till: its '
                  'products and staff are downloaded.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Cloud address',
            hintText: 'kofis-shop.example.com',
            errorText: fieldError('url'),
          ),
        ),
        if (insecure)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Use https:// for an internet address so passwords are encrypted.',
                style: TextStyle(color: AppColors.warning, fontSize: 12)),
          ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(labelText: _createShop ? 'Owner email' : 'Email or username', errorText: fieldError('email')),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _password,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: _createShop ? 'New cloud password (10+ characters)' : 'Cloud password',
            errorText: fieldError('password'),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (_createShop) ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _code,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Sign-up code (if your server needs one)',
              errorText: fieldError('signupCode'),
            ),
          ),
        ],
        if (_error != null && _errorField == null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ),
        const SizedBox(height: AppSpacing.md),
        ElevatedButton.icon(
          onPressed: _busy ? null : _connect,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_upload_rounded),
          label: Text(_createShop ? 'Create & Connect' : 'Sign In & Connect'),
        ),
      ],
    );
  }
}

/// Small chip showing Offline / Online / Syncing / Synced / Failed.
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    if (status == SyncStatus.notConfigured) return const SizedBox.shrink();
    final pending = ref.watch(syncProvider.select((s) => s.pending));
    final (icon, color) = switch (status) {
      SyncStatus.offline => (Icons.cloud_off_rounded, AppColors.textMuted),
      SyncStatus.syncing => (Icons.sync_rounded, AppColors.primary),
      SyncStatus.synced => (Icons.cloud_done_rounded, AppColors.success),
      SyncStatus.failed => (Icons.sync_problem_rounded, AppColors.danger),
      _ => (Icons.cloud_queue_rounded, AppColors.primary),
    };
    final label = status == SyncStatus.offline && pending > 0
        ? 'Offline · $pending queued'
        : status.label;
    // Text a step darker than the icon so it clears 4.5:1 on the tint.
    final textColor = Color.lerp(color, Colors.black, 0.3)!;
    const radius = BorderRadius.all(Radius.circular(999));
    return Tooltip(
      message: pending > 0 ? '$pending changes waiting to sync' : status.label,
      // The beam runs round the chip only while a sync is in flight.
      child: BorderBeam(
        active: status == SyncStatus.syncing,
        borderRadius: radius,
        size: 36,
        duration: const Duration(milliseconds: 1600),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: radius,
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
