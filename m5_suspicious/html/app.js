/* ============================================================
   m5_suspicious - NUI controller

   SECURITY NOTE
   Player names, licenses and Discord tags are attacker-controlled
   strings. Nothing from the server is ever written with innerHTML;
   every value goes through textContent so a player called
   "<img src=x onerror=...>" cannot inject anything into an admin's
   panel. Keep it that way when editing this file.
   ============================================================ */

const RES = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName() : 'm5_suspicious';

const post = (name, data = {}) =>
    fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).catch(() => {});

/* ---------- tiny DOM helper (textContent only) ---------- */

function el(tag, cls, text) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = String(text);
    return n;
}

const $ = (id) => document.getElementById(id);

/* ---------- state ---------- */

const S = {
    entries: [],
    filtered: [],
    selected: null,
    page: 1,
    pageSize: 10,
    filter: 'all',
    search: '',
    locale: {},
    durations: [],
    pending: null,          // { action, entry }
    durationIndex: 1,
};

const T = (k) => S.locale[k] || k;

const LEVELS = { LOW: 'low', MEDIUM: 'medium', HIGH: 'high', CRITICAL: 'critical' };
const lvlVar = (level) => `var(--${LEVELS[level] || 'low'})`;

/* ============================================================
   Alerts
   ============================================================ */

function renderAlert(d, seconds) {
    const box = $('alerts');
    const card = el('div', 'alert' + (d.critical ? ' critical' : ''));
    card.style.setProperty('--lvl', lvlVar(d.level));

    const head = el('div', 'alert-head');
    head.appendChild(el('span', 'tag', T('alert_title')));
    head.appendChild(el('span', 'name', d.name || '?'));
    head.appendChild(el('span', 'score', `${d.score}/100`));
    card.appendChild(head);

    const grid = el('div', 'alert-grid');
    const pair = (k, v, cls) => {
        grid.appendChild(el('span', 'k', k));
        grid.appendChild(el('span', 'v' + (cls ? ' ' + cls : ''), v));
    };
    pair(T('row_server_id'), d.serverId ?? '-');
    pair(T('row_user_id'), d.userId ?? '-');
    pair(T('row_vpn'), yesNoText(d.vpn));
    pair(T('row_new'), yesNoText(d.newAcc));
    pair(T('row_shared_ip'), d.sharedIP ?? 0);
    pair(T('row_shared_hwid'), d.sharedHW ?? 0);
    if (d.discord) pair(T('row_discord'), d.discord);
    if (d.fivem) pair(T('row_fivem'), d.fivem);
    card.appendChild(grid);

    const bar = el('div', 'bar');
    const fill = el('i');
    fill.style.animationDuration = seconds + 's';
    bar.appendChild(fill);
    card.appendChild(bar);

    box.appendChild(card);

    setTimeout(() => {
        card.classList.add('out');
        setTimeout(() => card.remove(), 260);
    }, seconds * 1000);

    // Never let a flood of alerts cover the screen.
    while (box.children.length > 5) box.firstChild.remove();
}

function yesNoText(v) {
    if (v === 1 || v === true) return T('alert_yes');
    if (v === 0 || v === false) return T('alert_no');
    return T('alert_unknown');
}

function yesNoClass(v) {
    if (v === 1 || v === true) return 'yes';
    if (v === 0 || v === false) return 'no';
    return 'unk';
}

/* ============================================================
   List
   ============================================================ */

function applyFilter() {
    const q = S.search.trim().toLowerCase();

    S.filtered = S.entries.filter((e) => {
        if (S.filter === 'pending'  && e.status !== 'pending') return false;
        if (S.filter === 'critical' && e.level !== 'CRITICAL') return false;
        if (S.filter === 'high'     && e.level !== 'HIGH' && e.level !== 'CRITICAL') return false;
        if (S.filter === 'online'   && !e.online) return false;

        if (!q) return true;
        return [e.name, e.userId, e.serverId, e.discord, e.fivem]
            .some((v) => v !== undefined && v !== null && String(v).toLowerCase().includes(q));
    });

    const pages = Math.max(1, Math.ceil(S.filtered.length / S.pageSize));
    if (S.page > pages) S.page = pages;
}

function renderFilters() {
    const bar = $('filters');
    bar.textContent = '';

    const defs = [
        ['all',      T('filter_all'),      S.entries.length],
        ['pending',  T('filter_pending'),  S.entries.filter((e) => e.status === 'pending').length],
        ['high',     T('filter_high'),     S.entries.filter((e) => e.level === 'HIGH' || e.level === 'CRITICAL').length],
        ['critical', T('filter_critical'), S.entries.filter((e) => e.level === 'CRITICAL').length],
        ['online',   T('filter_online'),   S.entries.filter((e) => e.online).length],
    ];

    for (const [key, label, count] of defs) {
        const chip = el('button', 'chip' + (S.filter === key ? ' active' : ''), label);
        chip.appendChild(el('span', 'count', count));
        chip.onclick = () => { S.filter = key; S.page = 1; render(); };
        bar.appendChild(chip);
    }
}

