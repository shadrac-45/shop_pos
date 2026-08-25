// ============================================================
// ShopPOS — Shared App Store + Utilities
// All pages import this script first.
// ============================================================

/* ── SEED PRODUCT DATA ── */
const SEED_PRODUCTS = [
  // Coffee
  { id:'c1', name:'Latte',             price:4.50, category:'Coffee',      emoji:'☕', stock:50, minStock:10 },
  { id:'c2', name:'Espresso',          price:3.00, category:'Coffee',      emoji:'☕', stock:45, minStock:10 },
  { id:'c3', name:'Cappuccino',        price:4.00, category:'Coffee',      emoji:'☕', stock:40, minStock:10 },
  { id:'c4', name:'Americano',         price:3.50, category:'Coffee',      emoji:'🫖', stock:48, minStock:10 },
  { id:'c5', name:'Cold Brew',         price:5.00, category:'Coffee',      emoji:'🧋', stock:25, minStock:8  },
  { id:'c6', name:'Mocha',             price:5.00, category:'Coffee',      emoji:'🍫', stock:30, minStock:8  },
  // Pastries
  { id:'p1', name:'Croissant',         price:3.75, category:'Pastries',    emoji:'🥐', stock:20, minStock:5  },
  { id:'p2', name:'Choc Cookie',       price:2.50, category:'Pastries',    emoji:'🍪', stock:35, minStock:10 },
  { id:'p3', name:'Blueberry Muffin',  price:3.25, category:'Pastries',    emoji:'🫐', stock:15, minStock:5  },
  { id:'p4', name:'Cinnamon Roll',     price:4.00, category:'Pastries',    emoji:'🌀', stock:12, minStock:4  },
  { id:'p5', name:'Banana Bread',      price:3.50, category:'Pastries',    emoji:'🍌', stock:10, minStock:4  },
  // Merchandise
  { id:'m1', name:'Travel Mug',        price:18.00, category:'Merchandise', emoji:'🧉', stock:8,  minStock:3  },
  { id:'m2', name:'Tote Bag',          price:15.00, category:'Merchandise', emoji:'🛍️', stock:12, minStock:3  },
  { id:'m3', name:'Coffee Beans 250g', price:12.00, category:'Merchandise', emoji:'🫘', stock:20, minStock:5  },
  // Seasonal
  { id:'s1', name:'Pumpkin Spice Latte',price:5.50, category:'Seasonal',    emoji:'🎃', stock:30, minStock:8  },
  { id:'s2', name:'Gingerbread Cookie', price:2.75, category:'Seasonal',    emoji:'🎄', stock:25, minStock:8  },
  { id:'s3', name:'Peppermint Mocha',   price:5.50, category:'Seasonal',    emoji:'🌿', stock:28, minStock:8  },
];

