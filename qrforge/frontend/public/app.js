/**
 * QRForge — Frontend Application Logic
 * ======================================
 * Handles: tab switching, template gallery, QR generation API calls,
 * canvas rendering with optional overlay text, download (PNG/SVG),
 * clipboard copy, history/stats panels, and theme toggle.
 */

'use strict';

// ─────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────
const state = {
  currentType:     'url',
  selectedTemplate:'minimal-mono',
  templates:       [],
  lastPngBlob:     null,
  lastSvgText:     null,
  lastQRParams:    null,
  generating:      false,
};

// ─────────────────────────────────────────────────────────────
// DOM references
// ─────────────────────────────────────────────────────────────
const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => [...document.querySelectorAll(sel)];

const elPreviewCanvas    = $('#previewCanvas');
const elPreviewPlaceholder = $('#previewPlaceholder');
const elPreviewSpinner   = $('#previewSpinner');
const elPreviewWrap      = $('#previewWrap');
const elCacheBadge       = $('#cacheBadge');
const elPodName          = $('#podName');
const elFooterPod        = $('#footerPod');
const elTemplateGrid     = $('#templateGrid');
const elHistoryList      = $('#historyList');
const elSizeSlider       = $('#ctrl-size');
const elSizeValue        = $('#sizeValue');
const elFgPicker         = $('#ctrl-fg');
const elBgPicker         = $('#ctrl-bg');
const elFgValue          = $('#fgValue');
const elBgValue          = $('#bgValue');
const elEccSelect        = $('#ctrl-ecc');
const elOverlay          = $('#ctrl-overlay');
const elBtnGenerate      = $('#btn-generate');
const elBtnDownloadPng   = $('#btn-download-png');
const elBtnDownloadSvg   = $('#btn-download-svg');
const elBtnCopy          = $('#btn-copy');
const elBtnStats         = $('#btn-stats');
const elBtnRefreshHistory= $('#btn-refresh-history');
const elBtnRefreshStats  = $('#btn-refresh-stats');

// Toast container (created once)
const toastContainer = document.createElement('div');
toastContainer.className = 'toast-container';
document.body.appendChild(toastContainer);

// ─────────────────────────────────────────────────────────────
// Toast notifications
// ─────────────────────────────────────────────────────────────
function showToast(msg, type = 'info', duration = 3000) {
  const el = document.createElement('div');
  el.className = `toast toast--${type}`;
  el.textContent = msg;
  toastContainer.appendChild(el);
  setTimeout(() => {
    el.classList.add('removing');
    el.addEventListener('animationend', () => el.remove(), { once: true });
  }, duration);
}

// ─────────────────────────────────────────────────────────────
// Theme toggle
// ─────────────────────────────────────────────────────────────
const elThemeToggle = $('#themeToggle');
const elThemeIcon   = elThemeToggle?.querySelector('.theme-icon');

function applyTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  localStorage.setItem('qrforge-theme', theme);
  if (elThemeIcon) elThemeIcon.textContent = theme === 'dark' ? '🌙' : '☀️';
}

// Restore saved theme
applyTheme(localStorage.getItem('qrforge-theme') || 'dark');

elThemeToggle?.addEventListener('click', () => {
  const current = document.documentElement.getAttribute('data-theme');
  applyTheme(current === 'dark' ? 'light' : 'dark');
});

// ─────────────────────────────────────────────────────────────
// Tab switching
// ─────────────────────────────────────────────────────────────
$$('.tab').forEach(tab => {
  tab.addEventListener('click', () => {
    const type = tab.dataset.type;
    $$('.tab').forEach(t => {
      t.classList.remove('tab--active');
      t.setAttribute('aria-selected', 'false');
    });
    tab.classList.add('tab--active');
    tab.setAttribute('aria-selected', 'true');
    $$('.input-group').forEach(g => g.classList.add('hidden'));
    $(`#fields-${type}`)?.classList.remove('hidden');
    state.currentType = type;
  });
});

// ─────────────────────────────────────────────────────────────
// Controls
// ─────────────────────────────────────────────────────────────
elSizeSlider?.addEventListener('input', () => {
  elSizeValue.textContent = elSizeSlider.value;
});
elFgPicker?.addEventListener('input', () => { elFgValue.textContent = elFgPicker.value; });
elBgPicker?.addEventListener('input', () => { elBgValue.textContent = elBgPicker.value; });