function renderList() {
    const list = $('list');
    list.textContent = '';

    const start = (S.page - 1) * S.pageSize;
    const slice = S.filtered.slice(start, start + S.pageSize);

    for (const e of slice) {
        const row = el('div', 'row' + (S.selected && S.selected.id === e.id ? ' active' : '')
                                    + (e.status !== 'pending' ? ' handled' : ''));
        row.style.setProperty('--lvl', lvlVar(e.level));

        row.appendChild(el('span', 'dot'));

        const meta = el('div', 'meta');
        meta.appendChild(el('div', 'n', e.name || '?'));
        meta.appendChild(el('div', 's', `#${e.serverId ?? '-'} · UID ${e.userId ?? '-'}`));
        row.appendChild(meta);

        if (e.online) row.appendChild(el('span', 'live'));
        row.appendChild(el('span', 'sc', e.score));

        row.onclick = () => { S.selected = e; render(); };
        list.appendChild(row);
    }

    const pages = Math.max(1, Math.ceil(S.filtered.length / S.pageSize));
    $('page-label').textContent = `${S.page} / ${pages}`;
    $('page-prev').disabled = S.page <= 1;
    $('page-next').disabled = S.page >= pages;
}

/* ============================================================
   Detail
   ============================================================ */

function ring(score, level) {
    const wrap = el('div', 'ring');
    wrap.style.setProperty('--lvl', lvlVar(level));

    const NS = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('width', '92');
    svg.setAttribute('height', '92');
    svg.setAttribute('viewBox', '0 0 92 92');

    const r = 40, c = 2 * Math.PI * r;
    for (const cls of ['track', 'fill']) {
        const circle = document.createElementNS(NS, 'circle');
        circle.setAttribute('class', cls);
        circle.setAttribute('cx', '46');
        circle.setAttribute('cy', '46');
        circle.setAttribute('r', String(r));
        circle.setAttribute('fill', 'none');
        circle.setAttribute('stroke-width', '6');
        if (cls === 'fill') {
            const v = Math.max(0, Math.min(100, score)) / 100;
            circle.setAttribute('stroke-dasharray', `${(c * v).toFixed(1)} ${c.toFixed(1)}`);
        }
        svg.appendChild(circle);
    }

    wrap.appendChild(svg);
    wrap.appendChild(el('div', 'val', score));
    return wrap;
}

function renderDetail() {
    const empty = $('detail-empty');
    const body  = $('detail-body');
    const e     = S.selected;

    if (!e) {
        empty.classList.remove('hidden');
        body.classList.add('hidden');
        return;
    }

    empty.classList.add('hidden');
    body.classList.remove('hidden');
    body.textContent = '';

    /* ---- header ---- */
    const head = el('div', 'd-head');
    head.appendChild(ring(e.score, e.level));

    const id = el('div', 'd-id');
    id.appendChild(el('h2', null, e.name || '?'));
    id.appendChild(el('div', 'sub', `Server ID ${e.serverId ?? '-'}  ·  User ID ${e.userId ?? '-'}`));
    const lvl = el('span', 'lvl', e.level);
    lvl.style.setProperty('--lvl', lvlVar(e.level));
    id.appendChild(lvl);
    head.appendChild(id);
    body.appendChild(head);

    /* ---- reasons ---- */
    if (e.reasons && e.reasons.length) {
        body.appendChild(el('div', 'section-title', T('section_reasons')));
        const wrap = el('div', 'reasons');
        for (const r of e.reasons) wrap.appendChild(el('span', 'reason', r));
        body.appendChild(wrap);
    }

    /* ---- data grid ---- */
    body.appendChild(el('div', 'section-title', T('section_identity')));
    const grid = el('div', 'grid');

    const cell = (k, v, cls) => {
        const c = el('div', 'cell');
        c.appendChild(el('div', 'k', k));
        c.appendChild(el('div', 'v' + (cls ? ' ' + cls : ''), (v === null || v === undefined || v === '') ? '-' : v));
        grid.appendChild(c);
    };

    cell(T('row_vpn'), yesNoText(e.vpn), yesNoClass(e.vpn));
    cell(T('row_new'), yesNoText(e.newAcc), yesNoClass(e.newAcc));
    cell(T('row_shared_ip'), e.sharedIP);
    cell(T('row_shared_hwid'), e.sharedHW);
    cell(T('row_tokens'), e.tokens);
    cell(T('row_ip'), e.ip);
    cell(T('row_license'), e.license);
    cell(T('row_discord'), e.discord);
    cell(T('row_fivem'), e.fivem);
    cell(T('row_steam'), e.steam);
    cell(T('row_location'), e.location);
    cell(T('row_first_seen'), e.firstSeen);
    cell(T('row_status'), `${e.status} (${e.handledBy})`);
    cell(T('row_online'), yesNoText(e.online), e.online ? 'no' : 'unk');

    body.appendChild(grid);

    /* ---- actions ---- */
    const actions = el('div', 'actions');

    const mk = (label, cls, fn) => {
        const b = el('button', 'btn ' + cls, label);
        b.onclick = fn;
        actions.appendChild(b);
    };

    mk(T('menu_ban_hwid'),    'btn-danger', () => openModal('ban_hwid', e));
    mk(T('menu_ban_license'), 'btn-danger', () => openModal('ban_license', e));
    mk(T('menu_ban_player'),  'btn-danger', () => openModal('ban_player', e));
    mk(T('menu_ignore'),      'btn-ok',     () => post('action', { id: e.id, action: 'ignore' }));
    mk(T('menu_refresh'),     'btn-ghost',  () => post('refresh'));

    body.appendChild(actions);
}

