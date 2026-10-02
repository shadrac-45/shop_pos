// ============================================
// ShopPOS backend — entry point
// ============================================
// Configuration (environment variables):
//   PORT                 default 3000
//   PAYSTACK_SECRET_KEY  sk_test_… / sk_live_… (enables MoMo)
//   API_KEY              shared secret the app sends as x-api-key
//                        (required for sync; protects MoMo too)
//   DATA_DIR             where synced data is stored (default ./data)
// ============================================

import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { createApp } from './src/app.js';
import { PaystackClient } from './src/paystack.js';
import { SyncStore } from './src/store.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.PORT ?? 3000);
const secretKey = process.env.PAYSTACK_SECRET_KEY;
const apiKey = process.env.API_KEY;

const app = createApp({
  apiKey,
  paystack: secretKey ? new PaystackClient({ secretKey }) : null,
  store: new SyncStore(process.env.DATA_DIR ?? path.join(here, 'data')),
});

http.createServer(app).listen(port, () => {
  console.log(`ShopPOS backend on http://0.0.0.0:${port}`);
  if (!secretKey) console.warn('  PAYSTACK_SECRET_KEY not set: MoMo disabled.');
  if (!apiKey) console.warn('  API_KEY not set: sync disabled and MoMo routes are open.');
});
