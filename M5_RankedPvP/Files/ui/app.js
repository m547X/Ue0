/* ==========================================================================
   M5 Ranked PvP — NUI controller

   Design rules followed here:
     · No full DOM rebuilds. Every list has its own render function and is only
       touched when its data actually changes.
     · No animation loops. Timers are plain setInterval at 1 Hz for countdowns
       and everything else is CSS driven.
     · All NUI traffic is event based; nothing polls the client.
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
const clock = (s) => {
  s = Math.max(0, Math.floor(s || 0));
  return `${Math.floor(s / 60)}:${pad(s % 60)}`;
};
const clockLong = (s) => {
  s = Math.max(0, Math.floor(s || 0));
  return `${pad(Math.floor(s / 60))}:${pad(s % 60)}`;
};
const num = (n) => (n || 0).toLocaleString('en-US');

function post(name, data) {
  return fetch(`https://${RES}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {})
  }).catch(() => {});
}

/* ---------------------------------------------------------------- defaults */
const DEFAULTS = {
  uiVolume: 55, musicVolume: 25, killSounds: true, hudSize: 100,
  killFeedPos: 'right', showPing: true, showMinimap: false,
  teamColorA: '#2ED9C3', teamColorB: '#FF4757', spectatorAuto: true,
  language: 'en', visualEffects: true, lowSpecMode: false
};

/* ------------------------------------------------------------------ state */
const S = {
  defaults: DEFAULTS,
  boot: null,
  theme: null,
  text: {},
  settings: {},
  page: 'dashboard',

  queue: { state: 'IDLE', mode: null, elapsed: 0, eta: 0, count: 0 },
  found: null,
  foundTimer: null,
  mapvote: null,
  mapvoteTimer: null,

  lb: { board: 'global', page: 1, rows: [] },
  hist: { page: 1, rows: [] },
  profile: null,
  rewards: null,
  admin: null,
  party: null,
  rooms: [],
  room: null,

  match: null,
  hud: null,
  killfeed: [],
  tickTimer: null,
  hudTime: 0,
  boundaryTimer: null
};

/* ------------------------------------------------------------------ audio */
const Audio_ = (() => {
  let ctx = null;
  const volume = () => (S.settings.uiVolume !== undefined ? S.settings.uiVolume : 55) / 100;

  const TONES = {
    click:    [{ f: 620, d: 0.05, t: 'square', g: 0.05 }],
    hover:    [{ f: 380, d: 0.03, t: 'sine',   g: 0.02 }],
    open:     [{ f: 300, d: 0.09, t: 'sawtooth', g: 0.05 }, { f: 620, d: 0.12, t: 'sine', g: 0.05, at: 0.06 }],
    close:    [{ f: 480, d: 0.08, t: 'sine', g: 0.04 }, { f: 240, d: 0.1, t: 'sine', g: 0.04, at: 0.05 }],
    queue:    [{ f: 440, d: 0.1, t: 'sine', g: 0.05 }, { f: 660, d: 0.14, t: 'sine', g: 0.05, at: 0.08 }],
    found:    [{ f: 520, d: 0.14, t: 'square', g: 0.07 }, { f: 780, d: 0.2, t: 'square', g: 0.07, at: 0.12 },
               { f: 1040, d: 0.26, t: 'sine', g: 0.06, at: 0.26 }],
    accept:   [{ f: 720, d: 0.1, t: 'sine', g: 0.06 }, { f: 980, d: 0.16, t: 'sine', g: 0.05, at: 0.07 }],
    tick:     [{ f: 900, d: 0.04, t: 'square', g: 0.05 }],
    go:       [{ f: 1200, d: 0.22, t: 'sawtooth', g: 0.07 }],
    roundwin: [{ f: 660, d: 0.12, t: 'sine', g: 0.06 }, { f: 990, d: 0.18, t: 'sine', g: 0.05, at: 0.1 }],
    roundloss:[{ f: 330, d: 0.16, t: 'sine', g: 0.05 }, { f: 220, d: 0.2, t: 'sine', g: 0.05, at: 0.1 }],
    kill:     [{ f: 1100, d: 0.05, t: 'square', g: 0.05 }],
    headshot: [{ f: 1400, d: 0.05, t: 'square', g: 0.06 }, { f: 1800, d: 0.06, t: 'square', g: 0.05, at: 0.04 }],
    victory:  [{ f: 523, d: 0.18, t: 'sine', g: 0.07 }, { f: 659, d: 0.18, t: 'sine', g: 0.07, at: 0.16 },
               { f: 784, d: 0.34, t: 'sine', g: 0.07, at: 0.32 }],
    defeat:   [{ f: 392, d: 0.24, t: 'sine', g: 0.06 }, { f: 311, d: 0.34, t: 'sine', g: 0.06, at: 0.22 }],
    rankup:   [{ f: 523, d: 0.14, t: 'square', g: 0.06 }, { f: 698, d: 0.14, t: 'square', g: 0.06, at: 0.13 },
               { f: 880, d: 0.3, t: 'sine', g: 0.07, at: 0.26 }],
    rankdown: [{ f: 440, d: 0.2, t: 'sine', g: 0.05 }, { f: 294, d: 0.3, t: 'sine', g: 0.05, at: 0.18 }],
    error:    [{ f: 200, d: 0.16, t: 'square', g: 0.05 }],
    warning:  [{ f: 660, d: 0.09, t: 'square', g: 0.05 }, { f: 660, d: 0.09, t: 'square', g: 0.05, at: 0.14 }]
  };

  function play(key) {
    const spec = TONES[key];
    if (!spec) return;
    const v = volume();
    if (v <= 0) return;
    try {
      if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
      const now = ctx.currentTime;
      spec.forEach((s) => {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = s.t;
        osc.frequency.setValueAtTime(s.f, now + (s.at || 0));
        gain.gain.setValueAtTime(0, now + (s.at || 0));
        gain.gain.linearRampToValueAtTime(s.g * v, now + (s.at || 0) + 0.012);
        gain.gain.exponentialRampToValueAtTime(0.0001, now + (s.at || 0) + s.d);
        osc.connect(gain).connect(ctx.destination);
        osc.start(now + (s.at || 0));
        osc.stop(now + (s.at || 0) + s.d + 0.02);
      });
    } catch (e) { /* audio unavailable, silently ignore */ }
  }
  return { play };
})();

/* ------------------------------------------------------------- rank crest */
function crest(tier, color, size) {
  const c = color || '#5A616D';
  const chevrons = { IRON: 1, BRONZE: 1, SILVER: 2, GOLD: 2, PLATINUM: 3, DIAMOND: 3, ASCENDANT: 4 };
  const n = chevrons[tier] || 0;
  const star = tier === 'IMMORTAL' || tier === 'RADIANT';

  let inner = '';
  for (let i = 0; i < n; i++) {
    inner += `<use href="#chev" x="0" y="${-4 + i * 13}" width="100" height="100" opacity="${1 - i * 0.16}"/>`;
  }
  if (star) inner = `<use href="#star" x="22" y="20" width="56" height="56"/>`;
  if (tier === 'RADIANT') {
    inner += `<use href="#star" x="8" y="52" width="20" height="20" opacity=".6"/>
              <use href="#star" x="72" y="52" width="20" height="20" opacity=".6"/>`;
  }

  return `<svg viewBox="0 0 100 100" style="color:${c};width:${size || '100%'};height:${size || '100%'}">
    <use href="#crest" width="100" height="100"/>${inner}</svg>`;
}

/* ------------------------------------------------------------ page router */
function showPage(page) {
  S.page = page;
  document.querySelectorAll('.page').forEach((p) => p.classList.remove('active'));
  const target = $('page-' + page);
  if (target) target.classList.add('active');
  document.querySelectorAll('.rail-btn').forEach((b) => {
    b.classList.toggle('active', b.dataset.page === page);
  });

  if (page === 'leaderboard') fetchBoard();
  if (page === 'history') post('fetch', { what: 'history', page: S.hist.page });
  if (page === 'profile') post('fetch', { what: 'profile' });
  if (page === 'rewards') post('fetch', { what: 'rewards' });
  if (page === 'custom') post('custom', { action: 'list' });
  if (page === 'admin') post('admin', { action: 'dashboard' });
  if (page === 'training') renderTraining();
  if (page === 'settings') renderSettings();
}

/* ============================================================ BOOT RENDER */
function renderBoot(data) {
  S.boot = data;
  const p = data.player;

  $('id-name').textContent = p.name || '—';
  $('id-initial').textContent = (p.name || '?').charAt(0).toUpperCase();
  $('id-title').textContent = p.activeTitle || '';
  $('id-rank').textContent = (p.rank || 'UNRANKED').toUpperCase();
  $('id-rank').style.color = p.rankColor || '#8A929E';
  $('id-rp').textContent = `${num(p.rp)} RP`;
  $('id-level').textContent = p.level || 1;
  $('id-xp-bar').style.width =
    Math.min(100, ((p.xp || 0) / Math.max(1, p.xpNeeded || 1)) * 100) + '%';

  // season strip
  const strip = $('season-strip');
  strip.innerHTML = '';
  if (data.season) {
    const left = Math.max(0, (data.season.endsAt || 0) - Math.floor(Date.now() / 1000));
    const days = Math.floor(left / 86400);
    strip.appendChild(el('div', 'season-pill',
      `<i></i><span>${esc(data.season.name)} · <b>${days}d</b> LEFT</span>`));
  }
  if (data.status && data.status.frozen) {
    strip.appendChild(el('div', 'season-pill', `<i style="background:#FFC94A;box-shadow:0 0 10px #FFC94A"></i><span>RANKED FROZEN</span>`));
  }

  document.querySelector('.rail-admin')
    .classList.toggle('hidden', !(data.permissions && data.permissions.moderator));

  renderRankCard(p);
  renderRankPath(p);
  renderQuickModes(data.modes);
  renderModeCards(data.modes);
  renderDashStats(data.stats);
  renderDashMissions(data.missions);
  renderStatus(data.status);
  post('fetch', { what: 'history', page: 1 });

  if (data.stats) {
    S.profile = data.stats;
    if (S.page === 'profile') renderProfile();
  }
}

