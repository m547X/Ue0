/* The training page and the training HUD.
 *
 *   node tests/ui_training.js
 *
 * The drills, their wording and their paces are all sent by the server now, so
 * what matters is that the page is built from that list rather than a hardcoded
 * one, that picking a pace asks for that pace, and that the four HUD numbers
 * follow whichever drill is running.
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
};

/* exactly what Training.modeList() sends */
const BOOT = {
  player: { userId: 1, name: 'ME', level: 3, rp: 400, rankId: 2, tier: 'silver', rankColor: '#aaa' },
  maxParty: 5,
  modes: [{ id: '1v1', label: '1V1', teamSize: 1 }],
  allModes: [{ id: '1v1', label: '1V1', teamSize: 1 }],
  maps: [], weaponPresets: [], matchTypes: [], ranks: [], modePool: {},
  trainingModes: [
    { kind: 'aim', label: 'AIM TRAINING', desc: 'Static targets.' },
    { kind: 'headshot', label: 'HEADSHOT TRAINING', desc: 'Long range targets.' },
    { kind: 'moving', label: 'MOVING TARGETS', desc: 'Targets spawn around you.' },
    { kind: 'reflex', label: 'REFLEX TARGETS', desc: 'Aim Lab style.',
      paces: [{ id: 'slow', label: 'SLOW' }, { id: 'normal', label: 'NORMAL' },
              { id: 'fast', label: 'FAST' }] },
    { kind: 'range', label: 'FREE RANGE', desc: 'Open range.' }
  ]
};

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

  // ======================================================================
  // 1. the page is built from the server's list
  // ======================================================================
  await page.locator('.ft .tab[data-page="training"]').click();
  await page.waitForTimeout(150);

  check('the interface loads with no script error', errors, []);
  check('every drill the server sent has a card',
        await page.locator('.traincard').count(), 5);
  check('  in the order it sent them',
        await page.locator('.traincard b').allInnerTexts(),
        ['AIM TRAINING', 'HEADSHOT TRAINING', 'MOVING TARGETS', 'REFLEX TARGETS', 'FREE RANGE']);
  check('  with the description underneath',
        (await page.locator('.traincard').nth(2).innerText()).includes('Targets spawn around you'), true);

  // ======================================================================
  // 2. a drill with paces is entered by picking one
  // ======================================================================
  const reflex = page.locator('.traincard').nth(3);
  check('the reflex drill offers its three paces',
        await reflex.locator('[data-pace]').count(), 3);
  check('  and not a plain enter button',
        await reflex.locator('> .btn').count(), 0);
  check('  labelled for the player',
        await reflex.locator('[data-pace]').allInnerTexts(), ['SLOW', 'NORMAL', 'FAST']);

  await page.evaluate(() => { window.__posted = []; });
  await reflex.locator('[data-pace="fast"]').click();
  await page.waitForTimeout(100);
  check('picking a pace asks for that pace',
        await page.evaluate(() => window.__posted.find((p) => p.name === 'action')),
        { name: 'action', body: { action: 'training', enable: true, kind: 'reflex', pace: 'fast' } });

  await page.evaluate(() => { window.__posted = []; });
  await page.locator('.traincard').nth(2).click();
  await page.waitForTimeout(100);
  check('a drill without paces is entered by its card',
        await page.evaluate(() => window.__posted.find((p) => p.name === 'action')),
        { name: 'action', body: { action: 'training', enable: true, kind: 'moving' } });

  // ======================================================================
  // 3. the HUD numbers follow the drill
  // ======================================================================
  const tiles = () => page.evaluate(() => Array.from(
    document.querySelectorAll('#training-stats > div'),
    (n) => `${n.querySelector('span').textContent}=${n.querySelector('b').textContent}`));

  await page.evaluate(() => window.__send({ action: 'training', data: {
    active: true, label: 'REFLEX TARGETS', pace: 'FAST', kind: 'reflex', time: 120,
    stats: [{ l: 'HITS', v: '9' }, { l: 'MISSED', v: '2' },
            { l: 'REACTION', v: '284 MS' }, { l: 'STREAK', v: '4 / 6' }] } }));
  await page.waitForTimeout(120);

  check('the training box is up', await page.isVisible('#training'), true);
  check('  titled with the drill and the pace',
        await page.locator('#training-title').innerText(), 'REFLEX TARGETS · FAST');
  check('  and shows what a reflex run measures', await tiles(),
        ['HITS=9', 'MISSED=2', 'REACTION=284 MS', 'STREAK=4 / 6']);

  // a different drill reports different things through the same four tiles
  await page.evaluate(() => window.__send({ action: 'training', data: {
    active: true, label: 'MOVING TARGETS', kind: 'moving',
    stats: [{ l: 'HITS', v: '14' }, { l: 'HEADSHOTS', v: '5' },
            { l: 'ACCURACY', v: '61%' }, { l: 'CLOCK', v: '96s' }] } }));
  await page.waitForTimeout(120);
  check('another drill reuses the tiles for its own numbers', await tiles(),
        ['HITS=14', 'HEADSHOTS=5', 'ACCURACY=61%', 'CLOCK=96s']);
  check('  and drops the pace from the title',
        await page.locator('#training-title').innerText(), 'MOVING TARGETS');

  // ======================================================================
  // 4. the readouts are translated like everything else on screen
  // ======================================================================
  await page.evaluate(() => window.__send({ action: 'open', page: 'training', silent: true,
    locale: { language: 'ar', rtl: { ar: true }, strings: { ar: {
      'REFLEX TARGETS': 'أهداف سريعة', 'REACTION': 'رد الفعل', 'FAST': 'سريع' } } } }));
  await page.waitForTimeout(150);
  await page.evaluate(() => window.__send({ action: 'training', data: {
    active: true, label: 'REFLEX TARGETS', pace: 'FAST', kind: 'reflex',
    stats: [{ l: 'HITS', v: '1' }, { l: 'MISSED', v: '0' },
            { l: 'REACTION', v: '300 MS' }, { l: 'STREAK', v: '1 / 1' }] } }));
  await page.waitForTimeout(120);
  check('the readouts are translated', (await tiles())[2], 'رد الفعل=300 MS');
  check('  and so is the title',
        await page.locator('#training-title').innerText(), 'أهداف سريعة · سريع');

  // ======================================================================
  // 5. leaving takes the box with it
  // ======================================================================
  await page.evaluate(() => window.__send({ action: 'training', data: { active: false } }));
  await page.waitForTimeout(120);
  check('ending the session hides the box', await page.isVisible('#training'), false);
  check('  and the exit prompt with it', await page.isVisible('#train-prompt'), false);

  check('no script error the whole way through', errors, []);

  await browser.close();
  console.log(fails ? `\n${fails} FAILED of ${checks}` : `\nALL PASS (${checks} checks)`);
  process.exit(fails ? 1 : 0);
})();
