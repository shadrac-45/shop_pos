// ============================================================
// ShopPOS — Sales Terminal (POS) Logic
// ============================================================

/* ── STATE ── */
let selectedCategory = 'All';
let searchQuery      = '';
let discountVal      = 0;
let discountType     = 'percent';
let selectedPayment  = 'Cash';

/* ── BOOT ── */
document.addEventListener('DOMContentLoaded', () => {
  AppStore.init();
  UIUtils.setupThemeToggle();
  UIUtils.setActivePage('pos');
  renderCategories();
  renderProducts();
  renderCart();
  initEventListeners();
});

/* ═══════════════════════════════════════════
   EVENT WIRING
   ═══════════════════════════════════════════ */
function initEventListeners() {
  /* Search */
  const searchIn    = document.getElementById('search-input');
  const searchClear = document.getElementById('search-clear');

  searchIn.addEventListener('input', e => {
    searchQuery = e.target.value;
    searchClear.style.display = searchQuery ? 'flex' : 'none';
    renderProducts();
  });

  searchClear.addEventListener('click', () => {
    searchIn.value  = '';
    searchQuery     = '';
    searchClear.style.display = 'none';
    renderProducts();
    searchIn.focus();
  });

  /* Discount */
  document.getElementById('discount-value').addEventListener('input', e => {
    discountVal = parseFloat(e.target.value) || 0;
    updateTotals();
  });
  document.getElementById('discount-type').addEventListener('change', e => {
    discountType = e.target.value;
    updateTotals();
  });

  /* Payment method selector */
  document.querySelectorAll('.payment-method').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.payment-method').forEach(b => b.classList.remove('selected'));
      btn.classList.add('selected');
      selectedPayment = btn.dataset.method;
      updatePaymentSection();
    });
  });

  /* Tendered input keyboard shortcuts */
  document.getElementById('tendered-input').addEventListener('keydown', e => {
    if (e.key === 'Enter') confirmCharge();
  });
}

/* ═══════════════════════════════════════════
   CATEGORIES
   ═══════════════════════════════════════════ */
function renderCategories() {
  const container = document.getElementById('categories');
  const cats      = AppStore.getCategories();
  container.innerHTML = cats.map(cat => {
    const icon = { All:'apps', Coffee:'local_cafe', Pastries:'bakery_dining', Merchandise:'shopping_bag', Seasonal:'eco' }[cat] || 'category';
    return `<button class="pill ${cat === selectedCategory ? 'active' : ''}" onclick="selectCategory('${cat}')">
      <span class="material-symbols-outlined" style="font-size:14px">${icon}</span>${cat}
    </button>`;
  }).join('');
}

function selectCategory(cat) {
  selectedCategory = cat;
  renderCategories();
  renderProducts();
}

/* ═══════════════════════════════════════════
   PRODUCTS
   ═══════════════════════════════════════════ */
function renderProducts() {
  const grid     = document.getElementById('product-grid');
  const category = selectedCategory === 'All' ? null : selectedCategory;
  const products = AppStore.getProducts(category, searchQuery);

  if (!products.length) {
    grid.innerHTML = `
      <div class="empty-state" style="grid-column:1/-1">
        <span class="material-symbols-outlined">search_off</span>
        <h3>No products found</h3>
        <p>Try adjusting your search or selecting a different category</p>
      </div>`;
    return;
  }

  grid.innerHTML = products.map(p => {
    const cartItem   = AppStore.getCartItem(p.id);
    const qty        = cartItem ? cartItem.qty : 0;
    const catCls     = UIUtils.catClass(p.category);
    const isOutStock = p.stock <= 0;

    return `
      <div class="product-card ${isOutStock ? 'out-of-stock' : ''}"
           id="pcard-${p.id}"
           onclick="${!isOutStock ? `addToCart('${p.id}')` : ''}">
        <div class="product-card-img ${catCls}">
          <span>${p.emoji}</span>
        </div>
        <div class="product-card-body">
          <div class="product-card-name">${p.name}</div>
          <div class="product-card-price">${AppStore.fmt(p.price)}</div>
          <div class="product-card-stock">
            ${isOutStock ? '⚠️ Out of stock' : `${p.stock} in stock`}
          </div>
        </div>
        <div class="product-card-badge ${qty > 0 ? 'show' : ''}" id="badge-${p.id}">${qty}</div>
      </div>`;
  }).join('');
}

