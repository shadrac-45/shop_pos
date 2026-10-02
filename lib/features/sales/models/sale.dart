import 'package:isar/isar.dart';

part 'sale.g.dart';

/// Lifecycle of a sale. Stored as a plain string so older rows (written
/// before this field existed) read back as [completed].
class SaleStatus {
  SaleStatus._();

  static const completed = 'completed';

  /// Cancelled in full; every item went back into stock.
  static const voided = 'voided';

  /// Some items were returned and refunded.
  static const partiallyRefunded = 'partially_refunded';

  /// Every item was returned and refunded.
  static const refunded = 'refunded';
}

/// One tender applied to a sale. A normal sale has a single payment; a
/// split payment has several (e.g. part cash, part MoMo).
@embedded
class SalePayment {
  /// One of the `AppConstants.payment*` method codes.
  String method = 'cash';
  double amount = 0;

  /// Paystack reference, card slip number, QR transaction ID, etc.
  String? reference;
}

/// Money given back to the customer, by a refund or a void.
@embedded
class SaleRefund {
  double amount = 0;

  /// How the money went back: usually 'cash'.
  String method = 'cash';

  DateTime? at;
  int userId = 0;

  /// Shift open for the refunding user, so cash-ups can subtract it.
  int? shiftId;

  String? reason;
}

@Collection()
class Sale {
  Id id = Isar.autoIncrement;

  /// Stable ID used for sync and backups (local [id]s differ per device).
  @Index()
  String? uuid;

  @Index()
  late DateTime timestamp;

  /// Primary method: the single method used, or 'split'.
  @Index(composite: [CompositeIndex('timestamp')])
  late String paymentType; // Composite index on (paymentType, timestamp)

  /// ID of the AppUser (staff member) who processed this sale.
  /// 0 means unknown / pre-migration record.
  @Index()
  int cashierId = 0;

  /// The shift this sale was rung up in, if one was open.
  @Index()
  int? shiftId;

  /// Amount the customer paid: subtotal − discount (+ tax when prices
  /// exclude tax).
  late double totalAmount;

  /// Sum of line totals after line discounts, before the sale discount.
  /// Null on sales recorded before tax/discount support.
  double? subtotal;

  /// Line discounts plus the sale-level discount.
  double discountAmount = 0;

  /// Tax contained in (or added to) [totalAmount].
  double taxAmount = 0;

  /// VAT rate (%) in force when the sale was made.
  double taxRate = 0;

  /// Cash handed over by the customer, and the change given back.
  double? amountTendered;
  double changeDue = 0;

  List<SalePayment> payments = [];

  late String itemsJson;
  bool isSynced = false;
  DateTime? updatedAt;

  // ── Status: void / refund ────────────────────────────────────────────
  String status = SaleStatus.completed;
  double refundedAmount = 0;
  List<SaleRefund> refunds = [];
  String? statusReason;
  DateTime? statusChangedAt;
  int? statusChangedBy;

  // ── Paystack MoMo fields (null for cash sales) ──────────────────────
  /// Paystack transaction reference (e.g. "shoppos_1722390000000_abc123").
  @Index()
  String? paystackReference;

  /// Ghana MoMo provider code: "mtn" | "vod" | "atl". Null for cash.
  String? momoProvider;

  /// Customer phone number in international format (e.g. "+233551234987").
  String? momoPhone;

  // ── Derived values ──────────────────────────────────────────────────

  /// Subtotal, falling back to the total for legacy rows.
  @ignore
  double get effectiveSubtotal => subtotal ?? totalAmount;

  /// What the shop keeps from this sale after refunds.
  @ignore
  double get netAmount => status == SaleStatus.voided
      ? 0
      : (totalAmount - refundedAmount).clamp(0, double.infinity).toDouble();

  @ignore
  bool get isVoided => status == SaleStatus.voided;

  /// Payments for this sale; legacy rows (no embedded payments) are
  /// treated as one payment of the full total by [paymentType].
  @ignore
  List<SalePayment> get effectivePayments => payments.isNotEmpty
      ? payments
      : [
          SalePayment()
            ..method = paymentType
            ..amount = totalAmount
            ..reference = paystackReference,
        ];

  /// Short human-readable receipt number.
  @ignore
  String get receiptNumber => 'R${id.toString().padLeft(6, '0')}';
}
