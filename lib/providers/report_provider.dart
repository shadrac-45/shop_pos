import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/sale.dart';
import 'database_provider.dart';

final reportProvider = StateNotifierProvider<ReportNotifier, List<Sale>>((ref) {
  return ReportNotifier(ref);
});

class ReportNotifier extends StateNotifier<List<Sale>> {
  final Ref ref;

  ReportNotifier(this.ref) : super([]);

  Future<void> loadTodaySales() async {
    final isar = ref.read(isarProvider);
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final sales = await isar.sales
        .filter()
        .timestampBetween(startOfDay, endOfDay)
        .sortByTimestampDesc()
        .findAll();

    state = sales;
  }

  double get todayTotal =>
      state.fold(0.0, (sum, sale) => sum + sale.totalAmount);

  Map<String, double> get todayBreakdown {
    double cash = 0.0;
    double momo = 0.0;

    for (var sale in state) {
      if (sale.paymentType == 'cash') cash += sale.totalAmount;
      if (sale.paymentType == 'momo') momo += sale.totalAmount;
    }
    return {'cash': cash, 'momo': momo};
  }
}
