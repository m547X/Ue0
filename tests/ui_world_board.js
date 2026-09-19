/* The page that gets painted onto the board out in the world.
 *
 *   node tests/ui_world_board.js
 *
 * This one is not the menu. It is rendered into a texture at a fixed size and
 * stretched over a flat surface in the world, so two things decide whether it
 * is any good and neither of them shows in the code:
 *
 *   - nothing may spill outside the 1280x720 it is given, because there is no
 *     scrollbar out there and anything past the edge is simply gone, and
 *   - it must sit perfectly still once drawn, because every change repaints
 *     the texture on every machine that can see the board.
 *
 * So the real page is loaded in Chromium at the texture's size, fed the same
 * payload the client sends, and then measured and watched.
 */
const path = require('path');
const { chromium } = require(process.env.PW || '/opt/node22/lib/node_modules/playwright');

const PAGE = 'file://' + path.resolve(__dirname, '../M5_RankedPvP/Files/ui/board.html');
const W = 1280, H = 720;

let fails = 0, checks = 0;
function check(name, got, want) {
  checks++;
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { fails++; console.log(`FAIL ${name.padEnd(56)} got=${JSON.stringify(got)} want=${JSON.stringify(want)}`); }
  else console.log(`ok   ${name.padEnd(56)} ${JSON.stringify(got)}`);
}

/* Counts every way a page has of waking itself up. The board must use none of
   them: a repainting texture is paid for by everyone standing in front of it. */
const SPY = () => {
  window.__woke = { interval: 0, timeout: 0, frame: 0, fetch: 0 };
  const si = window.setInterval, st = window.setTimeout, raf = window.requestAnimationFrame;
  window.setInterval = function (...a) { window.__woke.interval++; return si.apply(window, a); };
  window.setTimeout = function (...a) { window.__woke.timeout++; return st.apply(window, a); };
  window.requestAnimationFrame = function (...a) { window.__woke.frame++; return raf.apply(window, a); };
  window.fetch = function () { window.__woke.fetch++; return Promise.reject(new Error('no')); };
  window.__send = (m) => window.dispatchEvent(new MessageEvent('message', { data: m }));
};

const player = (i, over) => Object.assign({
  position: i, userId: 1000 + i, name: 'PLAYER ' + i, rank: 'GOLD III',
  color: '#E8B33A', level: 30 + i, kills: 900 - i * 7, deaths: 400 + i * 3,
  wins: 120 - i, losses: 40 + i, kd: (2.25 - i * 0.05).toFixed(2), rp: 9000 - i * 137
}, over || {});

const ROWS = [];
for (let i = 1; i <= 12; i++) ROWS.push(player(i));

const PAYLOAD = {
  action: 'board', rows: ROWS, max: 9, season: 'SEASON 3 STANDINGS',
  title: 'LEADERBOARD TOP 3', subtitle: 'LEADERBOARD OVERVIEW',
  theme: { accent: '#25D0A0', gold: '#FFC93C' },
  brand: { name: 'M5', accent: 'RANKED' }
};

