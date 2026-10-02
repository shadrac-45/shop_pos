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
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/utils/id_helpers.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/auth/services/auth_service.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/stock_movement.dart';

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

  /// True when shelf prices already include VAT.
  bool pricesIncludeTax;

  // Step 3 — Payment methods
  bool enableCash;
  bool enableCard;
  bool enableMoMo;
  bool enableQr;

  // Step 4 — Staff
  /// The owner's own PIN for the PIN keypad (replaces the seeded default).
  String ownerPin;
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
    this.pricesIncludeTax = true,
    this.enableCash = true,
    this.enableCard = true,
    this.enableMoMo = true,
    this.enableQr = false,
    this.ownerPin = '',
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
    bool? pricesIncludeTax,
    bool? enableCash,
    bool? enableCard,
    bool? enableMoMo,
    bool? enableQr,
    String? ownerPin,
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
      pricesIncludeTax: pricesIncludeTax ?? this.pricesIncludeTax,
      enableCash: enableCash ?? this.enableCash,
      enableCard: enableCard ?? this.enableCard,
      enableMoMo: enableMoMo ?? this.enableMoMo,
      enableQr: enableQr ?? this.enableQr,
      ownerPin: ownerPin ?? this.ownerPin,
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
    if (index < 0 || index >= state.staff.length) return;
    final newList = [...state.staff]..removeAt(index);
    state = state.copyWith(staff: newList);
  }

  /// Removes [entry] (staff are optional, so the list may become empty).
  void removeStaffEntry(WizardStaffEntry entry) {
    state = state.copyWith(staff: [...state.staff]..remove(entry));
  }

  void updateStaff(int index, WizardStaffEntry entry) {
    final newList = [...state.staff];
    newList[index] = entry;
    state = state.copyWith(staff: newList);
  }

  static final _digits = RegExp(r'^\d+$');

  /// Why [pin] can't be used, or null. Shared by every PIN field.
  static String? pinProblem(String pin) {
    if (pin.isEmpty) return 'Enter a PIN.';
    if (!_digits.hasMatch(pin)) return 'Use digits only.';
    if (pin.length < AppConstants.minPinLength || pin.length > AppConstants.maxPinLength) {
      return 'Use ${AppConstants.minPinLength}–${AppConstants.maxPinLength} digits.';
    }
    if (AppConstants.defaultPins.contains(pin)) {
      return '$pin is a well-known default PIN. Choose another.';
    }
    return null;
  }

  /// Owner PIN step: [confirm] must repeat [pin].
  static String? ownerPinProblem(String pin, String confirm) =>
      pinProblem(pin) ?? (pin == confirm ? null : 'The two PINs don\'t match.');

  /// Per-field problems for each staff entry (null = fine). Entries left
  /// completely blank are skipped. Every PIN must differ from the owner's
  /// and from each other.
  List<StaffEntryErrors> staffErrors() {
    final s = state;
    final seen = <String, int>{s.ownerPin.trim(): -1};
    return [
      for (var i = 0; i < s.staff.length; i++)
        () {
          final name = s.staff[i].name.trim();
          final pin = s.staff[i].pin.trim();
          if (name.isEmpty && pin.isEmpty) return const StaffEntryErrors();
          String? pinError = pinProblem(pin);
          if (pinError == null) {
            final other = seen[pin];
            if (other != null) {
              pinError = other == -1
                  ? 'Same as your owner PIN. Every PIN must be different.'
                  : 'Same as staff member ${other + 1}. Every PIN must be different.';
            } else {
              seen[pin] = i;
            }
          }
          return StaffEntryErrors(
            name: name.isEmpty ? 'Enter a name, or clear the PIN to skip this person.' : null,
            pin: pinError,
          );
        }(),
    ];
  }

  /// First problem across the owner PIN and staff, for Finish.
  String? validateStaff() {
    final ownerProblem = pinProblem(state.ownerPin.trim());
    if (ownerProblem != null) return 'Owner PIN: $ownerProblem';
    final errors = staffErrors();
    for (var i = 0; i < errors.length; i++) {
      final e = errors[i];
      if (e.name != null || e.pin != null) {
        return 'Staff member ${i + 1}: ${e.name ?? e.pin}';
      }
    }
    return null;
  }

  /// Persist everything to Isar and mark setup as complete.
  Future<void> saveAndComplete() async {
    final problem = validateStaff();
    if (problem != null) throw StateError(problem);

    // Hash before the database transaction: bcrypt is slow on purpose.
    final ownerPinHash = await HashHelpers.hashPinAsync(state.ownerPin.trim());
    final adminPasswordHash = state.adminPassword.isEmpty
        ? null
        : await HashHelpers.hashPasswordAsync(state.adminPassword);
    final staffPinHashes = <WizardStaffEntry, String>{};
    for (final entry in state.staff) {
      if (entry.name.trim().isEmpty) continue;
      final pin = entry.pin.trim();
      // Also unique against accounts already on this device.
      final clash = await AuthService.findUserByPin(ref.read(isarProvider), pin);
      if (clash != null && clash.role != AppConstants.roleOwner) {
        throw StateError("${entry.name.trim()}'s PIN is already used by ${clash.name}.");
      }
      staffPinHashes[entry] = await HashHelpers.hashPinAsync(pin);
    }

    final isar = ref.read(isarProvider);
    final s = state;
    AppUser? owner;
    final now = DateTime.now();

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
        ..pricesIncludeTax = s.pricesIncludeTax
        ..taxId = s.taxId
        ..enableCash = s.enableCash
        ..enableCard = s.enableCard
        ..enableMoMo = s.enableMoMo
        ..enableQr = s.enableQr
        ..printerEnabled = s.printerEnabled
        ..scannerEnabled = s.scannerEnabled
        ..cashDrawerEnabled = s.cashDrawerEnabled
        ..setupCompleted = true;
      if (settings.deviceId.isEmpty) settings.deviceId = IdHelpers.newUuid();
      await isar.storeSettings.put(settings);

      // 2. Update or create admin owner account
      final allUsers = await isar.appUsers.where().findAll();
      owner = allUsers.where((u) => u.role == 'owner').firstOrNull;
      owner ??= AppUser()
        ..name = 'Shop Owner'
        ..role = 'owner'
        ..isActive = true
        ..uuid = IdHelpers.newUuid();
      owner!
        ..pinHash = ownerPinHash
        ..updatedAt = now;
      if (s.adminEmail.trim().isNotEmpty) {
        owner!.email = s.adminEmail.trim().toLowerCase();
      }
      if (adminPasswordHash != null) owner!.passwordHash = adminPasswordHash;
      await isar.appUsers.put(owner!);

      // 3. Create staff accounts (validated above: named, unique PINs).
      for (final entry in s.staff) {
        final trimmedName = entry.name.trim();
        final pinHash = staffPinHashes[entry];
        if (trimmedName.isEmpty || pinHash == null) continue;
        final staff = AppUser()
          ..name = trimmedName
          ..role = AppConstants.staffRoles.contains(entry.role)
              ? entry.role
              : AppConstants.roleCashier
          ..isActive = true
          ..pinHash = pinHash
          ..uuid = IdHelpers.newUuid()
          ..updatedAt = now;
        await isar.appUsers.put(staff);
      }

      // 4. Import products from CSV
      for (final row in s.importedProducts) {
        try {
          final price = double.tryParse(row['price'] ?? '') ?? 0.0;
          final qty = int.tryParse(row['quantity'] ?? '') ?? 0;
          final name = (row['name'] ?? '').trim();
          if (name.isEmpty) continue;
          final product = Product()
            ..name = name
            ..price = price
            ..category = row['category'] ?? 'Uncategorized'
            ..uuid = IdHelpers.newUuid()
            ..updatedAt = now;
          final productId = await isar.products.put(product);
          if (qty > 0) {
            final farFuture = now.add(const Duration(days: 3650));
            final batch = Batch()
              ..productId = productId
              ..quantity = qty
              ..expiryDate = farFuture
              ..restockDate = now
              ..uuid = IdHelpers.newUuid()
              ..updatedAt = now;
            await isar.batchs.put(batch);
            batch.product.value = product;
            await batch.product.save();
            await isar.stockMovements.put(StockMovement()
              ..uuid = IdHelpers.newUuid()
              ..productId = productId
              ..batchId = batch.id
              ..quantityChange = qty
              ..type = StockMovementType.import
              ..note = 'Setup wizard'
              ..timestamp = now);
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

/// Problems with one staff entry's fields (null = fine).
class StaffEntryErrors {
  final String? name;
  final String? pin;
  const StaffEntryErrors({this.name, this.pin});
  bool get isEmpty => name == null && pin == null;
}

final setupWizardProvider =
    NotifierProvider<SetupWizardNotifier, WizardState>(
  SetupWizardNotifier.new,
);
