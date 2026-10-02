/// ============================================
/// Stock Adjustment Dialog — ShopPOS
/// ============================================
/// Record stock leaving for a reason (damage,
/// loss, theft, expiry…), found stock, or a full
/// stock count that sets the quantity outright.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/stock_movement.dart';
import 'package:shop_pos/features/products/services/inventory_service.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';

enum _Mode { remove, add, count }

class StockAdjustDialog extends ConsumerStatefulWidget {
  final Product product;
  const StockAdjustDialog({super.key, required this.product});

  @override
  ConsumerState<StockAdjustDialog> createState() => _StockAdjustDialogState();
}

class _StockAdjustDialogState extends ConsumerState<StockAdjustDialog> {
  _Mode _mode = _Mode.remove;
  String _reason = AdjustmentReason.damage;
  final _qtyCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  int get _current => widget.product.totalStock.toInt();

  Future<void> _save() async {
    final qty = int.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty < 0 || (_mode != _Mode.count && qty == 0)) {
      setState(() => _error = 'Enter a whole number.');
      return;
    }
    if (_mode == _Mode.remove && qty > _current) {
      setState(() => _error = 'Only $_current in stock.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final isar = ref.read(isarProvider);
    final user = ref.read(currentUserProvider);
    try {
      switch (_mode) {
        case _Mode.remove:
          await InventoryService.adjust(isar, user,
              product: widget.product,
              quantityChange: -qty,
              reason: _reason,
              note: _noteCtrl.text.trim());
        case _Mode.add:
          await InventoryService.adjust(isar, user,
              product: widget.product,
              quantityChange: qty,
              reason: AdjustmentReason.other,
              note: _noteCtrl.text.trim().isEmpty ? 'Found stock' : _noteCtrl.text.trim());
        case _Mode.count:
          await InventoryService.setCountedStock(isar, user,
              product: widget.product,
              countedQuantity: qty,
              note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim());
      }
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      context.showSuccessSnackbar('Stock updated for ${widget.product.name}.');
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
      title: Text('Adjust stock — ${widget.product.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('In stock now: $_current',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.remove, label: Text('Remove')),
                ButtonSegment(value: _Mode.add, label: Text('Add')),
                ButtonSegment(value: _Mode.count, label: Text('Count')),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() {
                _mode = v.first;
                _error = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_mode == _Mode.remove)
              DropdownButtonFormField<String>(
                initialValue: _reason,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: [
                  for (final r in AdjustmentReason.all.where((r) => r != AdjustmentReason.countCorrection))
                    DropdownMenuItem(value: r, child: Text(AdjustmentReason.label(r))),
                ],
                onChanged: (v) => setState(() => _reason = v ?? _reason),
              ),
            TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: switch (_mode) {
                  _Mode.remove => 'Quantity to remove',
                  _Mode.add => 'Quantity found / returned',
                  _Mode.count => 'Quantity counted on the shelf',
                },
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_mode == _Mode.count && int.tryParse(_qtyCtrl.text.trim()) != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Difference: ${(int.parse(_qtyCtrl.text.trim()) - _current) >= 0 ? '+' : ''}'
                  '${int.parse(_qtyCtrl.text.trim()) - _current}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_mode == _Mode.remove)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Removed soonest-expiring first, including expired batches.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
