/// ============================================
/// Store Settings Screen — ShopPOS
/// ============================================
/// Owner-only editor for what the setup wizard
/// collected: store profile (shown on receipts),
/// currency, VAT, receipt footer, accepted
/// payment methods and hardware.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';

class StoreSettingsScreen extends ConsumerStatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  ConsumerState<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends ConsumerState<StoreSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController();
  late final _phone = TextEditingController();
  late final _address = TextEditingController();
  late final _currency = TextEditingController();
  late final _vat = TextEditingController();
  late final _taxId = TextEditingController();
  late final _footer = TextEditingController();

  late bool _pricesIncludeTax;
  late bool _cash, _momo, _card, _qr;
  late bool _printer, _scanner, _drawer;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(storeSettingsProvider);
    _name.text = s.storeName;
    _phone.text = s.storePhone;
    _address.text = s.storeAddress;
    _currency.text = s.currency;
    _vat.text = s.vatRate == 0 ? '' : s.vatRate.toString();
    _taxId.text = s.taxId;
    _footer.text = s.receiptFooter;
    _pricesIncludeTax = s.pricesIncludeTax;
    _cash = s.enableCash;
    _momo = s.enableMoMo;
    _card = s.enableCard;
    _qr = s.enableQr;
    _printer = s.printerEnabled;
    _scanner = s.scannerEnabled;
    _drawer = s.cashDrawerEnabled;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _currency, _vat, _taxId, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!(_cash || _momo || _card || _qr)) {
      context.showErrorSnackbar('Turn on at least one payment method.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(storeSettingsProvider.notifier).edit(
        (s) => s
          ..storeName = _name.text.trim()
          ..storePhone = _phone.text.trim()
          ..storeAddress = _address.text.trim()
          ..currency = _currency.text.trim().toUpperCase()
          ..vatRate = double.tryParse(_vat.text.trim()) ?? 0
          ..pricesIncludeTax = _pricesIncludeTax
          ..taxId = _taxId.text.trim()
          ..receiptFooter = _footer.text.trim()
          ..enableCash = _cash
          ..enableMoMo = _momo
          ..enableCard = _card
          ..enableQr = _qr
          ..printerEnabled = _printer
          ..scannerEnabled = _scanner
          ..cashDrawerEnabled = _drawer,
        user: ref.read(currentUserProvider),
        logDetails: 'Store settings updated',
      );
      if (!mounted) return;
      context.showSuccessSnackbar('Store settings saved.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        context.showErrorSnackbar(errorMessage(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label,
            {String? hint, TextInputType? keyboard, FormFieldValidator<String>? validator}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: TextFormField(
            controller: c,
            keyboardType: keyboard,
            validator: validator,
            decoration: InputDecoration(labelText: label, hintText: hint),
          ),
        );

    Widget toggle(String label, bool value, ValueChanged<bool> onChanged, {String? subtitle}) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: subtitle == null ? null : Text(subtitle),
          value: value,
          onChanged: (v) => setState(() => onChanged(v)),
        );

    final vat = double.tryParse(_vat.text.trim()) ?? 0;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(title: const Text('Store Settings'), backgroundColor: AppColors.cardBg),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const SectionLabel('Store profile (printed on receipts)'),
              field(_name, 'Store name'),
              field(_phone, 'Phone', keyboard: TextInputType.phone),
              field(_address, 'Address'),

              const SectionLabel('Currency & tax'),
              field(_currency, 'Currency code',
                  hint: 'GHS',
                  validator: (v) => (v == null || !RegExp(r'^[A-Za-z]{3}$').hasMatch(v.trim()))
                      ? '3-letter code, e.g. GHS'
                      : null),
              Text('Shown as ${CurrencyHelpers.symbolFor(_currency.text.isEmpty ? 'GHS' : _currency.text)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _vat,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'VAT rate (%)', hintText: '0'),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = double.tryParse(v.trim());
                  return (n == null || n < 0 || n > 100) ? 'Between 0 and 100' : null;
                },
              ),
              if (vat > 0)
                toggle(
                  'Shelf prices already include VAT',
                  _pricesIncludeTax,
                  (v) => _pricesIncludeTax = v,
                  subtitle: _pricesIncludeTax
                      ? 'Customers pay the shelf price; VAT is shown on the receipt.'
                      : 'VAT is added on top of shelf prices at checkout.',
                ),
              field(_taxId, 'Tax ID / TIN (optional)'),
              field(_footer, 'Receipt footer', hint: 'Thank you for shopping with us!'),

              const SectionLabel('Payment methods'),
              toggle('Cash', _cash, (v) => _cash = v),
              toggle('Mobile Money (Paystack)', _momo, (v) => _momo = v,
                  subtitle: 'Needs the backend set up in Integrations.'),
              toggle('Card', _card, (v) => _card = v,
                  subtitle: 'Recorded after you charge on your own card machine.'),
              toggle('QR', _qr, (v) => _qr = v,
                  subtitle: 'Recorded after the customer pays by QR code.'),

              const SectionLabel('Hardware'),
              toggle('Receipt printer', _printer, (v) => _printer = v,
                  subtitle: 'Opens the print dialog after every sale.'),
              toggle('Barcode scanner', _scanner, (v) => _scanner = v),
              toggle('Cash drawer', _drawer, (v) => _drawer = v,
                  subtitle: 'Saved for future use: drawers are not controlled by the app yet.'),

              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, AppTouch.buttonHeight)),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