function render() {
    applyFilter();
    renderFilters();
    renderList();
    renderDetail();

    $('t-subtitle').textContent =
        `${S.filtered.length} / ${S.entries.length} ${T('subtitle_records')}`;
}

/* ============================================================
   Modal
   ============================================================ */

function openModal(action, entry) {
    S.pending = { action, entry };
    S.durationIndex = 1;

    $('modal-title').textContent  = T('menu_' + action);
    $('modal-target').textContent = `${entry.name || '?'}  ·  UID ${entry.userId ?? '-'}`;
    $('modal-reason').value = '';

    const chips = $('modal-durations');
    chips.textContent = '';
    S.durations.forEach((label, i) => {
        const chip = el('button', 'chip' + (i === 0 ? ' active' : ''), label);
        chip.onclick = () => {
            S.durationIndex = i + 1;
            [...chips.children].forEach((c, j) => c.classList.toggle('active', j === i));
        };
        chips.appendChild(chip);
    });

    // A license ban has no token duration picker distinction, but the server
    // applies the same expiry to both, so the control stays meaningful.
    $('modal').parentElement.classList.remove('hidden');
    setTimeout(() => $('modal-reason').focus(), 50);
}

function closeModal() {
    $('modal').parentElement.classList.add('hidden');
    S.pending = null;
}

function confirmModal() {
    if (!S.pending) return;
    post('action', {
        id: S.pending.entry.id,
        action: S.pending.action,
        reason: $('modal-reason').value,
        duration: S.durationIndex,
    });
    closeModal();
}

/* ============================================================
   Wiring
   ============================================================ */

$('btn-close').onclick   = () => post('close');
$('btn-refresh').onclick = () => post('refresh');
$('page-prev').onclick   = () => { if (S.page > 1) { S.page--; render(); } };
$('page-next').onclick   = () => { S.page++; render(); };

$('search').oninput = (ev) => { S.search = ev.target.value; S.page = 1; render(); };

$('modal-cancel').onclick  = closeModal;
$('modal-confirm').onclick = confirmModal;

$('modal-reason').onkeydown = (ev) => {
    if (ev.key === 'Enter') confirmModal();
    ev.stopPropagation();
};

document.onkeydown = (ev) => {
    if (ev.key !== 'Escape') return;
    if (!$('modal').parentElement.classList.contains('hidden')) closeModal();
    else post('close');
};

/* ---------- messages from client.lua ---------- */

window.addEventListener('message', (ev) => {
    const msg = ev.data || {};

    if (msg.action === 'theme') {
        const root = document.documentElement;
        for (const [key, value] of Object.entries(msg.theme || {})) {
            // Only accept simple colour tokens, never arbitrary CSS.
            if (/^[a-z0-9-]+$/i.test(key) && /^[#a-z0-9(),.\s%-]+$/i.test(String(value))) {
                root.style.setProperty('--' + key, value);
            }
        }
        document.body.dir = msg.dir === 'rtl' ? 'rtl' : 'ltr';
        document.documentElement.dir = document.body.dir;
        $('alerts').className = 'alerts pos-' + (msg.alertPosition || 'top-right');
        return;
    }

    if (msg.action === 'locale') {
        S.locale = msg.locale || {};
        S.durations = msg.durations || [];
        S.pageSize = msg.pageSize || 10;

        $('t-title').textContent = T('menu_title');
        $('t-empty').textContent = T('menu_empty');
        $('search').placeholder = T('search_placeholder');
        $('t-reason-label').textContent   = T('label_reason');
        $('t-duration-label').textContent = T('label_duration');
        $('modal-cancel').textContent     = T('btn_cancel');
        $('modal-confirm').textContent    = T('btn_confirm');
        return;
    }

    if (msg.action === 'open') {
        S.entries = Array.isArray(msg.entries) ? msg.entries : [];

        // Keep the selection across a refresh.
        if (S.selected) {
            const id = S.selected.id;
            S.selected = S.entries.find((e) => e.id === id) || null;
        }

        $('panel').classList.remove('hidden');
        render();
        return;
    }

    if (msg.action === 'close') {
        $('panel').classList.add('hidden');
        closeModal();
        return;
    }

    if (msg.action === 'alert') {
        renderAlert(msg.data || {}, msg.seconds || 12);
        return;
    }
});