// ─────────────────────────────────────────────────────────────
// Build request payload from current UI state
// ─────────────────────────────────────────────────────────────
function buildPayload(format = 'png') {
  const type = state.currentType;
  const base = {
    type,
    template: state.selectedTemplate,
    size:     parseInt(elSizeSlider?.value || '512', 10),
    fg:       elFgPicker?.value,
    bg:       elBgPicker?.value,
    ecc:      elEccSelect?.value,
    format,
  };

  switch (type) {
    case 'url':   return { ...base, data: $('#input-url')?.value.trim() };
    case 'text':  return { ...base, data: $('#input-text')?.value.trim() };
    case 'wifi':  return { ...base, ssid: $('#input-ssid')?.value.trim(), password: $('#input-password')?.value, encryption: $('#input-encryption')?.value };
    case 'email': return { ...base, email: $('#input-email')?.value.trim(), subject: $('#input-subject')?.value.trim(), body: $('#input-body')?.value.trim() };
    case 'phone': return { ...base, phone: $('#input-phone')?.value.trim() };
    case 'vcard': return { ...base, name: $('#input-vname')?.value.trim(), org: $('#input-vorg')?.value.trim(), phone: $('#input-vphone')?.value.trim(), email: $('#input-vemail')?.value.trim(), url: $('#input-vurl')?.value.trim() };
    default:      return base;
  }
}

/** Validate that the required fields are filled for the current type */
function validate() {
  const type = state.currentType;
  const missing = (id, label) => {
    const el = $(id);
    if (!el || !el.value.trim()) { showToast(`Please fill in: ${label}`, 'error'); return true; }
    return false;
  };
  switch (type) {
    case 'url':   return !missing('#input-url', 'URL');
    case 'text':  return !missing('#input-text', 'Text');
    case 'wifi':  return !missing('#input-ssid', 'SSID');
    case 'email': return !missing('#input-email', 'Email address');
    case 'phone': return !missing('#input-phone', 'Phone number');
    case 'vcard': return !missing('#input-vname', 'Full name');
    default:      return true;
  }
}

// ─────────────────────────────────────────────────────────────
// Render QR onto canvas (with optional center text overlay)
// ─────────────────────────────────────────────────────────────
function renderToCanvas(imgBlob, overlayText) {
  const url = URL.createObjectURL(imgBlob);
  const img = new Image();
  img.onload = () => {
    const ctx = elPreviewCanvas.getContext('2d');
    elPreviewCanvas.width  = 300;
    elPreviewCanvas.height = 300;
    ctx.drawImage(img, 0, 0, 300, 300);
    URL.revokeObjectURL(url);

    if (overlayText && overlayText.trim()) {
      // Draw white rounded rect + text in center for logo-area effect
      const cx = 150, cy = 150;
      const text = overlayText.trim().toUpperCase();
      ctx.font = 'bold 14px Inter, sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      const tw = ctx.measureText(text).width;
      const pad = 8, rh = 24, rw = tw + pad * 2;
      const rx = cx - rw / 2, ry = cy - rh / 2;
      // White pill background
      ctx.fillStyle = 'white';
      ctx.beginPath();
      ctx.roundRect(rx, ry, rw, rh, 6);
      ctx.fill();
      // Dark text
      ctx.fillStyle = '#111';
      ctx.fillText(text, cx, cy);
    }

    elPreviewCanvas.classList.add('visible');
    elPreviewPlaceholder.classList.add('hidden');
  };
  img.src = url;
}

