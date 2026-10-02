/// ============================================
/// Sale Service — ShopPOS
/// ============================================
/// Completing, voiding and refunding sales. Each
/// operation runs in one Isar transaction, so a
/// failure part-way (e.g. stock ran out) leaves
/// nothing half-written.
/// ============================================
library;

import 'dart:convert';

import 'package:isar/isar.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/utils/id_helpers.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/stock_movement.dart';
import 'package:shop_pos/features/products/services/inventory_service.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/models/sale_item.dart';
import 'package:shop_pos/features/sales/services/sale_calculator.dart';
import 'package:shop_pos/features/shifts/services/shift_service.dart';

class SaleValidationException implements Exception {
  final String message;
  SaleValidationException(this.message);
  @override
  String toString() => message;
}

class CheckoutLine {
  final Product product;
  final int quantity;

  /// Discount on the whole line.
  final double discount;

  const CheckoutLine({
    required this.product,
    required this.quantity,
    this.discount = 0,
  });
}

/// A payment as entered at checkout.
class PaymentInput {
  final String method;
  final double amount;
  final String? reference;
  const PaymentInput(this.method, this.amount, {this.reference});
}

/// Tax settings applied to a sale.
class TaxConfig {
  final double rate;
  final bool pricesIncludeTax;
  const TaxConfig({this.rate = 0, this.pricesIncludeTax = true});
}

class SaleService {
  SaleService._();

  static const _tolerance = 0.005;

  static SaleTotals totalsFor(
    List<CheckoutLine> lines, {
    double saleDiscount = 0,
    TaxConfig tax = const TaxConfig(),
  }) =>
      SaleCalculator.calculate(
        [
          for (final l in lines)
            CalcLine(
                unitPrice: l.product.price,
                quantity: l.quantity,
                discount: l.discount),
        ],
        saleDiscount: saleDiscount,
        taxRate: tax.rate,
        pricesIncludeTax: tax.pricesIncludeTax,
      );

