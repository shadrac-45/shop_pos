library;

import 'package:flutter/material.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/theme/app_colors.dart';

enum ExpiryLevel { expired, urgent, warning, good, noStock }

class ExpiryHelpers {
  ExpiryHelpers._();

  /// Determine the expiry severity level from days remaining.
  static ExpiryLevel getLevel(int? daysUntilExpiry) {
    if (daysUntilExpiry == null) return ExpiryLevel.noStock;
    if (daysUntilExpiry <= 0) return ExpiryLevel.expired;
    if (daysUntilExpiry <= AppConstants.expiryUrgentDays) {
      return ExpiryLevel.urgent;
    }
    if (daysUntilExpiry <= AppConstants.expirySoonDays) {
      return ExpiryLevel.warning;
    }
    return ExpiryLevel.good;
  }

  /// Color for the expiry level indicator.
  static Color getColor(int? daysUntilExpiry) {
    switch (getLevel(daysUntilExpiry)) {
      case ExpiryLevel.expired:
      case ExpiryLevel.urgent:
        return AppColors.expiryUrgent;
      case ExpiryLevel.warning:
        return AppColors.expirySoon;
      case ExpiryLevel.good:
        return AppColors.expiryGood;
      case ExpiryLevel.noStock:
        return AppColors.textMuted;
    }
  }

  /// Icon for the expiry level.
  static IconData getIcon(int? daysUntilExpiry) {
    switch (getLevel(daysUntilExpiry)) {
      case ExpiryLevel.expired:
        return Icons.error_rounded;
      case ExpiryLevel.urgent:
        return Icons.warning_rounded;
      case ExpiryLevel.warning:
        return Icons.schedule_rounded;
      case ExpiryLevel.good:
        return Icons.check_circle_rounded;
      case ExpiryLevel.noStock:
        return Icons.inventory_2_outlined;
    }
  }

  /// Short chip text for the expiry badge on product cards.
  static String getChipText(int? daysUntilExpiry) {
    if (daysUntilExpiry == null) return 'No stock';
    if (daysUntilExpiry <= 0) return 'EXPIRED';
    return '${daysUntilExpiry}d';
  }

  /// Whether a product's soonest-expiry date makes it unsellable.
  static bool isSoonestBatchExpired(DateTime? soonestExpiry) {
    if (soonestExpiry == null) return false;
    return soonestExpiry.isBefore(DateTime.now());
  }
}