/* ── GENERATE SAMPLE ORDER HISTORY ── */
function generateSampleOrders() {
  const templates = [
    [{ productId:'c1', name:'Latte',            price:4.50, emoji:'☕', qty:2, note:'Extra hot' }],
    [{ productId:'c2', name:'Espresso',         price:3.00, emoji:'☕', qty:1, note:'' },
     { productId:'p1', name:'Croissant',        price:3.75, emoji:'🥐', qty:1, note:'' }],
    [{ productId:'c3', name:'Cappuccino',       price:4.00, emoji:'☕', qty:2, note:'' },
     { productId:'p2', name:'Choc Cookie',      price:2.50, emoji:'🍪', qty:3, note:'' }],
    [{ productId:'c5', name:'Cold Brew',        price:5.00, emoji:'🧋', qty:1, note:'No ice' }],
    [{ productId:'m1', name:'Travel Mug',       price:18.00, emoji:'🧉', qty:1, note:'' },
     { productId:'c6', name:'Mocha',            price:5.00, emoji:'🍫', qty:1, note:'' }],
    [{ productId:'s1', name:'Pumpkin Spice Latte',price:5.50, emoji:'🎃', qty:2, note:'' },
     { productId:'s2', name:'Gingerbread Cookie', price:2.75, emoji:'🎄', qty:2, note:'' }],
    [{ productId:'p3', name:'Blueberry Muffin', price:3.25, emoji:'🫐', qty:1, note:'' },
     { productId:'c4', name:'Americano',        price:3.50, emoji:'🫖', qty:1, note:'Large' }],
  ];

  const methods = ['Cash','Card','Mobile Pay'];
  const orders = [];

  for (let i = 0; i < 20; i++) {
    const items = JSON.parse(JSON.stringify(templates[i % templates.length]));
    const rawSub = items.reduce((s, it) => s + it.price * it.qty, 0);
    const tax    = rawSub * 0.08;
    const total  = rawSub + tax;
    const method = methods[i % 3];
    const d      = new Date();
    // Spread orders over last 7 days
    d.setHours(d.getHours() - i * 6 - Math.floor(Math.random() * 3));

    orders.push({
      id: 'ORD-' + String(i + 1).padStart(4, '0'),
      timestamp: d.toISOString(),
      items,
      rawSubtotal:    rawSub,
      discountVal:    0,
      discountType:   'percent',
      discountAmount: 0,
      subtotal:       rawSub,
      tax,
      total,
      paymentMethod:  method,
      tendered:       method === 'Cash' ? Math.ceil(total * 2) / 2 : total,
      change:         method === 'Cash' ? Math.ceil(total * 2) / 2 - total : 0,
    });
  }
  return orders;
}

/* ═══════════════════════════════════════════
   APP STORE
   ═══════════════════════════════════════════ */
