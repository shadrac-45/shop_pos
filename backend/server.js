// ============================================
// ShopPOS backend — entry point
// ============================================
// One shop (environment variables):
//   API_KEY              shared secret the app sends as x-api-key
//   PAYSTACK_SECRET_KEY  sk_test_… / sk_live_… (enables MoMo)
//
// Several shops: SHOPS_FILE points at a JSON file
//   [{"id": "kofi-corner", "apiKey": "…", "paystackSecretKey": "sk_…"}, …]
// Each shop gets its own data folder under DATA_DIR.
//
// Also: PORT (default 3000), DATA_DIR (default ./data)
// ============================================

import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { createApp } from './src/app.js';
import { PaystackClient } from './src/paystack.js';
import { SyncStore } from './src/store.js';
import { loadShops } from './src/shops.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.PORT ?? 3000);
const dataDir = process.env.DATA_DIR ?? path.join(here, 'data');

const shopConfigs = loadShops({
  shopsFile: process.env.SHOPS_FILE,
  apiKey: process.env.API_KEY,
  paystackSecretKey: process.env.PAYSTACK_SECRET_KEY,
  readFile: (f) => fs.readFileSync(f, 'utf8'),
});

const shops = shopConfigs.map((s) => ({
  id: s.id,
  apiKey: s.apiKey,
  paystack: s.paystackSecretKey ? new PaystackClient({ secretKey: s.paystackSecretKey }) : null,
  // The single-shop setup keeps its data where earlier versions put it.
  store: new SyncStore(shopConfigs.length === 1 && s.id === 'default' ? dataDir : path.join(dataDir, s.id)),
}));

const openPaystack =
  shops.length === 0 && process.env.PAYSTACK_SECRET_KEY
    ? new PaystackClient({ secretKey: process.env.PAYSTACK_SECRET_KEY })
    : null;

http.createServer(createApp({ shops, openPaystack })).listen(port, () => {
  console.log(`ShopPOS backend on http://0.0.0.0:${port}`);
  if (shops.length === 0) {
    console.warn('  No API_KEY or SHOPS_FILE: sync disabled and MoMo routes are open.');
  } else {
    console.log(`  Shops: ${shops.map((s) => `${s.id}${s.paystack ? '' : ' (no MoMo)'}`).join(', ')}`);
  }
});
