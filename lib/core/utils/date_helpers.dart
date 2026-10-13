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

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Get the start of a given day (midnight).
  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Get the end of a given day (23:59:59).
  static DateTime endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59);
  }
}