const AppStore = {

  /* ── state ── */
  cart:     [],   // { productId, name, price, emoji, qty, note }
  products: [],
  orders:   [],
  settings: {
    taxRate:     0.08,
    currency:    '$',
    theme:       'light',
    storeName:   'ShopPOS Café',
    cashierName: 'Cashier',
  },

  /* ── init ── */
  init() {
    this._load();
    this._applyTheme();
  },

  /* ── persistence ── */
  _save() {
    try {
      localStorage.setItem('spos_products', JSON.stringify(this.products));
      localStorage.setItem('spos_orders',   JSON.stringify(this.orders));
      localStorage.setItem('spos_settings', JSON.stringify(this.settings));
    } catch(_) {}
  },

  _load() {
    try {
      const p = localStorage.getItem('spos_products');
      const o = localStorage.getItem('spos_orders');
      const s = localStorage.getItem('spos_settings');
      this.products = p ? JSON.parse(p) : SEED_PRODUCTS.map(x => ({ ...x }));
      this.orders   = o ? JSON.parse(o) : generateSampleOrders();
      if (s) this.settings = { ...this.settings, ...JSON.parse(s) };
    } catch(_) {
      this.products = SEED_PRODUCTS.map(x => ({ ...x }));
      this.orders   = generateSampleOrders();
    }
  },

  /* ── theme ── */
  _applyTheme() {
    document.documentElement.setAttribute('data-theme', this.settings.theme);
  },

  toggleTheme() {
    this.settings.theme = this.settings.theme === 'dark' ? 'light' : 'dark';
    this._applyTheme();
    this._save();
  },

  /* ── products ── */
  getProducts(category = null, search = '') {
    let list = this.products;
    if (category && category !== 'All') list = list.filter(p => p.category === category);
    if (search) {
      const q = search.toLowerCase();
      list = list.filter(p => p.name.toLowerCase().includes(q) || p.category.toLowerCase().includes(q));
    }
    return list;
  },

  getProductById(id) { return this.products.find(p => p.id === id); },

  addProduct(data) {
    const id = 'prod_' + Date.now();
    this.products.push({ id, ...data });
    this._save();
    return id;
  },

  updateProduct(id, data) {
    const idx = this.products.findIndex(p => p.id === id);
    if (idx !== -1) { this.products[idx] = { ...this.products[idx], ...data }; this._save(); }
  },

  deleteProduct(id) { this.products = this.products.filter(p => p.id !== id); this._save(); },

  adjustStock(id, delta) {
    const p = this.getProductById(id);
    if (p) { p.stock = Math.max(0, p.stock + delta); this._save(); }
  },

  getCategories() {
    const cats = [...new Set(this.products.map(p => p.category))];
    return ['All', ...cats];
  },

  /* ── cart ── */
  getCartItem(productId) { return this.cart.find(i => i.productId === productId); },

  addToCart(productId) {
    const product = this.getProductById(productId);
    if (!product) return false;
    const existing = this.getCartItem(productId);
    if (existing) {
      if (existing.qty >= product.stock) return false; // honour stock limit
      existing.qty++;
    } else {
      if (product.stock <= 0) return false;
      this.cart.push({ productId, name: product.name, price: product.price, emoji: product.emoji, qty: 1, note: '' });
    }
    return true;
  },

  decreaseQty(productId) {
    const item = this.getCartItem(productId);
    if (!item) return;
    if (item.qty > 1) { item.qty--; } else { this.cart = this.cart.filter(i => i.productId !== productId); }
  },

  removeCartItem(productId) { this.cart = this.cart.filter(i => i.productId !== productId); },

  setCartNote(productId, note) { const i = this.getCartItem(productId); if (i) i.note = note; },

  clearCart() { this.cart = []; },

  getCartCount()      { return this.cart.reduce((s, i) => s + i.qty, 0); },
  getRawSubtotal()    { return this.cart.reduce((s, i) => s + i.price * i.qty, 0); },

  getSubtotal(discVal = 0, discType = 'percent') {
    const raw = this.getRawSubtotal();
    if (discType === 'percent') return raw * (1 - Math.min(Math.max(discVal, 0), 100) / 100);
    return Math.max(0, raw - Math.max(discVal, 0));
  },

  getTax(subtotal) { return subtotal * this.settings.taxRate; },

  getTotal(discVal = 0, discType = 'percent') {
    const sub = this.getSubtotal(discVal, discType);
    return sub + this.getTax(sub);
  },

  /* ── orders ── */
  placeOrder({ paymentMethod, tendered = 0, discountVal = 0, discountType = 'percent' }) {
    const rawSub  = this.getRawSubtotal();
    const sub     = this.getSubtotal(discountVal, discountType);
    const tax     = this.getTax(sub);
    const total   = sub + tax;
    const discAmt = rawSub - sub;

    const order = {
      id:             'ORD-' + String(this.orders.length + 1).padStart(4, '0'),
      timestamp:      new Date().toISOString(),
      items:          JSON.parse(JSON.stringify(this.cart)),
      rawSubtotal:    rawSub,
      discountVal,
      discountType,
      discountAmount: discAmt,
      subtotal:       sub,
      tax,
      total,
      paymentMethod,
      tendered:       paymentMethod === 'Cash' ? tendered : total,
      change:         paymentMethod === 'Cash' ? Math.max(0, tendered - total) : 0,
    };

    // Deduct stock
    this.cart.forEach(item => this.adjustStock(item.productId, -item.qty));

    this.orders.unshift(order);
    this.clearCart();
    this._save();
    return order;
  },

  getOrders(search = '', dateFilter = '') {
    let list = this.orders;
    if (search) {
      const q = search.toLowerCase();
      list = list.filter(o =>
        o.id.toLowerCase().includes(q) ||
        o.paymentMethod.toLowerCase().includes(q) ||
        o.items.some(i => i.name.toLowerCase().includes(q))
      );
    }
    if (dateFilter) list = list.filter(o => o.timestamp.startsWith(dateFilter));
    return list;
  },

  /* ── reports ── */
  getReportData() {
    const today = new Date().toISOString().split('T')[0];
    const todayOrders = this.orders.filter(o => o.timestamp.startsWith(today));

    // Sales by category
    const catSales = {};
    this.orders.forEach(o => o.items.forEach(i => {
      const p = this.getProductById(i.productId);
      const cat = p ? p.category : 'Other';
      catSales[cat] = (catSales[cat] || 0) + i.price * i.qty;
    }));

    // Top products
    const prodMap = {};
    this.orders.forEach(o => o.items.forEach(i => {
      if (!prodMap[i.productId]) prodMap[i.productId] = { name: i.name, emoji: i.emoji, qty: 0, revenue: 0 };
      prodMap[i.productId].qty     += i.qty;
      prodMap[i.productId].revenue += i.price * i.qty;
    }));
    const topProducts = Object.values(prodMap).sort((a, b) => b.revenue - a.revenue).slice(0, 6);

    // Weekly chart (last 7 days)
    const weekLabels = [];
    const weekRevenue = [];
    for (let d = 6; d >= 0; d--) {
      const dt = new Date();
      dt.setDate(dt.getDate() - d);
      const key = dt.toISOString().split('T')[0];
      const dayOrders = this.orders.filter(o => o.timestamp.startsWith(key));
      weekLabels.push(dt.toLocaleDateString('en-US', { weekday:'short' }));
      weekRevenue.push(dayOrders.reduce((s, o) => s + o.total, 0));
    }

    return {
      today: {
        orders:   todayOrders.length,
        revenue:  todayOrders.reduce((s, o) => s + o.total, 0),
        avgOrder: todayOrders.length
          ? todayOrders.reduce((s, o) => s + o.total, 0) / todayOrders.length
          : 0,
      },
      allTime: {
        orders:  this.orders.length,
        revenue: this.orders.reduce((s, o) => s + o.total, 0),
      },
      catSales,
      topProducts,
      weekLabels,
      weekRevenue,
      recentOrders: this.orders.slice(0, 8),
    };
  },

  /* ── formatting helpers ── */
  fmt(amount)   { return this.settings.currency + Number(amount).toFixed(2); },
  fmtDate(iso)  { return new Date(iso).toLocaleDateString('en-US', { month:'short', day:'numeric', year:'numeric' }); },
  fmtTime(iso)  { return new Date(iso).toLocaleTimeString('en-US', { hour:'2-digit', minute:'2-digit' }); },
  fmtDT(iso)    { return this.fmtDate(iso) + ' · ' + this.fmtTime(iso); },
};

