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

### Database

Reads are cached (`leaderboardCacheTime`, `profileCacheTime`), writes are
batched — player rows are marked dirty and flushed on an interval instead of
per event. Every table carries the indexes its queries need.

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

Each command can be renamed or disabled in `Config.Commands`.

Permissions (`Config.Permissions`): `pvp.menu`, `pvp.custom.create`,
`pvp.moderator`, `pvp.admin`, `pvp.spectate`, `pvp.bans`, `pvp.seasons`,
`pvp.rewards`, `pvp.maps`, `pvp.mmr`, `pvp.rp.modify`.

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