function renderRankCard(p) {
  $('rankcard-crest').innerHTML = crest(p.tier, p.rankColor);
  $('rankcard-name').textContent = (p.rank || 'UNRANKED').toUpperCase();
  $('rankcard-name').style.color = p.rankColor || '#F4F6F8';
  $('rankcard-rp').textContent = num(p.rp);
  $('rankcard-pos').textContent = p.position ? `GLOBAL #${p.position}` : '';

  const pr = p.progress || {};
  $('rankcard-bar').style.width = (pr.percent || 0) + '%';

  if (p.placement && !p.placement.done && p.placement.enabled) {
    $('rankcard-next').textContent =
      `PLACEMENT ${p.placement.played} / ${p.placement.total} MATCHES`;
  } else if (pr.next) {
    $('rankcard-next').textContent = `${pr.needed} RP TO ${pr.next.toUpperCase()}`;
  } else {
    $('rankcard-next').textContent = 'MAXIMUM RANK REACHED';
  }
}

function renderRankPath(p) {
  const path = (S.boot && S.boot.rankPath) || [];
  const host = $('rankpath');
  host.innerHTML = '';
  const curIndex = path.indexOf(p.tier);
  path.forEach((tier, i) => {
    const node = el('div', 'rp-node', tier.slice(0, 4));
    if (curIndex >= 0 && i < curIndex) node.classList.add('done');
    if (tier === p.tier) node.classList.add('cur');
    host.appendChild(node);
  });
}

function renderQuickModes(modes) {
  const host = $('quick-modes');
  host.innerHTML = '';
  (modes || []).slice(0, 4).forEach((m) => {
    const card = el('div', 'qmode', `<b>${esc(m.label)}</b><span>${esc(m.teamSize)}v${esc(m.teamSize)} · ${esc(m.type).toUpperCase()}</span>`);
    card.onclick = () => { showPage('ranked'); selectMode(m.id); };
    card.onmouseenter = () => Audio_.play('hover');
    host.appendChild(card);
  });
}

function renderDashStats(profile) {
  const host = $('dash-stats');
  host.innerHTML = '';
  if (!profile || !profile.stats) return;
  const s = profile.stats;
  const rows = [
    ['MATCHES', num(s.matches), ''],
    ['WIN RATE', s.winRate + '%', s.winRate >= 50 ? 'good' : 'bad'],
    ['K / D', s.kd, s.kd >= 1 ? 'good' : 'bad'],
    ['KILLS', num(s.kills), ''],
    ['HEADSHOT %', s.hsPercent + '%', ''],
    ['MVP', num(s.mvp), ''],
    ['WIN STREAK', num(s.winStreak), ''],
    ['CLUTCHES', num(s.clutches), ''],
    ['ACES', num(s.aces), '']
  ];
  rows.forEach(([label, value, cls]) => {
    host.appendChild(el('div', 'stat ' + cls, `<b>${esc(value)}</b><span>${label}</span>`));
  });
}

function renderDashMissions(missions) {
  const host = $('dash-missions');
  host.innerHTML = '';
  const list = (missions && missions.daily) || [];
  if (!list.length) {
    host.appendChild(el('div', 'party-empty', 'NO ACTIVE MISSIONS'));
    return;
  }
  list.forEach((m) => {
    const pct = Math.min(100, (m.progress / Math.max(1, m.target)) * 100);
    const node = el('div', 'mission' + (m.completed ? ' done' : ''),
      `<div class="mission-top"><span>${esc(m.label)}</span><s>${m.progress}/${m.target}</s></div>
       <div class="mission-bar"><i style="width:${pct}%"></i></div>`);
    host.appendChild(node);
  });
}

function renderMiniHistory(rows) {
  const host = $('dash-history');
  host.innerHTML = '';
  if (!rows || !rows.length) {
    host.appendChild(el('div', 'party-empty', 'NO MATCHES YET'));
    return;
  }
  rows.slice(0, 5).forEach((r) => {
    const loss = r.result === 'LOSS';
    host.appendChild(el('div', 'mh' + (loss ? ' loss' : ''),
      `<i></i>
       <div><div class="mh-mode">${esc(r.mode)}</div><div class="mh-map">${esc(r.map)}</div></div>
       <div class="mh-kd">${r.kills}/${r.deaths}</div>
       <div class="mh-rp ${r.rpChange < 0 ? 'neg' : ''}">${r.rpChange > 0 ? '+' : ''}${r.rpChange}</div>`));
  });
}

function renderStatus(status) {
  const panel = $('status-panel');
  const body = $('status-body');
  if (!status) return;
  body.innerHTML = '';
  let show = false;

  if (status.banned) {
    show = true;
    const until = status.banned.permanent ? 'PERMANENT'
      : new Date(status.banned.expiry * 1000).toLocaleString();
    body.appendChild(el('div', 'toast error',
      `<b>RANKED BAN</b><span>${esc(status.banned.reason)} — ${esc(until)}</span>`));
  }
  if (status.cooldown > 0) {
    show = true;
    body.appendChild(el('div', 'toast warning',
      `<b>QUEUE COOLDOWN</b><span>${Math.ceil(status.cooldown / 60)} minutes remaining</span>`));
  }
  if (status.reconnect) {
    show = true;
    const b = el('div', 'toast');
    b.innerHTML = `<b>MATCH IN PROGRESS</b><span>You can rejoin your match.</span>`;
    const btn = el('button', 'btn btn-sm', 'RECONNECT');
    btn.style.marginTop = '8px';
    btn.onclick = () => post('action', { action: 'reconnect' });
    b.appendChild(btn);
    body.appendChild(b);
  }
  panel.classList.toggle('hidden', !show);
}

/* ============================================================ RANKED PAGE */
let selectedMode = null;

function renderModeCards(modes) {
  const host = $('ranked-modes');
  host.innerHTML = '';
  (modes || []).forEach((m) => {
    const card = el('div', 'modecard',
      `<div class="modecard-glyph">${esc(m.label.replace(/[^0-9V]/gi, '').slice(0, 3) || m.label.slice(0, 3))}</div>
       <div><b>${esc(m.label)}</b><p>${esc(m.description || '')}</p></div>
       <div class="modecard-meta">
         <span>${m.teamSize}v${m.teamSize}</span>
         <span>${esc((m.type || '').toUpperCase())}</span>
         ${m.roundsToWin ? `<span>FIRST TO ${m.roundsToWin}</span>` : ''}
       </div>`);
    card.dataset.mode = m.id;
    card.onmouseenter = () => Audio_.play('hover');
    card.onclick = () => { selectMode(m.id); startQueue(m.id); };
    host.appendChild(card);
  });
}

function selectMode(mode) {
  selectedMode = mode;
  document.querySelectorAll('.modecard').forEach((c) =>
    c.classList.toggle('selected', c.dataset.mode === mode));
}

function startQueue(mode) {
  if (S.queue.state === 'SEARCHING') { post('queue', { action: 'leave' }); return; }
  Audio_.play('queue');
  post('queue', { action: 'join', mode: mode || selectedMode });
}

function renderQueue(q) {
  const searching = q && q.state === 'SEARCHING';
  $('searching').classList.toggle('hidden', !searching);
  $('queue-idle').classList.toggle('hidden', searching);

  if (!searching) {
    S.queue.state = 'IDLE';
    return;
  }
  S.queue.state = 'SEARCHING';
  if (q.mode) S.queue.mode = q.mode;
  if (q.elapsed !== undefined) $('search-elapsed').textContent = clockLong(q.elapsed);
  if (q.estimate !== undefined) $('search-eta').textContent = clockLong(q.estimate);
  if (q.searching !== undefined) $('search-count').textContent = q.searching;

  if (S.boot && S.boot.player) {
    const p = S.boot.player;
    $('search-rank').innerHTML =
      `<span style="color:${p.rankColor}">${esc((p.rank || '').toUpperCase())}</span> · ${num(p.rp)} RP`;
  }
}

/* =========================================================== MATCH FOUND */
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
  $('found-mode').textContent = (d.modeLabel || d.mode || 'RANKED').toUpperCase();
  $('found-accepted').textContent = d.accepted || 0;
  $('found-total').textContent = d.total || 0;

  const mine = d.accepted_self === true;
  $('found-waiting').classList.toggle('hidden', !mine);
  document.querySelector('.found-actions').classList.toggle('hidden', mine);

  if (first) {
    Audio_.play('found');
    let left = d.timeout || 15;
    const total = left;
    const ring = $('found-ring');
    const circumference = 2 * Math.PI * 52;
    ring.style.strokeDasharray = circumference;

    const tick = () => {
      $('found-timer').textContent = Math.max(0, left);
      ring.style.strokeDashoffset = circumference * (1 - left / total);
      if (left <= 5 && left > 0) Audio_.play('tick');
      left -= 1;
      if (left < 0) {
        clearInterval(S.foundTimer);
        S.foundTimer = null;
      }
    };
    tick();
    S.foundTimer = setInterval(tick, 1000);
  }
}

$('btn-accept').onclick = () => {
  if (!S.found) return;
  Audio_.play('accept');
  post('ready', { id: S.found.id, accept: true });
  $('found-waiting').classList.remove('hidden');
  document.querySelector('.found-actions').classList.add('hidden');
};
$('btn-decline').onclick = () => {
  if (!S.found) return;
  post('ready', { id: S.found.id, accept: false });
  renderFound(null);
};

