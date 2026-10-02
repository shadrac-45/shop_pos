# ShopPOS — Offline-First Point of Sale System

A mobile-first POS system built with Flutter for small shops in emerging markets (Ghana, Nigeria, etc.). Designed to work **offline-first** on budget Android phones (Tecno, Infinix, Samsung A-series), with optional Paystack Ghana Mobile Money integration when a backend is reachable.

## 🚀 Features

### 🔐 Authentication & Security
- **Dual login modes** — Admin/Owner uses **Email + Password**; Cashiers/Staff use a **PIN keypad**
- **Role select screen** — Clean entry point for choosing between Admin and Staff login
- **Multi-role system** — `owner`, `cashier`, `manager`, and `stock_clerk` roles supported
- **SHA-256 hashed PINs** — Salted, domain-separated (`ShopPOS_Salt_2026_Ghana`), hashed with `compute()` offload to avoid UI jank
- **Session management** — Auto-logout after **15 minutes of inactivity** via `SessionManager`
- **Staff soft-deactivation** — Accounts can be deactivated without breaking historical sale records

### 🏪 First-Run Setup Wizard
- **6-step guided onboarding** for new stores:
  1. **Store Profile** — Name, phone, address
  2. **Tax & Currency** — Currency code, VAT rate, Tax/VAT ID
  3. **Payment Methods** — Toggle Cash, Card, Mobile Money, QR
  4. **Staff** — Add staff with name, role, and 4-digit PIN
  5. **Inventory** — Paste CSV to bulk-import initial stock
  6. **Hardware** — Toggle Printer, Barcode scanner, Cash drawer
- Setup state persisted as a singleton `StoreSettings` Isar record

### 🛒 Sales & Checkout
- **Quick-sale grid** — Colorful product buttons for fast cashier workflow
- **Barcode scanning** — Camera-based product lookup via `mobile_scanner`
- **Checkout flow** — Dedicated checkout screen with itemized cart
- **Split payments** — Cash, MoMo, and split payment support
- **Ghana MoMo payments** — Paystack-backed MoMo charge with live polling via a dedicated `MomoPaymentScreen`
- **Cashier sales history** — Dedicated history screen per cashier

### 📦 Inventory & Products
- **FEFO stock management** — First Expired, First Out batch tracking
- **Product & batch management** — Owner-only screens for full inventory control
- **Expiry alerts** — Color-coded indicators (green/orange/red): urgent <= 7 days, soon <= 30 days
- **Local push notifications** — Expiry alerts via `flutter_local_notifications`
- **CSV / Excel import** — Import products from `.csv`, `.xlsx`, `.xls` files; `.doc`, `.docx`, `.pdf` are detected and gracefully rejected
- **Invalid row export** — Download a report of rows that failed validation during import
- **Barcode & SKU fields** — Optional barcode and SKU on products; cost price tracking

### 📊 Reports
- **Daily sales reports** — Today totals, payment-method split (Cash / MoMo / Split), and itemized transaction history
- **Report filtering** — Filter by date range and payment type
- **KPI summaries** — Top products and aggregated revenue via `ReportAggregator`

### ⚙️ Settings
- **Store settings** — Owner can view and manage store profile
- **Staff management** — Owner-only: create, deactivate, and reset PINs for cashier/staff accounts
- **Change PIN** — Cashiers can update their own PIN
- **Developer debug screen** — Hidden behind a 5-tap easter egg on the version tile (debug builds only); configures backend URL for LAN/emulator testing

### 🎨 UI & UX
- **Dark mode** — High-contrast UI optimized for all lighting conditions
- **Responsive layout** — `AppBreakpoints` utility adapts UI for phones and tablets
- **Skeleton loaders** — `AppSkeleton` widget for graceful loading states
- **Empty states** — `AppEmptyState` widget for zero-data screens
- **Haptic feedback** — Physical response on every tap
- **Inter font** — Full weight range (100-900) bundled for crisp rendering on budget screens

