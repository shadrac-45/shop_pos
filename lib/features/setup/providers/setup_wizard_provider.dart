/// ============================================
/// SetupWizardProvider — ShopPOS
/// ============================================
/// Holds all in-memory state for the first-run
/// setup wizard and persists it on completion.
/// ============================================
library;

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/batch.dart';

// ── State ────────────────────────────────────────────────────────

class WizardStaffEntry {
  String name;
  String role; // 'cashier', 'manager', 'stock_clerk'
  String pin;
  WizardStaffEntry({this.name = '', this.role = 'cashier', this.pin = ''});
}

class WizardState {
  // Step 1 — Store profile
  String storeName;
  String storePhone;
  String storeAddress;
  String? logoPath;

  // Step 2 — Tax & currency
  String currency;
  double vatRate;
  String taxId;

  // Step 3 — Payment methods
  bool enableCash;
  bool enableCard;
  bool enableMoMo;
  bool enableQr;

  // Step 4 — Staff
  List<WizardStaffEntry> staff;

  // Step 5 — Inventory (CSV rows parsed)
  List<Map<String, String>> importedProducts;

  // Step 6 — Hardware
  bool printerEnabled;
  bool scannerEnabled;
  bool cashDrawerEnabled;

  // Admin credentials (set at wizard start after admin login)
  String adminEmail;
  String adminPassword;
  int adminUserId;

  WizardState({
    this.storeName = '',
    this.storePhone = '',
    this.storeAddress = '',
    this.logoPath,
    this.currency = 'GHS',
    this.vatRate = 0.0,
    this.taxId = '',
    this.enableCash = true,
    this.enableCard = true,
    this.enableMoMo = true,
    this.enableQr = false,
    List<WizardStaffEntry>? staff,
    List<Map<String, String>>? importedProducts,
    this.printerEnabled = false,
    this.scannerEnabled = false,
    this.cashDrawerEnabled = false,
    this.adminEmail = '',
    this.adminPassword = '',
    this.adminUserId = -1,
  })  : staff = staff ?? [WizardStaffEntry()],
        importedProducts = importedProducts ?? [];

