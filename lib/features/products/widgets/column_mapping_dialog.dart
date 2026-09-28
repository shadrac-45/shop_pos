/// ============================================
/// Column Mapping Dialog — ShopPOS
/// ============================================
/// Shown when the import parser cannot tell which column holds the
/// product name. Guessing is what made category text appear in the
/// Name column, so the owner picks the columns instead.
///
/// Each field is assigned to at most one column, and a column can only
/// back one field, which the dialog enforces as the selection changes.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/products/services/product_import_parser.dart';

/// The fields the owner can map, in display order.
enum MappableField { name, price, stock, category, barcode, cost }

extension MappableFieldLabel on MappableField {
  String get label {
    switch (this) {
      case MappableField.name:
        return 'Name';
      case MappableField.price:
        return 'Price';
      case MappableField.stock:
        return 'Qty';
      case MappableField.category:
        return 'Category';
      case MappableField.barcode:
        return 'Barcode';
      case MappableField.cost:
        return 'Cost';
    }
  }

  /// Only Name is mandatory; everything else may be left unmapped.
  bool get required => this == MappableField.name;
}

class ColumnMappingDialog extends StatefulWidget {
  final List<String> headerLabels;
  final List<List<String>> sampleRows;
  final ColumnMapping? initial;

  const ColumnMappingDialog({
    super.key,
    required this.headerLabels,
    this.sampleRows = const [],
    this.initial,
  });

  /// Returns the confirmed mapping, or null if the owner cancelled.
  static Future<ColumnMapping?> show(
    BuildContext context, {
    required List<String> headerLabels,
    List<List<String>> sampleRows = const [],
    ColumnMapping? initial,
  }) {
    return showDialog<ColumnMapping>(
      context: context,
      builder: (_) => ColumnMappingDialog(
        headerLabels: headerLabels,
        sampleRows: sampleRows,
        initial: initial,
      ),
    );
  }

  @override
  State<ColumnMappingDialog> createState() => _ColumnMappingDialogState();
}

class _ColumnMappingDialogState extends State<ColumnMappingDialog> {
  late final Map<MappableField, int?> _selection = {
    MappableField.name: widget.initial?.name,
    MappableField.price: widget.initial?.price,
    MappableField.stock: widget.initial?.stock,
    MappableField.category: widget.initial?.category,
    MappableField.barcode: widget.initial?.barcode,
    MappableField.cost: widget.initial?.cost,
  };

  bool get _nameChosen => _selection[MappableField.name] != null;

  /// Assigns [column] to [field], releasing it from whichever other field
  /// held it so no column ever backs two fields at once.
  void _assign(MappableField field, int? column) {
    setState(() {
      if (column == null) {
        _selection[field] = null;
        return;
      }
      for (final entry in _selection.entries.toList()) {
        if (entry.key != field && entry.value == column) {
          _selection[entry.key] = null;
        }
      }
      _selection[field] = column;
    });
  }

  /// True when [column] is already claimed by a different field, so the
  /// dropdown can show it as unavailable instead of silently stealing it.
  bool _takenBy(MappableField field, int column) {
    for (final entry in _selection.entries) {
      if (entry.key != field && entry.value == column) return true;
    }
    return false;
  }

  void _submit() {
    final mapping = ColumnMapping(
      name: _selection[MappableField.name] ?? -1,
      price: _selection[MappableField.price] ?? -1,
      stock: _selection[MappableField.stock] ?? -1,
      category: _selection[MappableField.category] ?? -1,
      barcode: _selection[MappableField.barcode] ?? -1,
      cost: _selection[MappableField.cost] ?? -1,
      // The first row is a header whenever it was identified as one.
      skipHeader: widget.initial?.skipHeader ?? true,
      detected: false,
    );
    Navigator.of(context).pop(mapping);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;

    return AlertDialog(
      title: const Text('Match your columns'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'We could not tell which column holds the product name. '
                'Choose the right column for each field below.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final field in MappableField.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          field.required ? '${field.label} *' : field.label,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: field.required
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _selection[field],
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          hint: Text(field.required
                              ? 'Choose a column'
                              : 'Not mapped'),
                          items: [
                            if (!field.required)
                              const DropdownMenuItem<int>(
                                value: null,
                                child: Text('— none —'),
                              ),
                            for (var i = 0; i < widget.headerLabels.length; i++)
                              if (!_takenBy(field, i) || _selection[field] == i)
                                DropdownMenuItem<int>(
                                  value: i,
                                  child: Text(
                                    widget.headerLabels[i],
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _takenBy(field, i)
                                          ? cs.onSurfaceVariant
                                          : null,
                                    ),
                                  ),
                                ),
                          ],
                          onChanged: (v) => _assign(field, v),
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.sampleRows.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'First rows of your file',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final row in widget.sampleRows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      row.join('  |  '),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _nameChosen ? _submit : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