// ─────────────────────────────────────────────────────────────
// Generate QR
// ─────────────────────────────────────────────────────────────
async function generateQR() {
  if (state.generating) return;
  if (!validate()) return;

  state.generating = true;
  elBtnGenerate.classList.add('loading');
  elPreviewSpinner.classList.remove('hidden');
  elBtnDownloadPng.disabled = true;
  elBtnDownloadSvg.disabled = true;
  elBtnCopy.disabled        = true;

  const payload = buildPayload('png');

  try {
    // ── Fetch PNG ──
    const pngRes = await fetch('/api/qr', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (!pngRes.ok) {
      const err = await pngRes.json().catch(() => ({ error: 'Unknown error' }));
      throw new Error(err.error || `HTTP ${pngRes.status}`);
    }

    const cacheHeader = pngRes.headers.get('X-Cache');
    const pod         = pngRes.headers.get('X-Pod');
    const pngBlob     = await pngRes.blob();

    state.lastPngBlob  = pngBlob;
    state.lastQRParams = payload;

    // Update pod info
    if (pod) {
      elPodName.textContent  = pod;
      elFooterPod.textContent = pod;
    }

    // Update cache badge
    if (elCacheBadge) {
      elCacheBadge.textContent = cacheHeader === 'HIT' ? 'Cache HIT' : 'Cache MISS';
      elCacheBadge.className   = `cache-badge ${cacheHeader === 'HIT' ? 'hit' : 'miss'}`;
    }

    // Render to canvas
    renderToCanvas(pngBlob, elOverlay?.value);

    // ── Fetch SVG in background ──
    fetch('/api/qr', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...payload, format: 'svg' }),
    }).then(r => r.ok ? r.text() : null).then(svg => {
      state.lastSvgText = svg;
      elBtnDownloadSvg.disabled = !svg;
    }).catch(() => {});

    elBtnDownloadPng.disabled = false;
    elBtnCopy.disabled        = false;

    // Refresh history
    setTimeout(loadHistory, 500);

  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
    console.error('QR generation failed:', err);
  } finally {
    state.generating = false;
    elBtnGenerate.classList.remove('loading');
    elPreviewSpinner.classList.add('hidden');
  }
}

elBtnGenerate?.addEventListener('click', generateQR);

// Generate on Enter key in URL/Phone/Name fields
['#input-url','#input-phone','#input-vname'].forEach(sel => {
  $(sel)?.addEventListener('keydown', e => { if (e.key === 'Enter') generateQR(); });
});

