/// ============================================
/// Currency Helpers — Utility Functions
/// ============================================
/// Formatting currency values for display, in
/// the store's own currency (set from
/// StoreSettings via [configure]).
/// ============================================
library;

import 'package:intl/intl.dart';
import 'package:shop_pos/core/constants/app_constants.dart';

class CurrencyHelpers {
  CurrencyHelpers._();

  static final _formatter = NumberFormat('#,##0.00');

  static String _code = AppConstants.currencyCode;
  static String _symbol = AppConstants.currencySymbol;

  static String get code => _code;
  static String get symbol => _symbol;

  /// Symbols for currencies likely in use; anything else shows its code.
  static const _symbols = {
    'GHS': 'GH₵',
    'NGN': '₦',
    'KES': 'KSh',
    'UGX': 'USh',
    'TZS': 'TSh',
    'ZAR': 'R',
    'XOF': 'CFA',
    'XAF': 'FCFA',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
  };

  static String symbolFor(String code) =>
      _symbols[code.toUpperCase()] ?? code.toUpperCase();

  /// Sets the currency used by every format call.
  static void configure(String currencyCode) {
    final code = currencyCode.trim().isEmpty
        ? AppConstants.currencyCode
        : currencyCode.trim().toUpperCase();
    _code = code;
    _symbol = symbolFor(code);
  }

  /// Format a double as currency: "GH₵ 12.50"
  static String format(double amount) {
    return '$_symbol ${_formatter.format(amount)}';
  }

  /// Format a double as compact currency: "GH₵12.50"
  static String formatCompact(double amount) {
    return '$_symbol${_formatter.format(amount)}';
  }

  /// Format without symbol: "12.50"
  static String formatRaw(double amount) {
    return _formatter.format(amount);
  }
}
