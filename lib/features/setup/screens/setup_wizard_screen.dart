/// ============================================
/// Setup Wizard Screen — ShopPOS
/// ============================================
/// First-run configuration flow reached from
/// [AdminLoginScreen] when setup is not yet done.
///
/// Walks the owner through six steps, each editing the
/// in-memory [WizardState] held by [SetupWizardNotifier]:
///   0. Store profile
///   1. Tax & currency
///   2. Payment methods
///   3. Staff members
///   4. Inventory (CSV paste)
///   5. Hardware peripherals
///
/// On completion, `saveAndComplete()` persists everything
/// to Isar (StoreSettings, owner account, staff, products,
/// batches) and then navigates to the [MainShellScreen].
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/main/screens/main_shell_screen.dart';
import 'package:shop_pos/features/setup/providers/setup_wizard_provider.dart';

/// Display labels for the staff roles understood by [WizardStaffEntry].
const _staffRoles = ['cashier', 'manager', 'stock_clerk'];

class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  int _step = 0;
  bool _loading = false;
  String? _error;

  // ── Text field controllers (kept for the lifetime of the wizard) ─
  final _storeNameCtrl = TextEditingController();
  final _storePhoneCtrl = TextEditingController();
  final _storeAddressCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController();
  final _vatRateCtrl = TextEditingController();
  final _taxIdCtrl = TextEditingController();
  final _csvCtrl = TextEditingController();

  static const _stepTitles = [
    'Store Profile',
    'Tax & Currency',
    'Payment Methods',
    'Staff',
    'Inventory',
    'Hardware',
  ];

  @override
  void initState() {
    super.initState();
    // Pre-fill controllers from whatever admin_login already stored.
    final s = ref.read(setupWizardProvider);
    _storeNameCtrl.text = s.storeName;
    _storePhoneCtrl.text = s.storePhone;
    _storeAddressCtrl.text = s.storeAddress;
    _currencyCtrl.text = s.currency;
    _vatRateCtrl.text = s.vatRate.toString();
    _taxIdCtrl.text = s.taxId;
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _storePhoneCtrl.dispose();
    _storeAddressCtrl.dispose();
    _currencyCtrl.dispose();
    _vatRateCtrl.dispose();
    _taxIdCtrl.dispose();
    _csvCtrl.dispose();
    super.dispose();
  }

  // ── Flush text-based step fields into the provider state ─────────
  void _flushStoreProfile() {
    ref.read(setupWizardProvider.notifier).update((s) => s.copyWith(
          storeName: _storeNameCtrl.text.trim(),
          storePhone: _storePhoneCtrl.text.trim(),
          storeAddress: _storeAddressCtrl.text.trim(),
        ));
  }

  void _flushTaxCurrency() {
    final vat = double.tryParse(_vatRateCtrl.text.trim()) ?? 0.0;
    ref.read(setupWizardProvider.notifier).update((s) => s.copyWith(
          currency: _currencyCtrl.text.trim().isNotEmpty
              ? _currencyCtrl.text.trim().toUpperCase()
              : s.currency,
          vatRate: vat.isNaN ? 0.0 : vat,
          taxId: _taxIdCtrl.text.trim(),
        ));
  }

  void _next() {
    if (_step == 0) _flushStoreProfile();
    if (_step == 1) _flushTaxCurrency();
    if (_step < _stepTitles.length - 1) {
      setState(() => _step++);
      _error = null;
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _finish() async {
    _flushStoreProfile();
    _flushTaxCurrency();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(setupWizardProvider.notifier).saveAndComplete();
      if (!mounted) return;
      // Setup is now persisted — drop the entire back stack.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShellScreen()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to save setup. Please try again.';
        });
      }
    }
  }

  // ── Step bodies ───────────────────────────────────────────────────
  Widget _buildStoreProfile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Store name'),
        _buildTextField(_storeNameCtrl, 'e.g. Kofi\'s Corner Shop'),
        const SizedBox(height: AppSpacing.md),
        _label('Phone number'),
        _buildTextField(_storePhoneCtrl, '+233 20 000 0000',
            keyboardType: TextInputType.phone),
        const SizedBox(height: AppSpacing.md),
        _label('Address'),
        _buildTextField(_storeAddressCtrl, 'Street, City, Region'),
      ],
    );
  }

  Widget _buildTaxCurrency() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Currency code'),
        _buildTextField(_currencyCtrl, 'GHS', maxLength: 4),
        const SizedBox(height: AppSpacing.md),
        _label('VAT rate (%)', hint: 'e.g. 12.5'),
        _buildTextField(_vatRateCtrl, '0',
            keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: AppSpacing.md),
        _label('Tax / VAT ID (optional)'),
        _buildTextField(_taxIdCtrl, 'Enter tax registration number'),
      ],
    );
  }

  Widget _buildPayments() {
    final s = ref.watch(setupWizardProvider);
    return _SwitchCard(
      title: 'Acceptable payment methods',
      children: [
        _boolSwitch('Cash', s.enableCash, (v) => _setPayment(enableCash: v)),
        _boolSwitch('Card', s.enableCard, (v) => _setPayment(enableCard: v)),
        _boolSwitch(
            'Mobile Money', s.enableMoMo, (v) => _setPayment(enableMoMo: v)),
        _boolSwitch('QR', s.enableQr, (v) => _setPayment(enableQr: v)),
      ],
    );
  }

  void _setPayment({
    bool? enableCash,
    bool? enableCard,
    bool? enableMoMo,
    bool? enableQr,
  }) {
    ref.read(setupWizardProvider.notifier).update((s) => s.copyWith(
          enableCash: enableCash ?? s.enableCash,
          enableCard: enableCard ?? s.enableCard,
          enableMoMo: enableMoMo ?? s.enableMoMo,
          enableQr: enableQr ?? s.enableQr,
        ));
  }

  Widget _buildStaff() {
    final s = ref.watch(setupWizardProvider);
    final staff = s.staff;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Staff members (${staff.length})'),
        const SizedBox(height: AppSpacing.sm),
        if (staff.isEmpty)
          const Text('No staff added yet.',
              style: TextStyle(color: AppColors.textMuted)),
        ...staff.asMap().entries.map((e) => _buildStaffRow(e.key, e.value)),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () => ref.read(setupWizardProvider.notifier).addStaff(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add staff member'),
        ),
      ],
    );
  }

  Widget _buildStaffRow(int index, WizardStaffEntry entry) {
    final nameCtrl = TextEditingController(text: entry.name);
    final pinCtrl = TextEditingController(text: entry.pin);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _buildTextField(nameCtrl, 'Name')),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _roleDropdown(entry.role, (role) {
              if (role == null) return;
              ref.read(setupWizardProvider.notifier).updateStaff(
                    index,
                    WizardStaffEntry(
                        name: entry.name, role: role, pin: entry.pin),
                  );
            }),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
              child: _buildTextField(pinCtrl, 'PIN (4 digits)', maxLength: 4)),
          const SizedBox(width: AppSpacing.md),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            onPressed: () {
              if (staffCanRemove) {
                ref.read(setupWizardProvider.notifier).removeStaff(index);
              }
            },
          ),
        ],
      ),
    );
  }

  /// At least one manager/cashier slot must remain.
  bool get staffCanRemove => ref.read(setupWizardProvider).staff.length > 1;

  // Persists name + pin edits for a staff row as the user types are
  // flushed on the next Next/Finish, but we update incrementally for the
  // role change above; name/pin are written here to keep the state current.
  Widget _roleDropdown(String value, ValueChanged<String?> onChanged) {
    String display(String r) => switch (r) {
          'cashier' => 'Cashier',
          'manager' => 'Manager',
          'stock_clerk' => 'Stock Clerk',
          _ => 'Cashier',
        };
    return InputDecorator(
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        isDense: true,
        labelText: 'Role',
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _staffRoles.contains(value) ? value : 'cashier',
          // Popup background color goes directly on DropdownButton —
          // ThemeData has no `popupBackgroundColor` parameter.
          dropdownColor: AppColors.cardBg,
          items: _staffRoles
              .map((r) => DropdownMenuItem(
                    value: r,
                    child: Text(display(r)),
                  ))
              .toList(),
          onChanged: onChanged,
          isDense: true,
          underline: const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildInventory() {
    final s = ref.watch(setupWizardProvider);
    final rows = s.importedProducts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Paste product CSV (name, price, quantity, category)',
            hint: 'One product per line, comma-separated'),
        const SizedBox(height: 4),
        TextField(
          controller: _csvCtrl,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Tomato Paste,125.00,50,Groceries',
            hintStyle: TextStyle(color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            ElevatedButton.icon(
              onPressed: _parseCsv,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Parse rows'),
            ),
            if (rows.isNotEmpty)
              TextButton.icon(
                onPressed: () => ref
                    .read(setupWizardProvider.notifier)
                    .update((s) => s.copyWith(importedProducts: [])),
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Clear all'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (rows.isNotEmpty) _buildInventoryTable(rows),
      ],
    );
  }

  void _parseCsv() {
    final rows = <Map<String, String>>[];
    for (final line in _csvCtrl.text.split('\n')) {
      final trimmed = line.split(',').map((p) => p.trim()).toList();
      if (trimmed.isEmpty || (trimmed.length == 1 && trimmed[0].isEmpty)) {
        continue;
      }
      rows.add({
        'name': trimmed[0],
        'price': trimmed.length > 1 ? trimmed[1] : '0',
        'quantity': trimmed.length > 2 ? trimmed[2] : '0',
        'category': trimmed.length > 3 ? trimmed[3] : 'Uncategorized',
      });
    }
    ref
        .read(setupWizardProvider.notifier)
        .update((s) => s.copyWith(importedProducts: rows));
    _csvCtrl.clear();
  }

  Widget _buildInventoryTable(List<Map<String, String>> rows) {
    return SizedBox(
      width: double.infinity,
      child: DataTable(
        headingRowHeight: 32,
        // dataRowHeight is deprecated — use min/max instead, both set to
        // the same value to keep the previous fixed-height behavior.
        dataRowMinHeight: 32,
        dataRowMaxHeight: 32,
        columnSpacing: AppSpacing.sm,
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Price')),
          DataColumn(label: Text('Qty')),
          DataColumn(label: Text('Category')),
        ],
        rows: rows
            .map((r) => DataRow(cells: [
                  DataCell(Text(r['name'] ?? '')),
                  DataCell(Text(r['price'] ?? '')),
                  DataCell(Text(r['quantity'] ?? '')),
                  DataCell(Text(r['category'] ?? '')),
                ]))
            .toList(),
      ),
    );
  }

  Widget _buildHardware() {
    final s = ref.watch(setupWizardProvider);
    return _SwitchCard(
      title: 'Hardware peripherals',
      children: [
        _boolSwitch(
            'Printer', s.printerEnabled, (v) => _setHardware(printer: v)),
        _boolSwitch('Barcode scanner', s.scannerEnabled,
            (v) => _setHardware(scanner: v)),
        _boolSwitch('Cash drawer', s.cashDrawerEnabled,
            (v) => _setHardware(cashDrawer: v)),
      ],
    );
  }

  void _setHardware({bool? printer, bool? scanner, bool? cashDrawer}) {
    ref.read(setupWizardProvider.notifier).update((s) => s.copyWith(
          printerEnabled: printer ?? s.printerEnabled,
          scannerEnabled: scanner ?? s.scannerEnabled,
          cashDrawerEnabled: cashDrawer ?? s.cashDrawerEnabled,
        ));
  }

  // ── Small presentational helpers ────────────────────────────────
  Widget _boolSwitch(String label, bool value, ValueChanged<bool?> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textPrimary)),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _label(String text, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        if (hint != null)
          Text(hint,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint, {
    TextInputType? keyboardType,
    bool obscure = false,
    int? maxLength,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLength: maxLength,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        isDense: true,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(setupWizardProvider);

    Widget body;
    switch (_step) {
      case 0:
        body = _buildStoreProfile();
        break;
      case 1:
        body = _buildTaxCurrency();
        break;
      case 2:
        body = _buildPayments();
        break;
      case 3:
        body = _buildStaff();
        break;
      case 4:
        body = _buildInventory();
        break;
      case 5:
        body = _buildHardware();
        break;
      default:
        body = const SizedBox.shrink();
    }

    final isLast = _step == _stepTitles.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF14151D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Store Setup'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Admin credentials hint ─────────────────────
                  if (s.adminEmail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        children: [
                          const Icon(Icons.check_circle,
                              color: AppColors.success, size: 16),
                          Text('Admin account: ${s.adminEmail}',
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  // ── Step indicator ─────────────────────────────
                  _buildStepIndicator(),
                  const SizedBox(height: AppSpacing.lg),
                  // ── Step content ───────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: AppSpacing.borderXl,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: body,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // ── Error ─────────────────────────────────────
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.danger, fontSize: 13)),
                    ),
                  // ── Navigation ────────────────────────────────
                  _buildActions(isLast),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Wrap(
      spacing: 2,
      runSpacing: 14,
      alignment: WrapAlignment.center,
      children: List.generate(_stepTitles.length, (i) {
        final active = i == _step;
        final done = i < _step;
        final bg = done
            ? AppColors.success
            : (active ? AppColors.primary : const Color(0xFF2A2C38));
        final fg = done || active ? Colors.white : AppColors.textMuted;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: bg,
              foregroundColor: fg,
              child: done
                  ? const Icon(Icons.check, size: 16)
                  : Text('${i + 1}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            const SizedBox(height: 6),
            Text(_stepTitles[i],
                style: TextStyle(
                    color: active
                        ? AppColors.primaryDark
                        : done
                            ? AppColors.success
                            : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
          ],
        );
      }),
    );
  }

  Widget _buildActions(bool isLast) {
    return Row(
      children: [
        if (_step > 0)
          Expanded(
            child: OutlinedButton(
              onPressed: _loading ? null : _back,
              child: const Text('Back'),
            ),
          ),
        if (_step > 0) const SizedBox(width: AppSpacing.md),
        Expanded(
          child: ElevatedButton(
            onPressed: _loading ? null : (isLast ? _finish : _next),
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(isLast ? 'Finish & open store' : 'Next'),
          ),
        ),
      ],
    );
  }
}

/// A tiny card wrapping a titled column of switches.
class _SwitchCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SwitchCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        ...children,
      ],
    );
  }
}
