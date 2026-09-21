/* The leaderboard page: whose rank it claims you have, and who is on it.
 *
 *   node tests/ui_leaderboard.js
 *
 * Two things only the rendered page can answer.
 *
 * The card on the left says your rank next to the mode tab you are looking at.
 * It read that rank straight off the boot payload, which carries the DEFAULT
 * ladder — so a player who is Radiant at 1v1 and has never touched 2v2 was
 * shown as "Radiant · 2V2", and as Radiant on every other tab as well.
 *
 * And the table itself: it is the ladder for that mode, so anybody holding RP
 * belongs on it. It used to be built from matches still in m5_match_players,
 * which meant a server whose players had ranks but no recent matches showed an
 * empty table under the word LEADERBOARD.
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
  window.__send = (msg) => window.dispatchEvent(new MessageEvent('message', { data: msg }));
};

const MODES = [
  { id: '1v1', label: '1V1', teamSize: 1 },
  { id: '2v2', label: '2V2', teamSize: 2 },
  { id: '5v5', label: '5V5', teamSize: 5 }
];

const RANKS = [
  { id: 0,  name: 'Unranked', tier: 'UNRANKED', color: '#5A616D', rp: 0 },
  { id: 16, name: 'Diamond I', tier: 'DIAMOND', color: '#8E6BFF', rp: 1500 },
  { id: 23, name: 'Radiant',  tier: 'RADIANT',  color: '#FFE9A8', rp: 2600 }
];

const PIX = 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==';

/* The player is Radiant on the 1v1 ladder and has never played anything else,
   so there is no row for 2v2 or 5v5 at all — which is the whole point. */
const BOOT = {
  player: {
    userId: 1, name: '01', level: 5,
    rp: 2680, rank: 'Radiant', rankId: 23, tier: 'RADIANT', rankColor: '#FFE9A8',
    placement: { done: true, played: 5, total: 5, enabled: true },
    avatar: PIX
  },
  pool: '1v1',
  perModeRanks: true,
  modePool: { '1v1': '1v1', '2v2': '2v2', '5v5': '5v5' },
  pools: {
    '1v1': { rp: 2680, rank: 'Radiant', rankId: 23, tier: 'RADIANT',
             rankColor: '#FFE9A8', progress: { percent: 100, needed: 0 },
             placement: { done: true, played: 5, total: 5, enabled: true } }
  },
  modes: MODES, allModes: MODES, ranks: RANKS,
  maps: [], weaponPresets: [], matchTypes: [], loadouts: [],
  partyQueue: { autoMode: false, lockToPartySize: false,
                autoFill: { enabled: false, default: false } }
};

const ROWS = [
  { position: 1, userId: 900001, name: 'SHADOW', rp: 2680, rankId: 23,
    rank: 'Radiant', rankColor: '#FFE9A8', tier: 'RADIANT',
    wins: 301, losses: 111, kills: 2184, deaths: 946, kd: 2.31, avatar: PIX },
  { position: 2, userId: 900002, name: 'VIPER', rp: 2310, rankId: 16,
    rank: 'Diamond I', rankColor: '#8E6BFF', tier: 'DIAMOND',
    wins: 268, losses: 119, kills: 1903, deaths: 980, kd: 1.94, avatar: PIX },
  { position: 3, userId: 1, name: '01', rp: 1500, rankId: 16,
    rank: 'Diamond I', rankColor: '#8E6BFF', tier: 'DIAMOND',
    wins: 0, losses: 0, kills: 0, deaths: 0, kd: 0 }
];

