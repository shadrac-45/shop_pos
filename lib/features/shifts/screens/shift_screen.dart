/// ============================================
/// Shift Screen — ShopPOS
/// ============================================
/// Open a till shift with a cash float, see the
/// running cash position, and close it with an
/// end-of-day cash count (expected vs counted).
/// Owners and managers also see recent shifts
/// from every staff member.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/shared/widgets/touchable_card.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';
import 'package:shop_pos/features/shifts/models/shift.dart';
import 'package:shop_pos/features/shifts/providers/shift_provider.dart';
import 'package:shop_pos/features/shifts/services/shift_service.dart';

class ShiftScreen extends ConsumerStatefulWidget {
  const ShiftScreen({super.key});

  @override
  ConsumerState<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends ConsumerState<ShiftScreen> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _busy = false;
  ShiftSummary? _summary;
  int? _summaryFor;
  List<Shift> _history = [];
  Map<int, String> _names = {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final isar = ref.read(isarProvider);
    final user = ref.read(currentUserProvider);
    final seeAll = Permissions.can(user, Permission.viewReports);
    final shifts = await ShiftService.recentShifts(isar, userId: seeAll ? null : user?.id);
    final users = await isar.appUsers.where().findAll();
    if (!mounted) return;
    setState(() {
      _history = shifts;
      _names = {for (final u in users) u.id: u.name};
    });
  }

  Future<void> _loadSummary(Shift shift) async {
    final summary = await ShiftService.summarize(ref.read(isarProvider), shift);
    if (mounted) {
      setState(() {
        _summary = summary;
        _summaryFor = shift.id;
      });
    }
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      await ShiftService.openShift(ref.read(isarProvider), ref.read(currentUserProvider),
          openingFloat: parseMoney(_amountCtrl.text));
      _amountCtrl.clear();
      if (mounted) context.showSuccessSnackbar('Shift opened.');
      await _loadHistory();
    } catch (e) {
      if (mounted) context.showErrorSnackbar(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close(Shift shift) async {
    if (_amountCtrl.text.trim().isEmpty) {
      context.showErrorSnackbar('Count the cash in the till and enter the total.');
      return;
    }
    final counted = parseMoney(_amountCtrl.text);
    final expected = _summary?.expectedCash ?? 0;
    final ok = await confirmDialog(
      context,
      title: 'Close shift?',
      message: 'Expected ${CurrencyHelpers.format(expected)}, counted '
          '${CurrencyHelpers.format(counted)} '
          '(${_varianceText(counted - expected)}).',
      confirmLabel: 'Close Shift',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final closed = await ShiftService.closeShift(
        ref.read(isarProvider),
        ref.read(currentUserProvider),
        shift: shift,
        countedCash: counted,
        note: _noteCtrl.text,
      );
      _amountCtrl.clear();
      _noteCtrl.clear();
      if (mounted) {
        context.showSuccessSnackbar(
            'Shift closed. ${_varianceText(closed.variance ?? 0)}.');
      }
      await _loadHistory();
    } catch (e) {
      if (mounted) context.showErrorSnackbar(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _varianceText(double v) => v.abs() < 0.005
      ? 'cash balances'
      : v > 0
          ? 'over by ${CurrencyHelpers.format(v)}'
          : 'short by ${CurrencyHelpers.format(-v)}';

  @override
  Widget build(BuildContext context) {
    final shiftAsync = ref.watch(currentShiftProvider);
    final shift = shiftAsync.valueOrNull;
    if (shift != null && _summaryFor != shift.id) _loadSummary(shift);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(title: const Text('Shift & Cash-up'), backgroundColor: AppColors.cardBg),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            if (shift != null) await _loadSummary(shift);
            await _loadHistory();
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (shiftAsync.isLoading)
                const Center(child: CircularProgressIndicator())
              else if (shift == null)
                _buildOpenCard()
              else
                _buildCloseCard(shift),
              const SectionLabel('Recent shifts'),
              if (_history.isEmpty)
                const Text('No shifts yet.', style: TextStyle(color: AppColors.textSecondary)),
              for (final s in _history) _buildHistoryTile(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOpenCard() {
    return TouchableCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('No shift open',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Count the cash in the till before you start selling and enter it as the opening float.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          MoneyField(controller: _amountCtrl, label: 'Opening float'),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton.icon(
            onPressed: _busy ? null : _open,
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Open Shift'),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseCard(Shift shift) {
    final s = _summary;
    Widget row(String label, double amount, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
              Text(CurrencyHelpers.format(amount),
                  style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
            ],
          ),
        );

    return TouchableCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Shift open since ${DateHelpers.formatDateTime(shift.openedAt)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.md),
          if (s == null)
            const LinearProgressIndicator()
          else ...[
            row('Opening float', s.openingFloat),
            row('+ Cash sales (${s.saleCount} sales)', s.cashSales),
            row('− Cash refunds', s.cashRefunds),
            row('− Paid out of till', s.tillPayouts),
            const Divider(),
            row('Expected in till', s.expectedCash, bold: true),
          ],
          const SizedBox(height: AppSpacing.lg),
          MoneyField(
            controller: _amountCtrl,
            label: 'Cash counted in till',
            onChanged: (_) => setState(() {}),
          ),
          if (s != null && _amountCtrl.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Builder(builder: (_) {
                final v = parseMoney(_amountCtrl.text) - s.expectedCash;
                return Text(
                  _varianceText(v),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: v.abs() < 0.005 ? AppColors.success : AppColors.danger,
                  ),
                );
              }),
            ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton.icon(
            onPressed: _busy ? null : () => _close(shift),
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Close Shift'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(Shift s) {
    final v = s.variance;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        title: Text('${_names[s.userId] ?? 'Staff'} · ${DateHelpers.formatDateTime(s.openedAt)}'),
        subtitle: Text(s.isOpen
            ? 'Open · float ${CurrencyHelpers.format(s.openingFloat)}'
            : 'Closed ${DateHelpers.formatTime(s.closedAt!)} · expected '
                '${CurrencyHelpers.format(s.expectedCash ?? 0)}, counted '
                '${CurrencyHelpers.format(s.countedCash ?? 0)}'
                '${s.closingNote != null ? '\n${s.closingNote}' : ''}'),
        trailing: v == null
            ? const StatusPill('open', color: AppColors.info)
            : StatusPill(
                v.abs() < 0.005 ? 'balanced' : (v > 0 ? 'over' : 'short'),
                color: v.abs() < 0.005 ? AppColors.success : AppColors.danger,
              ),
      ),
    );
  }
}
