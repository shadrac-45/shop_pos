/// ============================================
/// Shift Provider — ShopPOS
/// ============================================
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/shifts/models/shift.dart';

/// The signed-in user's open shift, kept live.
final currentShiftProvider = StreamProvider.autoDispose<Shift?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);
  return ref
      .watch(isarProvider)
      .shifts
      .filter()
      .userIdEqualTo(user.id)
      .closedAtIsNull()
      .watch(fireImmediately: true)
      .map((list) => list.isEmpty ? null : list.first);
});