const board = (mode, rows) => ({
  action: 'data',
  data: { what: 'leaderboard', board: 'mode', mode, page: 1, pool: mode,
          rows: rows, stats: { wins: 0, matches: 0, kills: 0, deaths: 0, kd: 0, points: 0 } }
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
    window.__send({ action: 'open', page: 'leaderboard', theme: {}, brand: {}, silent: true });
    window.__send({ action: 'boot', data: boot });
  }, BOOT);
  await page.waitForTimeout(200);

  const mine = () => page.evaluate(() => {
    const n = document.querySelector('#lb-me .who span');
    return n ? n.textContent.replace(/\s+/g, ' ').trim() : null;
  });
  const tab = (label) => page.locator('#lb-tabs .mtab', { hasText: label }).first();

  check('the interface loads with no script error', errors, []);

  // ======================================================================
  // 1. the rank beside the mode is the rank on that mode's ladder
  // ======================================================================
  await page.evaluate((m) => window.__send(m), board('1v1', ROWS));
  await page.waitForTimeout(150);
  check('on the mode they play, their real rank', await mine(), 'Radiant · 1V1');

  await tab('2V2').click();
  await page.waitForTimeout(120);
  await page.evaluate((m) => window.__send(m), board('2v2', []));
  await page.waitForTimeout(150);
  check('on a ladder they have never touched, Unranked',
        await mine(), 'Unranked · 2V2');

  await tab('5V5').click();
  await page.waitForTimeout(120);
  await page.evaluate((m) => window.__send(m), board('5v5', []));
  await page.waitForTimeout(150);
  check('  and on every other one too', await mine(), 'Unranked · 5V5');

  // the crest beside it has to follow as well, not stay gold
  const crestColour = () => page.evaluate(() =>
    (document.querySelector('#lb-me .who span svg') || {}).style.color);
  check('the crest is not still the top rank colour', await crestColour(), 'rgb(90, 97, 109)');

  await tab('1V1').click();
  await page.waitForTimeout(120);
  await page.evaluate((m) => window.__send(m), board('1v1', ROWS));
  await page.waitForTimeout(150);
  check('back on their own ladder it is gold again', await crestColour(), 'rgb(255, 233, 168)');

  // ======================================================================
  // 2. a server whose ladder has people on it is not an empty table
  // ======================================================================
  const rows = () => page.evaluate(() => Array.from(
    document.querySelectorAll('#lb-body .brow')).map((n) => ({
      pos: n.querySelector('.pos').textContent,
      name: n.querySelector('.who b').textContent,
      you: n.classList.contains('you'),
      pic: (n.querySelector('.who .av img') || {}).getAttribute
           ? n.querySelector('.who .av img').getAttribute('src') : null,
      letter: (n.querySelector('.who .av .ini') || {}).textContent || null
    })));

  const r = await rows();
  check('everybody on the ladder is listed', r.length, 3);
  check('  in ladder order',                 r.map((x) => x.name), ['SHADOW', 'VIPER', '01']);
  check('  and your own row is marked',      r[2].you, true);

  // ======================================================================
  // 3. the pictures
  // ======================================================================
  check('a listed player shows their picture', r[0].pic, PIX);
  check('  with the initial underneath',       r[0].letter, 'S');
  check('a player with no picture keeps the letter', r[2].pic, null);
  check('  which is still drawn',                    r[2].letter, '0');

  const meCard = await page.evaluate(() => {
    const av = document.querySelector('#lb-me .av');
    const img = av.querySelector('img');
    const a = av.getBoundingClientRect();
    const b = img && img.getBoundingClientRect();
    return {
      src: img ? img.getAttribute('src') : null,
      covers: !!b && Math.round(b.width) === Math.round(a.width)
                  && Math.round(b.height) === Math.round(a.height)
    };
  });
  check('your own card shows your picture', meCard.src, PIX);
  check('  filling the whole box',          meCard.covers, true);

  // ======================================================================
  // 4. an empty ladder says it is empty, not that there are no matches
  // ======================================================================
  await page.evaluate((m) => window.__send(m), board('1v1', []));
  await page.waitForTimeout(150);
  const empty = await page.evaluate(() => {
    const n = document.querySelector('#lb-body .empty');
    return n ? n.textContent : null;
  });
  check('an empty ladder says so', empty, 'NOBODY IS ON THIS LADDER YET');
  check('  and does not blame the match history',
        /MATCH/i.test(empty || ''), false);

  check('no script error the whole way through', errors, []);

  await browser.close();
  console.log(fails ? `\n${fails} FAILED of ${checks}` : `\nALL PASS (${checks} checks)`);
  process.exit(fails ? 1 : 0);
})();
