/// ============================================
/// Currency Helpers — Utility Functions
/// ============================================
/// Formatting currency values for display.
/// ============================================
library;

import 'package:intl/intl.dart';
import 'package:shop_pos/core/constants/app_constants.dart';

class CurrencyHelpers {
  CurrencyHelpers._();

  static final _formatter = NumberFormat('#,##0.00');

  /// Format a double as currency: "GH₵ 12.50"
  static String format(double amount) {
    return '${AppConstants.currencySymbol} ${_formatter.format(amount)}';
  }

  /// Format a double as compact currency: "GH₵12.50"
  static String formatCompact(double amount) {
    return '${AppConstants.currencySymbol}${_formatter.format(amount)}';
  }

  /// Format without symbol: "12.50"
  static String formatRaw(double amount) {
    return _formatter.format(amount);
  }
}