### Offline-First
- All data stored in Isar (embedded NoSQL database)
- Cash sales require zero network connectivity
- `isSynced` flag on each `Sale` record tracks pending cloud sync
- `SyncHelper` logs unsynced sales for future cloud push

---

## 📱 Tech Stack

| Layer | Technology |
|-------|------------|
| **Framework** | Flutter (SDK `^3.3.0`, Flutter `>=3.19.0`) |
| **Database** | Isar 3.x (embedded, offline-first) |
| **State** | Riverpod 2.x (`hooks_riverpod`, `riverpod_annotation`) |
| **Barcode** | `mobile_scanner ^5.2.3` |
| **Notifications** | `flutter_local_notifications ^17.2.3` |
| **Connectivity** | `connectivity_plus ^6.0.5` |
| **HTTP / Payments** | `dio ^5.4.0` — proxied Paystack MoMo calls only |
| **Crypto** | `crypto ^3.0.5` — SHA-256 PIN and password hashing |
| **UUIDs** | `uuid ^4.4.0` — unique transaction references |
| **Preferences** | `shared_preferences ^2.5.5` — session timeout logging |
| **File Picking** | `file_picker ^13.1.0` — CSV/Excel product import |
| **Excel Parsing** | `excel ^4.0.6` — `.xlsx` / `.xls` import pipeline |
| **Archiving** | `archive ^3.6.1` — Excel file decompression |
| **Internationalisation** | `intl ^0.19.0` — date and currency formatting |
| **Fonts** | Inter (bundled via `assets/fonts/`) |
| **App Icon** | `flutter_launcher_icons ^0.14.3` |

---

## 📁 Project Structure

```
lib/
├── core/
│   ├── constants/
│   │   ├── app_constants.dart    # Roles, payment types, thresholds, MoMo config
│   │   └── app_assets.dart       # Asset path constants
│   ├── database/
│   │   └── database_provider.dart
│   ├── extensions/               # BuildContext extensions (snackbars, etc.)
│   ├── models/
│   │   └── store_settings.dart   # Isar singleton — persists setup wizard data
│   ├── providers/
│   │   └── store_settings_provider.dart
│   ├── responsive/
│   │   └── app_breakpoints.dart  # Tablet/phone layout breakpoints
│   ├── services/
│   │   ├── notification_service.dart   # Local expiry-alert notifications
│   │   └── session_manager.dart        # Inactivity timeout and auto-logout (15 min)
│   ├── theme/                    # AppColors + AppTheme (dark mode) + AppSpacing
│   └── utils/
│       ├── currency_helpers.dart
│       ├── date_helpers.dart
│       ├── expiry_helpers.dart
│       ├── hash_helpers.dart     # SHA-256 PIN and password hashing (with compute())
│       └── sync_helper.dart      # isSynced flag logger (placeholder for cloud push)
│
├── features/
│   ├── auth/
│   │   ├── models/
│   │   │   └── app_user.dart     # Isar user: roles, PIN hash, email+password
│   │   ├── providers/
│   │   │   └── auth_provider.dart
│   │   ├── screens/
│   │   │   ├── admin_login_screen.dart   # Email + password login for Owner/Admin
│   │   │   ├── login_screen.dart         # PIN keypad login for Staff
│   │   │   └── role_select_screen.dart   # Entry point: choose Admin or Staff
│   │   └── services/
│   │       ├── admin_auth_service.dart
│   │       └── auth_service.dart
│   │
│   ├── setup/
│   │   ├── providers/
│   │   │   └── setup_wizard_provider.dart
│   │   └── screens/
│   │       ├── setup_wizard_screen.dart   # 6-step first-run wizard
│   │       └── setup_complete_screen.dart
│   │
│   ├── sales/
│   │   ├── models/
│   │   │   ├── sale.dart                 # Isar sale record (items JSON, isSynced)
│   │   │   └── paystack_models.dart      # Transient charge and verify result models
│   │   ├── providers/
│   │   ├── screens/
│   │   │   ├── cashier_sales_screen.dart   # Quick-sale product grid
│   │   │   ├── checkout_screen.dart        # Cart review and payment selection
│   │   │   ├── momo_payment_screen.dart    # Paystack MoMo charge + polling UI
│   │   │   ├── cashier_history_screen.dart # Per-cashier transaction history
│   │   │   └── mobile_scanner_screen.dart  # Camera barcode scanner
│   │   ├── services/
│   │   │   ├── payment_gateway.dart        # Abstract PaymentGateway interface
│   │   │   └── paystack_service.dart       # Concrete Paystack MoMo implementation
│   │   └── widgets/
│   │       ├── checkout_bottom_sheet.dart
│   │       └── payment_option_button.dart
│   │
│   ├── products/
│   │   ├── models/
│   │   │   ├── product.dart    # Isar: name, price, barcode, SKU, cost price, color
│   │   │   └── batch.dart      # Isar: FEFO batch with expiryDate, quantity
│   │   ├── providers/
│   │   ├── screens/
│   │   │   └── owner_products_screen.dart
│   │   ├── services/
│   │   │   ├── csv_import_service.dart       # File picker + delegates to parser
│   │   │   ├── product_import_parser.dart    # CSV/Excel parse + numFmtId repair
│   │   │   └── invalid_rows_export.dart      # Export failed import rows
│   │   └── widgets/
│   │
│   ├── reports/
│   │   ├── providers/
│   │   ├── screens/
│   │   │   └── daily_report_screen.dart
│   │   └── services/
│   │       └── report_aggregator.dart
│   │
│   ├── settings/
│   │   ├── providers/
│   │   ├── screens/
│   │   │   ├── settings_screen.dart
│   │   │   ├── manage_staff_screen.dart
│   │   │   └── developer_debug_screen.dart  # Hidden (5-tap easter egg), debug only
│   │   └── widgets/
│   │
│   ├── main/
│   │   └── screens/
│   │       └── main_shell_screen.dart   # Bottom nav shell
│   │
│   └── shared/
│       └── widgets/
│           ├── touchable_card.dart
│           ├── app_skeleton.dart        # Skeleton loading placeholders
│           └── app_empty_state.dart     # Zero-data empty state widget
│
└── main.dart    # App entry: Isar init, seeding, Riverpod ProviderScope
```

