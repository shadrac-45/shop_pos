/// ============================================
/// Integrations Screen — ShopPOS
/// ============================================
/// Owner-only. Two separate servers:
///  • Payment server: Mobile Money through
///    Paystack (required for MoMo).
///  • Cloud sync server (optional): shares sales,
///    stock and products between tills and keeps
///    an off-device copy. Sync is off until one
///    is set; it never uses the payment server.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/providers/sync_provider.dart';
import 'package:shop_pos/core/services/sync_service.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/sales/services/paystack_service.dart';
import 'package:shop_pos/features/settings/screens/pending_momo_screen.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';

class IntegrationsScreen extends ConsumerStatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  ConsumerState<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends ConsumerState<IntegrationsScreen> {
  late final StoreSettings _initial = ref.read(storeSettingsProvider);
  late final _payUrl = TextEditingController(text: _initial.backendUrl);
  late final _payKey = TextEditingController(text: _initial.syncApiKey);
  late final _syncUrl = TextEditingController(text: _initial.syncServerUrl);
  late final _syncKey = TextEditingController(text: _initial.syncServerKey);
  bool _obscurePayKey = true;
  bool _obscureSyncKey = true;
  bool _saving = false;
  bool? _payOk;
  String? _payError;
  bool? _syncOk;
  String? _syncError;

