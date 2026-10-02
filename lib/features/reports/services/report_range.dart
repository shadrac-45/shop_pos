/// ============================================
/// Report Range — ShopPOS
/// ============================================
/// A reporting period: [start] inclusive, [end]
/// exclusive, both at local midnight.
/// ============================================
library;

import 'package:shop_pos/core/utils/date_helpers.dart';

enum ReportPeriod { today, yesterday, thisWeek, last7Days, thisMonth, lastMonth, custom }

class ReportRange {
  final ReportPeriod period;
  final DateTime start;
  final DateTime end;

  const ReportRange._(this.period, this.start, this.end);

  factory ReportRange.of(ReportPeriod period, {DateTime? now}) {
    final today = DateHelpers.startOfDay(now ?? DateTime.now());
    final tomorrow = _addDays(today, 1);
    return switch (period) {
      ReportPeriod.today => ReportRange._(period, today, tomorrow),
      ReportPeriod.yesterday =>
        ReportRange._(period, _addDays(today, -1), today),
      // Calendar week starting Monday.
      ReportPeriod.thisWeek => ReportRange._(
          period, _addDays(today, -(today.weekday - DateTime.monday)), tomorrow),
      ReportPeriod.last7Days =>
        ReportRange._(period, _addDays(today, -6), tomorrow),
      ReportPeriod.thisMonth =>
        ReportRange._(period, DateTime(today.year, today.month), tomorrow),
      ReportPeriod.lastMonth => ReportRange._(period,
          DateTime(today.year, today.month - 1), DateTime(today.year, today.month)),
      ReportPeriod.custom => ReportRange._(period, today, tomorrow),
    };
  }

  /// Whole days from [first] to [last], inclusive.
  factory ReportRange.custom(DateTime first, DateTime last) {
    final a = DateHelpers.startOfDay(first);
    final b = DateHelpers.startOfDay(last);
    final (from, to) = a.isAfter(b) ? (b, a) : (a, b);
    return ReportRange._(ReportPeriod.custom, from, _addDays(to, 1));
  }

  /// Last instant inside the range, for inclusive `between` queries.
  DateTime get endInclusive => end.subtract(const Duration(microseconds: 1));

  /// Last day in the range.
  DateTime get lastDay => _addDays(end, -1);

  String get label => switch (period) {
        ReportPeriod.today => 'Today',
        ReportPeriod.yesterday => 'Yesterday',
        ReportPeriod.thisWeek => 'This week',
        ReportPeriod.last7Days => 'Last 7 days',
        ReportPeriod.thisMonth => 'This month',
        ReportPeriod.lastMonth => 'Last month',
        ReportPeriod.custom => DateHelpers.isSameDay(start, lastDay)
            ? DateHelpers.formatShort(start)
            : '${DateHelpers.formatShort(start)} – ${DateHelpers.formatShort(lastDay)}',
      };

  // Calendar arithmetic (not Duration) so DST changes can't shift midnight.
  static DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);
}
