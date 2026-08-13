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
  settings: {},
  page: 'ranked',

  mode: '1v1',
  queue: { searching: false, elapsed: 0 },
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

  hud: null, hudTime: 0,
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
function mapArt(id, forced) {
  let h = 0;
  const str = String(id);
  for (let i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) % 360;
  const hue = forced !== undefined ? forced : h;
  return `background:linear-gradient(155deg,hsl(${hue} 26% 20%),hsl(${(hue + 42) % 360} 32% 9%))`;
}
function tierOf(rankId) {
  const r = ((S.boot && S.boot.ranks) || []).find((x) => x.id === rankId);
  return r ? r.tier : 'UNRANKED';
}
function tierColor(rankId) {
  const r = ((S.boot && S.boot.ranks) || []).find((x) => x.id === rankId);
  return r ? r.color : '#5A616D';
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
const PAGE_TITLES = {
  ranked: 'MATCHMAKING', leaderboard: 'MATCHMAKING', custom: 'MATCHMAKING',
  profile: 'PROFILE', history: 'MATCH HISTORY', rewards: 'REWARDS',
  training: 'TRAINING', settings: 'SETTINGS', admin: 'ADMIN CONTROL'
};

function showPage(page) {
  S.page = page;
  document.querySelectorAll('.pg').forEach((p) => p.classList.remove('active'));
  const target = $('pg-' + page);
  if (target) target.classList.add('active');
  document.querySelectorAll('.ft .tab').forEach((b) => b.classList.toggle('active', b.dataset.page === page));

  document.querySelector('.hd-title').textContent = PAGE_TITLES[page] || 'MATCHMAKING';
  $('btn-start').classList.toggle('hidden', page !== 'ranked');
  $('btn-back').classList.toggle('hidden', !(page === 'custom' && S.room));

  if (page === 'leaderboard') fetchBoard();
  if (page === 'history') post('fetch', { what: 'history', page: S.hist.page });
  if (page === 'profile') post('fetch', { what: 'profile' });
  if (page === 'rewards') post('fetch', { what: 'rewards' });
  if (page === 'custom') { post('custom', { action: 'list' }); renderCustom(); }
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

  renderModeTabs();
  renderSlots();
  renderCustom();
}

/* ============================================================ RANKED PAGE */
function renderModeTabs() {
  const modes = (S.boot && S.boot.modes) || [];
  const build = (host, current, onPick) => {
    host.innerHTML = '';
    modes.forEach((m) => {
      const b = el('button', 'mtab' + (m.id === current ? ' active' : ''), esc(m.label));
      b.onclick = () => { Sfx.play('click'); onPick(m.id); };
      host.appendChild(b);
    });
  };
  build($('mode-tabs'), S.mode, (id) => { S.mode = id; renderModeTabs(); renderSlots(); });
  build($('lb-tabs'), S.lb.mode, (id) => { S.lb.mode = id; S.lb.page = 1; renderModeTabs(); fetchBoard(); });
}

/** The party slots. Slot 1 is always you, the rest fill from the party. */
function renderSlots() {
  const host = $('party-slots');
  const p = S.boot && S.boot.player;
  const max = (S.boot && S.boot.maxParty) || 5;
  const modeCfg = ((S.boot && S.boot.modes) || []).find((m) => m.id === S.mode);
  const capacity = Math.min(max, modeCfg ? modeCfg.teamSize : max);

  const members = (S.party && S.party.members && S.party.members.length)
    ? S.party.members
    : (p ? [{ userId: p.userId, name: p.name, rank: p.rank, rankId: p.rankId, rp: p.rp, leader: true, ready: true }] : []);

  const meId = p && p.userId;
  const iAmLeader = !S.party || S.party.leader === meId;

  host.innerHTML = '';
  for (let i = 0; i < max; i++) {
    const m = members[i];

    if (!m) {
      const slot = el('div', 'slot empty', '<svg><use href="#i-plus"/></svg>');
      if (i < capacity && iAmLeader) slot.onclick = () => openInvite();
      else slot.style.opacity = '.4';
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
        <div class="slot-ready ${m.ready ? 'on' : ''}">${m.ready ? 'READY' : 'NOT READY'}</div>
      </div>
      <div class="slot-foot">
        <div class="slot-crest">${crest(tier, color)}</div>
        <div class="slot-track"><i style="width:${pct}%"></i></div>
        <div class="slot-nums">
          <span>${num(lo)}</span>
          <span class="slot-rank">${esc(m.rank || 'Unranked')} (${esc((modeCfg && modeCfg.label) || S.mode)})</span>
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
  setTimeout(() => input.focus(), 40);
}

function toggleQueue() {
  if (S.queue.searching) { post('queue', { action: 'leave' }); return; }
  Sfx.play('queue');
  post('queue', { action: 'join', mode: S.mode });
}

function renderQueue(q) {
  const searching = !!(q && q.state === 'SEARCHING');
  S.queue.searching = searching;

  const start = $('btn-start');
  start.classList.toggle('searching', searching);
  start.innerHTML = searching ? '<svg><use href="#i-x"/></svg>CANCEL'
                              : '<svg><use href="#i-play"/></svg>START';

  $('searchdock').classList.toggle('hidden', !searching);
  if (!searching) { S.queue.elapsed = 0; return; }

  if (q.elapsed !== undefined) S.queue.elapsed = q.elapsed;
  const modeCfg = ((S.boot && S.boot.modes) || []).find((m) => m.id === (q.mode || S.mode));
  $('sd-mode').textContent = (modeCfg && modeCfg.label) || String(q.mode || S.mode).toUpperCase();
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
  $('found-waiting').classList.toggle('hidden', !mine);
  document.querySelector('.found-actions').classList.toggle('hidden', mine);

  if (first) {
    Sfx.play('found');
    let left = d.timeout || 15;
    const total = left;
    const ring = $('found-ring');
    const circ = 2 * Math.PI * 52;
    ring.style.strokeDasharray = circ;
    const tick = () => {
      $('found-timer').textContent = Math.max(0, left);
      ring.style.strokeDashoffset = circ * (1 - left / total);
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
      const card = el('div', 'mv-card', `
        <div class="mv-art" style="${mapArt(m.id, (i * 47 + 200) % 360)}"></div>
        <div class="mv-votes" data-map="${esc(m.id)}">0</div>
        <div class="mv-name">${esc(m.name)}</div>`);
      card.onclick = () => {
        document.querySelectorAll('.mv-card').forEach((c) => c.classList.remove('picked'));
        card.classList.add('picked');
        Sfx.play('click');
        post('mapVote', { mapId: m.id });
        $('mv-foot').textContent = `YOU VOTED FOR ${String(m.name).toUpperCase()}`;
      };
      grid.appendChild(card);
    });

    let left = d.duration || 20;
    $('mv-timer').textContent = left;
    if (S.mapvoteTimer) clearInterval(S.mapvoteTimer);
    S.mapvoteTimer = setInterval(() => {
      left -= 1; $('mv-timer').textContent = Math.max(0, left);
      if (left <= 0) { clearInterval(S.mapvoteTimer); S.mapvoteTimer = null; }
    }, 1000);
  }

  if (d.votes) {
    Object.keys(d.votes).forEach((id) => {
      const n = document.querySelector(`.mv-votes[data-map="${id}"]`);
      if (n) n.textContent = d.votes[id];
    });
  }
}

/* ================================================================== PARTY */
function renderParty(d) {
  if (!d) return;

  if (d.invite) {
    const t = toast('info', `${d.invite.from} invited you to a party`, 'PARTY INVITE', 12000);
    const row = el('div');
    row.style.cssText = 'display:flex;gap:6px;margin-top:8px';
    const a = el('button', 'btn', 'ACCEPT'); a.style.cssText = 'padding:6px 14px;font-size:10px';
    const r = el('button', 'btn ghost', 'DECLINE'); r.style.cssText = 'padding:6px 14px;font-size:10px';
    a.onclick = () => { post('party', { action: 'accept' }); t.remove(); };
    r.onclick = () => { post('party', { action: 'decline' }); t.remove(); };
    row.appendChild(a); row.appendChild(r);
    t.appendChild(row);
    return;
  }

  S.party = d.id ? d : null;
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
  $('lb-page').textContent = `PAGE ${d.page || 1}`;
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
    `<div class="lb-stat"><label>${l}</label><b>${esc(v)}</b></div>`).join('');

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
  $('hist-page').textContent = `PAGE ${page || 1}`;
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
    { kind: 'aim', label: 'AIM TRAINING', desc: 'Static targets at mixed ranges. Warm up tracking and flicks.' },
    { kind: 'headshot', label: 'HEADSHOT TRAINING', desc: 'Long range targets. One clean head hit is always lethal — practise it.' },
    { kind: 'range', label: 'FREE RANGE', desc: 'Open range with a full loadout. No targets, no timer.' }
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
       <button class="btn">${active ? 'SWITCH' : 'ENTER'}</button>`);
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
  { key: 'language', label: 'LANGUAGE', type: 'select', options: ['en', 'ar'] },
  { key: 'teamColorA', label: 'TEAM A COLOUR', type: 'color' },
  { key: 'teamColorB', label: 'TEAM B COLOUR', type: 'color' }
];

function renderSettings() {
  const host = $('settings-root');
  const rows = SETTING_DEFS.map((d) => {
    const v = S.settings[d.key];
    if (d.type === 'range') return `<div class="srow"><label>${d.label}</label>
      <div style="display:flex;align-items:center;gap:10px">
        <input type="range" min="${d.min}" max="${d.max}" value="${v}" data-set="${d.key}"/>
        <span class="val" data-val="${d.key}">${v}</span></div></div>`;
    if (d.type === 'bool') return `<div class="srow"><label>${d.label}</label>
      <label class="sw"><input type="checkbox" data-set="${d.key}" ${v ? 'checked' : ''}/><i></i></label></div>`;
    if (d.type === 'select') return `<div class="srow"><label>${d.label}</label>
      <select class="sel" data-set="${d.key}">${d.options.map((o) =>
        `<option value="${o}" ${o === v ? 'selected' : ''}>${o.toUpperCase()}</option>`).join('')}</select></div>`;
    return `<div class="srow"><label>${d.label}</label>
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

function applyTheme(theme) {
  if (!theme) return;
  S.theme = theme;
  const root = document.documentElement;

  if (theme.colors) {
    Object.keys(COLOR_VARS).forEach((key) => {
      const value = theme.colors[key];
      if (value) root.style.setProperty(COLOR_VARS[key], value);
    });
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
  S.settings = Object.assign({}, DEFAULTS, stored);
  applySettings();
}
function saveSettings() {
  try { localStorage.setItem('m5rp_settings', JSON.stringify(S.settings)); } catch (e) {}
  applySettings();
  post('settings', { settings: S.settings });
}
function applySettings() {
  const r = document.documentElement;
  if (S.settings.teamColorA) r.style.setProperty('--team-a', S.settings.teamColorA);
  if (S.settings.teamColorB) r.style.setProperty('--team-b', S.settings.teamColorB);
  $('killfeed').classList.toggle('left', S.settings.killFeedPos === 'left');
  $('hud').style.transform = `scale(${(S.settings.hudSize || 100) / 100})`;
  $('hud-ping').style.display = S.settings.showPing === false ? 'none' : '';
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

/** Shared target box: one player id/name feeds every player tool. */
function admTarget() {
  return ($('adm-target') && $('adm-target').value.trim()) || '';
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
  if (def.confirm && !confirm(`${def.label || action}\n\nConfirm this action?`)) return;

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
      `<svg><use href="${g.icon}"/></svg>${g.label}`);
    b.onclick = () => { S.admTab = g.id; Sfx.play('click'); renderAdmin(S.admin); };
    host.appendChild(b);
  });

  const refresh = el('button', 'adm-tab', '<svg><use href="#i-back"/></svg>REFRESH');
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
      <div><span class="lbl">TARGET PLAYER</span>
        <input class="inp" id="adm-target" placeholder="ID or name" value="${esc(S.admTargetValue || '')}"/></div>
      <div><span class="lbl">REASON</span>
        <input class="inp" id="adm-reason" placeholder="Required for most actions"/></div>
      <div><span class="lbl">STATUS</span>
        <div class="who ${S.admLookup ? 'on' : ''}" id="adm-who">
          <span class="dot"></span>
          ${S.admLookup
            ? `<b>${esc(S.admLookup.name)}</b> · ${esc(S.admLookup.rank)} · ${num(S.admLookup.rp)} RP`
            : 'no player loaded'}
          <button class="mini" data-adm="lookupInput" style="margin-left:6px">LOAD</button>
        </div></div>
    </div>`;

  /* one action row: name, fields, single button */
  const act = (action, opts) => {
    if (!admCan(action)) return '';
    const def = admDef(action);
    const o = opts || {};
    return `<div class="act ${o.danger ? 'danger' : ''}">
      <div class="act-name"><b>${esc(def.label || action)}</b><span>${esc(def.permission || action)}</span></div>
      <div class="${o.fields ? 'act-fields' : 'act-hint'}">${o.fields || o.hint || ''}</div>
      <button class="btn ${o.danger ? '' : 'ghost'}" data-adm="${esc(o.run || action)}">${esc(o.button || 'APPLY')}</button>
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

  const t = $('adm-target');
  if (t) t.oninput = () => { S.admTargetValue = t.value; };

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
      if (!target) { toast('warning', 'Enter a player id or name first.', 'ADMIN'); break; }
      post('admin', { action: 'playerLookup', target });
      break;

    case 'kickFromMatch': admRun('kickFromMatch', { target }); break;
    case 'movePlayer':    admRun('movePlayer', { target, matchId: val('adm-match'), team: parseInt(val('adm-team'), 10) }); break;
    case 'freezeOn':      admRun('freeze', { value: true }); break;
    case 'freezeOff':     admRun('freeze', { value: false }); break;

    case 'addRP':         admRun('addRP', { target, amount: parseInt(val('adm-rp-add'), 10) }); break;
    case 'removeRP':      admRun('removeRP', { target, amount: parseInt(val('adm-rp-rem'), 10) }); break;
    case 'setRP':         admRun('setRP', { target, value: parseInt(val('adm-rp-set'), 10) }); break;
    case 'setRank':       admRun('setRank', { target, rankId: parseInt(val('adm-rank'), 10) }); break;
    case 'addXP':         admRun('addXP', { target, amount: parseInt(val('adm-xp'), 10) }); break;
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
function renderHud(d) {
  if (!d) return;
  S.hud = d;
  $('hud-score-a').textContent = d.scores.a;
  $('hud-score-b').textContent = d.scores.b;
  $('hud-alive-a').textContent = d.aliveA;
  $('hud-alive-b').textContent = d.aliveB;
  $('hud-round').textContent = d.ffa ? 'FREE FOR ALL'
    : (d.overtime ? `OVERTIME · ROUND ${d.round}` : `ROUND ${d.round}`);
  $('hud-ping').textContent = `${d.ping || 0} ms`;
  S.hudTime = d.time || 0;
  updateTimer();
}
function updateTimer() {
  const n = $('hud-timer');
  n.textContent = clock(S.hudTime);
  n.classList.toggle('low', S.hudTime <= 15 && S.hudTime > 0);
}
function renderLocalHud(d) {
  if (!d) return;
  const hp = Math.max(0, Math.min(100, d.health));
  $('hud-hp').textContent = hp; $('hud-hp-bar').style.width = hp + '%';
  $('hud-ar').textContent = d.armor; $('hud-ar-bar').style.width = Math.max(0, Math.min(100, d.armor)) + '%';
  $('hud-weapon-name').textContent = String(d.weapon || '').replace('WEAPON_', '');
  $('hud-clip').textContent = d.clip; $('hud-ammo').textContent = d.ammo;
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

function renderRound(d) {
  if (!d) return;
  const phase = $('phase');
  if (d.phase === 'countdown') {
    let n = d.seconds || 3;
    phase.classList.remove('hidden');
    $('phase-label').textContent = `ROUND ${d.round}`;
    const step = () => {
      const node = $('phase-count');
      if (n > 0) { node.textContent = n; node.classList.remove('go'); Sfx.play('tick'); }
      else {
        node.textContent = 'GO'; node.classList.add('go'); Sfx.play('go');
        setTimeout(() => phase.classList.add('hidden'), 900);
        clearInterval(renderRound._t);
      }
      n -= 1;
    };
    clearInterval(renderRound._t); step();
    renderRound._t = setInterval(step, 1000);

  } else if (d.phase === 'end') {
    phase.classList.remove('hidden');
    const won = d.winner === d.myTeam;
    const node = $('phase-count');
    node.textContent = d.winner === 0 ? 'DRAW' : (won ? 'ROUND WON' : 'ROUND LOST');
    node.style.fontSize = '54px';
    node.classList.toggle('go', won);
    $('phase-label').textContent = `${d.scores.a} — ${d.scores.b}`;
    Sfx.play(won ? 'roundwin' : 'roundloss');
    setTimeout(() => { phase.classList.add('hidden'); node.style.fontSize = ''; }, 4200);

  } else if (d.phase === 'live') {
    phase.classList.add('hidden');
  }
}

function renderMatchEnd(d) {
  if (!d) return;
  const modal = $('modal-result'), root = $('result-root');
  modal.classList.remove('hidden');
  root.classList.toggle('defeat', d.result === 'DEFEAT');
  root.classList.toggle('draw', d.result === 'DRAW');

  $('result-tag').textContent = d.result;
  $('result-a').textContent = d.yourTeam === 2 ? d.scores.b : d.scores.a;
  $('result-b').textContent = d.yourTeam === 2 ? d.scores.a : d.scores.b;

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
    <div><b>${s.kills || 0}</b><span>KILLS</span></div>
    <div><b>${s.deaths || 0}</b><span>DEATHS</span></div>
    <div><b>${s.assists || 0}</b><span>ASSISTS</span></div>
    <div><b>${s.headshots || 0}</b><span>HEADSHOTS</span></div>
    <div><b>${num(s.damage || 0)}</b><span>DAMAGE</span></div>`;

  const board = d.scoreboard || [];
  const rows = (t) => board.filter((p) => p.team === t).map((p) => `
    <div class="arow"><b>${esc(p.name)}</b>
      <span class="grow">${p.kills}/${p.deaths}/${p.assists} · ${p.headshots} HS · ${num(p.damage)} DMG</span>
      <span>${p.score}</span></div>`).join('');
  $('result-scoreboard').innerHTML = `
    <div class="card-tag" style="color:var(--team-a)">TEAM A</div>${rows(1)}
    <div class="card-tag" style="color:var(--team-b);margin-top:10px">TEAM B</div>${rows(2)}`;

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
function toast(kind, message, title, ttl) {
  const node = el('div', 'toast ' + (kind || 'info'),
    `${title ? `<b>${esc(title)}</b>` : ''}<span>${esc(message)}</span>`);
  $('toasts').appendChild(node);
  setTimeout(() => { if (node.parentNode) node.remove(); }, ttl || 5200);
  if (kind === 'error') Sfx.play('error');
  else if (kind === 'warning') Sfx.play('warning');
  return node;
}

/* ============================================================ NUI EVENTS */
window.addEventListener('message', (e) => {
  const d = e.data || {};
  switch (d.action) {
    case 'open':
      if (!Object.keys(S.settings).length) loadSettings();
      if (d.theme) applyTheme(d.theme);
      $('app').classList.remove('hidden');
      if (!d.silent) Sfx.play('open');
      showPage(d.page && $('pg-' + d.page) ? d.page : (S.page || 'ranked'));
      break;

    case 'close':
      $('app').classList.add('hidden');
      $('modal-invite').classList.add('hidden');
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
        else { toast('success', 'Action applied.', 'ADMIN'); post('admin', { action: 'dashboard' }); }
      }
      break;
    }

    case 'matchSetup': $('hud').classList.remove('hidden'); $('killfeed').innerHTML = ''; break;
    case 'hud': renderHud(d.data); break;
    case 'localHud': renderLocalHud(d.data); break;
    case 'killfeed': addKillFeed(d.data); break;
    case 'event': showEvent(d.data); break;
    case 'round': renderRound(d.data); break;
    case 'matchEnd': renderMatchEnd(d.data); break;

    case 'matchCleanup':
      ['hud', 'killfeed', 'phase', 'boundary', 'spectate', 'combat-banner'].forEach((id) => {
        const n = $(id); if (n) n.classList.add('hidden');
      });
      $('killfeed').innerHTML = '';
      S.hud = null;
      break;

    case 'hudVisible': $('hud').classList.toggle('hidden', !d.value); break;

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
      const n = $('training'), t = d.data || {};
      const hint = $('train-prompt');

      // a press-again-to-confirm prompt from the exit key
      if (t.confirm) {
        hint.classList.remove('hidden');
        hint.classList.add('confirm');
        $('train-prompt-text').textContent = 'PRESS AGAIN TO EXIT';
        clearTimeout(hint._t);
        hint._t = setTimeout(() => {
          hint.classList.remove('confirm');
          $('train-prompt-text').textContent =
            (S.training && S.training.exit && S.training.exit.text) || 'EXIT TRAINING';
        }, (t.seconds || 2) * 1000);
        break;
      }

      n.classList.toggle('hidden', !t.active);

      if (!t.active) {
        S.training = null;
        hint.classList.add('hidden');
      } else {
        // periodic updates only carry counters, so merge instead of replacing
        S.training = Object.assign({ active: true }, S.training, t);

        if (t.label) $('training-title').textContent = t.label;
        if (t.exit) {
          hint.classList.remove('hidden');
          $('train-prompt-key').textContent = t.exit.key || 'BACKSPACE';
          $('train-prompt-text').textContent = t.exit.text || 'EXIT TRAINING';
        }
        if (t.hits !== undefined) {
          $('training-hits').textContent = t.hits;
          $('training-hs').textContent = t.headshots;
          $('training-acc').textContent = t.accuracy + '%';
          $('training-time').textContent = t.elapsed + 's';
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
$('cm-armor').onchange = (e) => { S.cm.armor = e.target.checked; };
$('cm-hsonly').onchange = (e) => { S.cm.hsOnly = e.target.checked; };

document.addEventListener('click', (e) => {
  const tab = e.target.closest('.ft .tab[data-page]');
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
    case 'invite-send': {
      const v = $('invite-id').value.trim();
      if (v) post('party', { action: 'invite', target: v });
      $('modal-invite').classList.add('hidden');
      break;
    }

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
    case 'cm-chat': toast('info', 'Share the room code with your friends.', 'ROOM CODE'); break;
    case 'cm-create': post('custom', Object.assign({ action: 'create' }, customPayload())); break;
    case 'cm-leave': post('custom', { action: 'leave' }); break;
    case 'cm-joincode': {
      const code = (prompt('Room code:') || '').trim();
      if (code) post('custom', { action: 'joinCode', code });
      break;
    }

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
    if (!$('modal-invite').classList.contains('hidden')) { $('modal-invite').classList.add('hidden'); return; }
    if (!$('modal-result').classList.contains('hidden')) $('modal-result').classList.add('hidden');
    post('close');
  }
  if (e.key === 'Enter') {
    if (!$('modal-invite').classList.contains('hidden')) {
      const v = $('invite-id').value.trim();
      if (v) post('party', { action: 'invite', target: v });
      $('modal-invite').classList.add('hidden');
      return;
    }
    if (S.found) $('btn-accept').click();
  }
}, true);

document.addEventListener('mouseover', (e) => {
  if (e.target.closest('.btn,.tab,.mtab,.chip,.pill,.mini,.slot')) Sfx.play('hover');
}, { passive: true });

/* One shared 1 Hz timer drives every countdown on screen. */
setInterval(() => {
  if (S.hudTime > 0) { S.hudTime -= 1; updateTimer(); }
  if (S.queue.searching) { S.queue.elapsed += 1; $('sd-time').textContent = clock(S.queue.elapsed); }
}, 1000);

loadSettings();