  WizardState copyWith({
    String? storeName,
    String? storePhone,
    String? storeAddress,
    String? logoPath,
    String? currency,
    double? vatRate,
    String? taxId,
    bool? enableCash,
    bool? enableCard,
    bool? enableMoMo,
    bool? enableQr,
    List<WizardStaffEntry>? staff,
    List<Map<String, String>>? importedProducts,
    bool? printerEnabled,
    bool? scannerEnabled,
    bool? cashDrawerEnabled,
    String? adminEmail,
    String? adminPassword,
    int? adminUserId,
  }) {
    return WizardState(
      storeName: storeName ?? this.storeName,
      storePhone: storePhone ?? this.storePhone,
      storeAddress: storeAddress ?? this.storeAddress,
      logoPath: logoPath ?? this.logoPath,
      currency: currency ?? this.currency,
      vatRate: vatRate ?? this.vatRate,
      taxId: taxId ?? this.taxId,
      enableCash: enableCash ?? this.enableCash,
      enableCard: enableCard ?? this.enableCard,
      enableMoMo: enableMoMo ?? this.enableMoMo,
      enableQr: enableQr ?? this.enableQr,
      staff: staff ?? this.staff,
      importedProducts: importedProducts ?? this.importedProducts,
      printerEnabled: printerEnabled ?? this.printerEnabled,
      scannerEnabled: scannerEnabled ?? this.scannerEnabled,
      cashDrawerEnabled: cashDrawerEnabled ?? this.cashDrawerEnabled,
      adminEmail: adminEmail ?? this.adminEmail,
      adminPassword: adminPassword ?? this.adminPassword,
      adminUserId: adminUserId ?? this.adminUserId,
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────

class SetupWizardNotifier extends Notifier<WizardState> {
  @override
  WizardState build() => WizardState();

  void update(WizardState Function(WizardState) updater) {
    state = updater(state);
  }

  void addStaff() {
    final newList = [...state.staff, WizardStaffEntry()];
    state = state.copyWith(staff: newList);
  }

  void removeStaff(int index) {
    if (state.staff.length <= 1) return;
    final newList = [...state.staff]..removeAt(index);
    state = state.copyWith(staff: newList);
  }

  void updateStaff(int index, WizardStaffEntry entry) {
    final newList = [...state.staff];
    newList[index] = entry;
    state = state.copyWith(staff: newList);
  }

  /// Persist everything to Isar and mark setup as complete.
  Future<void> saveAndComplete() async {
    final isar = ref.read(isarProvider);
    final s = state;
    AppUser? owner;

    await isar.writeTxn(() async {
      // 1. Save StoreSettings
      final settings = await isar.storeSettings.get(1) ?? StoreSettings();
      settings
        ..storeName = s.storeName
        ..storePhone = s.storePhone
        ..storeAddress = s.storeAddress
        ..logoPath = s.logoPath
        ..currency = s.currency
        ..vatRate = s.vatRate
        ..taxId = s.taxId
        ..enableCash = s.enableCash
        ..enableCard = s.enableCard
        ..enableMoMo = s.enableMoMo
        ..enableQr = s.enableQr
        ..printerEnabled = s.printerEnabled
        ..scannerEnabled = s.scannerEnabled
        ..cashDrawerEnabled = s.cashDrawerEnabled
        ..setupCompleted = true;
      await isar.storeSettings.put(settings);

      // 2. Update or create admin owner account
      final allUsers = await isar.appUsers.where().findAll();
      owner = allUsers.where((u) => u.role == 'owner').firstOrNull;
      owner ??= AppUser()
        ..name = 'Shop Owner'
        ..role = 'owner'
        ..isActive = true
        ..pinHash = HashHelpers.hashPin('1234');
      if (s.adminEmail.trim().isNotEmpty) {
        owner!.email = s.adminEmail.trim().toLowerCase();
      }
      if (s.adminPassword.isNotEmpty) {
        owner!.passwordHash = HashHelpers.hashPassword(s.adminPassword);
      }
      await isar.appUsers.put(owner!);

      // 3. Create staff accounts
      for (final entry in s.staff) {
        final trimmedName = entry.name.trim();
        final trimmedPin = entry.pin.trim();
        if (trimmedName.isEmpty || trimmedPin.length != 4) continue;
        final staff = AppUser()
          ..name = trimmedName
          ..role = entry.role
          ..isActive = true
          ..pinHash = HashHelpers.hashPin(trimmedPin);
        await isar.appUsers.put(staff);
      }

      // 4. Import products from CSV
      for (final row in s.importedProducts) {
        try {
          final price = double.tryParse(row['price'] ?? '') ?? 0.0;
          final qty = int.tryParse(row['quantity'] ?? '') ?? 0;
          final product = Product()
            ..name = row['name'] ?? ''
            ..price = price
            ..category = row['category'] ?? 'Uncategorized';
          final productId = await isar.products.put(product);
          if (qty > 0) {
            final farFuture = DateTime.now().add(const Duration(days: 3650));
            final batch = Batch()
              ..productId = productId
              ..quantity = qty
              ..expiryDate = farFuture
              ..restockDate = DateTime.now();
            await isar.batchs.put(batch);
            batch.product.value = product;
            await batch.product.save();
          }
        } catch (e) {
          debugPrint('[Wizard] Failed to import product row: $row — $e');
        }
      }
    });

    // 5. Establish owner session so the user lands on the admin dashboard
    if (owner != null) {
      ref.read(currentUserProvider.notifier).setUser(owner!);
    }
  }
}

final setupWizardProvider =
    NotifierProvider<SetupWizardNotifier, WizardState>(
  SetupWizardNotifier.new,
);
