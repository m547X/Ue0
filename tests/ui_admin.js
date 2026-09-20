/* The admin panel.
 *
 *   node tests/ui_admin.js
 *
 * Two things decide whether this screen is any good, and neither shows in a
 * screenshot:
 *
 *   - it must never offer an action the server did not say this admin holds,
 *     because a button that comes back "no permission" teaches people to
 *     ignore the panel, and
 *   - an action that lands on a player must not be able to fire with no
 *     player loaded, or with the reason the server is going to demand left
 *     empty.
 *
 * So the real page is loaded, fed the same dashboard the server sends, and
 * clicked.
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

/* The shape Config.AdminActions arrives in: permission, label, group, and the
   two flags that decide whether the panel asks for a reason or a confirm. */
const A = (permission, label, group, confirm, reason) => ({ permission, label, group, confirm, reason });
const ALL = {
  dashboard:     A('pvp.admin.view', 'View Dashboard', 'monitor'),
  playerLookup:  A('pvp.admin.view', 'Player Lookup', 'monitor'),
  spectate:      A('pvp.admin.spectate', 'Spectate Match', 'monitor'),
  stopSpectate:  A('pvp.admin.spectate', 'Stop Spectating', 'monitor'),
  endMatch:      A('pvp.admin.match.end', 'Force End Match', 'match', true, true),
  restartRound:  A('pvp.admin.match.round', 'Restart Round', 'match'),
  movePlayer:    A('pvp.admin.match.move', 'Move Player Team', 'match'),
  kickFromMatch: A('pvp.admin.match.kick', 'Kick From Match', 'match', false, true),
  closeRoom:     A('pvp.admin.custom.close', 'Close Custom Room', 'match', true),
  freeze:        A('pvp.admin.freeze', 'Freeze Ranked Queue', 'match', true),
  startBotMatch: A('pvp.admin.botmatch', 'Start Bot Match', 'match'),
  stopBotMatch:  A('pvp.admin.botmatch', 'Stop Bot Match', 'match'),
  addRP:         A('pvp.admin.rp.add', 'Compensate RP', 'points', false, true),
  removeRP:      A('pvp.admin.rp.remove', 'Deduct RP', 'points', false, true),
  setRP:         A('pvp.admin.rp.set', 'Set RP', 'points', false, true),
  setRank:       A('pvp.admin.rank.set', 'Set Rank', 'points', false, true),
  addXP:         A('pvp.admin.xp', 'Grant XP', 'points', false, true),
  giveCoins:     A('pvp.admin.coins', 'Give Coins', 'points', false, true),
  takeCoins:     A('pvp.admin.coins', 'Take Coins', 'points', false, true),
  allowCard:     A('pvp.admin.custom.card', 'Allow Custom Card', 'points', false, true),
  resetCard:     A('pvp.admin.custom.card', 'Reset Custom Card', 'points', false, true),
  denyCard:      A('pvp.admin.custom.card', 'Remove Custom Card Access', 'points', true, true),
  allowPortrait: A('pvp.admin.custom.portrait', 'Allow Custom Portrait', 'points', false, true),
  resetPortrait: A('pvp.admin.custom.portrait', 'Reset Custom Portrait', 'points', false, true),
  denyPortrait:  A('pvp.admin.custom.portrait', 'Remove Custom Portrait Access', 'points', true, true),
  resetStats:    A('pvp.admin.stats.reset', 'Reset Season Stats', 'points', true, true),
  ban:           A('pvp.admin.ban', 'Ranked Ban', 'punish', true, true),
  unban:         A('pvp.admin.unban', 'Lift Ranked Ban', 'punish', false, true),
  clearCooldown: A('pvp.admin.cooldown', 'Clear Cooldown', 'punish'),
  newSeason:     A('pvp.admin.season', 'Start New Season', 'system', true, true),
  toggleMode:    A('pvp.admin.mode', 'Enable / Disable Mode', 'system', true),
  auditLog:      A('pvp.admin.audit', 'Audit Log', 'system')
};

