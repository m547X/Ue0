/* The world board's page.
 *
 * It is painted into a texture that the client draws on a flat surface out in
 * the world. The client pushes it a set of rows with SendDuiMessage and the
 * page draws them once. There is no loop and no clock in here on purpose: a
 * DUI texture is repainted whenever the page changes, and that repaint is paid
 * by every machine looking at the board. So the page is still unless it is
 * given something new, and it checks that what it was given is actually
 * different before touching the DOM at all.
 */
'use strict';

const $ = (id) => document.getElementById(id);

const esc = (s) => String(s === undefined || s === null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

const num = (n) => {
  const v = Number(n);
  return Number.isFinite(v) ? v.toLocaleString('en-US') : '0';
};

const initial = (name) => (String(name || '?').trim()[0] || '?').toUpperCase();

/* A rank is a tier and, usually, a division: "ASCENDANT III". Written as one
   run of text it is the longest thing in its column and was being cut off —
   "ASCEND…" tells nobody anything. The division is a numeral, so it is split
   off and set smaller beside the tier, which fits and reads better anyway. */
const DIVISIONS = { I: 1, II: 1, III: 1, IV: 1, V: 1 };

function rankParts(name) {
  const words = String(name || '').trim().toUpperCase().split(/\s+/);
  const last = words[words.length - 1];
  if (words.length > 1 && DIVISIONS[last]) {
    return { tier: words.slice(0, -1).join(' '), div: last };
  }
  return { tier: words.join(' '), div: '' };
}

function rankChip(row, cls) {
  const p = rankParts(row && row.rank);
  if (!p.tier) return `<span class="${cls}"></span>`;
  return `<span class="${cls}" style="color:${esc(tint(row && row.color))}">`
       + `<svg><use href="#crest"/></svg>`
       + `<b>${esc(p.tier)}</b>${p.div ? `<i>${esc(p.div)}</i>` : ''}</span>`;
}

/** A hex colour the config wrote, or the accent if it wrote something odd. */
const tint = (c) => (typeof c === 'string' && /^#[0-9a-f]{3,8}$/i.test(c)) ? c : 'var(--accent)';

/** `#rrggbb` as the bare `r,g,b` triplet a translucent tint needs. */
function rgbOf(hex) {
  const h = String(hex || '').replace('#', '');
  if (h.length !== 6) return null;
  const n = parseInt(h, 16);
  if (!Number.isFinite(n)) return null;
  return `${(n >> 16) & 255},${(n >> 8) & 255},${n & 255}`;
}

function avatar(row, cls) {
  const src = row && row.avatar;
  return `<span class="${cls}">${
    src ? `<img src="${esc(src)}" alt="" onerror="this.remove()"/>` : ''
  }${esc(initial(row && row.name))}</span>`;
}

/* ------------------------------------------------------------------ podium */
function drawPodium(rows) {
  const host = $('bd-stand');
  // second, first, third — the middle one is the tallest, so it is drawn there
  const order = [rows[1], rows[0], rows[2]];
  const place = [2, 1, 3];

  host.innerHTML = order.map((r, i) => {
    const n = place[i];
    const base = `<div class="base">${n}</div>`;
    if (!r) return `<div class="col c${n}"><div class="pod p${n} empty-pod"></div>${base}</div>`;
    const score = num(r.rp);
    return `<div class="col c${n}">
      <div class="pod p${n}">
        ${n === 1 ? '<svg class="pod-crown" viewBox="0 0 64 46"><use href="#crown"/></svg>' : ''}
        ${avatar(r, 'pod-av')}
        <div class="pod-name">${esc(r.name)}</div>
        ${rankChip(r, 'pod-rank')}
        <div class="pod-score${score.length > 5 ? ' long' : ''}">${score}</div>
        <div class="pod-unit">POINTS</div>
        <div class="pod-stats">
          <span>W <b>${num(r.wins)}</b></span>
          <span>L <b>${num(r.losses)}</b></span>
          <span>K <b>${num(r.kills)}</b></span>
          <span>K/D <b>${esc(r.kd)}</b></span>
        </div>
      </div>
      ${base}
    </div>`;
  }).join('');

  fitNames(host);
}

/* A name that has been cut off with an ellipsis is no use to the person whose
   name it is, and a card is only so wide. Counting characters guesses wrong —
   `WWW` is not `iii` — so each one is measured once and stepped down until it
   fits, wrapping onto a second line as a last resort. This reads the layout,
   which is why it happens here and not on every frame: the podium is only
   rebuilt when the standings actually change. */
const NAME_SIZES = [15, 13, 11.5, 10, 9];

function fitNames(host) {
  host.querySelectorAll('.pod-name').forEach((n) => {
    for (let i = 0; i < NAME_SIZES.length; i++) {
      n.style.fontSize = NAME_SIZES[i] + 'px';
      n.style.letterSpacing = i === 0 ? '' : (i < 3 ? '.02em' : '0');
      if (n.scrollWidth <= n.clientWidth) return;
    }
    // still too long: let it wrap rather than lose the end of it
    n.style.whiteSpace = 'normal';
    n.style.overflowWrap = 'anywhere';
    n.style.lineHeight = '1.2';
  });
}

/* ------------------------------------------------------------------- table */
function drawRows(rows, note) {
  const host = $('bd-rows');
  const empty = $('bd-empty');

  if (!rows.length) {
    host.innerHTML = '';
    empty.textContent = note;
    empty.classList.remove('hidden');
    return;
  }
  empty.classList.add('hidden');

  host.innerHTML = rows.map((r, i) => {
    /* The medal tints belong to the actual top three, who are on the podium —
       not to whoever happens to be first in this table. */
    const place = Number(r.position);
    const top = place >= 1 && place <= 3 ? ` top${place}` : '';
    const col = tint(r.color);
    return `<div class="grid row${top}">
      <span class="c-top">#${esc(r.position || i + 1)}</span>
      ${rankChip(r, 'c-rank')}
      <span class="c-player">
        ${avatar(r, 'av')}
        <span class="who"><b>${esc(r.name)}</b><i>#${esc(r.userId)}</i></span>
      </span>
      <span class="c-lvl"><i class="lvl">${esc(r.level || 1)}</i></span>
      <span class="c-num">${num(r.kills)}</span>
      <span class="c-num">${num(r.deaths)}</span>
      <span class="c-num win">${num(r.wins)}</span>
      <span class="c-num loss">${num(r.losses)}</span>
      <span class="c-num kd">${esc(r.kd)}</span>
      <span class="c-num c-score">${num(r.rp)}</span>
    </div>`;
  }).join('');
}

/* The page is built for 1280x720 and scaled onto the texture it was actually
   given. Reading the size once on load is enough — a DUI surface never
   changes size — but the listener costs nothing and covers a client that
   rebuilds the board at a different size without reloading the page. */
const DESIGN_W = 1280, DESIGN_H = 720;

function fitToSurface() {
  const w = window.innerWidth || DESIGN_W;
  const h = window.innerHeight || DESIGN_H;
  const s = Math.min(w / DESIGN_W, h / DESIGN_H) || 1;
  document.documentElement.style.setProperty('--s', s);
}

fitToSurface();
window.addEventListener('resize', fitToSurface);

/* -------------------------------------------------------------------- skin */
/* Only something that really is a colour is allowed through. A CSS variable
   set to nonsense does not fall back to what it was — it makes every property
   that reads it invalid, so one bad value in the config would turn the page's
   own background transparent and the board would go invisible in the world
   with nothing anywhere to say why. */
const COLOUR = /^(#[0-9a-f]{3,8}|rgba?\([\d\s.,%]+\)|hsla?\([\d\s.,%deg]+\))$/i;
const colourOf = (v) => (typeof v === 'string' && COLOUR.test(v.trim()) ? v.trim() : null);

function applyTheme(t) {
  if (!t) return;
  const root = document.documentElement.style;
  const set = (name, value) => {
    const c = colourOf(value);
    if (c) root.setProperty(name, c);
  };

  const accent = colourOf(t.accent);
  if (accent) {
    root.setProperty('--accent', accent);
    const rgb = rgbOf(accent);
    if (rgb) root.setProperty('--accent-rgb', rgb);
  }
  set('--gold', t.gold);
  set('--text', t.text);
  set('--dim', t.dim);
  set('--bg', t.bg);
  set('--panel', t.panel);
}

function applyBrand(b) {
  if (!b) return;
  $('bd-name').textContent   = b.name || 'M5';
  $('bd-accent').textContent = b.accent || '';
}

/* ------------------------------------------------------------------ inputs */
/* Redrawing costs a repaint of the whole texture for everyone looking at it,
   so a payload that says the same thing as the last one is dropped here. */
let lastKey = '';

function render(d) {
  if (!d) return;

  applyTheme(d.theme);
  applyBrand(d.brand);

  if (d.title) $('bd-podium-title').textContent = d.title;
  if (d.season) $('bd-season').textContent = d.season;
  if (d.subtitle) $('bd-sub').textContent = d.subtitle;

  const rows = Array.isArray(d.rows) ? d.rows : [];

  /* The season strip carries the season even when the standings have not
     changed, because a new season starts with the same empty ladder. */
  $('bd-meta-season').textContent = String(d.season || '—')
    .replace(/\s*STANDINGS\s*$/i, '') || '—';
  $('bd-meta-count').textContent = num(rows.length);

  const key = JSON.stringify(rows);
  if (key === lastKey) return;
  lastKey = key;

  /* The table is the whole ladder from first down, medals and all. The podium
     on the left is the same three names again, shown large. */
  drawPodium(rows);
  drawRows(rows.slice(0, Math.max(1, d.max || 10)),
           d.emptyText || 'NO RANKED PLAYERS YET');
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'board') render(d);
});

/* Nothing has been sent yet, so the board says so rather than sitting blank
   while the client works out whether anyone is near enough to see it. */
render({ rows: [] });
