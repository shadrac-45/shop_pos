/// ============================================
/// Date Helpers — Utility Functions
/// ============================================
/// Common date formatting and comparison helpers
/// used throughout the app.
/// ============================================
library;

import 'package:intl/intl.dart';

class DateHelpers {
  DateHelpers._();

  /// Format date as "12 Mar 2026"
  static String formatShort(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  /// Format date as "12/03/2026"
  static String formatSlash(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  /// Format date as "March 12, 2026"
  static String formatLong(DateTime date) {
    return DateFormat('MMMM dd, yyyy').format(date);
  }

  /// Format time as "2:30 PM"
  static String formatTime(DateTime date) {
    return DateFormat('h:mm a').format(date);
  }

  /// Format date and time as "12 Mar 2026, 2:30 PM"
  static String formatDateTime(DateTime date) {
    return DateFormat('dd MMM yyyy, h:mm a').format(date);
  }

  /// Get days between now and a future date.
  static int daysUntil(DateTime date) {
    return date.difference(DateTime.now()).inDays;
  }

  /// Get a human-readable relative time string.
  static String relativeTime(DateTime date) {
    final days = daysUntil(date);
    if (days < 0) return '${-days} days ago';
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    if (days < 7) return 'In $days days';
    if (days < 30) return 'In ${days ~/ 7} weeks';
    if (days < 365) return 'In ${days ~/ 30} months';
    return 'In ${days ~/ 365} years';
  }

  /// Check if a date is today.
  static bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Get the start of a given day (midnight).
  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Get the end of a given day (23:59:59).
  static DateTime endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59);
  }
}
