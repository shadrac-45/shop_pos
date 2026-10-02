/// ============================================
/// Setup Wizard Screen — ShopPOS
/// ============================================
/// First-run configuration flow reached from
/// [AdminLoginScreen] when setup is not yet done.
///
/// One question group per screen, so business
/// and security questions are never mixed:
///   0. Store profile       (business)
///   1. Currency & tax      (business)
///   2. Payment methods     (business)
///   3. Owner PIN           (security)
///   4. Staff & PINs        (security)
///   5. Opening stock       (setup)
///   6. Hardware            (setup)
///
/// Everything typed is kept in controllers that
/// live for the whole wizard, so Back / Next
/// never lose data. Each step validates its own
/// fields (errors shown on the field itself)
/// before moving on. On completion,
/// `saveAndComplete()` persists everything and
/// opens the [MainShellScreen].
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/main/screens/main_shell_screen.dart';
import 'package:shop_pos/features/setup/providers/setup_wizard_provider.dart';

enum _Group { business, security, setup }

class _StepInfo {
  final String title;
  final String helper;
  final _Group group;
  const _StepInfo(this.title, this.helper, this.group);
}

const _steps = [
  _StepInfo(
      'Store profile',
      'Your shop\'s name and contact details, printed on every receipt.',
      _Group.business),
  _StepInfo(
      'Currency & tax',
      'How prices are shown and how VAT is worked out at checkout.',
      _Group.business),
  _StepInfo(
      'Payment methods',
      'The ways customers can pay you. You can change these later in Settings.',
      _Group.business),
  _StepInfo(
      'Your owner PIN',
      'Your own PIN for the keypad. It also approves overrides and lets you '
          'reset your password if you forget it.',
      _Group.security),
  _StepInfo(
      'Staff & their PINs',
      'Each person signs in with their own PIN. Every PIN must be different. '
          'You can add staff later in Settings → Manage Staff.',
      _Group.security),
  _StepInfo(
      'Opening stock',
      'Optional: paste products to start with. You can import a spreadsheet later.',
      _Group.setup),
  _StepInfo(
      'Hardware',
      'Optional devices. Printers are chosen later in Settings → Receipt Printer.',
      _Group.setup),
];

/// Text controllers for one staff entry, kept for the wizard's lifetime.
class _StaffControllers {
  final TextEditingController name;
  final TextEditingController pin;
  bool obscurePin = true;
  _StaffControllers(WizardStaffEntry e)
      : name = TextEditingController(text: e.name),
        pin = TextEditingController(text: e.pin);
  void dispose() {
    name.dispose();
    pin.dispose();
  }
}

