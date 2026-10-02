/// ============================================
/// Report Provider — ShopPOS
/// ============================================
/// The reporting period the owner/manager has
/// picked, and the report for it.
/// ============================================
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/features/reports/services/report_range.dart';
import 'package:shop_pos/features/reports/services/report_service.dart';

final reportProvider =
    StateNotifierProvider<ReportNotifier, AsyncValue<ReportSummary>>((ref) {
  return ReportNotifier(ref);
});

class ReportNotifier extends StateNotifier<AsyncValue<ReportSummary>> {
  final Ref ref;
  ReportRange _range = ReportRange.of(ReportPeriod.today);

  ReportNotifier(this.ref) : super(const AsyncValue.loading()) {
    refresh();
  }

  ReportRange get range => _range;

  Future<void> setRange(ReportRange range) {
    _range = range;
    return refresh();
  }

  /// Reloads the current period. Relative periods ("Today") are re-derived
  /// so a report left open past midnight moves on to the new day.
  Future<void> refresh() async {
    if (_range.period != ReportPeriod.custom) {
      _range = ReportRange.of(_range.period);
    }
    final range = _range;
    try {
      final summary = await ReportSummary.load(ref.read(isarProvider), range);
      if (mounted && identical(range, _range)) state = AsyncValue.data(summary);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }
}
