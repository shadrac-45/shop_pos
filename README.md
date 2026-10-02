# ShopPOS — Offline-First Point of Sale

A Flutter point-of-sale app for small shops in Ghana and similar markets. It runs fully offline on
budget Android phones. Mobile Money (Paystack) and cloud sync work through a small backend in
[`backend/`](backend/README.md) whenever it is reachable.

**Version 1.3.0**

## Features

### Selling
- Quick-tap product grid, search, and barcode or SKU scanning
- Quantities limited by real sellable stock across all unexpired batches
- **Discounts** per line and per sale (owner and manager only)
- **VAT**: prices can include it (extracted and shown on the receipt) or have it added at checkout
- **Payments**: cash, Mobile Money (Paystack), card and QR (recorded after the card machine or QR
  app takes the payment). Each method can be turned on or off. Payments can be split across methods.
- **Cash received and change due**, with quick note buttons
- **Receipts** after every sale and from history: print on a paired **Bluetooth ESC/POS thermal
  printer** (58 or 80 mm), or through the Android print dialog, or share as PDF (WhatsApp, email,
  SMS apps). A **cash drawer** plugged into the printer opens on cash sales.
- **Void** a whole sale or **refund** chosen items, by cash or the original method. Items go back
  to the batches they came from, or are left out of stock if damaged.
- MoMo safety: a timed-out charge is re-checked instead of charged again. Every charge is tracked
  until it resolves, and **Pending MoMo Payments** reconciles any that were paid but not saved.

### Stock
- FEFO: first-expiring batches sell first, and expired batches can't be sold
- Restock with cost per unit, adjust stock (damage, loss, theft, found stock), full stock counts,
  and one-tap write-off of expired batches
- **Stock history** for every product: who changed what, when, and why
- **Low-stock levels** per product, filters for low stock, expiring and archived products, and a
  daily notification for expiring and low-stock products
- Archive or restore products (past sales are kept)
- Cost price, barcode and SKU on every product (unique barcodes and SKUs). CSV and Excel import.
- **Product photos** from the camera or gallery, shown on the till buttons

### People and security
- Roles enforced in the services, not just hidden in the UI:

  | | Owner | Manager | Cashier | Stock clerk |
  |---|:-:|:-:|:-:|:-:|
  | Sell | ✓ | ✓ | ✓ | |
  | Discounts, voids, refunds | ✓ | ✓ | | |
  | Products, restock, adjust stock | ✓ | ✓ | | restock / adjust |
  | Reports, expenses, activity log | ✓ | ✓ | | |
  | Staff, store settings, backups | ✓ | | | |

- PINs are 4–6 digits, unique, and stored hashed. The default PINs `1234` and `0000` are refused
  at login and can't be chosen. The owner sets their own PIN in the setup wizard.
- 5 wrong PINs lock the keypad for 30 s. The lockout survives restarts.
- Inactivity sign-out after 15 minutes. Any tap counts as activity.
- The admin password can be reset with the owner PIN, or changed in Settings.

### Money and reporting
- Reports for today, yesterday, this week, the last 7 days, this or last month, or any date range:
  gross and net sales, discounts, refunds, VAT, cost of goods, gross and net profit, voids, takings
  per payment method, per-cashier and per-product figures. **CSV export.**
- **Expenses**, including cash paid out of the till
- **Shifts and cash-up**: open with a float. At close, expected cash (float + cash sales − cash
  refunds − till payouts) is compared with the counted cash.
- **Activity log** of sign-ins, sales, voids, refunds, stock, staff and settings changes

### Data
- Everything is stored on the phone in Isar and works with no network
- **Backup and restore** of the whole database to one file
- **Several tills, one shop**: every 10 minutes each device syncs with the ShopPOS backend. Stock
  movements are applied once on every device, so stock levels agree. Sales, refunds, expenses,
  products, prices and staff names are shared, so any device's reports cover the whole shop.
  Shifts and cash-ups stay per till.
- To add a second till, restore a backup from the first one, or start it empty and sync. Either way
  it rebuilds the stock from the movement history. Staff from other tills need a PIN set on each
  new device, because PINs are never synced.
- **Several shops, one server**: the backend can host many shops, each with its own key, Paystack
  account and data (see `backend/README.md`).

## Getting started

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Isar / Riverpod code
flutter run
```

First launch: admin email and password, then the setup wizard (store, tax, payment methods, owner
PIN and staff, opening stock, hardware). After that, the role picker offers **Admin / Owner**
(email and password) or **Staff** (PIN).

Mobile Money and sync need the backend: see [`backend/README.md`](backend/README.md), then enter
its URL and API key under **Settings → Integrations**.

## Tests

```bash
flutter test          # app: maths, stock, sales, refunds, shifts, reports, permissions, backup, sync, import
cd backend && npm test
```

On Windows the Isar tests load `isar.dll` from the project root.

## Project layout

```
lib/
├── core/
│   ├── auth/permissions.dart        # role → permission matrix, enforced by services
│   ├── database/                    # Isar provider, schema list, startup migrations
│   ├── models/store_settings.dart
│   ├── providers/                   # store settings, sync
│   ├── services/                    # session, notifications, stock alerts, backup, sync
│   └── utils/                       # currency, dates, hashing, ids, file export
├── features/
│   ├── activity/                    # activity log model, service, screen
│   ├── auth/                        # users, PIN + email login, password reset
│   ├── expenses/
│   ├── main/                        # role-based navigation shell
│   ├── products/                    # products, batches, stock movements, inventory service, import
│   ├── reports/                     # date ranges, report service, CSV export, screen
│   ├── sales/                       # cart, sale service, calculator, receipts, MoMo, history
│   ├── settings/                    # store settings, integrations, backup, staff, pending MoMo
│   ├── setup/                       # first-run wizard
│   ├── shared/                      # shared widgets
│   └── shifts/
└── main.dart
backend/                             # Node.js Paystack proxy + sync server (no dependencies)
```

Business rules live in services (`SaleService`, `InventoryService`, `ShiftService`,
`ExpenseService`, `ReportSummary`, `BackupService`, `SyncService`). Each one checks permissions and
writes in a single transaction. Screens call services and never write to the database directly.

## Known limits

- Product photos stay on the device that took them: they aren't synced or included in backups.
- If two tills sell the last unit at the same moment while offline, both sales go through and stock
  can show below zero after syncing. The movement history shows exactly what happened.
- Receipts print in plain ASCII, so the currency shows as its code (GHS) rather than the symbol.

## License

MIT