function addToCart(productId) {
  const ok = AppStore.addToCart(productId);
  if (ok) {
    refreshProductBadge(productId);
    renderCart();
    UIUtils.showToast(`${AppStore.getProductById(productId).name} added`, 'success', 1600);
  } else {
    const badge = document.getElementById(`badge-${productId}`);
    if (badge) { badge.style.animation = 'none'; requestAnimationFrame(() => { badge.style.animation = ''; }); }
    UIUtils.showToast('Maximum stock reached', 'warn', 2000);
  }
}

function refreshProductBadge(productId) {
  const badge    = document.getElementById(`badge-${productId}`);
  const cartItem = AppStore.getCartItem(productId);
  const qty      = cartItem ? cartItem.qty : 0;
  if (!badge) return;
  badge.textContent = qty;
  badge.classList.toggle('show', qty > 0);
}

/* ═══════════════════════════════════════════
   CART RENDERING
   ═══════════════════════════════════════════ */
function renderCart() {
  const container = document.getElementById('cart-items');
  const chargeBtn = document.getElementById('charge-btn');
  const cart      = AppStore.cart;
  const count     = AppStore.getCartCount();

  /* Update count badge with bump animation */
  const countEl = document.getElementById('cart-count');
  const prev    = parseInt(countEl.textContent) || 0;
  countEl.textContent = count;
  if (count > prev) {
    countEl.classList.remove('bump');
    void countEl.offsetWidth; // reflow
    countEl.classList.add('bump');
  }

  /* Update mobile preview bar */
  document.getElementById('preview-count').textContent = `${count} item${count !== 1 ? 's' : ''}`;
  document.getElementById('preview-total').textContent  = AppStore.fmt(AppStore.getTotal(discountVal, discountType));

  if (!cart.length) {
    container.innerHTML = `
      <div class="cart-empty">
        <span class="material-symbols-outlined">shopping_basket</span>
        <p>No items yet.<br>Tap a product to add it.</p>
      </div>`;
    chargeBtn.disabled = true;
    updateTotals();
    return;
  }

  chargeBtn.disabled = false;

  container.innerHTML = cart.map(item => `
    <div class="cart-item" id="citem-${item.productId}">
      <div class="cart-item-emoji">${item.emoji}</div>
      <div class="cart-item-info" style="cursor:pointer;min-width:0" onclick="toggleNote('${item.productId}')">
        <div class="cart-item-name">${item.name}</div>
        <div class="cart-item-note" id="note-preview-${item.productId}">
          ${item.note ? `📝 ${item.note}` : '<span style="color:var(--text-muted);font-size:11px">+ Add note</span>'}
        </div>
        <input class="input-field input-sm cart-item-note-input" id="note-input-${item.productId}"
          type="text" placeholder="Add note (e.g. Extra hot)…"
          value="${item.note || ''}"
          onclick="event.stopPropagation()"
          onblur="saveNote('${item.productId}', this.value)"
          onkeydown="if(event.key==='Enter'){this.blur()}"
          style="margin-top:4px;font-size:12px"/>
      </div>
      <div class="cart-qty-controls">
        <button class="qty-btn" onclick="decreaseQty('${item.productId}')" title="Decrease">
          <span class="material-symbols-outlined" style="font-size:15px">remove</span>
        </button>
        <span class="qty-value">${item.qty}</span>
        <button class="qty-btn" onclick="increaseQty('${item.productId}')" title="Increase">
          <span class="material-symbols-outlined" style="font-size:15px">add</span>
        </button>
      </div>
      <div class="cart-item-price">${AppStore.fmt(item.price * item.qty)}</div>
      <button class="cart-delete" onclick="removeCartItem('${item.productId}')" title="Remove">
        <span class="material-symbols-outlined" style="font-size:16px">delete</span>
      </button>
    </div>`).join('');

  updateTotals();
}

function toggleNote(productId) {
  const inp = document.getElementById(`note-input-${productId}`);
  if (!inp) return;
  inp.classList.toggle('open');
  if (inp.classList.contains('open')) inp.focus();
}

function saveNote(productId, note) {
  AppStore.setCartNote(productId, note.trim());
  /* Update preview without full re-render */
  const preview = document.getElementById(`note-preview-${productId}`);
  if (preview) {
    const n = note.trim();
    preview.innerHTML = n ? `📝 ${n}` : '<span style="color:var(--text-muted);font-size:11px">+ Add note</span>';
  }
}

