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

  /// Paired Bluetooth receipt printer (ESC/POS). Empty means print through
  /// the system print dialog instead.
  String printerAddress = '';
  String printerName = '';

  /// Paper roll width in mm: 58 or 80.
  int printerPaperMm = 58;

  // ── Payment server (Mobile Money) ────────
  /// Base URL of the payment server, e.g. https://pay.example.com/api.
  /// Empty means Mobile Money is not configured.
  String backendUrl = '';

  /// API key sent to the payment server as x-api-key. (Named before sync
  /// got its own server; kept so saved settings carry over.)
  String syncApiKey = '';

  // ── Cloud sync server (optional) ─────────
  /// Base URL of the sync server (backend/ in this repo), e.g.
  /// https://sync.example.com/api. Empty means sync is off.
  String syncServerUrl = '';

  /// API key for the sync server.
  String syncServerKey = '';

  /// Identifies this device to the sync server.
  String deviceId = '';

  // ── ShopPOS Cloud ────────────────────────
  /// Base URL of the ShopPOS cloud API, e.g. https://api.example.com/api.
  /// Empty means this till is not connected to the cloud. When connected,
  /// the cloud is used for both sync and Mobile Money.
  String cloudUrl = '';

  /// This till's device token (from the owner's cloud sign-in). Identifies
  /// the till and its shop; never a server secret.
  String cloudDeviceToken = '';

  String cloudShopId = '';
  String cloudShopName = '';

  /// Pull position in the cloud change feed.
  String cloudCursor = '';

  /// When the cloud shop settings were last applied here.
  DateTime? cloudShopUpdatedAt;

  String cloudBusinessId = '';

  /// This till's code in its shop (T1, T2, …), assigned by the cloud.
  String cloudDeviceCode = '';

  /// Last receipt number used on this till (with [cloudDeviceCode]).
  int receiptSeq = 0;

  /// What the last pull covered: 'full' (manager/owner) or 'limited'
  /// (cashier). A full-scope person signing in re-downloads everything.
  String cloudCursorScope = '';

  /// Shop settings changed on this till and not yet uploaded.
  bool settingsSynced = true;
  DateTime? settingsUpdatedAt;
  int? settingsModifiedBy;

  DateTime? lastSyncAt;
  DateTime? lastBackupAt;

  // ── Setup State ──────────────────────────
  /// True once the admin has completed the first-run setup wizard.
  bool setupCompleted = false;
}
