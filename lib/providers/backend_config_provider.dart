/// ============================================
/// Backend Config Provider — ShopPOS
/// ============================================
/// Provides state management for the Backend API Base URL,
/// allowing cashiers/owners to configure host LAN IP
/// for physical device testing.
/// ============================================
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Active Backend API Base URL provider.
/// Defaults to host machine LAN IP (10.68.171.116) or 10.0.2.2 for emulator.
final backendUrlProvider = StateProvider<String>((ref) {
  return 'http://10.68.171.116:3000/api';
});
