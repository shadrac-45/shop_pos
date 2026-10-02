/// ============================================
/// Receipt Service — ShopPOS
/// ============================================
/// Builds a receipt for a sale, as data for the
/// on-screen receipt and as an 80 mm PDF that can
/// be printed (system print dialog, which reaches
/// Wi-Fi and many Bluetooth printers) or shared
/// (WhatsApp, email, SMS apps).
/// ============================================
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:isar/isar.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/models/sale_item.dart';
import 'package:shop_pos/features/sales/services/sale_service.dart';

class ReceiptLine {
  final String name;
  final int quantity;
  final double unitPrice;
  final double discount;
  final double total;
  final int refundedQty;

  const ReceiptLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.total,
    this.refundedQty = 0,
  });
}

class ReceiptData {
  final StoreSettings store;
  final Sale sale;
  final List<ReceiptLine> lines;
  final String cashierName;

  const ReceiptData({
    required this.store,
    required this.sale,
    required this.lines,
    required this.cashierName,
  });

  String get storeName =>
      store.storeName.trim().isEmpty ? AppConstants.appName : store.storeName.trim();

  static Future<ReceiptData> load(
      Isar isar, Sale sale, StoreSettings store) async {
    final items = await SaleService.itemsFor(isar, sale.id);
    final cashier = sale.cashierId > 0 ? await isar.appUsers.get(sale.cashierId) : null;
    return ReceiptData(
      store: store,
      sale: sale,
      lines: items.isNotEmpty ? items.map(_fromItem).toList() : _fromJson(sale),
      cashierName: cashier?.name ?? '—',
    );
  }

  static ReceiptLine _fromItem(SaleItem i) => ReceiptLine(
        name: i.productName,
        quantity: i.quantity,
        unitPrice: i.unitPrice,
        discount: i.discount,
        total: i.lineTotal,
        refundedQty: i.refundedQty,
      );

  /// Sales saved before sale lines existed only have the JSON blob.
  static List<ReceiptLine> _fromJson(Sale sale) {
    try {
      final decoded = SaleItemsJson.decode(sale.itemsJson);
      return [
        for (final m in decoded)
          ReceiptLine(
            name: m['productName'] as String? ?? 'Item',
            quantity: (m['quantity'] as num?)?.toInt() ?? 1,
            unitPrice: (m['price'] as num?)?.toDouble() ?? 0,
            discount: (m['discount'] as num?)?.toDouble() ?? 0,
            total: (m['lineTotal'] as num?)?.toDouble() ??
                ((m['price'] as num?)?.toDouble() ?? 0) *
                    ((m['quantity'] as num?)?.toInt() ?? 1),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }
}

class ReceiptService {
  ReceiptService._();

  static final _date = DateFormat('dd MMM yyyy, HH:mm');

  /// Amount with the currency code; the PDF's built-in font has no glyph
  /// for symbols such as ₵, so receipts always print the code.
  static String _money(double v) =>
      '${CurrencyHelpers.code} ${CurrencyHelpers.formatRaw(v)}';

  static Future<Uint8List> buildPdf(ReceiptData r) async {
    final doc = pw.Document(title: 'Receipt ${r.sale.receiptNumber}');
    final s = r.sale;
    const small = pw.TextStyle(fontSize: 8);
    final bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);

    pw.Widget row(String left, String right, {pw.TextStyle? style}) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(left, style: style ?? small),
            pw.Text(right, style: style ?? small),
          ],
        );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(10),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(r.storeName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          if (r.store.storeAddress.isNotEmpty)
            pw.Text(r.store.storeAddress, textAlign: pw.TextAlign.center, style: small),
          if (r.store.storePhone.isNotEmpty)
            pw.Text('Tel: ${r.store.storePhone}',
                textAlign: pw.TextAlign.center, style: small),
          if (r.store.taxId.isNotEmpty)
            pw.Text('TIN: ${r.store.taxId}',
                textAlign: pw.TextAlign.center, style: small),
          pw.SizedBox(height: 6),
          row('Receipt', s.receiptNumber),
          row('Date', _date.format(s.timestamp)),
          row('Cashier', r.cashierName),
          if (s.status != SaleStatus.completed)
            row('Status', s.status.replaceAll('_', ' ').toUpperCase(), style: bold),
          pw.Divider(thickness: 0.5),
          for (final l in r.lines) ...[
            pw.Text(l.name, style: bold),
            row('  ${l.quantity} x ${CurrencyHelpers.formatRaw(l.unitPrice)}'
                '${l.discount > 0 ? '  (-${CurrencyHelpers.formatRaw(l.discount)})' : ''}',
                CurrencyHelpers.formatRaw(l.total)),
            if (l.refundedQty > 0) row('  Returned: ${l.refundedQty}', ''),
          ],
          pw.Divider(thickness: 0.5),
          row('Subtotal', _money(s.effectiveSubtotal)),
          if (s.discountAmount > 0) row('Discount', '-${_money(s.discountAmount)}'),
          if (s.taxAmount > 0)
            row('VAT ${s.taxRate.toStringAsFixed(s.taxRate % 1 == 0 ? 0 : 1)}%'
                '${r.store.pricesIncludeTax ? ' (incl.)' : ''}',
                _money(s.taxAmount)),
          row('TOTAL', _money(s.totalAmount),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final p in s.effectivePayments)
            row('Paid by ${AppConstants.paymentLabel(p.method)}', _money(p.amount)),
          if (s.amountTendered != null) ...[
            row('Cash tendered', _money(s.amountTendered!)),
            row('Change', _money(s.changeDue)),
          ],
          if (s.refundedAmount > 0) row('Refunded', '-${_money(s.refundedAmount)}', style: bold),
          if (s.paystackReference != null) row('MoMo ref', s.paystackReference!),
          pw.SizedBox(height: 8),
          if (r.store.receiptFooter.isNotEmpty)
            pw.Text(r.store.receiptFooter, textAlign: pw.TextAlign.center, style: small),
        ],
      ),
    ));
    return doc.save();
  }
}

/// Decoding for [Sale.itemsJson].
class SaleItemsJson {
  SaleItemsJson._();

  static List<Map<String, dynamic>> decode(String json) => [
        for (final e in jsonDecode(json) as List) Map<String, dynamic>.from(e as Map)
      ];
}