/* ============================================================== MAP VOTE */
function renderMapVote(d) {
  const modal = $('modal-mapvote');
  if (!d) return;

  if (d.close || d.result) {
    modal.classList.add('hidden');
    if (S.mapvoteTimer) { clearInterval(S.mapvoteTimer); S.mapvoteTimer = null; }
    if (d.result) {
      const name = (S.mapvote && S.mapvote.names && S.mapvote.names[d.result]) || d.result;
      toast('info', `Map selected: ${name}`, 'MAP VOTE');
    }
    S.mapvote = null;
    return;
  }

  if (d.options) {
    S.mapvote = { names: {}, picked: null };
    modal.classList.remove('hidden');
    const grid = $('mv-grid');
    grid.innerHTML = '';

    d.options.forEach((m, i) => {
      S.mapvote.names[m.id] = m.name;
      const hue = (i * 47 + 200) % 360;
      const card = el('div', 'mv-card',
        `<div class="mv-card-art" style="background:
            linear-gradient(150deg,hsl(${hue} 40% 16%),hsl(${(hue + 40) % 360} 50% 8%)),
            repeating-linear-gradient(60deg,rgba(255,255,255,.03) 0 2px,transparent 2px 16px)"></div>
         <div class="mv-card-votes" data-map="${esc(m.id)}">0</div>
         <div class="mv-card-name">${esc(m.name)}</div>`);
      card.onclick = () => {
        document.querySelectorAll('.mv-card').forEach((c) => c.classList.remove('picked'));
        card.classList.add('picked');
        S.mapvote.picked = m.id;
        Audio_.play('click');
        post('mapVote', { mapId: m.id });
        $('mv-foot').textContent = `YOU VOTED FOR ${m.name.toUpperCase()}`;
      };
      card.onmouseenter = () => Audio_.play('hover');
      grid.appendChild(card);
    });

    let left = d.duration || 20;
    $('mv-timer').textContent = left;
    if (S.mapvoteTimer) clearInterval(S.mapvoteTimer);
    S.mapvoteTimer = setInterval(() => {
      left -= 1;
      $('mv-timer').textContent = Math.max(0, left);
      if (left <= 0) { clearInterval(S.mapvoteTimer); S.mapvoteTimer = null; }
    }, 1000);
  }

  if (d.votes) {
    Object.keys(d.votes).forEach((mapId) => {
      const node = document.querySelector(`.mv-card-votes[data-map="${mapId}"]`);
      if (node) node.textContent = d.votes[mapId];
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
    const a = el('button', 'btn sm', 'ACCEPT');
    const r = el('button', 'btn sm btn-ghost', 'DECLINE');
    a.onclick = () => { post('party', { action: 'accept' }); t.remove(); };
    r.onclick = () => { post('party', { action: 'decline' }); t.remove(); };
    row.appendChild(a); row.appendChild(r);
    t.appendChild(row);
    return;
  }

  S.party = d;
  const host = $('party-list');
  host.innerHTML = '';

  if (!d.members || !d.members.length) {
    host.appendChild(el('div', 'party-empty', 'NO PARTY — INVITE A PLAYER TO BEGIN'));
    return;
  }

  d.members.forEach((m) => {
    const node = el('div', 'party-member' + (m.leader ? ' leader' : '') + (m.ready ? ' ready' : ''),
      `<span class="dot"></span><b>${esc(m.name)}</b>
       <span class="chip">${esc(m.rank)}</span>`);
    if (S.party.leader === (S.boot && S.boot.player.userId) && !m.leader) {
      const kick = el('button', '', '✕');
      kick.style.cssText = 'color:var(--dim);font-size:11px';
      kick.onclick = () => post('party', { action: 'kick', target: m.userId });
      node.appendChild(kick);
    }
    host.appendChild(node);
  });
}

/* ================================================================ CUSTOM */
function renderRooms(list) {
  S.rooms = list || [];
  const host = $('rooms-body');
  host.innerHTML = '';

  if (!S.rooms.length) {
    host.appendChild(el('div', 'room-empty', 'NO ACTIVE ROOMS — CREATE ONE'));
    return;
  }

  S.rooms.forEach((r) => {
    const row = el('div', 'room',
      `<b>${esc(r.name)}${r.hasPassword ? ' <span class="locked">🔒</span>' : ''}</b>
       <span>${esc(r.host)}</span>
       <span>${esc(r.modeLabel)}</span>
       <span>${esc(r.mapName)}</span>
       <span>${r.players}/${r.maxPlayers}</span>
       <span class="${r.state === 'LIVE' ? 'locked' : ''}">${esc(r.state)}</span>`);
    const join = el('button', 'btn sm', 'JOIN');
    join.onclick = () => {
      const password = r.hasPassword ? (prompt('Room password:') || '') : '';
      post('custom', { action: 'join', roomId: r.id, password });
    };
    row.appendChild(join);
    host.appendChild(row);
  });
}

function renderRoom(room) {
  S.room = room;
  const view = $('roomview');
  $('rooms-panel').classList.toggle('hidden', !!room);
  $('createbox').classList.add('hidden');

  if (!room) { view.classList.add('hidden'); view.innerHTML = ''; return; }

  const me = S.boot && S.boot.player.userId;
  const isHost = room.hostId === me;
  const roster = room.roster || [];
  const teamA = roster.filter((p) => p.team === 1 && !p.spectator);
  const teamB = roster.filter((p) => p.team === 2 && !p.spectator);
  const specs = roster.filter((p) => p.spectator);

  const slot = (p) => `
    <div class="slot">
      <b>${esc(p.name)}</b>
      <span class="chip">${esc(p.rank)}</span>
      ${p.host ? '<span class="host">HOST</span>' : ''}
      ${isHost && !p.host ? `<span class="tools">
        <button data-room-act="move" data-user="${p.userId}" data-team="${p.team === 1 ? 2 : 1}">SWAP</button>
        <button data-room-act="kick" data-user="${p.userId}">KICK</button>
        <button data-room-act="ban" data-user="${p.userId}">BAN</button>
      </span>` : ''}
    </div>`;

  view.classList.remove('hidden');
  view.innerHTML = `
    <div class="panel">
      <div class="section-head" style="margin-bottom:12px">
        <h2 style="font-size:22px">${esc(room.name)}</h2>
        <div class="section-actions">
          ${isHost ? `<button class="btn btn-sm" data-room-act="start">START</button>` : ''}
          ${isHost ? `<button class="btn btn-sm btn-ghost" data-room-act="lock">${room.locked ? 'UNLOCK' : 'LOCK'}</button>` : ''}
          ${isHost && room.state === 'LIVE' ? `<button class="btn btn-sm btn-ghost" data-room-act="stop">STOP</button>` : ''}
          <button class="btn btn-sm btn-danger" data-room-act="leave">LEAVE</button>
        </div>
      </div>
      <div class="modecard-meta" style="margin:0 0 12px">
        <span>${esc(room.modeLabel)}</span><span>${esc(room.mapName)}</span>
        <span>${room.players}/${room.maxPlayers} PLAYERS</span>
        <span>${room.ranked ? 'RANKED' : 'UNRANKED'}</span>
        <span>${esc(room.state)}</span>
      </div>
      <div class="teams">
        <div class="teamcol a"><h4>TEAM A · ${teamA.length}</h4>${teamA.map(slot).join('') || '<div class="party-empty">EMPTY</div>'}</div>
        <div class="teamcol b"><h4>TEAM B · ${teamB.length}</h4>${teamB.map(slot).join('') || '<div class="party-empty">EMPTY</div>'}</div>
      </div>
      ${specs.length ? `<div class="teamcol" style="margin-top:14px"><h4>SPECTATORS</h4>${specs.map(slot).join('')}</div>` : ''}
      ${isHost ? renderRoomSettings(room) : ''}
    </div>`;
}

function renderRoomSettings(room) {
  const s = room.settings || {};
  const maps = (S.boot && S.boot.maps) || [];
  const modes = (S.boot && S.boot.allModes) || [];
  const numField = (key, label, value) =>
    `<div class="field"><label>${label}</label>
      <input class="input" type="number" data-setting="${key}" value="${value}" /></div>`;
  const boolField = (key, label, value) =>
    `<label class="switch"><input type="checkbox" data-setting="${key}" ${value ? 'checked' : ''}/><i></i>${label}</label>`;

  return `
    <div style="margin-top:18px;padding-top:16px;border-top:1px solid var(--line-soft)">
      <span class="panel-tag">ROOM SETTINGS</span>
      <div class="formgrid">
        <div class="field"><label>MODE</label>
          <select class="input" data-setting-mode>
            ${modes.map((m) => `<option value="${m.id}" ${m.id === room.mode ? 'selected' : ''}>${esc(m.label)}</option>`).join('')}
          </select></div>
        <div class="field"><label>MAP</label>
          <select class="input" data-setting-map>
            ${maps.map((m) => `<option value="${m.id}" ${m.id === room.map ? 'selected' : ''}>${esc(m.name)}</option>`).join('')}
          </select></div>
        ${numField('rounds', 'ROUNDS', s.rounds)}
        ${numField('roundTime', 'ROUND TIME (S)', s.roundTime)}
        ${numField('matchTime', 'MATCH TIME (S)', s.matchTime)}
        ${numField('killLimit', 'KILL LIMIT', s.killLimit)}
        ${numField('health', 'HEALTH', s.health)}
        ${numField('armor', 'ARMOR', s.armor)}
        ${numField('lives', 'LIVES', s.lives)}
        ${numField('respawnTime', 'RESPAWN (S)', s.respawnTime)}
      </div>
      <div class="formgrid" style="margin-top:10px">
        ${boolField('friendlyFire', 'FRIENDLY FIRE', s.friendlyFire)}
        ${boolField('headshotOneShot', 'HEADSHOT ONE SHOT', s.headshotOneShot)}
        ${boolField('respawn', 'RESPAWN', s.respawn)}
        ${boolField('jump', 'JUMP', s.jump)}
        ${boolField('minimap', 'MINIMAP', s.minimap)}
        ${boolField('vehicles', 'VEHICLES', s.vehicles)}
        ${boolField('killcam', 'KILLCAM', s.killcam)}
        ${boolField('overtime', 'OVERTIME', s.overtime)}
        ${boolField('suddenDeath', 'SUDDEN DEATH', s.suddenDeath)}
        ${boolField('spectators', 'SPECTATORS', s.spectators)}
        ${boolField('teamBalance', 'TEAM BALANCE', s.teamBalance)}
        ${boolField('autoStart', 'AUTO START', s.autoStart)}
      </div>
      <button class="btn btn-sm" style="margin-top:14px" data-room-act="apply">APPLY SETTINGS</button>
    </div>`;
}

function renderCreateBox() {
  const box = $('createbox');
  const maps = (S.boot && S.boot.maps) || [];
  const modes = (S.boot && S.boot.allModes) || [];
  box.classList.remove('hidden');
  $('rooms-panel').classList.add('hidden');
  box.innerHTML = `
    <span class="panel-tag">CREATE CUSTOM GAME</span>
    <div class="formgrid">
      <div class="field"><label>ROOM NAME</label><input class="input" id="cg-name" placeholder="My Room"/></div>
      <div class="field"><label>PASSWORD (OPTIONAL)</label><input class="input" id="cg-pass" placeholder="—"/></div>
      <div class="field"><label>MODE</label><select class="input" id="cg-mode">
        ${modes.map((m) => `<option value="${m.id}">${esc(m.label)}</option>`).join('')}</select></div>
      <div class="field"><label>MAP</label><select class="input" id="cg-map">
        ${maps.map((m) => `<option value="${m.id}">${esc(m.name)}</option>`).join('')}</select></div>
      <div class="field"><label>ROUNDS</label><input class="input" id="cg-rounds" type="number" value="13"/></div>
      <div class="field"><label>ROUND TIME (S)</label><input class="input" id="cg-roundtime" type="number" value="120"/></div>
    </div>
    <div class="formgrid" style="margin-top:10px">
      <label class="switch"><input type="checkbox" id="cg-ff"/><i></i>FRIENDLY FIRE</label>
      <label class="switch"><input type="checkbox" id="cg-hs" checked/><i></i>HEADSHOT ONE SHOT</label>
      <label class="switch"><input type="checkbox" id="cg-respawn"/><i></i>RESPAWN</label>
      <label class="switch"><input type="checkbox" id="cg-auto" checked/><i></i>AUTO START</label>
    </div>
    <div style="display:flex;gap:8px;margin-top:16px">
      <button class="btn btn-sm" data-action="custom-create">CREATE</button>
      <button class="btn btn-sm btn-ghost" data-action="custom-cancel">CANCEL</button>
    </div>`;
}

/* =========================================================== LEADERBOARD */
function fetchBoard() {
  post('fetch', { what: 'leaderboard', board: S.lb.board, page: S.lb.page });
}

function renderBoard(d) {
  S.lb.rows = d.rows || [];
  $('lb-page').textContent = `PAGE ${d.page || 1}`;

  const podium = $('podium');
  podium.innerHTML = '';
  const body = $('board-body');
  body.innerHTML = '';

  if (!S.lb.rows.length) {
    body.appendChild(el('div', 'room-empty', 'NO RANKED PLAYERS YET'));
    return;
  }

  const me = S.boot && S.boot.player.userId;

  // Top 3 podium, only on the first page
  if ((d.page || 1) === 1) {
    const top = S.lb.rows.slice(0, 3);
    const order = [1, 0, 2]; // 2nd, 1st, 3rd
    order.forEach((idx) => {
      const r = top[idx];
      if (!r) { podium.appendChild(el('div')); return; }
      const place = idx + 1;
      const node = el('div', `pod pod-${place}`,
        `<div class="pod-place">#${place}</div>
         <div class="pod-crest">${crest(r.tier, r.rankColor)}</div>
         <div class="pod-name">${esc(r.name)}</div>
         <div class="pod-rank" style="color:${r.rankColor}">${esc((r.rank || '').toUpperCase())}</div>
         <div class="pod-rp">${num(r.rp)} <span style="font-size:12px;color:var(--dim)">RP</span></div>
         <div class="pod-sub">${r.wins}W · ${r.losses}L · ${r.kd} KD</div>`);
      podium.appendChild(node);
    });
  }

  S.lb.rows.forEach((r) => {
    const row = el('div', 'brow' + (r.userId === me ? ' you' : ''),
      `<span class="pos">#${r.position}</span>
       <span class="pname">${esc(r.name)}${r.mmr ? ` <span class="chip">MMR ${r.mmr}</span>` : ''}</span>
       <span class="prank" style="color:${r.rankColor}">${esc((r.rank || '').toUpperCase())}</span>
       <span>${num(r.gained !== undefined ? r.gained : r.rp)}</span>
       <span>${r.wins} / ${r.losses}</span>
       <span>${r.kd}</span>
       <span>${r.hsPercent}%</span>`);
    row.onclick = () => { post('fetch', { what: 'profile', userId: r.userId }); showPage('profile'); };
    body.appendChild(row);
  });
}

/* =============================================================== PROFILE */
function renderProfile() {
  const p = S.profile;
  const host = $('profile-root');
  if (!p) { host.innerHTML = '<div class="room-empty">NO PROFILE DATA</div>'; return; }

  const s = p.stats;
  const stat = (label, value, cls) =>
    `<div class="stat ${cls || ''}"><b>${esc(value)}</b><span>${label}</span></div>`;
  const bar = (label, value, pct, colour) =>
    `<div class="barrow"><span><em style="font-style:normal">${label}</em><em style="font-style:normal">${value}</em></span>
      <div class="barline"><i style="width:${Math.min(100, pct)}%;${colour ? `background:${colour}` : ''}"></i></div></div>`;

  host.innerHTML = `
    <div class="pbanner">
      <div class="pav">${esc((p.name || '?').charAt(0).toUpperCase())}</div>
      <div class="pinfo">
        <div class="pname">${esc(p.name)}</div>
        <div class="ptitle">${esc(p.activeTitle || '')}</div>
        <div class="pmeta">
          <span class="chip chip-rank" style="color:${p.rankColor}">${esc((p.rank || '').toUpperCase())}</span>
          <span class="chip">${num(p.rp)} RP</span>
          <span class="chip">LEVEL ${p.level}</span>
          <span class="chip">GLOBAL #${p.position || '—'}</span>
          <span class="chip">PEAK ${esc(p.highestRank)}</span>
          ${p.mmr ? `<span class="chip">MMR ${p.mmr}</span>` : ''}
          <span class="chip">${p.commendations} COMMENDS</span>
        </div>
      </div>
      <div class="pcrest">${crest(p.tier, p.rankColor)}</div>
    </div>

    <div class="panel">
      <span class="panel-tag">CAREER STATISTICS</span>
      <div class="pgrid">
        ${stat('MATCHES', num(s.matches))}
        ${stat('WINS', num(s.wins), 'good')}
        ${stat('LOSSES', num(s.losses), 'bad')}
        ${stat('WIN RATE', s.winRate + '%', s.winRate >= 50 ? 'good' : 'bad')}
        ${stat('KILLS', num(s.kills))}
        ${stat('DEATHS', num(s.deaths))}
        ${stat('ASSISTS', num(s.assists))}
        ${stat('K / D', s.kd, s.kd >= 1 ? 'good' : 'bad')}
        ${stat('HEADSHOTS', num(s.headshots))}
        ${stat('HEADSHOT %', s.hsPercent + '%')}
        ${stat('DAMAGE', num(s.damage))}
        ${stat('MVP', num(s.mvp))}
        ${stat('WIN STREAK', num(s.winStreak))}
        ${stat('BEST STREAK', num(s.bestStreak))}
        ${stat('CLUTCHES', num(s.clutches))}
        ${stat('ACES', num(s.aces))}
        ${stat('FIRST BLOODS', num(s.firstBloods))}
        ${stat('PLAYTIME', Math.floor((s.playtime || 0) / 3600) + 'h')}
      </div>
    </div>

    <div class="settings">
      <div class="panel">
        <span class="panel-tag">PERFORMANCE</span>
        <div class="bars">
          ${bar('WIN RATE', s.winRate + '%', s.winRate)}
          ${bar('HEADSHOT RATE', s.hsPercent + '%', s.hsPercent, 'linear-gradient(90deg,#FF2E4D,#FF6B80)')}
          ${bar('K/D RATIO', s.kd, Math.min(100, s.kd * 50), 'linear-gradient(90deg,#28E0A0,#7CF3C8)')}
          ${bar('RANK PROGRESS', (p.progress && p.progress.percent || 0) + '%', p.progress && p.progress.percent || 0)}
        </div>
        <div style="margin-top:16px">
          <span class="panel-tag">FAVOURITES</span>
          <div class="chips">
            <span class="badge on">${esc((s.favWeapon || '—').replace('WEAPON_', ''))}</span>
            <span class="badge on">${esc((s.favMap || '—').toUpperCase())}</span>
          </div>
        </div>
      </div>

      <div class="panel">
        <span class="panel-tag">TITLES &amp; BADGES</span>
        <div class="chips">
          ${(p.titles || []).length ? p.titles.map((t) =>
            `<span class="badge ${t === p.activeTitle ? 'on' : ''}" data-title="${esc(t)}">${esc(t)}</span>`).join('')
            : '<span class="party-empty">NO TITLES YET</span>'}
        </div>
        <div class="chips" style="margin-top:12px">
          ${(p.badges || []).map((b) => `<span class="badge on">${esc(b)}</span>`).join('')
            || '<span class="party-empty">NO BADGES YET</span>'}
        </div>
        <div style="margin-top:18px">
          <span class="panel-tag">SEASON HISTORY</span>
          ${(p.seasons || []).length ? p.seasons.map((sn) =>
            `<div class="arow"><b>${esc(sn.name)}</b><span class="grow"></span>
              <span>${esc(sn.rank_name || '')}</span><span>${num(sn.final_rp)} RP</span></div>`).join('')
            : '<div class="party-empty">NO ARCHIVED SEASONS</div>'}
        </div>
      </div>
    </div>

    <div class="panel">
      <span class="panel-tag">ACHIEVEMENTS</span>
      ${(p.achievements || []).map((a) =>
        `<div class="ach ${a.unlocked ? 'on' : ''}">
          <span class="tick">${a.unlocked ? '✓' : ''}</span>
          <div><b>${esc(a.label)}</b><div style="font-size:11px;color:var(--dim)">${esc(a.desc)}</div></div>
          <span>${a.unlocked ? 'UNLOCKED' : 'LOCKED'}</span>
        </div>`).join('')}
    </div>`;

  host.querySelectorAll('[data-title]').forEach((n) => {
    n.onclick = () => post('action', { action: 'setTitle', title: n.dataset.title });
  });
}

/* =============================================================== HISTORY */
function renderHistory(rows, page) {
  S.hist.rows = rows || [];
  $('hist-page').textContent = `PAGE ${page || 1}`;
  const host = $('history-list');
  host.innerHTML = '';

  if (!S.hist.rows.length) {
    host.appendChild(el('div', 'room-empty', 'NO MATCHES PLAYED YET'));
    return;
  }

  S.hist.rows.forEach((r) => {
    const cls = r.result === 'LOSS' ? 'loss' : (r.result === 'DRAW' ? 'draw' : '');
    const row = el('div', 'hrow ' + cls,
      `<i class="bar"></i>
       <div><div class="hres">${r.result === 'WIN' ? 'VICTORY' : (r.result === 'LOSS' ? 'DEFEAT' : 'DRAW')}</div>
            <div class="mh-map">${esc(r.mode)} · ${esc(r.map)}</div></div>
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

  renderMiniHistory(S.hist.rows);
}

function renderMatchDetail(d) {
  const host = $('matchdetail');
  if (!d) { host.classList.add('hidden'); return; }
  host.classList.remove('hidden');

  const team = (t) => (d.roster || []).filter((p) => p.team === t);
  const rows = (list) => list.map((p) =>
    `<div class="brow">
      <span class="pos">${p.mvp ? '★' : ''}</span>
      <span class="pname">${esc(p.name)}</span>
      <span class="prank">${esc(p.rank)}</span>
      <span>${p.kills}/${p.deaths}/${p.assists}</span>
      <span>${p.kd}</span>
      <span>${num(p.damage)}</span>
      <span class="${p.rpChange < 0 ? 'mh-rp neg' : 'mh-rp'}">${p.rpChange > 0 ? '+' : ''}${p.rpChange}</span>
    </div>`).join('');

  host.innerHTML = `
    <div class="section-head" style="margin-bottom:12px">
      <h2 style="font-size:20px">${esc(d.mode)} · ${esc(d.map)}</h2>
      <div class="section-actions">
        <span class="chip">${d.scores.a} - ${d.scores.b}</span>
        <span class="chip">${Math.floor((d.duration || 0) / 60)} MIN</span>
        <span class="chip">${d.overtime ? 'OVERTIME' : 'REGULATION'}</span>
        <button class="btn btn-sm btn-ghost" data-action="detail-close">CLOSE</button>
      </div>
    </div>
    <div class="board-head"><span></span><span>PLAYER</span><span>RANK</span><span>K/D/A</span><span>KD</span><span>DMG</span><span>RP</span></div>
    <div class="teamcol a" style="margin-top:8px"><h4>TEAM A</h4>${rows(team(1))}</div>
    <div class="teamcol b" style="margin-top:10px"><h4>TEAM B</h4>${rows(team(2))}</div>`;
}

/* =============================================================== REWARDS */
function renderRewards(d) {
  S.rewards = d;
  const host = $('rewards-root');
  const p = S.boot && S.boot.player;

  const missions = (kind) => {
    const list = (d.missions && d.missions[kind]) || [];
    if (!list.length) return '<div class="party-empty">NONE ACTIVE</div>';
    return list.map((m) => {
      const pct = Math.min(100, (m.progress / Math.max(1, m.target)) * 100);
      return `<div class="mission ${m.completed ? 'done' : ''}">
        <div class="mission-top"><span>${esc(m.label)}</span><s>${m.progress}/${m.target}</s></div>
        <div class="mission-bar"><i style="width:${pct}%"></i></div>
        <div style="font-size:10px;color:var(--dim);margin-top:5px;letter-spacing:.14em">
          +${m.xp} XP${m.money ? ` · $${num(m.money)}` : ''}</div>
      </div>`;
    }).join('');
  };

  host.innerHTML = `
    <div class="panel">
      <span class="panel-tag">LEVEL PROGRESSION</span>
      <div style="display:flex;align-items:center;gap:20px">
        <div class="stat" style="min-width:120px"><b>${p ? p.level : 1}</b><span>LEVEL</span></div>
        <div style="flex:1">
          <div class="progress"><i style="width:${p ? Math.min(100, (p.xp / Math.max(1, p.xpNeeded)) * 100) : 0}%"></i></div>
          <div style="font-size:11px;color:var(--dim);margin-top:6px;letter-spacing:.16em">
            ${p ? num(p.xp) : 0} / ${p ? num(p.xpNeeded) : 0} XP</div>
        </div>
      </div>
    </div>

    <div class="settings">
      <div class="panel"><span class="panel-tag">DAILY MISSIONS</span><div class="missions">${missions('daily')}</div></div>
      <div class="panel"><span class="panel-tag">WEEKLY MISSIONS</span><div class="missions">${missions('weekly')}</div></div>
    </div>

    <div class="panel">
      <span class="panel-tag">YOUR REWARDS</span>
      <div class="rgrid">
        ${(d.rows || []).length ? (d.rows || []).map((r) => {
          let value = r.value;
          try { value = JSON.parse(r.value); } catch (e) { value = {}; }
          return `<div class="rcard ${r.claimed ? 'claimed' : ''}">
            <b>${esc((r.type || '').toUpperCase())}</b>
            <span>${esc(value && value.value !== undefined ? value.value : r.reward_key)}</span>
            <div style="margin-top:10px">
              ${r.claimed ? '<span class="chip">CLAIMED</span>'
                : `<button class="btn sm" data-claim="${esc(r.reward_key)}">CLAIM</button>`}
            </div>
          </div>`;
        }).join('') : '<div class="party-empty">NO REWARDS YET</div>'}
      </div>
    </div>

    <div class="panel">
      <span class="panel-tag">SEASON REWARD TIERS</span>
      <div class="rgrid">
        ${Object.keys(d.season || {}).map((tier) => `
          <div class="rcard">
            <b style="color:var(--gold)">${esc(tier)}</b>
            <span>${(d.season[tier] || []).map((r) => `${r.type}: ${r.value}`).join(' · ')}</span>
          </div>`).join('')}
      </div>
    </div>

    <div class="panel">
      <span class="panel-tag">ACHIEVEMENTS</span>
      ${(d.achievements || []).map((a) =>
        `<div class="ach ${a.unlocked ? 'on' : ''}">
          <span class="tick">${a.unlocked ? '✓' : ''}</span>
          <div><b>${esc(a.label)}</b><div style="font-size:11px;color:var(--dim)">${esc(a.desc)}</div></div>
          <span>${a.unlocked ? 'UNLOCKED' : 'LOCKED'}</span>
        </div>`).join('')}
    </div>`;

  host.querySelectorAll('[data-claim]').forEach((b) => {
    b.onclick = () => post('action', { action: 'claimReward', key: b.dataset.claim });
  });
}

/* ============================================================== TRAINING */
function renderTraining() {
  const host = $('traingrid');
  const modes = [
    { kind: 'aim', label: 'AIM TRAINING', desc: 'Static targets at mixed ranges. Warm up your tracking and flicks.' },
    { kind: 'headshot', label: 'HEADSHOT TRAINING', desc: 'Long range targets. One clean head hit is always lethal — practise it.' },
    { kind: 'range', label: 'FREE RANGE', desc: 'Open range with a full loadout. No targets, no timer.' }
  ];
  host.innerHTML = '';
  modes.forEach((m) => {
    const card = el('div', 'traincard',
      `<div><b>${m.label}</b><p>${m.desc}</p></div>
       <button class="btn btn-sm">ENTER</button>`);
    card.onclick = () => post('action', { action: 'training', enable: true, kind: m.kind });
    card.onmouseenter = () => Audio_.play('hover');
    host.appendChild(card);
  });
}

/* ============================================================== SETTINGS */
const SETTING_DEFS = [
  { key: 'uiVolume',      label: 'UI VOLUME',        type: 'range', min: 0, max: 100 },
  { key: 'musicVolume',   label: 'MUSIC VOLUME',     type: 'range', min: 0, max: 100 },
  { key: 'hudSize',       label: 'HUD SIZE',         type: 'range', min: 70, max: 130 },
  { key: 'killSounds',    label: 'KILL SOUNDS',      type: 'bool' },
  { key: 'showPing',      label: 'SHOW PING',        type: 'bool' },
  { key: 'showMinimap',   label: 'MINIMAP IN MATCH', type: 'bool' },
  { key: 'visualEffects', label: 'VISUAL EFFECTS',   type: 'bool' },
  { key: 'lowSpecMode',   label: 'LOW SPEC MODE',    type: 'bool' },
  { key: 'spectatorAuto', label: 'AUTO SPECTATE',    type: 'bool' },
  { key: 'killFeedPos',   label: 'KILL FEED SIDE',   type: 'select', options: ['right', 'left'] },
  { key: 'language',      label: 'LANGUAGE',         type: 'select', options: ['en', 'ar'] },
  { key: 'teamColorA',    label: 'TEAM A COLOUR',    type: 'color' },
  { key: 'teamColorB',    label: 'TEAM B COLOUR',    type: 'color' }
];

function renderSettings() {
  const host = $('settings-root');
  const rows = SETTING_DEFS.map((d) => {
    const v = S.settings[d.key];
    if (d.type === 'range') {
      return `<div class="srow"><label>${d.label}</label>
        <div style="display:flex;align-items:center;gap:10px">
          <input type="range" min="${d.min}" max="${d.max}" value="${v}" data-set="${d.key}"/>
          <span class="val" data-val="${d.key}">${v}</span></div></div>`;
    }
    if (d.type === 'bool') {
      return `<div class="srow"><label>${d.label}</label>
        <label class="switch"><input type="checkbox" data-set="${d.key}" ${v ? 'checked' : ''}/><i></i></label></div>`;
    }
    if (d.type === 'select') {
      return `<div class="srow"><label>${d.label}</label>
        <select class="input" style="width:auto" data-set="${d.key}">
          ${d.options.map((o) => `<option value="${o}" ${o === v ? 'selected' : ''}>${o.toUpperCase()}</option>`).join('')}
        </select></div>`;
    }
    return `<div class="srow"><label>${d.label}</label>
      <input class="swatch" type="color" value="${v}" data-set="${d.key}"/></div>`;
  });

  const half = Math.ceil(rows.length / 2);
  host.innerHTML = `
    <div class="panel"><span class="panel-tag">INTERFACE</span>${rows.slice(0, half).join('')}</div>
    <div class="panel"><span class="panel-tag">GAMEPLAY</span>${rows.slice(half).join('')}
      <button class="btn btn-sm btn-ghost" style="margin-top:16px" data-action="settings-reset">RESET TO DEFAULTS</button>
    </div>`;

  host.querySelectorAll('[data-set]').forEach((input) => {
    const key = input.dataset.set;
    const handler = () => {
      let value;
      if (input.type === 'checkbox') value = input.checked;
      else if (input.type === 'range') {
        value = parseInt(input.value, 10);
        const label = host.querySelector(`[data-val="${key}"]`);
        if (label) label.textContent = value;
      } else value = input.value;
      S.settings[key] = value;
      saveSettings();
    };
    input.oninput = handler;
    input.onchange = handler;
  });
}

function loadSettings() {
  let stored = {};
  try { stored = JSON.parse(localStorage.getItem('m5rp_settings') || '{}'); } catch (e) { stored = {}; }
  S.settings = Object.assign({}, DEFAULTS, S.defaults || {}, stored);
  applySettings();
}

function saveSettings() {
  try { localStorage.setItem('m5rp_settings', JSON.stringify(S.settings)); } catch (e) {}
  applySettings();
  post('settings', { settings: S.settings });
}

function applySettings() {
  const root = document.documentElement;
  if (S.settings.teamColorA) root.style.setProperty('--team-a', S.settings.teamColorA);
  if (S.settings.teamColorB) root.style.setProperty('--team-b', S.settings.teamColorB);
  $('killfeed').classList.toggle('left', S.settings.killFeedPos === 'left');
  $('hud').style.transform = `scale(${(S.settings.hudSize || 100) / 100})`;
  $('hud-ping').style.display = S.settings.showPing === false ? 'none' : '';
  document.body.classList.toggle('lowspec', !!S.settings.lowSpecMode);
}

/* ================================================================= ADMIN */
function renderAdmin(d) {
  if (!d) return;
  S.admin = d;
  const host = $('admin-root');

  const list = (rows, render, empty) =>
    rows && rows.length ? rows.map(render).join('') : `<div class="party-empty">${empty}</div>`;

  host.innerHTML = `
    <div class="panel">
      <span class="panel-tag">LIVE MATCHES · ${(d.matches || []).length}</span>
      <div class="alist">${list(d.matches, (m) => `
        <div class="arow">
          <b>${esc(m.mode)}</b><span>${esc(m.map)}</span>
          <span class="grow">${esc(m.state)} · R${m.round} · ${m.scores.a}-${m.scores.b} · ${m.players}P</span>
          <button data-admin="spectate" data-match="${esc(m.id)}">SPECTATE</button>
          <button data-admin="restartRound" data-match="${esc(m.id)}">RESTART</button>
          <button data-admin="endMatch" data-match="${esc(m.id)}">END</button>
        </div>`, 'NO LIVE MATCHES')}</div>
    </div>

    <div class="panel">
      <span class="panel-tag">SEARCHING · ${(d.searching || []).length}</span>
      <div class="alist">${list(d.searching, (p) => `
        <div class="arow"><b>${esc(p.name)}</b><span class="grow">${esc(p.mode)} · ${esc(p.rank)} · MMR ${p.mmr}</span>
        <span>${p.waited}s</span></div>`, 'QUEUE EMPTY')}</div>
    </div>

    <div class="panel">
      <span class="panel-tag">SUSPICIOUS PLAYERS</span>
      <div class="alist">${list(d.suspicious, (f) => `
        <div class="arow"><b>${esc(f.name || f.user_id)}</b>
          <span class="grow">${f.flags} flags</span>
          <span class="sev">SEV ${f.score}</span>
          <button data-admin="lookup" data-target="${f.user_id}">INSPECT</button>
        </div>`, 'NOTHING FLAGGED')}</div>
    </div>

    <div class="panel">
      <span class="panel-tag">ACTIVE RANKED BANS</span>
      <div class="alist">${list(d.bans, (b) => `
        <div class="arow"><b>${esc(b.name || b.user_id)}</b>
          <span>${esc(b.type)}</span>
          <span class="grow">${esc(b.reason)}</span>
          <button data-admin="unban" data-target="${b.user_id}" data-ban="${b.id}">UNBAN</button>
        </div>`, 'NO ACTIVE BANS')}</div>
    </div>

    <div class="panel">
      <span class="panel-tag">CUSTOM ROOMS · ${(d.rooms || []).length}</span>
      <div class="alist">${list(d.rooms, (r) => `
        <div class="arow"><b>${esc(r.name)}</b><span class="grow">${esc(r.host)} · ${r.players}P · ${esc(r.state)}</span>
        <button data-admin="closeRoom" data-room="${esc(r.id)}">CLOSE</button></div>`, 'NO ROOMS')}</div>
    </div>

    <div class="panel">
      <span class="panel-tag">PLAYER TOOLS</span>
      <div class="field"><label>TARGET (ID OR NAME)</label><input class="input" id="adm-target" placeholder="e.g. 42"/></div>
      <div class="admin-tools" style="margin-top:12px">
        <div class="field"><label>SET RP</label><input class="input" id="adm-rp" type="number" placeholder="1500"/></div>
        <div class="field"><label>SET RANK ID</label><input class="input" id="adm-rank" type="number" placeholder="0-23"/></div>
        <div class="field"><label>BAN MINUTES (0 = PERM)</label><input class="input" id="adm-dur" type="number" value="60"/></div>
        <div class="field"><label>REASON</label><input class="input" id="adm-reason" placeholder="Reason"/></div>
      </div>
      <div style="display:flex;flex-wrap:wrap;gap:8px;margin-top:14px">
        <button class="btn btn-sm" data-admin="setRP">SET RP</button>
        <button class="btn btn-sm" data-admin="setRank">SET RANK</button>
        <button class="btn btn-sm btn-ghost" data-admin="lookupInput">LOOKUP</button>
        <button class="btn btn-sm btn-ghost" data-admin="resetStats">RESET STATS</button>
        <button class="btn btn-sm btn-danger" data-admin="ban">RANK BAN</button>
        <button class="btn btn-sm btn-ghost" data-admin="unbanInput">UNBAN</button>
        <button class="btn btn-sm btn-ghost" data-admin="newSeason">NEW SEASON</button>
      </div>
    </div>

    <div class="panel">
      <span class="panel-tag">SEASONS</span>
      <div class="alist">${list(d.seasons, (s) => `
        <div class="arow"><b>#${s.number} ${esc(s.name)}</b>
          <span class="grow">${esc(String(s.start_at || '').slice(0, 10))} → ${esc(String(s.end_at || '').slice(0, 10))}</span>
          <span>${s.active ? 'ACTIVE' : 'ARCHIVED'}</span></div>`, 'NO SEASONS')}</div>
    </div>`;

  host.querySelectorAll('[data-admin]').forEach((b) => { b.onclick = () => adminAction(b); });
}

function adminAction(btn) {
  const a = btn.dataset.admin;
  const target = ($('adm-target') && $('adm-target').value) || btn.dataset.target;

  const map = {
    spectate:     () => post('admin', { action: 'spectate', matchId: btn.dataset.match }),
    restartRound: () => post('admin', { action: 'restartRound', matchId: btn.dataset.match }),
    endMatch:     () => post('admin', { action: 'endMatch', matchId: btn.dataset.match }),
    closeRoom:    () => post('admin', { action: 'closeRoom', roomId: btn.dataset.room }),
    lookup:       () => post('admin', { action: 'playerLookup', target: btn.dataset.target }),
    lookupInput:  () => post('admin', { action: 'playerLookup', target }),
    unban:        () => post('admin', { action: 'unban', target: btn.dataset.target, banId: btn.dataset.ban }),
    unbanInput:   () => post('admin', { action: 'unban', target }),
    resetStats:   () => post('admin', { action: 'resetStats', target }),
    newSeason:    () => post('admin', { action: 'newSeason' }),
    setRP:        () => post('admin', { action: 'setRP', target, value: parseInt($('adm-rp').value, 10) }),
    setRank:      () => post('admin', { action: 'setRank', target, rankId: parseInt($('adm-rank').value, 10) }),
    ban:          () => post('admin', {
      action: 'ban', target,
      duration: (parseInt($('adm-dur').value, 10) || 0) * 60,
      reason: $('adm-reason').value, type: 'RANKED'
    })
  };
  if (map[a]) { Audio_.play('click'); map[a](); }
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

  // the local player's own side is always shown on the left
  const flip = d.team === 2;
  $('hud-score-a').style.color = flip ? 'var(--team-b)' : 'var(--team-a)';
  $('hud-score-b').style.color = flip ? 'var(--team-a)' : 'var(--team-b)';
}

function updateTimer() {
  const node = $('hud-timer');
  node.textContent = clock(S.hudTime);
  node.classList.toggle('low', S.hudTime <= 15 && S.hudTime > 0);
}

function renderLocalHud(d) {
  if (!d) return;
  const hp = Math.max(0, Math.min(100, d.health));
  $('hud-hp').textContent = hp;
  $('hud-hp-bar').style.width = hp + '%';
  $('hud-ar').textContent = d.armor;
  $('hud-ar-bar').style.width = Math.max(0, Math.min(100, d.armor)) + '%';
  $('hud-weapon-name').textContent = (d.weapon || '').replace('WEAPON_', '');
  $('hud-clip').textContent = d.clip;
  $('hud-ammo').textContent = d.ammo;
}

function addKillFeed(d) {
  const host = $('killfeed');
  const meName = S.boot && S.boot.player && S.boot.player.name;
  const mine = d.killer === meName || d.victim === meName;

  const teamCls = (t) => (t === 1 ? 'n-a' : 'n-b');
  const node = el('div', 'kf' + (mine ? ' mine' : ''),
    `${d.killer ? `<span class="${teamCls(d.killerTeam)}">${esc(d.killer)}</span>` : ''}
     <span class="kf-w">${esc((d.weapon || '').replace('WEAPON_', ''))}</span>
     ${d.headshot ? '<span class="kf-hs"><svg><use href="#ico-head"/></svg>HS</span>' : ''}
     <span class="${teamCls(d.victimTeam)}">${esc(d.victim)}</span>`);

  host.appendChild(node);
  while (host.children.length > 6) host.removeChild(host.firstChild);

  setTimeout(() => { if (node.parentNode) node.remove(); }, 6000);

  if (S.settings.killSounds !== false && d.killer === meName) {
    Audio_.play(d.headshot ? 'headshot' : 'kill');
  }
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
  const key = d.type.replace('_', '');
  let text = EVENT_TEXT[d.type] || EVENT_TEXT[key] || d.type.replace(/_/g, ' ');
  if (d.extra && typeof d.extra === 'number') text += ` ${d.extra}`;
  if (d.player) text = `${d.player.toUpperCase()} · ${text}`;

  $('combat-banner-text').textContent = text;
  banner.classList.remove('hidden');
  clearTimeout(showEvent._t);
  showEvent._t = setTimeout(() => banner.classList.add('hidden'), 2600);

  if (d.type === 'ACE' || d.type === 'CLUTCH') Audio_.play('rankup');
  else if (d.type === 'AFK_WARNING') Audio_.play('warning');
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
      if (n > 0) {
        node.textContent = n;
        node.classList.remove('go');
        Audio_.play('tick');
      } else {
        node.textContent = 'GO';
        node.classList.add('go');
        Audio_.play('go');
        setTimeout(() => phase.classList.add('hidden'), 900);
        clearInterval(renderRound._t);
      }
      n -= 1;
    };
    clearInterval(renderRound._t);
    step();
    renderRound._t = setInterval(step, 1000);

  } else if (d.phase === 'end') {
    phase.classList.remove('hidden');
    const won = d.winner === d.myTeam;
    $('phase-count').textContent = d.winner === 0 ? 'DRAW' : (won ? 'ROUND WON' : 'ROUND LOST');
    $('phase-count').style.fontSize = '58px';
    $('phase-count').classList.toggle('go', won);
    $('phase-label').textContent = `${d.scores.a} — ${d.scores.b}`;
    Audio_.play(won ? 'roundwin' : 'roundloss');
    setTimeout(() => {
      phase.classList.add('hidden');
      $('phase-count').style.fontSize = '';
    }, 4200);

  } else if (d.phase === 'live') {
    phase.classList.add('hidden');
  }
}

function renderMatchEnd(d) {
  if (!d) return;
  const modal = $('modal-result');
  const root = $('result-root');
  modal.classList.remove('hidden');

  const lost = d.result === 'DEFEAT';
  root.classList.toggle('defeat', lost);
  root.classList.toggle('draw', d.result === 'DRAW');

  $('result-tag').textContent = d.result;
  $('result-a').textContent = d.yourTeam === 2 ? d.scores.b : d.scores.a;
  $('result-b').textContent = d.yourTeam === 2 ? d.scores.a : d.scores.b;

  // RP block
  const rpBlock = $('result-rp');
  if (d.rp && d.ranked) {
    rpBlock.classList.remove('hidden');
    if (d.rp.placement) {
      $('rp-rank').textContent = 'PLACEMENT MATCHES';
      $('rp-before').textContent = d.rp.played;
      $('rp-after').textContent = d.rp.total;
      $('rp-delta').textContent = `${d.rp.total - d.rp.played} REMAINING`;
      $('rp-delta').classList.remove('neg');
      $('rp-bar-fill').style.width = (d.rp.played / Math.max(1, d.rp.total)) * 100 + '%';
      $('rp-breakdown').innerHTML = '';
    } else {
      $('rp-rank').textContent = (d.rank && d.rank.after || '').toUpperCase();
      $('rp-rank').style.color = (d.rank && d.rank.color) || '';
      countUp($('rp-before'), d.rp.before, d.rp.before, 0);
      countUp($('rp-after'), d.rp.before, d.rp.after, 900);
      $('rp-delta').textContent = `${d.rp.delta > 0 ? '+' : ''}${d.rp.delta} RP`;
      $('rp-delta').classList.toggle('neg', d.rp.delta < 0);
      $('rp-bar-fill').style.width = ((d.rank && d.rank.progress && d.rank.progress.percent) || 0) + '%';

      const b = d.rp.breakdown || {};
      $('rp-breakdown').innerHTML = Object.keys(b).map((k) =>
        `<span>${k.toUpperCase()} ${b[k] > 0 ? '+' : ''}${b[k]}</span>`).join('');
    }
  } else {
    rpBlock.classList.add('hidden');
  }

  // personal stats
  const s = d.stats || {};
  $('result-stats').innerHTML = `
    <div><b>${s.kills || 0}</b><span>KILLS</span></div>
    <div><b>${s.deaths || 0}</b><span>DEATHS</span></div>
    <div><b>${s.assists || 0}</b><span>ASSISTS</span></div>
    <div><b>${s.headshots || 0}</b><span>HEADSHOTS</span></div>
    <div><b>${num(s.damage || 0)}</b><span>DAMAGE</span></div>
    <div><b>${s.clutches || 0}</b><span>CLUTCHES</span></div>`;

  // scoreboard
  const board = d.scoreboard || [];
  const rows = (team) => board.filter((p) => p.team === team).map((p) => `
    <div class="brow">
      <span class="pos"></span>
      <span class="pname">${esc(p.name)}</span>
      <span class="prank">${esc(p.rank || '')}</span>
      <span>${p.kills}/${p.deaths}/${p.assists}</span>
      <span>${p.headshots}</span>
      <span>${num(p.damage)}</span>
      <span>${p.score}</span>
    </div>`).join('');

  $('result-scoreboard').innerHTML = `
    <div class="board-head"><span></span><span>PLAYER</span><span>RANK</span><span>K/D/A</span><span>HS</span><span>DMG</span><span>SCORE</span></div>
    <div class="teamcol a"><h4>TEAM A</h4>${rows(1)}</div>
    <div class="teamcol b" style="margin-top:10px"><h4>TEAM B</h4>${rows(2)}</div>`;

  Audio_.play(lost ? 'defeat' : 'victory');

  // MVP → then rank change
  const afterResult = () => {
    if (d.mvp) {
      showMVP(d.mvp, () => maybeRankChange(d));
    } else {
      maybeRankChange(d);
    }
  };
  setTimeout(afterResult, 2600);
}

function maybeRankChange(d) {
  if (!d.rank || (!d.rank.up && !d.rank.down)) return;
  const modal = $('modal-rank');
  const root = $('rankup-root');
  modal.classList.remove('hidden');
  root.classList.toggle('down', !!d.rank.down);
  $('rankup-tag').textContent = d.rank.up ? 'RANK UP' : 'RANK DOWN';
  $('rankup-name').textContent = (d.rank.after || '').toUpperCase();
  $('rankup-sub').textContent = d.rank.up ? 'NEW RANK' : 'DEMOTED';
  $('rankup-crest').innerHTML = crest(
    (S.boot && S.boot.ranks || []).find((r) => r.id === d.rank.id)?.tier || 'IRON',
    d.rank.color);
  Audio_.play(d.rank.up ? 'rankup' : 'rankdown');
  setTimeout(() => modal.classList.add('hidden'), 5200);
}

function showMVP(mvp, done) {
  const modal = $('modal-mvp');
  modal.classList.remove('hidden');
  $('mvp-name').textContent = (mvp.name || '').toUpperCase();
  $('mvp-kills').textContent = mvp.kills;
  $('mvp-deaths').textContent = mvp.deaths;
  $('mvp-hs').textContent = mvp.headshots;
  $('mvp-dmg').textContent = num(mvp.damage);
  Audio_.play('rankup');
  setTimeout(() => { modal.classList.add('hidden'); if (done) done(); }, 4600);
}

function countUp(node, from, to, duration) {
  if (!duration) { node.textContent = num(to); return; }
  const start = performance.now();
  const diff = to - from;
  const step = (now) => {
    const t = Math.min(1, (now - start) / duration);
    const eased = 1 - Math.pow(1 - t, 3);
    node.textContent = num(Math.round(from + diff * eased));
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
  if (kind === 'error') Audio_.play('error');
  else if (kind === 'warning') Audio_.play('warning');
  return node;
}

/* ============================================================ NUI EVENTS */
window.addEventListener('message', (event) => {
  const d = event.data || {};

  switch (d.action) {
    case 'open':
      S.theme = d.theme; S.text = d.text || {};
      if (d.defaults) S.defaults = Object.assign({}, DEFAULTS, d.defaults);
      $('app').classList.remove('hidden');
      if (!d.silent) Audio_.play('open');
      if (d.page) showPage(d.page === 'matchEnd' ? S.page : d.page);
      break;

    case 'close':
      $('app').classList.add('hidden');
      $('modal-found').classList.add('hidden');
      $('modal-mapvote').classList.add('hidden');
      $('modal-result').classList.add('hidden');
      Audio_.play('close');
      break;

    case 'boot':        renderBoot(d.data); break;
    case 'toast':       toast(d.kind, d.message, d.title); break;
    case 'queue':       renderQueue(d.data); break;
    case 'matchFound':  renderFound(d.data); break;
    case 'mapVote':     renderMapVote(d.data); break;
    case 'party':       renderParty(d.data); break;

    case 'custom':
      if (d.data && d.data.list) renderRooms(d.data.list);
      if (d.data && d.data.room !== undefined) renderRoom(d.data.room || null);
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
        else if (p.action === 'playerLookup') showLookup(p.result);
        else { toast('success', 'Action applied.', 'ADMIN'); post('admin', { action: 'dashboard' }); }
      }
      break;
    }

    case 'matchSetup':
      S.match = d.data;
      $('hud').classList.remove('hidden');
      $('killfeed').innerHTML = '';
      break;

    case 'hud':         renderHud(d.data); break;
    case 'localHud':    renderLocalHud(d.data); break;
    case 'killfeed':    addKillFeed(d.data); break;
    case 'event':       showEvent(d.data); break;
    case 'round':       renderRound(d.data); break;
    case 'matchEnd':    renderMatchEnd(d.data); break;

    case 'matchCleanup':
      $('hud').classList.add('hidden');
      $('killfeed').innerHTML = '';
      $('phase').classList.add('hidden');
      $('boundary').classList.add('hidden');
      $('spectate').classList.add('hidden');
      $('combat-banner').classList.add('hidden');
      S.match = null; S.hud = null;
      break;

    case 'hudVisible':
      $('hud').classList.toggle('hidden', !d.value);
      break;

    case 'boundary': {
      const node = $('boundary');
      node.classList.toggle('hidden', !d.active);
      if (d.active) {
        $('boundary-count').textContent = d.seconds;
        $('boundary-dist').textContent = `${d.distance}m OUTSIDE THE ZONE`;
        if (d.seconds <= 3) Audio_.play('tick');
      }
      break;
    }

    case 'spectate': {
      const node = $('spectate');
      node.classList.toggle('hidden', !(d.data && d.data.active));
      if (d.data && d.data.active) {
        $('spectate-name').textContent = d.data.overview ? 'OVERVIEW CAMERA'
          : `${d.data.name} (${d.data.index || 1}/${d.data.total || 1})`;
      }
      break;
    }

    case 'training': {
      const node = $('training');
      const t = d.data || {};
      node.classList.toggle('hidden', !t.active);
      if (t.active) {
        if (t.label) $('training-title').textContent = t.label;
        if (t.hits !== undefined) {
          $('training-hits').textContent = t.hits;
          $('training-hs').textContent = t.headshots;
          $('training-acc').textContent = t.accuracy + '%';
          $('training-time').textContent = t.elapsed + 's';
        }
      }
      break;
    }

    case 'death':
      if (d.data && d.data.killer) {
        toast('error',
          `${d.data.killer}${d.data.headshot ? ' · HEADSHOT' : ''}`,
          'ELIMINATED', 3600);
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

    case 'damaged':
      document.body.animate(
        [{ filter: 'none' }, { filter: 'saturate(.6) brightness(1.12)' }, { filter: 'none' }],
        { duration: 180 });
      break;
  }
});

function showLookup(p) {
  if (!p) { toast('error', 'Player not found.', 'ADMIN'); return; }
  S.profile = p;
  showPage('profile');
  toast('info', `Inspecting ${p.name}`, 'ADMIN');
}

/* ============================================================== BINDINGS */
document.addEventListener('click', (e) => {
  const rail = e.target.closest('.rail-btn');
  if (rail) { Audio_.play('click'); showPage(rail.dataset.page); return; }

  const tab = e.target.closest('#lb-tabs .tab');
  if (tab) {
    document.querySelectorAll('#lb-tabs .tab').forEach((t) => t.classList.remove('active'));
    tab.classList.add('active');
    S.lb.board = tab.dataset.board;
    S.lb.page = 1;
    Audio_.play('click');
    fetchBoard();
    return;
  }

  const roomBtn = e.target.closest('[data-room-act]');
  if (roomBtn) {
    const act = roomBtn.dataset.roomAct;
    Audio_.play('click');
    if (act === 'leave') post('custom', { action: 'leave' });
    else if (act === 'start') post('custom', { action: 'start' });
    else if (act === 'stop') post('custom', { action: 'stop' });
    else if (act === 'lock') post('custom', { action: 'lock', value: !(S.room && S.room.locked) });
    else if (act === 'kick') post('custom', { action: 'kick', userId: parseInt(roomBtn.dataset.user, 10) });
    else if (act === 'ban') post('custom', { action: 'ban', userId: parseInt(roomBtn.dataset.user, 10) });
    else if (act === 'move') post('custom', {
      action: 'move', userId: parseInt(roomBtn.dataset.user, 10),
      team: parseInt(roomBtn.dataset.team, 10)
    });
    else if (act === 'apply') applyRoomSettings();
    return;
  }

  const act = e.target.closest('[data-action]');
  if (!act) return;
  const a = act.dataset.action;
  Audio_.play('click');

  switch (a) {
    case 'close': post('close'); break;
    case 'queue-cancel': post('queue', { action: 'leave' }); break;
    case 'party-invite': {
      const t = $('party-target').value.trim();
      if (t) { post('party', { action: 'invite', target: t }); $('party-target').value = ''; }
      break;
    }
    case 'party-ready': post('party', { action: 'ready', value: true }); break;
    case 'party-leave': post('party', { action: 'leave' }); break;
    case 'custom-refresh': post('custom', { action: 'list' }); break;
    case 'custom-create-open': renderCreateBox(); break;
    case 'custom-cancel':
      $('createbox').classList.add('hidden');
      $('rooms-panel').classList.remove('hidden');
      break;
    case 'custom-create':
      post('custom', {
        action: 'create',
        name: $('cg-name').value,
        password: $('cg-pass').value,
        mode: $('cg-mode').value,
        map: $('cg-map').value,
        rounds: parseInt($('cg-rounds').value, 10),
        roundTime: parseInt($('cg-roundtime').value, 10),
        friendlyFire: $('cg-ff').checked,
        headshotOneShot: $('cg-hs').checked,
        respawn: $('cg-respawn').checked,
        autoStart: $('cg-auto').checked
      });
      $('createbox').classList.add('hidden');
      break;
    case 'lb-prev': if (S.lb.page > 1) { S.lb.page -= 1; fetchBoard(); } break;
    case 'lb-next': S.lb.page += 1; fetchBoard(); break;
    case 'hist-prev':
      if (S.hist.page > 1) { S.hist.page -= 1; post('fetch', { what: 'history', page: S.hist.page }); }
      break;
    case 'hist-next':
      S.hist.page += 1; post('fetch', { what: 'history', page: S.hist.page });
      break;
    case 'detail-close': $('matchdetail').classList.add('hidden'); break;
    case 'result-close': $('modal-result').classList.add('hidden'); post('close'); break;
    case 'stop-training': post('action', { action: 'training', enable: false }); break;
    case 'admin-refresh': post('admin', { action: 'dashboard' }); break;
    case 'admin-freeze':
      post('admin', { action: 'freeze', value: !(S.admin && S.admin.frozen) });
      break;
    case 'settings-reset':
      S.settings = Object.assign({}, DEFAULTS, S.defaults);
      saveSettings();
      renderSettings();
      break;
  }
});

function applyRoomSettings() {
  const settings = {};
  document.querySelectorAll('[data-setting]').forEach((input) => {
    settings[input.dataset.setting] =
      input.type === 'checkbox' ? input.checked : parseFloat(input.value);
  });
  post('custom', { action: 'settings', settings });

  const mode = document.querySelector('[data-setting-mode]');
  const map = document.querySelector('[data-setting-map]');
  if (mode && S.room && mode.value !== S.room.mode) post('custom', { action: 'mode', mode: mode.value });
  if (map && S.room && map.value !== S.room.map) post('custom', { action: 'map', map: map.value });
}

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    if (!$('modal-result').classList.contains('hidden')) {
      $('modal-result').classList.add('hidden');
    }
    post('close');
  }
  if (e.key === 'Enter' && S.found) $('btn-accept').click();
});

document.addEventListener('mouseover', (e) => {
  if (e.target.closest('.btn') || e.target.closest('.tab')) Audio_.play('hover');
}, { passive: true });

/* One shared 1 Hz timer drives every in-match countdown. */
setInterval(() => {
  if (S.hudTime > 0) { S.hudTime -= 1; updateTimer(); }
  if (S.queue.state === 'SEARCHING') {
    const node = $('search-elapsed');
    const parts = node.textContent.split(':');
    const secs = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10) + 1;
    node.textContent = clockLong(secs);
  }
}, 1000);

loadSettings();
