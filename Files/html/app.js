'use strict';

const RES = (() => {
    try { return window.GetParentResourceName ? window.GetParentResourceName() : 'M5_iCreator'; }
    catch (_) { return 'M5_iCreator'; }
})();

function nui(cb, data = {}) {
    return fetch(`https://${RES}/${cb}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
    }).catch(e => console.warn('[NUI]', e));
}

const S = {
    spots        : [],
    activeId     : null,
    previewOn    : false,
    rotating     : false,
    settingsSpot : null,
    stats        : { source: '—', total: 0, pending: 0 },
};

const $ = id => document.getElementById(id);

let _stTimer = null;
function status(msg, type = 'idle') {
    $('s-text').textContent = msg;
    const dot = $('s-dot');
    dot.className = 'dot ' + ({ idle:'idle', ok:'ok', err:'err', info:'info' }[type] || 'idle');
    if (_stTimer) clearTimeout(_stTimer);
    if (type !== 'idle') {
        _stTimer = setTimeout(() => status('جاهز', 'idle'), 3500);
    }
}

function switchTab(name) {
    document.querySelectorAll('.nav-btn').forEach(b => b.classList.toggle('active', b.dataset.tab === name));
    document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.id === `tab-${name}`));
}

function esc(s) {
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function fmtCoords(vc) {
    if (!vc) return '— — — —';
    return `${vc.x.toFixed(1)}, ${vc.y.toFixed(1)}, ${vc.z.toFixed(1)}  H:${(vc.w||0).toFixed(0)}°`;
}

function renderSpots() {
    const grid = $('spots-grid');
    if (!S.spots.length) {
        grid.innerHTML = '<p class="empty-state" style="grid-column:1/-1;padding:40px 0"><span class="ei">📍</span><br/>لا توجد مواقع محفوظة بعد</p>';
        return;
    }

    grid.innerHTML = S.spots.map(sp => {
        const isActive = sp.id === S.activeId;
        const vc = sp.vehicleCoords;
        const coordStr = vc ? `${vc.x.toFixed(0)}, ${vc.y.toFixed(0)}, ${vc.z.toFixed(0)}` : '—';

        return `
        <div class="spot-card${isActive ? ' active' : ''}" data-id="${esc(sp.id)}">
          ${isActive ? '<div class="sc-dot"></div>' : ''}
          <div class="sc-name">${esc(sp.name)}</div>
          <span class="sc-badge ${sp.isDefault ? 'def' : 'cus'}">${sp.isDefault ? 'افتراضي' : 'مخصص'}</span>
          <div class="sc-spawn-row">
            <span>🚗</span>
            <span class="sc-coords">${esc(coordStr)}</span>
            <button class="btn secondary sm" data-act="spawn" data-id="${esc(sp.id)}" title="تحديد موقع الرسبون">📍</button>
          </div>
          <div class="sc-actions">
            <button class="btn secondary sm" data-act="select" data-id="${esc(sp.id)}">✓ تحديد</button>
            <button class="btn secondary sm" data-act="preview" data-id="${esc(sp.id)}">👁 معاينة</button>
            <button class="btn secondary sm" data-act="settings" data-id="${esc(sp.id)}">⚙️ إعدادات</button>
            <button class="btn secondary sm" data-act="camera" data-id="${esc(sp.id)}">📷 كاميرا</button>
            ${!sp.isDefault ? `<button class="btn danger-soft sm" data-act="delete" data-id="${esc(sp.id)}">🗑</button>` : ''}
          </div>
        </div>`;
    }).join('');

    grid.querySelectorAll('[data-act]').forEach(btn => {
        btn.addEventListener('click', e => {
            e.stopPropagation();
            handleCard(btn.dataset.act, btn.dataset.id);
        });
    });

    grid.querySelectorAll('.spot-card').forEach(card => {
        card.addEventListener('click', e => {
            if (e.target.closest('[data-act]')) return;
            handleCard('select', card.dataset.id);
        });
    });

    const active = S.spots.find(s => s.id === S.activeId);
    $('active-name').textContent = active ? active.name : '—';
}

function handleCard(act, id) {
    const spot = S.spots.find(s => s.id === id);

    switch (act) {
        case 'select':
            S.activeId = id;
            nui('selectSpot', { id });
            status('تم التحديد: ' + (spot?.name || id), 'info');
            break;

        case 'preview':
            S.activeId = id;
            nui('selectSpot', { id });
            nui('previewSpot', { id, testModel: $('test-model').value.trim() || 'adder' });
            S.previewOn = true;
            status('معاينة: ' + (spot?.name || id), 'info');
            switchTab('screenshot');
            break;

        case 'settings':
            openSettings(spot);
            switchTab('settings');
            break;

        case 'camera':
            nui('openCameraEditor', { id });
            status('فتح محرر الكاميرا...', 'info');
            break;

        case 'spawn':
            nui('openVehiclePlacer', { id });
            status('وضع تحديد الرسبون: H لنقل السيارة | Enter حفظ', 'info');
            break;

        case 'delete':
            if (confirm(`هل تريد حذف "${spot?.name || id}"؟`)) {
                nui('deleteSpot', { id });
            }
            break;
    }
}

function openSettings(spot) {
    if (!spot) return;
    S.settingsSpot = spot;

    $('settings-empty').classList.add('hidden');
    $('settings-form').classList.remove('hidden');

    $('s-id').value             = spot.id;
    $('s-name').value           = spot.name || '';
    $('s-weather').value        = spot.weather || 'EXTRASUNNY';
    $('s-hour').value           = spot.timeHour ?? 12;
    $('s-minute').value         = spot.timeMin ?? 0;
    $('s-auto-rotate').checked  = !!spot.autoRotate;
    $('s-rotate-spd').value     = spot.rotateSpeed ?? 0.4;

    updateVCDisplay(spot.vehicleCoords);
}

const SOURCE_LABELS = {
    garage: 'ملف الجراج',
    sql   : 'قاعدة البيانات',
    config: 'ملف الإعدادات',
};

function updateStats(p) {
    S.stats = p;
    $('src-name').textContent    = SOURCE_LABELS[p.source] || p.source || '—';
    $('src-total').textContent   = p.total ?? 0;
    $('src-pending').textContent = p.pending ?? 0;
    $('src-pending').classList.toggle('done', (p.pending ?? 0) === 0);
}

function updateVCDisplay(vc) {
    if (!vc) return;
    $('vc-x').textContent = vc.x?.toFixed(2) ?? '—';
    $('vc-y').textContent = vc.y?.toFixed(2) ?? '—';
    $('vc-z').textContent = vc.z?.toFixed(2) ?? '—';
    $('vc-h').textContent = (vc.w ?? 0).toFixed(1) + '°';
}

function bindEvents() {
    document.querySelectorAll('.nav-btn').forEach(btn => {
        btn.addEventListener('click', () => switchTab(btn.dataset.tab));
    });

    $('btn-close').addEventListener('click', () => nui('close'));
    document.addEventListener('keydown', e => { if (e.key === 'Escape') nui('close'); });

    $('btn-open-modal').addEventListener('click', () => {
        $('modal-create').classList.remove('hidden');
        setTimeout(() => $('create-name').focus(), 40);
    });

    $('btn-modal-cancel').addEventListener('click', () => {
        $('modal-create').classList.add('hidden');
    });

    $('modal-create').addEventListener('click', e => {
        if (e.target === $('modal-create')) $('modal-create').classList.add('hidden');
    });

    $('btn-modal-confirm').addEventListener('click', confirmCreate);
    $('create-name').addEventListener('keydown', e => {
        if (e.key === 'Enter') confirmCreate();
    });

    $('btn-preview').addEventListener('click', () => {
        if (!S.activeId) { status('حدد مكاناً أولاً', 'err'); return; }
        nui('previewSpot', { id: S.activeId, testModel: $('test-model').value.trim() || 'adder' });
        S.previewOn = true;
        status('تشغيل المعاينة...', 'info');
    });

    $('btn-stop-preview').addEventListener('click', () => {
        nui('stopPreview');
        S.previewOn = false;
        S.rotating = false;
        $('btn-toggle-rotate').innerHTML = '<span>🔃</span>دوران';
        status('توقفت المعاينة', 'idle');
    });

    $('btn-change-veh').addEventListener('click', () => {
        const m = $('test-model').value.trim() || 'adder';
        nui('changeTestVehicle', { model: m });
        status('السيارة: ' + m, 'info');
    });

    $('btn-toggle-rotate').addEventListener('click', () => {
        S.rotating = !S.rotating;
        nui('toggleRotation', { speed: 0.4 });
        $('btn-toggle-rotate').innerHTML = S.rotating
            ? '<span>⏹</span>إيقاف الدوران'
            : '<span>🔃</span>دوران';
        status('الدوران: ' + (S.rotating ? 'تشغيل' : 'إيقاف'), 'info');
    });

    $('btn-start-shot').addEventListener('click', () => {
        if (!S.activeId) { status('اختر مكاناً نشطاً أولاً', 'err'); return; }
        nui('startScreenshot');
        status('جلسة التصوير بدأت...', 'ok');
    });

    $('btn-reload-src').addEventListener('click', () => {
        nui('reloadVehicles');
        status('جاري إعادة قراءة قائمة السيارات...', 'info');
    });

    $('btn-export-garage').addEventListener('click', () => {
        nui('exportGarage');
        status('تم إرسال طلب تصدير جدول الجراج', 'ok');
    });

    $('btn-load-vehicles').addEventListener('click', () => {
        if (!S.activeId) { status('اختر مكاناً نشطاً أولاً', 'err'); return; }
        nui('loadVehicles');
        status('تلويد السيارات بدأ... Backspace للإيقاف', 'info');
    });

    $('btn-save-settings').addEventListener('click', () => {
        const id = $('s-id').value;
        if (!id) return;

        const name = $('s-name').value.trim();
        if (!name) { status('الاسم لا يمكن أن يكون فارغاً', 'err'); return; }

        nui('updateSpotSettings', {
            id,
            name,
            weather: $('s-weather').value,
            timeHour: parseInt($('s-hour').value) || 12,
            timeMin: parseInt($('s-minute').value) || 0,
            autoRotate: $('s-auto-rotate').checked,
            rotateSpeed: parseFloat($('s-rotate-spd').value) || 0.4,
        });

        status('حُفظت الإعدادات', 'ok');
    });

    $('btn-open-cam-editor').addEventListener('click', () => {
        const id = $('s-id').value;
        if (!id) return;
        nui('openCameraEditor', { id });
        status('فتح محرر الكاميرا...', 'info');
    });

    $('btn-use-my-pos').addEventListener('click', async () => {
        const id = $('s-id').value;
        if (!id) { status('افتح إعدادات مكان أولاً', 'err'); return; }

        const res = await nui('usePlayerPos', { id });
        if (res) {
            const d = await res.json().catch(() => null);
            if (d) updateVCDisplay(d);
        }

        status('تم ضبط موقع الرسبون على موقعك الحالي', 'ok');
    });

    $('btn-interactive-place').addEventListener('click', () => {
        const id = $('s-id').value;
        if (!id) { status('افتح إعدادات مكان أولاً', 'err'); return; }
        nui('openVehiclePlacer', { id });
        status('H = نقل السيارة | Enter = حفظ | Backspace = إلغاء', 'info');
    });

    $('btn-preview-vpos').addEventListener('click', () => {
        const id = $('s-id').value;
        if (!id) return;
        nui('previewSpot', { id, testModel: $('test-model').value.trim() || 'adder' });
        status('معاينة موقع الرسبون', 'info');
    });
}

function confirmCreate() {
    const name = $('create-name').value.trim();
    if (!name) {
        $('create-name').style.borderColor = 'var(--err)';
        setTimeout(() => $('create-name').style.borderColor = '', 1500);
        return;
    }

    nui('createSpot', { name });
    $('modal-create').classList.add('hidden');
    $('create-name').value = '';
    status('جاري إنشاء المكان...', 'info');
}

window.addEventListener('message', e => {
    const { action, ...p } = e.data || {};
    switch (action) {
        case 'open':
            document.body.classList.remove('hidden');
            break;

        case 'close':
            document.body.classList.add('hidden');
            break;

        case 'updateSpots':
            S.spots = p.spots || [];
            {
                const found = S.spots.find(s => s.isActive);
                if (found) S.activeId = found.id;
            }
            renderSpots();
            if (S.settingsSpot) {
                const updated = S.spots.find(s => s.id === S.settingsSpot.id);
                if (updated) openSettings(updated);
            }
            break;

        case 'activeSpot':
            $('active-name').textContent = p.name || '—';
            break;

        case 'status':
            status(p.message, p.isError ? 'err' : 'ok');
            break;

        case 'updateVC':
            updateVCDisplay(p.coords);
            break;

        case 'vehicleStats':
            updateStats(p);
            break;
    }
});

document.addEventListener('DOMContentLoaded', () => {
    bindEvents();
    status('جاهز', 'idle');
});
