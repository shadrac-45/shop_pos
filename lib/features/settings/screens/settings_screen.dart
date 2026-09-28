/// ============================================
/// Settings Screen — ShopPOS
/// ============================================
/// Clean, end-user facing screen for Cashiers and Owners.
/// Displays cashier profile, PIN management ("Change PIN"),
/// store preferences, app version, and cashier logout.
///
/// OWNER-ONLY: "Manage Staff" section for creating / managing
/// cashier accounts is only shown when role == "owner".
///
/// GATING: Developer/Debug configuration is hidden from normal view.
/// In DEBUG builds: tapping the "ShopPOS Version" tile 5 times triggers
/// Developer Mode. In RELEASE builds: the tap counter is disabled.
/// ============================================
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/auth/screens/login_screen.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';
import 'package:shop_pos/features/settings/widgets/change_pin_dialog.dart';
import 'package:shop_pos/features/settings/screens/developer_debug_screen.dart';
import 'package:shop_pos/features/settings/screens/manage_staff_screen.dart';
import 'package:shop_pos/features/products/widgets/csv_import_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _devTapCount = 0;
  DateTime? _lastTapTime;

  void _onVersionTileTapped() {
    if (!kDebugMode) return;

    final now = DateTime.now();
    if (_lastTapTime == null || now.difference(_lastTapTime!).inSeconds > 2) {
      _devTapCount = 1;
    } else {
      _devTapCount++;
    }
    _lastTapTime = now;

    HapticFeedback.lightImpact();

    if (_devTapCount >= 3 && _devTapCount < 5) {
      context.showSuccessSnackbar('Tap ${5 - _devTapCount} more time(s) to open Developer Options.');
    } else if (_devTapCount >= 5) {
      _devTapCount = 0;
      HapticFeedback.mediumImpact();
      context.showSuccessSnackbar('Developer Mode Unlocked!');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DeveloperDebugScreen()),
      );
    }
  }

  Future<void> _openChangePinDialog() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangePinDialog(user: user),
    );

    if (result == true && mounted) {
      context.showSuccessSnackbar('Your PIN has been updated successfully!');
    }
  }

  void _openCsvImportDialog() {
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CsvImportDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isOwner = user?.role == 'owner';

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Settings & Profile'),
        backgroundColor: AppColors.cardBg,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // ── User Profile Card ─────────────────────────────
            TouchableCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (user?.name ?? 'U')[0].toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'Store Cashier',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: AppSpacing.borderSm,
                          ),
                          child: Text(
                            (user?.role ?? 'cashier').toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Security & Account Section (For ALL staff) ────
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'SECURITY & ACCOUNT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TouchableCard(
              onTap: _openChangePinDialog,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.pin_rounded, color: AppColors.primary),
                title: Text('Change My PIN'),
                subtitle: Text(
                  'Replace assigned PIN with a personal 4-digit PIN',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
              ),
            ),

            // ── Owner-only: Manage Staff ──────────────────────
            if (isOwner) ...[
              const SizedBox(height: AppSpacing.xl),
              const Text(
                'STAFF MANAGEMENT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TouchableCard(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManageStaffScreen()),
                ),
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.manage_accounts_rounded, color: AppColors.primary),
                  title: Text('Manage Staff'),
                  subtitle: Text(
                    'Create, deactivate & manage cashier accounts',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),
              const Text(
                'INVENTORY & DATA',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TouchableCard(
                onTap: _openCsvImportDialog,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.file_upload_outlined, color: AppColors.primary),
                  title: Text('Import Products (CSV)'),
                  subtitle: Text(
                    'Bulk import catalog & stock quantities from CSV or text',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),
            const Text(
              'STORE PREFERENCES',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            const TouchableCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.payments_rounded, color: AppColors.primary),
                    title: Text('Store Currency'),
                    subtitle: Text('${AppConstants.currencySymbol} (${AppConstants.currencyCode})', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ),
                  Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.touch_app_rounded, color: AppColors.info),
                    title: Text('Interface Mode'),
                    subtitle: Text('Touch-First Shop Floor POS', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            const Text(
              'ABOUT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            TouchableCard(
              child: Column(
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.store_rounded, color: AppColors.primary),
                    title: Text('Application'),
                    subtitle: Text('ShopPOS Offline-First Point of Sale', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ),
                  const Divider(),

                  InkWell(
                    onTap: _onVersionTileTapped,
                    borderRadius: AppSpacing.borderMd,
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.info_outline_rounded, color: AppColors.textSecondary),
                      title: Text('ShopPOS Version'),
                      subtitle: Text('v1.2.0 (Build 2026.07)', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Logout Button
            ElevatedButton.icon(
              onPressed: () {
                ref.read(currentUserProvider.notifier).logout();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign Out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
