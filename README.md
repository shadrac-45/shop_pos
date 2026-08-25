# ShopPOS — Offline-First Point of Sale System

A mobile-first POS system built with Flutter for small shops in emerging markets (Ghana, Nigeria, etc.). Designed to work **offline-first** on budget Android phones (Tecno, Infinix, Samsung A-series), with optional Paystack Ghana Mobile Money integration when a backend is reachable.

## 🚀 Features

- **PIN-based login** — Owner and multi-Cashier roles; all PINs hashed with SHA-256
- **Staff management** — Owner can create, deactivate, and reset PINs for cashier accounts
- **Quick-sale grid** — Colorful product buttons for fast cashier workflow
- **Barcode scanning** — Camera-based product lookup via `mobile_scanner`
- **FEFO stock management** — First Expired, First Out batch tracking
- **Product & batch management** — Owner-only screens for inventory
- **Expiry alerts** — Color-coded indicators (green/orange/red) plus local push notifications for soon-to-expire stock
- **Daily sales reports** — Today's totals, payment-method split, and itemized transaction history
- **Cash & MoMo payments** — Cash payments work fully offline; Ghana MoMo charges routed through a Paystack-backed Node/Express proxy
- **Paystack Ghana MoMo** — Live charge + polling verification via `PaystackService`; secret key never touches the Flutter app
- **Settings screen** — Cashier profile card, Change PIN, Manage Staff (owner-only), and app info
- **Developer debug screen** — Hidden behind a 5-tap easter egg on the version tile (debug builds only); configures backend URL for LAN testing
- **Dark mode** — High-contrast UI optimized for all lighting conditions
- **Offline-first** — All data stored in Isar; `isSynced` flag tracks unsynced sales for future cloud push

## 📱 Tech Stack

| Layer | Technology |
|-------|-----------|
| **Framework** | Flutter (SDK `^3.3.0`, Flutter `>=3.19.0`) |
| **Database** | Isar 3.x (embedded, offline-first) |
| **State** | Riverpod 2.x (`hooks_riverpod`, `riverpod_annotation`) |
| **Barcode** | `mobile_scanner ^5.2.3` |
| **Notifications** | `flutter_local_notifications ^17.2.3` |
| **Connectivity** | `connectivity_plus ^6.0.5` |
| **HTTP / Payments** | `dio ^5.4.0` — proxied Paystack MoMo calls only |
| **Crypto** | `crypto ^3.0.5` — SHA-256 PIN & password hashing |
| **UUIDs** | `uuid ^4.4.0` — unique transaction references |
| **Fonts** | Inter (bundled via `assets/fonts/`) |
| **App Icon** | `flutter_launcher_icons ^0.14.3` |

## 📁 Project Structure

```
lib/
├── core/
│   ├── constants/        # App constants (roles, currency, thresholds, MoMo config)
│   ├── extensions/       # BuildContext extensions (snackbars, etc.)
│   └── theme/            # AppColors + AppTheme (dark mode) + AppSpacing
├── models/               # Isar collections + transient models
│   ├── product.dart      # Product with computed stock/expiry
│   ├── batch.dart        # FEFO batch tracking
│   ├── sale.dart         # Sale transactions (JSON items, isSynced flag)
│   ├── app_user.dart     # PIN-auth users with roles (owner / cashier)
│   └── paystack_models.dart  # Transient charge & verify result models (non-Isar)
├── providers/            # Riverpod state management
│   ├── database_provider.dart
│   ├── auth_provider.dart
│   ├── product_provider.dart
│   ├── cart_provider.dart
│   ├── sales_provider.dart    # Report filter + KPI + top-products providers
│   ├── report_provider.dart   # Daily sales report state
│   ├── staff_provider.dart    # Owner-only cashier CRUD (create/deactivate/reset PIN)
│   ├── notification_provider.dart  # Local expiry-alert notifications
│   └── backend_config_provider.dart  # Configurable backend URL (LAN / emulator)
├── services/
│   ├── auth_service.dart       # PIN hashing helpers (delegates to HashHelpers)
│   ├── payment_gateway.dart    # Abstract PaymentGateway interface
│   ├── paystack_service.dart   # Concrete Paystack MoMo implementation (Dio)
│   └── report_aggregator.dart  # Daily/filtered sales aggregation logic
├── features/
│   ├── auth/screens/      # Login screen (PIN keypad)
│   ├── sales/screens/     # Cashier sales screen + checkout
│   ├── products/screens/  # Owner product management
│   ├── reports/screens/   # Daily report screen
│   ├── settings/
│   │   ├── screens/       # Settings screen, Manage Staff screen, Developer Debug screen
│   │   └── widgets/       # Add Cashier dialog, Change PIN dialog
│   ├── main/screens/      # Main app shell / navigation
│   └── common/widgets/    # Checkout, Add Product, Restock dialogs, TouchableCard
├── utils/
│   ├── currency_helpers.dart
│   ├── date_helpers.dart
│   ├── expiry_helpers.dart
│   ├── hash_helpers.dart  # SHA-256 PIN & password hashing (with compute() offload)
│   └── sync_helper.dart   # isSynced flag logger (placeholder for real cloud push)
└── main.dart              # App entry: Isar init, seeding, Riverpod
```

