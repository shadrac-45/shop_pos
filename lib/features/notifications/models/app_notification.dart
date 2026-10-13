/// ============================================
/// AppNotification — ShopPOS Isar Model
/// ============================================
/// A notification kept on this device for one
/// person (copied from ShopPOS Cloud), so the
/// notification centre works offline too.
/// ============================================
library;

import 'package:isar/isar.dart';

part 'app_notification.g.dart';

@Collection()
class AppNotification {
  Id id = Isar.autoIncrement;

  /// The cloud notification id (one local copy per cloud notification).
  @Index(unique: true, replace: true)
  late String cloudId;

  /// Whose notification this is (AppUser.uuid): people sharing a till
  /// each see only their own.
  @Index()
  late String userUuid;

  String shopId = '';
  String shopName = '';
  String type = '';

  /// critical | warning | info
  String severity = 'info';
  String title = '';
  String body = '';

  @Index()
  late DateTime createdAt;

  /// Read on this device.
  bool read = false;

  /// Read here but not yet reported to the cloud (offline).
  bool readPendingUpload = false;
}
