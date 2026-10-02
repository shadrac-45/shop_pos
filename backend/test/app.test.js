import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { createApp } from '../src/app.js';
import { PaystackClient, toLocalGhanaPhone } from '../src/paystack.js';
import { SyncStore } from '../src/store.js';
import { loadShops } from '../src/shops.js';

/** Fake Paystack: records requests, returns canned responses. */
function fakePaystack(responses) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init, body: init.body ? JSON.parse(init.body) : null });
    const key = Object.keys(responses).find((k) => url.includes(k));
    const [status, json] = responses[key] ?? [404, { status: false, message: 'not found' }];
    return { status, json: async () => json };
  };
  return { calls, client: new PaystackClient({ secretKey: 'sk_test_x', fetchImpl }) };
}

/** Single shop from the old-style options, or pass `shops` directly. */
function appOptions({ apiKey, paystack, store, shops, openPaystack }) {
  if (shops) return { shops, openPaystack };
  return apiKey
    ? { shops: [{ id: 'default', apiKey, paystack, store }] }
    : { shops: [], openPaystack: paystack };
}

async function withServer(options, fn) {
  const server = http.createServer(createApp(appOptions(options)));
  await new Promise((r) => server.listen(0, r));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    await fn(base);
  } finally {
    await new Promise((r) => server.close(r));
  }
}

function tempStore() {
  return new SyncStore(fs.mkdtempSync(path.join(os.tmpdir(), 'shoppos-')));
}

test('phone numbers are converted to the local format Paystack expects', () => {
  assert.equal(toLocalGhanaPhone('+233551234987'), '0551234987');
  assert.equal(toLocalGhanaPhone('233551234987'), '0551234987');
  assert.equal(toLocalGhanaPhone('055 123 4987'), '0551234987');
  assert.equal(toLocalGhanaPhone('12345'), null);
});

test('charge sends the Paystack request and maps tgo to atl', async () => {
  const { calls, client } = fakePaystack({
    '/charge': [200, { status: true, data: { reference: 'shoppos_1_abc', status: 'pay_offline' } }],
  });
  await withServer({ apiKey: 'k', paystack: client, store: tempStore() }, async (base) => {
    const res = await fetch(`${base}/api/momo/charge`, {
      method: 'POST',
      headers: { 'x-api-key': 'k', 'content-type': 'application/json' },
      body: JSON.stringify({
        phone: '+233551234987', amount_pesewas: 2550, provider: 'tgo', reference: 'shoppos_1_abc',
      }),
    });
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), {
      success: true, reference: 'shoppos_1_abc', status: 'pay_offline',
    });
  });
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].body.mobile_money, { phone: '0551234987', provider: 'atl' });
  assert.equal(calls[0].body.amount, 2550);
  assert.equal(calls[0].body.currency, 'GHS');
});

test('api key is required when configured', async () => {
  const { client } = fakePaystack({});
  await withServer({ apiKey: 'secret', paystack: client, store: tempStore() }, async (base) => {
    const res = await fetch(`${base}/api/momo/verify/shoppos_1_abc`);
    assert.equal(res.status, 401);
    const health = await fetch(`${base}/health`);
    assert.equal(health.status, 200);
  });
});

test('verify maps Paystack statuses for the app', async () => {
  const cases = [
    ['success', 'success'],
    ['ongoing', 'pending'],
    ['reversed', 'failed'],
    ['abandoned', 'abandoned'],
  ];
  for (const [paystackStatus, expected] of cases) {
    const { client } = fakePaystack({
      '/transaction/verify/': [200, { status: true, data: { status: paystackStatus, amount: 100 } }],
    });
    assert.equal((await client.verify('shoppos_1_abc')).status, expected);
  }
  const { client } = fakePaystack({});
  assert.equal((await client.verify('shoppos_1_abc')).status, 'failed'); // 404: never charged
});

