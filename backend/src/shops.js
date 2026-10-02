// ============================================
// Shop configuration — ShopPOS backend
// ============================================

/**
 * Reads the shops this server hosts: from SHOPS_FILE if given, otherwise a
 * single "default" shop from API_KEY / PAYSTACK_SECRET_KEY. Throws on an
 * invalid file so a typo can't silently open the server.
 */
export function loadShops({ shopsFile, apiKey, paystackSecretKey, readFile }) {
  if (shopsFile) {
    const list = JSON.parse(readFile(shopsFile));
    if (!Array.isArray(list) || list.length === 0) {
      throw new Error('SHOPS_FILE must be a non-empty JSON array.');
    }
    const ids = new Set();
    const keys = new Set();
    for (const s of list) {
      if (typeof s.id !== 'string' || !/^[a-z0-9][a-z0-9-]{0,62}$/.test(s.id)) {
        throw new Error(`Invalid shop id: ${JSON.stringify(s.id)} (use lowercase letters, digits, dashes).`);
      }
      if (typeof s.apiKey !== 'string' || s.apiKey.length < 16) {
        throw new Error(`Shop ${s.id}: apiKey must be at least 16 characters.`);
      }
      if (ids.has(s.id)) throw new Error(`Duplicate shop id: ${s.id}`);
      if (keys.has(s.apiKey)) throw new Error(`Shop ${s.id}: apiKey is used by another shop.`);
      ids.add(s.id);
      keys.add(s.apiKey);
    }
    return list.map((s) => ({
      id: s.id,
      apiKey: s.apiKey,
      paystackSecretKey: s.paystackSecretKey || null,
    }));
  }
  if (apiKey) {
    return [{ id: 'default', apiKey, paystackSecretKey: paystackSecretKey || null }];
  }
  return [];
}
