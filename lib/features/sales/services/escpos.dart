/// ============================================
/// ESC/POS Encoder — ShopPOS
/// ============================================
/// Builds the raw bytes most thermal receipt
/// printers understand: text, alignment, bold,
/// double size, paper cut and the cash-drawer
/// pulse (the drawer is wired to the printer).
///
/// Text is sent as plain ASCII: characters the
/// printer's code page may not have (₵, ₦, …)
/// are replaced, so receipts print the currency
/// code instead of the symbol.
/// ============================================
library;

import 'dart:typed_data';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/services/receipt_service.dart';

enum EscPosAlign { left, center, right }

class EscPosBuilder {
  /// Characters per line at normal size: 32 on 58 mm paper, 48 on 80 mm.
  final int width;
  final _bytes = BytesBuilder();

  EscPosBuilder({int paperMm = 58}) : width = paperMm >= 80 ? 48 : 32 {
    _bytes.add([0x1B, 0x40]); // ESC @ — reset
  }

  /// Replaces anything outside printable ASCII.
  static String toAscii(String s) {
    const replacements = {
      '₵': 'GHS', '₦': 'NGN', '€': 'EUR', '£': 'GBP', '−': '-', '–': '-', '—': '-',
      '×': 'x', '‘': "'", '’': "'", '“': '"', '”': '"', '…': '...',
    };
    final out = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      if (replacements.containsKey(ch)) {
        out.write(replacements[ch]);
      } else if (rune >= 0x20 && rune < 0x7F) {
        out.write(ch);
      } else if (rune == 0x0A) {
        out.write('\n');
      } else {
        out.write('?');
      }
    }
    return out.toString();
  }

  void align(EscPosAlign a) => _bytes.add([0x1B, 0x61, a.index]);
  void bold(bool on) => _bytes.add([0x1B, 0x45, on ? 1 : 0]);

  /// Double width and height (headings, totals).
  void large(bool on) => _bytes.add([0x1D, 0x21, on ? 0x11 : 0x00]);

  void text(String s) => _bytes.add(toAscii(s).codeUnits);
  void line([String s = '']) => text('$s\n');

  /// [left] and [right] on one line, wrapping [left] if needed.
  void row(String left, String right, {int? lineWidth}) {
    final w = lineWidth ?? width;
    final l = toAscii(left);
    final r = toAscii(right);
    if (l.length + r.length + 1 <= w) {
      line('$l${' ' * (w - l.length - r.length)}$r');
    } else {
      for (final chunk in wrap(l, w)) {
        line(chunk);
      }
      line(r.padLeft(w));
    }
  }

  void divider() => line('-' * width);
  void feed([int lines = 1]) => _bytes.add([0x1B, 0x64, lines]);

  /// Feeds paper past the cutter and cuts (ignored by printers without one).
  void cut() {
    feed(3);
    _bytes.add([0x1D, 0x56, 0x42, 0x00]);
  }

  /// Pulses the cash-drawer port (pin 2): ESC p 0 25 250.
  void openDrawer() => _bytes.add([0x1B, 0x70, 0x00, 0x19, 0xFA]);

  Uint8List build() => _bytes.toBytes();

  static List<String> wrap(String s, int w) {
    final words = s.split(' ');
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      if (word.length > w) {
        if (current.isNotEmpty) lines.add(current);
        for (var i = 0; i < word.length; i += w) {
          lines.add(word.substring(i, (i + w).clamp(0, word.length)));
        }
        current = '';
        continue;
      }
      final next = current.isEmpty ? word : '$current $word';
      if (next.length > w) {
        lines.add(current);
        current = word;
      } else {
        current = next;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }
}

class EscPosReceipt {
  EscPosReceipt._();

  static String _money(double v) => CurrencyHelpers.formatRaw(v);

  /// The receipt for [r]. [openDrawer] adds the drawer pulse first, so the
  /// drawer opens while the receipt prints.
  static Uint8List build(ReceiptData r, {int paperMm = 58, bool openDrawer = false}) {
    final p = EscPosBuilder(paperMm: paperMm);
    final s = r.sale;
    if (openDrawer) p.openDrawer();

    p
      ..align(EscPosAlign.center)
      ..bold(true)
      ..large(true)
      ..line(r.storeName)
      ..large(false)
      ..bold(false);
    if (r.store.storeAddress.isNotEmpty) p.line(r.store.storeAddress);
    if (r.store.storePhone.isNotEmpty) p.line('Tel: ${r.store.storePhone}');
    if (r.store.taxId.isNotEmpty) p.line('TIN: ${r.store.taxId}');
    p
      ..align(EscPosAlign.left)
      ..divider()
      ..row('Receipt', s.receiptNumber)
      ..row('Date', _date(s.timestamp))
      ..row('Cashier', r.cashierName);
    if (s.status != SaleStatus.completed) {
      p
        ..bold(true)
        ..row('Status', s.status.replaceAll('_', ' ').toUpperCase())
        ..bold(false);
    }
    p.divider();

    for (final l in r.lines) {
      p
        ..bold(true)
        ..line(l.name.length > p.width ? l.name.substring(0, p.width) : l.name)
        ..bold(false)
        ..row('  ${l.quantity} x ${_money(l.unitPrice)}'
            '${l.discount > 0 ? ' -${_money(l.discount)}' : ''}', _money(l.total));
      if (l.refundedQty > 0) p.line('  Returned: ${l.refundedQty}');
    }

    p
      ..divider()
      ..row('Subtotal', _money(s.effectiveSubtotal));
    if (s.discountAmount > 0) p.row('Discount', '-${_money(s.discountAmount)}');
    if (s.taxAmount > 0) {
      p.row('VAT ${_rate(s.taxRate)}%${r.store.pricesIncludeTax ? ' incl.' : ''}',
          _money(s.taxAmount));
    }
    p
      ..bold(true)
      ..row('TOTAL ${CurrencyHelpers.code}', _money(s.totalAmount))
      ..bold(false);
    for (final pay in s.effectivePayments) {
      p.row(AppConstants.paymentLabel(pay.method), _money(pay.amount));
    }
    if (s.amountTendered != null) {
      p
        ..row('Cash tendered', _money(s.amountTendered!))
        ..row('Change', _money(s.changeDue));
    }
    if (s.refundedAmount > 0) p.row('Refunded', '-${_money(s.refundedAmount)}');
    if (s.paystackReference != null) {
      p
        ..line('MoMo ref:')
        ..line(s.paystackReference!);
    }
    if (r.store.receiptFooter.isNotEmpty) {
      p
        ..feed()
        ..align(EscPosAlign.center)
        ..line(r.store.receiptFooter);
    }
    p.cut();
    return p.build();
  }

  /// A short page to check the printer works and paper width is right.
  static Uint8List testPage({required String storeName, int paperMm = 58}) {
    final p = EscPosBuilder(paperMm: paperMm)
      ..align(EscPosAlign.center)
      ..bold(true)
      ..line(storeName.isEmpty ? AppConstants.appName : storeName)
      ..bold(false)
      ..line('Printer test')
      ..line('$paperMm mm paper')
      ..align(EscPosAlign.left)
      ..divider()
      ..row('Left', 'Right')
      ..divider();
    p.cut();
    return p.build();
  }

  static String _rate(double r) => r % 1 == 0 ? r.toInt().toString() : r.toString();

  static String _date(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}
