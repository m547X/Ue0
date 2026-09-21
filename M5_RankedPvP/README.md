# M5 Ranked PvP

A complete competitive PvP system for FiveM — ranked ladder, hidden MMR, seasons,
custom games, matchmaking, penalties, anti-boosting, spectator, and a premium NUI.

**Stack:** FiveM · Lua · vRP (Dunko) · oxmysql · NUI (HTML/CSS/JS)

---

## 1. File structure

Four system files you never need to edit, plus two that are yours:

```
M5_RankedPvP/
│
├── fxmanifest.lua
│
├── الاعدادات/              ← every file you edit lives in here
│   ├── Locale.lua         ← YOURS: every line of text the players see
│   ├── Export.lua         ← YOURS: your hooks, events and exports
│   ├── Config_Client.lua  ← client settings only (safe to be public)
│   └── Config_Server.lua  ← server settings only (never sent to a client)
│
├── Files/
│   ├── Client.lua
│   ├── Server.lua
│   └── ui/
│       ├── index.html
│       ├── style.css
│       ├── app.js
│       ├── board.html     ← the world leaderboard board (see 7f)
│       ├── board.css
│       └── board.js
│
├── m5_rankedpvp.sql
└── README.md
```

`Config_Server.lua` is listed only under `server_scripts`, so webhooks, RP
formulas, permission strings and anti-cheat thresholds never reach a player.

---

## 2. Installation

1. Copy the `M5_RankedPvP` folder into your `resources` directory.
2. Import `m5_rankedpvp.sql` — or skip it, the resource creates every table it
   needs on first start.
3. Add to `server.cfg`, **after** vRP and oxmysql:

```cfg
ensure vrp
ensure oxmysql
ensure M5_RankedPvP
```

4. Set the interaction point in `Config_Client.lua`:

```lua
Config.OpenMenu.location.coords = vector3(-1035.42, -2733.18, 13.75)
```

5. Fill in your Discord webhooks in `Config_Server.lua` → `Config.Webhooks.urls`.
6. Set map spawn points in `Config_Server.lua` → `Config.Maps` for your own arenas.

---

## 3. Architecture

### Server authority

The client is a renderer and a reporter. It never decides an outcome.

| Decided on the server | Reported by the client |
|---|---|
| RP, MMR, rank, placement | shots fired (throttled, with a trace) |
| kills, deaths, assists, MVP | damage taken (own health delta) |
| headshot lethality | head-bone hit on itself |
| round and match results | out-of-bounds timer expiry |
| rewards, missions, achievements | activity signals for AFK |

Every inbound event passes a rate limiter (`Config.Security.rateLimits`) and a
validation pass: same live match, opposing sides, whitelisted weapon, victim
alive, spawn protection expired, duplicate window, minimum kill interval.

### Threads

The whole server runs on **one** loop (`Config.Match.tickInterval`, 250 ms) with
accumulators for matchmaking (2 s), custom rooms (15 s), database flush (30 s),
webhooks (4 s) and the season check (60 s).

The client runs:

* one always-on proximity thread with an adaptive wait — 3000 ms far away,
  1000 ms mid range, 250 ms near, and per-frame **only** while the marker is
  actually on screen;
* one match thread that exists only while in a match, and runs per frame only
  during a live round while alive (that is where bullet detection must happen);
  it drops to 200 ms in every other state;
* one spectator thread that exists only while spectating.

Nothing runs for players who are not using the PvP system.

### What one frame of a live round costs

The match thread is the only thing running per frame, and `tests/bench_hotpath.lua`
runs the real functions out of `Client.lua` against counted stubs, so these are
measured numbers rather than an estimate. Standing in a 4v4 with three
teammates in front of you: **43 native calls and 3 allocations a frame**, and
all three allocations are vectors the engine itself hands back. Look away from
your team and it is 13. Alone on the server it rounds to **a quarter of a
native call a frame**.

The rules that keep it there, each one guarded by a check in that file:

* **Nothing is asked for twice.** Whether you are shooting is read once a frame
  and handed to everything that wants to know; your health is read once and
  passed to the death check rather than read again.
* **The teammate list is not rebuilt every frame.** `GetActivePlayers` returns a
  fresh table, so calling it sixty times a second is sixty tables a second. It
  is walked twice a second and the result kept.
* **A nameplate that would not land on screen is not drawn** — that is ten
  native calls each, so looking away from your team genuinely costs less.
* **Distances are compared squared.** `#(a - b)` builds a vector and takes a
  square root to answer a question that `dx*dx + dy*dy + dz*dz` answers without
  either. Nothing that only compares a distance takes a square root any more.
* **Whether you are still there is sampled four times a second**, not sixty.
  The answer is only ever sent to the server every three seconds, so asking the
  camera and the movement keys on every frame in between was asking a question
  nobody was listening for. A player who has moved is active on their position
  alone and never reaches that check at all.

On the server, the scoreboard goes out about once a second for as long as a
match runs. It used to build a fresh table per player per push — three hundred
pushes in a five-minute 5v5, ten tables each. The rows are now reused and only
their fields rewritten, and the team names, which cannot change once a match is
running, are worked out once instead of twice a second. `tests/hud_payload.lua`
holds both sides of that: no new tables, and the numbers on them still right
after a kill, a death and a player leaving.

### vRP integration (Dunko)

Calls go straight through vRP's own Proxy and Tunnel — there is no abstraction
layer. Two details of this framework matter and are easy to get wrong:

* **Proxy passes arguments in a table.** `Proxy.lua` calls
  `f(table.unpack(args))`, so every call is `vRP.getUserId({ source })`,
  `vRP.hasPermission({ user_id, perm })`, `vRP.giveMoney({ user_id, amount })`
  and so on — never plain arguments.
* **`Tunnel.getInterface(name, identifier)` needs a second argument**: the name
  of the calling resource. Without it vRP registers `vRP:nil:tunnel_res` and
  throws `attempt to concatenate a nil value (local 'identifier')`.