  /// Records a sale, takes the stock out (soonest expiry first) and links
  /// it to the cashier's open shift.
  ///
  /// [payments] must add up to the total. The cash payment's amount is the
  /// cash *kept*; [amountTendered] is what the customer handed over, from
  /// which change is worked out.
  ///
  /// With a [paystackReference] the call is idempotent: if that payment
  /// was already saved, the existing sale is returned unchanged. Because
  /// the customer has already paid by then, it is not refused for a
  /// signed-out user ([cashierId] attributes it instead).
  static Future<Sale> completeSale(
    Isar isar,
    AppUser? user, {
    required List<CheckoutLine> lines,
    required List<PaymentInput> payments,
    double saleDiscount = 0,
    TaxConfig tax = const TaxConfig(),
    double? amountTendered,
    String? paystackReference,
    String? momoProvider,
    String? momoPhone,
    int? cashierId,
  }) async {
    if (paystackReference != null) {
      final existing = await isar.sales
          .filter()
          .paystackReferenceEqualTo(paystackReference)
          .findFirst();
      if (existing != null) return existing;
    } else {
      Permissions.require(user, Permission.sell);
    }

    if (lines.isEmpty) throw SaleValidationException('The cart is empty.');
    if ((saleDiscount > 0 || lines.any((l) => l.discount > 0)) &&
        paystackReference == null) {
      Permissions.require(user, Permission.discount);
    }
    for (final l in lines) {
      if (l.quantity <= 0) {
        throw SaleValidationException('Invalid quantity for ${l.product.name}.');
      }
    }

    final totals = totalsFor(lines, saleDiscount: saleDiscount, tax: tax);
    final paid = roundMoney(payments.fold(0.0, (s, p) => s + p.amount));
    if (payments.any((p) => p.amount < 0)) {
      throw SaleValidationException('Payment amounts cannot be negative.');
    }
    if ((paid - totals.total).abs() > _tolerance) {
      throw SaleValidationException(
          'Payments (${paid.toStringAsFixed(2)}) must equal the total '
          '(${totals.total.toStringAsFixed(2)}).');
    }

    final cashDue = roundMoney(payments
        .where((p) => p.method == AppConstants.paymentCash)
        .fold(0.0, (s, p) => s + p.amount));
    var change = 0.0;
    if (amountTendered != null) {
      change = SaleCalculator.changeDue(tendered: amountTendered, cashDue: cashDue);
      if (change < -_tolerance) {
        throw SaleValidationException(
            'Cash tendered is less than the cash due (${cashDue.toStringAsFixed(2)}).');
      }
    }

    final staffId = cashierId ?? user?.id ?? 0;
    final shift = staffId > 0 ? await ShiftService.currentShift(isar, staffId) : null;
    final now = DateTime.now();
    final nonEmptyPayments = payments.where((p) => p.amount > 0).toList();

    final sale = Sale()
      ..uuid = IdHelpers.newUuid()
      ..timestamp = now
      ..updatedAt = now
      ..cashierId = staffId
      ..shiftId = shift?.id
      ..totalAmount = totals.total
      ..subtotal = totals.subtotal
      ..discountAmount = totals.discountTotal
      ..taxAmount = totals.taxAmount
      ..taxRate = totals.taxRate
      ..amountTendered = amountTendered
      ..changeDue = change < 0 ? 0 : change
      ..paymentType = nonEmptyPayments.length > 1
          ? AppConstants.paymentSplit
          : (nonEmptyPayments.isEmpty
              ? AppConstants.paymentCash
              : nonEmptyPayments.first.method)
      ..payments = [
        for (final p in nonEmptyPayments)
          SalePayment()
            ..method = p.method
            ..amount = roundMoney(p.amount)
            ..reference = p.reference,
      ]
      ..paystackReference = paystackReference
      ..momoProvider = momoProvider
      ..momoPhone = momoPhone
      ..itemsJson = jsonEncode([
        for (var i = 0; i < lines.length; i++)
          {
            'productId': lines[i].product.id,
            'productName': lines[i].product.name,
            'quantity': lines[i].quantity,
            'price': lines[i].product.price,
            'discount': totals.lineDiscountShares[i],
            'lineTotal': totals.lineTotals[i],
          }
      ]);

    await isar.writeTxn(() async {
      await isar.sales.put(sale);
      final items = <SaleItem>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        await InventoryService.deductFefoInTxn(
          isar,
          productId: line.product.id,
          productName: line.product.name,
          quantity: line.quantity,
          type: StockMovementType.sale,
          userId: staffId,
          saleId: sale.id,
          at: now,
        );
        items.add(SaleItem()
          ..uuid = IdHelpers.newUuid()
          ..saleId = sale.id
          ..productId = line.product.id
          ..productName = line.product.name
          ..quantity = line.quantity
          ..unitPrice = line.product.price
          ..unitCost = line.product.costPrice
          ..discount = totals.lineDiscountShares[i]
          ..lineTotal = totals.lineTotals[i]
          ..timestamp = now
          ..cashierId = staffId);
      }
      await isar.saleItems.putAll(items);
      await isar.activityLogs.put(ActivityLogService.entry(
          user,
          ActivityAction.sale,
          '${sale.receiptNumber} ${AppConstants.paymentLabel(sale.paymentType)} '
          '${sale.totalAmount.toStringAsFixed(2)}'));
    });
    return sale;
  }

  static Future<List<SaleItem>> itemsFor(Isar isar, int saleId) =>
      isar.saleItems.filter().saleIdEqualTo(saleId).findAll();

  /// Cancels a whole sale: all items go back to stock and the full amount
  /// is refunded by the way it was paid. Only for sales with no refunds.
  static Future<Sale> voidSale(
    Isar isar,
    AppUser? user, {
    required Sale sale,
    required String reason,
  }) async {
    Permissions.require(user, Permission.voidAndRefund);
    if (sale.status != SaleStatus.completed) {
      throw SaleValidationException(
          'Only a sale with no refunds can be voided; use Refund instead.');
    }
    if (reason.trim().isEmpty) {
      throw SaleValidationException('A reason is required to void a sale.');
    }

    final shift = await ShiftService.currentShift(isar, user!.id);
    final now = DateTime.now();
    final items = await itemsFor(isar, sale.id);

    await isar.writeTxn(() async {
      for (final item in items) {
        final qty = item.quantity - item.refundedQty;
        if (qty > 0) {
          await _returnToStockInTxn(isar,
              saleId: sale.id,
              productId: item.productId,
              quantity: qty,
              type: StockMovementType.voidSale,
              userId: user.id,
              note: reason);
        }
        item
          ..refundedQty = item.quantity
          ..refundedAmount = item.lineTotal;
      }
      await isar.saleItems.putAll(items);

      sale
        ..status = SaleStatus.voided
        ..refundedAmount = sale.totalAmount
        ..refunds = [
          ...sale.refunds,
          for (final p in sale.effectivePayments)
            SaleRefund()
              ..amount = p.amount
              ..method = p.method
              ..at = now
              ..userId = user.id
              ..shiftId = shift?.id
              ..reason = reason.trim(),
        ]
        ..statusReason = reason.trim()
        ..statusChangedAt = now
        ..statusChangedBy = user.id
        ..updatedAt = now
        ..isSynced = false;
      await isar.sales.put(sale);
      await isar.activityLogs.put(ActivityLogService.entry(user,
          ActivityAction.voidSale, '${sale.receiptNumber}: ${reason.trim()}'));
    });
    return sale;
  }

  /// Refunds some units of some lines. [quantities] maps SaleItem id to
  /// the number of units being returned. Returns the amount refunded.
  static Future<double> refund(
    Isar isar,
    AppUser? user, {
    required Sale sale,
    required Map<int, int> quantities,
    required String reason,
    String method = AppConstants.paymentCash,
    bool returnToStock = true,
  }) async {
    Permissions.require(user, Permission.voidAndRefund);
    if (sale.isVoided) throw SaleValidationException('This sale was voided.');
    if (reason.trim().isEmpty) {
      throw SaleValidationException('A reason is required for a refund.');
    }

    final items = await itemsFor(isar, sale.id);
    final byId = {for (final i in items) i.id: i};
    var amount = 0.0;
    for (final entry in quantities.entries) {
      final item = byId[entry.key];
      if (item == null) throw SaleValidationException('Unknown sale line.');
      final qty = entry.value;
      if (qty <= 0) continue;
      if (qty > item.quantity - item.refundedQty) {
        throw SaleValidationException(
            'Only ${item.quantity - item.refundedQty} of ${item.productName} can be refunded.');
      }
    }
    if (quantities.values.every((q) => q <= 0)) {
      throw SaleValidationException('Choose at least one item to refund.');
    }

    final shift = await ShiftService.currentShift(isar, user!.id);
    final now = DateTime.now();

    await isar.writeTxn(() async {
      for (final entry in quantities.entries) {
        final qty = entry.value;
        if (qty <= 0) continue;
        final item = byId[entry.key]!;
        final remainingAfter = item.quantity - item.refundedQty - qty;
        // The last units refunded take whatever is left of the line, so
        // rounding never refunds more or less than the customer paid.
        final lineRefund = remainingAfter == 0
            ? roundMoney(item.lineTotal - item.refundedAmount)
            : roundMoney(item.lineTotal * qty / item.quantity);
        amount = roundMoney(amount + lineRefund);
        item
          ..refundedQty += qty
          ..refundedAmount = roundMoney(item.refundedAmount + lineRefund);
        if (returnToStock) {
          await _returnToStockInTxn(isar,
              saleId: sale.id,
              productId: item.productId,
              quantity: qty,
              type: StockMovementType.refund,
              userId: user.id,
              note: reason);
        }
      }
      await isar.saleItems.putAll(items);

      final allReturned = items.every((i) => i.refundedQty >= i.quantity);
      sale
        ..refundedAmount = roundMoney(sale.refundedAmount + amount)
        ..status = allReturned ? SaleStatus.refunded : SaleStatus.partiallyRefunded
        ..refunds = [
          ...sale.refunds,
          SaleRefund()
            ..amount = amount
            ..method = method
            ..at = now
            ..userId = user.id
            ..shiftId = shift?.id
            ..reason = reason.trim(),
        ]
        ..statusReason = reason.trim()
        ..statusChangedAt = now
        ..statusChangedBy = user.id
        ..updatedAt = now
        ..isSynced = false;
      await isar.sales.put(sale);
      await isar.activityLogs.put(ActivityLogService.entry(
          user,
          ActivityAction.refund,
          '${sale.receiptNumber} ${amount.toStringAsFixed(2)}: ${reason.trim()}'
          '${returnToStock ? '' : ' (not restocked)'}'));
    });
    return amount;
  }

  /// Puts [quantity] units back into the batches this sale took them from,
  /// most recently taken first, net of anything already returned.
  static Future<void> _returnToStockInTxn(
    Isar isar, {
    required int saleId,
    required int productId,
    required int quantity,
    required String type,
    required int userId,
    String? note,
  }) async {
    final movements = await isar.stockMovements
        .filter()
        .saleIdEqualTo(saleId)
        .productIdEqualTo(productId)
        .findAll();

    // Net units still out per batch: taken by the sale minus returned.
    final outByBatch = <int?, int>{};
    for (final m in movements) {
      outByBatch[m.batchId] = (outByBatch[m.batchId] ?? 0) - m.quantityChange;
    }

    var remaining = quantity;
    for (final entry in outByBatch.entries.toList().reversed) {
      if (remaining == 0) break;
      if (entry.value <= 0) continue;
      final put = remaining < entry.value ? remaining : entry.value;
      await InventoryService.addToBatchInTxn(isar,
          productId: productId,
          quantity: put,
          type: type,
          userId: userId,
          batchId: entry.key,
          saleId: saleId,
          note: note);
      remaining -= put;
    }
    if (remaining > 0) {
      // Legacy sale with no movement records: add to the newest batch.
      await InventoryService.addToBatchInTxn(isar,
          productId: productId,
          quantity: remaining,
          type: type,
          userId: userId,
          saleId: saleId,
          note: note);
    }
  }
}
