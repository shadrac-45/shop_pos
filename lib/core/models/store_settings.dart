/// ============================================
/// StoreSettings — ShopPOS Isar Model
/// ============================================
/// Persists all first-run setup wizard data.
/// Only one record is ever created (id = 1).
/// ============================================
library;

import 'package:isar/isar.dart';

part 'store_settings.g.dart';

@Collection()
class StoreSettings {
  Id id = 1; // Singleton — always id=1

  // ── Store Profile ────────────────────────
  String storeName = '';
  String storePhone = '';
  String storeAddress = '';
  String? logoPath; // Absolute path to locally stored logo image

  // ── Tax & Currency ───────────────────────
  String currency = 'GHS'; // ISO currency code
  double vatRate = 0.0; // e.g. 12.5 for 12.5%
  String taxId = ''; // Optional TIN / VAT registration

  /// True when shelf prices already include VAT (tax is extracted from
  /// the total); false when VAT is added on top at checkout.
  bool pricesIncludeTax = true;

  // ── Receipts ─────────────────────────────
  String receiptFooter = 'Thank you for shopping with us!';

  // ── Payment Methods ──────────────────────
  bool enableCash = true;
  bool enableCard = true;
  bool enableMoMo = true;
  bool enableQr = false;

  // ── Hardware ─────────────────────────────
  bool printerEnabled = false;
  bool scannerEnabled = false;
  bool cashDrawerEnabled = false;

  // ── Backend (MoMo + cloud sync) ──────────
  /// Base URL of the ShopPOS backend, e.g. https://pos.example.com/api.
  /// Empty means not configured.
  String backendUrl = '';

  /// Shared secret sent to the backend's sync API.
  String syncApiKey = '';

  /// Identifies this device to the sync server.
  String deviceId = '';

  DateTime? lastSyncAt;
  DateTime? lastBackupAt;

  // ── Setup State ──────────────────────────
  /// True once the admin has completed the first-run setup wizard.
  bool setupCompleted = false;
}
