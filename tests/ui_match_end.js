/* The screens between rounds and at the end of a match, in a real browser.
 *
 *   node tests/ui_match_end.js
 *
 * Two of these were reported from screenshots rather than from logs: a 3-1
 * round shown as "1 | 0", and FIGHT appearing on some rounds and not others.
 * Both are timing and serialisation, which only a rendered page shows.
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

const BOOT = {
  player: { userId: 1, name: 'ME', rankId: 2, tier: 'silver', rankColor: '#aaa' },
  maxParty: 5, modes: [], allModes: [], maps: [], weaponPresets: [],
  matchTypes: [], ranks: [], modePool: {}
};

const END = {
  matchId: 'm1', winner: 1, yourTeam: 1, result: 'VICTORY', reason: 'COMPLETE',
  ranked: false, scores: { a: 3, b: 1 }, teamA: 'ME', teamB: 'BOT x1',
  stats: { kills: 3, deaths: 1, assists: 0, headshots: 3, damage: 600 },
  scoreboard: [{ userId: 1, name: 'ME', team: 1, kills: 3, deaths: 1, assists: 0,
                 headshots: 3, damage: 600, score: 300 }],
  mvp: { name: 'ME', kills: 3, deaths: 1, headshots: 3, damage: 600 }
};

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));

  await page.addInitScript(SHIM);
  await page.goto(UI);
  await page.evaluate((b) => {
    window.__send({ action: 'open', page: 'ranked', theme: {}, brand: {}, silent: true });
    window.__send({ action: 'boot', data: b });
    window.__send({ action: 'close' });
  }, BOOT);
  await page.waitForTimeout(200);

  // ======================================================================
  // 1. the round score
  // ======================================================================
  // A Lua table keyed 1 and 2 is a sequence, so it crosses as the ARRAY
  // [a,b] — and ["1"] on an array is the SECOND element while ["2"] is
  // nothing at all. That is how a 3-1 round was displayed as "1 | 0".
  const roundEnd = (scores) => page.evaluate((sc) => window.__send({
    action: 'round',
    data: { phase: 'end', round: 4, winner: 1, myTeam: 1, reason: 'ELIMINATION', scores: sc }
  }), scores);

  await roundEnd({ a: 3, b: 1 });
  await page.waitForTimeout(120);
  check('a 3-1 round reads 3 and 1',
        [await page.locator('#phase-score-a').textContent(),
         await page.locator('#phase-score-b').textContent()], ['3', '1']);

  // the shape that produced the bug, read correctly rather than silently wrong
  await roundEnd([3, 1]);
  await page.waitForTimeout(120);
  check('  and so does the raw array Lua would have sent',
        [await page.locator('#phase-score-a').textContent(),
         await page.locator('#phase-score-b').textContent()], ['3', '1']);

  await roundEnd({ a: 0, b: 0 });
  await page.waitForTimeout(120);
  check('  0-0 is drawn as 0-0, not blank',
        [await page.locator('#phase-score-a').textContent(),
         await page.locator('#phase-score-b').textContent()], ['0', '0']);

  // ======================================================================
  // 2. the banner, and the board that no longer opens with it
  // ======================================================================
  await roundEnd({ a: 3, b: 1 });
  await page.waitForTimeout(120);
  check('winning a round says so',
        await page.locator('#phase-band').evaluate((n) => n.classList.contains('win')), true);
  check('  in the player\'s language',
        await page.locator('#phase-word').textContent(), 'VICTORY');
  check('  and it is drawn big',
        await page.locator('#phase-word').evaluate(
          (n) => parseInt(getComputedStyle(n).fontSize, 10) >= 80), true);

  await page.evaluate(() => window.__send({
    action: 'round',
    data: { phase: 'end', round: 5, winner: 2, myTeam: 1, scores: { a: 3, b: 2 } } }));
  await page.waitForTimeout(120);
  check('losing one says that instead',
        await page.locator('#phase-band').evaluate((n) => n.classList.contains('loss')), true);

  check('the scoreboard is not forced open with it',
        await page.locator('#scoreboard').evaluate((n) => n.classList.contains('hidden')), true);

  // ======================================================================
  // 3. FIGHT, which used to come and go
  // ======================================================================
  // The countdown is the client's own interval; the server's `live` event
  // arrives on its own schedule and used to wipe the dial before the
  // countdown reached zero. Which one won was down to ping.
  const countdown = () => page.evaluate(() => window.__send({
    action: 'round', data: { phase: 'countdown', round: 1, seconds: 2 } }));

  await countdown();
  await page.waitForTimeout(2400);
  check('the countdown ends on FIGHT',
        await page.locator('#phase-word').textContent(), 'FIGHT');

  // and now the race: live lands in the middle of the countdown
  await countdown();
  await page.waitForTimeout(200);
  await page.evaluate(() => window.__send({ action: 'round', data: { phase: 'live' } }));
  await page.waitForTimeout(2400);
  check('live arriving mid-countdown does not steal FIGHT',
        await page.locator('#phase-word').textContent(), 'FIGHT');
  check('  and the band is still the start one',
        await page.locator('#phase-band').evaluate((n) => n.classList.contains('start')), true);

  /* A band already on screen is also left alone — FIGHT has to stay up long
     enough to read, and `live` lands right behind it. */
  await page.evaluate(() => window.__send({ action: 'round', data: { phase: 'live' } }));
  await page.waitForTimeout(120);
  check('live behind a FIGHT already up leaves it alone',
        await page.locator('#phase-band').evaluate((n) => n.classList.contains('start')), true);

  // but with neither a countdown nor a band, it does clear the phase
  await page.evaluate(() => {
    window.__send({ action: 'round', data: { phase: 'end', round: 1, winner: 1, myTeam: 1,
                                             scores: { a: 1, b: 0 } } });
  });
  await page.waitForTimeout(120);
  await page.evaluate(() => {
    document.getElementById('phase-band').className = 'ph-band hidden';
    window.__send({ action: 'round', data: { phase: 'live' } });
  });
  await page.waitForTimeout(150);
  check('live with nothing running clears the phase',
        await page.locator('#phase').evaluate((n) => n.classList.contains('hidden')), true);

  // ======================================================================
  // 4. MVP first, then the result
  // ======================================================================
  await page.evaluate((d) => window.__send({
    action: 'matchEnd', data: d, dismissHint: 'BACKSPACE', autoClose: 0, rankCfg: {} }), END);
  await page.waitForTimeout(250);

  check('the MVP is what comes up first',
        await page.locator('#modal-mvp').evaluate((n) => !n.classList.contains('hidden')), true);
  check('  and the result is waiting behind it',
        await page.locator('#modal-result').evaluate((n) => n.classList.contains('hidden')), true);
  check('  the MVP names the player',
        await page.locator('#mvp-name').textContent(), 'ME');
  check('  and says which key moves on',
        await page.locator('#mvp-key').textContent(), 'BACKSPACE');

  await page.locator('#mvp-next').click();
  await page.waitForTimeout(200);
  check('pressing it takes the MVP away',
        await page.locator('#modal-mvp').evaluate((n) => n.classList.contains('hidden')), true);
  check('  and brings the result up',
        await page.locator('#modal-result').evaluate((n) => !n.classList.contains('hidden')), true);
  check('  with the right score on it',
        [await page.locator('#result-a').textContent(),
         await page.locator('#result-b').textContent()], ['3', '1']);

  // the dismiss key takes the MVP first as well, not both screens at once
  await page.evaluate((d) => {
    document.getElementById('modal-result').classList.add('hidden');
    window.__send({ action: 'matchEnd', data: d, dismissHint: 'BACKSPACE', autoClose: 0, rankCfg: {} });
  }, END);
  await page.waitForTimeout(250);
  await page.evaluate(() => window.__send({ action: 'closeResult' }));
  await page.waitForTimeout(200);
  check('the dismiss key moves past the MVP, it does not skip the result',
        [await page.locator('#modal-mvp').evaluate((n) => n.classList.contains('hidden')),
         await page.locator('#modal-result').evaluate((n) => !n.classList.contains('hidden'))],
        [true, true]);

  // a match with no MVP goes straight to the result
  await page.evaluate((d) => {
    document.getElementById('modal-result').classList.add('hidden');
    const noMvp = Object.assign({}, d); delete noMvp.mvp;
    window.__send({ action: 'matchEnd', data: noMvp, dismissHint: 'BACKSPACE', autoClose: 0, rankCfg: {} });
  }, END);
  await page.waitForTimeout(200);
  check('no MVP means the result comes straight up',
        await page.locator('#modal-result').evaluate((n) => !n.classList.contains('hidden')), true);
  check('  and no MVP screen is shown',
        await page.locator('#modal-mvp').evaluate((n) => n.classList.contains('hidden')), true);

  check('nothing threw along the way', errors, []);

  await browser.close();
  console.log();
  console.log(fails === 0 ? `ALL PASS (${checks} checks)` : `${fails} FAILED`);
  process.exit(fails === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
