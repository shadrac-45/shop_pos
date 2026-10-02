/// ============================================
/// Activity Log Service — ShopPOS
/// ============================================
library;

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';

class ActivityLogService {
  ActivityLogService._();

  /// Builds an entry without writing it, for callers already inside a
  /// write transaction (Isar transactions can't nest).
  static ActivityLog entry(
    AppUser? user,
    String action, [
    String details = '',
  ]) =>
      ActivityLog()
        ..userId = user?.id ?? 0
        ..userName = user?.name ?? 'System'
        ..action = action
        ..details = details
        ..timestamp = DateTime.now();

  /// Writes an entry in its own transaction. Never throws: a failed log
  /// write must not undo the action being logged.
  static Future<void> log(
    Isar isar,
    AppUser? user,
    String action, [
    String details = '',
  ]) async {
    try {
      await isar.writeTxn(
          () => isar.activityLogs.put(entry(user, action, details)));
    } catch (e) {
      debugPrint('[ActivityLog] Failed to write $action: $e');
    }
  }

  static Future<List<ActivityLog>> query(
    Isar isar, {
    required DateTime from,
    required DateTime to,
    int? userId,
  }) {
    final q = isar.activityLogs.filter().timestampBetween(from, to);
    return (userId == null ? q : q.userIdEqualTo(userId))
        .sortByTimestampDesc()
        .findAll();
  }
}
