/* The store side of an item the staff granted, and the form that grants it.
 *
 *   node tests/ui_store_custom.js
 *
 * Also the line under the server name, which now says which page you are on.
 */
const path = require('path');
const { chromium } = require(process.env.PW || '/opt/node22/lib/node_modules/playwright');

/* Portraits go through an <img>, and an <img> that cannot load removes itself
   and falls back to the initial — which is right in the game and useless in a
   test. So the two that are really loaded are data URIs; the rest are CSS
   backgrounds, which do not care. */
const PNG1 = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const PNG2 = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

const UI = 'file://' + path.resolve(__dirname, '../M5_RankedPvP/Files/ui/index.html');

let fails = 0, checks = 0;
function check(name, got, want) {
  checks++;
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { fails++; console.log(`FAIL ${name.padEnd(56)} got=${JSON.stringify(got)} want=${JSON.stringify(want)}`); }
  else console.log(`ok   ${name.padEnd(56)} ${JSON.stringify(got)}`);
}

const SHIM = () => {
  window.__posted = [];
  window.fetch = (url, opts) => {
    const name = String(url).split('/').pop();
    let body = {};
    try { body = JSON.parse(opts && opts.body || '{}'); } catch (e) {}
    window.__posted.push({ name, body });
    return Promise.resolve({ json: () => Promise.resolve({}) });
  };
  window.__send = (msg) => window.dispatchEvent(new MessageEvent('message', { data: msg }));
};

const BOOT = {
  player: { userId: 1, name: 'ME', level: 3, rp: 400, rankId: 2, tier: 'silver',
            rankColor: '#aaa', coins: 900, avatar: PNG1 },
  maxParty: 5,
  modes: [{ id: '1v1', label: '1V1', teamSize: 1 }],
  allModes: [{ id: '1v1', label: '1V1', teamSize: 1 }],
  maps: [], weaponPresets: [], matchTypes: [], ranks: [], modePool: {},
  permissions: { moderator: true }
};

/* what Store.payload sends once a card and a portrait have been granted */
const STORE = {
  enabled: true, currency: 'COINS', coins: 900,
  cards: [
    { id: 'default', name: 'Default', rarity: 'common', rarityLabel: 'COMMON',
      rarityColor: '#8B93A3', price: 0, image: '', owned: true, equipped: true },
    { id: 'thorn', name: 'Thorn', rarity: 'rare', rarityLabel: 'RARE',
      rarityColor: '#3FA9FF', price: 200, image: 'https://cdn/thorn.png', owned: false, equipped: false },
    { id: 'custom', name: 'M547', rarity: 'legendary', rarityLabel: 'LEGENDARY',
      rarityColor: '#F5C542', price: 0, image: 'https://cdn/mine.gif',
      owned: true, equipped: false, custom: true }
  ],
  titles: [], effects: [], frames: [], avatars: [],
  portraits: [
    { id: 'default', name: 'Default', rarity: 'common', rarityLabel: 'COMMON',
      rarityColor: '#8B93A3', price: 0, image: PNG1, owned: true, equipped: true },
    { id: 'custom', name: 'MY FACE', rarity: 'legendary', rarityLabel: 'LEGENDARY',
      rarityColor: '#F5C542', price: 0, image: 'https://cdn/face.png',
      owned: true, equipped: false, custom: true }
  ],
  equippedcard: 'default', equippedportrait: 'default'
};

