/// ============================================
/// Expenses Screen — ShopPOS
/// ============================================
/// Record and review money spent: supplier
/// payments, transport, utilities, wages, and
/// cash paid out of the till.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/core/utils/date_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/expenses/models/expense.dart';
import 'package:shop_pos/features/expenses/services/expense_service.dart';
import 'package:shop_pos/features/reports/providers/report_provider.dart';
import 'package:shop_pos/features/reports/services/report_range.dart';
import 'package:shop_pos/features/shared/widgets/app_empty_state.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  ReportRange _range = ReportRange.of(ReportPeriod.thisMonth);
  List<Expense>? _expenses;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ExpenseService.inRange(
        ref.read(isarProvider), _range.start, _range.endInclusive);
    if (mounted) setState(() => _expenses = list);
  }

  Future<void> _add() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddExpenseDialog(),
    );
    if (added == true) {
      await _load();
      ref.read(reportProvider.notifier).refresh();
    }
  }

  Future<void> _delete(Expense e) async {
    final ok = await confirmDialog(context,
        title: 'Delete expense?',
        message: '${ExpenseCategory.label(e.category)} ${CurrencyHelpers.format(e.amount)}'
            '${e.description.isEmpty ? '' : ' — ${e.description}'}',
        confirmLabel: 'Delete',
        destructive: true);
    if (!ok) return;
    try {
      await ExpenseService.delete(ref.read(isarProvider), ref.read(currentUserProvider), e);
      await _load();
      ref.read(reportProvider.notifier).refresh();
    } catch (err) {
      if (mounted) context.showErrorSnackbar(errorMessage(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final expenses = _expenses;
    final total = expenses?.fold<double>(0, (s, e) => s + e.amount) ?? 0;
    final byCategory = <String, double>{};
    for (final e in expenses ?? const <Expense>[]) {
      byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(title: const Text('Expenses'), backgroundColor: AppColors.cardBg),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Expense'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final p in [
                  ReportPeriod.today,
                  ReportPeriod.thisWeek,
                  ReportPeriod.thisMonth,
                  ReportPeriod.lastMonth,
                ])
                  ChoiceChip(
                    label: Text(ReportRange.of(p).label),
                    selected: _range.period == p,
                    onSelected: (_) {
                      setState(() => _range = ReportRange.of(p));
                      _load();
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Total: ${CurrencyHelpers.format(total)}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            if (byCategory.isNotEmpty)
              Text(
                byCategory.entries
                    .map((e) => '${ExpenseCategory.label(e.key)} ${CurrencyHelpers.format(e.value)}')
                    .join(' · '),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            const SizedBox(height: AppSpacing.md),
            if (expenses == null)
              const Center(child: CircularProgressIndicator())
            else if (expenses.isEmpty)
              const AppEmptyState(
                icon: Icons.receipt_outlined,
                title: 'No expenses recorded',
                description: 'Record money spent so reports can show your real profit.',
              )
            else
              for (final e in expenses)
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ListTile(
                    leading: Icon(
                      e.paidFromTill ? Icons.point_of_sale_rounded : Icons.receipt_rounded,
                      color: e.paidFromTill ? AppColors.warning : AppColors.textSecondary,
                    ),
                    title: Text(e.description.isEmpty
                        ? ExpenseCategory.label(e.category)
                        : e.description),
                    subtitle: Text('${ExpenseCategory.label(e.category)} · '
                        '${DateHelpers.formatDateTime(e.timestamp)}'
                        '${e.paidFromTill ? ' · from till' : ''}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(CurrencyHelpers.format(e.amount),
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                          onPressed: () => _delete(e),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _AddExpenseDialog extends ConsumerStatefulWidget {
  const _AddExpenseDialog();

  @override
  ConsumerState<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends ConsumerState<_AddExpenseDialog> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = ExpenseCategory.stock;
  bool _fromTill = false;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseMoney(_amountCtrl.text);
    if (amount <= 0) {
      setState(() => _error = 'Enter an amount.');
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      await ExpenseService.add(
        ref.read(isarProvider),
        ref.read(currentUserProvider),
        amount: amount,
        category: _category,
        description: _descCtrl.text,
        paidFromTill: _fromTill,
        at: DateHelpers.isSameDay(_date, now)
            ? now
            : DateTime(_date.year, _date.month, _date.day, 12),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Expense'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MoneyField(controller: _amountCtrl, label: 'Amount', autofocus: true),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in ExpenseCategory.all)
                  DropdownMenuItem(value: c, child: Text(ExpenseCategory.label(c))),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_rounded),
              title: Text(DateHelpers.formatShort(_date)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _fromTill,
              onChanged: (v) => setState(() => _fromTill = v),
              title: const Text('Paid with cash from the till'),
              subtitle: const Text('Deducted from expected cash at shift close'),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
