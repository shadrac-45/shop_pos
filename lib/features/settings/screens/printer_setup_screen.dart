/// ============================================
/// Printer Setup Screen — ShopPOS
/// ============================================
/// Choose a paired Bluetooth receipt printer,
/// its paper width, print a test page and test
/// the cash drawer.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/sales/services/bluetooth_printer_service.dart';
import 'package:shop_pos/features/sales/services/escpos.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';

class PrinterSetupScreen extends ConsumerStatefulWidget {
  const PrinterSetupScreen({super.key});

  @override
  ConsumerState<PrinterSetupScreen> createState() => _PrinterSetupScreenState();
}

class _PrinterSetupScreenState extends ConsumerState<PrinterSetupScreen> {
  List<PairedPrinter>? _printers;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _error = null;
      _printers = null;
    });
    try {
      final list = await BluetoothPrinterService.pairedPrinters();
      if (mounted) setState(() => _printers = list);
    } catch (e) {
      if (mounted) {
        setState(() {
          _printers = const [];
          _error = errorMessage(e);
        });
      }
    }
  }

  Future<void> _save(void Function(StoreSettings s) change, String log) async {
    try {
      await ref.read(storeSettingsProvider.notifier).edit(
            (s) => change(s),
            user: ref.read(currentUserProvider),
            logDetails: log,
          );
    } catch (e) {
      if (mounted) context.showErrorSnackbar(errorMessage(e));
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) context.showSuccessSnackbar(success);
    } catch (e) {
      if (mounted) context.showErrorSnackbar(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(storeSettingsProvider);
    final printers = _printers;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(title: const Text('Receipt Printer'), backgroundColor: AppColors.cardBg),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text(
              'Pair the printer first in Android Settings → Bluetooth, then choose it here. '
              'Works with ESC/POS thermal printers (most 58 mm and 80 mm Bluetooth printers). '
              'With no printer chosen, receipts print through the Android print dialog.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SectionLabel('Paired printers'),
            if (printers == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_error != null)
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              if (printers.isEmpty && _error == null)
                const Text('No paired Bluetooth devices found.'),
              for (final p in printers)
                Card(
                  child: ListTile(
                    leading: Icon(
                      s.printerAddress == p.address
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: AppColors.primary,
                    ),
                    title: Text(p.name.isEmpty ? p.address : p.name),
                    subtitle: Text(p.address),
                    onTap: () => _save((st) {
                      st.printerAddress = p.address;
                      st.printerName = p.name;
                      st.printerEnabled = true;
                    }, 'Printer → ${p.name}'),
                  ),
                ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _scan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                  const Spacer(),
                  if (s.printerAddress.isNotEmpty)
                    TextButton(
                      onPressed: () => _save((st) {
                        st.printerAddress = '';
                        st.printerName = '';
                      }, 'Bluetooth printer removed'),
                      child: const Text('Use print dialog instead',
                          style: TextStyle(color: AppColors.danger)),
                    ),
                ],
              ),
            ],
            const SectionLabel('Paper width'),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 58, label: Text('58 mm')),
                ButtonSegment(value: 80, label: Text('80 mm')),
              ],
              selected: {s.printerPaperMm},
              onSelectionChanged: (v) =>
                  _save((st) => st.printerPaperMm = v.first, 'Paper ${v.first} mm'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Print automatically after each sale'),
              value: s.printerEnabled,
              onChanged: (v) => _save((st) => st.printerEnabled = v,
                  'Auto-print ${v ? 'on' : 'off'}'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Open cash drawer on cash sales'),
              subtitle: const Text('For a drawer plugged into the printer\'s RJ11/DK port'),
              value: s.cashDrawerEnabled,
              onChanged: (v) => _save((st) => st.cashDrawerEnabled = v,
                  'Cash drawer ${v ? 'on' : 'off'}'),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy || s.printerAddress.isEmpty
                        ? null
                        : () => _run(
                              () => BluetoothPrinterService.send(
                                s.printerAddress,
                                EscPosReceipt.testPage(
                                    storeName: s.storeName, paperMm: s.printerPaperMm),
                              ),
                              'Test page sent.',
                            ),
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('Print Test'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || s.printerAddress.isEmpty
                        ? null
                        : () => _run(
                              () => BluetoothPrinterService.send(
                                s.printerAddress,
                                (EscPosBuilder()..openDrawer()).build(),
                              ),
                              'Drawer signal sent.',
                            ),
                    icon: const Icon(Icons.point_of_sale_rounded),
                    label: const Text('Open Drawer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