// ─────────────────────────────────────────────────────────────
// Downloads
// ─────────────────────────────────────────────────────────────
elBtnDownloadPng?.addEventListener('click', () => {
  if (!state.lastPngBlob) return;
  const url = URL.createObjectURL(state.lastPngBlob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `qrforge-${state.selectedTemplate}-${Date.now()}.png`;
  a.click();
  URL.revokeObjectURL(url);
  showToast('PNG downloaded!', 'success');
});

elBtnDownloadSvg?.addEventListener('click', () => {
  if (!state.lastSvgText) return;
  const blob = new Blob([state.lastSvgText], { type: 'image/svg+xml' });
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href     = url;
  a.download = `qrforge-${state.selectedTemplate}-${Date.now()}.svg`;
  a.click();
  URL.revokeObjectURL(url);
  showToast('SVG downloaded!', 'success');
});

// ─────────────────────────────────────────────────────────────
// Copy to clipboard
// ─────────────────────────────────────────────────────────────
elBtnCopy?.addEventListener('click', async () => {
  if (!state.lastPngBlob) return;
  try {
    await navigator.clipboard.write([
      new ClipboardItem({ 'image/png': state.lastPngBlob }),
    ]);
    showToast('QR code copied to clipboard!', 'success');
  } catch {
    // Fallback: copy canvas data URL
    try {
      const dataUrl = elPreviewCanvas.toDataURL('image/png');
      await navigator.clipboard.writeText(dataUrl);
      showToast('Image data URL copied (clipboard API unavailable)', 'info');
    } catch {
      showToast('Clipboard access denied. Try downloading instead.', 'error');
    }
  }
});

// ─────────────────────────────────────────────────────────────
// Template gallery
// ─────────────────────────────────────────────────────────────
function renderTemplates(templates) {
  elTemplateGrid.innerHTML = '';
  templates.forEach(tmpl => {
    const card = document.createElement('button');
    card.className  = `template-card${state.selectedTemplate === tmpl.id ? ' template-card--active' : ''}`;
    card.id         = `template-${tmpl.id}`;
    card.role       = 'radio';
    card.setAttribute('aria-checked', state.selectedTemplate === tmpl.id ? 'true' : 'false');
    card.setAttribute('aria-label', `Template: ${tmpl.name}`);
    card.style.background = tmpl.cardGradient;
    card.innerHTML = `
      <div class="template-card-name">${tmpl.name}</div>
      <div class="template-card-desc">${tmpl.description}</div>
      <span class="template-card-qr" aria-hidden="true">⬡</span>
    `;
    card.addEventListener('click', () => selectTemplate(tmpl));
    elTemplateGrid.appendChild(card);
  });
}

function selectTemplate(tmpl) {
  state.selectedTemplate = tmpl.id;
  // Update color pickers to match template
  if (elFgPicker) { elFgPicker.value = tmpl.fg; elFgValue.textContent = tmpl.fg; }
  if (elBgPicker) { elBgPicker.value = tmpl.bg; elBgValue.textContent = tmpl.bg; }
  if (elEccSelect) elEccSelect.value = tmpl.ecc;
  // Update card active states
  $$('.template-card').forEach(c => {
    const isActive = c.id === `template-${tmpl.id}`;
    c.classList.toggle('template-card--active', isActive);
    c.setAttribute('aria-checked', isActive ? 'true' : 'false');
  });
  showToast(`Template: ${tmpl.name}`, 'success', 1500);
}

async function loadTemplates() {
  try {
    const res = await fetch('/api/templates');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    state.templates = await res.json();
    renderTemplates(state.templates);
    // Apply first template's colors as defaults
    const first = state.templates.find(t => t.id === state.selectedTemplate) || state.templates[0];
    if (first) selectTemplate(first);
  } catch (err) {
    elTemplateGrid.innerHTML = '<p class="empty-hint">Could not load templates</p>';
  }
}

// ─────────────────────────────────────────────────────────────
// History panel
// ─────────────────────────────────────────────────────────────
function timeAgo(ts) {
  const diff = (Date.now() - ts) / 1000;
  if (diff < 60)   return 'just now';
  if (diff < 3600) return `${Math.floor(diff/60)}m ago`;
  if (diff < 86400)return `${Math.floor(diff/3600)}h ago`;
  return `${Math.floor(diff/86400)}d ago`;
}

async function loadHistory() {
  try {
    const res = await fetch('/api/history');
    if (!res.ok) return;
    const items = await res.json();
    if (!items.length) {
      elHistoryList.innerHTML = '<p class="empty-hint">No history yet — generate your first QR code!</p>';
      return;
    }
    elHistoryList.innerHTML = items.map(item => `
      <div class="history-item">
        <span class="history-chip">${item.type || 'url'}</span>
        <span class="history-preview" title="${escHtml(item.preview || '')}">${escHtml(item.preview || '—')}</span>
        <span class="history-meta">${item.ts ? timeAgo(item.ts) : ''}</span>
      </div>
    `).join('');
  } catch {
    elHistoryList.innerHTML = '<p class="empty-hint">Could not load history</p>';
  }
}

function escHtml(str) {
  return str.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

elBtnRefreshHistory?.addEventListener('click', loadHistory);

// ─────────────────────────────────────────────────────────────
// Stats panel
// ─────────────────────────────────────────────────────────────
async function loadStats() {
  try {
    const res = await fetch('/api/stats');
    if (!res.ok) return;
    const data = await res.json();
    $('#stat-total').textContent  = data.total ?? '0';
    $('#stat-hits').textContent   = data.cache?.hits ?? '0';
    $('#stat-misses').textContent = data.cache?.misses ?? '0';
    const ratio = (data.cache?.hits ?? 0) + (data.cache?.misses ?? 0);
    $('#stat-ratio').textContent  = ratio
      ? ((data.cache.hits / ratio) * 100).toFixed(1) + '%'
      : '—';
  } catch {
    // silently fail
  }
}

elBtnRefreshStats?.addEventListener('click', loadStats);
elBtnStats?.addEventListener('click', () => {
  loadStats();
  $('#statsPanel')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
});

// ─────────────────────────────────────────────────────────────
// Initialise
// ─────────────────────────────────────────────────────────────
async function init() {
  await loadTemplates();
  loadHistory();
  loadStats();
  // Auto-refresh stats every 30s
  setInterval(loadStats, 30_000);
  setInterval(loadHistory, 30_000);
}

init();
