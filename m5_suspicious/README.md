# m5_suspicious

Suspicious player detection, risk scoring and permanent HWID bans for **FiveM**, built for **vRP 0.5** and **oxmysql**.

When a player connects, the server collects every identifier and token FiveM exposes, compares them against history and ban lists, produces a **risk score from 0 to 100**, alerts staff in game, logs to Discord, and lets an admin ban the player by **HWID token**, by **license**, or both — permanently or temporarily.

---

## Contents

```
m5_suspicious/
├── fxmanifest.lua
├── config.lua      -- every tunable value, permission, weight, message and webhook
├── server.lua      -- all security logic: analysis, scoring, bans, admin API
├── client.lua      -- rendering only (alerts + menu)
├── sql.sql         -- database schema
└── README.md
```

---

## Installation

1. Import `sql.sql` into your database.
2. Drop the folder into your `resources` directory.
3. Open `config.lua` and set, at minimum:
   * `Config.AdminPermission` — the vRP permission your staff has.
   * `Config.HWID.Salt` — **change this once, before the first launch.** Changing it later invalidates every stored hash and existing bans stop matching.
   * `Config.Webhook` — your Discord webhook (or set `Config.EnableDiscordLogs = false`).
4. Add `ensure m5_suspicious` to `server.cfg`, **after** `vrp` and `oxmysql`.

The resource warns in the console on startup if the salt or the webhook is still at its default value.

---

## How the analysis works

Everything below runs inside the `playerConnecting` deferral, once per connection.

| Signal | Source |
|---|---|
| Server ID, player name | FiveM |
| vRP User ID | `vRP.getUserIdByIdentifiers` |
| License / Discord / Steam / FiveM ID / IP | `GetPlayerIdentifiers` |
| HWID tokens | `GetNumPlayerTokens` / `GetPlayerToken` |
| First join, join count | `player_history` |
| Shared IP count | `player_history` |
| Shared HWID count | `player_tokens` |
| VPN / proxy, country, region, city | external API, cached |
| Banned HWID / banned license | in-memory ban cache |

No single indicator decides anything. Each contributes a weight, the sum is clamped to `0-100`, and the level comes from `Config.RiskLevels`:

```
0  - 29   LOW
30 - 59   MEDIUM
60 - 79   HIGH
80 - 100  CRITICAL
```

Weights live in `Config.RiskScore` and are all editable:

```lua
Config.RiskScore = {
    VPN = 30, NewAccount = 15, MissingFiveM = 10, MissingDiscord = 10,
    SharedHWID = 30, SharedIP = 15, BannedHWID = 100, BannedLicense = 100,
}
```

Shared HWID/IP additionally scale with the number of linked accounts (`Config.SharedAccountStep`, capped).

A player at or above `Config.SuspiciousThreshold` is recorded in `suspicious_players`, pushed to Discord, and alerted to online staff.

### Auto-ban

Off by default and intentionally hard to trip:

```lua
Config.AutoBan = { Enabled = false, Threshold = 100, MinReasons = 3, Type = "both", Minutes = 0 }
```

A VPN alone, or a new account alone, can never reach it. Leave it disabled unless you have watched the scores on your own server for a while first.

---

## HWID bans

`[Ban HWID]` reads every token of the target — live from the socket when they are online, otherwise from `player_tokens` — and writes one `hwid_bans` row per token, sharing a `group_id` so a single unban lifts the whole set.

On every subsequent connection the tokens are hashed and checked against an in-memory cache of active bans. A match rejects the connection before any API call or query is made, writes an audit row, and fires the `Banned HWID Detected` webhook.

IP is **never** used as a substitute for an HWID ban — it is only ever a scoring signal.

Durations come from `Config.BanDurations` (permanent, 30 days, 7 days, 24 hours by default). Expired bans are deactivated by a one-minute maintenance loop. Unban via the console or in game:

```
unbanhwid <ban id>
unbanlicense <license:xxxxxxxx>
```

### Token handling

Raw tokens are never written to the database, never sent to a client and never posted to Discord. Each token is stored as:

* `token` — salted SHA-256 (`Config.HWID.Salt`), used for comparison;
* `token_mask` — display only, e.g. `8ca357ca...2b686b`.

The SHA-256 implementation is pure Lua 5.4 (no external dependency) and is verified against the standard test vectors.

---

## In-game alerts and menu

Alerts are sent only to sources the **server** has verified with `vRP.hasPermission`, re-checked every 15 seconds. Ordinary players receive nothing at all — not a filtered payload, no event.

