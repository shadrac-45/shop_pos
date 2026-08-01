import 'package:isar/isar.dart';

part 'sale.g.dart';

@Collection()
class Sale {
  Id id = Isar.autoIncrement;

  @Index()
  late DateTime timestamp;

  @Index(composite: [CompositeIndex('timestamp')])
  late String paymentType; // Composite index on (paymentType, timestamp)

  @Index(composite: [CompositeIndex('timestamp')])
  late String cashierPin; // Stored as pinHash for legacy attribution

  /// ID of the AppUser (staff member) who processed this sale.
  /// 0 means unknown / pre-migration record.
  @Index()
  int cashierId = 0;

  late double totalAmount;
  late String itemsJson;
  bool isSynced = false;

  // ── Paystack MoMo fields (null for cash sales) ──────────────────────
  /// Paystack transaction reference (e.g. "shoppos_1722390000000_abc123").
  String? paystackReference;

  /// Ghana MoMo provider code: "mtn" | "vod" | "tgo". Null for cash.
  String? momoProvider;

  /// Customer phone number in international format (e.g. "+233551234987").
  String? momoPhone;
}
