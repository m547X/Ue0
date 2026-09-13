/* Drives the real interface in a real browser: the vote screen with all three
 * questions, the invite card, the custom map list, and the lobby controls.
 *
 *   node tests/ui_vote.js
 *
 * The NUI is a web page, so the things that break in it — a selector that
 * matches nothing, a modal that will not close, a control rendered off screen —
 * only show up when it is actually rendered. Chromium is already on the box.
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

/* Everything the page posts back to Lua is captured instead of sent. */
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
  player: { userId: 1, name: 'ME', level: 3, rp: 400, rankId: 2, tier: 'silver', rankColor: '#aaa' },
  maxParty: 5,
  modes: [{ id: '1v1', label: '1V1', teamSize: 1 }, { id: '5v5', label: '5V5', teamSize: 5 }],
  allModes: [{ id: '1v1', label: '1V1', teamSize: 1 }, { id: '5v5', label: '5V5', teamSize: 5 }],
  maps: [
    { id: 'dust',  name: 'DUST',   modes: ['5v5'] },
    { id: 'lego',  name: 'LEGO',   modes: ['1v1'] },
    { id: 'neon1', name: 'NEON 1', modes: ['5v5'] },
    { id: 'arena1', name: 'ARENA 1', modes: ['5v5'] }
  ],
  weaponPresets: [{ id: 'smg', label: 'SMG' }, { id: 'sniper', label: 'Sniper' }],
  matchTypes: [{ id: 'normal', label: 'Normal' }],
  ranks: [], modePool: {}
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

  check('the interface loads with no script error', errors, []);

  // ======================================================================
  // 1. the vote: three questions on one screen
  // ======================================================================
  await page.evaluate(() => window.__send({ action: 'mapVote', data: {
    matchId: 'm1', duration: 20,
    options: [{ id: 'dust', name: 'DUST' }, { id: 'neon1', name: 'NEON 1' }],
    weapons: [{ id: 'smg', name: 'SMG' }, { id: 'sniper', name: 'Sniper' }],
    rules:   [{ id: 'full', name: 'FULL BODY' }, { id: 'head', name: 'HEADSHOT ONLY' }]
  } }));
  await page.waitForTimeout(120);

  check('the vote screen is up', await page.isVisible('#modal-mapvote'), true);
  check('  two maps are drawn',   await page.locator('.mv-card').count(), 2);
  check('  two weapons',          await page.locator('#mv-weapons .mv-opt').count(), 2);
  check('  two kill rules',       await page.locator('#mv-rules .mv-opt').count(), 2);
  check('  and both extra groups are shown',
        await page.isVisible('#mv-weapons-wrap') && await page.isVisible('#mv-rules-wrap'), true);

  // every option has to be clickable where it is drawn, not under something
  await page.locator('.mv-card').first().click();
  await page.locator('#mv-weapons .mv-opt').nth(1).click();
  await page.locator('#mv-rules .mv-opt').nth(1).click();
  await page.waitForTimeout(80);

  const posted = await page.evaluate(() => window.__posted.filter((p) => p.name === 'mapVote'));
  check('the map vote is sent as its own group',
        posted[0], { name: 'mapVote', body: { kind: 'map', choice: 'dust' } });
  check('  the weapon likewise',
        posted[1], { name: 'mapVote', body: { kind: 'weapon', choice: 'sniper' } });
  check('  and the rule',
        posted[2], { name: 'mapVote', body: { kind: 'rule', choice: 'head' } });

  check('what you picked is marked in each group',
        await page.locator('.mv-card.picked, .mv-opt.picked').count(), 3);

  // tallies land on the right counters
  await page.evaluate(() => window.__send({ action: 'mapVote', data: {
    update: true,
    tallies: { map: { dust: 3 }, weapon: { sniper: 2, smg: 1 }, rule: { head: 4 } }
  } }));
  await page.waitForTimeout(80);
  check('the map tally is painted',
        await page.locator('.mv-votes[data-map="dust"] b').textContent(), '3');
  check('  the weapon tally',
        await page.locator('.n[data-vote="weapon:sniper"]').textContent(), '2');
  check('  and the rule tally',
        await page.locator('.n[data-vote="rule:head"]').textContent(), '4');

  // ======================================================================
  // 2. escape must not strand the vote
  // ======================================================================
  // This is the bug: escape hid the whole menu and left the vote owed, and the
  // only way back was to open ranked again.
  await page.keyboard.press('Escape');
  await page.waitForTimeout(80);
  check('escape does not close the menu during a vote',
        await page.evaluate(() => window.__posted.some((p) => p.name === 'close')), false);
  check('  and the vote is still on screen', await page.isVisible('#modal-mapvote'), true);

  /* The modal covers the close button, so it cannot be reached with a real
     click — which is the first line of defence. This fires the handler anyway,
     the way a stray dispatch would, and it has to be refused as well. */
  check('the close button is unreachable behind the vote',
        await page.locator('[data-action="close"]').evaluate((n) => {
          const r = n.getBoundingClientRect();
          const top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
          return n.contains(top);
        }), false);
  await page.evaluate(() => document.querySelector('[data-action="close"]').click());
  await page.waitForTimeout(80);
  check('  and the handler refuses it even when fired directly',
        await page.evaluate(() => window.__posted.some((p) => p.name === 'close')), false);

  // once it resolves, escape works again
  await page.evaluate(() => window.__send({ action: 'mapVote', data: {
    result: 'dust', weaponName: 'Sniper', rule: 'head', close: true } }));
  await page.waitForTimeout(120);
  check('the vote closes on the result', await page.isVisible('#modal-mapvote'), false);

  await page.keyboard.press('Escape');
  await page.waitForTimeout(80);
  check('  and escape works again afterwards',
        await page.evaluate(() => window.__posted.some((p) => p.name === 'close')), true);

  // ======================================================================
  // 3. a vote with only some of the questions
  // ======================================================================
  await page.evaluate(() => {
    window.__posted = [];
    window.__send({ action: 'open', page: 'ranked', silent: true });
    window.__send({ action: 'mapVote', data: {
      matchId: 'm2', duration: 20,
      options: [{ id: 'dust', name: 'DUST' }, { id: 'neon1', name: 'NEON 1' }]
    } });
  });
  await page.waitForTimeout(120);
  check('a map-only vote hides the weapon row',
        await page.isVisible('#mv-weapons-wrap'), false);
  check('  and the rule row',  await page.isVisible('#mv-rules-wrap'), false);
  check('  while still drawing the maps', await page.locator('.mv-card').count(), 2);

  await page.evaluate(() => window.__send({ action: 'mapVote', data: { close: true } }));
  await page.waitForTimeout(80);

  // ======================================================================
  // 4. the invite: drawn over the game, with the menu shut
  // ======================================================================
  // The whole point of the card is that it does not open the interface. The
  // menu is closed here and has to stay closed, with the card still readable
  // and still clickable.
  await page.evaluate(() => {
    window.__posted = [];
    window.__send({ action: 'close' });
    window.__send({ action: 'prime', theme: {}, brand: {},
      locale: { language: 'ar', strings: { ar: { ACCEPT: 'قبول', DECLINE: 'رفض', S: 'ث',
                                 'TO ANSWER': 'للرد', 'TO ACCEPT': 'للقبول' } },
                rtl: { ar: true } } });
    window.__send({ action: 'promptFocus', on: false });
    window.__send({ action: 'party', promptKey: 'LMENU', data: {
      invite: { kind: 'room', roomName: 'MY ROOM', from: 'FRIEND', timeout: 30 } } });
  });
  await page.waitForTimeout(150);

  check('the interface stays shut for an invite',
        await page.locator('#app').evaluate((n) => n.classList.contains('hidden')), true);
  check('  and the card is on screen anyway', await page.isVisible('.invite-row'), true);
  check('  prime brought the language with it, without opening anything',
        await page.locator('.invite-row .btn').first().innerText(), 'قبول');

  /* No cursor yet: the player is still playing. The card names the key that
     reaches it rather than grabbing the mouse out of a fight. */
  check('the buttons are dimmed until the player asks for a cursor',
        await page.locator('.invite-row').first().evaluate((n) => n.classList.contains('inert')), true);
  let hint = await page.locator('.invite-hint-key').last().innerText();
  check('  and the key to press is named',   /LMENU/.test(hint), true);
  check('  along with the shortcut to accept', /ENTER/.test(hint), true);
  check('  in the player\'s language',        /للرد/.test(hint), true);

  // the client says the cursor is theirs now
  await page.evaluate(() => window.__send({ action: 'promptFocus', on: true }));
  await page.waitForTimeout(100);
  check('once the key is pressed the buttons come alive',
        await page.locator('.invite-row').first().evaluate((n) => n.classList.contains('inert')), false);
  check('  and the hint goes away',
        await page.locator('.invite-hint-key').last().isVisible(), false);
  check('  and the buttons can actually be clicked, not just seen',
        await page.locator('.invite-row .btn').first().evaluate((n) => {
          const r = n.getBoundingClientRect();
          const top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
          return n.contains(top) || n === top;
        }), true);

  // pressing it again puts the cursor away, and the hint comes back
  await page.evaluate(() => window.__send({ action: 'promptFocus', on: false }));
  await page.waitForTimeout(100);
  check('putting the cursor away brings the hint back',
        await page.locator('.invite-hint-key').last().isVisible(), true);
  await page.evaluate(() => window.__send({ action: 'promptFocus', on: true }));
  await page.waitForTimeout(100);

  let text = await page.locator('.toast').last().innerText();
  check('a room invite names the room', /MY ROOM/.test(text), true);
  check('  and is labelled a room invite', /ROOM INVITE/i.test(text), true);
  check('  with something to press', await page.locator('.toast button').count() >= 2, true);

  // the seconds suffix comes out of the string table too, so this is Arabic
  check('  and a clock saying how long you have',
        await page.locator('.invite-clock').last().innerText(), '30ث');

  await page.evaluate(() => window.__send({ action: 'party', data: {
    invite: { kind: 'party', from: 'FRIEND', timeout: 30 } } }));
  await page.waitForTimeout(120);
  text = await page.locator('.toast').last().innerText();
  check('a party invite is labelled a party invite', /PARTY INVITE/i.test(text), true);

  /* The card used to sit for a fixed 12 seconds against a 30 second invite, so
     the invite outlived the only way to accept it. It now lives as long as the
     server says the invite does. */
  const life = await page.locator('.toast').last()
    .locator('.tbar').evaluate((n) => getComputedStyle(n).animationDuration);
  check('  and the card lasts as long as the invite does', life, '30s');

  // accepting, and declining, each send the right thing — and each hands the
  // cursor back, because the card is the only reason the player has one
  await page.evaluate(() => { window.__posted = []; });
  await page.locator('.toast').last().locator('.btn').first().click();
  await page.waitForTimeout(100);
  check('accept sends accept',
        await page.evaluate(() => window.__posted.find((p) => p.name === 'party')),
        { name: 'party', body: { action: 'accept' } });
  check('  and hands the cursor back',
        await page.evaluate(() => window.__posted.some((p) => p.name === 'promptDone')), true);
  check('  and the card goes with it',
        await page.locator('.invite-row').count(), 1);   // the room one is still up

  await page.evaluate(() => { window.__posted = []; });
  await page.locator('.toast').last().locator('.btn').nth(1).click();
  await page.waitForTimeout(100);
  check('decline sends decline',
        await page.evaluate(() => window.__posted.find((p) => p.name === 'party')),
        { name: 'party', body: { action: 'decline' } });
  check('  and hands the cursor back too',
        await page.evaluate(() => window.__posted.some((p) => p.name === 'promptDone')), true);

  // an invite nobody answers must not leave the cursor behind either
  await page.evaluate(() => {
    window.__posted = [];
    window.__send({ action: 'party', data: {
      invite: { kind: 'party', from: 'FRIEND', timeout: 5 } } });
  });
  await page.waitForTimeout(200);
  check('an unanswered invite still holds the cursor',
        await page.evaluate(() => window.__posted.some((p) => p.name === 'promptDone')), false);
  await page.waitForTimeout(5200);
  check('  and gives it back when it runs out',
        await page.evaluate(() => window.__posted.some((p) => p.name === 'promptDone')), true);
  check('  without answering it either way',
        await page.evaluate(() => window.__posted.some((p) => p.name === 'party')), false);
  check('  and the card is gone', await page.locator('.invite-row').count(), 0);

  // enter accepts the one on screen, so an invite that just opened the menu
  // can be taken without reaching for the mouse
  await page.evaluate(() => {
    window.__posted = [];
    window.__send({ action: 'party', data: {
      invite: { kind: 'party', from: 'FRIEND', timeout: 30 } } });
  });
  await page.waitForTimeout(120);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(100);
  check('enter accepts the invite on screen',
        await page.evaluate(() => window.__posted.find((p) => p.name === 'party')),
        { name: 'party', body: { action: 'accept' } });
  check('  and answering it twice is not possible',
        await page.evaluate(() => {
          window.__posted = [];
          document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
          return window.__posted.length;
        }), 0);

  // ======================================================================
  // 5. the lobby: leaving, and a kick you can see
  // ======================================================================
  // back to English, and the interface open, because the party slots live in it
  await page.evaluate(() => window.__send({ action: 'open', page: 'ranked', silent: true,
    locale: { language: 'en', strings: {}, rtl: {} } }));
  await page.waitForTimeout(120);
  await page.evaluate(() => window.__send({ action: 'party', data: {
    id: 'p1', leader: 1,
    members: [{ userId: 1, name: 'ME', leader: true, rankId: 2 },
              { userId: 2, name: 'FRIEND', rankId: 2 }] } }));
  await page.waitForTimeout(150);

  const kick = page.locator('.slot-kick').first();
  check('the leader sees a kick control', await kick.count(), 1);
  const kv = await kick.evaluate((n) => getComputedStyle(n).opacity);
  check('  and it is visible without hovering', kv, '1');
  check('  and it says what it does', (await kick.innerText()).trim().length > 0, true);

  // the member's own seat carries a way out
  await page.evaluate(() => window.__send({ action: 'party', data: {
    id: 'p1', leader: 2,
    members: [{ userId: 2, name: 'FRIEND', leader: true, rankId: 2 },
              { userId: 1, name: 'ME', rankId: 2 }] } }));
  await page.waitForTimeout(150);
  check('a member who does not lead sees a leave control',
        await page.locator('.slot-leave').count(), 1);
  check('  and no kick control',  await page.locator('.slot-kick').count(), 0);

  await page.evaluate(() => { window.__posted = []; });
  await page.locator('.slot-leave').first().click();
  await page.waitForTimeout(100);
  check('  pressing it leaves the party',
        await page.evaluate(() => window.__posted.find((p) => p.name === 'party')),
        { name: 'party', body: { action: 'leave' } });

  // ======================================================================
  // 6. custom games offer every map
  // ======================================================================
  await page.evaluate(() => window.__send({ action: 'open', page: 'custom', silent: true }));
  await page.waitForTimeout(200);
  check('every map is offered in a custom room, not just the mode\'s',
        await page.locator('#cm-maps .mapcard').count(), 4);
  check('  the ones that do not fit the mode are marked',
        await page.locator('#cm-maps .mapcard.offmode').count() > 0, true);
  check('  and the ones that do come first',
        await page.locator('#cm-maps .mapcard').first().evaluate((n) => n.classList.contains('offmode')),
        false);
  check('  a marked one is still selectable',
        await page.locator('#cm-maps .mapcard.offmode').first().isEnabled(), true);

  // the auto start switch is there and off
  check('the auto start switch exists', await page.locator('#cm-autostart').count(), 1);
  check('  and starts off', await page.locator('#cm-autostart').isChecked(), false);

  // ======================================================================
  // 7. the chat button sends the code
  // ======================================================================
  await page.evaluate(() => {
    window.__posted = [];
    window.__send({ action: 'custom', data: { room: {
      id: 'r1', code: 'B3C7', name: 'MY ROOM', hostId: 1, state: 'LOBBY',
      roster: [{ userId: 1, name: 'ME', team: 1, host: true }]
    } } });
  });
  await page.waitForTimeout(150);
  await page.click('[data-action="cm-chat"]');
  await page.waitForTimeout(100);
  check('the chat button sends the code to the game',
        await page.evaluate(() => window.__posted.find((p) => p.name === 'roomCode')),
        { name: 'roomCode', body: { code: 'B3C7' } });

  // and the host can leave their own room
  await page.evaluate(() => { window.__posted = []; });
  check('the host sees a leave control on their own seat',
        await page.locator('#cm-roomview [data-room="leave"]').count(), 1);

  // ======================================================================
  // 8. nothing threw along the way
  // ======================================================================
  check('no script error the whole way through', errors, []);

  // and it survives a phone-width viewport
  await page.setViewportSize({ width: 400, height: 760 });
  await page.evaluate(() => window.__send({ action: 'mapVote', data: {
    matchId: 'm3', duration: 20,
    options: [{ id: 'dust', name: 'DUST' }, { id: 'neon1', name: 'NEON 1' }],
    weapons: [{ id: 'smg', name: 'SMG' }],
    rules: [{ id: 'full', name: 'FULL BODY' }, { id: 'head', name: 'HEADSHOT ONLY' }]
  } }));
  await page.waitForTimeout(150);
  const overflow = await page.evaluate(() =>
    document.documentElement.scrollWidth - document.documentElement.clientWidth);
  check('the vote screen does not run off a narrow screen', overflow <= 1, true);

  await browser.close();
  console.log();
  console.log(fails === 0 ? `ALL PASS (${checks} checks)` : `${fails} FAILED`);
  process.exit(fails === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
