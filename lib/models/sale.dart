import 'package:isar/isar.dart';

part 'sale.g.dart';

@Collection()
class Sale {
  Id id = Isar.autoIncrement;

  late DateTime timestamp;
  late String cashierPin;
  late double totalAmount;
  late String paymentType; // "cash", "momo", "split"
  late String itemsJson; // Store sold items as JSON string for MVP
}
