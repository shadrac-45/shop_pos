/// ============================================
/// Sale Calculator — ShopPOS
/// ============================================
/// Pure checkout maths: line and sale discounts,
/// VAT (inclusive or added on top), and how the
/// final total is shared across lines so refunds
/// return exactly what the customer paid.
///
/// All money is rounded to 2 decimal places
/// (pesewas); per-line shares absorb rounding so
/// they always add up to the sale total.
/// ============================================
library;

double roundMoney(double value) => (value * 100).roundToDouble() / 100;

class CalcLine {
  final double unitPrice;
  final int quantity;

  /// Discount on the whole line (not per unit).
  final double discount;

  const CalcLine({
    required this.unitPrice,
    required this.quantity,
    this.discount = 0,
  });

  double get gross => roundMoney(unitPrice * quantity);

  /// Line discount can't exceed the line's value.
  double get clampedDiscount => discount.clamp(0, gross).toDouble();

  double get net => roundMoney(gross - clampedDiscount);
}

class SaleTotals {
  /// Σ quantity × unit price.
  final double grossSubtotal;

  /// Σ line discounts.
  final double lineDiscounts;

  /// Sale-level discount actually applied (clamped).
  final double saleDiscount;

  /// [grossSubtotal] − [lineDiscounts].
  final double subtotal;

  final double taxRate;
  final bool pricesIncludeTax;
  final double taxAmount;

  /// What the customer pays.
  final double total;

  /// The customer's payment for each line, in input order. Sums to [total].
  final List<double> lineTotals;

  /// Line discount + share of the sale discount, per line.
  final List<double> lineDiscountShares;

  const SaleTotals({
    required this.grossSubtotal,
    required this.lineDiscounts,
    required this.saleDiscount,
    required this.subtotal,
    required this.taxRate,
    required this.pricesIncludeTax,
    required this.taxAmount,
    required this.total,
    required this.lineTotals,
    required this.lineDiscountShares,
  });

  double get discountTotal => roundMoney(lineDiscounts + saleDiscount);
}

class SaleCalculator {
  SaleCalculator._();

  static SaleTotals calculate(
    List<CalcLine> lines, {
    double saleDiscount = 0,
    double taxRate = 0,
    bool pricesIncludeTax = true,
  }) {
    final gross = roundMoney(lines.fold(0.0, (s, l) => s + l.gross));
    final lineDiscounts =
        roundMoney(lines.fold(0.0, (s, l) => s + l.clampedDiscount));
    final subtotal = roundMoney(gross - lineDiscounts);
    final appliedSaleDiscount =
        roundMoney(saleDiscount.clamp(0, subtotal).toDouble());
    final taxable = roundMoney(subtotal - appliedSaleDiscount);
    final rate = taxRate < 0 ? 0.0 : taxRate;

    final double tax;
    final double total;
    if (pricesIncludeTax) {
      tax = roundMoney(taxable * rate / (100 + rate));
      total = taxable;
    } else {
      tax = roundMoney(taxable * rate / 100);
      total = roundMoney(taxable + tax);
    }

    // Share the sale discount and (exclusive) tax across lines in
    // proportion to each line's net value; the last line takes the
    // rounding remainder so the shares sum exactly.
    final lineTotals = <double>[];
    final discountShares = <double>[];
    var allocatedTotal = 0.0;
    var allocatedDiscount = 0.0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLast = i == lines.length - 1;
      final weight = subtotal > 0 ? line.net / subtotal : 0.0;

      final discountShare = isLast
          ? roundMoney(appliedSaleDiscount - allocatedDiscount)
          : roundMoney(appliedSaleDiscount * weight);
      final lineTotal = isLast
          ? roundMoney(total - allocatedTotal)
          : roundMoney(total * weight);

      allocatedDiscount = roundMoney(allocatedDiscount + discountShare);
      allocatedTotal = roundMoney(allocatedTotal + lineTotal);
      discountShares.add(roundMoney(line.clampedDiscount + discountShare));
      lineTotals.add(lineTotal);
    }

    return SaleTotals(
      grossSubtotal: gross,
      lineDiscounts: lineDiscounts,
      saleDiscount: appliedSaleDiscount,
      subtotal: subtotal,
      taxRate: rate,
      pricesIncludeTax: pricesIncludeTax,
      taxAmount: tax,
      total: total,
      lineTotals: lineTotals,
      lineDiscountShares: discountShares,
    );
  }

  /// Change due when [tendered] cash is handed over for [cashDue].
  /// Negative means the customer hasn't paid enough.
  static double changeDue({required double tendered, required double cashDue}) =>
      roundMoney(tendered - cashDue);
}
