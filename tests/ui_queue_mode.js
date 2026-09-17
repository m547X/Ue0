/* The queue mode the player ends up searching, and the lobby row when the
 * party is bigger than the row can draw.
 *
 *   node tests/ui_queue_mode.js
 *
 * Both are things only the rendered page can answer: which mode survives an
 * autoMode sync, and whether a wide row scrolls instead of clipping.
 */
const path = require('path');
const { chromium } = require(process.env.PW || '/opt/node22/lib/node_modules/playwright');

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
  try { localStorage.removeItem('m5rp_autofill'); } catch (e) {}
};

const MODES = [
  { id: '1v1', label: '1V1', teamSize: 1 },
  { id: '2v2', label: '2V2', teamSize: 2 },
  { id: '3v3', label: '3V3', teamSize: 3 },
  { id: '5v5', label: '5V5', teamSize: 5 }
];

const BOOT = {
  player: { userId: 1, name: 'ME', level: 3, rp: 400, rankId: 2, tier: 'silver', rankColor: '#aaa' },
  maxParty: 5,
  modes: MODES, allModes: MODES,
  maps: [], weaponPresets: [], matchTypes: [], ranks: [], modePool: {},
  partyQueue: {
    autoMode: true,
    lockToPartySize: true,
    autoFill: { enabled: true, default: false }
  }
};

const party = (ids, autoMode) => ({
  id: 'p1', leader: ids[0], autoMode: autoMode || null,
  members: ids.map((id) => ({ userId: id, name: id === 1 ? 'ME' : 'P' + id,
                              rankId: 2, leader: id === ids[0], ready: true }))
});

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });

  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });

  await page.addInitScript(SHIM);
  await page.goto(UI);
  await page.evaluate((boot) => {
    window.__send({ action: 'open', page: 'ranked', theme: {}, brand: {}, silent: true });
    window.__send({ action: 'boot', data: boot });
  }, BOOT);
  await page.waitForTimeout(200);

  const mode = () => page.evaluate(() => S.mode);
  const tab = (label) => page.locator('#mode-tabs .mtab', { hasText: label }).first();

  // ======================================================================
  // 1. without AUTO FILL a mode that needs more players is not selectable
  // ======================================================================
  check('the interface loads with no script error', errors, []);
  check('it starts on 1V1', await mode(), '1v1');
  check('2V2 is locked for one player',
        await tab('2V2').evaluate((n) => n.classList.contains('locked')), true);
  await tab('2V2').click();
  await page.waitForTimeout(80);
  check('  and clicking it does not change the mode', await mode(), '1v1');

  // ======================================================================
  // 2. with AUTO FILL on, the mode the player picks is the mode they search
  // ======================================================================
  await page.locator('#btn-autofill').click();
  await page.waitForTimeout(80);
  check('AUTO FILL unlocks 2V2 for one player',
        await tab('2V2').evaluate((n) => n.classList.contains('locked')), false);

  await tab('2V2').click();
  await page.waitForTimeout(80);
  check('  picking 2V2 selects it', await mode(), '2v2');
  check('  and the tab shows as the active one',
        await tab('2V2').evaluate((n) => n.classList.contains('active')), true);

  /* This is the bug: autoMode looks at the party size, decides one player means
     1V1, and quietly undid the choice — so the search went out on 1V1. */
  await page.evaluate((p) => window.__send({ action: 'party', data: p }), party([1], '1v1'));
  await page.waitForTimeout(120);
  check('a party sync does not drag it back to 1V1', await mode(), '2v2');

  await page.evaluate(() => { window.__posted = []; });
  await page.locator('#btn-start').click();
  await page.waitForTimeout(120);
  check('  and the search goes out on 2V2',
        await page.evaluate(() => window.__posted.find((p) => p.name === 'queue')),
        { name: 'queue', body: { action: 'join', mode: '2v2', autoFill: true } });

  // ======================================================================
  // 3. the pin is only kept while that mode can still be searched
  // ======================================================================
  await page.evaluate((p) => window.__send({ action: 'party', data: p }), party([1, 2, 3], '3v3'));
  await page.waitForTimeout(120);
  check('a third player makes 2V2 impossible, so the mode follows the party',
        await mode(), '3v3');

  // back to one player and pinned on 5V5, then AUTO FILL is switched off
  await page.evaluate((p) => window.__send({ action: 'party', data: p }), party([1], '1v1'));
  await page.waitForTimeout(120);
  await tab('5V5').click();
  await page.waitForTimeout(80);
  check('one player can pick 5V5 with AUTO FILL on', await mode(), '5v5');
  await page.locator('#btn-autofill').click();
  await page.waitForTimeout(120);
  check('  turning AUTO FILL off puts them back on a mode they can search',
        await mode(), '1v1');
  check('  and the pin is gone with it',
        await page.evaluate(() => S.modePin), null);

  // ======================================================================
  // 4. a row too wide to draw scrolls instead of shrinking to a strip
  // ======================================================================
  const row = async (maxParty, size) => {
    await page.evaluate((a) => {
      S.boot.maxParty = a.maxParty;
      const ids = [];
      for (let i = 0; i < a.size; i++) ids.push(i === a.size - 1 ? 1 : 60 + i);
      window.__send({ action: 'party', data: {
        id: 'p1', leader: ids[0],
        members: ids.map((id) => ({ userId: id, name: id === 1 ? 'ME' : 'P' + id,
                                    rankId: 2, leader: id === ids[0], ready: true })) } });
    }, { maxParty, size });
    await page.waitForTimeout(150);
    return page.evaluate(() => {
      const host = document.getElementById('party-slots');
      const cards = Array.from(host.querySelectorAll('.slot'));
      const me = cards.find(
        (n) => ((n.querySelector('.slot-name') || {}).textContent || '').indexOf('ME') === 0);
      const a = me.getBoundingClientRect(), b = host.getBoundingClientRect();
      return {
        cardW: Math.round(a.width),
        scrolls: host.scrollWidth > host.clientWidth,
        offCentre: Math.round(Math.abs((a.left + a.right) / 2 - (b.left + b.right) / 2)),
        // the first card must be reachable: scrolled fully back it starts inside
        firstReachable: (() => {
          const was = host.scrollLeft;
          host.scrollLeft = -99999;                 // clamps to the near edge
          const first = cards[0].getBoundingClientRect();
          const host2 = host.getBoundingClientRect();
          const ok = first.left >= host2.left - 1;
          host.scrollLeft = was;
          return ok;
        })()
      };
    });
  };

  let r = await row(5, 5);
  check('five seats still fit without scrolling', r.scrolls, false);
  check('  and you are on the centre line', r.offCentre <= 1, true);

  r = await row(12, 12);
  check('twelve seats scroll instead', r.scrolls, true);
  check('  the cards keep a readable width', r.cardW >= 160, true);
  check('  you are still on the centre line', r.offCentre <= 1, true);
  check('  and the far end of the row is reachable', r.firstReachable, true);

  check('no script error the whole way through', errors, []);

  await browser.close();
  console.log(fails ? `\n${fails} FAILED of ${checks}` : `\nALL PASS (${checks} checks)`);
  process.exit(fails ? 1 : 0);
})();