---

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

### First Launch Flow
1. App checks `StoreSettings.setupCompleted`
2. If **not completed** → `RoleSelectScreen` → `AdminLoginScreen` → `SetupWizardScreen` (6-step wizard)
3. If **completed** → `RoleSelectScreen` → Admin (email + password) or Staff (PIN keypad)

### Login Credentials
| Role | Credential | Access |
|------|-----------|--------|
| Owner / Admin | Email + Password (set during setup wizard) | Full access |
| Cashier / Staff | 4-digit PIN (set during setup or by Owner) | Sales screen, personal history |

> Additional staff accounts can be created by the Owner from **Settings -> Manage Staff**.

---

## 🏗️ Architecture

### Clean Architecture + Feature-First Structure
- **Feature modules** (`auth`, `setup`, `sales`, `products`, `reports`, `settings`) are self-contained with their own models, providers, screens, services, and widgets
- **Core** holds shared utilities, database access, theme, and cross-cutting services
- **Providers** — Riverpod for reactive state management; code-generated via `riverpod_annotation` + `build_runner`
- **Services** — Business logic isolated in service classes
- **Interface segregation** — `PaymentGateway` abstract class decouples UI from the Paystack implementation

### Session Management
- `SessionManager` tracks user activity and triggers auto-logout after **15 minutes of inactivity**
- Timeout events are persisted to `SharedPreferences` for audit logging

### FEFO (First Expired, First Out)
When a sale is made, stock is deducted from the batch with the **earliest expiry date** first. This ensures perishable goods are sold before they expire.

### Offline-First Design
- All data stored in Isar (embedded NoSQL database)
- Cash sales require zero network connectivity
- Mobile Money sales call the Node/Express backend only when available
- `isSynced` flag on each `Sale` tracks sync state for future cloud push

