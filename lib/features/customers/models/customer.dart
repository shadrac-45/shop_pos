/// ============================================
/// Customer — ShopPOS Isar Model
/// ============================================
/// A shop's customer. Shared with the shop's
/// other tills through cloud sync (newest edit
/// wins).
/// ============================================
library;

import 'package:isar/isar.dart';

part 'customer.g.dart';

@Collection()
class Customer {
  Id id = Isar.autoIncrement;

  /// Stable id across devices.
  @Index(unique: true, replace: false)
  String? uuid;

  @Index(caseSensitive: false)
  late String name;

  @Index()
  String? phone;

  String? email;
  String? notes;

  DateTime? updatedAt;

  /// Local user id of whoever last changed this record (sync sends it as
  /// that person).
  int? modifiedBy;

  bool isSynced = false;
}
