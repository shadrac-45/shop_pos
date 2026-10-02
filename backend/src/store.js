// ============================================
// Sync Store — ShopPOS backend
// ============================================
// Keeps every record pushed by shop devices in
// one JSON file, keyed by collection and uuid.
// Writes go to a temp file then rename, so a
// crash mid-write can't corrupt the data.
//
// Fine for a single shop's volume; swap for a
// real database if many shops share a server.
// ============================================

import fs from 'node:fs';
import path from 'node:path';

export const SYNC_COLLECTIONS = [
  'products',
  'batches',
  'sales',
  'saleItems',
  'stockMovements',
  'expenses',
  'shifts',
  'users',
  'activityLogs',
];

export class SyncStore {
  constructor(dataDir) {
    this.file = path.join(dataDir, 'shoppos-sync.json');
    fs.mkdirSync(dataDir, { recursive: true });
    this.data = fs.existsSync(this.file)
      ? JSON.parse(fs.readFileSync(this.file, 'utf8'))
      : { devices: {}, collections: {} };
    // Serialises writes: each save waits for the previous one.
    this._writing = Promise.resolve();
  }

  /**
   * Upserts [records] into [collection]. A record replaces the stored one
   * unless the stored copy has a newer `updatedAt` (last write wins).
   * Returns how many records were stored.
   */
  upsert(collection, records, deviceId, receivedAt = new Date().toISOString()) {
    if (!SYNC_COLLECTIONS.includes(collection)) {
      throw new Error(`Unknown collection: ${collection}`);
    }
    const bucket = (this.data.collections[collection] ??= {});
    let stored = 0;
    for (const record of records) {
      const key = record?.uuid;
      if (typeof key !== 'string' || key.length === 0) continue;
      const existing = bucket[key];
      if (existing && newer(existing.record.updatedAt, record.updatedAt)) continue;
      bucket[key] = { record, deviceId, receivedAt };
      stored++;
    }
    this.data.devices[deviceId] = receivedAt;
    return stored;
  }

  /** Records in [collection] received after [since] from other devices. */
  changesSince(collection, since, excludeDeviceId) {
    const bucket = this.data.collections[collection] ?? {};
    return Object.values(bucket)
      .filter((e) => (!since || e.receivedAt > since) && e.deviceId !== excludeDeviceId)
      .map((e) => e.record);
  }

  count(collection) {
    return Object.keys(this.data.collections[collection] ?? {}).length;
  }

  save() {
    this._writing = this._writing.then(async () => {
      const tmp = `${this.file}.tmp`;
      await fs.promises.writeFile(tmp, JSON.stringify(this.data));
      await fs.promises.rename(tmp, this.file);
    });
    return this._writing;
  }
}

/** True if timestamp [a] is strictly later than [b] (missing = oldest). */
function newer(a, b) {
  if (!a) return false;
  if (!b) return true;
  return Date.parse(a) > Date.parse(b);
}
