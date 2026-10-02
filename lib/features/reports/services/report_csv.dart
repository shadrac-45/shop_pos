/// ============================================
/// Report CSV Export — ShopPOS
/// ============================================
/// Turns a [ReportSummary] into CSV text that
/// opens in Excel / Google Sheets.
/// ============================================
library;

import 'package:intl/intl.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/features/expenses/models/expense.dart';
import 'package:shop_pos/features/reports/services/report_service.dart';

class ReportCsv {
  ReportCsv._();

  static final _dateTime = DateFormat('yyyy-MM-dd HH:mm');
  static final _date = DateFormat('yyyy-MM-dd');

  /// Quotes a cell when it contains a comma, quote or line break.
  static String cell(Object? value) {
    final s = value == null
        ? ''
        : value is double
            ? value.toStringAsFixed(2)
            : value.toString();
    if (s.contains(RegExp('[",\r\n]'))) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _rows(List<List<Object?>> rows) =>
      '${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n';

  /// One CSV with three sections: summary, sales, products, expenses.
  static String build(ReportSummary r, {String storeName = ''}) {
    final names = {for (final c in r.cashiers) c.cashierId: c.name};
    final buffer = StringBuffer()
      ..write(_rows([
        ['ShopPOS report', storeName],
        ['Period', '${_date.format(r.range.start)} to ${_date.format(r.range.lastDay)}'],
        [],
        ['Summary', 'Amount'],
        ['Sales (count)', r.saleCount],
        ['Gross sales', r.grossSales],
        ['Discounts given', r.discounts],
        ['Refunds', r.refunds],
        ['Net sales', r.netSales],
        ['VAT', r.tax],
        ['Cost of goods', r.costOfGoods],
        ['Gross profit', r.grossProfit],
        ['Expenses', r.totalExpenses],
        ['Net profit', r.netProfit],
        ['Voided sales (count)', r.voidCount],
        ['Voided sales (amount)', r.voidedAmount],
        for (final e in r.byPaymentMethod.entries)
          ['Collected by ${AppConstants.paymentLabel(e.key)}', e.value],
        [],
        ['Sales'],
        [
          'Receipt', 'Date', 'Cashier', 'Status', 'Payment', 'Subtotal',
          'Discount', 'VAT', 'Total', 'Refunded', 'Net'
        ],
        for (final s in r.sales)
          [
            s.receiptNumber,
            _dateTime.format(s.timestamp),
            names[s.cashierId] ?? s.cashierId,
            s.status,
            AppConstants.paymentLabel(s.paymentType),
            s.effectiveSubtotal,
            s.discountAmount,
            s.taxAmount,
            s.totalAmount,
            s.refundedAmount,
            s.netAmount,
          ],
        [],
        ['Products'],
        ['Product', 'Units sold', 'Revenue', 'Cost', 'Profit'],
        for (final p in r.products)
          [p.productName, p.quantity, p.revenue, p.cost, p.profit],
        [],
        ['Expenses'],
        ['Date', 'Category', 'Description', 'From till', 'Amount'],
        for (final e in r.expenses)
          [
            _dateTime.format(e.timestamp),
            ExpenseCategory.label(e.category),
            e.description,
            e.paidFromTill ? 'yes' : 'no',
            e.amount,
          ],
      ]));
    return buffer.toString();
  }
}