/** Everything that is inside the board, and by how much it is not. */
const spill = (page) => page.evaluate((size) => {
  const b = document.getElementById('board').getBoundingClientRect();
  const out = [];
  document.querySelectorAll('.pod, .col, .base, .row, .grid, .brand, .stand, .table, .podium')
    .forEach((n) => {
      const r = n.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) return;
      if (r.right > b.right + 0.6 || r.bottom > b.bottom + 0.6 ||
          r.left < b.left - 0.6 || r.top < b.top - 0.6) {
        out.push(n.className + ' ' + JSON.stringify({
          l: Math.round(r.left), t: Math.round(r.top),
          r: Math.round(r.right), b: Math.round(r.bottom)
        }));
      }
    });
  return { out, w: Math.round(b.width), h: Math.round(b.height), page: size };
}, { w: W, h: H });

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const page = await browser.newPage({ viewport: { width: W, height: H } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));

  await page.addInitScript(SPY);
  await page.goto(PAGE);
  await page.waitForTimeout(150);

  // ======================================================================
  // 1. before the client has said anything
  // ======================================================================
  check('an untold board says so rather than sitting blank',
        await page.locator('#bd-empty').evaluate((n) => !n.classList.contains('hidden')), true);
  check('  and shows no standings', await page.locator('#bd-rows .row').count(), 0);
  check('  nor anybody on the podium',
        await page.locator('.pod:not(.empty-pod)').count(), 0);

  // ======================================================================
  // 2. the rows it was given
  // ======================================================================
  await page.evaluate((d) => window.__send(d), PAYLOAD);
  await page.waitForTimeout(150);

  check('the empty line goes once there is something to show',
        await page.locator('#bd-empty').evaluate((n) => n.classList.contains('hidden')), true);
  check('  it lists as many as it was told to, not all twelve',
        await page.locator('#bd-rows .row').count(), 9);
  check('  the header names ten columns',
        await page.locator('.grid.head > span').count(), 10);
  check('  and a row fills every one of them',
        await page.locator('#bd-rows .row').first().locator('> span').count(), 10);

  check('the season line is the one the server sent',
        await page.locator('#bd-season').textContent(), 'SEASON 3 STANDINGS');
  check('  and the brand is the one from the config',
        await page.locator('#bd-name').textContent(), 'M5');

  const first = await page.locator('#bd-rows .row').first().innerText();
  check('the leader is at the top with a place on them',
        /#1/.test(first) && /PLAYER 1/.test(first), true);
  check('  and their score is grouped, not a wall of digits',
        /8,863/.test(first), true);

  // ======================================================================
  // 3. the podium: the winner in the middle, and taller
  // ======================================================================
  check('three stand on the podium', await page.locator('.pod').count(), 3);
  const order = await page.locator('.pod').evaluateAll(
    (ns) => ns.map((n) => n.querySelector('.pod-name').textContent.trim()));
  check('  the winner stands in the middle, not on the left',
        order, ['PLAYER 2', 'PLAYER 1', 'PLAYER 3']);
  check('  wearing the crown',
        await page.locator('.pod.p1 .pod-crown').count(), 1);
  check('  and nobody else is',
        await page.locator('.pod:not(.p1) .pod-crown').count(), 0);

  check('  and each card stands on a numbered plinth',
        await page.locator('.base').evaluateAll(
          (ns) => ns.map((n) => n.textContent.trim())), ['2', '1', '3']);
  check('  no ordinary name is cut off either',
        await page.locator('.pod-name').evaluateAll(
          (ns) => ns.filter((n) => n.scrollWidth > n.clientWidth + 1).length), 0);

  const tops = await page.locator('.pod').evaluateAll(
    (ns) => ns.map((n) => Math.round(n.getBoundingClientRect().top)));
  check('  first place is raised above the other two',
        tops[1] < tops[0] && tops[1] < tops[2], true);
  const bases = await page.locator('.base').evaluateAll(
    (ns) => ns.map((n) => Math.round(n.getBoundingClientRect().height)));
  check('  because its plinth is the tallest',
        bases[1] > bases[0] && bases[0] > bases[2], true);
  const floor = await page.locator('.base').evaluateAll(
    (ns) => ns.map((n) => Math.round(n.getBoundingClientRect().bottom)));
  check('  and all three stand on the same floor',
        floor[0] === floor[1] && floor[1] === floor[2], true);

  const left = await page.locator('.podium').boundingBox();
  const table = await page.locator('.table').boundingBox();
  check('the podium is on the left and the standings on the right',
        left.x + left.width <= table.x + 1, true);

  // ======================================================================
  // 4. it stays inside the texture
  // ======================================================================
  const fit = await spill(page);
  check('the board is exactly the size of the texture', [fit.w, fit.h], [W, H]);
  check('  and nothing hangs off the edge of it', fit.out, []);
  check('  the page itself never has to scroll',
        await page.evaluate(() => [document.documentElement.scrollWidth,
                                   document.documentElement.scrollHeight]), [W, H]);

  // long names and long scores are what actually breaks a fixed panel
  const BIG = ROWS.map((r, i) => Object.assign({}, r, {
    name: i === 0 ? 'ABDULRAHMAN ALMUTAIRI' : r.name,
    rp: 1234567 - i, kills: 999999, wins: 123456
  }));
  await page.evaluate((d) => window.__send(d), Object.assign({}, PAYLOAD, { rows: BIG }));
  await page.waitForTimeout(150);
  const fitBig = await spill(page);
  check('a long name and a seven digit score still fit', fitBig.out, []);
  check('  and no name anywhere is cut in half',
        await page.locator('.pod-name').evaluateAll(
          (ns) => ns.filter((n) => n.scrollWidth > n.clientWidth + 1).length), 0);

  await page.evaluate((d) => window.__send(d), PAYLOAD);
  await page.waitForTimeout(120);

  // ======================================================================
  // 5. it holds still
  // ======================================================================
  // the rows and the cards are replaced wholesale when the page redraws, so a
  // mark left on one of them is the only way to see a repaint from out here
  const mark = () => page.evaluate(() => {
    document.querySelector('#bd-rows .row').dataset.mark = 'x';
    document.querySelector('#bd-stand .pod').dataset.mark = 'x';
  });
  const marks = () => page.evaluate(() => [
    document.querySelector('#bd-rows .row').dataset.mark,
    document.querySelector('#bd-stand .pod').dataset.mark
  ]);

  await mark();
  await page.evaluate((d) => window.__send(d), PAYLOAD);
  await page.evaluate((d) => window.__send(d), PAYLOAD);
  await page.waitForTimeout(200);
  check('the same rows sent again are not redrawn', await marks(), ['x', 'x']);

  const changed = ROWS.map((r, i) => Object.assign({}, r, { rp: r.rp + (i === 0 ? 1 : 0) }));
  await page.evaluate((d) => window.__send(d), Object.assign({}, PAYLOAD, { rows: changed }));
  await page.waitForTimeout(150);
  check('  but a real change is', await marks(), [undefined, undefined]);

  const woke = await page.evaluate(() => window.__woke);
  check('the page runs no clock of its own', woke.interval, 0);
  check('  no animation frames',              woke.frame, 0);
  check('  and asks the network for nothing', woke.fetch, 0);

  // ======================================================================
  // 6. names come from players, so they are not trusted
  // ======================================================================
  const NASTY = [player(1, { name: '<img src=x onerror="window.__pwn=1">' }),
                 player(2, { rank: '<b>oops</b>' }), player(3)];
  await page.evaluate((d) => window.__send(d), Object.assign({}, PAYLOAD, { rows: NASTY }));
  await page.waitForTimeout(150);
  check('a name with markup in it is shown, not run',
        await page.evaluate(() => window.__pwn), undefined);
  check('  and lands on the podium as written',
        await page.locator('.pod.p1 .pod-name').textContent(),
        '<img src=x onerror="window.__pwn=1">');

  // ======================================================================
  // 7. the look it is given
  // ======================================================================
  await page.evaluate((d) => window.__send(d), Object.assign({}, PAYLOAD, { rows: ROWS }));
  await page.waitForTimeout(150);
  check('the accent from the config reaches the page',
        await page.evaluate(() =>
          getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()),
        '#25D0A0');
  check('  and a rank keeps its own colour',
        await page.locator('#bd-rows .row').first().locator('.c-rank').evaluate(
          (n) => n.style.color), 'rgb(232, 179, 58)');

  // CEF is an old Chromium — these three are the ones that do not survive it
  const css = await page.evaluate(async () => {
    const r = await fetch('board.css').catch(() => null);
    return r ? r.text() : '';
  }).catch(() => '');
  const src = css || require('fs').readFileSync(
    path.resolve(__dirname, '../M5_RankedPvP/Files/ui/board.css'), 'utf8');
  check('the stylesheet keeps off color-mix', /color-mix\(/.test(src), false);
  check('  and off :has()',                   /:has\(/.test(src), false);
  check('  and blurs nothing',                /blur\(/.test(src), false);

  check('nothing threw along the way', errors, []);

  await page.screenshot({ path: path.resolve(__dirname, '../scratchpad/world_board.png') });

  await browser.close();
  console.log();
  console.log(fails === 0 ? `ALL PASS (${checks} checks)` : `${fails} FAILED`);
  process.exit(fails === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