const DASH = (allowed) => ({
  allowed: allowed || ALL, level: 'super', frozen: false,
  botMatch: { difficulties: [{ id: 'normal', label: 'NORMAL', isDefault: true }] },
  matches: [
    { id: 'M-1042', mode: '1V1', map: 'Sandy Yard', state: 'LIVE', round: 3, scores: { a: 2, b: 1 }, players: 2 },
    { id: 'M-1043', mode: '2V2', map: 'Warehouse', state: 'ROUND_END', round: 5, scores: { a: 3, b: 2 }, players: 4 }
  ],
  searching: [{ name: 'M547', mode: '1V1', rank: 'Diamond II', mmr: 1840, waited: 42 }],
  rooms: [{ id: 'R-7', name: "M547's room", host: 'M547', players: 6, maxPlayers: 10, state: 'LOBBY', code: '4F2K' }],
  suspicious: [{ user_id: 1042, name: 'Sami', flags: 4, score: 31 }],
  bans: [{ id: 3, user_id: 1042, name: 'Sami', type: 'RANKED', reason: 'boosting', admin: 'M547' }],
  seasons: [{ number: 3, name: 'Season 3', start_at: '2026-07-01', end_at: '2026-10-01', active: true }],
  audit: [{ action: 'addRP', admin_name: 'M547', target_name: 'Khalid', amount: 250,
            reason: 'crash', created_at: '2026-09-19T14:22:00' }]
});

const LOOKUP = {
  userId: 1042, name: 'Sami Alharbi', rank: 'Platinum I', rankColor: '#57C7E8',
  rp: 1780, level: 37, coins: 2450, online: true,
  bans: [{ id: 3 }], cooldown: 0, flags: [1, 2, 3, 4],
  customCard: true, customPortrait: false, stats: {}
};

const BOOT = {
  player: { userId: 1, name: 'M547', rank: 'Diamond II', tier: 'diamond', rankColor: '#57C7E8',
            rp: 2600, level: 42, xp: 120, xpMax: 400, coins: 9400 },
  modes: [{ id: '1v1', label: '1V1' }],
  allModes: [{ id: '1v1', label: '1V1' }, { id: '2v2', label: '2V2' }],
  ranks: [{ id: 1, name: 'Bronze I' }, { id: 23, name: 'Diamond II' }],
  maps: [{ id: 'yard', name: 'Sandy Yard' }],
  rankBanTypes: ['RANKED'], banDurations: [{ seconds: 3600, label: '1 HOUR' }],
  isAdmin: true
};