function increaseQty(productId) {
  const ok = AppStore.addToCart(productId);
  if (!ok) { UIUtils.showToast('Max stock reached', 'warn', 1800); return; }
  refreshProductBadge(productId);
  renderCart();
}

function decreaseQty(productId) {
  AppStore.decreaseQty(productId);
  refreshProductBadge(productId);
  renderCart();
}

function removeCartItem(productId) {
  AppStore.removeCartItem(productId);
  refreshProductBadge(productId);
  renderCart();
}

function clearOrder() {
  if (!AppStore.cart.length) return;
  if (!confirm('Clear the current order?')) return;
  AppStore.cart.forEach(i => {
    const b = document.getElementById(`badge-${i.productId}`);
    if (b) { b.textContent = '0'; b.classList.remove('show'); }
  });
  AppStore.clearCart();
  renderCart();
  UIUtils.showToast('Order cleared', 'info');
}

/* ── TOTALS ── */
function updateTotals() {
  const rawSub    = AppStore.getRawSubtotal();
  const sub       = AppStore.getSubtotal(discountVal, discountType);
  const tax       = AppStore.getTax(sub);
  const total     = sub + tax;
  const discAmt   = rawSub - sub;

  document.getElementById('cart-subtotal').textContent = AppStore.fmt(sub);
  document.getElementById('cart-tax').textContent      = AppStore.fmt(tax);
  document.getElementById('cart-total').textContent    = AppStore.fmt(total);
  document.getElementById('preview-total').textContent = AppStore.fmt(total);

  const discRow = document.getElementById('discount-row');
  if (discAmt > 0.001) {
    discRow.style.display = 'flex';
    document.getElementById('cart-discount').textContent = '-' + AppStore.fmt(discAmt);
  } else {
    discRow.style.display = 'none';
  }
}

/* ═══════════════════════════════════════════
   MOBILE CART SHEET
   ═══════════════════════════════════════════ */
function toggleMobileCart() {
  const sidebar  = document.getElementById('cart-sidebar');
  const overlay  = document.getElementById('cart-overlay');
  const isOpen   = sidebar.classList.contains('cart-open');
  if (isOpen) {
    sidebar.classList.remove('cart-open');
    overlay.classList.remove('open');
  } else {
    sidebar.classList.add('cart-open');
    overlay.classList.add('open');
  }
}

/* ═══════════════════════════════════════════
   CHECKOUT MODAL
   ═══════════════════════════════════════════ */
function openCheckout() {
  if (!AppStore.cart.length) return;

  const total = AppStore.getTotal(discountVal, discountType);
  document.getElementById('checkout-total').textContent = AppStore.fmt(total);
  document.getElementById('tendered-input').value       = '';
  document.getElementById('change-display').textContent = '';

  /* Mini items summary */
  document.getElementById('checkout-items').innerHTML = AppStore.cart.map(i =>
    `<div style="display:flex;justify-content:space-between;font-size:12px;color:var(--text-3)">
       <span>${i.emoji} ${i.name} × ${i.qty}</span>
       <span style="font-family:var(--font-mono)">${AppStore.fmt(i.price * i.qty)}</span>
     </div>`).join('');

  /* Reset to Cash */
  document.querySelectorAll('.payment-method').forEach(b => b.classList.remove('selected'));
  document.querySelector('[data-method="Cash"]').classList.add('selected');
  selectedPayment = 'Cash';
  updatePaymentSection();

  /* Quick-tendered amounts */
  buildQuickAmounts(total);

  document.getElementById('confirm-btn').disabled = false;
  UIUtils.openModal('checkout-overlay');

  /* Auto-focus tendered field */
  setTimeout(() => document.getElementById('tendered-input').focus(), 320);
}

function buildQuickAmounts(total) {
  const container = document.getElementById('quick-amounts');
  const rounded   = Math.ceil(total);
  const opts      = new Set([rounded, Math.ceil(total / 5) * 5, Math.ceil(total / 10) * 10, Math.ceil(total / 20) * 20]);
  container.innerHTML = [...opts].filter(v => v >= total).sort((a,b)=>a-b).slice(0,4).map(v =>
    `<button class="btn btn-secondary btn-sm" onclick="document.getElementById('tendered-input').value='${v.toFixed(2)}';calcChange()">
       $${v.toFixed(2)}
     </button>`).join('');
}