class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  int _step = 0;
  bool _loading = false;
  String? _error;

  /// Steps whose errors are shown (after the user tried to continue).
  final Set<int> _showErrors = {};

  final _scrollCtrl = ScrollController();

  // ── Controllers (kept for the lifetime of the wizard) ─────────────
  final _storeNameCtrl = TextEditingController();
  final _storePhoneCtrl = TextEditingController();
  final _storeAddressCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController();
  final _vatRateCtrl = TextEditingController();
  final _taxIdCtrl = TextEditingController();
  final _csvCtrl = TextEditingController();
  final _ownerPinCtrl = TextEditingController();
  final _ownerPinConfirmCtrl = TextEditingController();
  bool _obscureOwnerPin = true;
  final Map<WizardStaffEntry, _StaffControllers> _staffCtrls = {};

  @override
  void initState() {
    super.initState();
    // Pre-fill from whatever is already in the wizard state.
    final s = ref.read(setupWizardProvider);
    _storeNameCtrl.text = s.storeName;
    _storePhoneCtrl.text = s.storePhone;
    _storeAddressCtrl.text = s.storeAddress;
    _currencyCtrl.text = s.currency;
    _vatRateCtrl.text = s.vatRate == 0 ? '' : s.vatRate.toString();
    _taxIdCtrl.text = s.taxId;
    _ownerPinCtrl.text = s.ownerPin;
    _ownerPinConfirmCtrl.text = s.ownerPin;
  }

  @override
  void dispose() {
    for (final c in [
      _storeNameCtrl,
      _storePhoneCtrl,
      _storeAddressCtrl,
      _currencyCtrl,
      _vatRateCtrl,
      _taxIdCtrl,
      _csvCtrl,
      _ownerPinCtrl,
      _ownerPinConfirmCtrl,
    ]) {
      c.dispose();
    }
    for (final c in _staffCtrls.values) {
      c.dispose();
    }
    _scrollCtrl.dispose();
    super.dispose();
  }

  WizardState get _state => ref.read(setupWizardProvider);
  void _update(WizardState Function(WizardState) f) =>
      ref.read(setupWizardProvider.notifier).update(f);

  _StaffControllers _ctrlsFor(WizardStaffEntry e) =>
      _staffCtrls.putIfAbsent(e, () => _StaffControllers(e));

  // ── Save what's typed into the wizard state ───────────────────────
  void _flush() {
    _update((s) => s.copyWith(
          storeName: _storeNameCtrl.text.trim(),
          storePhone: _storePhoneCtrl.text.trim(),
          storeAddress: _storeAddressCtrl.text.trim(),
          currency: _currencyCtrl.text.trim().isEmpty
              ? s.currency
              : _currencyCtrl.text.trim().toUpperCase(),
          vatRate: double.tryParse(_vatRateCtrl.text.trim()) ?? 0,
          taxId: _taxIdCtrl.text.trim(),
          ownerPin: _ownerPinCtrl.text.trim(),
        ));
    for (final entry in _state.staff) {
      final c = _ctrlsFor(entry);
      entry
        ..name = c.name.text
        ..pin = c.pin.text;
    }
  }

  // ── Per-step validation (messages appear on the fields) ───────────
  String? _storeNameError() =>
      _storeNameCtrl.text.trim().isEmpty ? 'Enter your store\'s name.' : null;

  String? _currencyError() {
    final c = _currencyCtrl.text.trim();
    if (c.isEmpty) return 'Enter a currency code, e.g. GHS.';
    if (!RegExp(r'^[A-Za-z]{3}$').hasMatch(c)) {
      return 'Use the 3-letter code, e.g. GHS.';
    }
    return null;
  }

  String? _vatError() {
    final v = _vatRateCtrl.text.trim();
    if (v.isEmpty) return null; // no VAT
    final n = double.tryParse(v);
    if (n == null) return 'Enter a number, e.g. 15.';
    if (n < 0 || n > 100) return 'Enter a rate between 0 and 100.';
    return null;
  }

  String? _ownerPinError() =>
      SetupWizardNotifier.pinProblem(_ownerPinCtrl.text.trim());

  String? _ownerConfirmError() {
    if (_ownerPinError() != null) return null;
    return _ownerPinConfirmCtrl.text.trim() == _ownerPinCtrl.text.trim()
        ? null
        : 'The two PINs don\'t match.';
  }

  bool _paymentsError() {
    final s = _state;
    return !(s.enableCash || s.enableCard || s.enableMoMo || s.enableQr);
  }

  bool _stepValid(int step) {
    _flush();
    switch (step) {
      case 0:
        return _storeNameError() == null;
      case 1:
        return _currencyError() == null && _vatError() == null;
      case 2:
        return !_paymentsError();
      case 3:
        return _ownerPinError() == null && _ownerConfirmError() == null;
      case 4:
        return ref
            .read(setupWizardProvider.notifier)
            .staffErrors()
            .every((e) => e.isEmpty);
      default:
        return true;
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────
  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      _error = null;
    });
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
  }

  void _next() {
    if (!_stepValid(_step)) {
      HapticFeedback.vibrate();
      setState(() {
        _showErrors.add(_step);
        _error = 'Please fix the highlighted fields.';
      });
      return;
    }
    if (_step < _steps.length - 1) _goTo(_step + 1);
  }

  void _back() {
    _flush();
    if (_step > 0) _goTo(_step - 1);
  }

  Future<void> _finish() async {
    // Re-check every step; jump to the first with a problem.
    for (var i = 0; i < _steps.length; i++) {
      if (!_stepValid(i)) {
        _goTo(i);
        setState(() {
          _showErrors.add(i);
          _error = 'Please fix the highlighted fields.';
        });
        return;
      }
    }
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
          _error = e is StateError
              ? e.message
              : 'Failed to save setup. Please try again.';
        });
      }
    }
  }

  // ── Step bodies ────────────────────────────────────────────────────
  Widget _buildStoreProfile() {
    final show = _showErrors.contains(0);
    return _Fields(children: [
      _textField(_storeNameCtrl, 'Store name',
          hint: 'e.g. Kofi\'s Corner Shop',
          error: show ? _storeNameError() : null,
          capitalize: true),
      _textField(_storePhoneCtrl, 'Phone number (optional)',
          hint: '+233 20 000 0000', keyboardType: TextInputType.phone),
      _textField(_storeAddressCtrl, 'Address (optional)',
          hint: 'Street, City, Region'),
    ]);
  }

  Widget _buildCurrencyTax() {
    final show = _showErrors.contains(1);
    final s = ref.watch(setupWizardProvider);
    final vat = double.tryParse(_vatRateCtrl.text.trim()) ?? 0;
    final code =
        _currencyCtrl.text.trim().isEmpty ? 'GHS' : _currencyCtrl.text.trim();
    return _Fields(children: [
      _textField(_currencyCtrl, 'Currency code',
          hint: 'GHS',
          maxLength: 3,
          helper: 'Shown as ${CurrencyHelpers.symbolFor(code)}',
          error: show ? _currencyError() : null,
          formatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z]'))],
          onChanged: (_) => setState(() {})),
      _textField(_vatRateCtrl, 'VAT rate (%)',
          hint: '0 if you don\'t charge VAT',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          formatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
          ],
          error: show ? _vatError() : null,
          onChanged: (_) => setState(() {})),
      if (vat > 0)
        _ChoiceGroup(
          label: 'Do your shelf prices already include VAT?',
          options: const [
            (
              'Yes, prices include VAT',
              'Customers pay the shelf price; VAT is shown on the receipt.'
            ),
            (
              'No, add VAT at checkout',
              'VAT is added on top of the shelf price.'
            ),
          ],
          selected: s.pricesIncludeTax ? 0 : 1,
          onSelected: (i) =>
              _update((w) => w.copyWith(pricesIncludeTax: i == 0)),
        ),
      _textField(_taxIdCtrl, 'Tax / VAT ID (optional)',
          hint: 'Your TIN, printed on receipts'),
    ]);
  }

  Widget _buildPayments() {
    final s = ref.watch(setupWizardProvider);
    void set(WizardState Function(WizardState) f) => setState(() => _update(f));
    return _Fields(children: [
      _switch(
          'Cash', s.enableCash, (v) => set((w) => w.copyWith(enableCash: v))),
      _switch('Mobile Money', s.enableMoMo,
          (v) => set((w) => w.copyWith(enableMoMo: v)),
          subtitle: 'MTN, Telecel and AirtelTigo through Paystack'),
      _switch(
          'Card', s.enableCard, (v) => set((w) => w.copyWith(enableCard: v)),
          subtitle: 'Taken on your own card machine'),
      _switch('QR', s.enableQr, (v) => set((w) => w.copyWith(enableQr: v))),
      if (_showErrors.contains(2) && _paymentsError())
        const Text('Turn on at least one payment method.',
            style: TextStyle(color: AppColors.danger, fontSize: 13)),
    ]);
  }

  Widget _buildOwnerPin() {
    final show = _showErrors.contains(3);
    return _Fields(children: [
      _pinField(_ownerPinCtrl, 'Owner PIN',
          obscure: _obscureOwnerPin,
          onToggle: () => setState(() => _obscureOwnerPin = !_obscureOwnerPin),
          helper: '4–6 digits. 1234 and 0000 are not allowed.',
          error: show ? _ownerPinError() : null),
      _pinField(_ownerPinConfirmCtrl, 'Enter the PIN again',
          obscure: _obscureOwnerPin, error: show ? _ownerConfirmError() : null),
    ]);
  }

  Widget _buildStaff() {
    final s = ref.watch(setupWizardProvider);
    final staff = s.staff;
    final errors = _showErrors.contains(4)
        ? ref.read(setupWizardProvider.notifier).staffErrors()
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (staff.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.lg),
            child: Text('No staff yet. You can add them now or later.',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        for (var i = 0; i < staff.length; i++) ...[
          _staffCard(i, staff[i],
              errors != null && i < errors.length ? errors[i] : null),
          const SizedBox(height: AppSpacing.xl),
        ],
        OutlinedButton.icon(
          onPressed: () {
            _flush();
            ref.read(setupWizardProvider.notifier).addStaff();
            setState(() {});
          },
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: const Text('Add staff member'),
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }

  Widget _staffCard(
      int index, WizardStaffEntry entry, StaffEntryErrors? errors) {
    final c = _ctrlsFor(entry);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceBg,
        borderRadius: AppSpacing.borderLg,
        border: Border.all(
          color: (errors != null && !errors.isEmpty)
              ? AppColors.danger
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text('${index + 1}',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Staff member ${index + 1}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              IconButton(
                tooltip: 'Remove staff member ${index + 1}',
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: () {
                  _flush();
                  ref
                      .read(setupWizardProvider.notifier)
                      .removeStaffEntry(entry);
                  _staffCtrls.remove(entry)?.dispose();
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Fields(children: [
            _textField(c.name, 'Name',
                hint: 'e.g. Ama Mensah',
                capitalize: true,
                error: errors?.name,
                onChanged: (v) => entry.name = v),
            DropdownButtonFormField<String>(
              initialValue: AppConstants.staffRoles.contains(entry.role)
                  ? entry.role
                  : AppConstants.roleCashier,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Role'),
              dropdownColor: AppColors.cardBg,
              items: [
                for (final r in AppConstants.staffRoles)
                  DropdownMenuItem(
                      value: r, child: Text(AppConstants.roleLabel(r))),
              ],
              onChanged: (role) =>
                  setState(() => entry.role = role ?? entry.role),
            ),
            _pinField(c.pin, 'Staff PIN',
                obscure: c.obscurePin,
                onToggle: () => setState(() => c.obscurePin = !c.obscurePin),
                helper: '4–6 digits, different from every other PIN',
                error: errors?.pin,
                onChanged: (v) => entry.pin = v),
          ]),
        ],
      ),
    );
  }

  Widget _buildInventory() {
    final s = ref.watch(setupWizardProvider);
    final rows = s.importedProducts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _csvCtrl,
          minLines: 4,
          maxLines: 8,
          scrollPadding: const EdgeInsets.only(bottom: 160),
          decoration: const InputDecoration(
            labelText: 'Products, one per line',
            helperText: 'name, price, quantity, category',
            hintText: 'Tomato Paste, 12.50, 50, Groceries',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ElevatedButton.icon(
              onPressed: _parseCsv,
              icon: const Icon(Icons.playlist_add_rounded, size: 18),
              label: const Text('Add these products'),
            ),
            if (rows.isNotEmpty)
              TextButton.icon(
                onPressed: () =>
                    _update((s) => s.copyWith(importedProducts: [])),
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Clear all'),
              ),
          ],
        ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('${rows.length} product${rows.length == 1 ? '' : 's'} ready',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          // Scrolls sideways on narrow screens instead of overflowing.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 36,
              columnSpacing: AppSpacing.lg,
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Price'), numeric: true),
                DataColumn(label: Text('Qty'), numeric: true),
                DataColumn(label: Text('Category')),
              ],
              rows: [
                for (final r in rows)
                  DataRow(cells: [
                    DataCell(Text(r['name'] ?? '')),
                    DataCell(Text(r['price'] ?? '')),
                    DataCell(Text(r['quantity'] ?? '')),
                    DataCell(Text(r['category'] ?? '')),
                  ]),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _parseCsv() {
    final rows = <Map<String, String>>[..._state.importedProducts];
    for (final line in _csvCtrl.text.split('\n')) {
      final parts = line.split(',').map((p) => p.trim()).toList();
      if (parts.isEmpty || parts[0].isEmpty) continue;
      rows.add({
        'name': parts[0],
        'price': parts.length > 1 ? parts[1] : '0',
        'quantity': parts.length > 2 ? parts[2] : '0',
        'category': parts.length > 3 ? parts[3] : 'Uncategorized',
      });
    }
    _update((s) => s.copyWith(importedProducts: rows));
    _csvCtrl.clear();
  }

  Widget _buildHardware() {
    final s = ref.watch(setupWizardProvider);
    void set(WizardState Function(WizardState) f) => setState(() => _update(f));
    return _Fields(children: [
      _switch('Receipt printer', s.printerEnabled,
          (v) => set((w) => w.copyWith(printerEnabled: v)),
          subtitle: 'Print a receipt after every sale'),
      _switch('Barcode scanner', s.scannerEnabled,
          (v) => set((w) => w.copyWith(scannerEnabled: v))),
      _switch('Cash drawer', s.cashDrawerEnabled,
          (v) => set((w) => w.copyWith(cashDrawerEnabled: v)),
          subtitle: 'Opens on cash sales (plugged into the printer)'),
    ]);
  }

  // ── Field helpers ──────────────────────────────────────────────────

  /// Keeps a focused field (plus some room below it) above the keyboard.
  static const _keyboardPadding = EdgeInsets.fromLTRB(20, 20, 20, 140);

  Widget _textField(
    TextEditingController ctrl,
    String label, {
    String? hint,
    String? helper,
    String? error,
    TextInputType? keyboardType,
    int? maxLength,
    bool capitalize = false,
    List<TextInputFormatter>? formatters,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: formatters,
      textCapitalization:
          capitalize ? TextCapitalization.words : TextCapitalization.none,
      scrollPadding: _keyboardPadding,
      onChanged: (v) {
        onChanged?.call(v);
        if (_showErrors.contains(_step)) setState(() {});
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        errorText: error,
        errorMaxLines: 3,
        counterText: '',
      ),
    );
  }

  Widget _pinField(
    TextEditingController ctrl,
    String label, {
    required bool obscure,
    VoidCallback? onToggle,
    String? helper,
    String? error,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: TextInputType.number,
      maxLength: AppConstants.maxPinLength,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      scrollPadding: _keyboardPadding,
      style: const TextStyle(letterSpacing: 4, fontSize: 18),
      onChanged: (v) {
        onChanged?.call(v);
        if (_showErrors.contains(_step)) setState(() {});
      },
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        errorText: error,
        errorMaxLines: 3,
        counterText: '',
        suffixIcon: onToggle == null
            ? null
            : IconButton(
                tooltip: obscure ? 'Show PIN' : 'Hide PIN',
                icon: Icon(obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: onToggle,
              ),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged,
      {String? subtitle}) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(setupWizardProvider);
    final info = _steps[_step];
    final isLast = _step == _steps.length - 1;
    final narrow = MediaQuery.sizeOf(context).width < 400;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    final body = switch (_step) {
      0 => _buildStoreProfile(),
      1 => _buildCurrencyTax(),
      2 => _buildPayments(),
      3 => _buildOwnerPin(),
      4 => _buildStaff(),
      5 => _buildInventory(),
      _ => _buildHardware(),
    };

    return Scaffold(
      backgroundColor: const Color(0xFF14151D),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Store Setup'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                    narrow ? AppSpacing.md : AppSpacing.lg,
                    AppSpacing.sm,
                    narrow ? AppSpacing.md : AppSpacing.lg,
                    AppSpacing.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (s.adminEmail.isNotEmpty) ...[
                          Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: AppColors.success, size: 16),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text('Admin account: ${s.adminEmail}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Color(0xFF8B8EA3),
                                        fontSize: 13)),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        _ProgressHeader(
                            step: _step, total: _steps.length, info: info),
                        const SizedBox(height: AppSpacing.lg),
                        // A Material (not a decorated box) so switches and list
                        // tiles inside can paint their ink.
                        Material(
                          color: AppColors.cardBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppSpacing.borderXl,
                            side: const BorderSide(color: AppColors.border),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(
                                narrow ? AppSpacing.lg : AppSpacing.xl),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(info.title,
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary)),
                                const SizedBox(height: AppSpacing.xs),
                                Text(info.helper,
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        height: 1.35)),
                                const SizedBox(height: AppSpacing.xl),
                                body,
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ── Bottom bar: error + Back / Next, always visible ──────
            Container(
              padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm,
                  AppSpacing.lg, keyboard > 0 ? AppSpacing.sm : AppSpacing.lg),
              color: const Color(0xFF14151D),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFFFF8A80), fontSize: 13)),
                        ),
                      Row(
                        children: [
                          if (_step > 0) ...[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _loading ? null : _back,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                      color: Color(0xFF3A3D4C)),
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                child: const Text('Back'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                          ],
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed:
                                  _loading ? null : (isLast ? _finish : _next),
                              style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48)),
                              child: _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(
                                      isLast ? 'Finish & open store' : 'Next'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Step 4 of 7", the group (Business / Security / Setup) and a progress bar.
class _ProgressHeader extends StatelessWidget {
  final int step;
  final int total;
  final _StepInfo info;
  const _ProgressHeader(
      {required this.step, required this.total, required this.info});

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (info.group) {
      _Group.business => ('Business', Icons.storefront_rounded),
      _Group.security => ('Security', Icons.lock_rounded),
      _Group.setup => ('Getting started', Icons.inventory_2_rounded),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(label,
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const Spacer(),
            Text('Step ${step + 1} of $total',
                style: const TextStyle(color: Color(0xFF8B8EA3), fontSize: 13)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (step + 1) / total,
            minHeight: 6,
            backgroundColor: const Color(0xFF2A2C38),
            color: AppColors.accent,
          ),
        ),
      ],
    );
  }
}

/// A column of form fields with 16 px between them.
class _Fields extends StatelessWidget {
  final List<Widget> children;
  const _Fields({required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.lg),
          children[i],
        ],
      ],
    );
  }
}

/// Radio-style choice between a few labelled options.
class _ChoiceGroup extends StatelessWidget {
  final String label;
  final List<(String, String)> options;
  final int selected;
  final ValueChanged<int> onSelected;
  const _ChoiceGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: InkWell(
              borderRadius: AppSpacing.borderMd,
              onTap: () => onSelected(i),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: AppSpacing.borderMd,
                  border: Border.all(
                    color: selected == i ? AppColors.primary : AppColors.border,
                    width: selected == i ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected == i
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: selected == i
                          ? AppColors.primary
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(options[i].$1,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text(options[i].$2,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