### Paystack Ghana MoMo Integration
- Flutter calls a local Node/Express backend (`/api/momo/charge`, `/api/momo/verify/:reference`)
- The backend holds the Paystack secret key — it **never** lives in the Flutter app
- Supported providers: MTN (`mtn`), Vodafone (`vod`), AirtelTigo (`tgo`)
- Polling interval: **5 seconds**, timeout: **90 seconds**
- Backend URL configurable at runtime via the **Developer Debug screen** (debug builds only, 5-tap easter egg)

### Staff Management
- Roles: `owner`, `cashier`, `manager`, `stock_clerk`
- PIN uniqueness enforced in application code (not DB-level, to avoid Isar null-index collision bug)
- Email uniqueness for admin accounts also enforced in application code
- All PINs stored as SHA-256 hashes with domain-separated salt (`ShopPOS_Salt_2026_Ghana`)

### Product Import Pipeline
- Supports **CSV**, **XLSX**, and **XLS** via `file_picker`
- `ProductImportParser` handles full parse + Excel `numFmtId` repair pipeline
- Invalid rows can be exported as a CSV report
- Columns: `name`, `price`, `quantity`, `category`, (optional) `barcode`, `sku`, `costPrice`, `expiryDate`
- Word / PDF files are detected and shown a friendly error message

---

## 📊 Data Models

### StoreSettings (Singleton, id = 1)
- Store name, phone, address, logo path
- Currency code, VAT rate, Tax/VAT ID
- Payment method toggles (Cash, Card, MoMo, QR)
- Hardware toggles (Printer, Scanner, Cash drawer)
- `setupCompleted` flag

### AppUser
- SHA-256 hashed PIN (salted, domain-separated)
- Role: `owner`, `cashier`, `manager`, or `stock_clerk`
- Optional `email` + `passwordHash` for admin accounts
- Optional `username` for staff accounts
- `isActive` flag for soft-deactivation

### Product
- Name, price, category, button color
- Optional: barcode, SKU, cost price, logo path
- Computed: `totalStock`, `soonestExpiry`, `daysUntilExpiry`

### Batch
- Links to Product via `productId`
- Quantity, expiryDate, restockDate, supplierNote
- FEFO ordering by `expiryDate`

### Sale
- Timestamp, cashier info, total, payment type (`cash` / `momo` / `split`)
- Items stored as JSON string for flexibility
- `isSynced` flag for future cloud push
- `paystackReference` stored after successful MoMo verification

### PaystackChargeResult / PaystackVerifyResult (transient)
- Plain Dart classes — never persisted to Isar
- Represent HTTP responses from the Paystack proxy backend
- Status enums cover all gateway response states

---

## 🎨 Design Philosophy

- **Large touch targets** — Minimum 48dp for all interactive elements
- **High contrast** — Dark theme with bright accents
- **Minimal text** — Icons + colors for rapid recognition
- **Haptic feedback** — Physical response on every tap
- **3-column grid** — Fits comfortably on 5-inch screens
- **Responsive** — `AppBreakpoints` adapts layout for larger screens
- **Skeleton loaders** — Smooth loading states instead of abrupt content pop-in
- **Inter font** — Full weight range (100-900) bundled for crisp rendering on budget screens

---

## 🔮 Future Roadmap

- [ ] Real cloud sync (replace `SyncHelper` placeholder with actual HTTP push)
- [ ] Multi-shop support
- [ ] Receipt printing (Bluetooth thermal) — hardware toggle already in setup wizard
- [ ] Product image support (`logoPath` field already on `Product`)
- [ ] Low-stock alerts (not just expiry)
- [ ] Weekly / monthly analytics beyond the daily report
- [ ] Nigeria MoMo support (extend `PaymentGateway` interface)
- [ ] QR payment support (toggle already in setup wizard)
- [ ] Card payment support (toggle already in setup wizard)

---

## 📄 License

MIT License — Free for commercial and personal use.
