/* ==========================================================================
   M5 Ranked PvP — NUI controller

   Rules kept throughout:
     · no full DOM rebuilds — each list owns its render function
     · no animation loops — one shared 1 Hz timer, everything else is CSS
     · all traffic is event driven, nothing polls the client
   ========================================================================== */

const RES = 'M5_RankedPvP';

/* ---------------------------------------------------------------- helpers */
const $  = (id) => document.getElementById(id);
const el = (tag, cls, html) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (html !== undefined) n.innerHTML = html;
  return n;
};
const esc = (s) => String(s === undefined || s === null ? '' : s)
  .replace(/[&<>"']/g, (c) => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
const pad = (n) => String(n).padStart(2, '0');
const clock = (s) => { s = Math.max(0, Math.floor(s || 0)); return `${Math.floor(s / 60)}:${pad(s % 60)}`; };
const num = (n) => (Number(n) || 0).toLocaleString('en-US');
const initial = (s) => (String(s || '?').trim().charAt(0) || '?').toUpperCase();

function post(name, data) {
  return fetch(`https://${RES}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {})
  }).catch(() => {});
}

/* --------------------------------------------------------------- defaults */
const DEFAULTS = {
  uiVolume: 55, musicVolume: 25, killSounds: true, hudSize: 100,
  killFeedPos: 'right', showPing: true, showMinimap: false,
  teamColorA: '#2ED9C3', teamColorB: '#FF4757', spectatorAuto: true,
  language: 'en', visualEffects: true, lowSpecMode: false
};

/* ------------------------------------------------------------------ state */
const S = {
  boot: null,
  theme: null,
  lang: 'en', rtl: false,
  settings: {},
  page: 'ranked',

  mode: '1v1',
  queue: { searching: false, elapsed: 0 },
  lastQueue: null,
  found: null, foundTimer: null,
  mapvote: null, mapvoteTimer: null,

  party: null,
  lb: { mode: '1v1', page: 1 },
  hist: { page: 1 },
  profile: null,
  admin: null, admTab: null, admTargetValue: '', admLookup: null,

  rooms: [], room: null,
  cm: {
    mode: '1v1', rounds: 7, matchType: 'normal',
    weapons: [], armor: false, hsOnly: false,
    map: null, mapPage: 1, step: 1
  },

  store: null, storeTab: 'cards',
  hud: null, hudTime: 0,
  matchInfo: null, sbOpen: false, dmgTimer: 0,
  brand: null,
  training: null
};

/* ------------------------------------------------------------------ audio */
const Sfx = (() => {
  let ctx = null;
  const vol = () => (S.settings.uiVolume !== undefined ? S.settings.uiVolume : 55) / 100;
  const T = {
    click:[{f:620,d:.05,t:'square',g:.05}],
    hover:[{f:380,d:.03,t:'sine',g:.02}],
    open:[{f:300,d:.09,t:'sawtooth',g:.05},{f:620,d:.12,t:'sine',g:.05,at:.06}],
    close:[{f:480,d:.08,t:'sine',g:.04},{f:240,d:.1,t:'sine',g:.04,at:.05}],
    queue:[{f:440,d:.1,t:'sine',g:.05},{f:660,d:.14,t:'sine',g:.05,at:.08}],
    found:[{f:520,d:.14,t:'square',g:.07},{f:780,d:.2,t:'square',g:.07,at:.12},{f:1040,d:.26,t:'sine',g:.06,at:.26}],
    accept:[{f:720,d:.1,t:'sine',g:.06},{f:980,d:.16,t:'sine',g:.05,at:.07}],
    tick:[{f:900,d:.04,t:'square',g:.05}],
    go:[{f:1200,d:.22,t:'sawtooth',g:.07}],
    roundwin:[{f:660,d:.12,t:'sine',g:.06},{f:990,d:.18,t:'sine',g:.05,at:.1}],
    roundloss:[{f:330,d:.16,t:'sine',g:.05},{f:220,d:.2,t:'sine',g:.05,at:.1}],
    kill:[{f:1100,d:.05,t:'square',g:.05}],
    headshot:[{f:1400,d:.05,t:'square',g:.06},{f:1800,d:.06,t:'square',g:.05,at:.04}],
    victory:[{f:523,d:.18,t:'sine',g:.07},{f:659,d:.18,t:'sine',g:.07,at:.16},{f:784,d:.34,t:'sine',g:.07,at:.32}],
    defeat:[{f:392,d:.24,t:'sine',g:.06},{f:311,d:.34,t:'sine',g:.06,at:.22}],
    rankup:[{f:523,d:.14,t:'square',g:.06},{f:698,d:.14,t:'square',g:.06,at:.13},{f:880,d:.3,t:'sine',g:.07,at:.26}],
    rankdown:[{f:440,d:.2,t:'sine',g:.05},{f:294,d:.3,t:'sine',g:.05,at:.18}],
    error:[{f:200,d:.16,t:'square',g:.05}],
    warning:[{f:660,d:.09,t:'square',g:.05},{f:660,d:.09,t:'square',g:.05,at:.14}]
  };
  return { play(key) {
    const spec = T[key]; if (!spec) return;
    const v = vol(); if (v <= 0) return;
    try {
      if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
      const now = ctx.currentTime;
      spec.forEach((s) => {
        const o = ctx.createOscillator(), g = ctx.createGain();
        o.type = s.t; o.frequency.setValueAtTime(s.f, now + (s.at || 0));
        g.gain.setValueAtTime(0, now + (s.at || 0));
        g.gain.linearRampToValueAtTime(s.g * v, now + (s.at || 0) + .012);
        g.gain.exponentialRampToValueAtTime(.0001, now + (s.at || 0) + s.d);
        o.connect(g).connect(ctx.destination);
        o.start(now + (s.at || 0)); o.stop(now + (s.at || 0) + s.d + .02);
      });
    } catch (e) { /* audio unavailable */ }
  } };
})();

/* --------------------------------------------------------------- rank art */
function crestSymbol(tier) {
  if (tier === 'IMMORTAL' || tier === 'RADIANT') return '#hex-star';
  if (!tier || tier === 'UNRANKED') return '#hex';
  return '#hex-chev';
}
function crest(tier, color) {
  return `<svg viewBox="0 0 100 100" style="color:${color || '#5A616D'}"><use href="${crestSymbol(tier)}"/></svg>`;
}
/** Tinted plate derived from the map id, used when there is no artwork. */
function mapGradient(id, forced) {
  let h = 0;
  const str = String(id);
  for (let i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) % 360;
  const hue = forced !== undefined ? forced : h;
  return `linear-gradient(155deg,hsl(${hue} 26% 20%),hsl(${(hue + 42) % 360} 32% 9%))`;
}
function mapArt(id, forced) {
  // background-image, not the shorthand: the caller may also set a size/position
  return `background-image:${mapGradient(id, forced)}`;
}
/** A bare name in the config means Files/ui/img/<name>.png; a path or URL is used as is. */
function imgUrl(src) {
  if (!src) return '';
  const s = String(src);
  return /[:/]/.test(s) ? s : `img/${s}.png`;
}
function tierOf(rankId) {
  const r = ((S.boot && S.boot.ranks) || []).find((x) => x.id === rankId);
  return r ? r.tier : 'UNRANKED';
}
function tierColor(rankId) {
  const r = ((S.boot && S.boot.ranks) || []).find((x) => x.id === rankId);
  return r ? r.color : '#5A616D';
}

/* -------------------------------------------------------------------- i18n */
/* ---------------------------------------------------------------- strings */
/* Every line of text comes from Locale.lua and is pushed in with the open
   payload, so this file keeps no dictionary of its own. STRINGS is that table
   for the active language; the English line is the key, and anything without
   a translation falls through unchanged. */
let LOCALE = { strings: {}, rtl: {} };          // every table, from Locale.lua
let STRINGS = {};                                // the active one
let NOTIFY_LANG = 'en';                          // Locale.notifications, or the active one
let LANGUAGES = [{ id: 'en', label: 'English' }];

function tx(str) {
  if (typeof str !== 'string') return str;
  return STRINGS[str] || str;
}

/** Text for a notification. Locale.notifications can pin these to one
 *  language while the rest of the interface follows the player's choice. */
function tn(str) {
  if (typeof str !== 'string') return str;
  const table = LOCALE.strings[NOTIFY_LANG] || STRINGS;
  return table[str] || str;
}

/** Stores what Locale.lua sent. Called on every open and on a language change. */
function applyLocale(payload) {
  if (!payload) return;
  LOCALE = { strings: payload.strings || {}, rtl: payload.rtl || {} };
  NOTIFY_LANG = payload.notifyLanguage || payload.language || 'en';
  if (Array.isArray(payload.languages) && payload.languages.length) {
    LANGUAGES = payload.languages;
  }
  applyLanguage(payload.language || 'en');
}

/** Re-labels the static markup, flips direction, and redraws dynamic text. */
function applyLanguage(lang) {
  const next = lang || 'en';
  const changed = next !== S.lang;
  S.lang = next;

  // pick the table for this language out of the bundle Locale.lua sent
  STRINGS = LOCALE.strings[next] || {};
  // Locale.rtl says which languages read right to left; 'ar' covers the case
  // where this runs before the bundle has arrived
  S.rtl = (LOCALE.rtl[next] !== undefined) ? LOCALE.rtl[next] === true : (next === 'ar');

  document.documentElement.setAttribute('lang', S.lang);
  document.documentElement.setAttribute('dir', S.rtl ? 'rtl' : 'ltr');

  document.querySelectorAll('[data-i18n]').forEach((n) => {
    n.textContent = tx(n.dataset.i18n);
  });

  /* Everything built by a renderer resolved its labels through tx() when it was
     drawn, so the static pass above cannot reach it — the party slots, the mode
     tabs and the open page keep the previous language until they are rebuilt. */
  if (changed) redrawForLanguage();

  // pages carry translated titles too
  renderHeadTitle();
}

/** The server name, then the line under it. Config.Brand.subtitle pins that
 *  line (the reference keeps it on MATCHMAKING); empty means follow the page. */
function renderBrand(brand) {
  if (brand) S.brand = brand;
  const b = S.brand || {};
  const name = $('hd-name');
  if (!name) return;

  if (b.enabled === false) {
    name.classList.add('hidden');
  } else {
    name.classList.remove('hidden');
    $('hd-name-a').textContent = b.name || '';
    $('hd-name-b').textContent = b.accent || '';
    $('hd-name-b').classList.toggle('hidden', !b.accent);
  }
  renderHeadTitle();
}

function renderHeadTitle() {
  const node = $('hd-title');
  if (!node) return;
  const pinned = S.brand && S.brand.subtitle;
  node.textContent = tx(pinned || PAGE_TITLES[S.page] || 'MATCHMAKING');
}

/** Rebuilds every rendered surface so a language switch reaches all of it. */
let langRedrawTimer = 0;
function redrawForLanguage() {
  clearTimeout(langRedrawTimer);
  /* Deferred by a tick on purpose: the switch usually arrives from the language
     <select>'s own change handler, and rebuilding the settings page would tear
     that element out from under the event still running on it. Debouncing also
     collapses the input+change pair a select fires into a single redraw. */
  langRedrawTimer = setTimeout(() => {
    if (!S.boot) return;
    try {
      renderModeTabs();
      renderSlots();
      renderQueue(S.lastQueue);
      showPage(S.page || 'ranked');
      // in-match surfaces too, or a switch mid match leaves them behind
      if (S.hud) renderHud(S.hud);
      if (S.matchInfo && S.matchInfo.scoreboardHint) {
        $('sb-hint').textContent = `${tx('HOLD')} ${S.matchInfo.scoreboardHint}`;
      }
    } catch (e) {
      // a failed relabel must never take the menu down with it
      console.error('language redraw failed', e);
    }
  }, 0);
}

/* --------------------------------------------------------- prompt / confirm */
/* CEF's window.prompt and window.confirm block the render loop and freeze the
   whole NUI, so both are replaced by this dialog. */
let promptResolve = null;

function closePrompt() {
  $('modal-prompt').classList.add('hidden');
  promptResolve = null;
}

function askInput(title, placeholder, onOk) {
  const modal = $('modal-prompt');
  $('prompt-title').textContent = tx(title);
  $('prompt-text').classList.add('hidden');
  $('prompt-wrap').classList.remove('hidden');
  const input = $('prompt-input');
  input.value = '';
  input.placeholder = tx(placeholder || '');
  modal.classList.remove('hidden');
  promptResolve = (ok) => { if (ok) onOk(input.value.trim()); };
  setTimeout(() => input.focus(), 40);
}

function askConfirm(title, text, onOk) {
  const modal = $('modal-prompt');
  $('prompt-title').textContent = tx(title);
  $('prompt-text').textContent = tx(text || '');
  $('prompt-text').classList.remove('hidden');
  $('prompt-wrap').classList.add('hidden');
  modal.classList.remove('hidden');
  promptResolve = (ok) => { if (ok) onOk(); };
}

/* ---------------------------------------------------------- custom select */
/* Native <select> popups cannot be styled inside CEF, so each one is kept in
   the DOM (so .value still works everywhere) and driven by a styled control. */
function enhanceSelects(root) {
  (root || document).querySelectorAll('select:not([data-xsel])').forEach((sel) => {
    sel.dataset.xsel = '1';

    const wrap = el('div', 'xsel');
    sel.parentNode.insertBefore(wrap, sel);
    wrap.appendChild(sel);
    sel.style.display = 'none';

    const btn  = el('button', 'xsel-btn');
    const list = el('div', 'xsel-list hidden');
    wrap.appendChild(btn);
    wrap.appendChild(list);

    const paint = () => {
      const opt = sel.options[sel.selectedIndex];
      btn.innerHTML = `<span>${esc(opt ? opt.text : '—')}</span><svg><use href="#i-caret"/></svg>`;
    };

    const build = () => {
      list.innerHTML = '';
      Array.from(sel.options).forEach((opt, i) => {
        const row = el('div', 'xsel-opt' + (i === sel.selectedIndex ? ' on' : ''),
          `<svg><use href="#i-check"/></svg><span>${esc(opt.text)}</span>`);
        row.onclick = (ev) => {
          ev.stopPropagation();
          sel.selectedIndex = i;
          sel.dispatchEvent(new Event('change', { bubbles: true }));
          paint();
          close();
        };
        list.appendChild(row);
      });
    };

    const close = () => { wrap.classList.remove('open'); list.classList.add('hidden'); };
    const open = () => {
      document.querySelectorAll('.xsel.open').forEach((o) => {
        o.classList.remove('open');
        const l = o.querySelector('.xsel-list'); if (l) l.classList.add('hidden');
      });
      build();
      wrap.classList.add('open');
      list.classList.remove('hidden');
      // flip upwards when there is no room below
      const box = btn.getBoundingClientRect();
      list.classList.toggle('up', (window.innerHeight - box.bottom) < 260);
    };

    btn.onclick = (ev) => {
      ev.stopPropagation();
      Sfx.play('click');
      if (wrap.classList.contains('open')) close(); else open();
    };

    paint();
  });
}
document.addEventListener('click', () => {
  document.querySelectorAll('.xsel.open').forEach((o) => {
    o.classList.remove('open');
    const l = o.querySelector('.xsel-list'); if (l) l.classList.add('hidden');
  });
});

/* ---------------------------------------------------------------- routing */
/* Used for the line under the server name when Config.Brand.subtitle is empty.
   Several pages used to share MATCHMAKING and `store` was missing entirely,
   so the line said the wrong thing on half the hub. */
const PAGE_TITLES = {
  ranked: 'MATCHMAKING', leaderboard: 'LEADERBOARD', custom: 'CUSTOM MATCH',
  profile: 'PROFILE', history: 'MATCH HISTORY', rewards: 'REWARDS',
  training: 'TRAINING', store: 'STORE', settings: 'SETTINGS',
  admin: 'ADMIN CONTROL'
};

function showPage(page) {
  S.page = page;
  document.querySelectorAll('.pg').forEach((p) => p.classList.remove('active'));
  const target = $('pg-' + page);
  if (target) target.classList.add('active');
  document.querySelectorAll('.ft .tab').forEach((b) => b.classList.toggle('active', b.dataset.page === page));
  $('btn-settings').classList.toggle('on', page === 'settings');

  renderHeadTitle();
  $('btn-start').classList.toggle('hidden', page !== 'ranked');
  $('mode-tabs').classList.toggle('hidden', page !== 'ranked');
  $('btn-back').classList.toggle('hidden', !(page === 'custom' && S.room));

  if (page === 'leaderboard') fetchBoard();
  if (page === 'history') post('fetch', { what: 'history', page: S.hist.page });
  if (page === 'profile') post('fetch', { what: 'profile' });
  if (page === 'rewards') post('fetch', { what: 'rewards' });
  if (page === 'custom') { post('custom', { action: 'list' }); renderCustom(); }
  if (page === 'store') post('fetch', { what: 'store' });
  if (page === 'training') renderTraining();
  if (page === 'settings') renderSettings();
  if (page === 'admin') post('admin', { action: 'dashboard' });
}

/* ============================================================ BOOT RENDER */
function renderBoot(data) {
  S.boot = data;
  const p = data.player;

  $('id-name').textContent = p.name || '—';
  $('id-initial').textContent = initial(p.name);
  $('id-levelbadge').textContent = p.level || 1;
  $('id-rankname').textContent = p.rank || 'Unranked';
  $('id-crest').innerHTML = crest(p.tier, p.rankColor);
  $('id-xp-bar').style.width = Math.min(100, ((p.xp || 0) / Math.max(1, p.xpNeeded || 1)) * 100) + '%';
  $('id-xp-text').textContent = `${num(p.xp)} / ${num(p.xpNeeded)} XP`;
  $('id-lvl-text').textContent = `LVL ${p.level || 1} / ∞`;

  document.querySelector('.admin-only')
    .classList.toggle('hidden', !(data.permissions && data.permissions.moderator));
  if (data.adminActions) S.admin = Object.assign({ allowed: data.adminActions }, S.admin || {});

  if (data.modes && data.modes.length && !data.modes.find((m) => m.id === S.mode)) {
    S.mode = data.modes[0].id;
    S.lb.mode = data.modes[0].id;
  }

  const d = data.customDefaults || {};
  if (!S.cm.weapons.length) S.cm.weapons = (d.weapons || []).slice();
  if (!S.cm.map && data.maps && data.maps.length) S.cm.map = data.maps[0].id;

  applyLanguage(S.settings.language || S.lang);
  renderModeTabs();
  renderSlots();
  renderCustom();
}

/* ============================================================ RANKED PAGE */
/** Party size drives which modes may be searched. */
function partySize() {
  return (S.party && S.party.members && S.party.members.length) || 1;
}
function modeAllowed(m) {
  const pq = (S.boot && S.boot.partyQueue) || {};
  const size = partySize();
  if (m.type === 'ffa') return true;
  if (size > m.teamSize) return false;                       // party too large
  if (pq.lockToPartySize && size !== m.teamSize) return false;
  return true;
}

function renderModeTabs() {
  const modes = (S.boot && S.boot.modes) || [];
  const pq = (S.boot && S.boot.partyQueue) || {};

  // ---- ranked tabs: locked modes are shown but not selectable
  const host = $('mode-tabs');
  host.innerHTML = '';
  modes.forEach((m) => {
    const ok = modeAllowed(m);
    const b = el('button', 'mtab' + (m.id === S.mode ? ' active' : '') + (ok ? '' : ' locked'),
      esc(m.label));
    b.title = ok ? '' : `Your party of ${partySize()} cannot search ${m.label}`;
    b.onclick = () => {
      if (!ok) { toast('warning', `A party of ${partySize()} cannot search ${m.label}.`, 'QUEUE'); return; }
      Sfx.play('click');
      S.mode = m.id;
      renderModeTabs();
      renderSlots();
    };
    host.appendChild(b);
  });

  // ---- leaderboard tabs stay a plain mode filter
  const lb = $('lb-tabs');
  lb.innerHTML = '';
  modes.forEach((m) => {
    const b = el('button', 'mtab' + (m.id === S.lb.mode ? ' active' : ''), esc(m.label));
    b.onclick = () => { Sfx.play('click'); S.lb.mode = m.id; S.lb.page = 1; renderModeTabs(); fetchBoard(); };
    lb.appendChild(b);
  });
}

/** Keeps the selected mode in step with the party size. */
function syncModeToParty() {
  const pq = (S.boot && S.boot.partyQueue) || {};
  if (!pq.autoMode) return;

  const suggested = (S.party && S.party.autoMode) || null;
  const size = partySize();

  if (suggested) {
    if (S.mode !== suggested) {
      S.mode = suggested;
      const cfg = ((S.boot && S.boot.modes) || []).find((m) => m.id === suggested);
      if (cfg && size > 1) toast('info', `Party of ${size} — switched to ${cfg.label}.`, 'QUEUE');
    }
  } else {
    // no exact mode for this size: fall back to the first one that fits
    const fit = ((S.boot && S.boot.modes) || []).find(modeAllowed);
    if (fit && !modeAllowed(((S.boot && S.boot.modes) || []).find((m) => m.id === S.mode) || {})) {
      S.mode = fit.id;
    }
  }
}

/** Label of the ranked mode a party of `size` players would play. */
function modeLabelForSize(size) {
  const m = ((S.boot && S.boot.modes) || []).find((x) => x.teamSize === size);
  return m ? m.label : null;
}

/** The party slots. Slot 1 is always you, the rest fill from the party. */
function renderSlots() {
  const host = $('party-slots');
  const p = S.boot && S.boot.player;
  const max = (S.boot && S.boot.maxParty) || 5;

  const members = (S.party && S.party.members && S.party.members.length)
    ? S.party.members
    : (p ? [{ userId: p.userId, name: p.name, rank: p.rank, rankId: p.rankId, rp: p.rp, leader: true, ready: true }] : []);

  const meId = p && p.userId;
  const iAmLeader = !S.party || S.party.leader === meId;
  const modeCfg = ((S.boot && S.boot.modes) || []).find((m) => m.id === S.mode);

  /* The seat right after the party is always invitable, whatever mode is
     selected: inviting is how the party grows, and the mode follows the new
     size (1v1 -> 2v2 -> 3v3 ...). Gating it on the current mode's team size
     locked every seat while in 1v1 and left no way to invite anyone. */
  const nextSeat = members.length;

  host.innerHTML = '';
  for (let i = 0; i < max; i++) {
    const m = members[i];

    if (!m) {
      const isNext    = i === nextSeat;
      const invitable = isNext && iAmLeader;

      /* the mode this seat belongs to, when one exists for that team size */
      const seatMode  = modeLabelForSize(i + 1);

      let cls, icon, head, sub;
      if (invitable) {
        cls  = 'open';
        icon = 'i-userplus';
        head = 'INVITE PLAYER';
        sub  = 'CLICK TO INVITE';
      } else if (isNext) {
        cls  = 'open noperm';
        icon = 'i-userplus';
        head = 'INVITE PLAYER';
        sub  = 'LEADER ONLY';
      } else {
        // reachable, just not yet — a padlock would read as permanently shut
        cls  = 'locked';
        icon = 'i-user';
        head = 'OPEN SLOT';
        sub  = 'INVITE IN ORDER';
      }

      const slot = el('div', 'slot ' + cls, `
        <div class="slot-top">
          <div class="slot-av ghost"><svg><use href="#${icon}"/></svg></div>
          <div class="slot-name">${esc(tx(head))}</div>
          <div class="slot-ready">${esc(tx(sub))}</div>
        </div>
        <div class="slot-foot">
          <div class="slot-crest"><span class="ghost-crest"></span></div>
          <div class="slot-track ghost"></div>
          <div class="slot-nums">
            <span>&ndash;</span>
            <span class="slot-rank">${seatMode ? esc(seatMode) : '&ndash;'}</span>
            <span>&ndash;</span>
          </div>
        </div>`);

      if (invitable) {
        slot.tabIndex = 0;
        slot.setAttribute('role', 'button');
        slot.onclick = () => { Sfx.play('click'); openInvite(); };
        slot.onkeydown = (ev) => {
          if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); slot.click(); }
        };
      }

      host.appendChild(slot);
      continue;
    }

    const isMe = m.userId === meId;
    const tier = isMe && p ? p.tier : tierOf(m.rankId);
    const color = isMe && p ? p.rankColor : tierColor(m.rankId);
    const prog = (isMe && p && p.progress) ? p.progress : null;
    const pct = prog ? prog.percent : 0;
    const lo = m.rp || 0;
    const hi = prog && prog.needed ? (lo + prog.needed) : (lo + 50);

    const slot = el('div', 'slot filled' + (m.leader ? ' leader' : ''), `
      <div class="slot-top">
        <div class="slot-av">${esc(initial(m.name))}${m.leader ? '<span class="slot-flag">★</span>' : ''}</div>
        <div class="slot-name">${esc(m.name)}${m.userId ? ` [${m.userId}]` : ''}</div>
        <div class="slot-ready ${m.ready ? 'on' : ''}">${esc(tx(m.ready ? 'READY' : 'NOT READY'))}</div>
      </div>
      <div class="slot-foot">
        <div class="slot-crest">${crest(tier, color)}</div>
        <div class="slot-track"><i style="width:${pct}%"></i></div>
        <div class="slot-nums">
          <span>${num(lo)}</span>
          <span class="slot-rank">${esc(tx(m.rank || 'Unranked'))} (${esc((modeCfg && modeCfg.label) || S.mode)})</span>
          <span>${num(hi)}</span>
        </div>
      </div>`);

    if (!isMe && iAmLeader) {
      const kick = el('button', 'slot-kick', '<svg><use href="#i-x"/></svg>');
      kick.onclick = (ev) => { ev.stopPropagation(); post('party', { action: 'kick', target: m.userId }); };
      slot.appendChild(kick);
    }
    host.appendChild(slot);
  }
}

function openInvite() {
  $('modal-invite').classList.remove('hidden');
  const input = $('invite-id');
  input.value = '';
  input.parentNode.classList.remove('bad');
  setTimeout(() => input.focus(), 40);
}

function sendInvite() {
  const input = $('invite-id');
  const v = input.value.trim();

  if (!v) {                                   // say why instead of closing silently
    const wrap = input.parentNode;
    wrap.classList.remove('bad');
    void wrap.offsetWidth;                    // restart the shake
    wrap.classList.add('bad');
    toast('warning', tn('Enter a player ID first.'), tn('INVITE PLAYER'), 3200);
    input.focus();
    return;
  }

  post('party', { action: 'invite', target: v });
  $('modal-invite').classList.add('hidden');
}

function toggleQueue() {
  if (S.queue.searching) { post('queue', { action: 'leave' }); return; }
  Sfx.play('queue');
  post('queue', { action: 'join', mode: S.mode });
}

/** Label of the mode the START button would queue for. */
function currentModeLabel() {
  const m = ((S.boot && S.boot.modes) || []).find((x) => x.id === S.mode);
  return (m && m.label) || String(S.mode || '').toUpperCase();
}

function renderQueue(q) {
  if (q) S.lastQueue = q;          // kept so a language redraw can replay it
  const searching = !!(q && q.state === 'SEARCHING');
  S.queue.searching = searching;

  const start = $('btn-start');
  start.classList.toggle('searching', searching);
  // the label and the mode underneath it, rather than replacing the whole
  // button — the mode line is what tells you what you are queuing for
  start.innerHTML = `
    <svg><use href="#${searching ? 'i-x' : 'i-play'}"/></svg>
    <span class="fb-text">
      <b>${esc(tx(searching ? 'CANCEL' : 'FIND MATCH'))}</b>
      <em id="btn-start-mode">${esc(currentModeLabel())}</em>
    </span>`;

  $('searchdock').classList.toggle('hidden', !searching);
  if (!searching) { S.queue.elapsed = 0; return; }

  if (q.elapsed !== undefined) S.queue.elapsed = q.elapsed;
  const modeCfg = ((S.boot && S.boot.modes) || []).find((m) => m.id === (q.mode || S.mode));
  const label = (modeCfg && modeCfg.label) || String(q.mode || S.mode).toUpperCase();
  const pq = (S.boot && S.boot.partyQueue) || {};
  const full = pq.fullTeamOnly && partySize() > 1;
  $('sd-mode').textContent = full ? `${label} · VS TEAM` : label;
  $('sd-time').textContent = clock(S.queue.elapsed);
}

/* ============================================================ MATCH FOUND */
function renderFound(d) {
  const modal = $('modal-found');
  if (!d || d.cancel || d.done) {
    modal.classList.add('hidden');
    if (S.foundTimer) { clearInterval(S.foundTimer); S.foundTimer = null; }
    S.found = null;
    return;
  }

  const first = !S.found;
  S.found = d;
  modal.classList.remove('hidden');

  $('found-mode').textContent = String(d.modeLabel || d.mode || 'RANKED').toUpperCase();
  $('found-accepted').textContent = d.accepted || 0;
  $('found-total').textContent = d.total || 0;

  const mine = d.accepted_self === true;
  // once the lobby is full the wait line says nothing the counter does not
  $('found-waiting').classList.toggle('hidden', !mine || (d.accepted || 0) >= (d.total || 0));
  document.querySelector('.found-actions').classList.toggle('hidden', mine);

  /* The number under the title means different things depending on where the
     queue is: how long you have left to accept, or how long until the vote. */
  $('found-sub').textContent = mine ? tx('VOTING IN…') : tx('ACCEPT TO CONTINUE');

  if (first) {
    Sfx.play('found');
    let left = d.timeout || 15;
    const total = left;
    const box  = $('found-box') || document.querySelector('.found-box');
    const ring = $('found-ring');
    // a rounded rect, so measure it rather than working the perimeter out
    const len = ring.getTotalLength ? ring.getTotalLength() : 388;
    ring.style.strokeDasharray = len;
    const tick = () => {
      $('found-timer').textContent = Math.max(0, left);
      ring.style.strokeDashoffset = len * (1 - Math.max(0, left) / total);
      if (box) box.classList.toggle('urgent', left <= 5);
      if (left <= 5 && left > 0) Sfx.play('tick');
      left -= 1;
      if (left < 0) { clearInterval(S.foundTimer); S.foundTimer = null; }
    };
    tick();
    S.foundTimer = setInterval(tick, 1000);
  }
}

/* =============================================================== MAP VOTE */
function renderMapVote(d) {
  const modal = $('modal-mapvote');
  if (!d) return;

  if (d.close || d.result) {
    modal.classList.add('hidden');
    if (S.mapvoteTimer) { clearInterval(S.mapvoteTimer); S.mapvoteTimer = null; }
    if (d.result) {
      const nm = (S.mapvote && S.mapvote.names && S.mapvote.names[d.result]) || d.result;
      toast('info', `Map selected: ${nm}`, 'MAP VOTE');
    }
    S.mapvote = null;
    return;
  }

  if (d.options) {
    S.mapvote = { names: {} };
    modal.classList.remove('hidden');
    const grid = $('mv-grid');
    grid.innerHTML = '';
    d.options.forEach((m, i) => {
      S.mapvote.names[m.id] = m.name;
      /* The screenshot is layered over the tinted plate rather than replacing
         it, so a missing or misnamed file degrades to the plate instead of a
         blank card. */
      const plate = mapGradient(m.id, (i * 47 + 200) % 360);
      const url = imgUrl(m.image);
      const art = url ? `background-image:url("${esc(url)}"),${plate}`
                      : `background-image:${plate}`;
      const card = el('div', 'mv-card', `
        <div class="mv-art" style="${art}"></div>
        <div class="mv-foot-card">
          <span class="mv-name">${esc(m.name)}</span>
          <span class="mv-votes" data-map="${esc(m.id)}"><b>0</b></span>
        </div>`);
      card.onclick = () => {
        document.querySelectorAll('.mv-card').forEach((c) => c.classList.remove('picked'));
        card.classList.add('picked');
        Sfx.play('click');
        post('mapVote', { mapId: m.id });
        $('mv-foot').textContent = `${tx('YOU VOTED FOR')} ${String(m.name).toUpperCase()}`;
      };
      grid.appendChild(card);
    });

    const total = d.duration || 20;
    let left = total;
    const fill = $('mv-rail-fill');
    const paint = () => {
      $('mv-timer').textContent = `${Math.max(0, left)}${tx('S')}`;
      $('mv-timer').classList.toggle('urgent', left <= 5);
      if (fill) fill.style.width = (Math.max(0, left) / total) * 100 + '%';
    };
    paint();
    if (S.mapvoteTimer) clearInterval(S.mapvoteTimer);
    S.mapvoteTimer = setInterval(() => {
      left -= 1; paint();
      if (left <= 0) { clearInterval(S.mapvoteTimer); S.mapvoteTimer = null; }
    }, 1000);
  }

  if (d.votes) {
    Object.keys(d.votes).forEach((id) => {
      const n = document.querySelector(`.mv-votes[data-map="${id}"] b`);
      if (n) n.textContent = d.votes[id];
    });
  }
}

/* ================================================================== PARTY */
function renderParty(d) {
  if (!d) return;

  if (d.invite) {
    const card = toast('info', `${d.invite.from} invited you to a party`, 'PARTY INVITE', 12000);
    const row = el('div');
    row.style.cssText = 'display:flex;gap:6px;margin-top:8px';
    const a = el('button', 'btn', 'ACCEPT'); a.style.cssText = 'padding:6px 14px;font-size:10px';
    const r = el('button', 'btn ghost', 'DECLINE'); r.style.cssText = 'padding:6px 14px;font-size:10px';
    a.onclick = () => { post('party', { action: 'accept' }); card.remove(); };
    r.onclick = () => { post('party', { action: 'decline' }); card.remove(); };
    row.appendChild(a); row.appendChild(r);
    card.appendChild(row);
    return;
  }

  S.party = d.id ? d : null;
  syncModeToParty();
  renderModeTabs();
  renderSlots();
  renderCustomParty();
}

/* ========================================================== CUSTOM MATCH */
function renderCustom() {
  if (!S.boot) return;
  renderCustomTypes();
  renderCustomWeapons();
  renderCustomMaps();
  renderCustomParty();
  renderCustomRoom();
  $('cm-mode').textContent = S.cm.mode;
  $('cm-rounds').textContent = S.cm.rounds;
  $('cm-armor').checked = S.cm.armor;
  $('cm-hsonly').checked = S.cm.hsOnly;
  updateSteps();
}

function updateSteps() {
  const step = S.room ? 4 : (S.cm.map ? 2 : 1);
  S.cm.step = step;
  document.querySelectorAll('#cm-steps .stp').forEach((n, i) => {
    n.classList.toggle('on', i + 1 === step);
    n.classList.toggle('done', i + 1 < step);
  });
}

function renderCustomTypes() {
  const host = $('cm-types');
  host.innerHTML = '';
  ((S.boot && S.boot.matchTypes) || []).forEach((t) => {
    const icon = t.id === 'gungame' ? '#i-party' : (t.id === 'random' ? '#i-target' : '#i-ranked');
    const b = el('button', 'pill' + (t.id === S.cm.matchType ? ' on' : ''),
      `<svg><use href="${icon}"/></svg>${esc(t.label)}`);
    b.title = t.description || '';
    b.onclick = () => { S.cm.matchType = t.id; Sfx.play('click'); renderCustomTypes(); };
    host.appendChild(b);
  });
}

function renderCustomWeapons() {
  const host = $('cm-weapons');
  const list = (S.boot && S.boot.weaponPresets) || [];
  host.innerHTML = '';
  list.forEach((w) => {
    const on = S.cm.weapons.includes(w.id);
    const b = el('button', 'chip' + (on ? ' on' : ''), esc(w.label));
    b.onclick = () => {
      const i = S.cm.weapons.indexOf(w.id);
      if (i >= 0) { if (S.cm.weapons.length > 1) S.cm.weapons.splice(i, 1); }
      else S.cm.weapons.push(w.id);
      Sfx.play('click');
      renderCustomWeapons();
    };
    host.appendChild(b);
  });
  $('cm-wcount').textContent = `${S.cm.weapons.length} / ${list.length}`;
}

function renderCustomMaps() {
  const host = $('cm-maps');
  const all = ((S.boot && S.boot.maps) || []).filter((m) => !m.modes || m.modes.includes(S.cm.mode));
  const perPage = 9;
  const pages = Math.max(1, Math.ceil(all.length / perPage));
  if (S.cm.mapPage > pages) S.cm.mapPage = 1;
  const slice = all.slice((S.cm.mapPage - 1) * perPage, S.cm.mapPage * perPage);

  host.innerHTML = '';
  if (!slice.length) host.appendChild(el('div', 'empty', 'NO MAP SUPPORTS THIS MODE'));
  slice.forEach((m) => {
    const card = el('div', 'mapcard' + (m.id === S.cm.map ? ' on' : ''),
      `<div class="art" style="${mapArt(m.id)}"></div><div class="cap">${esc(m.name)}</div>`);
    card.onclick = () => { S.cm.map = m.id; Sfx.play('click'); renderCustomMaps(); updateSteps(); };
    host.appendChild(card);
  });

  const pager = $('cm-pager');
  pager.innerHTML = '';
  for (let i = 1; i <= pages; i++) {
    const b = el('button', 'pgn' + (i === S.cm.mapPage ? ' on' : ''), i);
    b.onclick = () => { S.cm.mapPage = i; renderCustomMaps(); };
    pager.appendChild(b);
  }
}

function renderCustomParty() {
  const host = $('cm-party');
  if (!host) return;
  const max = (S.boot && S.boot.maxParty) || 5;
  const p = S.boot && S.boot.player;

  let members = [];
  if (S.room && S.room.roster) members = S.room.roster;
  else if (S.party && S.party.members) members = S.party.members;
  else if (p) members = [{ userId: p.userId, name: p.name, leader: true }];

  host.innerHTML = '';
  members.slice(0, max).forEach((m) => {
    host.appendChild(el('div', 'cm-slot',
      `<span class="av">${esc(initial(m.name))}</span><b>${esc(m.name)}</b>
       ${(m.host || m.leader) ? '<span class="tag">HOST</span>' : ''}`));
  });
  for (let i = members.length; i < max; i++) host.appendChild(el('div', 'cm-slot free', 'EMPTY'));

  $('cm-partycount').textContent = `${Math.min(members.length, max)}/${max}`;
  $('cm-code').textContent = (S.room && S.room.code) ? S.room.code.split('').join(' ') : '- - - -';
  $('cm-leave').classList.toggle('hidden', !S.room);
}

function renderCustomRoom() {
  const view = $('cm-roomview');
  if (!S.room) { view.classList.add('hidden'); view.innerHTML = ''; return; }

  const me = S.boot && S.boot.player.userId;
  const isHost = S.room.hostId === me;
  const roster = S.room.roster || [];
  const team = (t) => roster.filter((r) => r.team === t && !r.spectator);

  const slot = (r) => `
    <div class="cm-slot">
      <span class="av">${esc(initial(r.name))}</span><b>${esc(r.name)}</b>
      ${r.host ? '<span class="tag">HOST</span>' : ''}
      ${isHost && !r.host ? `<button class="mini" data-room="move" data-user="${r.userId}" data-team="${r.team === 1 ? 2 : 1}">SWAP</button>
        <button class="mini" data-room="kick" data-user="${r.userId}">KICK</button>` : ''}
    </div>`;

  view.classList.remove('hidden');
  view.innerHTML = `
    <div class="cm-panel-head"><svg><use href="#i-party"/></svg>${esc(S.room.name)} <em class="dot"></em>
      <span style="margin-left:auto;color:var(--dim);letter-spacing:.1em">${esc(S.room.state)}</span></div>
    <div style="padding:14px;display:grid;grid-template-columns:1fr 1fr;gap:12px">
      <div><div class="fld"><label style="color:var(--team-a)">TEAM A</label></div>
        ${team(1).map(slot).join('') || '<div class="empty">EMPTY</div>'}</div>
      <div><div class="fld"><label style="color:var(--team-b)">TEAM B</label></div>
        ${team(2).map(slot).join('') || '<div class="empty">EMPTY</div>'}</div>
    </div>
    ${isHost ? `<div style="padding:0 14px 14px;display:flex;gap:8px;flex-wrap:wrap">
      <button class="btn" data-room="start"><svg><use href="#i-play"/></svg> START MATCH</button>
      <button class="btn ghost" data-room="apply">APPLY SETTINGS</button>
      <button class="btn ghost" data-room="lock">${S.room.locked ? 'UNLOCK' : 'LOCK'}</button>
    </div>` : ''}`;
}

function customPayload() {
  return {
    mode: S.cm.mode, map: S.cm.map, rounds: S.cm.rounds,
    matchType: S.cm.matchType, weapons: S.cm.weapons,
    armorEnabled: S.cm.armor, headshotOnly: S.cm.hsOnly
  };
}

/* =========================================================== LEADERBOARD */
function fetchBoard() {
  post('fetch', { what: 'leaderboard', board: 'mode', mode: S.lb.mode, page: S.lb.page });
}

function crestInline(tier, color) {
  return `<svg viewBox="0 0 100 100" style="color:${color || '#5A616D'}"><use href="${crestSymbol(tier)}"/></svg>`;
}

function renderBoard(d) {
  $('lb-page').textContent = `${tx('PAGE')} ${d.page || 1}`;
  const rows = d.rows || [];
  const me = S.boot && S.boot.player.userId;
  const modeCfg = ((S.boot && S.boot.modes) || []).find((m) => m.id === S.lb.mode);
  const p = S.boot && S.boot.player;

  $('lb-me').innerHTML = p ? `
    <div class="av">${esc(initial(p.name))}</div>
    <div class="who">
      <b>${esc(p.name)} [${p.userId}]</b>
      <span>${crestInline(p.tier, p.rankColor)} ${esc(p.rank)} · ${esc((modeCfg && modeCfg.label) || S.lb.mode)}</span>
    </div>` : '';

  const st = d.stats;
  const cells = st ? [
    ['WIN GAME', num(st.wins)], ['TOTAL GAME', num(st.matches)],
    ['KILL SCORE', num(st.kills)], ['DEATH SCORE', num(st.deaths)],
    ['K/D RATIO', st.kd], ['POINTS', num(st.points)]
  ] : [];
  $('lb-stats').innerHTML = cells.map(([l, v]) =>
    `<div class="lb-stat"><label>${esc(tx(l))}</label><b>${esc(v)}</b></div>`).join('');

  const body = $('lb-body');
  body.innerHTML = '';
  if (!rows.length) { body.appendChild(el('div', 'empty', 'NO RANKED MATCHES IN THIS MODE YET')); return; }

  rows.forEach((r) => {
    const row = el('div', 'brow' + (r.position === 1 ? ' top1' : '') + (r.userId === me ? ' you' : ''), `
      <span class="pos">${r.position}</span>
      <span class="who">
        <span class="tier" style="color:${r.rankColor}">${crestInline(r.tier, r.rankColor)}${esc(r.rank)}</span>
        <span class="av">${esc(initial(r.name))}</span>
        <b>${esc(r.name)}</b>
      </span>
      <span>${num(r.points !== undefined ? r.points : r.rp)}</span>
      <span>${num(r.wins)}</span>
      <span>${num(r.kills)}</span>
      <span>${num(r.deaths)}</span>
      <span>${r.kd}</span>`);
    row.onclick = () => { post('fetch', { what: 'profile', userId: r.userId }); showPage('profile'); };
    body.appendChild(row);
  });
}

/* =============================================================== PROFILE */
function renderProfile() {
  const p = S.profile;
  const host = $('profile-root');
  if (!p) { host.innerHTML = '<div class="empty">NO PROFILE DATA</div>'; return; }
  const s = p.stats;
  const stat = (l, v, c) => `<div class="stat ${c || ''}"><b>${esc(v)}</b><span>${l}</span></div>`;

  host.innerHTML = `
    <div class="pbanner">
      <div class="pav">${esc(initial(p.name))}</div>
      <div style="flex:1">
        <div class="pname">${esc(p.name)}</div>
        <div class="ptitle">${esc(p.activeTitle || '')}</div>
        <div class="pmeta">
          <span class="tagchip" style="color:${p.rankColor}">${esc(String(p.rank || '').toUpperCase())}</span>
          <span class="tagchip">${num(p.rp)} RP</span>
          <span class="tagchip">LEVEL ${p.level}</span>
          <span class="tagchip">GLOBAL #${p.position || '—'}</span>
          <span class="tagchip">PEAK ${esc(p.highestRank)}</span>
          ${p.mmr ? `<span class="tagchip">MMR ${p.mmr}</span>` : ''}
        </div>
      </div>
      <div class="pcrest">${crest(p.tier, p.rankColor)}</div>
    </div>

    <div class="card">
      <span class="card-tag">CAREER STATISTICS</span>
      <div class="grid">
        ${stat('MATCHES', num(s.matches))}${stat('WINS', num(s.wins), 'good')}${stat('LOSSES', num(s.losses), 'bad')}
        ${stat('WIN RATE', s.winRate + '%', s.winRate >= 50 ? 'good' : 'bad')}
        ${stat('KILLS', num(s.kills))}${stat('DEATHS', num(s.deaths))}${stat('ASSISTS', num(s.assists))}
        ${stat('K / D', s.kd, s.kd >= 1 ? 'good' : 'bad')}
        ${stat('HEADSHOTS', num(s.headshots))}${stat('HEADSHOT %', s.hsPercent + '%')}
        ${stat('DAMAGE', num(s.damage))}${stat('MVP', num(s.mvp))}
        ${stat('WIN STREAK', num(s.winStreak))}${stat('BEST STREAK', num(s.bestStreak))}
        ${stat('CLUTCHES', num(s.clutches))}${stat('ACES', num(s.aces))}
        ${stat('FIRST BLOODS', num(s.firstBloods))}${stat('PLAYTIME', Math.floor((s.playtime || 0) / 3600) + 'h')}
      </div>
    </div>

    <div class="card">
      <span class="card-tag">TITLES</span>
      <div class="chips">
        ${(p.titles || []).length ? p.titles.map((t) =>
          `<span class="chip ${t === p.activeTitle ? 'on' : ''}" data-title="${esc(t)}">${esc(t)}</span>`).join('')
          : '<span class="empty">NO TITLES YET</span>'}
      </div>
    </div>

    <div class="card">
      <span class="card-tag">ACHIEVEMENTS</span>
      ${(p.achievements || []).map((a) => `
        <div class="arow"><b>${a.unlocked ? '✓' : '·'}</b><b>${esc(a.label)}</b>
          <span class="grow">${esc(a.desc)}</span>
          <span>${a.unlocked ? 'UNLOCKED' : 'LOCKED'}</span></div>`).join('')}
    </div>`;

  host.querySelectorAll('[data-title]').forEach((n) => {
    n.onclick = () => post('action', { action: 'setTitle', title: n.dataset.title });
  });
}

/* =============================================================== HISTORY */
function renderHistory(rows, page) {
  $('hist-page').textContent = `${tx('PAGE')} ${page || 1}`;
  const host = $('history-list');
  host.innerHTML = '';
  if (!rows || !rows.length) { host.appendChild(el('div', 'empty', 'NO MATCHES PLAYED YET')); return; }

  rows.forEach((r) => {
    const cls = r.result === 'LOSS' ? 'loss' : (r.result === 'DRAW' ? 'draw' : '');
    const row = el('div', 'hrow ' + cls, `
      <i class="bar"></i>
      <div><div class="hres">${r.result === 'WIN' ? 'VICTORY' : (r.result === 'LOSS' ? 'DEFEAT' : 'DRAW')}</div>
           <div class="hsub">${esc(r.mode)} · ${esc(r.map)}</div></div>
      <div class="hscore">${r.score.mine} - ${r.score.other}</div>
      <div class="hstats">
        <span><b>${r.kills}</b> K</span><span><b>${r.deaths}</b> D</span>
        <span><b>${r.assists}</b> A</span><span><b>${r.headshots}</b> HS</span>
        <span><b>${num(r.damage)}</b> DMG</span>
      </div>
      <div class="hrp ${r.rpChange < 0 ? 'neg' : ''}">${r.rpChange > 0 ? '+' : ''}${r.rpChange} RP</div>
      ${r.mvp ? '<span class="hmvp">MVP</span>' : '<span></span>'}`);
    row.onclick = () => post('fetch', { what: 'matchDetail', matchId: r.matchId });
    host.appendChild(row);
  });
}

function renderMatchDetail(d) {
  const host = $('matchdetail');
  if (!d) { host.classList.add('hidden'); return; }
  host.classList.remove('hidden');
  const rows = (t) => (d.roster || []).filter((p) => p.team === t).map((p) => `
    <div class="arow"><b>${p.mvp ? '★' : ''}</b><b>${esc(p.name)}</b>
      <span class="grow">${p.kills}/${p.deaths}/${p.assists} · ${num(p.damage)} DMG</span>
      <span class="hrp ${p.rpChange < 0 ? 'neg' : ''}" style="font-size:13px">${p.rpChange > 0 ? '+' : ''}${p.rpChange}</span>
    </div>`).join('');
  host.innerHTML = `
    <div class="cm-panel-head"><svg><use href="#i-clock"/></svg>${esc(d.mode)} · ${esc(d.map)} · ${d.scores.a}-${d.scores.b}
      <button class="mini" style="margin-left:auto" data-action="detail-close">CLOSE</button></div>
    <div style="padding:14px">
      <div class="card-tag" style="color:var(--team-a)">TEAM A</div>${rows(1)}
      <div class="card-tag" style="color:var(--team-b);margin-top:12px">TEAM B</div>${rows(2)}
    </div>`;
}

/* =============================================================== REWARDS */
function renderRewards(d) {
  const host = $('rewards-root');
  const p = S.boot && S.boot.player;
  const missions = (kind) => {
    const list = (d.missions && d.missions[kind]) || [];
    if (!list.length) return '<div class="empty">NONE ACTIVE</div>';
    return list.map((m) => {
      const pct = Math.min(100, (m.progress / Math.max(1, m.target)) * 100);
      return `<div class="stat" style="margin-bottom:8px">
        <div style="display:flex;justify-content:space-between;font-size:12px">
          <span>${esc(m.label)}</span><span style="color:var(--dim)">${m.progress}/${m.target}</span></div>
        <div class="slot-track" style="margin-top:7px"><i style="width:${pct}%"></i></div>
        <div style="font-size:10px;color:var(--dim);margin-top:5px">+${m.xp} XP${m.money ? ` · $${num(m.money)}` : ''}</div>
      </div>`;
    }).join('');
  };

  host.innerHTML = `
    <div class="card">
      <span class="card-tag">LEVEL PROGRESSION</span>
      <div style="display:flex;align-items:center;gap:18px">
        <div class="stat" style="min-width:110px"><b>${p ? p.level : 1}</b><span>LEVEL</span></div>
        <div style="flex:1">
          <div class="slot-track"><i style="width:${p ? Math.min(100, (p.xp / Math.max(1, p.xpNeeded)) * 100) : 0}%"></i></div>
          <div style="font-size:11px;color:var(--dim);margin-top:6px">${p ? num(p.xp) : 0} / ${p ? num(p.xpNeeded) : 0} XP</div>
        </div>
      </div>
    </div>
    <div class="settings">
      <div class="card"><span class="card-tag">DAILY MISSIONS</span>${missions('daily')}</div>
      <div class="card"><span class="card-tag">WEEKLY MISSIONS</span>${missions('weekly')}</div>
    </div>
    <div class="card">
      <span class="card-tag">YOUR REWARDS</span>
      <div class="grid">
        ${(d.rows || []).length ? d.rows.map((r) => {
          let v = {}; try { v = JSON.parse(r.value); } catch (err) {}
          return `<div class="stat"><b style="font-size:14px">${esc(String(r.type || '').toUpperCase())}</b>
            <span>${esc(v && v.value !== undefined ? v.value : r.reward_key)}</span>
            <div style="margin-top:9px">${r.claimed ? '<span class="tagchip">CLAIMED</span>'
              : `<button class="mini" data-claim="${esc(r.reward_key)}">CLAIM</button>`}</div></div>`;
        }).join('') : '<div class="empty">NO REWARDS YET</div>'}
      </div>
    </div>`;

  host.querySelectorAll('[data-claim]').forEach((b) => {
    b.onclick = () => post('action', { action: 'claimReward', key: b.dataset.claim });
  });
}

/* ============================================================== TRAINING */
function renderTraining() {
  const host = $('traingrid');
  const active = S.training;
  const modes = [
    { kind: 'aim', label: tx('AIM TRAINING'), desc: 'Static targets at mixed ranges. Warm up tracking and flicks.' },
    { kind: 'headshot', label: tx('HEADSHOT TRAINING'), desc: 'Long range targets. One clean head hit is always lethal — practise it.' },
    { kind: 'range', label: tx('FREE RANGE'), desc: 'Open range with a full loadout. No targets, no timer.' }
  ];
  host.innerHTML = '';

  if (active) {
    const bar = el('div', 'train-active', `
      <div style="flex:1">
        <b>${esc(active.label || 'TRAINING')}</b>
        <div><span>Session in progress${active.exit
          ? ` — press ${esc(active.exit.key)} in game${active.exit.command ? ` or ${esc(active.exit.command)}` : ''}`
          : ''}</span></div>
      </div>`);
    const leave = el('button', 'btn', '<svg><use href="#i-x"/></svg> EXIT TRAINING');
    leave.onclick = () => { Sfx.play('click'); post('action', { action: 'training', enable: false }); };
    bar.appendChild(leave);
    bar.style.gridColumn = '1 / -1';
    host.appendChild(bar);
  }

  modes.forEach((m) => {
    const c = el('div', 'traincard',
      `<div><b>${m.label}</b><p>${m.desc}</p></div>
       <button class="btn">${esc(tx(active ? 'SWITCH' : 'ENTER'))}</button>`);
    c.onclick = () => post('action', { action: 'training', enable: true, kind: m.kind });
    host.appendChild(c);
  });
}

/* ============================================================== SETTINGS */
const SETTING_DEFS = [
  { key: 'uiVolume', label: 'UI VOLUME', type: 'range', min: 0, max: 100 },
  { key: 'musicVolume', label: 'MUSIC VOLUME', type: 'range', min: 0, max: 100 },
  { key: 'hudSize', label: 'HUD SIZE', type: 'range', min: 70, max: 130 },
  { key: 'killSounds', label: 'KILL SOUNDS', type: 'bool' },
  { key: 'showPing', label: 'SHOW PING', type: 'bool' },
  { key: 'showMinimap', label: 'MINIMAP IN MATCH', type: 'bool' },
  { key: 'visualEffects', label: 'VISUAL EFFECTS', type: 'bool' },
  { key: 'lowSpecMode', label: 'LOW SPEC MODE', type: 'bool' },
  { key: 'spectatorAuto', label: 'AUTO SPECTATE', type: 'bool' },
  { key: 'killFeedPos', label: 'KILL FEED SIDE', type: 'select', options: ['right', 'left'] },
  { key: 'language', label: 'LANGUAGE', type: 'select', options: null },
  { key: 'teamColorA', label: 'TEAM A COLOUR', type: 'color' },
  { key: 'teamColorB', label: 'TEAM B COLOUR', type: 'color' }
];

function renderSettings() {
  const host = $('settings-root');
  const rows = SETTING_DEFS.map((d) => {
    const v = S.settings[d.key];
    if (d.type === 'range') return `<div class="srow"><label>${esc(tx(d.label))}</label>
      <div style="display:flex;align-items:center;gap:10px">
        <input type="range" min="${d.min}" max="${d.max}" value="${v}" data-set="${d.key}"/>
        <span class="val" data-val="${d.key}">${v}</span></div></div>`;
    if (d.type === 'bool') return `<div class="srow"><label>${esc(tx(d.label))}</label>
      <label class="sw"><input type="checkbox" data-set="${d.key}" ${v ? 'checked' : ''}/><i></i></label></div>`;
    if (d.type === 'select') {
      // the language row is built from Locale.available, so adding a language
      // to Locale.lua is enough to make it appear here
      const opts = d.options
        ? d.options.map((o) => ({ id: o, label: String(o).toUpperCase() }))
        : LANGUAGES;
      return `<div class="srow"><label>${esc(tx(d.label))}</label>
        <select class="sel" data-set="${d.key}">${opts.map((o) =>
          `<option value="${esc(o.id)}" ${o.id === v ? 'selected' : ''}>${esc(o.label)}</option>`
        ).join('')}</select></div>`;
    }
    return `<div class="srow"><label>${esc(tx(d.label))}</label>
      <input class="swatch" type="color" value="${v}" data-set="${d.key}"/></div>`;
  });
  const half = Math.ceil(rows.length / 2);
  host.innerHTML = `
    <div class="card"><span class="card-tag">INTERFACE</span>${rows.slice(0, half).join('')}</div>
    <div class="card"><span class="card-tag">GAMEPLAY</span>${rows.slice(half).join('')}
      <button class="btn ghost" style="margin-top:14px" data-action="settings-reset">RESET TO DEFAULTS</button></div>`;

  enhanceSelects(host);

  host.querySelectorAll('[data-set]').forEach((input) => {
    const key = input.dataset.set;
    const h = () => {
      let value;
      if (input.type === 'checkbox') value = input.checked;
      else if (input.type === 'range') {
        value = parseInt(input.value, 10);
        const lbl = host.querySelector(`[data-val="${key}"]`);
        if (lbl) lbl.textContent = value;
      } else value = input.value;
      S.settings[key] = value;
      if (key === 'language') {
        S.langPinned = true;
        try { localStorage.setItem('m5rp_lang_pinned', '1'); } catch (err) {}
        applyLanguage(value);
      }
      saveSettings();
    };
    input.oninput = h; input.onchange = h;
  });
}

/* ----------------------------------------------------------------- theme */
/** Maps Config.UI (client config) onto the stylesheet's CSS variables. */
const COLOR_VARS = {
  accent: '--red', accentDark: '--red-2', accentSoft: '--red-soft', accentGlow: '--red-glow',
  background: '--bg', panel: '--panel', panelAlt: '--panel-2', panelDeep: '--panel-deep',
  edge: '--edge', edgeSoft: '--edge-soft',
  text: '--text', textDim: '--dim', textFaint: '--dim-2',
  win: '--win', lose: '--lose', gold: '--gold',
  teamA: '--team-a', teamB: '--team-b',
  avatarFrom: '--avatar-from', avatarTo: '--avatar-to',
  accentLight: '--red-3', winLight: '--win-2',
  levelBadge: '--level', leaderMark: '--ok'
};

/** '#2E9BE6' -> '46,155,230'. Lets a stylesheet write a translucent tint of
 *  the accent without hardcoding the colour. */
function rgbTriplet(color) {
  const m = String(color || '').trim().match(/^#?([0-9a-f]{6})$/i);
  if (m) {
    const n = parseInt(m[1], 16);
    return `${(n >> 16) & 255},${(n >> 8) & 255},${n & 255}`;
  }
  const rgb = String(color || '').match(/(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
  return rgb ? `${rgb[1]},${rgb[2]},${rgb[3]}` : null;
}

function applyTheme(theme) {
  if (!theme) return;
  S.theme = theme;
  const root = document.documentElement;

  if (theme.colors) {
    Object.keys(COLOR_VARS).forEach((key) => {
      const value = theme.colors[key];
      if (value) root.style.setProperty(COLOR_VARS[key], value);
    });
    // the accent again as a triplet, for the translucent tints
    const trip = rgbTriplet(theme.colors.accent);
    if (trip) root.style.setProperty('--red-rgb', trip);
  }

  if (theme.radius !== undefined) root.style.setProperty('--r', theme.radius + 'px');
  if (theme.scale) root.style.setProperty('--scale', theme.scale);

  const decor = theme.decor || {};
  document.body.classList.toggle('no-decor', decor.grain === false && decor.vignette === false);
  const grain = document.querySelector('.ab-grain');
  const vig = document.querySelector('.ab-vignette');
  if (grain) grain.style.display = decor.grain === false ? 'none' : '';
  if (vig) vig.style.display = decor.vignette === false ? 'none' : '';
  document.querySelectorAll('.ab-glow').forEach((g) => {
    g.style.display = decor.glow === false ? 'none' : '';
  });

  // player colour overrides win over the config
  applySettings();
}

function loadSettings() {
  let stored = {};
  try { stored = JSON.parse(localStorage.getItem('m5rp_settings') || '{}'); } catch (e) {}
  try { S.langPinned = localStorage.getItem('m5rp_lang_pinned') === '1'; } catch (e) {}
  S.settings = Object.assign({}, DEFAULTS, stored);
  applyLanguage(S.settings.language || 'en');
  applySettings();
}
function saveSettings() {
  try { localStorage.setItem('m5rp_settings', JSON.stringify(S.settings)); } catch (e) {}
  applySettings();
  post('settings', { settings: S.settings });
}
function applySettings() {
  const r = document.documentElement;
  if (S.settings.language && S.settings.language !== S.lang) applyLanguage(S.settings.language);
  if (S.settings.teamColorA) r.style.setProperty('--team-a', S.settings.teamColorA);
  if (S.settings.teamColorB) r.style.setProperty('--team-b', S.settings.teamColorB);
  $('killfeed').classList.toggle('left', S.settings.killFeedPos === 'left');
  $('hud').style.transform = `scale(${(S.settings.hudSize || 100) / 100})`;
  $('hud-ping').style.display = S.settings.showPing === false ? 'none' : '';
}

/* ================================================================= STORE */
/* Cards are the banner behind your lobby slot, titles are a word beside your
   name. Prices and ownership come from the server with the payload; this file
   only draws what it is told and sends back an id. */

function renderStore(store) {
  if (store) S.store = store;
  const d = S.store;
  const host = $('store-root');
  if (!d || !host) return;

  $('store-coins').textContent = num(d.coins || 0);

  document.querySelectorAll('.stab').forEach((b) =>
    b.classList.toggle('active', b.dataset.stab === S.storeTab));

  const items = (S.storeTab === 'titles' ? d.titles : d.cards) || [];
  const isTitle = S.storeTab === 'titles';

  if (!items.length) {
    host.innerHTML = `<div class="empty">${esc(tx('NOTHING IN THE STORE'))}</div>`;
    return;
  }

  host.innerHTML = `<div class="${isTitle ? 'title-grid' : 'card-grid'}">${
    items.map((it) => {
      // owned but not worn -> EQUIP, not owned -> BUY, worn -> a flat label
      const action = it.equipped
        ? `<div class="si-owned">${esc(tx('EQUIPPED'))}</div>`
        : it.owned
          ? `<button class="btn si-btn" data-store="equip" data-kind="${isTitle ? 'title' : 'card'}"
                     data-id="${esc(it.id)}">${esc(tx('EQUIP'))}</button>`
          : `<button class="btn ghost si-btn${(d.coins < it.price) ? ' poor' : ''}"
                     data-store="buy" data-kind="${isTitle ? 'title' : 'card'}"
                     data-id="${esc(it.id)}">
               <svg><use href="#i-coin"/></svg>${num(it.price)} ${esc(tx('BUY'))}</button>`;

      const face = isTitle
        ? `<div class="ti-face" style="color:${esc(it.color || 'var(--text)')}">${esc(it.name)}</div>`
        : `<div class="ci-art"${it.image ? ` style="background-image:url('${esc(it.image)}')"` : ''}>
             ${it.image ? '' : `<span class="ci-blank">${esc(it.name)}</span>`}
           </div>`;

      return `<div class="sitem ${it.rarity}${it.equipped ? ' on' : ''}">
        <div class="si-rar" style="color:${esc(it.rarityColor)}">${esc(it.rarityLabel)}</div>
        ${face}
        <div class="si-foot">
          ${isTitle ? '' : `<div class="si-name">${esc(it.name)}</div>`}
          ${action}
        </div>
      </div>`;
    }).join('')}</div>`;

  host.querySelectorAll('[data-store]').forEach((b) => {
    b.onclick = () => {
      Sfx.play('click');
      post('store', { action: b.dataset.store, kind: b.dataset.kind, id: b.dataset.id });
    };
  });
}

/* ================================================================= ADMIN */
/* Every control is gated by d.allowed, which the server builds from
   Config.AdminActions for the calling staff member. Nothing that the caller
   cannot perform is rendered at all. */

const ADM_GROUPS = [
  { id: 'monitor', label: 'MONITOR', icon: '#i-target' },
  { id: 'match',   label: 'MATCHES', icon: '#i-play' },
  { id: 'points',  label: 'POINTS',  icon: '#i-ranked' },
  { id: 'punish',  label: 'PUNISH',  icon: '#i-shield' },
  { id: 'system',  label: 'SYSTEM',  icon: '#i-cog' }
];

function admCan(action) {
  return !!(S.admin && S.admin.allowed && S.admin.allowed[action]);
}
function admDef(action) {
  return (S.admin && S.admin.allowed && S.admin.allowed[action]) || {};
}

/** Difficulty presets for the bot match, sent with the admin dashboard. */
function botDifficultyOptions() {
  const list = (S.admin && S.admin.botMatch && S.admin.botMatch.difficulties) || [];
  if (!list.length) return `<option value="normal">NORMAL</option>`;
  return list.map((d) =>
    `<option value="${esc(d.id)}"${d.isDefault ? ' selected' : ''}>${esc(d.label)}</option>`).join('');
}

/** Shared target box: one player id feeds every player tool. Digits only. */
function admTarget() {
  const raw = ($('adm-target') && $('adm-target').value.trim()) || '';
  return /^[0-9]+$/.test(raw) ? raw : '';
}
function admReason() {
  return ($('adm-reason') && $('adm-reason').value.trim()) || '';
}

/** Runs an action, enforcing the reason and confirm flags the server declared. */
function admRun(action, extra) {
  const def = admDef(action);
  const payload = Object.assign({ action }, extra || {});

  if (def.reason) {
    const reason = admReason();
    if (reason.length < 3) { toast('warning', 'A reason is required for this action.', 'ADMIN'); return; }
    payload.reason = reason;
  }
  if (def.confirm) {
    askConfirm(def.label || action, 'Confirm this action?', () => {
      Sfx.play('click');
      post('admin', payload);
    });
    return;
  }

  Sfx.play('click');
  post('admin', payload);
}

function renderAdminTabs() {
  const host = $('adm-tabs');
  if (!host) return;
  const groups = ADM_GROUPS.filter((g) =>
    Object.keys((S.admin && S.admin.allowed) || {}).some((a) => admDef(a).group === g.id));

  if (!S.admTab || !groups.find((g) => g.id === S.admTab)) {
    S.admTab = groups.length ? groups[0].id : 'monitor';
  }

  host.innerHTML = '';
  groups.forEach((g) => {
    const b = el('button', 'adm-tab' + (g.id === S.admTab ? ' active' : ''),
      `<svg><use href="${g.icon}"/></svg>${esc(tx(g.label))}`);
    b.onclick = () => { S.admTab = g.id; Sfx.play('click'); renderAdmin(S.admin); };
    host.appendChild(b);
  });

  const refresh = el('button', 'adm-tab', `<svg><use href="#i-back"/></svg>${esc(tx('REFRESH'))}`);
  refresh.style.marginLeft = 'auto';
  refresh.onclick = () => post('admin', { action: 'dashboard' });
  host.appendChild(refresh);
}

function renderAdmin(d) {
  if (!d) return;
  S.admin = d;
  renderAdminTabs();

  const host = $('admin-root');
  const tab  = S.admTab;
  const list = (rows, fn, empty) => (rows && rows.length) ? rows.map(fn).join('') : `<div class="empty">${empty}</div>`;

  /* ---------- shared target bar ---------- */
  const targetBar = `
    <div class="adm-target">
      <div><span class="lbl">${esc(tx('TARGET PLAYER'))}</span>
        <input class="inp" id="adm-target" inputmode="numeric" maxlength="10"
               placeholder="${esc(tx('PLAYER ID'))}" value="${esc(S.admTargetValue || '')}"/></div>
      <div><span class="lbl">${esc(tx('REASON'))}</span>
        <input class="inp" id="adm-reason" placeholder="Required for most actions"/></div>
      <div><span class="lbl">${esc(tx('STATUS'))}</span>
        <div class="who ${S.admLookup ? 'on' : ''}" id="adm-who">
          <span class="dot"></span>
          ${S.admLookup
            ? `<b>${esc(S.admLookup.name)}</b> · ${esc(S.admLookup.rank)} · ${num(S.admLookup.rp)} RP`
            : esc(tx('no player loaded'))}
          <button class="mini" data-adm="lookupInput" style="margin-left:6px">${esc(tx('LOAD'))}</button>
        </div></div>
    </div>`;

  /* one action row: name, fields, single button */
  const act = (action, opts) => {
    if (!admCan(action)) return '';
    const def = admDef(action);
    const o = opts || {};
    // hints may carry markup, so they are translated but not escaped. A row
    // with controls still shows its hint, printed underneath them.
    const middle = o.fields
      ? `<div class="act-fields">${o.fields}${
           o.hint ? `<div class="act-note">${tx(o.hint)}</div>` : ''}</div>`
      : `<div class="act-hint">${tx(o.hint || '')}</div>`;

    return `<div class="act ${o.danger ? 'danger' : ''}">
      <div class="act-name"><b>${esc(tx(def.label || action))}</b><span>${esc(def.permission || action)}</span></div>
      ${middle}
      <button class="btn ${o.danger ? '' : 'ghost'}" data-adm="${esc(o.run || action)}">${esc(tx(o.button || 'APPLY'))}</button>
    </div>`;
  };

  let html = '';

  /* ------------------------------------------------------- MONITOR */
  if (tab === 'monitor') {
    html = `<div class="adm-cols">
      <div class="card"><span class="card-tag">LIVE MATCHES · ${(d.matches || []).length}</span>
        <div class="alist">${list(d.matches, (m) => `<div class="arow">
          <b>${esc(m.mode)}</b>
          <span class="grow">${esc(m.map)} · ${esc(m.state)} · R${m.round} · ${m.scores.a}-${m.scores.b} · ${m.players}P</span>
          ${admCan('spectate') ? `<button class="mini" data-adm="spectate" data-match="${esc(m.id)}">WATCH</button>` : ''}
          ${admCan('restartRound') ? `<button class="mini" data-adm="restartRound" data-match="${esc(m.id)}">RESTART</button>` : ''}
          ${admCan('endMatch') ? `<button class="mini" data-adm="endMatch" data-match="${esc(m.id)}">STOP</button>` : ''}
        </div>`, 'NO LIVE MATCHES')}</div>
        ${admCan('stopSpectate') ? '<button class="btn ghost wide" style="margin-top:11px" data-adm="stopSpectate">STOP SPECTATING</button>' : ''}
      </div>

      <div class="card"><span class="card-tag">IN QUEUE · ${(d.searching || []).length}</span>
        <div class="alist">${list(d.searching, (p) => `<div class="arow"><b>${esc(p.name)}</b>
          <span class="grow">${esc(p.mode)} · ${esc(p.rank)}${p.mmr ? ` · MMR ${p.mmr}` : ''}</span>
          <span>${p.waited}s</span></div>`, 'QUEUE EMPTY')}</div></div>

      <div class="card"><span class="card-tag">CUSTOM ROOMS · ${(d.rooms || []).length}</span>
        <div class="alist">${list(d.rooms, (r) => `<div class="arow"><b>${esc(r.name)}</b>
          <span class="grow">${esc(r.host)} · ${r.players}/${r.maxPlayers} · ${esc(r.state)}${r.code ? ` · ${esc(r.code)}` : ''}</span>
          ${admCan('closeRoom') ? `<button class="mini" data-adm="closeRoom" data-room="${esc(r.id)}">CLOSE</button>` : ''}
        </div>`, 'NO ROOMS')}</div></div>

      <div class="card"><span class="card-tag">FLAGGED PLAYERS</span>
        <div class="alist">${list(d.suspicious, (f) => `<div class="arow"><b>${esc(f.name || f.user_id)}</b>
          <span class="grow">${f.flags} flags</span><span class="sev">SEV ${f.score}</span>
          ${admCan('playerLookup') ? `<button class="mini" data-adm="lookup" data-target="${f.user_id}">INSPECT</button>` : ''}
        </div>`, 'NOTHING FLAGGED')}</div></div>
    </div>`;
  }

  /* -------------------------------------------------------- MATCH */
  if (tab === 'match') {
    html = targetBar + `<div class="adm-list">
      ${act('kickFromMatch', { button: 'REMOVE', danger: true,
        hint: 'Takes the target out of their current match.' })}
      ${act('movePlayer', { button: 'MOVE', fields:
        `<input class="inp" id="adm-match" placeholder="Match id"/>
         <select id="adm-team"><option value="1">Team A</option><option value="2">Team B</option></select>` })}
      ${act('freeze', { button: 'FREEZE', run: 'freezeOn', danger: true,
        hint: `Ranked queue is currently <b style="color:${d.frozen ? 'var(--lose)' : 'var(--win)'}">${d.frozen ? 'FROZEN' : 'OPEN'}</b>.` })}
      ${admCan('freeze') ? `<div class="act">
        <div class="act-name"><b>Unfreeze Queue</b><span>pvp.admin.freeze</span></div>
        <div class="act-hint">Re-opens ranked matchmaking.</div>
        <button class="btn ghost" data-adm="freezeOff">UNFREEZE</button></div>` : ''}

      ${act('startBotMatch', { button: 'START', fields: `
        <select id="adm-bot-diff">${botDifficultyOptions()}</select>
        <select id="adm-bot-count">${[1, 2, 3, 4, 5]
          .map((n) => `<option value="${n}">${n} ${tx(n === 1 ? 'BOT' : 'BOTS')}</option>`).join('')}</select>
        <select id="adm-bot-rounds">${[1, 3, 5, 7, 9]
          .map((n) => `<option value="${n}"${n === 5 ? ' selected' : ''}>${n} ${tx('ROUNDS')}</option>`).join('')}</select>
        <select id="adm-bot-map"><option value="">${esc(tx('RANDOM MAP'))}</option>${
          ((S.boot && S.boot.maps) || [])
            .map((m) => `<option value="${esc(m.id)}">${esc(m.name)}</option>`).join('')}</select>`,
        hint: 'Practice duel against AI on your own screen. Always unranked — no RP, MMR or stats.' })}
      ${admCan('startBotMatch') ? `<div class="act">
        <div class="act-name"><b>${esc(tx('Stop Bot Match'))}</b><span>pvp.admin.botmatch</span></div>
        <div class="act-hint">${esc(tx('Ends your practice session and returns you to the world.'))}</div>
        <button class="btn ghost" data-adm="stopBotMatch">${esc(tx('STOP'))}</button></div>` : ''}
    </div>

    <div class="card" style="margin-top:16px"><span class="card-tag">LIVE MATCHES</span>
      <div class="alist">${list(d.matches, (m) => `<div class="arow"><b>${esc(m.id)}</b>
        <span class="grow">${esc(m.mode)} · ${esc(m.map)} · ${esc(m.state)}</span>
        ${admCan('spectate') ? `<button class="mini" data-adm="spectate" data-match="${esc(m.id)}">WATCH</button>` : ''}
        ${admCan('endMatch') ? `<button class="mini" data-adm="endMatch" data-match="${esc(m.id)}">STOP</button>` : ''}
      </div>`, 'NO LIVE MATCHES')}</div></div>`;
  }

  /* ------------------------------------------------------- POINTS */
  if (tab === 'points') {
    const rankOptions = ((S.boot && S.boot.ranks) || [])
      .map((r) => `<option value="${r.id}">${esc(r.name)}</option>`).join('');

    html = targetBar + `<div class="adm-list">
      ${act('addRP', { button: 'GRANT', fields:
        `<input class="inp" id="adm-rp-add" type="number" placeholder="RP to grant"/>` })}
      ${act('removeRP', { button: 'DEDUCT', danger: true, fields:
        `<input class="inp" id="adm-rp-rem" type="number" placeholder="RP to deduct"/>` })}
      ${act('setRP', { button: 'SET', fields:
        `<input class="inp" id="adm-rp-set" type="number" placeholder="Exact RP total"/>` })}
      ${act('setRank', { button: 'APPLY', fields: `<select id="adm-rank">${rankOptions}</select>` })}
      ${act('addXP', { button: 'GRANT XP', fields:
        `<input class="inp" id="adm-xp" type="number" placeholder="XP"/>` })}
      ${act('giveCoins', { button: 'GIVE', fields:
        `<input class="inp" id="adm-coins-add" type="number" placeholder="Coins to give"/>`,
        hint: 'Coins are spent in the Store on cards and titles.' })}
      ${act('takeCoins', { button: 'TAKE', danger: true, fields:
        `<input class="inp" id="adm-coins-rem" type="number" placeholder="Coins to take"/>` })}
      ${act('resetStats', { button: 'RESET', danger: true,
        hint: 'Wipes stats, rank and MMR for the current season only.' })}
    </div>`;
  }

  /* ------------------------------------------------------- PUNISH */
  if (tab === 'punish') {
    const types = ((S.boot && S.boot.rankBanTypes) || ['RANKED'])
      .map((t) => `<option value="${esc(t)}">${esc(t)}</option>`).join('');
    const durations = ((S.boot && S.boot.banDurations) || [])
      .map((b) => `<option value="${b.seconds}">${esc(b.label)}</option>`).join('');

    html = targetBar + `<div class="adm-list">
      ${act('ban', { button: 'BAN', danger: true, fields:
        `<select id="adm-bantype">${types}</select><select id="adm-bandur">${durations}</select>` })}
      ${act('unban', { button: 'UNBAN', hint: 'Lifts every active ranked ban on the target.' })}
      ${act('clearCooldown', { button: 'CLEAR', hint: 'Removes an abandon or decline cooldown.' })}
    </div>

    <div class="adm-cols" style="margin-top:16px">
      <div class="card"><span class="card-tag">ACTIVE RANKED BANS</span>
        <div class="alist">${list(d.bans, (b) => `<div class="arow"><b>${esc(b.name || b.user_id)}</b>
          <span class="grow">${esc(b.type)} · ${esc(b.reason)} · by ${esc(b.admin)}</span>
          ${admCan('unban') ? `<button class="mini" data-adm="unbanRow" data-target="${b.user_id}" data-ban="${b.id}">UNBAN</button>` : ''}
        </div>`, 'NO ACTIVE BANS')}</div></div>

      <div class="card"><span class="card-tag">ANTI-BOOST FLAGS</span>
        <div class="alist">${list(d.suspicious, (f) => `<div class="arow"><b>${esc(f.name || f.user_id)}</b>
          <span class="grow">${f.flags} flags</span><span class="sev">SEV ${f.score}</span>
          ${admCan('playerLookup') ? `<button class="mini" data-adm="lookup" data-target="${f.user_id}">INSPECT</button>` : ''}
        </div>`, 'NOTHING FLAGGED')}</div></div>
    </div>`;
  }

  /* ------------------------------------------------------- SYSTEM */
  if (tab === 'system') {
    const modes = ((S.boot && S.boot.allModes) || [])
      .map((m) => `<option value="${m.id}">${esc(m.label)}</option>`).join('');

    html = `<div class="adm-list">
      ${act('newSeason', { button: 'START SEASON', danger: true,
        hint: 'Archives the season, pays rewards and opens the next one.' })}
      ${act('toggleMode', { button: 'ENABLE', run: 'modeOn',
        fields: `<select id="adm-mode">${modes}</select>` })}
      ${admCan('toggleMode') ? `<div class="act">
        <div class="act-name"><b>Disable Mode</b><span>pvp.admin.mode</span></div>
        <div class="act-hint">Uses the mode selected above.</div>
        <button class="btn ghost" data-adm="modeOff">DISABLE</button></div>` : ''}
    </div>

    <div class="adm-cols" style="margin-top:16px">
      <div class="card"><span class="card-tag">SEASONS</span>
        <div class="alist">${list(d.seasons, (x) => `<div class="arow"><b>#${x.number} ${esc(x.name)}</b>
          <span class="grow">${esc(String(x.start_at || '').slice(0, 10))} → ${esc(String(x.end_at || '').slice(0, 10))}</span>
          <span>${x.active ? 'ACTIVE' : 'ARCHIVED'}</span></div>`, 'NO SEASONS')}</div></div>

      ${admCan('auditLog') ? `<div class="card"><span class="card-tag">AUDIT LOG · LAST 30</span>
        <div class="alist">${list(d.audit, (a) => `<div class="audit-row">
          <span class="act-tag">${esc(a.action)}</span>
          <span>${esc(a.admin_name)}${a.target_name ? ` → ${esc(a.target_name)}` : ''}${
            a.amount ? ` · ${a.amount > 0 ? '+' : ''}${a.amount}` : ''}${a.reason ? ` · ${esc(a.reason)}` : ''}</span>
          <span class="when">${esc(String(a.created_at || '').replace('T', ' ').slice(0, 16))}</span>
        </div>`, 'NOTHING LOGGED YET')}</div></div>` : ''}
    </div>`;
  }

  if (!html) html = '<div class="locked-note">YOU HAVE NO PERMISSIONS IN THIS SECTION</div>';
  host.innerHTML = html;

  /* The target is a user id only — a name could match two accounts and point a
     ban or an RP wipe at the wrong one, so anything non-numeric is stripped. */
  const targetInput = $('adm-target');
  if (targetInput) {
    targetInput.oninput = () => {
      const clean = targetInput.value.replace(/[^0-9]/g, '');
      if (clean !== targetInput.value) targetInput.value = clean;
      S.admTargetValue = clean;
    };
  }

  host.querySelectorAll('[data-adm]').forEach((b) => { b.onclick = () => admAction(b); });
  enhanceSelects(host);
}

function admAction(btn) {
  const a = btn.dataset.adm;
  const target = admTarget();
  const val = (id) => { const n = $(id); return n ? n.value : ''; };

  switch (a) {
    case 'spectate':      admRun('spectate', { matchId: btn.dataset.match }); break;
    case 'stopSpectate':  admRun('stopSpectate', {}); break;
    case 'restartRound':  admRun('restartRound', { matchId: btn.dataset.match }); break;
    case 'endMatch':      admRun('endMatch', { matchId: btn.dataset.match }); break;
    case 'closeRoom':     admRun('closeRoom', { roomId: btn.dataset.room }); break;

    case 'lookup':        post('admin', { action: 'playerLookup', target: btn.dataset.target }); break;
    case 'lookupInput':
      if (!target) { toast('warning', tn('Enter a player ID first.'), tn('ADMIN')); break; }
      post('admin', { action: 'playerLookup', target });
      break;

    case 'kickFromMatch': admRun('kickFromMatch', { target }); break;
    case 'movePlayer':    admRun('movePlayer', { target, matchId: val('adm-match'), team: parseInt(val('adm-team'), 10) }); break;
    case 'freezeOn':      admRun('freeze', { value: true }); break;
    case 'freezeOff':     admRun('freeze', { value: false }); break;

    case 'startBotMatch':
      admRun('startBotMatch', {
        difficulty: val('adm-bot-diff'),
        bots:       parseInt(val('adm-bot-count'), 10) || 1,
        rounds:     parseInt(val('adm-bot-rounds'), 10) || 5,
        map:        val('adm-bot-map') || null
      });
      break;
    case 'stopBotMatch':  admRun('stopBotMatch', {}); break;

    case 'addRP':         admRun('addRP', { target, amount: parseInt(val('adm-rp-add'), 10) }); break;
    case 'removeRP':      admRun('removeRP', { target, amount: parseInt(val('adm-rp-rem'), 10) }); break;
    case 'setRP':         admRun('setRP', { target, value: parseInt(val('adm-rp-set'), 10) }); break;
    case 'setRank':       admRun('setRank', { target, rankId: parseInt(val('adm-rank'), 10) }); break;
    case 'addXP':         admRun('addXP', { target, amount: parseInt(val('adm-xp'), 10) }); break;
    case 'giveCoins':     admRun('giveCoins', { target, amount: parseInt(val('adm-coins-add'), 10) }); break;
    case 'takeCoins':     admRun('takeCoins', { target, amount: parseInt(val('adm-coins-rem'), 10) }); break;
    case 'resetStats':    admRun('resetStats', { target }); break;

    case 'ban':           admRun('ban', { target, type: val('adm-bantype'), duration: parseInt(val('adm-bandur'), 10) }); break;
    case 'unban':         admRun('unban', { target }); break;
    case 'unbanRow':      admRun('unban', { target: btn.dataset.target, banId: btn.dataset.ban }); break;
    case 'clearCooldown': admRun('clearCooldown', { target }); break;

    case 'newSeason':     admRun('newSeason', {}); break;
    case 'modeOn':        admRun('toggleMode', { mode: val('adm-mode'), value: true }); break;
    case 'modeOff':       admRun('toggleMode', { mode: val('adm-mode'), value: false }); break;
  }
}

/* =============================================================== IN MATCH */
/** A player portrait. The initial is always drawn underneath and the avatar
 *  sits on top of it, so a picture that fails to load simply reveals the
 *  letter — no error handler rewriting the DOM while it is still parsing. */
/* The initial is always drawn underneath and the image laid over it, so a
   portrait that fails to load simply reveals the letter again. */
function avatarInner(p) {
  const img = p.avatar
    ? `<img src="${esc(p.avatar)}" alt="" loading="lazy" onerror="this.remove()"/>`
    : '';
  return `<span class="ini">${esc(initial(p.name))}</span>${img}`;
}
function avatarCell(p, cls) {
  return `<div class="${cls}">${avatarInner(p)}</div>`;
}

/** `#1234` next to a name, or '' when ids are switched off. */
function idTag(userId, on) {
  return (on !== false && userId !== undefined && userId !== null)
    ? `<i class="pid">#${esc(userId)}</i>` : '';
}

/* A row of ticks rather than one continuous bar. The nodes are only rebuilt
   when the tick count changes — every other frame just toggles a class. */
function segBar(host, filled, total) {
  if (!host) return;
  if (host.children.length !== total) {
    host.innerHTML = new Array(total).fill('<i></i>').join('');
  }
  for (let i = 0; i < total; i++) host.children[i].classList.toggle('on', i < filled);
}

/** Ping bands, so a bad connection reads before the number does. */
function pingClass(ms) {
  const n = ms || 0;
  return n >= 120 ? ' bad' : (n >= 70 ? ' warn' : '');
}

function hudCfg(part) {
  const c = (S.matchInfo && S.matchInfo.hudCfg) || {};
  return (part ? c[part] : c) || {};
}

/** The row of portraits on one side of the HUD. */
function renderFaces(hostId, players, meId) {
  const host = $(hostId);
  if (!host) return;
  host.innerHTML = players.map((p) => {
    const state = (p.connected === false) ? ' down'
                : (p.alive === false ? ' down' : '');
    const mine  = p.userId === meId ? ' me' : '';
    return avatarCell(p, 'face' + state + mine);
  }).join('');
}

function renderHud(d) {
  if (!d) return;
  S.hud = d;
  $('hud-score-a').textContent = d.scores.a;
  $('hud-score-b').textContent = d.scores.b;
  $('hud-alive-a').textContent = d.aliveA;
  $('hud-alive-b').textContent = d.aliveB;
  $('hud-round').textContent = d.ffa ? tx('FREE FOR ALL')
    : (d.overtime ? `${tx('OVERTIME')} · ${tx('ROUND')} ${d.round}` : `${tx('ROUND')} ${d.round}`);
  $('hud-ping').textContent = `${d.ping || 0} ms`;

  // team names come from the server (fixed, or named after a player)
  $('hud-team-a').textContent = d.teamA || tx('TEAM A');
  $('hud-team-b').textContent = d.teamB || tx('TEAM B');

  // one pip per round won, out of the rounds needed to take the match
  const need = (S.matchInfo && S.matchInfo.settings && S.matchInfo.settings.roundsToWin)
               || Math.ceil((d.maxRounds || 0) / 2) || 0;
  if (need > 0 && !d.ffa) {
    const pips = (won) => `<div class="pips ${won.side}">${
      Array.from({ length: need }, (_, i) =>
        `<i class="${i < won.n ? 'on' : ''}"></i>`).join('')}</div>`;
    $('hud-pips').innerHTML = pips({ side: 'a', n: d.scores.a }) + pips({ side: 'b', n: d.scores.b });
    $('hud-pips').style.display = '';
  } else {
    $('hud-pips').style.display = 'none';
  }

  /* Each side's panel carries its own score, so the state of the series is
     told on the panel rather than by a shared pair in the middle: the side
     that is behind steps back, and a side one round from the match goes gold. */
  const sideA = document.querySelector('.hud-side.a');
  const sideB = document.querySelector('.hud-side.b');
  const pointA = need > 0 && !d.ffa && d.scores.a === need - 1;
  const pointB = need > 0 && !d.ffa && d.scores.b === need - 1;
  if (sideA) {
    sideA.classList.toggle('trail', d.scores.a < d.scores.b);
    sideA.classList.toggle('point', pointA);
  }
  if (sideB) {
    sideB.classList.toggle('trail', d.scores.b < d.scores.a);
    sideB.classList.toggle('point', pointB);
  }

  const flag = $('hud-flag');
  flag.textContent = tx('MATCH POINT');
  flag.classList.toggle('hidden', !(pointA || pointB));

  const board = d.scoreboard || [];
  const meId  = S.boot && S.boot.player && S.boot.player.userId;
  renderFaces('hud-faces-a', board.filter((p) => p.team === 1), meId);
  renderFaces('hud-faces-b', board.filter((p) => p.team === 2), meId);

  if (S.sbOpen) renderScoreboard();

  S.hudTime = d.time || 0;
  updateTimer();
}

/* ------------------------------------------------------------ scoreboard */
/** Full in-match scoreboard, shown while TAB is held. */
function renderScoreboard() {
  const d = S.hud;
  if (!d) return;

  const meId  = S.boot && S.boot.player && S.boot.player.userId;
  const board = (d.scoreboard || []).slice();

  $('sb-mode').textContent = (S.matchInfo && S.matchInfo.modeLabel)
    || (d.ffa ? tx('FREE FOR ALL') : tx('RANKED'));
  $('sb-map').textContent = (S.matchInfo && S.matchInfo.map && S.matchInfo.map.name) || '';
  $('sb-score-a').textContent = d.scores.a;
  $('sb-score-b').textContent = d.scores.b;
  $('sb-round').textContent = d.maxRounds
    ? `${tx('ROUND')} ${d.round} / ${d.maxRounds}` : `${tx('ROUND')} ${d.round}`;

  $('sb-team-a').textContent = d.teamA || tx('TEAM A');
  $('sb-team-b').textContent = d.teamB || tx('TEAM B');
  $('sb-alive-a').textContent = `${d.aliveA} ${tx('ALIVE')}`;
  $('sb-alive-b').textContent = `${d.aliveB} ${tx('ALIVE')}`;

  const showIds = hudCfg('showcase').showIds;

  const row = (p, pos, top) => {
    const cls = (p.connected === false ? ' gone' : (p.alive === false ? ' dead' : ''))
              + (p.userId === meId ? ' me' : '')
              + (top ? ' top' : '');
    return `<div class="sb-row${cls}">
      <span class="sb-pos">#${pos}</span>
      <span class="sb-who">
        ${avatarCell(p, 'sb-av')}
        <span class="sb-nm">
          <span class="sb-nmrow"><b>${esc(p.name)}</b>${idTag(p.userId, showIds)}</span>
          <span>${esc(tx(p.rank || ''))}</span>
        </span>
      </span>
      <span>${p.kills || 0}</span>
      <span>${p.deaths || 0}</span>
      <span>${p.assists || 0}</span>
      <span class="hs">${p.headshots || 0}</span>
      <span>${num(p.damage || 0)}</span>
      <span class="sb-ping${pingClass(p.ping)}">${p.ping || 0}</span>
    </div>`;
  };

  const side = (team) => {
    const rows = board.filter((p) => p.team === team)
                      .sort((a, b) => (b.score || 0) - (a.score || 0));
    // the top of a sorted side leads it, but only once someone has scored
    const lead = rows.length && (rows[0].score || 0) > 0 ? rows[0] : null;
    return rows.length ? rows.map((p, i) => row(p, i + 1, p === lead)).join('')
                       : `<div class="sb-empty">${esc(tx('NO PLAYERS'))}</div>`;
  };

  $('sb-rows-a').innerHTML = side(1);
  $('sb-rows-b').innerHTML = side(2);
}

function toggleScoreboard(show) {
  S.sbOpen = !!show;
  const n = $('scoreboard');
  if (!n) return;
  if (show) { renderScoreboard(); n.classList.remove('hidden'); }
  else n.classList.add('hidden');
}
function updateTimer() {
  $('hud-clock').textContent = clock(S.hudTime);
  $('hud-timer').classList.toggle('low', S.hudTime <= 15 && S.hudTime > 0);
}
/* ============================================================== SHOWCASE */
/** Map name and both rosters, over the arena, until the first countdown. */
function renderShowcase(d) {
  const host = $('showcase');
  if (!host) return;
  const cfg = ((d && d.hudCfg) || {}).showcase || {};
  if (!d || cfg.enabled === false || d.ffa) { hideShowcase(); return; }

  $('sc-map').textContent = String((d.map && d.map.name) || d.modeLabel || '').toUpperCase();
  $('sc-sub').textContent = tx('PREPARING MATCH…');

  const names = d.teamNames || {};
  $('sc-team-a').textContent = names['1'] || names[1] || tx('TEAM A');
  $('sc-team-b').textContent = names['2'] || names[2] || tx('TEAM B');

  const meId = S.boot && S.boot.player && S.boot.player.userId;
  const card = (p, i) => `
    <div class="sc-card${p.userId === meId ? ' me' : ''}" style="animation-delay:${i * 70}ms">
      ${avatarCell(p, 'sc-av')}
      <span class="sc-who">
        <span class="sc-nm"><b>${esc(p.name)}</b>${idTag(p.userId, cfg.showIds)}</span>
        <span class="sc-rank">${esc(tx(p.rank || 'Unranked')).toUpperCase()}</span>
      </span>
      <span class="sc-crest${p.rank ? '' : ' none'}"><svg><use href="#i-crest"/></svg></span>
    </div>`;

  const side = (team, hostId) => {
    const rows = (d.roster || []).filter((p) => p.team === team);
    $(hostId).innerHTML = rows.map(card).join('');
  };
  side(1, 'sc-list-a');
  side(2, 'sc-list-b');

  host.classList.remove('hidden');
  clearTimeout(renderShowcase._t);
  renderShowcase._t = setTimeout(hideShowcase, (cfg.duration || 8) * 1000);
}
function hideShowcase() {
  clearTimeout(renderShowcase._t);
  const host = $('showcase');
  if (host) host.classList.add('hidden');
}

/** Name, portrait and id on the player card — fixed for the whole match. */
function renderPlayerCard() {
  const p = (S.boot && S.boot.player) || {};
  const cfg = hudCfg('player');
  $('hud-player').classList.toggle('hidden', cfg.enabled === false);
  $('pc-name').textContent = p.name || '—';
  $('pc-id').textContent = (cfg.showId !== false && p.userId !== undefined && p.userId !== null)
    ? `#${p.userId}` : '';
  $('pc-av').innerHTML = avatarInner(p);
  // draw the empty ticks now so the card is never half-built before the
  // first localHud frame arrives
  const segs = cfg.segments || 10;
  segBar($('pc-hp-segs'), 0, segs);
  segBar($('pc-ar-segs'), 0, segs);
  segBar($('gc-mag'), 0, hudCfg('weapon').segments || 12);
}

function renderLocalHud(d) {
  if (!d) return;
  const show = hudCfg('show');
  const pcfg = hudCfg('player');
  const wcfg = hudCfg('weapon');

  /* ---- player card: health and armour as ticks, not a sliding bar ---- */
  const segs = pcfg.segments || 10;
  const hp = Math.max(0, Math.min(100, d.health || 0));
  const ar = Math.max(0, Math.min(100, d.armor || 0));

  $('pc-hp').textContent = hp;
  segBar($('pc-hp-segs'), Math.ceil((hp / 100) * segs), segs);
  $('pc-hp-row').classList.toggle('low', hp <= 30);
  $('pc-hp-row').classList.toggle('hidden', show.health === false);

  $('pc-ar').textContent = ar;
  segBar($('pc-ar-segs'), Math.ceil((ar / 100) * segs), segs);
  $('pc-ar-row').classList.toggle('hidden', show.armor === false);

  /* ---- weapon card ---- */
  const gun = $('hud-gun');
  gun.classList.toggle('hidden', wcfg.enabled === false || show.weapon === false);

  const raw = String(d.weapon || '');
  $('hud-weapon-name').textContent = raw.replace('WEAPON_', '').replace(/_/g, ' ') || '—';

  // configured artwork wins; anything unlisted keeps the drawn silhouette
  const art = $('gc-art');
  const src = imgUrl((wcfg.images || {})[raw]);
  if (src) { art.style.backgroundImage = `url("${src}")`; art.classList.add('art'); }
  else { art.style.backgroundImage = ''; art.classList.remove('art'); }

  const clip = d.clip || 0;
  const max  = d.clipMax || 0;
  const ammo = d.ammo || 0;
  $('hud-clip').textContent = clip;
  // a loadout with infinite reserve reports a huge number, not a flag
  $('hud-ammo').textContent = ammo >= 9999 ? '∞' : ammo;
  $('hud-ammo').style.display = show.ammo === false ? 'none' : '';

  const mag = wcfg.segments || 12;
  segBar($('gc-mag'), max > 0 ? Math.min(mag, Math.ceil((clip / max) * mag)) : 0, mag);
  // 'dry', not 'empty': .empty is a generic placeholder class with padding
  $('gc-mag').parentNode.classList.toggle('dry', clip === 0);
}

function addKillFeed(d) {
  const host = $('killfeed');
  const meName = S.boot && S.boot.player && S.boot.player.name;
  const mine = d.killer === meName || d.victim === meName;
  const tc = (t) => (t === 1 ? 'n-a' : 'n-b');
  const node = el('div', 'kf' + (mine ? ' mine' : ''), `
    ${d.killer ? `<span class="${tc(d.killerTeam)}">${esc(d.killer)}</span>` : ''}
    <span class="kf-w">${esc(String(d.weapon || '').replace('WEAPON_', ''))}</span>
    ${d.headshot ? '<span class="kf-hs"><svg><use href="#i-head"/></svg>HS</span>' : ''}
    <span class="${tc(d.victimTeam)}">${esc(d.victim)}</span>`);
  host.appendChild(node);
  while (host.children.length > 6) host.removeChild(host.firstChild);
  setTimeout(() => { if (node.parentNode) node.remove(); }, 6000);
  if (S.settings.killSounds !== false && d.killer === meName) Sfx.play(d.headshot ? 'headshot' : 'kill');
}

const EVENT_TEXT = {
  FIRSTBLOOD: 'FIRST BLOOD', DOUBLEKILL: 'DOUBLE KILL', TRIPLEKILL: 'TRIPLE KILL',
  QUADRAKILL: 'QUADRA KILL', ACE: 'ACE', CLUTCH: 'CLUTCH', REVENGE: 'REVENGE',
  NEMESIS: 'NEMESIS', KILLSTREAK: 'KILL STREAK', OVERTIME: 'OVERTIME',
  SUDDEN_DEATH: 'SUDDEN DEATH', AFK_WARNING: 'MOVE OR BE REMOVED'
};

function showEvent(d) {
  if (!d || !d.type) return;
  if (d.type === 'SURRENDER_VOTE') {
    toast('warning', `Surrender vote: ${d.extra.yes}/${d.extra.total}`, 'SURRENDER');
    return;
  }
  const banner = $('combat-banner');
  let text = EVENT_TEXT[d.type] || d.type.replace(/_/g, ' ');
  if (typeof d.extra === 'number') text += ` ${d.extra}`;
  if (d.player) text = `${String(d.player).toUpperCase()} · ${text}`;
  $('combat-banner-text').textContent = text;
  banner.classList.remove('hidden');
  clearTimeout(showEvent._t);
  showEvent._t = setTimeout(() => banner.classList.add('hidden'), 2600);
  if (d.type === 'ACE' || d.type === 'CLUTCH') Sfx.play('rankup');
  else if (d.type === 'AFK_WARNING') Sfx.play('warning');
}

/* circumference of the countdown dial (2πr, r=53 in the SVG viewBox) */
const PH_CIRC = 333;

/* Puts the phase block back to its neutral state. Every branch below starts
   here, so nothing from the previous round can leak into the next one. */
function phaseReset() {
  clearInterval(renderRound._t);
  clearTimeout(renderRound._h);
  // the showcase has had its moment once a round starts moving
  hideShowcase();
  const phase = $('phase');
  phase.classList.remove('go', 'last');
  $('phase-dial').classList.remove('hidden');
  $('phase-word').classList.add('hidden');
  $('phase-score').classList.add('hidden');
  $('phase-round').textContent = '';
  $('phase-label').textContent = '';
  const num = $('phase-count');
  num.classList.remove('go', 'tick');
  const arc = $('phase-arc');
  arc.classList.remove('run');
  arc.style.strokeDashoffset = '0';
}

/* Restarts a CSS animation that is already on the element. Re-adding the class
   in the same frame is a no-op unless the layout is read in between. */
function replay(node, cls) {
  node.classList.remove(cls);
  void node.offsetWidth;
  node.classList.add(cls);
}

function renderRound(d) {
  if (!d) return;
  const phase = $('phase');

  if (d.phase === 'countdown') {
    phaseReset();
    phase.classList.remove('hidden');
    $('phase-round').textContent = `${tx('ROUND')} ${d.round}`;
    $('phase-label').textContent = tx('GET READY');

    const num = $('phase-count');
    const arc = $('phase-arc');
    let n = d.seconds || 3;

    const step = () => {
      if (n > 0) {
        // the final second turns the whole dial gold
        phase.classList.toggle('last', n === 1);
        num.textContent = n;
        num.classList.remove('go');
        replay(num, 'tick');
        // drain the ring over the second this number is up
        arc.classList.remove('run');
        arc.style.strokeDashoffset = '0';
        void arc.getBoundingClientRect();
        arc.classList.add('run');
        arc.style.strokeDashoffset = String(PH_CIRC);
        Sfx.play('tick');
      } else {
        clearInterval(renderRound._t);
        phase.classList.remove('last');
        phase.classList.add('go');
        num.textContent = tx('GO');
        num.classList.add('go');
        replay(num, 'tick');
        // ring snaps closed behind the word
        arc.classList.remove('run');
        arc.style.strokeDashoffset = '0';
        $('phase-label').textContent = '';
        Sfx.play('go');
        renderRound._h = setTimeout(() => phase.classList.add('hidden'), 950);
      }
      n -= 1;
    };
    step();
    renderRound._t = setInterval(step, 1000);

  } else if (d.phase === 'end') {
    phaseReset();
    phase.classList.remove('hidden');
    $('phase-dial').classList.add('hidden');

    const draw = !d.winner || d.winner === 0;
    const won  = !draw && d.winner === d.myTeam;
    const word = $('phase-word');
    word.textContent = draw ? tx('DRAW') : (won ? tx('ROUND WON') : tx('ROUND LOST'));
    word.className = 'ph-word ' + (draw ? 'draw' : (won ? 'win' : 'loss'))
                   + (word.textContent.length > 6 ? ' long' : '');

    $('phase-round').textContent = `${tx('ROUND')} ${d.round}`;
    if (d.reason && d.reason !== 'DRAW') $('phase-label').textContent = tx(d.reason);

    // Lua's {[1]=x,[2]=y} arrives as {"1":x,"2":y}; accept both shapes
    const sc = d.scores || {};
    $('phase-score-a').textContent = (sc.a !== undefined) ? sc.a : (sc['1'] || 0);
    $('phase-score-b').textContent = (sc.b !== undefined) ? sc.b : (sc['2'] || 0);
    $('phase-score').classList.remove('hidden');

    Sfx.play(won ? 'roundwin' : 'roundloss');
    renderRound._h = setTimeout(() => phase.classList.add('hidden'), 4200);

  } else if (d.phase === 'live') {
    phaseReset();
    phase.classList.add('hidden');
  }
}

function renderMatchEnd(d) {
  if (!d) return;
  const modal = $('modal-result');
  modal.classList.remove('hidden');
  // nothing else should be on screen behind the result
  toggleScoreboard(false);

  /* Accept either wording. A real match reports VICTORY/DEFEAT and a practice
     one used to report WIN/LOSS, which matched neither the colour test nor a
     locale key — the panel came out green with an untranslated word on it. */
  const RESULT = { WIN: 'VICTORY', LOSS: 'DEFEAT', LOSE: 'DEFEAT', TIE: 'DRAW' };
  const result = RESULT[d.result] || d.result || 'DRAW';

  modal.classList.toggle('defeat', result === 'DEFEAT');
  modal.classList.toggle('draw', result === 'DRAW');

  $('result-tag').textContent = tx(result);
  // Lua's {[1]=x,[2]=y} arrives as {"1":x,"2":y}; accept both shapes
  const sc = d.scores || {};
  const sa = (sc.a !== undefined) ? sc.a : (sc['1'] || 0);
  const sb = (sc.b !== undefined) ? sc.b : (sc['2'] || 0);
  $('result-a').textContent = d.yourTeam === 2 ? sb : sa;
  $('result-b').textContent = d.yourTeam === 2 ? sa : sb;

  const rp = $('result-rp');
  if (d.rp && d.ranked) {
    rp.classList.remove('hidden');
    if (d.rp.placement) {
      $('rp-rank').textContent = 'PLACEMENT MATCHES';
      $('rp-before').textContent = d.rp.played;
      $('rp-after').textContent = d.rp.total;
      $('rp-delta').textContent = `${d.rp.total - d.rp.played} REMAINING`;
      $('rp-delta').classList.remove('neg');
      $('rp-bar-fill').style.width = (d.rp.played / Math.max(1, d.rp.total)) * 100 + '%';
      $('rp-breakdown').innerHTML = '';
    } else {
      $('rp-rank').textContent = String((d.rank && d.rank.after) || '').toUpperCase();
      $('rp-rank').style.color = (d.rank && d.rank.color) || '';
      $('rp-before').textContent = num(d.rp.before);
      countUp($('rp-after'), d.rp.before, d.rp.after, 900);
      $('rp-delta').textContent = `${d.rp.delta > 0 ? '+' : ''}${d.rp.delta} RP`;
      $('rp-delta').classList.toggle('neg', d.rp.delta < 0);
      $('rp-bar-fill').style.width = ((d.rank && d.rank.progress && d.rank.progress.percent) || 0) + '%';
      const b = d.rp.breakdown || {};
      $('rp-breakdown').innerHTML = Object.keys(b).map((k) =>
        `<span>${k.toUpperCase()} ${b[k] > 0 ? '+' : ''}${b[k]}</span>`).join('');
    }
  } else rp.classList.add('hidden');

  const s = d.stats || {};
  $('result-stats').innerHTML = `
    <div><b>${s.kills || 0}</b><span>${esc(tx('KILLS'))}</span></div>
    <div><b>${s.deaths || 0}</b><span>${esc(tx('DEATHS'))}</span></div>
    <div><b>${s.assists || 0}</b><span>${esc(tx('ASSISTS'))}</span></div>
    <div><b>${s.headshots || 0}</b><span>${esc(tx('HEADSHOTS'))}</span></div>
    <div><b>${num(s.damage || 0)}</b><span>${esc(tx('DAMAGE'))}</span></div>`;

  // same row shape as the TAB scoreboard, so the two read as one thing
  const meId = S.boot && S.boot.player && S.boot.player.userId;
  const board = d.scoreboard || [];
  const rows = (t) => board
    .filter((p) => p.team === t)
    .sort((a, b) => (b.score || 0) - (a.score || 0))
    .map((p) => `
      <div class="rb-row${p.userId === meId ? ' me' : ''}">
        <span class="rb-who">${avatarCell(p, 'rb-av')}<b>${esc(p.name)}</b></span>
        <span class="rb-kda">${p.kills}/${p.deaths}/${p.assists}</span>
        <span class="rb-hs">${p.headshots} HS</span>
        <span class="rb-dmg">${num(p.damage)}</span>
        <span class="rb-score">${num(p.score)}</span>
      </div>`).join('');

  const teamName = (t) => (t === 1)
    ? ((d.teamA || (S.hud && S.hud.teamA)) || tx('TEAM A'))
    : ((d.teamB || (S.hud && S.hud.teamB)) || tx('TEAM B'));

  $('result-scoreboard').innerHTML = `
    <div class="rb-team a">${esc(teamName(1))}</div>${rows(1)}
    <div class="rb-team b">${esc(teamName(2))}</div>${rows(2)}`;

  Sfx.play(d.result === 'DEFEAT' ? 'defeat' : 'victory');
  setTimeout(() => { if (d.mvp) showMVP(d.mvp, () => maybeRankChange(d)); else maybeRankChange(d); }, 2600);
}

function maybeRankChange(d) {
  if (!d.rank || (!d.rank.up && !d.rank.down)) return;
  const modal = $('modal-rank');
  modal.classList.remove('hidden');
  $('rankup-root').classList.toggle('down', !!d.rank.down);
  $('rankup-tag').textContent = d.rank.up ? 'RANK UP' : 'RANK DOWN';
  $('rankup-name').textContent = String(d.rank.after || '').toUpperCase();
  $('rankup-sub').textContent = d.rank.up ? 'NEW RANK' : 'DEMOTED';
  $('rankup-crest').innerHTML = crest(tierOf(d.rank.id), d.rank.color);
  Sfx.play(d.rank.up ? 'rankup' : 'rankdown');
  setTimeout(() => modal.classList.add('hidden'), 5200);
}

function showMVP(mvp, done) {
  const modal = $('modal-mvp');
  modal.classList.remove('hidden');
  $('mvp-name').textContent = String(mvp.name || '').toUpperCase();
  $('mvp-kills').textContent = mvp.kills;
  $('mvp-deaths').textContent = mvp.deaths;
  $('mvp-hs').textContent = mvp.headshots;
  $('mvp-dmg').textContent = num(mvp.damage);
  Sfx.play('rankup');
  setTimeout(() => { modal.classList.add('hidden'); if (done) done(); }, 4600);
}

function countUp(node, from, to, duration) {
  const start = performance.now(), diff = to - from;
  const step = (now) => {
    const t = Math.min(1, (now - start) / duration);
    node.textContent = num(Math.round(from + diff * (1 - Math.pow(1 - t, 3))));
    if (t < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

/* ================================================================ TOASTS */
const TOAST_ICON = {
  info: '#i-ranked', success: '#i-check', warning: '#i-shield', error: '#i-x'
};

function toast(kind, message, title, ttl) {
  const k = kind || 'info';
  const life = ttl || 5200;
  // pinned notifications may read the other way round from the page
  const rtl = LOCALE.rtl[NOTIFY_LANG] === true;
  const node = el('div', 'toast ' + k + (rtl ? ' rtl' : ''), `
    <span class="tico"><svg><use href="${TOAST_ICON[k] || TOAST_ICON.info}"/></svg></span>
    ${title ? `<b>${esc(title)}</b>` : ''}
    <span>${esc(message)}</span>
    <i class="tbar" style="animation-duration:${life}ms"></i>`);
  $('toasts').appendChild(node);

  // fade out rather than vanish, and only then leave the column
  setTimeout(() => {
    if (!node.parentNode) return;
    node.classList.add('out');
    setTimeout(() => { if (node.parentNode) node.remove(); }, 200);
  }, life);

  if (k === 'error') Sfx.play('error');
  else if (k === 'warning') Sfx.play('warning');
  return node;
}

/* ============================================================ NUI EVENTS */
window.addEventListener('message', (e) => {
  const d = e.data || {};
  switch (d.action) {
    case 'open':
      if (!Object.keys(S.settings).length) loadSettings();
      if (d.theme) applyTheme(d.theme);
      if (d.brand) renderBrand(d.brand);
      // Locale.lua arrives with every open: it carries the string table, the
      // language list and which way the text reads.
      if (d.locale) {
        LOCALE = { strings: d.locale.strings || {}, rtl: d.locale.rtl || {} };
        NOTIFY_LANG = d.locale.notifyLanguage || d.locale.language || 'en';
        if (Array.isArray(d.locale.languages) && d.locale.languages.length) {
          LANGUAGES = d.locale.languages;
        }
        // Locale.default wins until the player pins a choice in Settings
        const lang = (S.langPinned && S.settings.language) || d.locale.language;
        S.settings.language = lang;
        applyLanguage(lang);
      }
      $('app').classList.remove('hidden');
      if (!d.silent) Sfx.play('open');
      showPage(d.page && $('pg-' + d.page) ? d.page : (S.page || 'ranked'));
      break;

    case 'close':
      $('app').classList.add('hidden');
      $('modal-invite').classList.add('hidden');
      closePrompt();
      Sfx.play('close');
      break;

    case 'boot':
      if (d.theme) applyTheme(d.theme);
      renderBoot(d.data);
      break;
    case 'toast': toast(d.kind, d.message, d.title); break;
    case 'queue': renderQueue(d.data); break;
    case 'matchFound': renderFound(d.data); break;
    case 'mapVote': renderMapVote(d.data); break;
    case 'party': renderParty(d.data); break;

    case 'custom':
      if (d.data && d.data.list) S.rooms = d.data.list;
      if (d.data && d.data.room !== undefined) {
        S.room = d.data.room || null;
        renderCustomParty(); renderCustomRoom(); updateSteps();
        $('btn-back').classList.toggle('hidden', !(S.page === 'custom' && S.room));
      }
      break;

    case 'data': {
      const p = d.data || {};
      if (p.what === 'leaderboard') renderBoard(p);
      else if (p.what === 'profile') { S.profile = p.profile; renderProfile(); }
      else if (p.what === 'history') renderHistory(p.rows, p.page);
      else if (p.what === 'matchDetail') renderMatchDetail(p.detail);
      else if (p.what === 'rewards') renderRewards(p);
      else if (p.what === 'store') renderStore(p.store);
      else if (p.what === 'admin') {
        if (p.action === 'dashboard') renderAdmin(p.result);
        else if (p.action === 'playerLookup') {
          S.profile = p.result;
          if (p.result) {
            S.admLookup = { name: p.result.name, rank: p.result.rank, rp: p.result.rp };
            S.admTargetValue = String(p.result.userId);
          }
          if (S.page === 'admin') renderAdmin(S.admin); else showPage('profile');
        }
        else { toast('success', tn('Action applied.'), tn('ADMIN')); post('admin', { action: 'dashboard' }); }
      }
      break;
    }

    case 'matchSetup': {
      S.matchInfo = d.data || null;
      const hint = S.matchInfo && S.matchInfo.scoreboardHint;
      $('sb-hint').textContent = hint ? `${tx('HOLD')} ${hint}` : '';
      $('sb-hint').style.display = hint ? '' : 'none';
      $('hud').classList.remove('hidden');
      $('killfeed').innerHTML = '';
      toggleScoreboard(false);
      renderPlayerCard();
      renderShowcase(S.matchInfo);
      break;
    }

    case 'locale': applyLocale(d.data); break;

    case 'scoreboard': toggleScoreboard(d.show === true); break;

    case 'damaged': {
      // a short red vignette, stronger for a heavier hit
      const n = $('dmg-flash');
      n.style.setProperty('opacity', '');
      n.classList.remove('on');
      void n.offsetWidth;
      n.style.opacity = Math.min(1, 0.35 + (d.amount || 0) / 60);
      n.classList.add('on');
      clearTimeout(S.dmgTimer);
      S.dmgTimer = setTimeout(() => { n.classList.remove('on'); n.style.opacity = ''; }, 110);
      break;
    }

    case 'surrender': {
      const n = $('surrender');
      const s = d.data || {};
      if (!s.active) { n.classList.add('hidden'); break; }

      const p = Math.max(0, Math.min(1, s.progress || 0));
      const total = s.seconds || 5;
      const left = Math.max(1, Math.ceil(total * (1 - p)));
      // the key first, then it counts down — the ring alone does not say how
      // much longer the key has to stay down
      $('sr-key').textContent = p > 0.04 ? String(left) : (s.key || 'X');
      $('sr-arc').style.strokeDashoffset = 276.5 * (1 - p);   // 2 * PI * 44
      n.classList.remove('hidden');
      break;
    }
    case 'hud': renderHud(d.data); break;
    case 'localHud': renderLocalHud(d.data); break;
    case 'killfeed': addKillFeed(d.data); break;
    case 'event': showEvent(d.data); break;
    case 'round': renderRound(d.data); break;
    case 'matchEnd': renderMatchEnd(d.data); break;

    case 'matchCleanup':
      // the result overlay goes with everything else: nothing survives the
      // match it belonged to
      ['hud', 'killfeed', 'phase', 'showcase', 'boundary', 'spectate', 'combat-banner',
       'modal-result', 'modal-mvp', 'surrender'].forEach((id) => {
        const n = $(id); if (n) n.classList.add('hidden');
      });
      hideShowcase();
      toggleScoreboard(false);
      $('killfeed').innerHTML = '';
      S.hud = null;
      S.matchInfo = null;
      break;

    case 'hudVisible':
      $('hud').classList.toggle('hidden', !d.value);
      if (!d.value) toggleScoreboard(false);   // never leave it stuck open
      break;

    case 'boundary': {
      const n = $('boundary');
      n.classList.toggle('hidden', !d.active);
      if (d.active) {
        $('boundary-count').textContent = d.seconds;
        $('boundary-dist').textContent = `${d.distance}m OUTSIDE THE ZONE`;
        if (d.seconds <= 3) Sfx.play('tick');
      }
      break;
    }

    case 'spectate': {
      const n = $('spectate');
      n.classList.toggle('hidden', !(d.data && d.data.active));
      if (d.data && d.data.active) {
        $('spectate-name').textContent = d.data.overview ? 'OVERVIEW CAMERA'
          : `${d.data.name} (${d.data.index || 1}/${d.data.total || 1})`;
      }
      break;
    }

    case 'training': {
      const n = $('training'), tr = d.data || {};
      const hint = $('train-prompt');

      // a press-again-to-confirm prompt from the exit key
      if (tr.confirm) {
        hint.classList.remove('hidden');
        hint.classList.add('confirm');
        $('train-prompt-text').textContent = 'PRESS AGAIN TO EXIT';
        clearTimeout(hint._t);
        hint._t = setTimeout(() => {
          hint.classList.remove('confirm');
          $('train-prompt-text').textContent =
            (S.training && S.training.exit && S.training.exit.text) || 'EXIT TRAINING';
        }, (tr.seconds || 2) * 1000);
        break;
      }

      n.classList.toggle('hidden', !tr.active);

      if (!tr.active) {
        S.training = null;
        hint.classList.add('hidden');
      } else {
        // periodic updates only carry counters, so merge instead of replacing
        S.training = Object.assign({ active: true }, S.training, tr);

        if (tr.label) $('training-title').textContent = tr.label;
        if (tr.exit) {
          hint.classList.remove('hidden');
          $('train-prompt-key').textContent = tr.exit.key || 'BACKSPACE';
          $('train-prompt-text').textContent = tr.exit.text || 'EXIT TRAINING';
        }
        if (tr.hits !== undefined) {
          $('training-hits').textContent = tr.hits;
          $('training-hs').textContent = tr.headshots;
          $('training-acc').textContent = tr.accuracy + '%';
          $('training-time').textContent = tr.elapsed + 's';
        }
      }

      if (S.page === 'training') renderTraining();
      break;
    }

    case 'death':
      if (d.data && d.data.killer) {
        toast('error', `${d.data.killer}${d.data.headshot ? ' · HEADSHOT' : ''}`, 'ELIMINATED', 3600);
      }
      break;

    case 'hitmarker': {
      const hm = $('hitmarker');
      hm.classList.remove('hidden');
      hm.classList.toggle('head', !!d.head);
      clearTimeout(hm._t);
      hm._t = setTimeout(() => hm.classList.add('hidden'), 150);
      break;
    }
  }
});

/* ============================================================== BINDINGS */
$('btn-start').onclick = () => { Sfx.play('click'); toggleQueue(); };
$('sd-cancel').onclick = () => post('queue', { action: 'leave' });
$('btn-accept').onclick = () => {
  if (!S.found) return;
  Sfx.play('accept');
  post('ready', { id: S.found.id, accept: true });
  $('found-waiting').classList.remove('hidden');
  document.querySelector('.found-actions').classList.add('hidden');
};
$('btn-decline').onclick = () => {
  if (S.found) { post('ready', { id: S.found.id, accept: false }); renderFound(null); }
};
$('prompt-ok').onclick = () => { const r = promptResolve; closePrompt(); if (r) r(true); };
$('prompt-cancel').onclick = () => { const r = promptResolve; closePrompt(); if (r) r(false); };
$('prompt-input').onkeydown = (e) => {
  if (e.key === 'Enter') { e.preventDefault(); $('prompt-ok').click(); }
  if (e.key === 'Escape') { e.preventDefault(); $('prompt-cancel').click(); }
};

$('cm-armor').onchange = (e) => { S.cm.armor = e.target.checked; };
$('cm-hsonly').onchange = (e) => { S.cm.hsOnly = e.target.checked; };

document.addEventListener('click', (e) => {
  const tab = e.target.closest('.ft .tab[data-page], .hd-actions [data-page]');
  if (tab) { Sfx.play('click'); showPage(tab.dataset.page); return; }

  const step = e.target.closest('[data-step]');
  if (step) {
    const parts = step.dataset.step.split(':');
    const what = parts[0], delta = parseInt(parts[1], 10);
    Sfx.play('click');
    if (what === 'mode') {
      const modes = (S.boot && S.boot.allModes) || [];
      if (modes.length) {
        const i = Math.max(0, modes.findIndex((m) => m.id === S.cm.mode));
        const next = modes[(i + delta + modes.length) % modes.length];
        if (next) { S.cm.mode = next.id; S.cm.mapPage = 1; }
      }
    } else if (what === 'rounds') {
      const lim = (S.boot && S.boot.customLimits && S.boot.customLimits.rounds) || { min: 1, max: 31 };
      S.cm.rounds = Math.max(lim.min, Math.min(lim.max, S.cm.rounds + delta));
    }
    renderCustom();
    return;
  }

  const room = e.target.closest('[data-room]');
  if (room) {
    const a = room.dataset.room;
    Sfx.play('click');
    if (a === 'start') post('custom', { action: 'start' });
    else if (a === 'lock') post('custom', { action: 'lock', value: !(S.room && S.room.locked) });
    else if (a === 'apply') post('custom', { action: 'settings', settings: customPayload() });
    else if (a === 'kick') post('custom', { action: 'kick', userId: parseInt(room.dataset.user, 10) });
    else if (a === 'move') post('custom', { action: 'move', userId: parseInt(room.dataset.user, 10), team: parseInt(room.dataset.team, 10) });
    return;
  }

  const act = e.target.closest('[data-action]');
  if (!act) return;
  const a = act.dataset.action;
  Sfx.play('click');

  switch (a) {
    case 'close': post('close'); break;
    case 'back':
      S.room = null; renderCustomRoom(); renderCustomParty(); updateSteps();
      $('btn-back').classList.add('hidden');
      break;

    case 'invite-cancel': $('modal-invite').classList.add('hidden'); break;
    case 'invite-send': sendInvite(); break;

    case 'cm-all': {
      const all = ((S.boot && S.boot.weaponPresets) || []).map((w) => w.id);
      S.cm.weapons = (S.cm.weapons.length === all.length) ? all.slice(0, 1) : all;
      renderCustomWeapons();
      break;
    }
    case 'cm-invite': {
      const v = $('cm-invite').value.trim();
      if (v) { post('party', { action: 'invite', target: v }); $('cm-invite').value = ''; }
      break;
    }
    case 'cm-copy':
      if (S.room && S.room.code) {
        try { navigator.clipboard.writeText(S.room.code); } catch (err) {}
        toast('success', `Code ${S.room.code} copied`, 'ROOM CODE');
      }
      break;
    case 'cm-chat': toast('info', tn('Share the room code with your friends.'), tn('ROOM CODE')); break;
    case 'cm-create': post('custom', Object.assign({ action: 'create' }, customPayload())); break;
    case 'cm-leave': post('custom', { action: 'leave' }); break;
    case 'cm-joincode':
      askInput('JOIN CODE', 'Enter the room code', (code) => {
        if (!code) { toast('warning', tn('Enter the room code'), tn('ROOM CODE')); return; }
        post('custom', { action: 'joinCode', code: code.toUpperCase() });
      });
      break;

    case 'lb-prev': if (S.lb.page > 1) { S.lb.page -= 1; fetchBoard(); } break;
    case 'lb-next': S.lb.page += 1; fetchBoard(); break;
    case 'hist-prev':
      if (S.hist.page > 1) { S.hist.page -= 1; post('fetch', { what: 'history', page: S.hist.page }); }
      break;
    case 'hist-next': S.hist.page += 1; post('fetch', { what: 'history', page: S.hist.page }); break;
    case 'detail-close': $('matchdetail').classList.add('hidden'); break;
    case 'result-close': $('modal-result').classList.add('hidden'); post('close'); break;
    case 'settings-reset': S.settings = Object.assign({}, DEFAULTS); saveSettings(); renderSettings(); break;
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    if (!$('modal-prompt').classList.contains('hidden')) {
      const r = promptResolve; closePrompt(); if (r) r(false);
      return;
    }
    if (!$('modal-invite').classList.contains('hidden')) { $('modal-invite').classList.add('hidden'); return; }
    if (!$('modal-result').classList.contains('hidden')) $('modal-result').classList.add('hidden');
    post('close');
  }
  if (e.key === 'Enter') {
    if (!$('modal-prompt').classList.contains('hidden')) return;   // handled by the dialog
    if (!$('modal-invite').classList.contains('hidden')) { sendInvite(); return; }
    if (S.found) $('btn-accept').click();
  }
}, true);

document.addEventListener('click', (e) => {
  const tab = e.target.closest('.stab');
  if (!tab) return;
  S.storeTab = tab.dataset.stab;
  Sfx.play('click');
  renderStore();
});

document.addEventListener('mouseover', (e) => {
  if (e.target.closest('.btn,.tab,.mtab,.chip,.pill,.mini,.slot')) Sfx.play('hover');
}, { passive: true });

/* One shared 1 Hz timer drives every countdown on screen. */
setInterval(() => {
  if (S.hudTime > 0) { S.hudTime -= 1; updateTimer(); }
  if (S.queue.searching) { S.queue.elapsed += 1; $('sd-time').textContent = clock(S.queue.elapsed); }
}, 1000);

loadSettings();
