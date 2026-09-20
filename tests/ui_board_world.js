/* Moving the board while standing in front of it.
 *
 *   node tests/ui_board_world.js
 *
 * The world panel is drawn over the game with the menu shut, so the only way
 * to know it works is to open the real page, put it in world mode and click
 * the things. What matters:
 *
 *   - every control posts something the client can act on, and posts the right
 *     axis — a + that sends the wrong letter looks perfect and moves the wrong
 *     thing, and
 *   - it offers a podium spot only what a podium spot has. A person has no
 *     width and no tilt.
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
  // the client answers a grab with 'grab' or 'miss'; __grab decides which
  window.__grab = 'grab';
  window.fetch = (url, opts) => {
    let body = {};
    try { body = JSON.parse(opts && opts.body || '{}'); } catch (e) {}
    const name = String(url).split('/').pop();
    window.__posted.push({ name, body });
    const reply = (name === 'boardWorld' && body.action === 'grab') ? window.__grab : {};
    return Promise.resolve({ json: () => Promise.resolve(reply) });
  };
  window.__send = (m) => window.dispatchEvent(new MessageEvent('message', { data: m }));
};

const SCREEN = {
  action: 'boardWorld', on: true, mode: 'move', speed: 1, sel: 's0', walk: false,
  targets: [{ id: 's0', kind: 's', n: 1, title: 'TOP' },
            { id: 'p0', kind: 'p', n: 1 },
            { id: 'p1', kind: 'p', n: 2 }],
  item: { kind: 's', x: 10.5, y: -20.25, z: 44.02, h: 214, pitch: 0, width: 6 }
};

const last = (p, name) => p.evaluate((n) => {
  const u = window.__posted.filter((x) => x.name === n);
  return u.length ? u[u.length - 1].body : null;
}, name || 'boardWorld');

const clear = (p) => p.evaluate(() => { window.__posted = []; });

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));

  await page.addInitScript(SHIM);
  await page.goto(UI);
  await page.evaluate(() => window.__send({ action: 'open', page: 'board',
    theme: {}, brand: {}, silent: true }));
  await page.waitForTimeout(150);

  // ======================================================================
  // 1. getting there from the list
  // ======================================================================
  await page.evaluate(() => window.__send({ action: 'boardEdit', layout: {
      screensEnabled: true, podiumEnabled: true, podiumDistance: 25,
      screens: [{ pos: { x: 10, y: 20, z: 30 }, title: 'TOP', enabled: true,
                  h: 0, pitch: 0, width: 6, rows: 10, opacity: 255, distance: 35 }],
      podium: [{ pos: { x: 12, y: 20, z: 29 }, h: 90 }]
    }, here: { x: 1, y: 2, z: 3, h: 4 } }));
  await page.waitForTimeout(150);

  check('the list offers to move it in the world',
        await page.locator('#be-body .btn', { hasText: 'MOVE IT IN THE WORLD' }).count(), 1);

  await clear(page);
  await page.locator('#be-body .btn', { hasText: 'MOVE IT IN THE WORLD' }).click();
  await page.waitForTimeout(150);
  const handover = await last(page, 'boardEdit');
  check('  and hands the client the layout to move',
        [handover.action, handover.sel, handover.layout.screens.length], ['world', 's0', 1]);

  // the panel does not appear on its own — the client answers with the mode
  check('  the panel waits to be told',
        await page.locator('#bw').evaluate((n) => n.classList.contains('hidden')), true);

  // ======================================================================
  // 2. the panel itself
  // ======================================================================
  await page.evaluate((d) => window.__send(d), SCREEN);
  await page.waitForTimeout(150);

  check('the panel is up', await page.locator('#bw').evaluate(
    (n) => !n.classList.contains('hidden')), true);
  check('  with four things you can do',  await page.locator('.bw-mode').count(), 4);
  check('  MOVE is the one lit',
        await page.locator('.bw-mode.on').textContent(), 'MOVE');
  check('  and the menu is shut behind it',
        await page.locator('#app').evaluate((n) => n.classList.contains('hidden')), true);

  const rows = await page.locator('.bw-row label').evaluateAll(
    (ns) => ns.map((n) => n.textContent.trim()));
  check('moving offers the three directions',
        rows, ['EAST / WEST', 'NORTH / SOUTH', 'HEIGHT']);
  check('  showing where it is now',
        await page.locator('.bw-val').evaluateAll(
          (ns) => ns.map((n) => n.textContent.trim())), ['10.5', '-20.25', '44.02']);

  // ======================================================================
  // 3. every nudge sends its own axis
  // ======================================================================
  const nudge = async (label, which) => {
    await clear(page);
    await page.locator('.bw-row', { hasText: label }).locator('.bw-nudge').nth(which).click();
    await page.waitForTimeout(120);
    return last(page);
  };

  check('east pushes x the right way',   await nudge('EAST / WEST', 1),
        { action: 'nudge', axis: 'x', dir: 1 });
  check('  and west the other',          await nudge('EAST / WEST', 0),
        { action: 'nudge', axis: 'x', dir: -1 });
  check('north pushes y',                await nudge('NORTH / SOUTH', 1),
        { action: 'nudge', axis: 'y', dir: 1 });
  check('height pushes z',               await nudge('HEIGHT', 1),
        { action: 'nudge', axis: 'z', dir: 1 });

  // ======================================================================
  // 4. the other three modes
  // ======================================================================
  await clear(page);
  await page.locator('.bw-mode', { hasText: 'SIZE' }).click();
  await page.waitForTimeout(120);
  check('SIZE asks the client to switch', await last(page), { action: 'mode', mode: 'size' });

  await page.evaluate((d) => window.__send(Object.assign({}, d, { mode: 'size' })), SCREEN);
  await page.waitForTimeout(150);
  check('  and then offers the width alone',
        await page.locator('.bw-row label').evaluateAll(
          (ns) => ns.map((n) => n.textContent.trim())), ['WIDTH']);
  check('  in metres',
        await page.locator('.bw-val').textContent(), '6m');
  check('  which pushes the width',      await nudge('WIDTH', 1),
        { action: 'nudge', axis: 'width', dir: 1 });

  await page.evaluate((d) => window.__send(Object.assign({}, d, { mode: 'rotate' })), SCREEN);
  await page.waitForTimeout(150);
  check('ROTATE offers a facing and a tilt',
        await page.locator('.bw-row label').evaluateAll(
          (ns) => ns.map((n) => n.textContent.trim())), ['FACING', 'TILT']);
  check('  in degrees',
        await page.locator('.bw-val').evaluateAll(
          (ns) => ns.map((n) => n.textContent.trim())), ['214°', '0°']);
  check('  and turning pushes the heading', await nudge('FACING', 1),
        { action: 'nudge', axis: 'h', dir: 1 });

  await page.evaluate((d) => window.__send(Object.assign({}, d, { mode: 'confirm' })), SCREEN);
  await page.waitForTimeout(150);
  await clear(page);
  await page.locator('.bw-save').click();
  await page.waitForTimeout(120);
  check('CONFIRM saves', await last(page), { action: 'confirm' });

  // ======================================================================
  // 5. a podium spot is a person, not a panel
  // ======================================================================
  const PODIUM = Object.assign({}, SCREEN, {
    sel: 'p0', mode: 'size', item: { kind: 'p', x: 1, y: 2, z: 3, h: 90 }
  });
  await page.evaluate((d) => window.__send(d), PODIUM);
  await page.waitForTimeout(150);
  check('a podium spot has no width to set',
        await page.locator('.bw-row').count(), 0);
  check('  and says so rather than showing an empty box',
        await page.locator('.bw-none').count(), 1);

  await page.evaluate((d) => window.__send(Object.assign({}, d, { mode: 'rotate' })), PODIUM);
  await page.waitForTimeout(150);
  check('  it can still be turned',
        await page.locator('.bw-row label').evaluateAll(
          (ns) => ns.map((n) => n.textContent.trim())), ['FACING']);
  check('  but not tilted, because it is a person',
        await page.locator('.bw-row', { hasText: 'TILT' }).count(), 0);

  // ======================================================================
  // 6. step size, picking a target, and the two footers
  // ======================================================================
  await page.evaluate((d) => window.__send(d), SCREEN);
  await page.waitForTimeout(150);

  check('the step size is shown as it stands',
        await page.locator('.bw-speed-val').textContent(), '1x');
  await clear(page);
  await page.locator('.bw-speed-row .bw-btn').nth(1).click();
  await page.waitForTimeout(120);
  check('  and can be raised', await last(page), { action: 'speed', dir: 1 });
  await clear(page);
  await page.locator('.bw-speed-row .bw-btn').nth(0).click();
  await page.waitForTimeout(120);
  check('  and lowered',       await last(page), { action: 'speed', dir: -1 });

  check('every board and podium spot is listed',
        await page.locator('.bw-target:not(.add):not(.del)').count(), 3);
  check('  the one being moved is lit',
        await page.locator('.bw-target.on').textContent(), 'SCREEN 1 — TOP');
  await clear(page);
  await page.locator('.bw-target').nth(2).click();
  await page.waitForTimeout(120);
  check('  and another can be picked', await last(page), { action: 'pick', sel: 'p1' });

  await clear(page);
  await page.locator('.bw-ghost', { hasText: 'PUT IT WHERE I STAND' }).click();
  await page.waitForTimeout(120);
  check('it can be dropped where the player stands', await last(page), { action: 'here' });

  await clear(page);
  await page.locator('.bw-ghost', { hasText: 'BACK TO THE MENU' }).click();
  await page.waitForTimeout(120);
  check('and the list is one click away', await last(page), { action: 'back' });

  // ======================================================================
  // 7. handing the mouse back to the game
  // ======================================================================
  await page.evaluate((d) => window.__send(d), SCREEN);
  await page.waitForTimeout(150);
  check('the chip offers to let you walk',
        (await page.locator('.bw-walk').innerText()).replace(/\s+/g, ' ').trim(),
        'CLICK HERE TO MOVE THE PLAYER');
  await clear(page);
  await page.locator('.bw-walk').click();
  await page.waitForTimeout(120);
  check('  and asks the client to drop focus', await last(page),
        { action: 'walk', on: true });

  await page.evaluate((d) => window.__send(Object.assign({}, d, { walk: true })), SCREEN);
  await page.waitForTimeout(150);
  check('walking dims the panel',
        await page.locator('#bw').evaluate((n) => n.classList.contains('walking')), true);
  check('  and the chip says how to come back',
        (await page.locator('.bw-walk').innerText()).replace(/\s+/g, ' ').trim(),
        'PRESS F5 TO EDIT');
  check('  nothing else is clickable',
        await page.locator('.bw-modes').evaluate(
          (n) => getComputedStyle(n).pointerEvents), 'none');
  check('  except the chip',
        await page.locator('.bw-walk').evaluate(
          (n) => getComputedStyle(n).pointerEvents), 'auto');

  await page.evaluate((d) => window.__send(d), SCREEN);
  await page.waitForTimeout(150);

  // ======================================================================
  // 8. it does not cover the board it is moving
  // ======================================================================
  const box = await page.locator('#bw').boundingBox();
  check('the panel keeps to the top of the screen', box.y + box.height < 900 * 0.75, true);
  check('  and to one side of the middle of it',    box.width < 1600 * 0.35, true);

  await page.evaluate(() => window.__send({ action: 'boardWorld', on: false }));
  await page.waitForTimeout(150);
  check('leaving world mode takes the panel away',
        await page.locator('#bw').evaluate((n) => n.classList.contains('hidden')), true);

  // ======================================================================
  // 9. the mouse layer: dragging a handle in the world
  // ======================================================================
  // The handles are drawn by the client and it alone knows where they are, so
  // all this side does is report the cursor. What it must get right is the
  // space: normalized 0..1, the same one the client projects into.
  await page.evaluate((d) => window.__send(d), SCREEN);
  await page.waitForTimeout(150);

  check('the mouse layer is up with the panel',
        await page.locator('#bw-catch').evaluate((n) => !n.classList.contains('hidden')), true);
  check('  and sits under it, so the buttons take their clicks first',
        await page.evaluate(() => {
          const z = (id) => parseInt(getComputedStyle(document.getElementById(id)).zIndex, 10);
          return z('bw-catch') < z('bw');
        }), true);

  await clear(page);
  await page.mouse.move(800, 450);
  await page.mouse.down();
  await page.waitForTimeout(120);
  check('pressing on it asks the client what is under the cursor',
        await last(page), { action: 'grab', x: 0.5, y: 0.5 });

  await clear(page);
  await page.mouse.move(960, 450);
  await page.waitForTimeout(120);
  check('  and moving reports where the cursor went',
        await last(page), { action: 'drag', x: 0.6, y: 0.5 });

  await clear(page);
  await page.mouse.up();
  await page.waitForTimeout(120);
  check('letting go tells the client to let go', await last(page), { action: 'drop' });

  // a press that lands on nothing must not leave the page thinking it holds
  // something, or the next mouseup posts a drop for a drag that never was
  await page.evaluate(() => { window.__grab = 'miss'; });
  await page.mouse.move(700, 300);
  await page.mouse.down();
  await page.waitForTimeout(120);
  await clear(page);
  await page.mouse.up();
  await page.waitForTimeout(120);
  check('a press that hit nothing sends no drop', await last(page), null);
  await page.evaluate(() => { window.__grab = 'grab'; });

  // walking hands the mouse back to the game, so the layer stands down
  await page.evaluate((d) => window.__send(Object.assign({}, d, { walk: true })), SCREEN);
  await page.waitForTimeout(150);
  check('walking takes the mouse layer away',
        await page.locator('#bw-catch').evaluate((n) => n.classList.contains('hidden')), true);
  await page.evaluate((d) => window.__send(d), SCREEN);
  await page.waitForTimeout(150);

  // ======================================================================
  // 10. adding one: pick the spot first
  // ======================================================================
  await clear(page);
  await page.locator('.bw-target.add', { hasText: 'SCREEN' }).click();
  await page.waitForTimeout(120);
  check('adding a screen asks the client for the marker',
        await last(page), { action: 'place', kind: 's' });
  await clear(page);
  await page.locator('.bw-target.add', { hasText: 'PODIUM' }).click();
  await page.waitForTimeout(120);
  check('  and a podium spot the same way',
        await last(page), { action: 'place', kind: 'p' });

  await page.evaluate((d) => window.__send(Object.assign({}, d, { placing: 's' })), SCREEN);
  await page.waitForTimeout(150);
  check('placing replaces the panel with where-does-it-go',
        await page.locator('.bw-place').count(), 1);
  check('  and the controls are out of the way',
        await page.locator('.bw-modes').count(), 0);
  check('  the cursor says you are placing something',
        await page.locator('#bw-catch').evaluate((n) => n.classList.contains('placing')), true);

  await clear(page);
  await page.mouse.move(700, 600);
  await page.mouse.down();
  await page.mouse.up();
  await page.waitForTimeout(150);
  check('clicking the ground puts it there',
        await last(page), { action: 'placeHere' });

  await clear(page);
  await page.locator('.bw-ghost', { hasText: 'CANCEL' }).click();
  await page.waitForTimeout(120);
  check('  or it can be called off', await last(page), { action: 'placeCancel' });

  await page.evaluate((d) => window.__send(d), SCREEN);
  await page.waitForTimeout(150);

  // ======================================================================
  // 11. removing one, and letting the height go back to automatic
  // ======================================================================
  await clear(page);
  await page.locator('.bw-target.del').click();
  await page.waitForTimeout(120);
  check('the one being moved can be removed', await last(page), { action: 'remove' });

  await page.evaluate((d) => window.__send(Object.assign({}, d, { targets: [d.targets[0]] })), SCREEN);
  await page.waitForTimeout(150);
  check('  but not the last one left', await page.locator('.bw-target.del').count(), 0);

  await page.evaluate((d) => window.__send(Object.assign({}, d, { mode: 'size' })), SCREEN);
  await page.waitForTimeout(150);
  check('a board on automatic height is not offered a reset',
        await page.locator('.bw-ghost', { hasText: 'AUTO HEIGHT' }).count(), 0);

  await page.evaluate((d) => window.__send(Object.assign({}, d, { mode: 'size',
    item: Object.assign({}, d.item, { height: 4.2 }) })), SCREEN);
  await page.waitForTimeout(150);
  check('  one that was dragged taller is',
        await page.locator('.bw-ghost', { hasText: 'AUTO HEIGHT' }).count(), 1);
  await clear(page);
  await page.locator('.bw-ghost', { hasText: 'AUTO HEIGHT' }).click();
  await page.waitForTimeout(120);
  check('  and it hands the height back', await last(page), { action: 'autoHeight' });

  // ======================================================================
  // 12. a held nudge stops when you let go
  // ======================================================================
  // Holding + repeats. The client answers every nudge with a fresh payload and
  // the panel is rebuilt from it, which takes the button being held out of the
  // document — so its own mouseup never arrives. Watched on the button alone,
  // the repeat ran for ever and the board span on its own.
  await page.evaluate((d) => window.__send(Object.assign({}, d, { mode: 'rotate' })), SCREEN);
  await page.waitForTimeout(150);

  const plus = page.locator('.bw-row', { hasText: 'FACING' }).locator('.bw-nudge').nth(1);
  const plusBox = await plus.boundingBox();
  await clear(page);
  await page.mouse.move(plusBox.x + plusBox.width / 2, plusBox.y + plusBox.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(600);        // past the repeat's first delay

  const held = await page.evaluate(() =>
    window.__posted.filter((x) => x.body && x.body.action === 'nudge').length);
  check('holding the button repeats', held > 1, true);

  // the client answers, and the panel is rebuilt under the cursor
  await page.evaluate((d) => window.__send(Object.assign({}, d, { mode: 'rotate' })), SCREEN);
  await page.waitForTimeout(150);
  await clear(page);
  await page.waitForTimeout(300);
  check('  a rebuild under the cursor stops it', await page.evaluate(() =>
    window.__posted.filter((x) => x.body && x.body.action === 'nudge').length), 0);

  // and letting go anywhere at all stops it, not only over the button
  await page.mouse.down();
  await page.waitForTimeout(500);
  await page.mouse.move(40, 800);
  await page.mouse.up();
  await page.waitForTimeout(150);
  await clear(page);
  await page.waitForTimeout(400);
  check('letting go away from the button stops it too', await page.evaluate(() =>
    window.__posted.filter((x) => x.body && x.body.action === 'nudge').length), 0);

  // ======================================================================
  // 13. the panel gets out of the way of the thing it is moving
  // ======================================================================
  await page.evaluate((d) => window.__send(d), SCREEN);
  await page.waitForTimeout(150);

  const faded = () => page.locator('#bw').evaluate(
    (n) => n.classList.contains('dragging'));

  check('the panel is solid to begin with', await faded(), false);
  await page.mouse.move(800, 450);
  await page.mouse.down();
  await page.waitForTimeout(160);
  check('  and fades out while a handle is held', await faded(), true);
  await page.mouse.up();
  await page.waitForTimeout(160);
  check('  then comes back when you let go',      await faded(), false);

  // a grab that hit nothing is not a drag, so the panel stays where it is
  await page.evaluate(() => { window.__grab = 'miss'; });
  await page.mouse.down();
  await page.waitForTimeout(160);
  check('a press that hit no handle does not fade it', await faded(), false);
  await page.mouse.up();
  await page.evaluate(() => { window.__grab = 'grab'; });
  await page.waitForTimeout(120);

  // and it can be put away by hand, for a longer look
  await page.locator('.bw-ghost', { hasText: 'HIDE THE PANEL' }).click();
  await page.waitForTimeout(150);
  check('putting the panel away leaves the controls behind',
        await page.locator('.bw-modes, .bw-pad, .bw-targets').count(), 0);
  check('  with a way back',
        await page.locator('.bw-ghost', { hasText: 'SHOW THE PANEL' }).count(), 1);
  check('  and the walk chip still there, because it is the way out',
        await page.locator('.bw-walk').count(), 1);

  await page.locator('.bw-ghost', { hasText: 'SHOW THE PANEL' }).click();
  await page.waitForTimeout(150);
  check('bringing it back brings the controls with it',
        await page.locator('.bw-modes').count(), 1);

  // the walk chip is the one thing that must always take a click
  await clear(page);
  await page.locator('.bw-walk').click();
  await page.waitForTimeout(120);
  check('the walk chip takes its click', await last(page), { action: 'walk', on: true });

  await page.evaluate((d) => window.__send(d), SCREEN);
  await page.waitForTimeout(150);

  check('nothing threw along the way', errors, []);

  await browser.close();
  console.log();
  console.log(fails === 0 ? `ALL PASS (${checks} checks)` : `${fails} FAILED`);
  process.exit(fails === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
