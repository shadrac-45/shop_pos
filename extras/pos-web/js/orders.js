// ============================================================
// ShopPOS — Orders History Logic
// ============================================================

let searchQ       = '';
let dateFilter    = '';
let paymentFilter = 'all';

document.addEventListener('DOMContentLoaded', () => {
  AppStore.init();
  UIUtils.setupThemeToggle();
  UIUtils.setActivePage('orders');
  renderOrders();

  document.getElementById('orders-search').addEventListener('input', e => {
    searchQ = e.target.value;
    renderOrders();
  });

  document.getElementById('date-filter').addEventListener('change', e => {
    dateFilter = e.target.value;
    renderOrders();
  });
});

/* ── PAYMENT FILTER ── */
function filterByPayment(method) {
  paymentFilter = method;
  ['all','Cash','Card','Mobile Pay'].forEach(m => {
    const key = m === 'all' ? 'pay-all' : m === 'Cash' ? 'pay-cash' : m === 'Card' ? 'pay-card' : 'pay-mobile';
    const el  = document.getElementById(key);
    if (el) el.classList.toggle('active', m === method);
  });
  renderOrders();
}

function clearDateFilter() {
  document.getElementById('date-filter').value = '';
  dateFilter = '';
  renderOrders();
}

/* ── RENDER ── */
function renderOrders() {
  let orders = AppStore.getOrders(searchQ, dateFilter);

  if (paymentFilter !== 'all') {
    orders = orders.filter(o => o.paymentMethod === paymentFilter);
  }

  /* Summary label */
  const totalRev = orders.reduce((s, o) => s + o.total, 0);
  document.getElementById('order-summary-label').textContent =
    `${orders.length} order${orders.length !== 1 ? 's' : ''} · ${AppStore.fmt(totalRev)} total`;

  const container = document.getElementById('orders-list');

  if (!orders.length) {
    container.innerHTML = `
      <div class="empty-state">
        <span class="material-symbols-outlined">receipt_long</span>
        <h3>No orders found</h3>
        <p>Orders will appear here after checkout. Try adjusting your filters.</p>
      </div>`;
    return;
  }

  container.innerHTML = orders.map((order, idx) => `
    <div class="order-card" id="order-${order.id}" style="animation-delay:${idx * 30}ms">

      <div class="order-card-head" onclick="toggleOrder('${order.id}')">
        <div style="flex:1;min-width:0">
          <div style="font-weight:800;font-size:14px;color:var(--text);font-family:var(--font-mono)">${order.id}</div>
          <div style="font-size:11px;color:var(--text-muted);margin-top:2px">${AppStore.fmtDT(order.timestamp)}</div>
        </div>
        <div style="display:flex;align-items:center;gap:10px;flex-shrink:0">
          <span class="chip chip-${UIUtils.paymentChip(order.paymentMethod)}">${order.paymentMethod}</span>
          <div style="text-align:right">
            <div style="font-family:var(--font-mono);font-weight:800;color:var(--primary);font-size:15px">${AppStore.fmt(order.total)}</div>
            <div style="font-size:11px;color:var(--text-muted)">${order.items.length} item${order.items.length !== 1 ? 's' : ''}</div>
          </div>
          <span class="material-symbols-outlined order-chevron">expand_more</span>
        </div>
      </div>

      <div class="order-card-body">
        <div style="display:flex;flex-direction:column;gap:4px;margin-bottom:12px">
          ${order.items.map(i => `
            <div style="display:flex;justify-content:space-between;align-items:center;font-size:13px;padding:3px 0">
              <span style="color:var(--text-2)">${i.emoji} ${i.name} × ${i.qty}${i.note ? ` <span style="color:var(--text-muted)">· ${i.note}</span>` : ''}</span>
              <span style="font-family:var(--font-mono);color:var(--text)">${AppStore.fmt(i.price * i.qty)}</span>
            </div>`).join('')}
        </div>
        <div style="border-top:1px solid var(--border);padding-top:10px;display:flex;flex-direction:column;gap:4px">
          ${order.discountAmount > 0.001 ? `
            <div style="display:flex;justify-content:space-between;font-size:12px">
              <span style="color:var(--success)">Discount</span>
              <span style="font-family:var(--font-mono);color:var(--success)">-${AppStore.fmt(order.discountAmount)}</span>
            </div>` : ''}
          <div style="display:flex;justify-content:space-between;font-size:12px;color:var(--text-3)">
            <span>Tax (8%)</span>
            <span style="font-family:var(--font-mono)">${AppStore.fmt(order.tax)}</span>
          </div>
          <div style="display:flex;justify-content:space-between;font-size:15px;font-weight:800">
            <span style="color:var(--text)">Total</span>
            <span style="font-family:var(--font-mono);color:var(--primary)">${AppStore.fmt(order.total)}</span>
          </div>
          ${order.paymentMethod === 'Cash' ? `
            <div style="display:flex;justify-content:space-between;font-size:12px;color:var(--text-3);margin-top:4px">
              <span>Tendered</span>
              <span style="font-family:var(--font-mono)">${AppStore.fmt(order.tendered)}</span>
            </div>
            <div style="display:flex;justify-content:space-between;font-size:12px;font-weight:700">
              <span style="color:var(--primary)">Change</span>
              <span style="font-family:var(--font-mono);color:var(--primary)">${AppStore.fmt(order.change)}</span>
            </div>` : ''}
        </div>
      </div>

    </div>`).join('');
}

function toggleOrder(id) {
  document.getElementById(`order-${id}`)?.classList.toggle('expanded');
}

/* ── CSV EXPORT ── */
function exportCSV() {
  const orders = AppStore.getOrders(searchQ, dateFilter);
  if (!orders.length) { UIUtils.showToast('No orders to export', 'warn'); return; }

  const rows = [['Order ID','Date','Time','Items','Raw Subtotal','Discount','Subtotal','Tax','Total','Payment Method']];
  orders.forEach(o => {
    rows.push([
      o.id,
      AppStore.fmtDate(o.timestamp),
      AppStore.fmtTime(o.timestamp),
      o.items.map(i => `${i.name}×${i.qty}`).join('; '),
      o.rawSubtotal.toFixed(2),
      o.discountAmount.toFixed(2),
      o.subtotal.toFixed(2),
      o.tax.toFixed(2),
      o.total.toFixed(2),
      o.paymentMethod,
    ]);
  });

  const csv  = rows.map(r => r.map(c => `"${String(c).replace(/"/g,'""')}"`).join(',')).join('\n');
  const blob = new Blob([csv], { type: 'text/csv' });
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href     = url;
  a.download = `shoppos-orders-${new Date().toISOString().split('T')[0]}.csv`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  UIUtils.showToast('Orders exported successfully', 'success');
}