```
⚠️ SUSPICIOUS PLAYER
Name: wenestonhadron
Server ID: 283
User ID: 7975

Risk Score: 85/100
Risk Level: HIGH

VPN/Proxy: YES
New Account: NO
Shared IP: 1
Shared HWID: 1

Discord: @alighanem21
FiveM ID: 19236283
```

`/suspicious` (or the optional `Config.MenuKey` binding) opens the list. Arrow keys navigate, `Enter` opens details, `Backspace` goes back, `R` refreshes.

The detail view shows the score, the reasons, masked IP, truncated license, Discord, FiveM ID, Steam, token count, first-detection time, VPN state, location, online state and the previous action taken — with the buttons:

```
[View Details] [Ban HWID] [Ban License] [Ban Player] [Ignore] [Refresh]
```

`←` / `→` cycle the ban duration; confirming a ban opens the on-screen keyboard for the reason.

---

## Security model

* Every decision is server-side. The client sends only a record id, an action name, a duration **index** and a reason string.
* Permissions are checked server-side on every event, per call — never cached into a client-trusted flag.
* Server ID and User ID cannot be spoofed: the target is re-resolved from `suspicious_players` by record id, and the live source from `vRP.getUserSource`.
* Duration is an index into `Config.BanDurations`, so a crafted payload cannot invent an arbitrary value.
* Reason strings are stripped of control characters and length-capped.
* Rate limiting per player (`Config.RateLimit`): `Events` per `Window` seconds, with strikes and an optional kick on repeated abuse.
* Unauthorized event attempts are logged to the server console.
* Clients only ever receive masked IPs and truncated licenses; raw tokens never leave the server.

---

## Error handling

* If the VPN API times out, errors, or returns malformed data, the result is `UNKNOWN` (`-1`) and **contributes zero score**. The connection continues normally and a warning is logged.
* The whole analysis runs under `pcall`. A crash logs the error, fires the error webhook and lets the player in — the anticheat never becomes the reason nobody can join.
* If the ban-cache refresh fails, the previous cache is kept rather than emptied, so a database blip cannot silently lift every ban.

---

## Performance

* No polling loop over players. Work happens on `playerConnecting`, on admin refresh, and on an administrative action.
* The ban list is held in memory (`Config.Cache.BanList`), so a join costs **zero** queries for the ban check, and is invalidated instantly on a local ban/unban.
* Intel gathering is three queries, batched, with indexes on every column they filter on.
* VPN lookups are cached in memory and in `ip_intel_cache` (`Config.VPN.CacheMinutes`, 12 h default), so an IP is queried once.
* The menu list is cached for `Config.Cache.Menu` seconds.
* One maintenance tick per minute expires bans and prunes caches.

---

## Database

| Table | Purpose |
|---|---|
| `suspicious_players` | detections, scores, reasons, handling status |
| `hwid_bans` | one row per banned token hash (+ mask, reason, expiry, group) |
| `license_bans` | license/identifier bans used by `[Ban License]` and `[Ban Player]` |
| `player_tokens` | hashed token history, powers shared-HWID detection and offline bans |
| `player_history` | connection history, powers shared-IP and new-account detection |
| `suspicious_actions` | audit trail of every admin action and every blocked join |
| `ip_intel_cache` | cached VPN/geo results |

---

## Discord logs

Three webhook events, each independently configurable in `Config.Webhooks` (falling back to `Config.Webhook`):

* **⚠️ Suspicious Player** — name, IDs, score, level, VPN, location, identifiers, shared counts, reason list. Escalates to red and can ping `Config.WebhookCriticalRole` at `Config.CriticalThreshold`.
* **🔨 HWID Ban** — player, admin, reason, token count, masked tokens, permanent/temporary.
* **🚨 Banned HWID Detected** — player, server id, matched masked token, original ban id and original player.

Plus unban and internal-error logs. IPs are masked (`1.2.x.x`) and can be hidden entirely with `Config.WebhookShowIP = false`.

---

## Exports

```lua
exports.m5_suspicious:banHWID(userId, reason, minutes, adminName)
exports.m5_suspicious:banPlayer(userId, license, reason, minutes, adminName)
exports.m5_suspicious:isHWIDBanned(source)  --> boolean, banId, reason
```

---

## Notes and limits

* HWID tokens are the strongest identifier FiveM exposes, but they are not unforgeable. A determined user can rotate them. Banning the whole token set (which this resource does) and pairing it with the license ban is what makes evasion expensive — treat it as a strong deterrent, not an absolute one.
* `Config.MinExpectedTokens` flags clients reporting suspiciously few tokens; tune it on your own server before relying on it, as legitimate clients occasionally report fewer.
* The default VPN provider is `ip-api.com` (free, no key, rate limited to ~45 requests/minute). For a busy server use `proxycheck` or `vpnapi` with a key.