Display names come from `GetPlayerName` and nothing else — synchronous, always
available, and no database round trip on login. `vRP.getUserIdentity` is
callback based in this framework and cannot return through the synchronous
Proxy, so it is not used anywhere in the resource.

### Database

Reads are cached (`leaderboardCacheTime`, `profileCacheTime`), writes are
batched — player rows are marked dirty and flushed on an interval instead of
per event. Every table carries the indexes its queries need.

**`TINYINT(1)` comes back as a boolean.** oxmysql sits on node-mysql2, which
maps `TINYINT(1)` to a JavaScript boolean, so such a column arrives in Lua as
`true`/`false` rather than `1`/`0`. `tonumber(true)` is `nil`, so the natural
`tonumber(row.flag) == 1` reads a *set* flag as false. That is why a player
could hold `rank_id = 23, rp = 2600, placement_done = 1` in the database and
still load as **Unranked**: the rank was stored perfectly, but
`placement_done` failed the round trip and the boot payload falls back to
Unranked whenever placement is unfinished. Every such column is now read
through `toBool()`, which accepts booleans, numbers and strings.

Five points keep per-season data from being lost:

- **The per-season tables are written as upserts.** `m5_player_ranks`,
  `m5_player_mmr` and `m5_player_stats` are keyed on `(user_id, season_id)`. A
  plain `UPDATE` reports success while changing nothing when that row does not
  exist, so an admin-granted rank could vanish on the next join. `INSERT … ON
  DUPLICATE KEY UPDATE` makes the write land whether the row exists or not.
- **No profile loads before the season is known.** `vRP:playerSpawn` waits for
  the boot sequence (`DB.init()` then `Season.load()`). Loading earlier would
  stamp the player's rows with season `0`, and every later save — which targets
  the real season — would quietly update nothing.
- **Re-loading a cached profile flushes it first.** A resource restart re-reads
  everyone who is already connected; the in-memory row is saved before it is
  replaced, so nothing pending is dropped.
- **A failed write keeps its dirty flag.** `DB.update` returns `0` both when a
  query errors and when nothing needed changing, so it cannot be used to decide
  that a save succeeded. `DB.write` reports the two apart; on an error the flag
  stays set and the next flush retries instead of dropping the change.
- **A player is never uncached with unsaved data.** `Player.save(pd, true)`
  keeps the entry in memory if any flag is still dirty.

If there is no active season at all, ranked writes are held and retried on the
next flush rather than being buried under a phantom season `0`.

### Checking a grant that "did not stick"

**Every staff grant verifies itself.** Right after saving, the rank row is read
back and compared with memory. If they differ — or the row is missing, or there
is no active season — the admin gets a red `NOT SAVED — …` toast immediately and
the console logs `VERIFY FAILED` with both values. A grant that reports nothing
is on disk; there is no longer a case where it looks applied but silently is not.

Grants are also always logged (`[M5RP] rank set: user … -> … season …`), and a
restart prints a matching pair of markers:

```
[M5RP] resource stopping — saving N profiles
[M5RP] resource stopped — N profiles saved
```

If the second line never appears, the shutdown save was cut off by the runtime
teardown. That is survivable by design — staff actions and match results are
written the moment they happen, not deferred to shutdown — but it is worth
knowing.

For the full picture, run this in the **server console**:

```
m5rankinfo <userId>
```

It prints the active season, the in-memory values with their dirty flags, the
row actually stored for that season, and a warning if a stale `season_id = 0`
row exists for that player — the fingerprint of a profile written before the
season had loaded. Such a row is never read back: re-grant the rank and delete
it.

```sql
SELECT * FROM m5_player_ranks WHERE season_id = 0;   -- damage from older builds
```

### Trade kills — when both players die

Nothing in a shooter arrives at the same instant. Two players fire, both
bullets land, and the two death reports reach the server milliseconds apart —
and that gap is their ping, not their aim.

The round used to end on the first of those reports. The second death then
arrived into a round whose state was no longer `LIVE`, so `registerKill`
dropped it: no death on that player's record, no kill for whoever fired it,
nothing in the kill feed, and **the round to whoever had the better
connection**.

`Config.Match.tradeWindow` (300 ms) fixes that. When the last player on a side
goes down the round is *held open* for that long, so a bullet already in flight
still lands:

* both sides end up at zero alive → the round is a **draw**, reason `TRADE`,
  neither side scores, and the round is replayed — the same rule the round
  timer already used for an even board;
* nobody trades → the window runs out and the round goes to the side still
  standing, exactly as before;
* either way the second death is a real death, with the kill, the K/D and the
  kill-feed line that go with it.

Set it to `0` for the old behaviour. It delays the round-end banner by roughly
its own length, which is the price of the fight deciding the round instead of
the ping. The window is resolved by a timer and re-checked on the match tick,
so a busy tick cannot leave a round hanging.

A drawn round adds nothing to either score, so `rounds` counts *decided*
rounds — a best-of-5 with one trade is played over six. `maxMatchDuration`
remains the backstop.

---

## 4. Headshot — one shot kill, no distance falloff

This is the core combat rule and it is enforced entirely on the server.

**How it works**

1. The victim's own client receives `CEventNetworkEntityDamage`, reads
   `GetPedLastDamageBone`, and reports a head hit. The victim's machine is the
   only place where the health delta and the bone are exact.
2. In parallel, the attacker's client traces the shot it just fired and reports
   which player was under the crosshair and whether the impact landed within
   24 cm of the head bone. This is **corroboration only** — it is never enough
   on its own.
3. The server validates the pair, then decides the kill itself and instructs the
   victim's client to die.

Because the server decides, the damage number the engine actually applied is
irrelevant. A valid head hit is lethal at 10 m, at 100 m and at 500 m alike —
`Config.Headshot.ignoreDistance` is respected literally; distance is recorded for
statistics and flagged for review past `Config.Weapons.maxPlausibleDistance`, but
it never reduces lethality.

**What is rejected**

