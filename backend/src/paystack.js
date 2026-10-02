// ============================================
// Paystack client — ShopPOS backend
// ============================================
// Ghana Mobile Money through Paystack's Charge
// API. The secret key stays on the server; the
// app only ever talks to this backend.
// ============================================

/** Paystack's Ghana provider codes. Older app builds sent 'tgo'. */
const PROVIDERS = { mtn: 'mtn', vod: 'vod', atl: 'atl', tgo: 'atl' };

/** +233551234987 / 233551234987 / 0551234987 → 0551234987, else null. */
export function toLocalGhanaPhone(raw) {
  const digits = String(raw ?? '').replace(/[\s\-()]/g, '');
  if (/^\+233\d{9}$/.test(digits)) return `0${digits.slice(4)}`;
  if (/^233\d{9}$/.test(digits)) return `0${digits.slice(3)}`;
  if (/^0\d{9}$/.test(digits)) return digits;
  return null;
}

export class PaystackClient {
  constructor({ secretKey, baseUrl = 'https://api.paystack.co', fetchImpl = fetch }) {
    this.secretKey = secretKey;
    this.baseUrl = baseUrl;
    this.fetch = fetchImpl;
  }

  async _call(method, path, body) {
    const res = await this.fetch(`${this.baseUrl}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${this.secretKey}`,
        'Content-Type': 'application/json',
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    let json = {};
    try {
      json = await res.json();
    } catch {
      // Non-JSON error page.
    }
    return { httpStatus: res.status, json };
  }

  /**
   * Starts a charge. Returns the app's charge response:
   * { success, reference, status, message }.
   */
  async charge({ phone, amountPesewas, provider, reference }) {
    const localPhone = toLocalGhanaPhone(phone);
    const providerCode = PROVIDERS[String(provider ?? '').toLowerCase()];
    if (!localPhone) return { success: false, message: 'Invalid Ghana phone number.' };
    if (!providerCode) return { success: false, message: `Unknown network: ${provider}` };
    if (!Number.isInteger(amountPesewas) || amountPesewas < 100) {
      return { success: false, message: 'Amount must be at least 1.00 GHS.' };
    }
    if (typeof reference !== 'string' || !/^[\w.=-]{6,100}$/.test(reference)) {
      return { success: false, message: 'Invalid payment reference.' };
    }

    const { httpStatus, json } = await this._call('POST', '/charge', {
      // Paystack requires an email; MoMo customers rarely have one on file.
      email: `${localPhone}@momo.shoppos.local`,
      amount: amountPesewas,
      currency: 'GHS',
      reference,
      mobile_money: { phone: localPhone, provider: providerCode },
    });

    if (httpStatus >= 400 || json.status !== true) {
      return {
        success: false,
        reference,
        status: 'failed',
        message: json.message || `Paystack error (HTTP ${httpStatus})`,
      };
    }
    return {
      success: true,
      reference: json.data?.reference ?? reference,
      status: json.data?.status ?? 'pending',
      message: json.data?.display_text || json.message,
    };
  }

  /**
   * Checks a charge. Returns { status, gateway_response, amount } where
   * status is success | failed | abandoned | pending.
   */
  async verify(reference) {
    if (typeof reference !== 'string' || !/^[\w.=-]{6,100}$/.test(reference)) {
      return { status: 'failed', gateway_response: 'Invalid reference' };
    }
    const { httpStatus, json } = await this._call(
      'GET',
      `/transaction/verify/${encodeURIComponent(reference)}`,
    );
    if (httpStatus === 404) {
      // Paystack never received this charge, so it can't be paid.
      return { status: 'failed', gateway_response: 'Payment request was not received by Paystack' };
    }
    if (httpStatus >= 400 || json.status !== true) {
      // Can't tell: the app keeps the payment pending and checks again.
      return { status: 'pending', gateway_response: json.message || `HTTP ${httpStatus}` };
    }
    const raw = String(json.data?.status ?? '').toLowerCase();
    const status =
      raw === 'success' ? 'success'
        : raw === 'failed' || raw === 'reversed' ? 'failed'
          : raw === 'abandoned' ? 'abandoned'
            : 'pending'; // ongoing, pending, processing, queued, send_otp…
    return {
      status,
      gateway_response: json.data?.gateway_response ?? raw,
      amount: json.data?.amount,
    };
  }
}
