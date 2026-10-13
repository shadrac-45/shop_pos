/// ============================================
/// Settings Screen — ShopPOS
/// ============================================
/// Hub for account, till, management and store
/// settings. Each section appears only for roles
/// allowed to use it (see Permissions).
///
/// GATING: Developer/Debug configuration is hidden from normal view.
/// In DEBUG builds: tapping the "ShopPOS Version" tile 5 times triggers
/// Developer Mode. In RELEASE builds: the tap counter is disabled.
/// ============================================
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shop_pos/features/cloud/screens/cloud_dashboard_screen.dart';
import 'package:shop_pos/features/customers/screens/customers_screen.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/activity/screens/activity_log_screen.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/auth/services/admin_auth_service.dart';
import 'package:shop_pos/features/expenses/screens/expenses_screen.dart';
import 'package:shop_pos/features/products/widgets/csv_import_dialog.dart';
import 'package:shop_pos/features/settings/screens/backup_screen.dart';
import 'package:shop_pos/features/settings/screens/developer_debug_screen.dart';
import 'package:shop_pos/features/settings/screens/integrations_screen.dart';
import 'package:shop_pos/features/settings/screens/manage_staff_screen.dart';
import 'package:shop_pos/features/settings/screens/pending_momo_screen.dart';
import 'package:shop_pos/features/settings/screens/printer_setup_screen.dart';
import 'package:shop_pos/features/settings/screens/store_settings_screen.dart';
import 'package:shop_pos/features/settings/widgets/change_pin_dialog.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';
import 'package:shop_pos/features/shifts/screens/shift_screen.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';
import 'package:shop_pos/features/shared/widgets/sign_out_button.dart';

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
      _open(const DeveloperDebugScreen());
    }
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  Future<void> _openChangePinDialog() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final result = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangePinDialog(user: user),
    );

    if (result == true && mounted) {
      context.showSuccessSnackbar('Your PIN has been updated successfully!');
    }
  }

  Future<void> _openChangePasswordDialog() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    String? error;

    final changed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Change Admin Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: current,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Current password')),
              TextField(
                  controller: next,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText:
                          'New password (${AdminAuthService.minPasswordLength}+ characters)')),
              TextField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm new password')),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(error!, style: const TextStyle(color: AppColors.danger)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (next.text != confirm.text) {
                  setDialogState(() => error = 'The new passwords do not match.');
                  return;
                }
                try {
                  final ok = await AdminAuthService.changePassword(
                    ref.read(isarProvider),
                    user,
                    currentPassword: current.text,
                    newPassword: next.text,
                  );
                  if (!ok) {
                    setDialogState(() => error = 'Current password is incorrect.');
                    return;
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  setDialogState(() => error = errorMessage(e));
                }
              },
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
    current.dispose();
    next.dispose();
    confirm.dispose();
    if (changed == true && mounted) context.showSuccessSnackbar('Password changed.');
  }

  void _openCsvImportDialog() {
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CsvImportDialog(),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color color = AppColors.primary,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TouchableCard(
        onTap: onTap,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: color),
          title: Text(title),
          subtitle: Text(subtitle,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final store = ref.watch(storeSettingsProvider);
    bool can(Permission p) => Permissions.can(user, p);

    // A tab of the main shell, which already shows the "Settings" title:
    // no app bar of its own, and the shell's canvas shows through.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: _sidePadding(MediaQuery.sizeOf(context).width),
            vertical: AppSpacing.sm,
          ),
          children: [
            // ── User Profile Card ─────────────────────────────
            TouchableCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: LayoutBuilder(builder: (context, c) {
                final who = Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.primaryLight,
                      child: Text(
                        (user?.name.isNotEmpty ?? false) ? user!.name[0].toUpperCase() : 'U',
                        style: const TextStyle(
                            color: AppColors.primaryDark, fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.name ?? 'Staff', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 4),
                          StatusPill(
                            AppConstants.roleLabel(user?.role ?? AppConstants.roleCashier),
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                // Compact, beside who is signed in; no full-width red slab.
                // Phones: below it, so the name keeps the card's width.
                if (c.maxWidth < 300) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [who, const SizedBox(height: AppSpacing.md), const SignOutButton()],
                  );
                }
                return Row(children: [Expanded(child: who), const SignOutButton()]);
              }),
            ),

            // ── Account ───────────────────────────────────────
            const SectionLabel('Security & account'),
            _tile(
              icon: Icons.pin_rounded,
              title: 'Change My PIN',
              subtitle: 'Set a personal 4–6 digit PIN',
              onTap: _openChangePinDialog,
            ),
            if (user?.passwordHash != null)
              _tile(
                icon: Icons.password_rounded,
                title: 'Change Admin Password',
                subtitle: 'Used to sign in with email',
                onTap: _openChangePasswordDialog,
              ),

            // ── Till ──────────────────────────────────────────
            if (can(Permission.runShift)) ...[
              const SectionLabel('Till'),
              _tile(
                icon: Icons.lock_clock_rounded,
                title: 'Shift & Cash-up',
                subtitle: 'Open with a float, close with a cash count',
                onTap: () => _open(const ShiftScreen()),
              ),
            ],

            // ── Cloud (any shop the person manages, from anywhere) ────
            if (cloudDashboardAvailable(ref.watch(storeSettingsProvider), ref.watch(currentUserProvider))) ...[
              const SectionLabel('ShopPOS Cloud'),
              _tile(
                icon: Icons.dashboard_rounded,
                title: 'Cloud Dashboard',
                subtitle: 'Live sales, stock, payments, activity, tills and staff of your shops',
                onTap: () => _open(const CloudDashboardScreen()),
              ),
            ],
            if (can(Permission.sell))
              _tile(
                icon: Icons.people_alt_rounded,
                title: 'Customers',
                subtitle: "Shared with the shop's other tills",
                onTap: () => _open(const CustomersScreen()),
              ),

            // ── Management ────────────────────────────────────
            if (can(Permission.manageExpenses) ||
                can(Permission.viewActivityLog) ||
                can(Permission.manageStaff)) ...[
              const SectionLabel('Management'),
              if (can(Permission.manageExpenses))
                _tile(
                  icon: Icons.receipt_rounded,
                  title: 'Expenses',
                  subtitle: 'Record spending and cash paid out of the till',
                  onTap: () => _open(const ExpensesScreen()),
                ),
              if (can(Permission.viewActivityLog))
                _tile(
                  icon: Icons.history_rounded,
                  title: 'Activity Log',
                  subtitle: 'Sign-ins, sales, voids, refunds and stock changes',
                  onTap: () => _open(const ActivityLogScreen()),
                ),
              if (can(Permission.manageStaff))
                _tile(
                  icon: Icons.manage_accounts_rounded,
                  title: 'Manage Staff',
                  subtitle: 'Add staff, set roles, reset PINs, deactivate',
                  onTap: () => _open(const ManageStaffScreen()),
                ),
              if (can(Permission.voidAndRefund))
                _tile(
                  icon: Icons.pending_actions_rounded,
                  title: 'Pending MoMo Payments',
                  subtitle: 'Reconcile charges that timed out or were not saved',
                  color: AppColors.warning,
                  onTap: () => _open(const PendingMomoScreen()),
                ),
            ],

            if (can(Permission.manageProducts)) ...[
              const SectionLabel('Inventory'),
              _tile(
                icon: Icons.file_upload_outlined,
                title: 'Import Products (CSV / Excel)',
                subtitle: 'Bulk import catalog & stock quantities',
                onTap: _openCsvImportDialog,
              ),
            ],

            // ── Store (owner) ─────────────────────────────────
            if (can(Permission.manageSettings)) ...[
              const SectionLabel('Store'),
              _tile(
                icon: Icons.storefront_rounded,
                title: 'Store Settings',
                subtitle: 'Profile, currency, VAT, receipts, payment methods, hardware',
                onTap: () => _open(const StoreSettingsScreen()),
              ),
              _tile(
                icon: Icons.print_rounded,
                title: 'Receipt Printer',
                subtitle: store.printerName.isEmpty
                    ? 'Set up a Bluetooth printer and cash drawer'
                    : store.printerName,
                onTap: () => _open(const PrinterSetupScreen()),
              ),
              _tile(
                icon: Icons.cloud_sync_rounded,
                title: 'Integrations',
                subtitle: 'Mobile Money backend and cloud sync',
                onTap: () => _open(const IntegrationsScreen()),
              ),
              _tile(
                icon: Icons.backup_rounded,
                title: 'Backup & Restore',
                subtitle: store.lastBackupAt == null
                    ? 'No backup yet — make one now'
                    : 'Save all data to a file, or restore from one',
                color: store.lastBackupAt == null ? AppColors.warning : AppColors.primary,
                onTap: () => _open(const BackupScreen()),
              ),
            ],

            // ── About ─────────────────────────────────────────
            const SectionLabel('About'),
            TouchableCard(
              child: InkWell(
                onTap: _onVersionTileTapped,
                borderRadius: AppSpacing.borderMd,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline_rounded, color: AppColors.textSecondary),
                  title: Text('ShopPOS Version'),
                  subtitle: Text('v${AppConstants.appVersion}',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// Keeps settings a readable column on wide screens.
double _sidePadding(double width) =>
    width > 1100 ? (width - 1100) / 2 + AppSpacing.xl : AppSpacing.lg;
