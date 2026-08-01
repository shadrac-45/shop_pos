/// ============================================
/// Report Provider — ShopPOS
/// ============================================
/// Loads and aggregates sales data for the Owner's
/// Reports dashboard. Provides:
///  • Per-period sale lists (today / this week)
///  • CashierSummary: per-staff revenue & transaction attribution
///  • Product summary: ranked by quantity + revenue
///  • Sample data generator for demo/testing
/// ============================================
library;

import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/app_user.dart';
import '../models/sale.dart';
import '../services/report_aggregator.dart';
import '../utils/date_helpers.dart';
import 'database_provider.dart';

// ── Providers ────────────────────────────────────────────

final reportProvider = StateNotifierProvider<ReportNotifier, List<Sale>>((ref) {
  return ReportNotifier(ref);
});

/// Ranked product summaries derived from the current reportProvider state.
final productSummariesProvider = Provider<List<ProductSummary>>((ref) {
  return ref.watch(reportProvider.notifier).productSummaries;
});

/// Per-cashier summaries (async — resolves AppUser names from Isar).
final cashierSummariesProvider =
    FutureProvider<List<CashierSummary>>((ref) async {
  final sales = ref.watch(reportProvider);
  final isar = ref.read(isarProvider);
  return ReportAggregator.buildCashierSummaries(isar, sales);
});

// ── ReportNotifier ────────────────────────────────────────

class ReportNotifier extends StateNotifier<List<Sale>> {
  final Ref ref;
  String _currentFilter = 'today';
  DateTime? _lastFetchTime;

  ReportNotifier(this.ref) : super([]) {
    loadSalesForFilter('today', force: true);
  }

  String get currentFilter => _currentFilter;

  /// Loads sales for the requested filter ('today' or 'week').
  Future<void> loadSalesForFilter(String filter, {bool force = false}) async {
    final now = DateTime.now();

    if (!force &&
        _currentFilter == filter &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!).inSeconds < 10 &&
        state.isNotEmpty) {
      return;
    }

    _currentFilter = filter;
    _lastFetchTime = now;

    final isar = ref.read(isarProvider);
    final DateTime startOfPeriod;
    final endOfPeriod =
        DateHelpers.startOfDay(now).add(const Duration(days: 1));

    if (filter == 'week') {
      startOfPeriod =
          DateHelpers.startOfDay(now).subtract(const Duration(days: 7));
    } else {
      startOfPeriod = DateHelpers.startOfDay(now);
    }

    final sales = await isar.sales
        .filter()
        .timestampBetween(startOfPeriod, endOfPeriod)
        .sortByTimestampDesc()
        .findAll();

    state = sales;
  }

  Future<void> loadTodaySales({bool force = true}) =>
      loadSalesForFilter('today', force: force);

  // ── Computed getters ──────────────────────────────────

  double get todayTotal => ReportAggregator.computeTotalRevenue(state);

  Map<String, double> get todayBreakdown =>
      ReportAggregator.computeBreakdown(state);

  /// Ranked products by quantity sold (descending), with revenue.
  List<ProductSummary> get productSummaries =>
      ReportAggregator.computeProductSummaries(state);

  /// Legacy getter — quantity only, used by existing providers.
  Map<String, int> get topProducts {
    return {for (final p in productSummaries) p.productName: p.totalQty};
  }

  // ── Sample data seeding ───────────────────────────────

  /// Seeds realistic multi-cashier sample sales for demo & testing.
  /// Looks up real AppUser IDs from Isar so cashier attribution works correctly.
  Future<void> seedSampleSales() async {
    final isar = ref.read(isarProvider);
    final now = DateTime.now();

    // Resolve real user IDs for seeding
    final owner =
        await isar.appUsers.filter().roleEqualTo('owner').findFirst();
    final cashier =
        await isar.appUsers.filter().roleEqualTo('cashier').findFirst();
    final ownerPin = owner?.pinHash ?? '';
    final cashierPin = cashier?.pinHash ?? '';
    final ownerId = owner?.id ?? 0;
    final cashierId = cashier?.id ?? 0;

    final sampleSales = [
      // Owner — Cash
      Sale()
        ..timestamp = now.subtract(const Duration(minutes: 15))
        ..cashierPin = ownerPin
        ..cashierId = ownerId
        ..totalAmount = 85.00
        ..paymentType = 'cash'
        ..itemsJson = jsonEncode([
          {'productId': 1, 'productName': 'Milk (1L)', 'quantity': 2, 'price': 25.00},
          {'productId': 2, 'productName': 'Bread (Loaf)', 'quantity': 1, 'price': 35.00},
        ])
        ..isSynced = false,
      // Owner — MoMo (with phone number)
      Sale()
        ..timestamp = now.subtract(const Duration(hours: 1, minutes: 20))
        ..cashierPin = ownerPin
        ..cashierId = ownerId
        ..totalAmount = 140.00
        ..paymentType = 'momo'
        ..itemsJson = jsonEncode([
          {'productId': 3, 'productName': 'Rice (5kg Bag)', 'quantity': 1, 'price': 140.00},
        ])
        ..momoProvider = 'mtn'
        ..momoPhone = '+233551234567'
        ..isSynced = false,
      // Cashier — Cash
      Sale()
        ..timestamp = now.subtract(const Duration(hours: 3, minutes: 45))
        ..cashierPin = cashierPin
        ..cashierId = cashierId
        ..totalAmount = 60.00
        ..paymentType = 'cash'
        ..itemsJson = jsonEncode([
          {'productId': 1, 'productName': 'Milk (1L)', 'quantity': 1, 'price': 25.00},
          {'productId': 4, 'productName': 'Sugar (1kg)', 'quantity': 2, 'price': 17.50},
        ])
        ..isSynced = false,
      // Cashier — MoMo (with phone number)
      Sale()
        ..timestamp = now.subtract(const Duration(hours: 5, minutes: 10))
        ..cashierPin = cashierPin
        ..cashierId = cashierId
        ..totalAmount = 210.00
        ..paymentType = 'momo'
        ..itemsJson = jsonEncode([
          {'productId': 5, 'productName': 'Cooking Oil (2L)', 'quantity': 2, 'price': 105.00},
        ])
        ..momoProvider = 'vod'
        ..momoPhone = '+233209876543'
        ..isSynced = false,
      // Cashier — Cash
      Sale()
        ..timestamp = now.subtract(const Duration(hours: 7))
        ..cashierPin = cashierPin
        ..cashierId = cashierId
        ..totalAmount = 45.00
        ..paymentType = 'cash'
        ..itemsJson = jsonEncode([
          {'productId': 2, 'productName': 'Bread (Loaf)', 'quantity': 1, 'price': 35.00},
          {'productId': 6, 'productName': 'Eggs (crate)', 'quantity': 1, 'price': 10.00},
        ])
        ..isSynced = false,
    ];

    await isar.writeTxn(() async {
      await isar.sales.putAll(sampleSales);
    });

    await loadSalesForFilter('today', force: true);
  }
}