self-kills · fabricated kill events · duplicated kills · kills outside a live
round · non-whitelisted or excluded weapons · melee (when `excludeMelee`) ·
explosion, fall, vehicle, fire and drowning damage · friendly fire when it is
disabled · hits on a spawn-protected victim · a head report with no matching
shot inside `Config.Headshot.shotWindow` · a weapon that does not match the
attacker's last shot.

> **Engine limit, stated plainly:** GTA stops registering bullet impacts past a
> weapon's own range defined in `weapons.meta`. Within every distance where the
> bullet still registers, this system guarantees the one-shot rule. To fight at
> ranges beyond a weapon's engine range you need a `weapons.meta` range edit —
> no script can change that from Lua.

---

## 5. Opening the menu

Three entry points, all opening the same NUI:

| Method | Configured in |
|---|---|
| World marker + `[E]` | `Config_Client.lua` → `Config.OpenMenu.location` |
| `/pvp` command | `Config_Client.lua` → `Config.OpenMenu.command` |
| `F6` keybind | `Config_Client.lua` → `Config.OpenMenu.keybind` |
| vRP main menu entry | `Config_Server.lua` → `Config.vRP.registerMenu` |

The vRP entry is registered with `vRP.registerMenuBuilder` and triggers the same
`m5rp:cl:openMenu` event as the other three.

---

## 6. Ranks and RP

`Unranked → Iron → Bronze → Silver → Gold → Platinum → Diamond → Ascendant →
Immortal → Radiant`, each tier with three divisions (Immortal and Radiant are
single). The whole ladder is data — edit `Config.Ranks` to reshape it.

RP is **not** win/loss only. `RP.calculate` weighs:

* base win/loss value
* round difference (dominance)
* opponent MMR gap and average rank gap
* K/D, kills, damage, headshots relative to the lobby average
* clutches and objective play
* your share of the team's score
* MVP, headshot bonus (capped), win streak
* whether the match was balanced at all
* lose-streak protection and demotion protection

The result is clamped between `minimumGain/maximumGain` and
`minimumLoss/maximumLoss`, so bonuses can never flip the sign of a result.

MMR is a separate hidden Elo with a confidence term, used only for matchmaking
and visible to staff (`Config.MMR.visibleTo`).

### One ladder per mode

`Config.RankPools.perMode` is on by default, so 1v1, 2v2 and 5v5 are **separate
ladders**. Radiant at 1v1 says nothing about 2v2: until you play it you are
Unranked there, with no row on that ladder at all. `shared` puts several modes
on one ladder (`['tdm'] = 'objective'`), and `perMode = false` puts everything
on `default`.