  @override
  void dispose() {
    for (final c in [_payUrl, _payKey, _syncUrl, _syncKey]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Trims trailing slashes; returns null (and shows why) if invalid.
  String? _cleanUrl(TextEditingController c) {
    final url = c.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isNotEmpty && !RegExp(r'^https?://').hasMatch(url)) {
      context.showErrorSnackbar('Addresses must start with https:// (or http:// on a local network).');
      return null;
    }
    c.text = url;
    return url;
  }

  Future<bool> _save(void Function(StoreSettings s) change, String log) async {
    setState(() => _saving = true);
    try {
      await ref.read(storeSettingsProvider.notifier).edit(change,
          user: ref.read(currentUserProvider), logDetails: log);
      return true;
    } catch (e) {
      if (mounted) context.showErrorSnackbar(errorMessage(e));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePayment() async {
    final url = _cleanUrl(_payUrl);
    if (url == null) return;
    final ok = await _save(
      (s) => s
        ..backendUrl = url
        ..syncApiKey = _payKey.text.trim(),
      'Payment server → ${url.isEmpty ? '(none)' : url}',
    );
    if (!ok || !mounted) return;
    if (url.isEmpty) {
      setState(() => _payOk = null);
      return;
    }
    setState(() {
      _payOk = null;
      _payError = null;
    });
    final reachable = await ref.read(paystackServiceProvider).testConnection();
    if (!mounted) return;
    setState(() {
      _payOk = reachable;
      _payError = reachable ? null : 'Could not reach the payment server at that address.';
    });
  }

  Future<void> _saveSync() async {
    final url = _cleanUrl(_syncUrl);
    if (url == null) return;
    final key = _syncKey.text.trim();
    if (url.isNotEmpty && key.isEmpty) {
      setState(() => _syncError = 'Enter the sync server\'s key.');
      return;
    }
    setState(() {
      _syncOk = null;
      _syncError = null;
    });
    // Check it before saving, so the payment server can't be saved as the
    // sync server by mistake.
    if (url.isNotEmpty) {
      final problem = await SyncService.testServer(url, key);
      if (!mounted) return;
      if (problem != null) {
        setState(() {
          _syncOk = false;
          _syncError = problem;
        });
        return;
      }
    }
    final ok = await _save(
      (s) => s
        ..syncServerUrl = url
        ..syncServerKey = key,
      url.isEmpty ? 'Cloud sync turned off' : 'Sync server → $url',
    );
    if (!ok || !mounted) return;
    setState(() => _syncOk = url.isEmpty ? null : true);
    if (url.isNotEmpty) await _syncNow();
  }

  Future<void> _turnSyncOff() async {
    _syncUrl.clear();
    _syncKey.clear();
    await _saveSync();
    if (mounted) context.showSuccessSnackbar('Cloud sync turned off.');
  }

  Future<void> _syncNow() async {
    final result = await ref.read(syncProvider.notifier).syncNow();
    if (!mounted || result == null) return;
    if (result.ok) {
      context.showSuccessSnackbar('Synced: sent ${result.pushed} records, received ${result.pulled}.');
    } else {
      context.showErrorSnackbar(result.error!);
    }
  }

  Widget _keyField(TextEditingController c, String label, bool obscure, VoidCallback toggle) {
    return TextField(
      controller: c,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: toggle,
        ),
      ),
    );
  }

  Widget _status(bool? ok, String? error, String okText) {
    if (ok == null && error == null) return const SizedBox.shrink();
    final good = ok == true;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Icon(good ? Icons.check_circle_rounded : Icons.error_rounded,
              color: good ? AppColors.success : AppColors.danger, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(good ? okText : (error ?? 'Failed.'),
                style: TextStyle(color: good ? AppColors.success : AppColors.danger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(storeSettingsProvider);
    final sync = ref.watch(syncProvider);
    final syncOn = ref.watch(syncConfiguredProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(title: const Text('Integrations'), backgroundColor: AppColors.cardBg),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // ── Payment server ───────────────────────────────────────
            const SectionLabel('Payment server (Mobile Money)'),
            const Text(
              'Takes Mobile Money payments through Paystack. Enter its address and '
              'the API key it was started with.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _payUrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Payment server URL',
                hintText: 'https://pay.example.com/api',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _keyField(_payKey, 'Payment server API key', _obscurePayKey,
                () => setState(() => _obscurePayKey = !_obscurePayKey)),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton.icon(
              onPressed: _saving ? null : _savePayment,
              icon: const Icon(Icons.wifi_tethering_rounded),
              label: const Text('Save & Test'),
            ),
            _status(_payOk, _payError, 'Payment server reachable.'),
            if (settings.backendUrl.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text('Mobile Money is off until a payment server is saved.',
                    style: TextStyle(color: AppColors.warning)),
              ),
            const SizedBox(height: AppSpacing.md),
            TouchableCard(
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const PendingMomoScreen())),
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.pending_actions_rounded, color: AppColors.warning),
                title: Text('Pending MoMo payments'),
                subtitle: Text('Charges that timed out or were paid but not saved'),
                trailing: Icon(Icons.chevron_right_rounded),
              ),
            ),

            // ── Sync server ──────────────────────────────────────────
            const SectionLabel('Cloud sync server (optional)'),
            const Text(
              'Shares sales, stock and products between several tills and keeps a copy '
              'off this phone. This is a different server from the payment server. '
              'Leave it empty if you use only one till.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            TouchableCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(syncOn ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                          color: syncOn ? AppColors.success : AppColors.textMuted),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          !syncOn
                              ? 'Sync is off'
                              : settings.lastSyncAt == null
                                  ? 'Sync is on · not synced yet'
                                  : 'Last synced ${DateHelpers.formatDateTime(settings.lastSyncAt!.toLocal())}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (syncOn && sync.last != null && !sync.last!.ok)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Last attempt failed: ${sync.last!.error}',
                          style: const TextStyle(color: AppColors.danger)),
                    ),
                  if (syncOn) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Runs every 10 minutes while someone is signed in. '
                      'PINs and passwords never leave this phone.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _syncUrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Sync server URL',
                      hintText: 'https://sync.example.com/api',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _keyField(_syncKey, 'Sync server key', _obscureSyncKey,
                      () => setState(() => _obscureSyncKey = !_obscureSyncKey)),
                  _status(_syncOk, _syncError, 'Sync server connected.'),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving ? null : _saveSync,
                          child: const Text('Save & Test'),
                        ),
                      ),
                      if (syncOn) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: sync.running ? null : _syncNow,
                            icon: sync.running
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.sync_rounded),
                            label: Text(sync.running ? 'Syncing…' : 'Sync Now'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (syncOn)
                    TextButton(
                      onPressed: _saving ? null : _turnSyncOff,
                      child: const Text('Turn sync off',
                          style: TextStyle(color: AppColors.danger)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