test('sync push stores records and pull returns other devices’ products', async () => {
  const store = tempStore();
  await withServer({ apiKey: 'k', paystack: null, store }, async (base) => {
    const headers = (device) => ({
      'x-api-key': 'k', 'x-device-id': device, 'content-type': 'application/json',
    });
    let res = await fetch(`${base}/api/sync/push`, {
      method: 'POST',
      headers: headers('phone-a'),
      body: JSON.stringify({
        collections: {
          products: [{ uuid: 'p1', name: 'Milo', price: 32, updatedAt: '2026-10-01T10:00:00Z' }],
          sales: [{ uuid: 's1', totalAmount: 32 }],
          bogus: [{ uuid: 'x' }],
        },
      }),
    });
    assert.equal(res.status, 200);
    assert.deepEqual((await res.json()).stored, { products: 1, sales: 1 });

    // An older edit doesn't overwrite a newer one.
    await fetch(`${base}/api/sync/push`, {
      method: 'POST',
      headers: headers('phone-b'),
      body: JSON.stringify({
        collections: {
          products: [{ uuid: 'p1', name: 'Old', price: 1, updatedAt: '2026-09-01T10:00:00Z' }],
        },
      }),
    });

    res = await fetch(`${base}/api/sync/pull`, { headers: headers('phone-b') });
    const pulled = await res.json();
    assert.equal(pulled.products.length, 1);
    assert.equal(pulled.products[0].name, 'Milo');

    // The device that made the change doesn't get it back.
    res = await fetch(`${base}/api/sync/pull`, { headers: headers('phone-a') });
    assert.equal((await res.json()).products.length, 0);
  });
  assert.equal(store.count('sales'), 1);
});

test('pull returns every shared collection', async () => {
  await withServer({ apiKey: 'k', paystack: null, store: tempStore() }, async (base) => {
    const h = (d) => ({ 'x-api-key': 'k', 'x-device-id': d, 'content-type': 'application/json' });
    await fetch(`${base}/api/sync/push`, {
      method: 'POST',
      headers: h('a'),
      body: JSON.stringify({
        collections: {
          stockMovements: [{ uuid: 'm1', quantityChange: -2 }],
          saleItems: [{ uuid: 's1#1', saleUuid: 's1' }],
          expenses: [{ uuid: 'e1', amount: 5 }],
          shifts: [{ uuid: 'sh1' }],
        },
      }),
    });
    const pulled = await (await fetch(`${base}/api/sync/pull`, { headers: h('b') })).json();
    assert.equal(pulled.stockMovements.length, 1);
    assert.equal(pulled.saleItems.length, 1);
    assert.equal(pulled.expenses.length, 1);
    assert.equal(pulled.shifts, undefined); // shifts stay per device
  });
});

test('shops on one server never see each other’s data', async () => {
  const shops = [
    { id: 'shop-a', apiKey: 'a'.repeat(20), paystack: null, store: tempStore() },
    { id: 'shop-b', apiKey: 'b'.repeat(20), paystack: null, store: tempStore() },
  ];
  await withServer({ shops }, async (base) => {
    const h = (key, d) => ({ 'x-api-key': key, 'x-device-id': d, 'content-type': 'application/json' });
    await fetch(`${base}/api/sync/push`, {
      method: 'POST',
      headers: h('a'.repeat(20), 'a1'),
      body: JSON.stringify({ collections: { products: [{ uuid: 'p', name: 'A only' }] } }),
    });
    const b = await (await fetch(`${base}/api/sync/pull`, { headers: h('b'.repeat(20), 'b1') })).json();
    assert.equal(b.products.length, 0);
    const a2 = await (await fetch(`${base}/api/sync/pull`, { headers: h('a'.repeat(20), 'a2') })).json();
    assert.equal(a2.products[0].name, 'A only');
    const bad = await fetch(`${base}/api/sync/pull`, { headers: h('c'.repeat(20), 'x') });
    assert.equal(bad.status, 401);
  });
});

test('shops file validation', () => {
  const read = (json) => () => json;
  assert.deepEqual(
    loadShops({ apiKey: 'k', paystackSecretKey: 'sk', readFile: read('') }),
    [{ id: 'default', apiKey: 'k', paystackSecretKey: 'sk' }],
  );
  assert.deepEqual(loadShops({ readFile: read('') }), []);
  const ok = loadShops({
    shopsFile: 'f',
    readFile: read(JSON.stringify([{ id: 'kofi', apiKey: 'x'.repeat(16) }])),
  });
  assert.equal(ok[0].id, 'kofi');
  assert.throws(() => loadShops({ shopsFile: 'f', readFile: read('[{"id":"Bad Id","apiKey":"xxxxxxxxxxxxxxxx"}]') }));
  assert.throws(() => loadShops({ shopsFile: 'f', readFile: read('[{"id":"a","apiKey":"short"}]') }));
  assert.throws(() => loadShops({
    shopsFile: 'f',
    readFile: read(JSON.stringify([{ id: 'a', apiKey: 'y'.repeat(16) }, { id: 'b', apiKey: 'y'.repeat(16) }])),
  }));
});

test('sync is refused when the server has no API key', async () => {
  await withServer({ apiKey: undefined, paystack: null, store: tempStore() }, async (base) => {
    const res = await fetch(`${base}/api/sync/pull`, { headers: { 'x-device-id': 'a' } });
    assert.equal(res.status, 503);
  });
});
