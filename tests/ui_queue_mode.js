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

  check('the search button starts on 1V1',
        await page.locator('#btn-start-mode').innerText(), '1V1');

  await tab('2V2').click();
  await page.waitForTimeout(80);
  check('  picking 2V2 selects it', await mode(), '2v2');
  check('  and the tab shows as the active one',
        await tab('2V2').evaluate((n) => n.classList.contains('active')), true);
  /* The mode line lives inside the search button, which only the queue message
     used to redraw — so the tab said 2V2 and the button still said 1V1 until
     you pressed search. */
  check('  and the search button says so without being pressed',
        await page.locator('#btn-start-mode').innerText(), '2V2');

  await tab('3V3').click();
  await page.waitForTimeout(80);
  check('  it follows every tab, not just the first',
        await page.locator('#btn-start-mode').innerText(), '3V3');
  await tab('2V2').click();
  await page.waitForTimeout(80);

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
  // 2b. a running search owns the mode
  // ======================================================================
  await page.evaluate(() => window.__send({ action: 'queue', data: {
    state: 'SEARCHING', mode: '2v2', elapsed: 4 } }));
  await page.waitForTimeout(120);
  check('while searching the button names the mode being searched',
        await page.locator('#btn-start-mode').innerText(), '2V2');

  await page.evaluate(() => { window.__posted = []; });
  await tab('5V5').click();
  await page.waitForTimeout(120);
  check('  and the tabs cannot move under it', await mode(), '2v2');
  check('  the button is not rewritten either',
        await page.locator('#btn-start-mode').innerText(), '2V2');
  check('  nothing is sent to the server', await page.evaluate(() => window.__posted.length), 0);

  await page.evaluate(() => window.__send({ action: 'queue', data: { state: 'IDLE' } }));
  await page.waitForTimeout(120);
  check('once the search stops the tabs work again', await (async () => {
    await tab('5V5').click();
    await page.waitForTimeout(80);
    return mode();
  })(), '5v5');
  await tab('2V2').click();
  await page.waitForTimeout(80);

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

  // ======================================================================
  // 5. the picture on a lobby seat
  // ======================================================================
  // Every other avatar in the interface draws the player's picture over their
  // initial. The lobby seat drew only the initial — there was no <img> in the
  // markup at all and the party payload carried no avatar to put in one — so
  // the biggest portrait on screen was the one place that never showed a face.
  const seats = async (members) => {
    await page.evaluate((m) => {
      window.__send({ action: 'party', data: { id: 'p1', leader: 1, members: m } });
    }, members);
    await page.waitForTimeout(120);
    return page.evaluate(() => Array.from(
      document.querySelectorAll('#party-slots .slot-av')).map((n) => {
        const img = n.querySelector('img');
        const box = n.getBoundingClientRect();
        const ib  = img && img.getBoundingClientRect();
        return {
          src: img ? img.getAttribute('src') : null,
          initial: (n.childNodes[0] || {}).textContent || '',
          // it has to cover the letter, not sit next to it
          covers: !!ib && Math.round(ib.width) === Math.round(box.width)
                       && Math.round(ib.height) === Math.round(box.height),
          round: !!img && getComputedStyle(img).borderRadius !== '0px'
        };
      }));
  };

  // a real one-pixel image, so the picture actually loads here rather than
  // leaving a failed request behind for the no-errors check at the end
  const PIX = 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==';

  let s = await seats([
    { userId: 1, name: 'ME', rankId: 2, leader: true, ready: true, avatar: PIX },
    { userId: 2, name: 'OTHER', rankId: 2, ready: true, avatar: PIX + '#2' }
  ]);
  check('a seat draws the picture the server resolved', s[0].src, PIX);
  check('  for the other players too', s[1].src, PIX + '#2');
  check('  over the whole portrait',   s[0].covers, true);
  check('  cut to the same circle',    s[0].round, true);
  check('  with the initial still underneath as the fallback',
        s[0].initial, 'M');

  // A player with no picture at all is the old behaviour, unchanged: the
  // letter, and no broken image icon next to it.
  s = await seats([{ userId: 1, name: 'ME', rankId: 2, leader: true, ready: true }]);
  check('no picture leaves the initial alone', s[0].src, null);
  check('  and the letter is still there',     s[0].initial, 'M');

  // ======================================================================
  // 6. the map card is not shared with the match HUD
  // ======================================================================
  // The card that names the map and both rosters comes up before the first
  // round. The HUD came up with it, so a score of 0-0, a clock at 0:00 and an
  // empty magazine sat over the card saying nothing and covering it.
  const hudShown = () => page.evaluate(() => {
    const h = document.getElementById('hud');
    return {
      hidden: h.classList.contains('hidden'),
      muted: h.classList.contains('muted'),
      opacity: getComputedStyle(h).opacity,
      showcase: !document.getElementById('showcase').classList.contains('hidden')
    };
  });

  await page.evaluate(() => window.__send({ action: 'matchSetup', data: {
    matchId: 'm1', mode: '1v1', modeLabel: '1V1',
    map: { id: 'mc', name: 'MINECRAFT' },
    teamNames: { 1: 'TEAM A', 2: 'TEAM B' },
    roster: [{ userId: 1, name: 'ME', team: 1, rank: 'Gold' },
             { userId: 2, name: 'BOT', team: 2, rank: 'Gold' }],
    settings: { rounds: 9, roundsToWin: 5 },
    hudCfg: { showcase: { enabled: true, duration: 8 } }
  } }));
  await page.waitForTimeout(120);
  let h = await hudShown();
  check('the map card is up', h.showcase, true);
  check('  and the HUD is out of the way while it is', h.muted, true);
  check('  which means it is not on screen',           h.opacity, '0');
  check('  without being switched off',                h.hidden, false);

  // Once the card goes, the HUD is back — the round is about to start.
  await page.evaluate(() => window.hideShowcase());
  await page.waitForTimeout(450);          // it fades back rather than snapping
  h = await hudShown();
  check('the card goes and the HUD comes back', h.muted, false);
  check('  on screen again',                    h.opacity, '1');

  // And a HUD that was switched off entirely stays off: stepping back for the
  // card must not be able to turn it on.
  await page.evaluate(() => {
    window.__send({ action: 'hudVisible', value: false });
    window.__send({ action: 'showcase' });
  });
  await page.waitForTimeout(80);
  h = await hudShown();
  check('a HUD switched off stays off through all of it', h.hidden, true);

  check('no script error the whole way through', errors, []);

  await browser.close();
  console.log(fails ? `\n${fails} FAILED of ${checks}` : `\nALL PASS (${checks} checks)`);
  process.exit(fails ? 1 : 0);
})();
