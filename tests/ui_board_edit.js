/* The in-game editor for the leaderboard screens and the podium spots.
 *
 *   node tests/ui_board_edit.js
 *
 * The thing that matters is that every control pushes the WHOLE layout back to
 * the client, because that is what the world redraws from — a control that
 * changes the panel but not the push is a slider that does nothing, and looks
 * fine in the code.
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
    let body = {};
    try { body = JSON.parse(opts && opts.body || '{}'); } catch (e) {}
    window.__posted.push({ name: String(url).split('/').pop(), body });
    return Promise.resolve({ json: () => Promise.resolve({}) });
  };
  window.__send = (m) => window.dispatchEvent(new MessageEvent('message', { data: m }));
};

const LAYOUT = {
  screensEnabled: true, podiumEnabled: true, podiumDistance: 25,
  screens: [{ pos: { x: 10, y: 20, z: 30 }, title: 'TOP', enabled: true,
              scale: 1.0, width: 1.0, rows: 10, opacity: 190, distance: 18 }],
  podium: [{ pos: { x: 12, y: 20, z: 29 }, h: 90 },
           { pos: { x: 14, y: 20, z: 29 }, h: 90 },
           { pos: { x: 16, y: 20, z: 29 }, h: 90 }]
};
const HERE = { x: 100.5, y: 200.25, z: 40.0, h: 175.5 };

const last = (p) => p.evaluate(() => {
  const u = window.__posted.filter((x) => x.name === 'boardEdit');
  return u.length ? u[u.length - 1].body : null;
});

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));

  await page.addInitScript(SHIM);
  await page.goto(UI);
  await page.evaluate((d) => {
    window.__send({ action: 'open', page: 'board', theme: {}, brand: {}, silent: true });
    window.__send({ action: 'boardEdit', layout: d.l, here: d.h });
  }, { l: LAYOUT, h: HERE });
  await page.waitForTimeout(250);

  // ======================================================================
  // 1. everything movable is listed
  // ======================================================================
  check('the editor opens on its own page',
        await page.locator('#pg-board').evaluate((n) => n.classList.contains('active')), true);
  check('  one screen and three podium spots are listed',
        await page.locator('.be-target').count(), 4);
  check('  the first one is selected',
        await page.locator('.be-target.on').count(), 1);
  check('  and its controls are shown',
        await page.locator('#be-body .be-row').count() > 4, true);

  // ======================================================================
  // 2. moving it pushes the whole layout, not just the panel
  // ======================================================================
  await page.evaluate(() => { window.__posted = []; });
  const northPlus = page.locator('.be-row', { hasText: 'NORTH' }).locator('.be-btn').nth(1);
  await northPlus.click();
  await page.waitForTimeout(120);

  let sent = await last(page);
  check('nudging north pushes an update', sent && sent.action, 'update');
  check('  it moved a quarter metre',     sent.layout.screens[0].pos.y, 20.25);
  check('  and nothing else moved',
        [sent.layout.screens[0].pos.x, sent.layout.screens[0].pos.z], [10, 30]);
  check('  the podium came along untouched',
        sent.layout.podium.length, 3);

  // and back again
  const northMinus = page.locator('.be-row', { hasText: 'NORTH' }).locator('.be-btn').nth(0);
  await northMinus.click();
  await page.waitForTimeout(120);
  sent = await last(page);
  check('nudging the other way puts it back', sent.layout.screens[0].pos.y, 20);

  // ======================================================================
  // 3. the width and the size, which is what was asked for
  // ======================================================================
  const bump = async (label, times) => {
    const b = page.locator('.be-row', { hasText: label }).locator('.be-btn').nth(1);
    for (let i = 0; i < times; i++) { await b.click(); await page.waitForTimeout(40); }
    await page.waitForTimeout(100);
    return last(page);
  };

  sent = await bump('WIDTH', 4);
  check('the width can be widened', Math.round(sent.layout.screens[0].width * 100) / 100, 1.2);
  sent = await bump('SIZE', 4);
  check('  and the size raised',     Math.round(sent.layout.screens[0].scale * 100) / 100, 1.2);
  sent = await bump('ROWS', 3);
  check('  and the row count',       sent.layout.screens[0].rows, 13);
  sent = await bump('SEEN FROM', 5);
  check('  and how far off it is visible', sent.layout.screens[0].distance, 23);

  // the numbers are clamped, so a held button cannot make a board a kilometre wide
  const wide = page.locator('.be-row', { hasText: 'WIDTH' }).locator('.be-btn').nth(1);
  for (let i = 0; i < 60; i++) await wide.click({ delay: 0 });
  await page.waitForTimeout(150);
  sent = await last(page);
  check('the width stops at its limit', sent.layout.screens[0].width <= 3, true);

  // ======================================================================
  // 4. put it where I stand
  // ======================================================================
  await page.locator('#be-body .btn', { hasText: 'PUT IT WHERE I STAND' }).click();
  await page.waitForTimeout(150);
  sent = await last(page);
  check('the screen lands where the player is',
        [sent.layout.screens[0].pos.x, sent.layout.screens[0].pos.y], [100.5, 200.25]);
  check('  at eye height, not on the floor',
        sent.layout.screens[0].pos.z, 41.35);

  // ======================================================================
  // 5. the podium: its own controls, and a facing
  // ======================================================================
  await page.locator('.be-target').nth(1).click();
  await page.waitForTimeout(150);
  check('a podium spot has a facing to set',
        await page.locator('.be-row', { hasText: 'FACING' }).count(), 1);
  check('  and no width, because it is a person',
        await page.locator('.be-row', { hasText: 'WIDTH' }).count(), 0);

  sent = await bump('FACING', 2);
  check('turning it moves in five degree steps', sent.layout.podium[0].h, 100);

  await page.locator('#be-body .btn', { hasText: 'PUT IT WHERE I STAND' }).click();
  await page.waitForTimeout(150);
  sent = await last(page);
  check('a podium spot stands on the floor, not in the air',
        sent.layout.podium[0].pos.z, 40);
  check('  facing the way the player faced',
        sent.layout.podium[0].h, 175.5);

  // ======================================================================
  // 6. switches, adding and removing
  // ======================================================================
  // the switch styles its checkbox away, so the label is what gets clicked
  await page.locator('.be-row', { hasText: 'PODIUM ON' }).locator('.sw').click();
  await page.waitForTimeout(150);
  sent = await last(page);
  check('the podium can be switched off from here', sent.layout.podiumEnabled, false);

  await page.click('[data-action="be-add"]');
  await page.waitForTimeout(200);
  sent = await last(page);
  check('a second screen can be added', sent.layout.screens.length, 2);
  check('  and it is the one being edited',
        await page.locator('.be-target.on').textContent(), 'SCREEN 2');

  await page.locator('#be-body .btn', { hasText: 'REMOVE THIS SCREEN' }).click();
  await page.waitForTimeout(200);
  sent = await last(page);
  check('and removed again', sent.layout.screens.length, 1);

  // ======================================================================
  // 7. saving, cancelling, resetting
  // ======================================================================
  await page.evaluate(() => { window.__posted = []; });
  await page.click('[data-action="be-save"]');
  await page.waitForTimeout(150);
  sent = await last(page);
  check('save sends the layout', sent.action, 'save');
  check('  with the screen in it', sent.layout.screens.length, 1);

  await page.evaluate(() => { window.__posted = []; });
  await page.click('[data-action="be-cancel"]');
  await page.waitForTimeout(150);
  check('cancel sends no layout at all',
        await last(page), { action: 'cancel' });

  // reset is asked for rather than done on a click
  await page.evaluate(() => { window.__posted = []; });
  await page.click('[data-action="be-reset"]');
  await page.waitForTimeout(150);
  check('reset asks first', await last(page), null);
  check('  with a dialog',
        await page.locator('#modal-prompt').evaluate((n) => !n.classList.contains('hidden')), true);
  await page.click('#prompt-ok');
  await page.waitForTimeout(150);
  check('  and only then resets', (await last(page)).action, 'reset');

  check('nothing threw along the way', errors, []);

  await browser.close();
  console.log();
  console.log(fails === 0 ? `ALL PASS (${checks} checks)` : `${fails} FAILED`);
  process.exit(fails === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