## 🛠️ Getting Started

### Prerequisites
- Flutter SDK `>=3.19.0` (tested on 3.19+)
- Android SDK (min SDK 21)
- A physical Android device or emulator

### Setup

```bash
# 1. Navigate to the project
cd shop_pos

# 2. Install dependencies
flutter pub get

# 3. Generate Isar schemas and Riverpod code
flutter pub run build_runner build --delete-conflicting-outputs

# 4. Run the app
flutter run
```

> **Fonts**: Inter font files must be present under `assets/fonts/`. See `assets/fonts/README.md` if they are missing.

### Default Login PINs
| Role | PIN | Access |
|------|-----|--------|
| Owner | `1234` | Product management, staff management, sales, reports, full access |
| Cashier | `0000` | Sales screen only |

> Additional cashier accounts can be created by the Owner from **Settings → Manage Staff**.

## 🏗️ Architecture

### Clean Architecture + MVVM
- **Models** — Isar collections with computed properties; `paystack_models.dart` holds transient (non-persisted) payment result types
- **Providers** — Riverpod for reactive state management; `riverpod_annotation` + `build_runner` for code generation
- **Services** — Business logic isolated in service classes (`PaystackService`, `ReportAggregator`, `StaffService`)
- **Screens** — `ConsumerStatefulWidget` / `ConsumerWidget` for UI
- **Interface segregation** — `PaymentGateway` abstract class decouples the UI from the concrete Paystack implementation

### FEFO (First Expired, First Out)
When a sale is made, stock is deducted from the batch with the **earliest expiry date** first. This ensures perishable goods are sold before they expire.

### Offline-First Design
- All data stored in Isar (embedded NoSQL database)
- Cash sales require zero network connectivity
- Mobile Money sales call the Node/Express backend only when available
- `SyncHelper` in `sync_helper.dart` logs pending sales for eventual cloud push; the `isSynced` flag on each `Sale` record tracks sync state

### Paystack Ghana MoMo Integration
- Flutter calls a local Node/Express backend (`/api/momo/charge`, `/api/momo/verify/:reference`)
- The backend holds the Paystack secret key — it **never** lives in the Flutter app
- `PaystackService` initiates charges and polls for confirmation using `uuid`-generated references
- Backend URL is configurable at runtime via **Developer Debug screen** (debug builds only, unlocked with a 5-tap easter egg on the version tile in Settings)

### Staff Management
- Owner creates cashier accounts with a name and a 4–6 digit unique PIN
- PIN uniqueness is enforced globally across all accounts before storage
- Cashier accounts can be deactivated (soft-delete) without breaking historical sale records
- Owner can reset any cashier's PIN at any time
- All PINs stored as SHA-256 hashes with a domain-separated salt (`ShopPOS_Salt_2026_Ghana`)
- `HashHelpers.hashPinAsync()` offloads hashing to a background isolate via `compute()` to avoid UI jank

## 📊 Data Models

### Product
- Name, price, category, button color
- Computed: `totalStock`, `soonestExpiry`, `daysUntilExpiry`

### Batch
- Links to Product via `productId`
- Quantity, expiryDate, restockDate, supplierNote
- FEFO ordering by `expiryDate`

### Sale
- Timestamp, cashier info, total, payment type (`cash` / `momo`)
- Items stored as JSON string for flexibility
- `isSynced` flag for future cloud push
- `paystackReference` stored after a successful MoMo verification

### AppUser
- SHA-256 hashed PIN (salted, domain-separated)
- Role-based access: `"owner"` or `"cashier"`
- `isActive` flag for soft-deactivation

### PaystackChargeResult / PaystackVerifyResult *(transient)*
- Plain Dart classes — never persisted to Isar
- Represent HTTP responses from the Paystack proxy backend
- `PaystackChargeStatus` and `PaystackVerifyStatus` enums cover all gateway response states

## 🎨 Design Philosophy

- **Large touch targets** — Minimum 48dp for all interactive elements
- **High contrast** — Dark theme with bright accents
- **Minimal text** — Icons + colors for rapid recognition
- **Haptic feedback** — Physical response on every tap
- **3-column grid** — Fits comfortably on 5" screens
- **Inter font** — Full weight range (100–900) bundled for crisp rendering on budget screens

## 🔮 Future Roadmap

- [ ] Real cloud sync (replace `SyncHelper` placeholder with actual HTTP push)
- [ ] Multi-shop support
- [ ] Receipt printing (Bluetooth thermal)
- [ ] Product image support
- [ ] Low-stock (not just expiry) alerts
- [ ] Weekly / monthly analytics beyond the daily report
- [ ] Nigeria MoMo support (extend `PaymentGateway` interface)

## 📄 License

MIT License — Free for commercial and personal use.
