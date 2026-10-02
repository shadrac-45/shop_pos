// ============================================
// HTTP app — ShopPOS backend
// ============================================
// Routes (all JSON):
//   GET  /health                     liveness check (no key)
//   POST /api/momo/charge            start a MoMo charge
//   GET  /api/momo/verify/:reference check a charge
//   POST /api/sync/push              upload changed records
//   GET  /api/sync/pull?since=ISO    catalog changes from other devices
//
// When API_KEY is set, every /api route needs the
// header `x-api-key: <API_KEY>`. Sync routes are
// refused entirely without an API_KEY.
// ============================================

import { timingSafeEqual } from 'node:crypto';
import { SYNC_COLLECTIONS } from './store.js';

const MAX_BODY_BYTES = 10 * 1024 * 1024;

export function createApp({ apiKey, paystack, store }) {
  return async function handle(req, res) {
    try {
      const url = new URL(req.url, 'http://localhost');
      const route = `${req.method} ${url.pathname}`;

      if (route === 'GET /health') {
        return send(res, 200, {
          status: 'ok',
          momo: Boolean(paystack),
          sync: Boolean(apiKey && store),
        });
      }

      if (url.pathname.startsWith('/api/')) {
        if (apiKey && !keyMatches(req.headers['x-api-key'], apiKey)) {
          return send(res, 401, { success: false, message: 'Invalid or missing API key.' });
        }
      }

      if (route === 'POST /api/momo/charge') {
        if (!paystack) return notConfigured(res, 'PAYSTACK_SECRET_KEY');
        const body = await readJson(req);
        const result = await paystack.charge({
          phone: body.phone,
          amountPesewas: body.amount_pesewas,
          provider: body.provider,
          reference: body.reference,
        });
        return send(res, result.success ? 200 : 400, result);
      }

      const verify = url.pathname.match(/^\/api\/momo\/verify\/([^/]+)$/);
      if (req.method === 'GET' && verify) {
        if (!paystack) return notConfigured(res, 'PAYSTACK_SECRET_KEY');
        return send(res, 200, await paystack.verify(decodeURIComponent(verify[1])));
      }

      if (url.pathname.startsWith('/api/sync/')) {
        if (!apiKey || !store) return notConfigured(res, 'API_KEY');
        const deviceId = String(req.headers['x-device-id'] ?? '');
        if (!deviceId) return send(res, 400, { success: false, message: 'Missing x-device-id header.' });

        if (route === 'POST /api/sync/push') {
          const body = await readJson(req);
          const collections = body.collections ?? {};
          const stored = {};
          const receivedAt = new Date().toISOString();
          for (const [name, records] of Object.entries(collections)) {
            if (!SYNC_COLLECTIONS.includes(name) || !Array.isArray(records)) continue;
            stored[name] = store.upsert(name, records, deviceId, receivedAt);
          }
          await store.save();
          return send(res, 200, { success: true, stored, serverTime: receivedAt });
        }

        if (route === 'GET /api/sync/pull') {
          const since = url.searchParams.get('since') || null;
          return send(res, 200, {
            success: true,
            serverTime: new Date().toISOString(),
            products: store.changesSince('products', since, deviceId),
          });
        }
      }

      return send(res, 404, { success: false, message: 'Not found' });
    } catch (err) {
      if (err instanceof BadRequest) return send(res, 400, { success: false, message: err.message });
      console.error('[ShopPOS backend]', err);
      return send(res, 500, { success: false, message: 'Server error' });
    }
  };
}

class BadRequest extends Error {}

function keyMatches(given, expected) {
  if (typeof given !== 'string') return false;
  const a = Buffer.from(given);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

function notConfigured(res, setting) {
  return send(res, 503, { success: false, message: `Server is missing ${setting}.` });
}

function send(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

async function readJson(req) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new BadRequest('Request body too large.');
    chunks.push(chunk);
  }
  if (chunks.length === 0) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new BadRequest('Body must be JSON.');
  }
}
