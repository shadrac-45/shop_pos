# ShopPOS — Offline-First Point of Sale System

A mobile-first POS system built with Flutter for small shops in emerging markets (Ghana, Nigeria, etc.). Designed to work **100% offline** on budget Android phones (Tecno, Infinix, Samsung A-series).

## 🚀 Features

- **PIN-based login** — Owner (1234) and Cashier (0000) roles
- **Quick-sale grid** — Colorful product buttons for fast cashier workflow
- **FEFO stock management** — First Expired, First Out batch tracking
- **Product & batch management** — Owner-only screens for inventory
- **Expiry alerts** — Color-coded indicators (green/orange/red)
- **Cash & MoMo payments** — Payment method tracking per sale
- **Dark mode** — High-contrast UI optimized for all lighting conditions
- **Fully offline** — Works for days without internet via Isar local DB

## 📱 Tech Stack

| Layer | Technology |
|-------|-----------|
| **Framework** | Flutter 3.24+ |
| **Database** | Isar (embedded, offline-first) |
| **State** | Riverpod 2.x (hooks_riverpod) |
| **Barcode** | mobile_scanner |
| **HTTP** | Dio (for future MongoDB sync) |
| **Crypto** | SHA-256 PIN hashing |

## 📁 Project Structure

```
lib/
├── core/
│   ├── constants/        # App constants (roles, currency, thresholds)
│   ├── extensions/       # BuildContext extensions
│   └── theme/            # AppColors + AppTheme (dark mode)
├── models/               # Isar collections
│   ├── product.dart      # Product with computed stock/expiry
│   ├── batch.dart        # FEFO batch tracking
│   ├── sale.dart         # Sale transactions (JSON items)
│   └── app_user.dart     # PIN-auth users with roles
├── providers/            # Riverpod state management
│   ├── database_provider.dart
│   ├── auth_provider.dart
│   ├── product_provider.dart
│   ├── cart_provider.dart
│   └── sales_provider.dart
├── features/
│   ├── auth/screens/     # Login screen (PIN keypad)
│   ├── sales/screens/    # Cashier sales screen
│   ├── products/screens/ # Owner product management
│   └── common/widgets/   # Checkout, Add Product, Restock dialogs
├── utils/                # Date, currency, sync helpers
└── main.dart             # App entry: Isar init, seeding, Riverpod
```

## 🛠️ Getting Started

### Prerequisites
- Flutter SDK 3.24+
- Android SDK
- A physical Android device or emulator

### Setup

```bash
# 1. Navigate to the project
cd shop_pos

# 2. Install dependencies
flutter pub get

# 3. Generate Isar schemas and Riverpod code
flutter pub run build_runner build --delete-conflicting-outputs

# 4. Download Inter font files (see assets/fonts/README.md)

# 5. Run the app
flutter run
```

### Default Login PINs
| Role | PIN | Access |
|------|-----|--------|
| Owner | `1234` | Product management, sales, full access |
| Cashier | `0000` | Sales screen only |

## 🏗️ Architecture

### Clean Architecture + MVVM
- **Models** — Isar collections with computed properties
- **Providers** — Riverpod for reactive state management
- **Screens** — ConsumerStatefulWidgets for UI
- **Services** — Business logic in provider service classes

### FEFO (First Expired, First Out)
When a sale is made, stock is deducted from the batch with the **earliest expiry date** first. This ensures perishable goods are sold before they expire.

### Offline-First Design
- All data stored in Isar (embedded NoSQL database)
- No network calls required for any operation
- Future sync to MongoDB via Dio (stub ready in `sync_helper.dart`)
- Sales marked with `isSynced` flag for eventual consistency

## 📊 Data Models

### Product
- Name, price, category, button color
- Computed: totalStock, soonestExpiry, daysUntilExpiry

### Batch
- Links to Product via productId
- Quantity, expiryDate, restockDate, supplierNote
- FEFO ordering by expiryDate

### Sale
- Timestamp, cashier info, total, payment type
- Items stored as JSON string for flexibility
- isSynced flag for future cloud sync

### AppUser
- SHA-256 hashed PIN (salted)
- Role-based access: "owner" or "cashier"

## 🎨 Design Philosophy

- **Large touch targets** — Minimum 48dp for all interactive elements
- **High contrast** — Dark theme with bright accents
- **Minimal text** — Icons + colors for rapid recognition
- **Haptic feedback** — Physical response on every tap
- **3-column grid** — Fits comfortably on 5" screens

## 🔮 Future Roadmap

- [ ] Barcode scanning with mobile_scanner
- [ ] MongoDB cloud sync via Dio
- [ ] Sales reports and analytics dashboard
- [ ] Multi-shop support
- [ ] Receipt printing (Bluetooth thermal)
- [ ] Product image support
- [ ] Inventory alerts and low-stock notifications

## 📄 License

MIT License — Free for commercial and personal use.