The menu's **Leaderboard** tabs are those ladders: each tab lists everyone
holding RP in that mode, highest first, and the card on the left shows **your**
rank on the ladder you are looking at — not the one you are best at. A tab with
nothing under it means that ladder is genuinely empty, which on a new server it
is; the demo SQL in [7f](#ten-made-up-players-to-see-the-board-at-all--m5_rankedpvp_board_demosql)
fills it. Placement is not a gate on being listed: a player mid-placement shows
with their real RP and an Unranked badge, because hiding everyone until they
finish makes a new server's leaderboard look broken rather than empty.

---

## 7. Commands

| Command | Permission | Purpose |
|---|---|---|
| `/pvp` | — | open the hub |
| `/rank` | — | show your rank and RP |
| `/leaderboard` | — | open the leaderboard |
| `/customgame` | — | open custom games |
| `/reconnectpvp` | — | rejoin a match you dropped from |
| `/pvpadmint` | `pvp.admin` | open the admin panel |
| `/rankban <id> <minutes> <reason>` | `pvp.bans` | issue a ranked ban |
| `/rankunban <id>` | `pvp.bans` | lift ranked bans |
| `/setrank <id> <rankId>` | `pvp.admin` | force a rank (0–23) |
| `/setrp <id> <rp>` | `pvp.rp.modify` | set RP |
| `/pvpstatus` | `pvp.moderator` | live system status |

Plus `/givepvprp <id> <amount> <reason>` — a positive amount compensates, a
negative one deducts. Each command can be renamed or disabled in
`Config.Commands`.

From the **server console** (not chat, and no permission involved because the
console is already the server): `m5boardrefresh` rebuilds the world
leaderboard's standings straight away, pushes them to every player and prints
the top ten — see [7f](#nobody-on-it-yet--m5_rankedpvp_board_seedsql).

---

## 7a. Party size and the ranked queue

`Config.PartyQueue` in `Config_Server.lua`:

```lua
Config.PartyQueue = {
    autoMode        = true,   -- party size picks the mode: 1 = 1V1, 2 = 2V2 …
    lockToPartySize = true,   -- a party of 2 may ONLY search 2V2
    teamMatching = {
        mode          = 'fullTeam',  -- 'fullTeam' | 'any'
        fallbackAfter = 60           -- seconds before falling back to 'any'
    }
}
```

**autoMode** — invite a friend while sitting on 1V1 and the queue switches to
2V2 by itself; a third makes it 3V3. The party payload carries the mode its
size implies and the panel follows it.

Because of that, the seat directly after your party is **always** invitable, no
matter which mode is selected — the mode follows the party, not the other way
round, so gating that seat on the current mode's team size would make 1V1 a dead
end with no way to invite anyone. It shows the mode it will turn into
(`BECOMES 2V2`). Seats further out stay dim and read `INVITE IN ORDER`; they
open as the ones before them fill, up to `Config.Party.maxSize`.

**lockToPartySize** — with it on, modes that do not match the party size are
struck through and refuse to be selected, and the server rejects them too. With
it off, a party may search any mode large enough to hold it and matchmaking
fills the empty slots. A party can never search a mode smaller than itself
either way.

**teamMatching** — decides how the *opposing* side is assembled.

* `'fullTeam'` — a complete party only ever faces another complete party. A duo
  searching 2V2 waits for a second duo searching 2V2 rather than being handed
  two solo players, so a premade never gets a coordination advantage over
  strangers. Solos and partial parties keep matching among themselves as usual,
  and a waiting full team is reserved — the mixed pool cannot consume it.
* `'any'` — the enemy team is built from whatever is waiting: another party,
  two solos, a duo plus a solo.

`fallbackAfter` is the escape hatch: if no mirror team appears within that many
seconds the party is matched the normal way instead of waiting forever. Set it
to 0 to wait indefinitely for a real team.

Changing the party size while a search is running cancels it, since the searched
mode depends on that size.

---

## 7b. Admin panel and permissions

Open it with `/pvpadmint` or the ADMIN tab. The panel has five sections —
Monitor, Matches, Points, Punish, System — and **renders only the controls the
caller is allowed to use**; everything else is absent, not greyed out.

### Working in it

The panel is five tabs and about thirty actions, so:

* **MONITOR** opens on a strip of numbers — live matches, players in them, the
  queue, rooms, flags, and whether ranked is frozen — then the lists those
  numbers came from, each row with the buttons that act on it.
* **The target bar** is sticky at the top of every player tab. Type an id and
  press Enter; the card fills in with their name, rank, RP, level and coins,
  and chips for what is already on them — online, banned, on a cooldown,
  flagged, and whether they hold a custom card or portrait slot. INSPECT on any
  list row loads them the same way.
* **Actions are cards**, grouped under headings, so a tab is a few short lists
  instead of one long one. A card wears a **REASON** chip when the server will
  demand one and a **CONFIRMS** chip when it will ask twice; hovering it shows
  the permission it needs.
* **FIND AN ACTION** searches every tab by name, so you do not have to remember
  which one *Give Coins* lives on.

An action that lands on a player refuses to fire with no player loaded or with
the reason left empty, and says which is missing — rather than sending it and
showing you the server's rejection. A confirm names who it lands on.

### Two layers of permission

```lua
Config.Permissions.superAdmin     = 'pvp.all'   -- a master key
Config.Permissions.adminGrantsAll = true        -- 'pvp.admin' is one too
```

`pvp.all` is a master key, not one more entry in the list: it passes **every**
permission this resource checks, including ones added in a later version. That
covers the admin panel, the board editor (`/pvpboard`), opening the menu,
creating custom rooms, spectating and the hidden MMR. It does not pretend the
holder literally has the `admin` or `moderator` role, which is what the panel
reads to decide how much of itself to show.

Set `adminGrantsAll = false` for strict per-action control even for admins;
`pvp.all` is unaffected by it.

### One permission per action

Every entry in `Config.AdminActions` declares its own permission, label, and
whether it needs a reason or a confirmation:

| Action | Permission | What it does |
|---|---|---|
| `dashboard`, `playerLookup` | `pvp.admin.view` | read the panel, inspect a player |
| `spectate` / `stopSpectate` | `pvp.admin.spectate` | watch any live match |
| `endMatch` | `pvp.admin.match.end` | force a match to finish |
| `restartRound` | `pvp.admin.match.round` | replay the current round |
| `movePlayer` | `pvp.admin.match.move` | switch a player's team |
| `kickFromMatch` | `pvp.admin.match.kick` | remove a player from a match |
| `closeRoom` | `pvp.admin.custom.close` | stop a custom game |
| `freeze` | `pvp.admin.freeze` | freeze / unfreeze the ranked queue |
| `addRP` | `pvp.admin.rp.add` | **compensate** a player with points |
| `removeRP` | `pvp.admin.rp.remove` | **deduct** points |
| `setRP` | `pvp.admin.rp.set` | overwrite the RP total |
| `setRank` | `pvp.admin.rank.set` | force a rank |
| `addXP` | `pvp.admin.xp` | grant progression XP |
| `resetStats` | `pvp.admin.stats.reset` | wipe this season for one player |
| `ban` / `unban` | `pvp.admin.ban` / `.unban` | ranked bans |
| `clearCooldown` | `pvp.admin.cooldown` | lift an abandon cooldown |
| `reviewFlag` | `pvp.admin.antiboost` | mark an anti-boost flag reviewed |
| `newSeason` | `pvp.admin.season` | archive and roll the season |
| `toggleMode` | `pvp.admin.mode` | enable or disable a mode |
| `auditLog` | `pvp.admin.audit` | read the audit log |

Gameplay permissions stay separate: `pvp.menu`, `pvp.custom.create`,
`pvp.spectate`, `pvp.mmr`, plus the staff tiers `pvp.moderator` and `pvp.admin`.

### Guardrails

Point changes are capped by `Config.AdminLimits` (`maxRPGrant`, `maxRPDeduct`,
`maxXPGrant`) so a typo cannot wreck a ladder, and actions marked `reason = true`
are refused without one.

**Targets are user IDs only.** The TARGET PLAYER box accepts digits and nothing
else — the UI strips anything else as you type and the server refuses a
non-numeric target. Name matching was removed on purpose: two accounts can carry
the same display name, and a partial match could silently point a ban or an RP
wipe at the wrong player. Use the LOAD button to confirm the ID resolves to the
account you expect before acting on it.

### Audit log

Every staff action writes a row to `m5_admin_logs` — who did it, to whom, the
amount, the before and after values, and the reason — and mirrors it to the
`adminActions` webhook. A player's recent actions show inside their lookup, and
the last 30 server-wide appear in the System tab. Rows older than
`Config.AdminLimits.auditRetentionDays` are pruned automatically.

---

## 7c. Bot match — practising alone

**Admin panel → MATCHES → Start Bot Match.** Pick a difficulty, one to five
bots, the number of rounds and a map, and you are dropped into a private world
against AI. It runs the real match presentation — map spawns, countdown,
rounds, HUD, kill feed, score, end screen — so a map or a weapon set can be
checked without a second player. **STOP** ends it, and so does the normal leave
button; disconnecting or restarting the resource cleans it up too.

Permission: `pvp.admin.botmatch`, on both `startBotMatch` and `stopBotMatch`
in `Config.AdminActions`. Holders of `pvp.all` pass as usual.

### It is always unranked, and that is deliberate

Only a client can create a ped and give it combat AI, so the bots live on the
screen of whoever started the session. That means a bot's death is *reported*
by that client, not proven by the server — the one thing this resource never
accepts for anything that counts. So nothing counts here:

| | Bot match |
|---|---|
| RP / MMR | none |
| Season stats | untouched |
| Match history | no row written |
| Leaderboard | unaffected |

The server still owns everything it can: the session, the rounds, the score,
every timer and transition, when a round starts and ends, and the player's own
death (which arrives through the normal combat path). The client is trusted for
exactly one message — "a bot went down" — and that message is worthless.

This is also why it is staff-only rather than a feature for everyone. Making it
public would need server-owned bots, which FiveM cannot provide.

### Tuning

`Config.BotMatch` in `Config_Server.lua`: `rounds`, `roundTime`, `countdown`,
`roundEndDelay`, `endDelay`, the player `loadout`, `maxBots`, and the
`bots.difficulties` presets — health, armour, weapon, `accuracy` (0-100),
`reaction`, `combatMovement` (0 stationary → 3 suicidal) and `alertness`. Add
or rename presets freely; the panel lists whatever is there, ordered by
accuracy. Rounds needed to win are derived from the round count (best of N), so
no second setting can disagree with the one you picked.

Each session takes its own routing bucket from `Config.BotMatch.bucket`
upwards (64 are reserved), so two admins practising at the same time never land
in each other's world.

---

## 7c-bis. Locale.lua — every line of text

`Locale.lua` holds every word the script shows a player: notifications, errors,
the whole menu, the match HUD and the scoreboard. Nothing user-facing is
written anywhere else, so it is the only file to touch to change wording or add
a language.

**The English line is the key.** There is no separate id to keep in sync:

```lua
Locale.ar['Party is full.'] = 'المجموعة ممتلئة.'
```

Anything without a translation falls through to the English key unchanged, so a
missing line is never a blank screen and a language can be filled in a few
lines at a time.

```lua
Locale.default  = 'ar'                -- language before a player picks one
Locale.fallback = 'en'
Locale.available = { { id = 'en', label = 'English' }, { id = 'ar', label = 'العربية' } }
Locale.rtl = { ar = true }            -- these mirror the interface
Locale.notifications = 'ar'           -- notifications only; nil = follow the player
```

`Locale.notifications` pins the corner notifications to one language whatever
the player set the menu to — an Arabic speaking server can keep the menu
available in English and still have every notification read Arabic. Each toast
carries its own direction, so a pinned Arabic notification reads right to left
on an otherwise left to right screen. Set it to `nil` to have notifications
follow the player's choice like everything else.

`%s` and `%d` are filled in by the script — keep them, in the same order as the
English line. The pattern is always translated **before** the values go in, so
`'You reached level %d'` becomes `'وصلت إلى المستوى %d'` and then `12` lands in
the right place.

### Adding a language

1. Copy the `ar` block and rename it, e.g. `Locale.fr = { ... }`.
2. Add `{ id = 'fr', label = 'Français' }` to `Locale.available`.
3. That is all — it appears in **Settings → Language** by itself, and the
   interface, the notifications and the server messages all follow it.

### How one file reaches all three sides

`Locale.lua` is a `shared_script`, so the client and the server both hold it.
The client also hands every table to the interface with each menu open, which
is why switching language is instant instead of waiting on a round trip.

Server notifications are the part worth understanding: the server does not know
which language a player chose, so it sends the **English key plus the values**,
and the player's own client does the swap. That is why a translated
notification is correct even when two players on the same server read different
languages.

---

## 7d. Export.lua — your code, your hooks

`Export.lua` is the one file meant to be edited. Give a hook a body and it runs
at that moment; nothing else needs touching.

```lua
M5.Server.onMatchJoin = function(data)
    vRP.tryPayment({ data.userId, 500 })          -- entry fee
end

M5.Client.onMatchJoin = function(data)
    exports['my_hud']:setVisible(false)           -- hide your own HUD
end

M5.Client.onMatchLeave = function(data)
    exports['my_hud']:setVisible(true)
end
```

It is a `shared_script`, so the same file loads on both sides: `M5.Client`
hooks only ever run on the client, `M5.Server` hooks only on the server. Every
hook is wrapped in `pcall` — a mistake in your code prints an error and the
match carries on. It can never take the PvP system down.

| Client | Server |
|---|---|
| `onMatchJoin` `onMatchLeave` | `onMatchJoin` `onMatchLeave` |
| `onRoundStart` `onRoundEnd` | `onMatchEnd` `onKill` |
| `onDeath` `onMatchEnd` | `onQueueJoin` `onQueueLeave` |
| `onTrainingStart` `onTrainingEnd` | `onRankChange` |

Each hook receives one table; the fields are documented above every hook in the
file itself.

**From another resource**, without editing anything, the same moments fire as
events (`m5rp:onMatchJoin`, `m5rp:onKill`, …) on the side they belong to, and
these exports are available:

```lua
-- server
exports.M5_RankedPvP:isInMatch(userId)
exports.M5_RankedPvP:getMatchInfo(userId)
exports.M5_RankedPvP:getPlayerRank(userId)    -- rank, rp, mmr, level
exports.M5_RankedPvP:getPlayerStats(userId)
-- client
exports.M5_RankedPvP:isInMatch()
exports.M5_RankedPvP:isTraining()
exports.M5_RankedPvP:getMatchInfo()
```

---

## 7e. Match HUD, avatars and the scoreboard

### Avatars — `Config.Avatars`

Every player in the HUD, the scoreboard and the lobby seats shows a picture.
Where it comes from is `Config.Avatars.source`:

- **`'discord'`** — the real avatar of the player's linked Discord account.
  Put a bot token in `Config.Avatars.discord.botToken`; the bot needs no
  permissions and does not have to be in your server, reading a public avatar
  only needs the token. Results are cached for `cacheTime` seconds because
  Discord rate limits hard. **Leave the token empty and nobody ever gets their
  real picture** — everyone keeps the Discord placeholder. It does not break
  anything, and the server says so in the console once, on the first player
  asked for, rather than failing quietly.
- **`'template'`** — build the URL yourself from the discord id, no API call:
  `template = 'https://my-cdn.example.com/avatars/%s.png'`.
- **`'none'`** — always the default.

`Config.Avatars.default` is used whenever a picture is missing or fails to
load. It can be a URL or a local file under `Files/ui/img/` (add it to the
`files` block in `fxmanifest.lua`).

The lookup is server side and only the finished URL reaches the UI — the bot
token stays in `Config_Server.lua`. If an image fails to load in game, the
player's initial shows in its place; the letter is always drawn underneath, so
there is no broken-image state.

**Waiting for Discord.** Asking Discord costs a round trip, and the menu opens
long before it comes back, so the card has to show *something* in the meantime.
That something is the player's real Discord default avatar, worked out from the
account id on the spot with no call at all — the grey/blurple crest they
actually have — instead of an empty square. The answer is asked for as soon as
they spawn, not when they first open the menu, so by the time they look it is
usually already there.

When the answer does land the player is told, and their card redraws itself. A
picture that arrives and is never announced is the same as no picture at all:
the card was built from the placeholder and nothing would ever replace it,
which reads in game as "the avatar never loads". It is now pushed the moment
the lookup settles, whether it succeeded or failed.

### Custom cards and portraits — the player brings the picture

Staff open a slot, the player fills it in. From **Admin → Points**:

- **Allow Custom Card** — `pvp.admin.custom.card`
- **Allow Custom Portrait** — `pvp.admin.custom.portrait`

The two are **separate permissions on purpose**: you can let someone set their
own card without letting them change their profile picture, or the other way
round. The optional box on the allow row starts them off with a picture; leave
it empty and the choice is theirs.

Each kind also has two more controls under the same permission:

- **Reset** — wipes the picture they chose and leaves the slot open, so they
  can set another. This is the moderation one: a picture that should not be on
  screen goes now without taking away what they were given. It also clears
  their change cooldown, so they are not locked out of replacing it.
- **Remove … Access** — closes the slot entirely.

The player then sees a dashed slot at the end of **Cards** or **Portraits** in
their store — `ADD YOUR OWN` — which opens a box for a link, with a live
preview of what that link actually loads and an optional name. Once set it is
an ordinary item in their list: equip it, unequip it, change it, or empty the
slot and leave it. Nobody else's store has it. **Portraits → Default** puts
them back on their Discord picture, which that tile previews.

The address is checked on the server every time, whether it came from a staff
member or from the player: only an `https://` link or a file under
`Files/ui/img/` is stored, because the value ends up inside a CSS `url()` in
the interface. `data:`, `javascript:`, `file:` and anything climbing out of the
folder are refused with a reason. Players are also rate limited between
changes.

`Config.Store.custom` holds the fallback name, the rarity badge, the cooldown,
the hint shown in the box, and `playerNames = false` if the name under the item
should stay the staff's to set. The slots live in `m5_player_custom`, which the
resource creates on start.

### Team names — `Config.TeamNames`

`mode = 'leader'` names each side after one of its players — `M547'S TEAM` —
using the party leader that queued it, or the highest ranked player when there
was no party. A team of one shows just the name, so a 1v1 reads as the two
player names facing each other. `mode = 'fixed'` uses `TEAM A` / `TEAM B`.

### Scoreboard — hold TAB

`Config.HUD.scoreboard`. Holding the key opens the full board: both teams with
avatars, names, rank, K / D / A, headshots, damage and ping, your own row
highlighted, dead players dimmed and disconnected ones greyed out. It never
opens on its own: the round break shows the win/loss banner and the score and
nothing else, and the board is there on the key if you want it.

The key is registered through FiveM's keybinding system, so a player can rebind
it under **Settings → Key Bindings → FiveM → M5 Ranked PvP** instead of being
stuck with TAB. It needs no NUI focus — the board is display only, so it cannot
swallow your mouse mid fight.

---

## 7f. The world leaderboard board

A leaderboard you can walk up to and read. It is not drawn with `DrawText` —
`Files/ui/board.html` is a real web page, rendered into a texture with FiveM's
DUI and stretched over a flat panel out in the world, so it looks exactly like
the menu does: the top three on a podium on the left, the season standings as a
ten-column table on the right, ranks, avatars, K/D and score.

The table is the whole ladder from first place down, medal tints and all; the
podium on the left is the same top three again, shown large.

Alongside it, three peds stand as the top three, wearing those players' real
appearance.

### What it costs

The point of doing it this way is that a texture costs nothing to keep looking
at — it only costs something when it *changes*. So:

* **One thread.** It sleeps **two seconds** per pass while you are away from
  every board and every podium spot, and only runs at frame rate when a board
  is actually in front of your camera — not merely near you.
* **The page is built on demand.** No board exists until somebody walks into
  range. Walk away and, after `keepAlive` seconds, the page is torn down and
  the texture handed back. Set `keepAlive = 0` to keep it loaded for good.
* **The page holds still.** `board.js` has no timer, no animation and no
  network call, and it compares each payload against the last one and drops it
  if the rows are identical. A repaint is paid for by every machine that can
  see the board, so it does not happen for nothing.
* **Two triangles.** The panel is a quad drawn with `DrawSpritePoly`. You can
  only stand on one side of a flat panel, so the side facing away from your
  camera is not drawn at all: standing in front of a board costs **two**
  triangles per frame, not four. It still reads from behind — walk round it and
  you get the other two instead. No prop is spawned and no game texture is
  replaced.
* **The corner maths runs once.** Turning a heading and a tilt into four world
  corners is eight sines and cosines, and none of it changes while the board
  hangs there, so the result is kept and only worked out again when the board
  actually moves.
* **The peds do not flicker in and out.** The top three are spawned at
  `podium.podiumDistance` and only despawned at a quarter further out again, so
  standing exactly on the line does not spawn and delete three peds every
  couple of seconds.

The editor used to be the expensive part, and is not any more:

* **Dragging a handle no longer rebuilds the menu.** A drag reports the cursor
  thirty times a second; each report used to send the whole panel state back to
  the interface and redraw every row of it — thirty full rebuilds a second
  while the mouse moved. The numbers now settle when you let go of the handle,
  which is the only moment you read them anyway.
* **The focus camera only moves when something moved.** `ركّز عليه` recomputed
  its position every frame from values that had not changed. It now returns
  immediately unless the thing being edited or the orbit around it actually
  changed.

**If it is still too heavy**, in the order worth trying:

| lever | where | what it buys |
|---|---|---|
| `screens.textureWidth` / `textureHeight` | Config_Client.lua | the floor cost. A DUI is a real browser; 1280×720 is one. 960×540 is noticeably cheaper and still readable at four metres — keep 16:9. |
| `keepAlive` | Config_Client.lua | how long the browser lingers after you walk away. Lower it on a server where people pass the board constantly. |
| `screens.distance` | Config_Client.lua | how far out the board starts existing. Nothing at all is paid outside it. |
| `podium.enabled` | Config_Client.lua | the three peds are ordinary peds with real clothing; switching them off is the single biggest saving. |
| `refresh` | Config_Server.lua | how often the standings are rebuilt and pushed. Every push repaints the page on every machine that can see a board. |

### Nobody on it yet — `m5_rankedpvp_board_seed.sql`

The board reads the ladder, and the ladder is built from matches that have been
played. On a new server that is nobody, so the board is empty and looks broken.

`m5_rankedpvp_board_seed.sql` puts a player on it by hand. Change the three
values at the top — user id, name, RP — and run it; every write is an upsert, so
running it again on the same player updates instead of duplicating. It does not
invent a rank badge: after the rows exist, **Admin → Points → Set RP** on the
same id recalculates the rank, the division and the placement state properly
from `Config.Ranks`.

The board rebuilds itself on `Config.WorldBoard.refresh` (five minutes by
default). To see it immediately, in the **server console**:

```
m5boardrefresh
```

which rebuilds the standings, pushes them to everyone, and prints the top ten so
you can check the rows landed where you expected.

### Ten made-up players, to see the board at all — `m5_rankedpvp_board_demo.sql`

The seed above puts one real player on the ladder. This one fills it with **ten
invented players** spread from Radiant down to Silver, so you can stand in front
of the panel and see the whole thing working — the podium, the medal tints, the
rank colours, the K/D columns, the three peds — before anybody has played a
match. It is how you place and size the board without waiting for a season's
worth of results.

They are not accounts. Nothing can log in as them, they are never matched
against anyone, and they take no slot; they exist only in the three tables the
board reads, on ids 900001–900010 so they cannot collide with a real vRP user.

It writes the rank badge itself, so there is nothing to do in the admin panel
afterwards: the file carries the RP thresholds from `Config.Ranks` as a SQL
`CASE`, and `tests/board_demo_sql.lua` checks that copy against the real config
at every RP from zero upwards, so the two cannot drift apart unnoticed. If you
have edited `Config.Ranks` yourself, either edit the `CASE` to match or run
**Admin → Points → Set RP** on each id afterwards.

**They are for testing.** Take them off before the server opens — the last
block of the file is the cleanup, three `DELETE`s over that id range, and then
`m5boardrefresh` again.

### Where it goes — `Config.WorldBoard` (Config_Client.lua)

Each entry under `screens.spots` is one panel:

| field | what it does |
|---|---|
| `pos` | the centre of the panel |
| `h` | which way it faces, in degrees |
| `pitch` | lean, −60 to 60; `0` is upright |
| `width` | how wide it is **in metres** |
| `height` | optional — left out, it follows `width` and the texture's shape so the picture is never stretched |
| `title` | its heading, in place of the season name |
| `enabled` | switch one panel off without deleting it |

`screens.distance` is how far off it is visible, `screens.rows` how many rows
the table shows (from first place down, capped by `Config.WorldBoard.top` on
the server), `screens.emptyText` what stands in for the table when there is
nobody to list, `screens.opacity` how solid it is, and
`screens.textureWidth` / `textureHeight` the size it is rendered at — 1280×720
is right for a panel of four to six metres, and the two must stay 16:9.

**Which rows** it shows — which ladder, how many, how often it refreshes — is
`Config.WorldBoard` in **Config_Server.lua**, because the board is server fed
and the client is never asked what the standings are.

### Placing it in game — `/pvpboard`

Needs `Config.Permissions.editBoard`. It opens an editor with every panel and
podium spot listed; pick one and nudge it while watching it move:

**NORTH / SOUTH**, **EAST / WEST**, **HEIGHT**, **FACING**, **TILT**,
**WIDTH** (metres), **ROWS**, **SEEN FROM**, **OPACITY**, its **TITLE**, and a
**SCREEN ON** switch. **STEP SIZE** multiplies every nudge — 0.25x to 4x — so
dragging a panel across a plaza is not sixty clicks. **PUT IT WHERE I STAND**
drops the panel at eye height turned back towards you, or stands a podium spot
on the floor facing the way you face. Save writes it; cancel throws it away;
reset asks first and then restores the config.

**Saving places it for the whole server, not for you.** The layout goes into
`m5_world_board`, and every player is sent it with the standings — the ones
already connected straight away, and anyone who joins later when they load in.
Nobody has to restart and nothing has to be copied into `Config_Client.lua`;
the spots in the config are only the starting point for a server that has never
placed one. **Reset** puts everybody back on those config spots.

It is read back on the next start and cleaned the same way it was cleaned on
the way in, so a row that has been hand-edited into something unusable is
dropped and the config spots are used rather than leaving the board nowhere. If
the write did not land — the table missing, the database user unable to write
to it — the editor says so on screen instead of reporting a save, because the
board looks placed either way until the restart that loses it.

If the board is nowhere to be seen, it is almost always one of three things,
in this order: nobody has placed it and you are not standing at the example
coordinates in `Config_Client.lua`; `Config.WorldBoard.enabled` is false in
**Config_Server.lua**, which switches it off for everyone whatever the client
config says; or the panel is there and empty because no one is on the ladder
yet — see the demo SQL above. The client asks the server for the rows every
five seconds until it gets an answer, and says so in F8 if six tries go by
with nothing.

### Moving it while you look at it

**MOVE IT IN THE WORLD** shuts the menu and leaves a small panel at the top of
the screen, so the thing you are moving is the thing you are looking at. The
client draws an axis marker at the board's centre — red east/west, green
north/south, blue up — and traces the board's outline in gold, so you can place
it before the page has even loaded.

The panel is the four buttons from the screenshots: **تحريك / حجم / دوران /
تأكيد**, and each of them puts handles on the thing in the world that you drag
with the mouse:

* **تحريك** — a red, a green and a blue arrow for X, Y and Z. Grab one and the
  thing slides along that axis and no other. The arrows grow with distance, so
  they stay the same size on screen wherever the board is.
* **حجم** — green handles on the left and right edges for the width, red ones
  on the top and bottom for the height. A height dragged by hand pins it and
  stretches the picture; **رجّع الارتفاع تلقائي** hands it back to the
  texture's own shape.
* **دوران** — a ring around it. Drag left and right to turn it, up and down to
  lean it. A podium spot is a person, so it turns and nothing else.

The nudge rows are still there underneath for the last quarter of a metre the
mouse will not give you, and the step size above multiplies both the buttons
and the drags, from 0.25x to 4x.

Below them: every board and podium spot, to switch between without going back,
with **+ شاشة** and **+ منصة** to add one and a red ✕ to remove the one being
moved. Then **PUT IT WHERE I STAND** and **BACK TO THE MENU**. **تأكيد** saves
and closes.

### Adding one — pick the spot first

**+ شاشة** and **+ منصة** do not drop the new one on top of you. The panel
turns into *وين تبي الشاشة؟* and the client draws a red disc on the ground
wherever you are looking, with a line up to the height a board would hang at.
Look at the spot, click the ground, and the new one is created there and
selected, with the handles already on it.

### How the mouse reaches the world

The handles are drawn by the client, which is the only side that knows where
they are; the cursor is known only to the page. So a transparent layer under
the panel reports the cursor in normalized screen coordinates — the same 0..1
space `GetScreenCoordFromWorldCoord` projects the handles into — and the
client does the hit testing and the maths. Moves are throttled to thirty a
second, and only while the editor holds focus: walking hands the mouse back to
the game and the layer stands down with it.

While the editor is open the mouse is a cursor: it picks up the handles and
clicks the panel, and it does **not** turn the camera — passing input through
to the game meant the camera span while you were trying to click, and nothing
was usable. **اضغط هنا لتحريك اللاعب** hands the mouse back to the game so you
can walk and look around; the panel dims and **F5** takes it back. That key is
registered through FiveM's keybinding system, so it can be rebound under
**Settings → Key Bindings**.

The panel gets out of the way on its own: while a handle is actually being
dragged it fades almost to nothing and comes back when the mouse comes up.

**ركّز عليه** does the rest of it — the panel goes away *and* the camera comes
round onto the thing you are editing, standing on the side a board faces at
about a width and a half back, so the handles are in front of you and nothing
is covering them. From there **right-drag swings the camera around it** and
**the wheel zooms**; the only things left on screen are the way back and the
walk chip. The camera follows the thing while you drag it, and is handed back
when you come out of the editor, walk, place a new one, or the resource stops.

Everything that has to agree with what is on screen — the projection the
handles are picked with, how long the arrows are, the board's own back-face
cull — reads the *rendered* camera rather than the gameplay one, so it is all
still right while that scripted camera is up.

`/pvpcoords` is the other way: stand where you want it and copy the printed
line straight into `spots`.

---

## 8. Feature map

**Matchmaking** — MMR/rank/ping windows that widen over time, party-aware team
building, ready check with decline cooldown and automatic requeue, avoid list.

**Match engine** — `WAITING → READY → MAP_VOTE → STARTING → LIVE → ROUND_END →
MATCH_END → CLEANUP`, per-match routing bucket with strict entity lockdown, map
voting with random tie-break, spawn protection, out-of-bounds countdown,
surrender vote, overtime with a sudden-death final round, forfeit on abandonment.

**Modes** — 1v1, 2v2, 3v3, 4v4, 5v5, FFA, Team Deathmatch, Search & Destroy,
all best-of configurable.

**Progression** — placement matches with a weighted placement score, seasons with
soft/hard reset, archived leaderboards, season rewards, levels and XP, daily and
weekly missions, achievements, titles, badges, card effects, card frames and
avatar decorations.

**Integrity** — leave penalties that escalate to ranked bans, AFK detection that
ignores countdowns and spectating, ranked bans separate from server bans, and
nine anti-boost detectors that raise reviewable flags with evidence rather than
banning automatically.

**UI** — dashboard, ranked queue, custom game browser and room editor, training,
leaderboard with an oversized top 3, profile, match history with drill-down,
rewards, settings, admin panel; plus the in-match HUD, kill feed, round
countdown, victory/defeat, MVP and rank-up sequences.

---

## 9. Tuning notes

* `Config.Buckets` — each match takes one bucket from `start..max`; custom games
  use `customStart..customMax`. Raise the ranges for very large servers.
* `Config.Matchmaking.expandInterval` / `mmrRangeStep` — the main lever for
  queue time versus match quality.
* `Config.AntiBoost.reviewThreshold` — the severity sum at which a player is
  surfaced in the admin panel.
* `Config.CustomGames.rankedAllowed` — off by default; custom games award no RP,
  no MMR and no rank change unless an admin with `pvp.admin` enables it.
