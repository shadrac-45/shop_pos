/// ============================================
/// Integrations Screen — ShopPOS
/// ============================================
/// Owner-only: connect the app to the ShopPOS
/// backend (backend/ in this repo) for Mobile
/// Money and cloud sync, test the connection,
/// and sync now.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/providers/sync_provider.dart';
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
  late final _url = TextEditingController(text: ref.read(storeSettingsProvider).backendUrl);
  late final _key = TextEditingController(text: ref.read(storeSettingsProvider).syncApiKey);
  bool _obscureKey = true;
  bool _saving = false;
  bool? _connectionOk;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<bool> _save() async {
    final url = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isNotEmpty && !RegExp(r'^https?://').hasMatch(url)) {
      context.showErrorSnackbar('The URL must start with https:// (or http:// on a local network).');
      return false;
    }
    setState(() => _saving = true);
    try {
      await ref.read(storeSettingsProvider.notifier).edit(
            (s) => s
              ..backendUrl = url
              ..syncApiKey = _key.text.trim(),
            user: ref.read(currentUserProvider),
            logDetails: 'Backend → ${url.isEmpty ? '(none)' : url}',
          );
      _url.text = url;
      return true;
    } catch (e) {
      if (mounted) context.showErrorSnackbar(errorMessage(e));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAndTest() async {
    if (!await _save()) return;
    setState(() => _connectionOk = null);
    final ok = await ref.read(paystackServiceProvider).testConnection();
    if (!mounted) return;
    setState(() => _connectionOk = ok);
    ok
        ? context.showSuccessSnackbar('Connected to the backend.')
        : context.showErrorSnackbar('Could not reach the backend at that URL.');
  }

  Future<void> _syncNow() async {
    final result = await ref.read(syncProvider.notifier).syncNow();
    if (!mounted) return;
    if (result == null) {
      context.showErrorSnackbar('Enter and save the backend URL and sync key first.');
    } else if (result.ok) {
      context.showSuccessSnackbar(
          'Synced: sent ${result.pushed} records, received ${result.pulled}.');
    } else {
      context.showErrorSnackbar(result.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(storeSettingsProvider);
    final sync = ref.watch(syncProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(title: const Text('Integrations'), backgroundColor: AppColors.cardBg),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text(
              'Mobile Money and cloud sync go through the ShopPOS backend '
              '(the backend/ folder of this project), run on a server you control. '
              'Enter its address and the API key it was started with.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SectionLabel('Backend'),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Backend URL',
                hintText: 'https://pos.example.com/api',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _key,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'API key',
                suffixIcon: IconButton(
                  icon: Icon(_obscureKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveAndTest,
                    icon: const Icon(Icons.wifi_tethering_rounded),
                    label: const Text('Save & Test'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                if (_connectionOk != null)
                  Icon(
                    _connectionOk! ? Icons.check_circle_rounded : Icons.error_rounded,
                    color: _connectionOk! ? AppColors.success : AppColors.danger,
                  ),
              ],
            ),

            const SectionLabel('Cloud sync'),
            TouchableCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    settings.lastSyncAt == null
                        ? 'Never synced'
                        : 'Last synced ${DateHelpers.formatDateTime(settings.lastSyncAt!.toLocal())}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (sync.last != null && !sync.last!.ok)
                    Text('Last attempt failed: ${sync.last!.error}',
                        style: const TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 4),
                  const Text(
                    'Sales, stock changes, expenses, shifts and products are uploaded '
                    'automatically every 10 minutes while someone is signed in. '
                    'Product and price changes made on other devices are downloaded. '
                    'PINs and passwords never leave this device.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: sync.running ? null : _syncNow,
                    icon: sync.running
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync_rounded),
                    label: Text(sync.running ? 'Syncing…' : 'Sync Now'),
                  ),
                ],
              ),
            ),

            const SectionLabel('Mobile Money'),
            TouchableCard(
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PendingMomoScreen())),
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.pending_actions_rounded, color: AppColors.warning),
                title: Text('Pending MoMo payments'),
                subtitle: Text('Charges that timed out or were paid but not saved'),
                trailing: Icon(Icons.chevron_right_rounded),
              ),
            ),
            if (settings.backendUrl.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'Mobile Money is off until a backend URL is saved.',
                  style: TextStyle(color: AppColors.warning),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