/* ═══════════════════════════════════════════
   SHARED UI UTILITIES
   ═══════════════════════════════════════════ */
const UIUtils = {
  /* ── Toast ── */
  showToast(message, type = 'success', duration = 2800) {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const icons = { success:'check_circle', error:'error', warn:'warning', info:'info' };
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.innerHTML = `<span class="material-symbols-outlined">${icons[type] || 'info'}</span><span>${message}</span>`;
    container.appendChild(el);

    setTimeout(() => {
      el.classList.add('exit');
      setTimeout(() => el.remove(), 280);
    }, duration);
  },

  /* ── Theme toggle button ── */
  setupThemeToggle() {
    const btn = document.getElementById('theme-toggle');
    if (!btn) return;
    const sync = () => {
      const dark = AppStore.settings.theme === 'dark';
      btn.innerHTML = `<span class="material-symbols-outlined">${dark ? 'light_mode' : 'dark_mode'}</span>`;
      btn.title = dark ? 'Switch to light mode' : 'Switch to dark mode';
    };
    sync();
    btn.addEventListener('click', () => { AppStore.toggleTheme(); sync(); });
  },

  /* ── Active nav item ── */
  setActivePage(pageKey) {
    document.querySelectorAll('[data-page]').forEach(el => {
      el.classList.toggle('active', el.dataset.page === pageKey);
    });
  },

  /* ── Modal open/close ── */
  openModal(id)  { document.getElementById(id)?.classList.add('open'); },
  closeModal(id) { document.getElementById(id)?.classList.remove('open'); },

  /* ── Category CSS class ── */
  catClass(category) {
    return { Coffee:'cat-coffee', Pastries:'cat-pastries', Merchandise:'cat-merch', Seasonal:'cat-seasonal' }[category] || 'cat-default';
  },

  /* ── Payment chip color ── */
  paymentChip(method) {
    return { Cash:'green', Card:'blue', 'Mobile Pay':'orange' }[method] || 'gray';
  },
};

window.AppStore = AppStore;
window.UIUtils  = UIUtils;
