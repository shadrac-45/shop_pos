/// ============================================
/// Backup & Restore Screen — ShopPOS
/// ============================================
/// Owner-only: save the whole database to a file
/// kept off the phone, and restore from one.
/// ============================================
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/services/backup_service.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/core/utils/file_export.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final bytes = await BackupService.export(
          ref.read(isarProvider), ref.read(currentUserProvider));
      final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '');
      final saved = await FileExport.save(
        fileName: 'shoppos-backup-$stamp.json',
        bytes: bytes,
        mimeType: 'application/json',
        dialogTitle: 'Save backup',
        allowedExtensions: ['json'],
      );
      ref.invalidate(storeSettingsProvider);
      if (mounted && saved != null) context.showSuccessSnackbar('Backup saved.');
    } catch (e) {
      if (mounted) context.showErrorSnackbar('Backup failed: ${errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty || files.single.path == null) return;

    final Uint8List bytes;
    final Map<String, int> counts;
    try {
      bytes = await File(files.single.path!).readAsBytes();
      counts = BackupService.inspect(bytes);
    } catch (e) {
      if (mounted) context.showErrorSnackbar(errorMessage(e));
      return;
    }
    if (!mounted) return;

    final ok = await confirmDialog(
      context,
      title: 'Replace ALL data?',
      message: 'Everything on this device (products, stock, sales, staff, '
          'settings) will be replaced by the backup:\n\n'
          '${counts.entries.where((e) => e.value > 0).map((e) => '• ${e.key}: ${e.value}').join('\n')}'
          '\n\nYou will be signed out afterwards. This cannot be undone, so '
          'save a backup of the current data first if you might need it.',
      confirmLabel: 'Restore',
      destructive: true,
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      await BackupService.restore(
          ref.read(isarProvider), ref.read(currentUserProvider), bytes);
      ref.invalidate(storeSettingsProvider);
      if (!mounted) return;
      context.showSuccessSnackbar('Data restored. Please sign in again.');
      // Accounts may have changed; ShopPOSApp returns to the role picker.
      ref.read(currentUserProvider.notifier).logout();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        context.showErrorSnackbar('Restore failed: ${errorMessage(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = ref.watch(storeSettingsProvider).lastBackupAt;
    final stale = last == null || DateTime.now().difference(last).inDays >= 7;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(title: const Text('Backup & Restore'), backgroundColor: AppColors.cardBg),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            TouchableCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Icon(stale ? Icons.warning_amber_rounded : Icons.verified_rounded,
                      color: stale ? AppColors.warning : AppColors.success),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      last == null
                          ? 'No backup made yet. If this phone is lost or reset, all data is lost.'
                          : 'Last backup: ${DateHelpers.formatDateTime(last)}',
                    ),
                  ),
                ],
              ),
            ),
            const SectionLabel('Backup'),
            const Text(
              'Saves everything to one file. Keep it somewhere other than this phone: '
              'Google Drive, email it to yourself, or copy it to a computer. '
              'The file contains staff PIN hashes, so keep it private.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Save Backup File'),
            ),
            const SectionLabel('Restore'),
            const Text(
              'Replaces all data on this device with a backup file, for example '
              'when moving to a new phone.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Restore From File'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            ),
            if (_busy) ...[
              const SizedBox(height: AppSpacing.lg),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}
