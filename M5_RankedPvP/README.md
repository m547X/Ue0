# M5 Ranked PvP

A complete competitive PvP system for FiveM — ranked ladder, hidden MMR, seasons,
custom games, matchmaking, penalties, anti-boosting, spectator, and a premium NUI.

**Stack:** FiveM · Lua · vRP (Dunko) · oxmysql · NUI (HTML/CSS/JS)

---

## 1. File structure

Exactly four Lua files, as required:

```
M5_RankedPvP/
│
├── fxmanifest.lua
│
├── Config_Client.lua      ← client settings only (safe to be public)
├── Config_Server.lua      ← server settings only (never sent to a client)
│
├── Files/
│   ├── Client.lua
│   ├── Server.lua
│   └── ui/
│       ├── index.html
│       ├── style.css
│       └── app.js
│
├── m5_rankedpvp.sql
└── README.md
```

`Config_Server.lua` is listed only under `server_scripts`, so webhooks, RP
formulas, permission strings and anti-cheat thresholds never reach a player.

---

## 2. Installation

1. Copy the `M5_RankedPvP` folder into your `resources` directory.
2. Import `m5_rankedpvp.sql` (or leave `Config.Database.autoCreateTables = true`
   and the resource will create every table on first start).
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

Grants are always logged (`[M5RP] rank set: user … -> … season …`). For the
full picture, run this in the **server console**:

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

### Two layers of permission

```lua
Config.Permissions.superAdmin     = 'pvp.all'   -- unlocks every action
Config.Permissions.adminGrantsAll = true        -- 'pvp.admin' also unlocks everything
```

Set `adminGrantsAll = false` for strict per-action control even for admins.

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
weekly missions, achievements, titles, badges, frames.

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
* `Config.Database.flushInterval` — lower it if you restart often, raise it to
  reduce write load.
* `Config.Matchmaking.expandInterval` / `mmrRangeStep` — the main lever for
  queue time versus match quality.
* `Config.AntiBoost.reviewThreshold` — the severity sum at which a player is
  surfaced in the admin panel.
* `Config.CustomGames.rankedAllowed` — off by default; custom games award no RP,
  no MMR and no rank change unless an admin with `pvp.admin` enables it.
