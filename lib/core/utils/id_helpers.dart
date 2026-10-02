/// ============================================
/// ID Helpers — ShopPOS
/// ============================================
library;

import 'package:uuid/uuid.dart';

class IdHelpers {
  IdHelpers._();

  static const _uuid = Uuid();

  /// Random v4 UUID used as a record's stable, device-independent ID.
  static String newUuid() => _uuid.v4();
}