const ADMIN = {
  allowed: {
    grantCustom:  { label: 'Grant Custom Card / Portrait', permission: 'pvp.admin.custom.item', group: 'points' },
    revokeCustom: { label: 'Remove Custom Item', permission: 'pvp.admin.custom.item', group: 'points' }
  },
  matches: [], queues: [], rooms: []
};

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });

  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  /* The stand-in pictures point at hosts that do not exist here, and a picture
     that will not load is not a script error — the page is expected to cope
     with one. Only what the code itself threw is collected. */
  page.on('console', (m) => {
    if (m.type() !== 'error') return;
    if (m.text().indexOf('Failed to load resource') === 0) return;
    errors.push(m.text());
  });

  await page.addInitScript(SHIM);
  await page.goto(UI);
  await page.evaluate((boot) => {
    window.__send({ action: 'open', page: 'ranked', theme: {},
                    brand: { name: 'D-VIBES', accent: 'RP', subtitle: '' }, silent: true });
    window.__send({ action: 'boot', data: boot });
  }, BOOT);
  await page.waitForTimeout(200);

  // ======================================================================
  // 1. the line under the server name
  // ======================================================================
  check('the interface loads with no script error', errors, []);
  check('the lobby says what it is',
        await page.locator('#hd-title').innerText(), 'MATCHMAKING');
  check('  and it is big enough to read',
        await page.locator('#hd-title').evaluate(
          (n) => parseInt(getComputedStyle(n).fontSize, 10) >= 15), true);

  const pageTitle = async (tab) => {
    await page.locator(`.ft .tab[data-page="${tab}"]`).click();
    await page.waitForTimeout(140);
    return page.locator('#hd-title').innerText();
  };
  check('the store says STORE',            await pageTitle('store'), 'STORE');
  check('the leaderboard says LEADERBOARD', await pageTitle('leaderboard'), 'LEADERBOARD');
  check('aim training says TRAINING',       await pageTitle('training'), 'TRAINING');
  check('and going back to the lobby says MATCHMAKING again',
        await pageTitle('ranked'), 'MATCHMAKING');

  // a server that pins the line keeps it on every page
  await page.evaluate(() => window.__send({ action: 'open', page: S.page, silent: true,
    brand: { name: 'D-VIBES', accent: 'RP', subtitle: 'MATCHMAKING' } }));
  await page.waitForTimeout(120);
  check('a pinned line does not follow the page', await pageTitle('store'), 'MATCHMAKING');
  await page.evaluate(() => window.__send({ action: 'open', page: S.page, silent: true,
    brand: { name: 'D-VIBES', accent: 'RP', subtitle: '' } }));
  await page.waitForTimeout(120);

  // ======================================================================
  // 2. the player's own picture on the identity card
  // ======================================================================
  check('the identity card wears the player\'s picture',
        await page.locator('#id-avatar img').getAttribute('src'), PNG1);
  check('  and the initial underneath is out of the way',
        await page.locator('#id-initial').evaluate((n) => getComputedStyle(n).visibility),
        'hidden');

  // a portrait equipped later arrives beside the cosmetics
  await page.evaluate((png) => window.__send({ action: 'data',
    data: { what: 'cosmetics', coins: 900, cosmetics: {}, avatar: png } }), PNG2);
  await page.waitForTimeout(140);
  check('equipping a portrait changes it without a reload',
        await page.locator('#id-avatar img').getAttribute('src'), PNG2);

  // ======================================================================
  // 3. the store
  // ======================================================================
  await page.locator('.ft .tab[data-page="store"]').click();
  await page.evaluate((st) => window.__send({ action: 'data',
    data: { what: 'store', store: st } }), STORE);
  await page.waitForTimeout(200);

  check('the store has a portraits tab',
        await page.locator('.stab[data-stab="portraits"]').count(), 1);

  const gifted = page.locator('.sitem.gifted').first();
  check('the granted card is in the card list', await page.locator('.sitem').count(), 3);
  check('  marked as a gift',                   await gifted.count(), 1);
  check('  with a gift badge on it',            await gifted.locator('.si-gift').count(), 1);
  check('  showing the picture it was given',
        await gifted.locator('.ci-art').evaluate(
          (n) => getComputedStyle(n).backgroundImage.includes('mine.gif')), true);
  check('  offered to wear, not to buy',
        (await gifted.locator('.si-btn').innerText()).trim(), 'EQUIP');

  await page.evaluate(() => { window.__posted = []; });
  await gifted.locator('.si-btn').click();
  await page.waitForTimeout(140);
  check('  and wearing it asks for exactly that',
        await page.evaluate(() => window.__posted.find((p) => p.name === 'store')),
        { name: 'store', body: { action: 'equip', kind: 'card', id: 'custom' } });

  await page.locator('.stab[data-stab="portraits"]').click();
  await page.waitForTimeout(160);
  check('the portraits tab lists both', await page.locator('.sitem').count(), 2);
  check('  the default one previews the picture the player has',
        await page.locator('.sitem').first().locator('.ci-art').evaluate(
          (n) => getComputedStyle(n).backgroundImage.indexOf('data:image/png') >= 0), true);
  check('  a portrait is drawn square, not as a card',
        await page.locator('.po-art').first().evaluate((n) => {
          const r = n.getBoundingClientRect();
          return Math.abs(r.width - r.height) <= 2;
        }), true);

  await page.evaluate(() => { window.__posted = []; });
  await page.locator('.sitem.gifted .si-btn').click();
  await page.waitForTimeout(140);
  check('  and equipping one asks for the portrait kind',
        await page.evaluate(() => window.__posted.find((p) => p.name === 'store')),
        { name: 'store', body: { action: 'equip', kind: 'portrait', id: 'custom' } });

  // ======================================================================
  // 4. the form the staff grants it from
  // ======================================================================
  await page.locator('.ft .tab[data-page="admin"]').click();
  await page.evaluate((a) => window.__send({ action: 'data',
    data: { what: 'admin', action: 'dashboard', result: a } }), ADMIN);
  await page.waitForTimeout(200);

  check('the grant control is on the admin panel',
        await page.locator('[data-adm="grantCustom"]').count(), 1);
  check('  with a kind to pick',  await page.locator('#adm-custom-kind option').count(), 2);
  check('  a box for the image',  await page.locator('#adm-custom-img').count(), 1);
  check('  and one for the name', await page.locator('#adm-custom-name').count(), 1);

  await page.fill('#adm-target', '42');
  /* The native <select> is replaced by a styled widget, so the pick is made
     through that rather than on the hidden element behind it. */
  const pick = async (id, label) => {
    await page.locator(`#${id}`).evaluate((sel) => sel.parentNode.querySelector('.xsel-btn').click());
    await page.locator(`#${id}`).evaluate((sel, want) => {
      const rows = sel.parentNode.querySelectorAll('.xsel-opt');
      for (const r of rows) if (r.textContent.trim() === want) { r.click(); return; }
      throw new Error('no option ' + want);
    }, label);
  };
  await pick('adm-custom-kind', 'Portrait');
  await page.fill('#adm-custom-img', 'https://cdn/gift.png');
  await page.fill('#adm-custom-name', 'WINNER');
  await page.evaluate(() => { window.__posted = []; });
  await page.locator('[data-adm="grantCustom"]').click();
  await page.waitForTimeout(160);
  check('granting sends the player, the kind, the picture and the name',
        await page.evaluate(() => {
          const p = window.__posted.find((x) => x.name === 'admin');
          return p && p.body;
        }),
        { action: 'grantCustom', target: '42', kind: 'portrait',
          image: 'https://cdn/gift.png', name: 'WINNER' });

  await page.evaluate(() => { window.__posted = []; });
  await pick('adm-custom-kind-del', 'Card');
  await page.locator('[data-adm="revokeCustom"]').click();
  await page.waitForTimeout(160);
  check('taking one back names the player and the kind',
        await page.evaluate(() => {
          const p = window.__posted.find((x) => x.name === 'admin');
          return p && p.body;
        }),
        { action: 'revokeCustom', target: '42', kind: 'card' });

  check('no script error the whole way through', errors, []);

  await browser.close();
  console.log(fails ? `\n${fails} FAILED of ${checks}` : `\nALL PASS (${checks} checks)`);
  process.exit(fails ? 1 : 0);
})();