function updatePaymentSection() {
  const isCash = selectedPayment === 'Cash';
  document.getElementById('cash-section').style.display = isCash ? 'block' : 'none';
  document.getElementById('card-section').style.display = isCash ? 'none'  : 'flex';
  if (!isCash) {
    document.getElementById('card-section').style.display = 'block';
    document.getElementById('confirm-btn').disabled = false;
  }
}

function calcChange() {
  const total    = AppStore.getTotal(discountVal, discountType);
  const tendered = parseFloat(document.getElementById('tendered-input').value) || 0;
  const change   = tendered - total;
  const el       = document.getElementById('change-display');
  const confirmBtn = document.getElementById('confirm-btn');

  if (tendered > 0) {
    if (change < -0.001) {
      el.textContent = `Still owe: ${AppStore.fmt(Math.abs(change))}`;
      el.style.color = 'var(--error)';
      confirmBtn.disabled = true;
    } else {
      el.textContent = `Change due: ${AppStore.fmt(change)}`;
      el.style.color = 'var(--success)';
      confirmBtn.disabled = false;
    }
  } else {
    el.textContent = '';
    confirmBtn.disabled = true;
  }
}

function closeCheckout() { UIUtils.closeModal('checkout-overlay'); }

function confirmCharge() {
  const total    = AppStore.getTotal(discountVal, discountType);
  const tendered = selectedPayment === 'Cash'
    ? parseFloat(document.getElementById('tendered-input').value) || 0
    : total;

  if (selectedPayment === 'Cash' && tendered < total - 0.001) {
    UIUtils.showToast('Tendered amount is insufficient', 'error');
    return;
  }

  const order = AppStore.placeOrder({
    paymentMethod: selectedPayment,
    tendered,
    discountVal,
    discountType,
  });

  /* Reset discount */
  discountVal  = 0;
  discountType = 'percent';
  document.getElementById('discount-value').value = '';
  document.getElementById('discount-type').value  = 'percent';

  closeCheckout();
  renderCart();
  renderProducts(); /* refresh stock counts */

  showReceipt(order);
}

/* ═══════════════════════════════════════════
   RECEIPT MODAL
   ═══════════════════════════════════════════ */
function showReceipt(order) {
  document.getElementById('r-id').textContent     = order.id;
  document.getElementById('r-dt').textContent     = AppStore.fmtDT(order.timestamp);
  document.getElementById('r-method').textContent = order.paymentMethod;

  /* Items */
  document.getElementById('r-items').innerHTML = order.items.map(i =>
    `<div class="receipt-item-row">
       <span class="receipt-item-left">${i.emoji} ${i.name} × ${i.qty}${i.note ? ` (${i.note})` : ''}</span>
       <span class="receipt-item-right">${AppStore.fmt(i.price * i.qty)}</span>
     </div>`).join('');

  /* Totals */
  document.getElementById('r-sub').textContent   = AppStore.fmt(order.subtotal);
  document.getElementById('r-tax').textContent   = AppStore.fmt(order.tax);
  document.getElementById('r-total').textContent = AppStore.fmt(order.total);

  /* Discount */
  const discRow = document.getElementById('r-disc-row');
  if (order.discountAmount > 0.001) {
    discRow.style.display = 'flex';
    document.getElementById('r-disc').textContent = '-' + AppStore.fmt(order.discountAmount);
  } else {
    discRow.style.display = 'none';
  }

  /* Cash change */
  const cashRows = document.getElementById('r-cash-rows');
  if (order.paymentMethod === 'Cash') {
    cashRows.style.display = 'block';
    document.getElementById('r-tendered').textContent = AppStore.fmt(order.tendered);
    document.getElementById('r-change').textContent   = AppStore.fmt(order.change);
  } else {
    cashRows.style.display = 'none';
  }

  UIUtils.openModal('receipt-overlay');
  UIUtils.showToast(`Order ${order.id} completed! 🎉`, 'success', 3500);
}

function closeReceipt()   { UIUtils.closeModal('receipt-overlay'); }

function printReceipt()   { window.print(); }

function startNewOrder()  {
  closeReceipt();
  UIUtils.showToast('Ready for next order!', 'info', 2000);
}
