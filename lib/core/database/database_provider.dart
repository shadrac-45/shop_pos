/// ============================================
/// Database Provider — Riverpod
/// ============================================
/// Provides the Isar database instance to the
/// entire app via Riverpod. The instance is
/// initialized in main.dart and overridden here.
/// ============================================
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';

/// Global Isar database provider.
/// This is overridden in main.dart with the actual instance.
final isarProvider = Provider<Isar>((ref) {
  throw UnimplementedError(
    'Isar must be initialized in main.dart and provided via override.',
  );
});
