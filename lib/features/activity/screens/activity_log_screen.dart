/// ============================================
/// Activity Log Screen — ShopPOS
/// ============================================
/// What staff did and when: sign-ins, sales,
/// voids, refunds, stock and settings changes.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/reports/services/report_range.dart';
import 'package:shop_pos/features/shared/widgets/app_empty_state.dart';

class ActivityLogScreen extends ConsumerStatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  ConsumerState<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen> {
  ReportRange _range = ReportRange.of(ReportPeriod.today);
  int? _userId;
  List<AppUser> _users = [];
  List<ActivityLog>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final isar = ref.read(isarProvider);
    final users = await isar.appUsers.where().findAll();
    final entries = await ActivityLogService.query(isar,
        from: _range.start, to: _range.endInclusive, userId: _userId);
    if (mounted) {
      setState(() {
        _users = users;
        _entries = entries;
      });
    }
  }

  static IconData _icon(String action) => switch (action) {
        ActivityAction.login || ActivityAction.logout || ActivityAction.sessionTimeout =>
          Icons.login_rounded,
        ActivityAction.loginFailed => Icons.gpp_bad_rounded,
        ActivityAction.sale => Icons.point_of_sale_rounded,
        ActivityAction.voidSale || ActivityAction.refund => Icons.undo_rounded,
        ActivityAction.restock || ActivityAction.stockAdjustment => Icons.inventory_rounded,
        ActivityAction.expense => Icons.receipt_rounded,
        ActivityAction.shiftOpened || ActivityAction.shiftClosed => Icons.lock_clock_rounded,
        _ => Icons.settings_rounded,
      };

  static Color _color(String action) => switch (action) {
        ActivityAction.loginFailed ||
        ActivityAction.voidSale ||
        ActivityAction.refund =>
          AppColors.danger,
        ActivityAction.stockAdjustment || ActivityAction.expense => AppColors.warning,
        ActivityAction.sale => AppColors.success,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(title: const Text('Activity Log'), backgroundColor: AppColors.cardBg),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<ReportPeriod>(
                      initialValue: _range.period,
                      decoration: const InputDecoration(labelText: 'Period', isDense: true),
                      items: [
                        for (final p in [
                          ReportPeriod.today,
                          ReportPeriod.yesterday,
                          ReportPeriod.last7Days,
                          ReportPeriod.thisMonth,
                        ])
                          DropdownMenuItem(value: p, child: Text(ReportRange.of(p).label)),
                      ],
                      onChanged: (p) {
                        if (p == null) return;
                        setState(() => _range = ReportRange.of(p));
                        _load();
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _userId,
                      decoration: const InputDecoration(labelText: 'Staff', isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Everyone')),
                        for (final u in _users)
                          DropdownMenuItem(value: u.id, child: Text(u.name)),
                      ],
                      onChanged: (v) {
                        setState(() => _userId = v);
                        _load();
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: entries == null
                  ? const Center(child: CircularProgressIndicator())
                  : entries.isEmpty
                      ? const AppEmptyState(
                          icon: Icons.history_toggle_off_rounded,
                          title: 'No activity',
                          description: 'Nothing was recorded for this period.',
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final e = entries[i];
                              return ListTile(
                                leading: Icon(_icon(e.action), color: _color(e.action)),
                                title: Text(
                                    '${ActivityAction.label(e.action)}'
                                    '${e.details.isEmpty ? '' : ' — ${e.details}'}'),
                                subtitle: Text(
                                    '${e.userName} · ${DateHelpers.formatDateTime(e.timestamp)}'),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
