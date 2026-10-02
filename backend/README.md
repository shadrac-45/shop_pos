# ShopPOS backend

A small Node.js server the ShopPOS app talks to for two things:

1. **Mobile Money (Paystack, Ghana).** The app never holds the Paystack secret key. It asks this
   server to start a charge and to check its status.
2. **Cloud sync.** Each device uploads its sales, stock movements, expenses, shifts, products and
   staff names and roles, and downloads product and price changes made on other devices.
   PINs and passwords never leave the phone.

It has no dependencies (Node 18 or newer), so there's nothing to install.

## Run it

```bash
cd backend
cp .env.example .env        # then fill in the values
export $(grep -v '^#' .env | xargs)   # or set the variables any other way
npm start
```

| Variable | Purpose |
|---|---|
| `PORT` | Port to listen on (default `3000`) |
| `PAYSTACK_SECRET_KEY` | Enables Mobile Money. Use `sk_test_…` while testing. |
| `API_KEY` | Shared secret the app sends as `x-api-key`. Required for sync, and it also protects the MoMo routes. |
| `SHOPS_FILE` | Host several shops instead (replaces the two settings above; see below) |
| `DATA_DIR` | Folder for synced data. Back it up. |

### Several shops on one server

Point `SHOPS_FILE` at a JSON file:

```json
[
  { "id": "kofi-corner", "apiKey": "at-least-16-random-chars", "paystackSecretKey": "sk_live_..." },
  { "id": "ama-provisions", "apiKey": "another-long-random-key" }
]
```

Each shop's devices use that shop's `apiKey`. A shop only ever sees its own data (stored under
`DATA_DIR/<id>/`) and charges MoMo to its own Paystack account. A shop without
`paystackSecretKey` gets sync but no MoMo.

Then in the app, as the owner: **Settings → Integrations**. Enter the URL ending in `/api`
(for example `https://pos.example.com/api`) and the same `API_KEY`, then tap **Save & Test**.

For a real shop, run it behind HTTPS (most hosts such as Railway, Render or Fly.io do this for you).
While developing, the Android emulator reaches your computer at `http://10.0.2.2:3000/api`; debug
builds use that address when no URL is saved.

## API

| Route | Body / query | Response |
|---|---|---|
| `GET /health` | | `{status:"ok", momo, sync}` |
| `POST /api/momo/charge` | `{phone, amount_pesewas, provider: mtn\|vod\|atl, reference}` | `{success, reference, status, message}` |
| `GET /api/momo/verify/:reference` | | `{status: success\|failed\|abandoned\|pending, gateway_response, amount}` |
| `POST /api/sync/push` | `{collections: {sales: [...], ...}}`, header `x-device-id` | `{success, stored, serverTime}` |
| `GET /api/sync/pull?since=ISO` | header `x-device-id` | `{success, serverTime, products, users, batches, sales, saleItems, stockMovements, expenses}` from the shop's other devices |

Records are keyed by `uuid`. When two devices edit the same record, the one with the later
`updatedAt` wins. Stock is shared through stock movements: each device applies every other device's
movements to its batches exactly once, so all tills agree on stock levels. Shifts and activity logs
are uploaded for safekeeping but not sent to other devices.

## Tests

```bash
npm test
```

## Limits

- Storage is one JSON file per shop, which is fine for a small shop's volume. For heavy use or many
  shops, swap `src/store.js` for a real database.
