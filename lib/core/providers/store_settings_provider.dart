/// ============================================
/// StoreSettings Provider — ShopPOS
/// ============================================
/// The store's settings (profile, tax, payment
/// methods, hardware, backend), loaded once and
/// kept current as the owner edits them.
/// ============================================
library;

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/utils/currency_helpers.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/activity/services/activity_log_service.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/sales/services/sale_service.dart';

final storeSettingsProvider =
    NotifierProvider<StoreSettingsNotifier, StoreSettings>(
  StoreSettingsNotifier.new,
);

class StoreSettingsNotifier extends Notifier<StoreSettings> {
  @override
  StoreSettings build() {
    final settings =
        ref.watch(isarProvider).storeSettings.getSync(1) ?? StoreSettings();
    CurrencyHelpers.configure(settings.currency);
    return settings;
  }

  /// Applies [change] to the stored settings and saves them.
  /// Requires [Permission.manageSettings] unless [system] (internal
  /// bookkeeping such as recording the last sync time).
  Future<void> edit(
    void Function(StoreSettings s) change, {
    AppUser? user,
    bool system = false,
    String? logDetails,
  }) async {
    if (!system) Permissions.require(user, Permission.manageSettings);
    final isar = ref.read(isarProvider);
    await isar.writeTxn(() async {
      final current = await isar.storeSettings.get(1) ?? StoreSettings();
      change(current);
      await isar.storeSettings.put(current);
      if (!system) {
        await isar.activityLogs.put(ActivityLogService.entry(
            user, ActivityAction.settingsChanged, logDetails ?? ''));
      }
    });
    // A fresh instance, so listeners see a new state object.
    state = isar.storeSettings.getSync(1) ?? StoreSettings();
    CurrencyHelpers.configure(state.currency);
  }
}

/// VAT settings to apply at checkout.
final taxConfigProvider = Provider<TaxConfig>((ref) {
  final s = ref.watch(storeSettingsProvider);
  return TaxConfig(rate: s.vatRate, pricesIncludeTax: s.pricesIncludeTax);
});

/// Payment methods the store accepts, in checkout order.
final enabledPaymentMethodsProvider = Provider<List<String>>((ref) {
  final s = ref.watch(storeSettingsProvider);
  return [
    if (s.enableCash) AppConstants.paymentCash,
    if (s.enableMoMo) AppConstants.paymentMomo,
    if (s.enableCard) AppConstants.paymentCard,
    if (s.enableQr) AppConstants.paymentQr,
  ];
});

/// Backend base URL, or '' when none is configured. Debug builds fall
/// back to the emulator address so local development needs no setup.
final backendUrlProvider = Provider<String>((ref) {
  final url = ref.watch(storeSettingsProvider).backendUrl.trim();
  if (url.isNotEmpty) return url;
  return kDebugMode ? AppConstants.devBackendBaseUrl : '';
});