const last = (p, name) => p.evaluate((n) => {
  const u = window.__posted.filter((x) => x.name === n);
  return u.length ? u[u.length - 1].body : null;
}, name || 'admin');
const clear = (p) => p.evaluate(() => { window.__posted = []; });
const tab = (p, t) => p.evaluate((x) => { S.admTab = x; renderAdmin(S.admin); }, t);

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));

  await page.addInitScript(SHIM);
  await page.goto(UI);
  await page.evaluate((d) => {
    window.__send({ action: 'open', page: 'admin', theme: {}, brand: {}, silent: true });
    window.__send({ action: 'boot', data: d.boot });
    window.__send({ action: 'data', data: { what: 'admin', action: 'dashboard', result: d.dash } });
  }, { boot: BOOT, dash: DASH() });
  await page.waitForTimeout(300);

  // ======================================================================
  // 1. the shape of the server, at a glance
  // ======================================================================
  check('the panel opens on its own page',
        await page.locator('#pg-admin').evaluate((n) => n.classList.contains('active')), true);
  check('  with all five sections',  await page.locator('.adm-tab').count() >= 5, true);

  await tab(page, 'monitor');
  await page.waitForTimeout(150);
  const stats = await page.locator('.adm-stat').evaluateAll(
    (ns) => ns.map((n) => [n.querySelector('span').textContent.trim(),
                           n.querySelector('b').textContent.trim()]));
  check('the numbers strip counts what is running',
        stats.slice(0, 4), [['LIVE MATCHES', '2'], ['PLAYERS IN MATCH', '6'],
                            ['IN QUEUE', '1'], ['CUSTOM ROOMS', '1']]);
  check('  and says whether the queue is frozen',
        stats[stats.length - 1], ['RANKED QUEUE', 'OPEN']);

  await page.evaluate((d) => window.__send({ action: 'data',
    data: { what: 'admin', action: 'dashboard', result: Object.assign(d, { frozen: true }) } }), DASH());
  await page.waitForTimeout(200);
  check('  which changes when it is',
        await page.locator('.adm-stat').last().locator('b').textContent(), 'FROZEN');
  await page.evaluate((d) => window.__send({ action: 'data',
    data: { what: 'admin', action: 'dashboard', result: d } }), DASH());
  await page.waitForTimeout(200);

  // ======================================================================
  // 2. nothing is offered that the server did not allow
  // ======================================================================
  const onlyView = { dashboard: ALL.dashboard, playerLookup: ALL.playerLookup,
                     addRP: ALL.addRP };
  await page.evaluate((d) => window.__send({ action: 'data',
    data: { what: 'admin', action: 'dashboard', result: d } }), DASH(onlyView));
  await page.waitForTimeout(250);
  check('a limited admin sees only the tabs they can use',
        await page.locator('.adm-tab').evaluateAll(
          (ns) => ns.map((n) => n.textContent.trim()).filter((t) => t && t !== 'REFRESH')),
        ['MONITOR', 'POINTS']);
  await tab(page, 'points');
  await page.waitForTimeout(150);
  check('  and only the one action they hold',
        await page.locator('.act .act-head b').evaluateAll(
          (ns) => ns.map((n) => n.textContent.trim())), ['Compensate RP']);
  check('  with no button for the ones they do not',
        await page.locator('[data-adm="removeRP"]').count(), 0);

  await page.evaluate((d) => window.__send({ action: 'data',
    data: { what: 'admin', action: 'dashboard', result: d } }), DASH());
  await page.waitForTimeout(250);

  // ======================================================================
  // 3. an action that needs a player cannot fire without one
  // ======================================================================
  await tab(page, 'points');
  await page.waitForTimeout(150);
  check('nobody is loaded to begin with',
        await page.locator('.adm-who.empty').count(), 1);

  await clear(page);
  await page.fill('#adm-rp-add', '250');
  await page.locator('[data-adm="addRP"]').click();
  await page.waitForTimeout(150);
  check('granting RP with no player sends nothing', await last(page), null);
  check('  and says so',
        (await page.locator('.toast').first().innerText()).includes('Load a player first'), true);

  // ======================================================================
  // 4. nor without the reason the server is going to ask for
  // ======================================================================
  await page.evaluate((r) => window.__send({ action: 'data',
    data: { what: 'admin', action: 'playerLookup', result: r } }), LOOKUP);
  await page.waitForTimeout(250);

  check('loading a player fills the card',
        await page.locator('.adm-who-name b').textContent(), 'Sami Alharbi');
  check('  under the id that was looked up',
        await page.locator('.adm-who-name .pid').textContent(), '#1042');
  check('  with what they hold',
        await page.locator('.adm-who-nums b').evaluateAll(
          (ns) => ns.map((n) => n.textContent.trim())), ['Platinum I', '1,780', '37', '2,450']);
  check('  and what is already on them',
        await page.locator('.adm-who-chips .tchip').evaluateAll(
          (ns) => ns.map((n) => n.textContent.trim())),
        ['ONLINE', 'BANNED · 1', 'FLAGS · 4', 'CARD SLOT']);
  check('  and the id box now holds their id',
        await page.locator('#adm-target').inputValue(), '1042');

  await clear(page);
  await page.fill('#adm-rp-add', '250');
  await page.locator('[data-adm="addRP"]').click();
  await page.waitForTimeout(150);
  check('an action that needs a reason will not go without one', await last(page), null);
  check('  marked on the card before you click it',
        await page.locator('.act', { hasText: 'Compensate RP' })
                  .locator('.act-tag.need').count(), 1);

  await page.fill('#adm-reason', 'lost to a crash');
  await clear(page);
  await page.fill('#adm-rp-add', '250');
  await page.locator('[data-adm="addRP"]').click();
  await page.waitForTimeout(150);
  check('with both it goes', await last(page),
        { action: 'addRP', target: '1042', amount: 250, reason: 'lost to a crash' });

  // the reason must survive the redraw that a lookup causes
  await page.evaluate((r) => window.__send({ action: 'data',
    data: { what: 'admin', action: 'playerLookup', result: r } }), LOOKUP);
  await page.waitForTimeout(200);
  check('  and the reason survives a redraw',
        await page.locator('#adm-reason').inputValue(), 'lost to a crash');

  // ======================================================================
  // 5. the ones that ask twice
  // ======================================================================
  await clear(page);
  await page.locator('[data-adm="resetStats"]').click();
  await page.waitForTimeout(150);
  check('a destructive action asks first', await last(page), null);
  check('  naming who it lands on',
        (await page.locator('#prompt-text').textContent()).includes('Sami Alharbi #1042'), true);
  await page.click('#prompt-ok');
  await page.waitForTimeout(150);
  check('  and only then goes', (await last(page)).action, 'resetStats');

  // ======================================================================
  // 6. finding an action without knowing its tab
  // ======================================================================
  await page.fill('#adm-filter', 'coin');
  await page.waitForTimeout(200);
  check('the filter narrows to what was typed',
        await page.locator('.act .act-head b').evaluateAll(
          (ns) => ns.map((n) => n.textContent.trim())), ['Give Coins', 'Take Coins']);
  check('  and the headings of empty sections go with them',
        await page.locator('.adm-sec').count(), 1);

  await page.fill('#adm-filter', 'zzzz');
  await page.waitForTimeout(200);
  check('a search that matches nothing says so, not nothing',
        await page.locator('.locked-note').count(), 1);
  await page.fill('#adm-filter', '');
  await page.waitForTimeout(200);
  check('  and clearing it brings them all back',
        await page.locator('.act').count() > 10, true);

  // ======================================================================
  // 7. the target can be dropped again
  // ======================================================================
  await page.locator('[data-adm="clearTarget"]').click();
  await page.waitForTimeout(200);
  check('the loaded player can be cleared',
        await page.locator('.adm-who.empty').count(), 1);
  check('  and the id box with them',
        await page.locator('#adm-target').inputValue(), '');

  // ======================================================================
  // 8. the lists on the other tabs still act
  // ======================================================================
  await tab(page, 'monitor');
  await page.waitForTimeout(150);
  await clear(page);
  await page.locator('[data-adm="spectate"]').first().click();
  await page.waitForTimeout(150);
  check('a live match can be watched from the list', await last(page),
        { action: 'spectate', matchId: 'M-1042' });

  await clear(page);
  await page.locator('[data-adm="lookup"]').first().click();
  await page.waitForTimeout(150);
  check('a flagged player can be inspected', await last(page),
        { action: 'playerLookup', target: '1042' });

  await tab(page, 'system');
  await page.waitForTimeout(150);
  check('the two mode buttons have their own pickers',
        await page.locator('#adm-mode, #adm-mode-off').count(), 2);
  await clear(page);
  await page.locator('[data-adm="modeOff"]').click();
  await page.waitForTimeout(150);
  await page.click('#prompt-ok');
  await page.waitForTimeout(150);
  check('  and disabling reads the one next to it', await last(page),
        { action: 'toggleMode', mode: '1v1', value: false });

  check('nothing threw along the way', errors, []);

  await browser.close();
  console.log();
  console.log(fails === 0 ? `ALL PASS (${checks} checks)` : `${fails} FAILED`);
  process.exit(fails === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
