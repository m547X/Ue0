--[[
    ============================================================================
     M5 Ranked PvP — Files/Server.lua
    ----------------------------------------------------------------------------
     Server authoritative core.

     Layout of this file
        01  Utilities
        02  vRP bridge
        03  Database layer (schema, cache, batched writes)
        04  Seasons
        05  Rank / RP / MMR maths
        06  Player registry
        07  Security (rate limits, validation)
        08  Discord logging
        09  Ranked bans & penalties
        10  Party
        11  Queue & matchmaking
        12  Match engine (state machine, rounds, buckets)
        13  Combat validation (headshot one-shot, kills, damage)
        14  Custom games
        15  Training
        16  Rewards / XP / missions / achievements
        17  Anti boosting
        18  Leaderboards / profiles / history
        19  Admin
        20  Net events
        21  Commands
        22  Master loop & lifecycle
    ============================================================================
]]

local RES = GetCurrentResourceName()

-- ============================================================================
-- 01. UTILITIES
-- ============================================================================

local function now()  return os.time() end
local function ms()   return GetGameTimer() end

local function log(fmt, ...)
    print(('[M5RP] ' .. fmt):format(...))
end

local function dbg(fmt, ...)
    if Config.Debug then log('[debug] ' .. fmt, ...) end
end

local function err(fmt, ...)
    print(('^1[M5RP][error] ' .. fmt .. '^7'):format(...))
end

-- ---------------------------------------------------------------------------
-- Integration hooks (Export.lua)
--
-- One entry point for everything the server owner wants to run around a match.
-- Each hook is called inside pcall so a mistake in Export.lua prints an error
-- and the match carries on; nothing in here may take the system down. The same
-- moment is also broadcast as an event, so other resources can listen without
-- touching this one.
-- ---------------------------------------------------------------------------

local function hook(name, data)
    local fn = M5 and M5.Server and M5.Server[name]
    if type(fn) == 'function' then
        local ok, e = pcall(fn, data)
        if not ok then err('Export.lua M5.Server.%s failed: %s', name, tostring(e)) end
    end
    TriggerEvent('m5rp:' .. name, data)
end

local function round(v, p)
    local m = 10 ^ (p or 0)
    return math.floor(v * m + 0.5) / m
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function copy(t)
    if type(t) ~= 'table' then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = copy(v) end
    return r
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function uid(prefix)
    return ('%s%d%04d'):format(prefix or 'M', now(), math.random(0, 9999))
end

local function jsonEncode(v)
    local ok, res = pcall(json.encode, v)
    return ok and res or '{}'
end

local function jsonDecode(v, fallback)
    if type(v) == 'table' then return v end
    if type(v) ~= 'string' or v == '' then return fallback or {} end
    local ok, res = pcall(json.decode, v)
    if ok and type(res) == 'table' then return res end
    return fallback or {}
end

--- Reads a MySQL TINYINT(1) back as a Lua boolean.
---
--- This is not decoration. oxmysql sits on node-mysql2, which converts
--- TINYINT(1) to a JavaScript boolean, so the column arrives in Lua as `true`
--- or `false` — not as 1 or 0. `tonumber(true)` is nil, so the obvious
--- `tonumber(row.flag) == 1` evaluates to false for a flag that is set, and a
--- player whose placement was finished reads back as Unranked on every load.
--- Older driver versions do hand back a number, and a few setups a string, so
--- all three forms are accepted.
local function toBool(v)
    if type(v) == 'boolean' then return v end
    if type(v) == 'number'  then return v ~= 0 end
    if type(v) == 'string'  then
        return v == '1' or v == 'true' or v == 'TRUE' or v == 't'
    end
    return false
end

local function hashString(s)
    local h = 5381
    for i = 1, #s do
        h = ((h * 33) + s:byte(i)) % 4294967296
    end
    return ('%x'):format(h)
end

local function inList(list, value)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

local function safeName(s, maxLen)
    if type(s) ~= 'string' then return '' end
    s = s:gsub('[%c\\]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

local function sqlDate(ts)
    return os.date('%Y-%m-%d %H:%M:%S', ts or now())
end

-- ============================================================================
-- 02. vRP  (Dunko vRP)
-- ============================================================================
-- Direct integration, no abstraction layer. `@vrp/lib/utils.lua` is loaded by
-- fxmanifest.lua and provides the `module`, `Proxy` and `Tunnel` globals.

local Proxy  = module('vrp', 'lib/Proxy')
local Tunnel = module('vrp', 'lib/Tunnel')

-- Tunnel.getInterface(name, identifier): the second argument is THIS resource's
-- name. Omitting it makes vRP register "vRP:nil:tunnel_res" and throw.
vRP       = Proxy.getInterface('vRP')
vRPclient = Tunnel.getInterface('vRP', RES)

--- Display name. GetPlayerName is the only source: it is synchronous, always
--- available, and costs no database round trip.
local function playerName(user_id, source)
    if source then
        local name = GetPlayerName(source)
        if name and name ~= '' then return safeName(name, 60) end
    end
    return 'User ' .. tostring(user_id)
end

--- Adds the "PvP Ranked" entry to the vRP main menu. It opens exactly the same
--- NUI as the command, the keybind and the world marker.
local function registerVrpMenu()
    local cfg = Config.vRP.registerMenu
    if not cfg or not cfg.enabled then return end

    vRP.registerMenuBuilder({ cfg.menu or 'main', function(add, data)
        local user_id = vRP.getUserId({ data.player })
        if not user_id then return end
        if not Config.PublicMenu and not vRP.hasPermission({ user_id, Config.Permissions.openMenu }) then
            return
        end

        local choices = {}
        choices[cfg.name] = {
            function(player)
                vRP.closeMenu({ player })
                TriggerClientEvent('m5rp:cl:openMenu', player)
            end,
            cfg.description or ''
        }
        add(choices)
    end })

    log('vRP menu entry registered ("%s")', cfg.name)
end

-- ============================================================================
-- 03. DATABASE LAYER
-- ============================================================================

--- Set once the schema exists and the active season is known. Loading a profile
--- before that point would stamp its per-season rows with season 0, and every
--- later save (which targets the real season) would then silently update
--- nothing — the player's rank and stats would reappear as fresh on the next
--- join. Every entry point that can load a profile waits on this.
local Boot = { ready = false }

--- Blocks the calling thread until the boot sequence has finished.
--- Returns false if it never does, so callers can bail instead of hanging.
local function waitForBoot(timeoutMs)
    local waited = 0
    local limit  = timeoutMs or 30000
    while not Boot.ready do
        if waited >= limit then return false end
        Citizen.Wait(100)
        waited = waited + 100
    end
    return true
end

local DB = {
    ready = false,
    -- Write batching. Dirty players are flushed on Config.Database.flushInterval.
    dirtyPlayers = {},
    dirtyStats   = {},
    dirtyRanks   = {},
    dirtyMMR     = {}
}

local SCHEMA = {
[[CREATE TABLE IF NOT EXISTS `m5_players` (
  `user_id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL DEFAULT 'Unknown',
  `license` VARCHAR(64) NOT NULL DEFAULT '',
  `discord` VARCHAR(32) NOT NULL DEFAULT '',
  `ip_hash` VARCHAR(64) NOT NULL DEFAULT '',
  `level` INT UNSIGNED NOT NULL DEFAULT 1,
  `xp` INT UNSIGNED NOT NULL DEFAULT 0,
  `titles` LONGTEXT NULL,
  `badges` LONGTEXT NULL,
  `active_title` VARCHAR(48) NOT NULL DEFAULT '',
  `frame` VARCHAR(48) NOT NULL DEFAULT 'default',
  `settings` LONGTEXT NULL,
  `commendations` INT UNSIGNED NOT NULL DEFAULT 0,
  `reports` INT UNSIGNED NOT NULL DEFAULT 0,
  `playtime` INT UNSIGNED NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_seen` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`),
  KEY `idx_players_license` (`license`),
  KEY `idx_players_iphash` (`ip_hash`),
  KEY `idx_players_level` (`level`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_player_stats` (
  `user_id` INT UNSIGNED NOT NULL,
  `season_id` INT UNSIGNED NOT NULL,
  `matches` INT UNSIGNED NOT NULL DEFAULT 0,
  `wins` INT UNSIGNED NOT NULL DEFAULT 0,
  `losses` INT UNSIGNED NOT NULL DEFAULT 0,
  `draws` INT UNSIGNED NOT NULL DEFAULT 0,
  `kills` INT UNSIGNED NOT NULL DEFAULT 0,
  `deaths` INT UNSIGNED NOT NULL DEFAULT 0,
  `assists` INT UNSIGNED NOT NULL DEFAULT 0,
  `headshots` INT UNSIGNED NOT NULL DEFAULT 0,
  `damage` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `mvp` INT UNSIGNED NOT NULL DEFAULT 0,
  `win_streak` INT NOT NULL DEFAULT 0,
  `best_win_streak` INT NOT NULL DEFAULT 0,
  `lose_streak` INT NOT NULL DEFAULT 0,
  `clutches` INT UNSIGNED NOT NULL DEFAULT 0,
  `aces` INT UNSIGNED NOT NULL DEFAULT 0,
  `first_bloods` INT UNSIGNED NOT NULL DEFAULT 0,
  `rounds_won` INT UNSIGNED NOT NULL DEFAULT 0,
  `rounds_played` INT UNSIGNED NOT NULL DEFAULT 0,
  `leaves` INT UNSIGNED NOT NULL DEFAULT 0,
  `afk_count` INT UNSIGNED NOT NULL DEFAULT 0,
  `playtime` INT UNSIGNED NOT NULL DEFAULT 0,
  `fav_weapon` VARCHAR(48) NOT NULL DEFAULT '',
  `fav_map` VARCHAR(48) NOT NULL DEFAULT '',
  `weapon_stats` LONGTEXT NULL,
  `map_stats` LONGTEXT NULL,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`,`season_id`),
  KEY `idx_stats_season_kills` (`season_id`,`kills`),
  KEY `idx_stats_season_wins` (`season_id`,`wins`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_player_ranks` (
  `user_id` INT UNSIGNED NOT NULL,
  `season_id` INT UNSIGNED NOT NULL,
  `mode` VARCHAR(24) NOT NULL DEFAULT '1v1',
  `rp` INT NOT NULL DEFAULT 0,
  `rank_id` INT NOT NULL DEFAULT 0,
  `division` INT NOT NULL DEFAULT 0,
  `highest_rank_id` INT NOT NULL DEFAULT 0,
  `highest_rp` INT NOT NULL DEFAULT 0,
  `placement_done` TINYINT(1) NOT NULL DEFAULT 0,
  `placement_played` INT NOT NULL DEFAULT 0,
  `placement_data` LONGTEXT NULL,
  `rank_protection` INT NOT NULL DEFAULT 0,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`,`season_id`,`mode`),
  KEY `idx_ranks_board` (`season_id`,`mode`,`rp`),
  KEY `idx_ranks_rank` (`season_id`,`mode`,`rank_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_player_mmr` (
  `user_id` INT UNSIGNED NOT NULL,
  `season_id` INT UNSIGNED NOT NULL,
  `mode` VARCHAR(24) NOT NULL DEFAULT '1v1',
  `mmr` INT NOT NULL DEFAULT 1000,
  `uncertainty` INT NOT NULL DEFAULT 350,
  `games` INT NOT NULL DEFAULT 0,
  `peak_mmr` INT NOT NULL DEFAULT 1000,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`,`season_id`,`mode`),
  KEY `idx_mmr_season` (`season_id`,`mode`,`mmr`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_matches` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `match_uid` VARCHAR(40) NOT NULL,
  `season_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `mode` VARCHAR(24) NOT NULL,
  `map_id` VARCHAR(48) NOT NULL,
  `ranked` TINYINT(1) NOT NULL DEFAULT 1,
  `custom_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `state` VARCHAR(16) NOT NULL DEFAULT 'CLEANUP',
  `team_a_score` INT NOT NULL DEFAULT 0,
  `team_b_score` INT NOT NULL DEFAULT 0,
  `winner` TINYINT NOT NULL DEFAULT 0,
  `rounds_played` INT NOT NULL DEFAULT 0,
  `overtime` TINYINT(1) NOT NULL DEFAULT 0,
  `bucket` INT NOT NULL DEFAULT 0,
  `avg_mmr_a` INT NOT NULL DEFAULT 0,
  `avg_mmr_b` INT NOT NULL DEFAULT 0,
  `balanced` TINYINT(1) NOT NULL DEFAULT 1,
  `mvp_user_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `duration` INT NOT NULL DEFAULT 0,
  `end_reason` VARCHAR(32) NOT NULL DEFAULT '',
  `started_at` DATETIME NULL,
  `ended_at` DATETIME NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_match_uid` (`match_uid`),
  KEY `idx_matches_season` (`season_id`,`ended_at`),
  KEY `idx_matches_mode` (`mode`),
  KEY `idx_matches_ended` (`ended_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_match_players` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `match_id` INT UNSIGNED NOT NULL,
  `user_id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL DEFAULT '',
  `team` TINYINT NOT NULL DEFAULT 1,
  `kills` INT NOT NULL DEFAULT 0,
  `deaths` INT NOT NULL DEFAULT 0,
  `assists` INT NOT NULL DEFAULT 0,
  `headshots` INT NOT NULL DEFAULT 0,
  `damage` INT NOT NULL DEFAULT 0,
  `score` INT NOT NULL DEFAULT 0,
  `clutches` INT NOT NULL DEFAULT 0,
  `first_bloods` INT NOT NULL DEFAULT 0,
  `rounds_won` INT NOT NULL DEFAULT 0,
  `mvp` TINYINT(1) NOT NULL DEFAULT 0,
  `rp_before` INT NOT NULL DEFAULT 0,
  `rp_after` INT NOT NULL DEFAULT 0,
  `rp_change` INT NOT NULL DEFAULT 0,
  `mmr_before` INT NOT NULL DEFAULT 0,
  `mmr_after` INT NOT NULL DEFAULT 0,
  `rank_before` INT NOT NULL DEFAULT 0,
  `rank_after` INT NOT NULL DEFAULT 0,
  `result` VARCHAR(12) NOT NULL DEFAULT 'LOSS',
  `left_early` TINYINT(1) NOT NULL DEFAULT 0,
  `afk` TINYINT(1) NOT NULL DEFAULT 0,
  `fav_weapon` VARCHAR(48) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_match_user` (`match_id`,`user_id`),
  KEY `idx_mp_user` (`user_id`),
  KEY `idx_mp_match` (`match_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_match_rounds` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `match_id` INT UNSIGNED NOT NULL,
  `round_no` INT NOT NULL,
  `winner` TINYINT NOT NULL DEFAULT 0,
  `duration` INT NOT NULL DEFAULT 0,
  `reason` VARCHAR(24) NOT NULL DEFAULT '',
  `score_a` INT NOT NULL DEFAULT 0,
  `score_b` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_rounds_match` (`match_id`,`round_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_match_kills` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `match_id` INT UNSIGNED NOT NULL,
  `round_no` INT NOT NULL DEFAULT 0,
  `killer` INT UNSIGNED NOT NULL DEFAULT 0,
  `victim` INT UNSIGNED NOT NULL DEFAULT 0,
  `weapon` VARCHAR(48) NOT NULL DEFAULT '',
  `headshot` TINYINT(1) NOT NULL DEFAULT 0,
  `distance` FLOAT NOT NULL DEFAULT 0,
  `ts` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_kills_match` (`match_id`),
  KEY `idx_kills_killer` (`killer`),
  KEY `idx_kills_victim` (`victim`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_seasons` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `number` INT NOT NULL DEFAULT 1,
  `name` VARCHAR(64) NOT NULL,
  `start_at` DATETIME NOT NULL,
  `end_at` DATETIME NOT NULL,
  `active` TINYINT(1) NOT NULL DEFAULT 1,
  `rewards` LONGTEXT NULL,
  `finalized` TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_seasons_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_season_players` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `season_id` INT UNSIGNED NOT NULL,
  `user_id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL DEFAULT '',
  `final_rp` INT NOT NULL DEFAULT 0,
  `final_rank_id` INT NOT NULL DEFAULT 0,
  `rank_name` VARCHAR(32) NOT NULL DEFAULT '',
  `highest_rank_id` INT NOT NULL DEFAULT 0,
  `placement` INT NOT NULL DEFAULT 0,
  `wins` INT NOT NULL DEFAULT 0,
  `losses` INT NOT NULL DEFAULT 0,
  `kd` FLOAT NOT NULL DEFAULT 0,
  `rewarded` TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_season_user` (`season_id`,`user_id`),
  KEY `idx_sp_board` (`season_id`,`final_rp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_rank_bans` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL DEFAULT '',
  `discord` VARCHAR(32) NOT NULL DEFAULT '',
  `license` VARCHAR(64) NOT NULL DEFAULT '',
  `type` VARCHAR(24) NOT NULL DEFAULT 'RANKED',
  `mode` VARCHAR(24) NOT NULL DEFAULT '',
  `reason` VARCHAR(255) NOT NULL DEFAULT '',
  `admin` VARCHAR(64) NOT NULL DEFAULT 'SYSTEM',
  `admin_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `duration` INT NOT NULL DEFAULT 0,
  `start_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expiry` DATETIME NULL,
  `evidence` LONGTEXT NULL,
  `notes` LONGTEXT NULL,
  `active` TINYINT(1) NOT NULL DEFAULT 1,
  `unbanned_by` VARCHAR(64) NOT NULL DEFAULT '',
  `unbanned_at` DATETIME NULL,
  PRIMARY KEY (`id`),
  KEY `idx_bans_user` (`user_id`,`active`),
  KEY `idx_bans_expiry` (`expiry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_custom_games` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `room_uid` VARCHAR(40) NOT NULL,
  `name` VARCHAR(64) NOT NULL,
  `host_id` INT UNSIGNED NOT NULL,
  `host_name` VARCHAR(64) NOT NULL DEFAULT '',
  `mode` VARCHAR(24) NOT NULL,
  `map_id` VARCHAR(48) NOT NULL,
  `ranked` TINYINT(1) NOT NULL DEFAULT 0,
  `settings` LONGTEXT NULL,
  `players` INT NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ended_at` DATETIME NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_room_uid` (`room_uid`),
  KEY `idx_custom_host` (`host_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_custom_game_players` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `game_id` INT UNSIGNED NOT NULL,
  `user_id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL DEFAULT '',
  `team` TINYINT NOT NULL DEFAULT 1,
  `kills` INT NOT NULL DEFAULT 0,
  `deaths` INT NOT NULL DEFAULT 0,
  `headshots` INT NOT NULL DEFAULT 0,
  `result` VARCHAR(12) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `idx_cgp_game` (`game_id`),
  KEY `idx_cgp_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_anti_boost_flags` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL DEFAULT '',
  `target_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `type` VARCHAR(48) NOT NULL,
  `severity` INT NOT NULL DEFAULT 1,
  `details` LONGTEXT NULL,
  `match_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `reviewed` TINYINT(1) NOT NULL DEFAULT 0,
  `admin` VARCHAR(64) NOT NULL DEFAULT '',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_flags_user` (`user_id`,`reviewed`),
  KEY `idx_flags_severity` (`severity`),
  KEY `idx_flags_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_rewards` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reward_key` VARCHAR(64) NOT NULL,
  `name` VARCHAR(96) NOT NULL,
  `type` VARCHAR(24) NOT NULL,
  `value` LONGTEXT NULL,
  `rank_required` INT NOT NULL DEFAULT 0,
  `season_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `active` TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_reward_key_season` (`reward_key`,`season_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_player_rewards` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` INT UNSIGNED NOT NULL,
  `reward_key` VARCHAR(64) NOT NULL,
  `season_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `type` VARCHAR(24) NOT NULL DEFAULT '',
  `value` LONGTEXT NULL,
  `claimed` TINYINT(1) NOT NULL DEFAULT 0,
  `claimed_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_player_reward` (`user_id`,`reward_key`,`season_id`),
  KEY `idx_pr_user` (`user_id`,`claimed`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_player_missions` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` INT UNSIGNED NOT NULL,
  `mission_key` VARCHAR(64) NOT NULL,
  `kind` VARCHAR(12) NOT NULL DEFAULT 'daily',
  `progress` INT NOT NULL DEFAULT 0,
  `target` INT NOT NULL DEFAULT 1,
  `completed` TINYINT(1) NOT NULL DEFAULT 0,
  `claimed` TINYINT(1) NOT NULL DEFAULT 0,
  `period` VARCHAR(16) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_mission` (`user_id`,`mission_key`,`period`),
  KEY `idx_missions_user` (`user_id`,`kind`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_player_achievements` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` INT UNSIGNED NOT NULL,
  `achievement` VARCHAR(64) NOT NULL,
  `unlocked_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_achievement` (`user_id`,`achievement`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_admin_logs` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `admin_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `admin_name` VARCHAR(64) NOT NULL DEFAULT '',
  `action` VARCHAR(48) NOT NULL,
  `target_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `target_name` VARCHAR(64) NOT NULL DEFAULT '',
  `amount` INT NOT NULL DEFAULT 0,
  `before_value` INT NOT NULL DEFAULT 0,
  `after_value` INT NOT NULL DEFAULT 0,
  `reason` VARCHAR(255) NOT NULL DEFAULT '',
  `details` LONGTEXT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_audit_admin` (`admin_id`),
  KEY `idx_audit_target` (`target_id`),
  KEY `idx_audit_action` (`action`),
  KEY `idx_audit_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_player_penalties` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` INT UNSIGNED NOT NULL,
  `type` VARCHAR(24) NOT NULL DEFAULT 'LEAVE',
  `match_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `rp_lost` INT NOT NULL DEFAULT 0,
  `cooldown` INT NOT NULL DEFAULT 0,
  `expires_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_pen_user` (`user_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

-- Store wallet and equipped cosmetics. Kept in its own table rather than as
-- columns on m5_players, because the schema is created with CREATE TABLE IF
-- NOT EXISTS — adding columns to a table that already exists would need an
-- ALTER that never runs on a live server.
[[CREATE TABLE IF NOT EXISTS `m5_player_store` (
  `user_id` INT UNSIGNED NOT NULL,
  `coins` BIGINT NOT NULL DEFAULT 0,
  `card` VARCHAR(48) NOT NULL DEFAULT 'default',
  `title` VARCHAR(48) NOT NULL DEFAULT 'none',
  `effect` VARCHAR(48) NOT NULL DEFAULT 'none',
  `frame` VARCHAR(48) NOT NULL DEFAULT 'none',
  `avatar` VARCHAR(48) NOT NULL DEFAULT 'none',
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `m5_player_items` (
  `user_id` INT UNSIGNED NOT NULL,
  `kind` VARCHAR(16) NOT NULL,
  `item_id` VARCHAR(48) NOT NULL,
  `price_paid` INT NOT NULL DEFAULT 0,
  `acquired_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`,`kind`,`item_id`),
  KEY `idx_items_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
}

function DB.query(sql, params)
    local ok, res = pcall(function()
        return MySQL.query.await(sql, params)
    end)
    if not ok then
        err('query failed: %s', tostring(res))
        return nil
    end
    return res
end

function DB.single(sql, params)
    local ok, res = pcall(function()
        return MySQL.single.await(sql, params)
    end)
    if not ok then
        err('single failed: %s', tostring(res))
        return nil
    end
    return res
end

function DB.scalar(sql, params)
    local ok, res = pcall(function()
        return MySQL.scalar.await(sql, params)
    end)
    if not ok then return nil end
    return res
end

function DB.insert(sql, params)
    local ok, res = pcall(function()
        return MySQL.insert.await(sql, params)
    end)
    if not ok then
        err('insert failed: %s', tostring(res))
        return nil
    end
    return res
end

function DB.update(sql, params)
    local ok, res = pcall(function()
        return MySQL.update.await(sql, params)
    end)
    if not ok then
        err('update failed: %s', tostring(res))
        return 0
    end
    return res or 0
end

--- Same query, but reports whether it actually ran. DB.update returns 0 both
--- for "the query failed" and for "nothing needed changing", which makes it
--- unsafe for anything that clears a dirty flag on success — a transient error
--- would drop the change for good. Returns ok, affectedRows.
function DB.write(sql, params)
    local ok, res = pcall(function()
        return MySQL.update.await(sql, params)
    end)
    if not ok then
        err('write failed: %s', tostring(res))
        return false, 0
    end
    return true, res or 0
end

--- Brings a database created before per-mode ranks up to date.
---
--- CREATE TABLE IF NOT EXISTS does nothing to a table that already exists, so
--- an existing install would keep the old two-column key and every ladder
--- would overwrite the one before it. This adds the column, stamps the old
--- rows with the legacy pool so nobody loses a rank, and widens the primary
--- key. It is idempotent: once the column is there it does nothing at all.
local function migrateRankPools()
    local db = DB.scalar('SELECT DATABASE()')
    if not db then return end

    local pools = Config.RankPools or {}
    local legacy = pools.legacy or pools.default or '1v1'

    -- the store gained an effect, a frame and an avatar slot; same idempotent
    -- shape, so a server that already has some of them only gets the rest
    for _, col in ipairs({ 'effect', 'frame', 'avatar' }) do
        local there = tonumber(DB.scalar(
            [[SELECT COUNT(*) FROM information_schema.TABLES
              WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'm5_player_store']], { db }) or 0) or 0
        local has = tonumber(DB.scalar(
            [[SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'm5_player_store'
                AND COLUMN_NAME = ?]], { db, col }) or 0) or 0
        if there > 0 and has == 0 then
            log('^3adding m5_player_store.%s', col)
            DB.query(("ALTER TABLE `m5_player_store` ADD COLUMN `%s` VARCHAR(48) NOT NULL DEFAULT 'none'")
                :format(col))
        end
    end

    for _, t in ipairs({ 'm5_player_ranks', 'm5_player_mmr' }) do
        local exists = tonumber(DB.scalar(
            [[SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = 'mode']],
            { db, t }) or 0) or 0

        -- the table may simply not exist yet on a fresh install
        local tableThere = tonumber(DB.scalar(
            [[SELECT COUNT(*) FROM information_schema.TABLES
              WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?]], { db, t }) or 0) or 0

        if tableThere > 0 and exists == 0 then
            log('^3migrating %s to per-mode ranks (existing rows -> ladder "%s")', t, legacy)
            DB.query(('ALTER TABLE `%s` ADD COLUMN `mode` VARCHAR(24) NOT NULL DEFAULT %s AFTER `season_id`')
                :format(t, ("'" .. legacy:gsub("'", "''") .. "'")))
            DB.query(('UPDATE `%s` SET `mode` = ? WHERE `mode` = %s'):format(t, "''"), { legacy })
            DB.query(('ALTER TABLE `%s` DROP PRIMARY KEY, ADD PRIMARY KEY (`user_id`,`season_id`,`mode`)')
                :format(t))
            log('^2%s migrated', t)
        end
    end
end

function DB.init()
    if not Config.Database.autoCreateTables then
        -- Even with auto-create off, a table missing the per-mode column would
        -- reject every rank write from here on. Say so loudly rather than
        -- failing silently once a match ends.
        local db = DB.scalar('SELECT DATABASE()')
        if db then
            local has = tonumber(DB.scalar(
                [[SELECT COUNT(*) FROM information_schema.COLUMNS
                  WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'm5_player_ranks'
                    AND COLUMN_NAME = 'mode']], { db }) or 0) or 0
            local tableThere = tonumber(DB.scalar(
                [[SELECT COUNT(*) FROM information_schema.TABLES
                  WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'm5_player_ranks']], { db }) or 0) or 0
            if tableThere > 0 and has == 0 then
                err('m5_player_ranks has no `mode` column: per-mode ranks cannot be saved. '
                    .. 'Run m5_rankedpvp_permode.sql, or turn Config.Database.autoCreateTables '
                    .. 'on once and restart to migrate automatically.')
            end
        end
        DB.ready = true
        return
    end
    for i = 1, #SCHEMA do
        DB.query(SCHEMA[i])
    end
    migrateRankPools()
    DB.ready = true
    log('database schema verified (%d tables)', #SCHEMA)
end

-- ============================================================================
-- 04. SEASONS
-- ============================================================================

local Season = {
    current = nil,   -- { id, number, name, start_at, end_at }
    endsAt  = 0
}

--- oxmysql hands DATETIME back either as a string or as a millisecond
--- timestamp depending on the driver version. A value we cannot read must
--- never resolve to "now", otherwise the season would roll over instantly.
local function toTimestamp(value, fallback)
    if type(value) == 'number' then
        return value > 100000000000 and math.floor(value / 1000) or math.floor(value)
    end
    if type(value) == 'string' then
        local y, mo, d, h, mi, sec = value:match('(%d+)-(%d+)-(%d+)[ T](%d+):(%d+):(%d+)')
        if y then
            return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                             hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec) })
        end
    end
    return fallback
end

function Season.load()
    local row = DB.single('SELECT * FROM m5_seasons WHERE active = 1 ORDER BY id DESC LIMIT 1')
    if row then
        Season.current = row
        Season.endsAt  = toTimestamp(row.end_at, 0)
        if Season.endsAt == 0 then
            err('could not read the season end date (%s) — automatic rollover disabled',
                tostring(row.end_at))
        end
        log('active season: #%d %s', row.number or 0, row.name or '?')
        return
    end

    if not Config.Seasons.autoCreate then
        log('^3no active season and autoCreate is off — ranked progression is paused')
        return
    end
    Season.create()
end

function Season.create(number)
    local lastNumber = DB.scalar('SELECT MAX(number) FROM m5_seasons') or 0
    local n = number or (tonumber(lastNumber) or 0) + 1
    local startAt = now()
    local endAt   = startAt + (Config.Seasons.defaultDurationDays * 86400)
    local name    = (Config.Seasons.namePattern or 'Season %d'):format(n)

    DB.update('UPDATE m5_seasons SET active = 0 WHERE active = 1')
    local id = DB.insert(
        'INSERT INTO m5_seasons (number, name, start_at, end_at, active) VALUES (?, ?, ?, ?, 1)',
        { n, name, sqlDate(startAt), sqlDate(endAt) })

    Season.current = { id = id, number = n, name = name }
    Season.endsAt  = endAt
    log('created new season #%d (%s), ends %s', n, name, sqlDate(endAt))
    return id
end

function Season.id()
    return Season.current and Season.current.id or 0
end

-- ============================================================================
-- 05. RANK / RP / MMR MATHS
-- ============================================================================

local RankById   = {}
local RankedList = {}   -- ranks with id > 0, ordered ascending

for i = 1, #Config.Ranks do
    local r = Config.Ranks[i]
    RankById[r.id] = r
    if r.id > 0 then RankedList[#RankedList + 1] = r end
end
table.sort(RankedList, function(a, b) return a.rpRequired < b.rpRequired end)

local Rank = {}

function Rank.get(id)
    return RankById[id] or RankById[0]
end

--- Resolve the rank entry for a given RP value.
function Rank.fromRP(rp)
    local best = RankedList[1]
    for i = 1, #RankedList do
        if rp >= RankedList[i].rpRequired then
            best = RankedList[i]
        else
            break
        end
    end
    return best
end

--- Base RP of the tier the player belongs to (used by demotion protection).
function Rank.tierFloor(rankId)
    local r = Rank.get(rankId)
    if not r or r.id == 0 then return 0 end
    local floorRP = r.rpRequired
    for i = 1, #RankedList do
        if RankedList[i].tier == r.tier then
            floorRP = RankedList[i].rpRequired
            break
        end
    end
    return floorRP
end

function Rank.nextThreshold(rp)
    for i = 1, #RankedList do
        if RankedList[i].rpRequired > rp then
            return RankedList[i].rpRequired, RankedList[i]
        end
    end
    return nil, nil
end

--- Progress data used by the rank card in the UI.
function Rank.progress(rp, rankId, placementDone)
    local cur = Rank.get(rankId)
    if not placementDone or rankId == 0 then
        return { percent = 0, current = 0, needed = 0, next = nil }
    end
    local nextRP, nextRank = Rank.nextThreshold(rp)
    if not nextRP then
        return { percent = 100, current = rp - cur.rpRequired, needed = 0, next = nil }
    end
    local base   = cur.rpRequired
    local span   = math.max(1, nextRP - base)
    local inside = clamp(rp - base, 0, span)
    return {
        percent = round((inside / span) * 100, 1),
        current = inside,
        needed  = nextRP - rp,
        next    = nextRank and nextRank.name or nil
    }
end

--- Public (client safe) rank table for the NUI.
local function rankTableForClient()
    local out = {}
    for i = 1, #Config.Ranks do
        local r = Config.Ranks[i]
        out[#out + 1] = {
            id = r.id, tier = r.tier, division = r.division,
            name = r.name, rp = r.rpRequired, color = r.color
        }
    end
    return out
end

-- ---------------------------------------------------------------------------
-- MMR
-- ---------------------------------------------------------------------------

local MMR = {}

function MMR.kFactor(pd)
    if not pd.placementDone then return Config.MMR.kPlacement end
    if pd.mmr >= Config.MMR.highRankThreshold then return Config.MMR.kHighRank end
    return Config.MMR.kBase
end

--- Expected score of A against B (classic elo).
function MMR.expected(a, b)
    return 1 / (1 + 10 ^ ((b - a) / 400))
end

--- Returns the new MMR value.
-- @param pd            player data
-- @param teamMMR       average MMR of the player's team
-- @param enemyMMR      average MMR of the enemy team
-- @param won           boolean
-- @param performance   -1.0 .. 1.0 relative performance inside the lobby
function MMR.calculate(pd, teamMMR, enemyMMR, won, performance)
    local k   = MMR.kFactor(pd)
    local exp = MMR.expected(teamMMR, enemyMMR)
    local act = won and 1 or 0
    local base = k * (act - exp)

    local perf = (performance or 0) * k * Config.MMR.performanceFactor
    local delta = base + perf

    -- Uncertainty widens the swing for new accounts
    local uFactor = 1 + ((pd.uncertainty - Config.MMR.uncertaintyMin) /
                         math.max(1, Config.MMR.uncertaintyStart)) * 0.5

    local newMMR = clamp(math.floor(pd.mmr + delta * uFactor + 0.5),
                         Config.MMR.min, Config.MMR.max)
    return newMMR
end

-- ---------------------------------------------------------------------------
-- RP calculation
-- ---------------------------------------------------------------------------

local RP = {}

--- Normalised performance value (0 .. 2, 1 = lobby average).
local function ratio(value, average)
    if average <= 0 then
        return value > 0 and 2.0 or 1.0
    end
    return clamp(value / average, 0.0, 2.0)
end

--- Computes the RP change for one player at the end of a ranked match.
-- @param ctx table {
--   won, draw, roundsWon, roundsLost, mvp,
--   kills, deaths, damage, headshots, clutches, objective,
--   avgKills, avgDamage, avgHeadshots, avgKD,
--   teamScoreShare, allyMMR, enemyMMR, allyRank, enemyRank,
--   winStreak, loseStreak, balanced, pd }
function RP.calculate(ctx)
    local C = Config.RankedPoints
    local W = C.weights
    local pd = ctx.pd

    local base = ctx.won and C.winBase or -C.lossBase
    if ctx.draw then base = 0 end

    -- --- round dominance -------------------------------------------------
    local diff = (ctx.roundsWon or 0) - (ctx.roundsLost or 0)
    local roundBonus = clamp(diff * W.roundDiffPerRound, -W.roundDiffMax, W.roundDiffMax)
    if not ctx.won and not ctx.draw then
        -- a close loss costs less, a blowout costs more
        roundBonus = clamp(roundBonus, -W.roundDiffMax, W.roundDiffMax)
    end

    -- --- opponent strength ------------------------------------------------
    local mmrGap    = (ctx.enemyMMR or 1000) - (ctx.allyMMR or 1000)
    local mmrFactor = ctx.won and W.mmrFactorWin or W.mmrFactorLoss
    local mmrBonus  = (mmrGap / W.mmrScale) * mmrFactor
    if not ctx.won then mmrBonus = mmrBonus * -1 end       -- losing to stronger teams hurts less
    mmrBonus = clamp(mmrBonus, -10, 10)

    -- --- rank gap ----------------------------------------------------------
    local rankGap   = clamp((ctx.enemyRank or 0) - (ctx.allyRank or 0),
                            -W.rankGapMax, W.rankGapMax)
    local rankBonus = rankGap * W.rankGapFactor * (ctx.won and 1 or -1)

    -- --- individual performance -------------------------------------------
    local kd     = (ctx.deaths or 0) > 0 and (ctx.kills or 0) / ctx.deaths or (ctx.kills or 0)
    local perf   = 0
    perf = perf + (ratio(kd, ctx.avgKD or 1) - 1) * W.kdWeight
    perf = perf + (ratio(ctx.kills or 0, ctx.avgKills or 1) - 1) * W.killsWeight
    perf = perf + (ratio(ctx.damage or 0, ctx.avgDamage or 1) - 1) * W.damageWeight
    perf = perf + (ratio(ctx.headshots or 0, ctx.avgHeadshots or 1) - 1) * W.headshotWeight
    perf = perf + clamp(ctx.clutches or 0, 0, 3) * W.clutchWeight
    perf = perf + clamp(ctx.objective or 0, 0, 4) * W.objectiveWeight
    perf = perf + ((ctx.teamScoreShare or 0.25) - 0.25) * W.teamShareWeight * 4

    perf = clamp(perf, -W.maxPerformanceMalus, W.maxPerformanceBonus)

    -- --- bonuses -----------------------------------------------------------
    local bonus = 0
    if ctx.mvp then bonus = bonus + C.mvpBonus end

    local hsBonus = math.min(math.floor((ctx.headshots or 0) / 4), C.headshotBonusLimit)
    bonus = bonus + hsBonus

    if ctx.won then
        local streak = ctx.winStreak or 0
        local streakBonus = 0
        for len, value in pairs(C.streakTable) do
            if streak >= len and value > streakBonus then streakBonus = value end
        end
        bonus = bonus + math.max(streakBonus, streak >= 2 and C.winStreakBonus or 0)
    end

    -- --- assemble ----------------------------------------------------------
    local total = base + roundBonus + mmrBonus + rankBonus + perf + bonus

    -- Unbalanced lobbies are worth less
    if ctx.balanced == false then
        total = total * W.unbalancedPenalty
    end

    -- Lose streak protection
    if not ctx.won and not ctx.draw and Config.RankSettings.loseStreakProtection.enabled then
        local lsp = Config.RankSettings.loseStreakProtection
        if (ctx.loseStreak or 0) >= lsp.afterLosses then
            total = total * lsp.lossMultiplier
        end
    end

    -- Never let bonuses flip the sign of the result
    if ctx.won then
        total = clamp(total, C.minimumGain, C.maximumGain)
    elseif ctx.draw then
        total = clamp(total, -6, 6)
    else
        total = clamp(total, -C.maximumLoss, -C.minimumLoss)
    end

    return math.floor(total + 0.5), {
        base       = round(base, 1),
        rounds     = round(roundBonus, 1),
        opponent   = round(mmrBonus + rankBonus, 1),
        performance= round(perf, 1),
        bonus      = round(bonus, 1)
    }
end

--- Applies an RP delta with demotion / rank protection and returns a summary.
function RP.apply(pd, delta, reason)
    local before      = pd.rp
    local beforeRank  = pd.rankId
    local settings    = Config.RankSettings

    local target = clamp(before + delta, settings.minRP, settings.maxRP)

    -- Demotion protection: stay inside the current tier for `rankProtection` games
    if delta < 0 and settings.demotionProtection then
        local floorRP = Rank.tierFloor(beforeRank)
        if pd.rankProtection > 0 and target < floorRP then
            target = floorRP
        end
    end

    pd.rp = target
    local newRank = Rank.fromRP(pd.rp)

    -- Radiant slot cap
    if newRank.tier == 'RADIANT' and (settings.radiantSlots or 0) > 0 then
        if not Rank.radiantSlotFree(pd.userId, pd.rp) then
            newRank = Rank.get(22) -- Immortal
        end
    end

    local changed = newRank.id ~= beforeRank
    pd.rankId   = newRank.id
    pd.division = newRank.division

    if pd.rankId > pd.highestRankId then pd.highestRankId = pd.rankId end
    if pd.rp > pd.highestRP then pd.highestRP = pd.rp end

    if changed and newRank.id > beforeRank then
        pd.rankProtection = Config.RankSettings.rankProtectionGames
    elseif pd.rankProtection > 0 then
        pd.rankProtection = pd.rankProtection - 1
    end

    pd.dirtyRank = true

    if changed then
        hook('onRankChange', {
            userId = pd.userId, name = pd.name,
            from = { id = beforeRank, name = Rank.get(beforeRank).name },
            to   = { id = newRank.id, name = newRank.name },
            rp = pd.rp, promoted = newRank.id > beforeRank
        })
    end

    return {
        before     = before,
        after      = pd.rp,
        delta      = pd.rp - before,
        rankBefore = beforeRank,
        rankAfter  = pd.rankId,
        rankUp     = changed and pd.rankId > beforeRank,
        rankDown   = changed and pd.rankId < beforeRank,
        reason     = reason
    }
end

--- Radiant is limited to the top N RP holders of the season.
function Rank.radiantSlotFree(userId, rp)
    local slots = Config.RankSettings.radiantSlots or 0
    if slots <= 0 then return true end
    local threshold = RankById[23] and RankById[23].rpRequired or 2600
    -- the cap is per ladder: the top slots of 1v1 are not the top slots of 2v2
    local pool = (Players[userId] and Players[userId].pool) or defaultPool()
    local higher = DB.scalar(
        'SELECT COUNT(*) FROM m5_player_ranks WHERE season_id = ? AND mode = ? AND user_id <> ? AND rp >= ? AND rp > ?',
        { Season.id(), pool, userId, threshold, rp }) or 0
    return tonumber(higher) < slots
end

-- ============================================================================
-- 06. PLAYER REGISTRY
-- ============================================================================

local Players   = {}   -- [userId] = playerData
local SrcToUser = {}   -- [source] = userId
local UserToSrc = {}   -- [userId] = source

local function srcOf(userId)
    local s = UserToSrc[userId]
    if s and GetPlayerName(s) then return s end
    return nil
end

local function pdOf(source)
    local uidv = SrcToUser[source]
    return uidv and Players[uidv] or nil
end

local function identifiersOf(source)
    local out = { license = '', discord = '', ip = '' }
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local id = GetPlayerIdentifier(source, i)
        if id then
            if id:sub(1, 8) == 'license:' then out.license = id:sub(9)
            elseif id:sub(1, 8) == 'discord:' then out.discord = id:sub(9)
            elseif id:sub(1, 3) == 'ip:' then out.ip = id:sub(4) end
        end
    end
    return out
end

local function emptyStats()
    return {
        matches = 0, wins = 0, losses = 0, draws = 0,
        kills = 0, deaths = 0, assists = 0, headshots = 0,
        damage = 0, mvp = 0, win_streak = 0, best_win_streak = 0,
        lose_streak = 0, clutches = 0, aces = 0, first_bloods = 0,
        rounds_won = 0, rounds_played = 0, leaves = 0, afk_count = 0,
        playtime = 0, fav_weapon = '', fav_map = '',
        weapon_stats = {}, map_stats = {}
    }
end

local Player = {}

-- ---------------------------------------------------------------------------
-- RANK POOLS
-- ---------------------------------------------------------------------------
-- One pool is one independent ladder — RP, rank, placement and MMR. Which pool
-- a mode belongs to is decided here and nowhere else.
--
-- Everything downstream (RP.apply, the rank getters, the boot payload, the
-- admin grants) keeps reading pd.rp / pd.rankId / pd.mmr exactly as it always
-- has: those flat fields are a window onto whichever pool is active. Switching
-- pools writes the window back and reads the next one in, so the hundreds of
-- call sites never had to learn about pools at all.
-- ---------------------------------------------------------------------------

local POOL_RANK_FIELDS = {
    'rp', 'rankId', 'division', 'highestRankId', 'highestRP',
    'placementDone', 'placementPlayed', 'placementData', 'rankProtection'
}
local POOL_MMR_FIELDS = { 'mmr', 'uncertainty', 'mmrGames', 'peakMMR' }

--- The pool the hub opens on, and the home of any row saved before pools.
local function defaultPool()
    return (Config.RankPools or {}).default or '1v1'
end

--- The pool a mode's rank belongs to.
function Player.poolOf(mode)
    local cfg = Config.RankPools or {}
    if cfg.perMode == false then return cfg.default or '1v1' end
    if not mode or mode == '' then return cfg.default or '1v1' end
    return (cfg.shared or {})[mode] or mode
end

local function emptyPool()
    return {
        rp = 0, rankId = 0, division = 0, highestRankId = 0, highestRP = 0,
        placementDone = false, placementPlayed = 0, placementData = {},
        rankProtection = 0,
        mmr = Config.MMR.startValue, uncertainty = Config.MMR.uncertaintyStart,
        mmrGames = 0, peakMMR = Config.MMR.startValue
    }
end

--- Copies the live fields back into the pool they belong to.
function Player.syncPool(pd)
    if not pd or not pd.pool then return end
    local into = pd.pools[pd.pool]
    if not into then into = emptyPool(); pd.pools[pd.pool] = into end
    for i = 1, #POOL_RANK_FIELDS do
        local f = POOL_RANK_FIELDS[i]; into[f] = pd[f]
    end
    for i = 1, #POOL_MMR_FIELDS do
        local f = POOL_MMR_FIELDS[i]; into[f] = pd[f]
    end
    local d = pd.poolDirty[pd.pool] or { rank = false, mmr = false }
    d.rank = d.rank or pd.dirtyRank
    d.mmr  = d.mmr  or pd.dirtyMMR
    pd.poolDirty[pd.pool] = d
end

--- Makes `pool` the live one. Safe to call with the pool already active.
function Player.usePool(pd, pool)
    if not pd then return end
    pool = pool or (Config.RankPools or {}).default or '1v1'
    if pd.pool == pool then return end

    Player.syncPool(pd)

    local from = pd.pools[pool]
    if not from then from = emptyPool(); pd.pools[pool] = from end
    for i = 1, #POOL_RANK_FIELDS do
        local f = POOL_RANK_FIELDS[i]; pd[f] = from[f]
    end
    for i = 1, #POOL_MMR_FIELDS do
        local f = POOL_MMR_FIELDS[i]; pd[f] = from[f]
    end

    pd.pool = pool
    local d = pd.poolDirty[pool] or { rank = false, mmr = false }
    pd.dirtyRank = d.rank
    pd.dirtyMMR  = d.mmr
end

--- Switches to the pool that owns `mode`. The one every caller should use.
function Player.useMode(pd, mode)
    Player.usePool(pd, Player.poolOf(mode))
end

--- Read one pool without disturbing the live one. For matchmaking, which has
--- to weigh several players against a mode none of them are inside yet.
function Player.poolData(pd, pool)
    if not pd then return emptyPool() end
    if pd.pool == pool then
        local live = emptyPool()
        for i = 1, #POOL_RANK_FIELDS do
            local f = POOL_RANK_FIELDS[i]; live[f] = pd[f]
        end
        for i = 1, #POOL_MMR_FIELDS do
            local f = POOL_MMR_FIELDS[i]; live[f] = pd[f]
        end
        return live
    end
    return pd.pools[pool] or emptyPool()
end

--- Loads (or creates) every persisted row for a user and puts it in the cache.
function Player.load(userId, source)
    -- Re-loading a profile that is already cached replaces the live table, so
    -- anything not yet written (an admin grant, a match result) would be lost.
    -- Flush it first; the read below then returns the same values.
    local cached = Players[userId]
    if cached then Player.save(cached, false) end

    local seasonId = Season.id()
    local ids      = source and identifiersOf(source) or { license = '', discord = '', ip = '' }
    local name     = playerName(userId, source)
    local ipHash   = ids.ip ~= '' and hashString(ids.ip) or ''

    -- ---- core row --------------------------------------------------------
    local row = DB.single('SELECT * FROM m5_players WHERE user_id = ?', { userId })
    if not row then
        DB.insert([[INSERT INTO m5_players (user_id, name, license, discord, ip_hash, settings, titles, badges)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
            { userId, name, ids.license, ids.discord, ipHash, '{}', '[]', '[]' })
        row = {
            user_id = userId, name = name, license = ids.license, discord = ids.discord,
            level = 1, xp = 0, titles = '[]', badges = '[]', active_title = '',
            frame = 'default', settings = '{}', commendations = 0, reports = 0, playtime = 0
        }
    elseif source then
        -- only refresh identity columns for a real connection; loading an
        -- offline row for an admin edit must not overwrite the stored name
        DB.update('UPDATE m5_players SET name = ?, license = ?, discord = ?, ip_hash = ?, last_seen = ? WHERE user_id = ?',
            { name, ids.license, ids.discord, ipHash, sqlDate(), userId })
    else
        name = row.name or name
    end

    -- ---- rank + mmr rows, one per pool -----------------------------------
    -- Every pool the player has ever played comes back in one read each; a
    -- pool with no row yet simply starts empty when it is first activated.
    local pools = {}
    local function poolEntry(name)
        local e = pools[name]
        if not e then
            e = {
                rp = 0, rankId = 0, division = 0, highestRankId = 0, highestRP = 0,
                placementDone = false, placementPlayed = 0, placementData = {},
                rankProtection = 0,
                mmr = Config.MMR.startValue, uncertainty = Config.MMR.uncertaintyStart,
                mmrGames = 0, peakMMR = Config.MMR.startValue
            }
            pools[name] = e
        end
        return e
    end

    local rankRows = DB.query('SELECT * FROM m5_player_ranks WHERE user_id = ? AND season_id = ?',
        { userId, seasonId }) or {}
    for i = 1, #rankRows do
        local r = rankRows[i]
        local e = poolEntry(r.mode ~= nil and r.mode ~= '' and r.mode or defaultPool())
        e.rp             = tonumber(r.rp) or 0
        e.rankId         = tonumber(r.rank_id) or 0
        e.division       = tonumber(r.division) or 0
        e.highestRankId  = tonumber(r.highest_rank_id) or 0
        e.highestRP      = tonumber(r.highest_rp) or 0
        e.placementDone  = toBool(r.placement_done)
        e.placementPlayed= tonumber(r.placement_played) or 0
        e.placementData  = jsonDecode(r.placement_data, {})
        e.rankProtection = tonumber(r.rank_protection) or 0
    end

    local mmrRows = DB.query('SELECT * FROM m5_player_mmr WHERE user_id = ? AND season_id = ?',
        { userId, seasonId }) or {}
    for i = 1, #mmrRows do
        local r = mmrRows[i]
        local e = poolEntry(r.mode ~= nil and r.mode ~= '' and r.mode or defaultPool())
        e.mmr         = tonumber(r.mmr) or Config.MMR.startValue
        e.uncertainty = tonumber(r.uncertainty) or Config.MMR.uncertaintyStart
        e.mmrGames    = tonumber(r.games) or 0
        e.peakMMR     = tonumber(r.peak_mmr) or Config.MMR.startValue
    end

    -- the pool the hub opens on always exists, so a brand new player has
    -- something to be Unranked in
    local startPool = defaultPool()
    local rank = poolEntry(startPool)

    -- ---- stats row -------------------------------------------------------
    local stats = DB.single('SELECT * FROM m5_player_stats WHERE user_id = ? AND season_id = ?',
        { userId, seasonId })
    if not stats then
        DB.insert('INSERT INTO m5_player_stats (user_id, season_id) VALUES (?, ?)', { userId, seasonId })
        stats = emptyStats()
    else
        stats.weapon_stats = jsonDecode(stats.weapon_stats, {})
        stats.map_stats    = jsonDecode(stats.map_stats, {})
    end

    local pd = {
        userId    = userId,
        source    = source,
        name      = name,
        license   = ids.license,
        discord   = ids.discord,
        ipHash    = ipHash,

        level     = tonumber(row.level) or 1,
        xp        = tonumber(row.xp) or 0,
        titles    = jsonDecode(row.titles, {}),
        badges    = jsonDecode(row.badges, {}),
        activeTitle = row.active_title or '',
        frame     = row.frame or 'default',
        settings  = jsonDecode(row.settings, {}),
        commendations = tonumber(row.commendations) or 0,
        reports   = tonumber(row.reports) or 0,
        playtime  = tonumber(row.playtime) or 0,

        -- every ladder the player has, and the one these flat fields mirror
        pools     = pools,
        pool      = startPool,
        poolDirty = {},

        rp             = rank.rp,
        rankId         = rank.rankId,
        division       = rank.division,
        highestRankId  = rank.highestRankId,
        highestRP      = rank.highestRP,
        placementDone  = rank.placementDone,
        placementPlayed= rank.placementPlayed,
        placementData  = rank.placementData,
        rankProtection = rank.rankProtection,

        mmr         = rank.mmr,
        uncertainty = rank.uncertainty,
        mmrGames    = rank.mmrGames,
        peakMMR     = rank.peakMMR,

        stats = {
            matches = tonumber(stats.matches) or 0,
            wins = tonumber(stats.wins) or 0,
            losses = tonumber(stats.losses) or 0,
            draws = tonumber(stats.draws) or 0,
            kills = tonumber(stats.kills) or 0,
            deaths = tonumber(stats.deaths) or 0,
            assists = tonumber(stats.assists) or 0,
            headshots = tonumber(stats.headshots) or 0,
            damage = tonumber(stats.damage) or 0,
            mvp = tonumber(stats.mvp) or 0,
            win_streak = tonumber(stats.win_streak) or 0,
            best_win_streak = tonumber(stats.best_win_streak) or 0,
            lose_streak = tonumber(stats.lose_streak) or 0,
            clutches = tonumber(stats.clutches) or 0,
            aces = tonumber(stats.aces) or 0,
            first_bloods = tonumber(stats.first_bloods) or 0,
            rounds_won = tonumber(stats.rounds_won) or 0,
            rounds_played = tonumber(stats.rounds_played) or 0,
            leaves = tonumber(stats.leaves) or 0,
            afk_count = tonumber(stats.afk_count) or 0,
            playtime = tonumber(stats.playtime) or 0,
            fav_weapon = stats.fav_weapon or '',
            fav_map = stats.fav_map or '',
            weapon_stats = type(stats.weapon_stats) == 'table' and stats.weapon_stats or {},
            map_stats = type(stats.map_stats) == 'table' and stats.map_stats or {}
        },

        -- runtime
        state     = 'IDLE',     -- IDLE | QUEUE | READY | MATCH | CUSTOM | TRAINING
        matchId   = nil,
        team      = 0,
        partyId   = nil,
        joinedAt  = now(),
        rateBuckets = {},
        floodCount  = 0,
        avoidList = {},

        dirtyPlayer = false,
        dirtyStats  = false,
        dirtyRank   = false,
        dirtyMMR    = false
    }

    Players[userId] = pd
    if source then
        SrcToUser[source] = userId
        UserToSrc[userId] = source
    end
    return pd
end

--- Flushes one player's dirty rows.
---
--- The per-season tables are written as upserts on purpose. A plain UPDATE
--- silently succeeds with zero affected rows when the (user_id, season_id) row
--- is missing — which is exactly how an admin-granted rank could disappear on
--- the next join. Upserting means the write always lands, whether the row was
--- created at load time, dropped by a season reset, or never existed at all.
function Player.save(pd, removeAfter)
    if not pd then return end
    local seasonId = Season.id()

    if pd.dirtyPlayer then
        local okWrite = DB.write([[UPDATE m5_players SET name = ?, level = ?, xp = ?, titles = ?, badges = ?,
                    active_title = ?, frame = ?, settings = ?, commendations = ?, reports = ?,
                    playtime = ?, last_seen = ? WHERE user_id = ?]],
            { pd.name, pd.level, pd.xp, jsonEncode(pd.titles), jsonEncode(pd.badges),
              pd.activeTitle, pd.frame, jsonEncode(pd.settings), pd.commendations,
              pd.reports, pd.playtime, sqlDate(), pd.userId })
        if okWrite then pd.dirtyPlayer = false end
    end

    -- Season 0 is not a season: it only happens if a profile was touched before
    -- Season.load() ran. Writing there would bury the data in a phantom season,
    -- so the dirty flags are kept and the next flush retries.
    if seasonId == 0 then
        if pd.dirtyRank or pd.dirtyMMR or pd.dirtyStats then
            err('no active season — holding unsaved ranked data for user %d', pd.userId)
        end
        if removeAfter then Players[pd.userId] = nil end
        return
    end

    -- Every pool the player has touched this session is written, not just the
    -- live one: they can win a 2v2 and then open the hub on 1v1, and the 2v2
    -- result must not be sitting in memory when they disconnect.
    Player.syncPool(pd)
    for pool, dirty in pairs(pd.poolDirty) do
        local e = pd.pools[pool]
        if e and dirty.rank then
            local okWrite = DB.write([[INSERT INTO m5_player_ranks
                        (user_id, season_id, mode, rp, rank_id, division, highest_rank_id, highest_rp,
                         placement_done, placement_played, placement_data, rank_protection)
                        VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                        ON DUPLICATE KEY UPDATE
                         rp = VALUES(rp), rank_id = VALUES(rank_id), division = VALUES(division),
                         highest_rank_id = VALUES(highest_rank_id), highest_rp = VALUES(highest_rp),
                         placement_done = VALUES(placement_done),
                         placement_played = VALUES(placement_played),
                         placement_data = VALUES(placement_data),
                         rank_protection = VALUES(rank_protection)]],
                { pd.userId, seasonId, pool, e.rp, e.rankId, e.division, e.highestRankId, e.highestRP,
                  e.placementDone and 1 or 0, e.placementPlayed, jsonEncode(e.placementData),
                  e.rankProtection })
            -- keep it dirty on a failed write so the next flush retries instead
            -- of dropping an admin grant or a match result on the floor
            if okWrite then dirty.rank = false
            else err('rank save failed for user %d pool %s — retrying on the next flush', pd.userId, pool) end
        end

        if e and dirty.mmr then
            local okWrite = DB.write([[INSERT INTO m5_player_mmr
                        (user_id, season_id, mode, mmr, uncertainty, games, peak_mmr)
                        VALUES (?,?,?,?,?,?,?)
                        ON DUPLICATE KEY UPDATE
                         mmr = VALUES(mmr), uncertainty = VALUES(uncertainty),
                         games = VALUES(games), peak_mmr = VALUES(peak_mmr)]],
                { pd.userId, seasonId, pool, e.mmr, e.uncertainty, e.mmrGames, e.peakMMR })
            if okWrite then dirty.mmr = false end
        end
    end
    -- the live flags follow whatever is still outstanding on the active pool
    local liveDirty = pd.poolDirty[pd.pool] or { rank = false, mmr = false }
    pd.dirtyRank = liveDirty.rank
    pd.dirtyMMR  = liveDirty.mmr

    if pd.dirtyStats then
        local s = pd.stats
        local okWrite = DB.write([[INSERT INTO m5_player_stats
                    (user_id, season_id, matches, wins, losses, draws, kills, deaths, assists,
                     headshots, damage, mvp, win_streak, best_win_streak, lose_streak, clutches,
                     aces, first_bloods, rounds_won, rounds_played, leaves, afk_count, playtime,
                     fav_weapon, fav_map, weapon_stats, map_stats)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON DUPLICATE KEY UPDATE
                     matches = VALUES(matches), wins = VALUES(wins), losses = VALUES(losses),
                     draws = VALUES(draws), kills = VALUES(kills), deaths = VALUES(deaths),
                     assists = VALUES(assists), headshots = VALUES(headshots),
                     damage = VALUES(damage), mvp = VALUES(mvp),
                     win_streak = VALUES(win_streak), best_win_streak = VALUES(best_win_streak),
                     lose_streak = VALUES(lose_streak), clutches = VALUES(clutches),
                     aces = VALUES(aces), first_bloods = VALUES(first_bloods),
                     rounds_won = VALUES(rounds_won), rounds_played = VALUES(rounds_played),
                     leaves = VALUES(leaves), afk_count = VALUES(afk_count),
                     playtime = VALUES(playtime), fav_weapon = VALUES(fav_weapon),
                     fav_map = VALUES(fav_map), weapon_stats = VALUES(weapon_stats),
                     map_stats = VALUES(map_stats)]],
            { pd.userId, seasonId, s.matches, s.wins, s.losses, s.draws, s.kills, s.deaths,
              s.assists, s.headshots, s.damage, s.mvp, s.win_streak, s.best_win_streak,
              s.lose_streak, s.clutches, s.aces, s.first_bloods, s.rounds_won, s.rounds_played,
              s.leaves, s.afk_count, s.playtime, s.fav_weapon, s.fav_map,
              jsonEncode(s.weapon_stats), jsonEncode(s.map_stats) })
        if okWrite then pd.dirtyStats = false end
    end

    -- Dropping the cache entry while something is still unwritten would throw
    -- the change away, so a failed save keeps the player in memory to retry.
    if removeAfter then
        local poolPending = false
        for _, d in pairs(pd.poolDirty) do
            if d.rank or d.mmr then poolPending = true break end
        end
        if pd.dirtyPlayer or pd.dirtyStats or poolPending then
            err('keeping user %d cached: unsaved data still pending', pd.userId)
        else
            Players[pd.userId] = nil
        end
    end
end

function Player.saveAll()
    for _, pd in pairs(Players) do
        Player.save(pd, false)
    end
end

--- Recomputes the favourite weapon / map from the aggregated stat maps.
function Player.refreshFavourites(pd)
    local bestW, bestWn = '', -1
    for w, n in pairs(pd.stats.weapon_stats) do
        if n > bestWn then bestW, bestWn = w, n end
    end
    local bestM, bestMn = '', -1
    for m, n in pairs(pd.stats.map_stats) do
        if n > bestMn then bestM, bestMn = m, n end
    end
    pd.stats.fav_weapon = bestW
    pd.stats.fav_map    = bestM
end

-- ============================================================================
-- 07. SECURITY
-- ============================================================================

local Security = {}

--- Sliding window rate limiter. Returns false when the caller must be ignored.
function Security.allow(pd, bucketName)
    if not pd then return false end
    local cfg = Config.Security.rateLimits[bucketName] or Config.Security.rateLimits.default
    local b = pd.rateBuckets[bucketName]
    local t = ms()
    if not b or (t - b.start) > cfg.window then
        pd.rateBuckets[bucketName] = { start = t, n = 1 }
        return true
    end
    b.n = b.n + 1
    if b.n > cfg.max then
        pd.floodCount = pd.floodCount + 1
        if Config.Security.logRejections then
            dbg('rate limit hit: user %d bucket %s (%d/%d)', pd.userId, bucketName, b.n, cfg.max)
        end
        return false
    end
    return true
end

function Security.weaponAllowed(weaponName)
    if not weaponName or weaponName == '' then return false end
    weaponName = weaponName:upper()
    if inList(Config.Weapons.blacklisted, weaponName) then return false end
    return inList(Config.Weapons.allowed, weaponName)
end

function Security.isMelee(weaponName)
    weaponName = (weaponName or ''):upper()
    return weaponName == 'WEAPON_KNIFE' or weaponName == 'WEAPON_BAT'
        or weaponName == 'WEAPON_UNARMED' or weaponName:find('MELEE') ~= nil
end

function Security.validSource(source, pd)
    return pd ~= nil and pd.source == source
end

-- ============================================================================
-- 08. DISCORD LOGGING
-- ============================================================================

local Logger = { queue = {} }

local function logFields(pd, extra)
    local fields = {}
    if pd then
        fields[#fields + 1] = { name = 'Player', value = ('%s (`%d`)'):format(pd.name, pd.userId), inline = true }
        fields[#fields + 1] = { name = 'Discord', value = pd.discord ~= '' and ('<@%s>'):format(pd.discord) or '—', inline = true }
        fields[#fields + 1] = { name = 'License', value = ('`%s`'):format(pd.license ~= '' and pd.license or '—'), inline = true }
        fields[#fields + 1] = { name = 'Rank', value = Rank.get(pd.rankId).name, inline = true }
        fields[#fields + 1] = { name = 'RP', value = tostring(pd.rp), inline = true }
    end
    if extra then
        for i = 1, #extra do fields[#fields + 1] = extra[i] end
    end
    return fields
end

--- Queue a Discord embed. Never blocks the caller.
function Logger.send(channel, title, description, pd, extraFields)
    if not Config.Webhooks.enabled then return end
    local url = Config.Webhooks.urls[channel]
    if not url or url == '' then return end
    if #Logger.queue >= Config.Webhooks.maxQueue then return end

    Logger.queue[#Logger.queue + 1] = {
        url = url,
        embed = {
            title       = title,
            description = description or '',
            color       = Config.Webhooks.colors[channel] or 3447003,
            fields      = logFields(pd, extraFields),
            footer      = { text = ('%s • %s'):format(Config.ServerName, os.date('%Y-%m-%d %H:%M:%S')) }
        }
    }
end

function Logger.flush()
    if #Logger.queue == 0 then return end

    -- Group embeds by webhook url (Discord accepts up to 10 embeds per message)
    local grouped = {}
    for i = 1, #Logger.queue do
        local item = Logger.queue[i]
        grouped[item.url] = grouped[item.url] or {}
        local g = grouped[item.url]
        if #g < 10 then g[#g + 1] = item.embed end
    end
    Logger.queue = {}

    for url, embeds in pairs(grouped) do
        PerformHttpRequest(url, function() end, 'POST', json.encode({
            username   = Config.Webhooks.botName,
            avatar_url = Config.Webhooks.avatar ~= '' and Config.Webhooks.avatar or nil,
            embeds     = embeds
        }), { ['Content-Type'] = 'application/json' })
    end
end

-- ---------------------------------------------------------------------------
-- Client push helpers
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Text (Locale.lua)
--
-- The English line is the key, so nothing here needs a lookup table of its
-- own: every message written in this file is handed to _L() on its way out and
-- comes back in the player's language, or unchanged when there is no
-- translation for it.
--
-- The server does not know which language a given player picked until they
-- have booted, so the actual swap happens on their client, which holds the
-- table. What the server sends is the English key plus the values to fill in.
-- ---------------------------------------------------------------------------

--- Translates a line into the server default. Used for console output and
--- Discord logs, where there is no player to ask.
local function _L(str)
    if type(str) ~= 'string' then return str end
    local lang = (Locale and Locale[Locale.default]) or nil
    return (lang and lang[str]) or str
end

--- Same, but formats afterwards. The pattern is translated *before* the values
--- are substituted, which is the only order that works.
local function _Lf(str, ...)
    return _L(str):format(...)
end

local function notify(source, kind, message, title, ...)
    if not source then return end
    -- The client translates and formats: it is the side that knows the
    -- player's chosen language.
    TriggerClientEvent('m5rp:cl:notify', source, {
        kind = kind or 'info', message = message, title = title,
        args = select('#', ...) > 0 and { ... } or nil
    })
end

local function notifyUser(userId, kind, message, title, ...)
    local s = srcOf(userId)
    if s then notify(s, kind, message, title, ...) end
end

-- ============================================================================
-- 09. RANKED BANS & PENALTIES
-- ============================================================================

local Bans = { cache = {} } -- [userId] = { list of active bans }

local function parseSqlDate(v)
    if not v then return 0 end
    return toTimestamp(v, 0)
end

function Bans.load(userId)
    local rows = DB.query('SELECT * FROM m5_rank_bans WHERE user_id = ? AND active = 1', { userId }) or {}
    local list = {}
    for i = 1, #rows do
        local r = rows[i]
        local expiry = r.duration == 0 and 0 or parseSqlDate(r.expiry)
        if expiry ~= 0 and expiry <= now() then
            DB.update('UPDATE m5_rank_bans SET active = 0 WHERE id = ?', { r.id })
        else
            list[#list + 1] = {
                id = r.id, type = r.type, mode = r.mode, reason = r.reason,
                admin = r.admin, expiry = expiry, duration = r.duration,
                notes = r.notes, evidence = r.evidence
            }
        end
    end
    Bans.cache[userId] = list
    return list
end

function Bans.get(userId)
    return Bans.cache[userId] or Bans.load(userId)
end

--- Returns the blocking ban entry or nil.
-- @param kind 'RANKED' | 'CUSTOM' | 'CHAT' | 'PARTY' | 'MODE'
function Bans.check(userId, kind, mode)
    local list = Bans.get(userId)
    for i = 1, #list do
        local b = list[i]
        if b.expiry ~= 0 and b.expiry <= now() then
            -- expired between refreshes
            DB.update('UPDATE m5_rank_bans SET active = 0 WHERE id = ?', { b.id })
        else
            if b.type == 'PERMANENT' then return b end
            if b.type == kind then
                if kind ~= 'MODE' or b.mode == '' or b.mode == mode then return b end
            end
            if kind == 'RANKED' and b.type == 'RANKED' then return b end
        end
    end
    return nil
end

function Bans.add(userId, data)
    local pd = Players[userId]
    local name    = data.name or (pd and pd.name) or ''
    local license = pd and pd.license or ''
    local discord = pd and pd.discord or ''
    local duration= tonumber(data.duration) or 0
    local expiry  = duration > 0 and sqlDate(now() + duration) or nil

    local id = DB.insert([[INSERT INTO m5_rank_bans
        (user_id, name, discord, license, type, mode, reason, admin, admin_id, duration, start_at, expiry, evidence, notes, active)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)]],
        { userId, name, discord, license, data.type or 'RANKED', data.mode or '',
          safeName(data.reason or 'No reason', 240), data.admin or 'SYSTEM', data.adminId or 0,
          duration, sqlDate(), expiry, data.evidence or '', data.notes or '' })

    Bans.load(userId)

    Logger.send('rankBan', 'Ranked Ban Issued', nil, pd or { name = name, userId = userId, discord = discord, license = license, rankId = 0, rp = 0 }, {
        { name = 'Type', value = data.type or 'RANKED', inline = true },
        { name = 'Duration', value = duration > 0 and (('%d min'):format(math.floor(duration / 60))) or 'Permanent', inline = true },
        { name = 'Admin', value = data.admin or 'SYSTEM', inline = true },
        { name = 'Reason', value = data.reason or 'No reason', inline = false }
    })

    if Config.RankBan.notifyPlayer then
        notifyUser(userId, 'error',
            ('You received a ranked ban (%s). Reason: %s'):format(data.type or 'RANKED', data.reason or '—'),
            'RANKED BAN')
    end
    return id
end

function Bans.remove(userId, banId, adminName)
    local q = banId
        and DB.update('UPDATE m5_rank_bans SET active = 0, unbanned_by = ?, unbanned_at = ? WHERE id = ? AND user_id = ?',
                      { adminName or 'SYSTEM', sqlDate(), banId, userId })
        or  DB.update('UPDATE m5_rank_bans SET active = 0, unbanned_by = ?, unbanned_at = ? WHERE user_id = ? AND active = 1',
                      { adminName or 'SYSTEM', sqlDate(), userId })
    Bans.load(userId)

    local pd = Players[userId]
    Logger.send('unban', 'Ranked Ban Removed', nil, pd, {
        { name = 'Admin', value = adminName or 'SYSTEM', inline = true },
        { name = 'Ban ID', value = tostring(banId or 'all'), inline = true }
    })
    notifyUser(userId, 'success', 'Your ranked ban has been removed.', 'UNBANNED')
    return q
end

-- ---------------------------------------------------------------------------
-- Leave / AFK penalties
-- ---------------------------------------------------------------------------

local Penalty = { cooldowns = {} } -- [userId] = expiry timestamp

function Penalty.cooldownLeft(userId)
    local c = Penalty.cooldowns[userId]
    if not c then return 0 end
    local left = c - now()
    if left <= 0 then
        Penalty.cooldowns[userId] = nil
        return 0
    end
    return left
end

function Penalty.setCooldown(userId, seconds)
    if seconds and seconds > 0 then
        Penalty.cooldowns[userId] = now() + seconds
    end
end

--- Counts recent offences inside the configured rolling window.
function Penalty.recentOffences(userId)
    local since = sqlDate(now() - (Config.LeavePenalty.windowDays * 86400))
    local n = DB.scalar('SELECT COUNT(*) FROM m5_player_penalties WHERE user_id = ? AND created_at >= ?',
        { userId, since }) or 0
    return tonumber(n) or 0
end

--- Applies the escalating leave / AFK penalty.
-- @param kind 'LEAVE' | 'AFK'
function Penalty.apply(userId, kind, matchId, preLive)
    if not Config.LeavePenalty.enabled then return nil end
    local pd = Players[userId]
    local offence = Penalty.recentOffences(userId) + 1

    local tier = Config.LeavePenalty.tiers[#Config.LeavePenalty.tiers]
    for i = 1, #Config.LeavePenalty.tiers do
        if Config.LeavePenalty.tiers[i].offence == offence then
            tier = Config.LeavePenalty.tiers[i]
            break
        end
    end

    local rpLoss = tier.rp
    if kind == 'AFK' then
        rpLoss = Config.AFK.penalty.rpPenalty
    end
    if preLive then
        rpLoss = math.floor(rpLoss * Config.LeavePenalty.preLiveMultiplier)
    end

    local result
    if pd and rpLoss > 0 and pd.placementDone then
        result = RP.apply(pd, -rpLoss, kind)
        pd.dirtyRank = true
    end

    if pd then
        pd.stats[kind == 'AFK' and 'afk_count' or 'leaves'] =
            (pd.stats[kind == 'AFK' and 'afk_count' or 'leaves'] or 0) + 1
        pd.dirtyStats = true
    end

    local cooldown = kind == 'AFK' and Config.AFK.penalty.cooldown or tier.cooldown
    Penalty.setCooldown(userId, cooldown)

    DB.insert('INSERT INTO m5_player_penalties (user_id, type, match_id, rp_lost, cooldown, expires_at) VALUES (?, ?, ?, ?, ?, ?)',
        { userId, kind, matchId or 0, rpLoss, cooldown, cooldown > 0 and sqlDate(now() + cooldown) or nil })

    if tier.ban and tier.ban > 0 then
        Bans.add(userId, {
            type = 'RANKED', duration = tier.ban, admin = 'SYSTEM',
            reason = ('Repeated abandons (offence #%d)'):format(offence)
        })
    end

    Logger.send(kind == 'AFK' and 'afk' or 'leave',
        kind == 'AFK' and 'AFK Penalty' or 'Match Abandoned', nil, pd, {
            { name = 'Offence', value = ('#%d (%s)'):format(offence, tier.label), inline = true },
            { name = 'RP Lost', value = tostring(rpLoss), inline = true },
            { name = 'Cooldown', value = cooldown > 0 and (('%d min'):format(math.floor(cooldown / 60))) or 'none', inline = true }
        })

    notifyUser(userId, 'error',
        ('%s penalty: -%d RP%s'):format(kind, rpLoss,
            cooldown > 0 and (', queue locked for ' .. math.floor(cooldown / 60) .. ' min') or ''),
        'PENALTY')

    return { rp = rpLoss, cooldown = cooldown, offence = offence, result = result }
end

-- ============================================================================
-- 10. PARTY
-- ============================================================================

-- Forward declaration. The store subsystem is defined much further down, but
-- the party roster below needs to read a member's equipped cosmetics, and a
-- local declared later in the file is not in scope up here.
local Store

local Parties = {}  -- [partyId] = party
local Invites  = {} -- [userId] = { partyId, from, expires }

-- forward declaration: the party code needs the matchmaker (party size drives
-- the searched mode), and the matchmaker needs the party code back
local Matchmaker

local PartyMgr = {}

local function partyPayload(party)
    local members = {}
    for i = 1, #party.members do
        local uidv = party.members[i]
        local mpd = Players[uidv]
        if mpd then
            -- the card art and title a member bought are part of who they
            -- are on the roster, not just something they see on their own card
            Store.load(uidv)
            members[#members + 1] = {
                userId = uidv,
                name   = mpd.name,
                rank   = Rank.get(mpd.rankId).name,
                rankId = mpd.rankId,
                rp     = mpd.rp,
                leader = (uidv == party.leader),
                ready  = party.ready[uidv] == true,
                state  = mpd.state,
                cosmetics = Store.cosmetics(uidv)
            }
        end
    end
    local size = #party.members
    return {
        id = party.id, leader = party.leader, members = members,
        searching = party.searching,
        size = size,
        autoMode = Config.PartyQueue.autoMode and Matchmaker.modeForSize(size) or nil,
        lockToPartySize = Config.PartyQueue.lockToPartySize
    }
end

function PartyMgr.sync(party)
    if not party then return end

    -- the searched mode depends on the party size, so a size change while a
    -- search is running invalidates it
    if party.searching and party.lastSize and party.lastSize ~= #party.members then
        party.searching = false
        for i = 1, #party.members do
            if Matchmaker.leave(party.members[i]) then break end
        end
        notifyUser(party.leader, 'warning',
            'Party size changed — the search was cancelled.', 'QUEUE')
    end
    party.lastSize = #party.members

    local payload = partyPayload(party)
    for i = 1, #party.members do
        local s = srcOf(party.members[i])
        if s then TriggerClientEvent('m5rp:cl:party', s, payload) end
    end
end

function PartyMgr.get(userId)
    local pd = Players[userId]
    if not pd or not pd.partyId then return nil end
    return Parties[pd.partyId]
end

function PartyMgr.create(userId)
    local pd = Players[userId]
    if not pd then return nil end
    if pd.partyId then return Parties[pd.partyId] end

    local id = uid('P')
    local party = {
        id = id, leader = userId, members = { userId },
        ready = { [userId] = true }, searching = false, createdAt = now()
    }
    Parties[id] = party
    pd.partyId = id
    PartyMgr.sync(party)
    return party
end

function PartyMgr.disband(party, reason)
    if not party then return end
    for i = 1, #party.members do
        local mpd = Players[party.members[i]]
        if mpd then
            mpd.partyId = nil
            local s = srcOf(mpd.userId)
            if s then
                TriggerClientEvent('m5rp:cl:party', s, { id = nil, members = {} })
                if reason then notify(s, 'warning', reason, 'PARTY') end
            end
        end
    end
    Parties[party.id] = nil
end

function PartyMgr.leave(userId)
    local party = PartyMgr.get(userId)
    if not party then return false end
    local pd = Players[userId]

    for i = #party.members, 1, -1 do
        if party.members[i] == userId then table.remove(party.members, i) end
    end
    party.ready[userId] = nil
    if pd then pd.partyId = nil end

    local s = srcOf(userId)
    if s then TriggerClientEvent('m5rp:cl:party', s, { id = nil, members = {} }) end

    if #party.members == 0 then
        Parties[party.id] = nil
        return true
    end

    if party.leader == userId then
        if Config.Party.disbandOnLeaderLeave then
            PartyMgr.disband(party, 'The party leader left. Party disbanded.')
            return true
        end
        party.leader = party.members[1]
        notifyUser(party.leader, 'info', 'You are now the party leader.', 'PARTY')
    end

    party.searching = false
    PartyMgr.sync(party)
    return true
end

function PartyMgr.invite(fromId, targetId)
    local party = PartyMgr.get(fromId) or PartyMgr.create(fromId)
    if not party then return false, 'Party unavailable.' end
    if party.leader ~= fromId then return false, 'Only the leader can invite.' end
    if #party.members >= Config.Party.maxSize then return false, 'Party is full.' end

    local target = Players[targetId]
    if not target then return false, 'Player not found.' end
    if target.partyId then return false, 'That player is already in a party.' end
    if target.state ~= 'IDLE' then return false, 'That player is busy.' end
    if Bans.check(targetId, 'PARTY') then return false, 'That player cannot join parties.' end

    if Config.Party.rankGapEnabled then
        local leader = Players[fromId]
        if leader and leader.placementDone and target.placementDone then
            if math.abs(leader.rankId - target.rankId) > Config.Party.rankGap then
                return false, 'Rank difference is too large for a party.'
            end
        end
    end

    Invites[targetId] = { partyId = party.id, from = fromId, expires = now() + Config.Party.inviteTimeout }
    local s = srcOf(targetId)
    if s then
        TriggerClientEvent('m5rp:cl:party', s, {
            invite = { partyId = party.id, from = Players[fromId] and Players[fromId].name or '?', timeout = Config.Party.inviteTimeout }
        })
    end
    return true
end

function PartyMgr.accept(userId)
    local inv = Invites[userId]
    if not inv or inv.expires < now() then
        Invites[userId] = nil
        return false, 'Invitation expired.'
    end
    Invites[userId] = nil

    local party = Parties[inv.partyId]
    if not party then return false, 'Party no longer exists.' end
    if #party.members >= Config.Party.maxSize then return false, 'Party is full.' end

    local pd = Players[userId]
    if not pd or pd.partyId then return false, 'You are already in a party.' end

    party.members[#party.members + 1] = userId
    party.ready[userId] = false
    party.searching = false
    pd.partyId = party.id
    PartyMgr.sync(party)
    return true
end

function PartyMgr.decline(userId)
    local inv = Invites[userId]
    Invites[userId] = nil
    if inv then
        notifyUser(inv.from, 'info', 'Your party invitation was declined.', 'PARTY')
    end
    return true
end

function PartyMgr.kick(leaderId, targetId)
    local party = PartyMgr.get(leaderId)
    if not party or party.leader ~= leaderId then return false, 'Only the leader can kick.' end
    if targetId == leaderId then return false, 'You cannot kick yourself.' end
    if not inList(party.members, targetId) then return false, 'Not a party member.' end

    notifyUser(targetId, 'warning', 'You were removed from the party.', 'PARTY')
    PartyMgr.leave(targetId)
    return true
end

function PartyMgr.transfer(leaderId, targetId)
    local party = PartyMgr.get(leaderId)
    if not party or party.leader ~= leaderId then return false, 'Only the leader can transfer.' end
    if not inList(party.members, targetId) then return false, 'Not a party member.' end
    party.leader = targetId
    PartyMgr.sync(party)
    return true
end

function PartyMgr.setReady(userId, ready)
    local party = PartyMgr.get(userId)
    if not party then return false end
    party.ready[userId] = ready and true or false
    PartyMgr.sync(party)
    return true
end

function PartyMgr.allReady(party)
    if not Config.Party.requireReady then return true end
    for i = 1, #party.members do
        local uidv = party.members[i]
        if uidv ~= party.leader and not party.ready[uidv] then return false end
    end
    return true
end

-- ============================================================================
-- 11. QUEUE & MATCHMAKING
-- ============================================================================

local Queue        = {}   -- [mode] = { entry, ... }
local ReadyChecks  = {}   -- [id]   = readyCheck
local Avoid        = {}   -- [userId] = { [otherId] = expiry }
local RecentOpp    = {}   -- [userId] = { [otherId] = timestamp }

Matchmaker = {}           -- (forward declared above)

local function modeCfg(mode)
    local m = Config.Modes[mode]
    if m and m.enabled ~= false then return m end
    return nil
end

local function entryPing(entry)
    local worst = 0
    for i = 1, #entry.members do
        local s = srcOf(entry.members[i])
        if s then
            local p = GetPlayerPing(s) or 0
            if p > worst then worst = p end
        end
    end
    return worst
end

local function queueList(mode)
    Queue[mode] = Queue[mode] or {}
    return Queue[mode]
end

function Matchmaker.inQueue(userId)
    for mode, list in pairs(Queue) do
        for i = 1, #list do
            if inList(list[i].members, userId) then return mode, list[i] end
        end
    end
    return nil
end

--- Returns nil when the player may queue, or a reason string.
function Matchmaker.canQueue(pd, mode)
    if Config.Global.rankedFrozen then return Config.Global.frozenMessage end
    if not Config.Matchmaking.enabled then return 'Matchmaking is disabled.' end
    if pd.state ~= 'IDLE' then return 'You are already in a queue or a match.' end

    local cfg = modeCfg(mode)
    if not cfg then return 'Unknown game mode.' end
    if not inList(Config.RankedQueueModes, mode) then return 'This mode is not available in ranked.' end

    local ban = Bans.check(pd.userId, 'RANKED') or Bans.check(pd.userId, 'MODE', mode)
    if ban then
        return ban.expiry == 0
            and 'You are permanently banned from ranked.'
            or ('You are banned from ranked for %d more minutes.'):format(math.ceil((ban.expiry - now()) / 60))
    end

    local cd = Penalty.cooldownLeft(pd.userId)
    if cd > 0 then
        return ('Queue locked for %d more minutes.'):format(math.ceil(cd / 60))
    end

    if Config.Global.requirements.enabled then
        if pd.level < Config.Global.requirements.minLevel then
            return ('Level %d required.'):format(Config.Global.requirements.minLevel)
        end
        if pd.playtime < Config.Global.requirements.minPlaytime then
            return 'Not enough playtime to access ranked.'
        end
    end

    return nil
end

--- The mode a party of this size should default to (autoMode).
function Matchmaker.modeForSize(size)
    for i = 1, #Config.RankedQueueModes do
        local key = Config.RankedQueueModes[i]
        local cfg = modeCfg(key)
        if cfg and cfg.type ~= 'ffa' and cfg.teamSize == size then return key end
    end
    return nil
end

--- Validates the requested mode against the party size.
-- Returns list, errorMessage.
function Matchmaker.resolveModes(request, size)
    local P = Config.PartyQueue

    local cfg = modeCfg(request)
    if not cfg then return nil, 'Unknown game mode.' end
    if not inList(Config.RankedQueueModes, request) then
        return nil, 'This mode is not available in ranked.'
    end

    if cfg.type ~= 'ffa' then
        if size > cfg.teamSize then
            return nil, ('Your party is too large for %s.'):format(cfg.label)
        end
        if P.lockToPartySize and size ~= cfg.teamSize then
            local suggested = Matchmaker.modeForSize(size)
            return nil, suggested
                and ('A party of %d must search %s.'):format(size, (modeCfg(suggested) or {}).label or suggested)
                or  ('No ranked mode fits a party of %d.'):format(size)
        end
    end

    return { request }
end

function Matchmaker.join(userId, mode)
    local pd = Players[userId]
    if not pd then return false, 'Player data unavailable.' end

    local party  = PartyMgr.get(userId)
    local members = { userId }

    if party then
        if party.leader ~= userId then return false, 'Only the party leader can start the search.' end
        if not PartyMgr.allReady(party) then return false, 'All party members must be ready.' end
        members = copy(party.members)
    end

    local modes, modeErr = Matchmaker.resolveModes(mode, #members)
    if not modes then return false, modeErr end

    -- Every member must be allowed to queue for the first mode of the set
    for i = 1, #members do
        local mpd = Players[members[i]]
        if not mpd then return false, 'A party member is not loaded.' end
        local reason = Matchmaker.canQueue(mpd, modes[1])
        if reason then return false, _Lf('%s: %s', mpd.name, _L(reason)) end
    end

    -- Party rank gap check
    if party and Config.Matchmaking.partyRankGapEnabled and #members > 1 then
        local gapPool = Player.poolOf(modes[1])
        local lo, hi = 99, -1
        for i = 1, #members do
            local e = Player.poolData(Players[members[i]], gapPool)
            if e.placementDone then
                lo = math.min(lo, e.rankId)
                hi = math.max(hi, e.rankId)
            end
        end
        if hi >= 0 and (hi - lo) > Config.Matchmaking.maxPartyRankGap then
            return false, 'Party rank difference is too large for ranked.'
        end
    end

    -- A group can search several modes at once and each mode has its own
    -- ladder, so the entry is seeded from the first mode's pool. The RP that
    -- actually moves is applied against whichever mode the match lands in.
    local searchPool = Player.poolOf(modes[1])
    local totalMMR, totalRank = 0, 0
    for i = 1, #members do
        local e = Player.poolData(Players[members[i]], searchPool)
        totalMMR  = totalMMR + e.mmr
        totalRank = totalRank + e.rankId
    end

    -- One entry per searched mode, all sharing a group key so that filling any
    -- one of them cancels the rest.
    local groupKey = uid('G')
    local joinedAt, joinedMs = now(), ms()

    for i = 1, #modes do
        local entry = {
            key       = uid('Q'),
            mode      = modes[i],
            groupKey  = groupKey,
            groupModes= modes,
            request   = mode,
            members   = members,
            partyId   = party and party.id or nil,
            mmr       = math.floor(totalMMR / #members),
            rankId    = math.floor(totalRank / #members),
            joinedAt  = joinedAt,
            joinedMs  = joinedMs,
            range     = Config.Matchmaking.mmrRangeStart,
            rankRange = Config.Matchmaking.rankRangeStart
        }
        local list = queueList(modes[i])
        list[#list + 1] = entry
    end

    local label = (modeCfg(modes[1]) or {}).label or modes[1]

    for i = 1, #members do
        local mpd = Players[members[i]]
        mpd.state = 'QUEUE'
        local s = srcOf(members[i])
        if s then
            TriggerClientEvent('m5rp:cl:queue', s, {
                state = 'SEARCHING', mode = mode, modeLabel = label,
                modes = modes, startedAt = joinedAt
            })
        end
        hook('onQueueJoin', {
            userId = members[i], name = mpd.name, mode = mode, partySize = #members
        })
    end

    if party then
        party.searching = true
        PartyMgr.sync(party)
    end

    dbg('queue join: group %s (%d members) modes=%s', groupKey, #members, table.concat(modes, ','))
    return true
end

function Matchmaker.leave(userId, silent)
    local _, entry = Matchmaker.inQueue(userId)
    if not entry then return false end

    -- a random search sits in several queues at once: clear every sibling
    for _, list in pairs(Queue) do
        for i = #list, 1, -1 do
            if list[i].key == entry.key
               or (entry.groupKey and list[i].groupKey == entry.groupKey) then
                table.remove(list, i)
            end
        end
    end

    for i = 1, #entry.members do
        local mpd = Players[entry.members[i]]
        if mpd and mpd.state == 'QUEUE' then mpd.state = 'IDLE' end
        local s = srcOf(entry.members[i])
        if s and not silent then
            TriggerClientEvent('m5rp:cl:queue', s, { state = 'IDLE' })
        end
        hook('onQueueLeave', {
            userId = entry.members[i], name = mpd and mpd.name or '?',
            mode = entry.mode, partySize = #entry.members
        })
    end

    if entry.partyId and Parties[entry.partyId] then
        Parties[entry.partyId].searching = false
        PartyMgr.sync(Parties[entry.partyId])
    end
    return true
end

--- Number of players currently searching (all modes) — displayed in the UI.
function Matchmaker.searchingCount(mode)
    local n, seen = 0, {}
    for m, list in pairs(Queue) do
        if not mode or m == mode then
            for i = 1, #list do
                local gk = list[i].groupKey or list[i].key
                if mode or not seen[gk] then
                    seen[gk] = true
                    n = n + #list[i].members
                end
            end
        end
    end
    return n
end

local function avoidBlocked(aId, bId)
    local a = Avoid[aId]
    if a and a[bId] and a[bId] > now() then return true end
    local b = Avoid[bId]
    if b and b[aId] and b[aId] > now() then return true end
    return false
end

local function entriesCompatible(a, b)
    local range = math.max(a.range, b.range)
    if math.abs(a.mmr - b.mmr) > range then return false end

    local rankRange = math.max(a.rankRange, b.rankRange)
    if math.abs(a.rankId - b.rankId) > rankRange then return false end

    -- ping preference relaxes after a while
    local maxPing = Config.Matchmaking.maxPing
    if maxPing > 0 then
        local waited = math.max(ms() - a.joinedMs, ms() - b.joinedMs)
        if waited > Config.Matchmaking.pingRelaxAfter then
            maxPing = Config.Matchmaking.pingRangeMax
        end
        if entryPing(a) > maxPing or entryPing(b) > maxPing then return false end
    end

    for i = 1, #a.members do
        for j = 1, #b.members do
            if avoidBlocked(a.members[i], b.members[j]) then return false end
        end
    end
    return true
end

--- Attempts to build a full lobby. Entries are tried oldest first, and a seed
--- that cannot be satisfied is skipped rather than blocking the whole queue.
local function tryBuildLobby(mode, cfg)
    local list = queueList(mode)
    if #list == 0 then return nil end

    table.sort(list, function(x, y) return x.joinedMs < y.joinedMs end)

    -- ---- free for all ---------------------------------------------------
    if cfg.type == 'ffa' then
        local minP = cfg.minPlayers or 4
        local maxP = cfg.maxPlayers or 12
        local seed = list[1]
        local picked, total = { seed }, #seed.members
        for i = 2, #list do
            if total >= maxP then break end
            local e = list[i]
            if entriesCompatible(seed, e) and (total + #e.members) <= maxP then
                picked[#picked + 1] = e
                total = total + #e.members
            end
        end
        if total < minP then return nil end
        return { entries = picked, teams = nil, ffa = true }
    end

    -- ---- team matching rules --------------------------------------------
    -- 'fullTeam': a complete party only ever faces another complete party, so
    -- a duo searching 2V2 waits for a second duo instead of being handed two
    -- solo players. A party that has waited past fallbackAfter is released
    -- back into the normal pool so nobody waits forever.
    local need = cfg.teamSize
    local TM = (Config.PartyQueue or {}).teamMatching or {}
    local fullTeamOnly = TM.mode == 'fullTeam'

    local function isFullTeam(e) return #e.members == need end
    local function relaxed(e)
        local after = TM.fallbackAfter or 0
        return after > 0 and ((ms() - e.joinedMs) / 1000) >= after
    end
    local function reserved(e)
        return fullTeamOnly and isFullTeam(e) and not relaxed(e)
    end

    -- Try every entry as a seed. A reserved party with no mirror yet simply
    -- keeps waiting while the rest of the queue continues to match.
    for si = 1, #list do
        local seed = list[si]

        if reserved(seed) then
            -- complete party: look for its mirror only
            for i = 1, #list do
                local e = list[i]
                if e.key ~= seed.key and isFullTeam(e) and entriesCompatible(seed, e) then
                    return { entries = nil, teams = { { seed }, { e } }, ffa = false }
                end
            end
        else
            local teamA, teamB = {}, {}
            local sizeA, sizeB = 0, 0
            local used = {}

            local function place(entry)
                local n = #entry.members
                if sizeA <= sizeB and (sizeA + n) <= need then
                    teamA[#teamA + 1] = entry; sizeA = sizeA + n; return true
                elseif (sizeB + n) <= need then
                    teamB[#teamB + 1] = entry; sizeB = sizeB + n; return true
                elseif (sizeA + n) <= need then
                    teamA[#teamA + 1] = entry; sizeA = sizeA + n; return true
                end
                return false
            end

            place(seed)
            used[seed.key] = true

            for i = 1, #list do
                if sizeA == need and sizeB == need then break end
                local e = list[i]

                if not used[e.key] and not reserved(e) and entriesCompatible(seed, e) then
                    local okWithAll = true
                    for _, other in ipairs(teamA) do
                        if not entriesCompatible(other, e) then okWithAll = false break end
                    end
                    if okWithAll then
                        for _, other in ipairs(teamB) do
                            if not entriesCompatible(other, e) then okWithAll = false break end
                        end
                    end
                    if okWithAll and place(e) then used[e.key] = true end
                end
            end

            if sizeA == need and sizeB == need then
                return { entries = nil, teams = { teamA, teamB }, ffa = false }
            end
        end
    end

    return nil
end

--- Removes the given entries — and every sibling entry of the same search —
--- from every queue they sit in.
local function removeEntries(mode, entries)
    local keys, groups = {}, {}
    for i = 1, #entries do
        keys[entries[i].key] = true
        if entries[i].groupKey then groups[entries[i].groupKey] = true end
    end

    for _, list in pairs(Queue) do
        for i = #list, 1, -1 do
            if keys[list[i].key] or (list[i].groupKey and groups[list[i].groupKey]) then
                table.remove(list, i)
            end
        end
    end
end

-- forward declaration, defined by the match engine
local Match

local function startReadyCheck(mode, cfg, lobby)
    local id = uid('R')
    local entries, teamOf = {}, {}

    if lobby.ffa then
        for i = 1, #lobby.entries do
            entries[#entries + 1] = lobby.entries[i]
            for _, u in ipairs(lobby.entries[i].members) do teamOf[u] = i end
        end
    else
        for t = 1, 2 do
            for _, e in ipairs(lobby.teams[t]) do
                entries[#entries + 1] = e
                for _, u in ipairs(e.members) do teamOf[u] = t end
            end
        end
    end

    removeEntries(mode, entries)

    local users, list = {}, {}
    for i = 1, #entries do
        for _, u in ipairs(entries[i].members) do
            users[u] = false
            list[#list + 1] = u
            local mpd = Players[u]
            if mpd then mpd.state = 'READY' end
        end
    end

    local rc = {
        id = id, mode = mode, cfg = cfg, entries = entries,
        users = users, list = list, teamOf = teamOf,
        ffa = lobby.ffa == true,
        expires = ms() + (Config.Matchmaking.readyCheck.duration * 1000),
        accepted = 0
    }
    ReadyChecks[id] = rc

    if not Config.Matchmaking.readyCheck.enabled then
        Match.createFromReady(rc)
        ReadyChecks[id] = nil
        return
    end

    for i = 1, #list do
        local s = srcOf(list[i])
        if s then
            TriggerClientEvent('m5rp:cl:matchFound', s, {
                id = id, mode = mode, modeLabel = cfg.label,
                total = #list, accepted = 0,
                timeout = Config.Matchmaking.readyCheck.duration
            })
        end
    end
    dbg('ready check %s created for %d players (%s)', id, #list, mode)
end

function Matchmaker.accept(userId, checkId)
    local rc = ReadyChecks[checkId]
    if not rc then return false end
    if rc.users[userId] == nil then return false end
    if rc.users[userId] then return true end

    rc.users[userId] = true
    rc.accepted = rc.accepted + 1

    for i = 1, #rc.list do
        local s = srcOf(rc.list[i])
        if s then
            TriggerClientEvent('m5rp:cl:matchFound', s, {
                id = rc.id, mode = rc.mode, modeLabel = rc.cfg.label,
                total = #rc.list, accepted = rc.accepted,
                timeout = math.max(0, math.floor((rc.expires - ms()) / 1000)),
                accepted_self = rc.users[rc.list[i]] == true
            })
        end
    end

    if rc.accepted >= #rc.list then
        ReadyChecks[rc.id] = nil
        Match.createFromReady(rc)
    end
    return true
end

--- Handles a ready check that timed out or was declined.
local function failReadyCheck(rc, declinedBy)
    ReadyChecks[rc.id] = nil

    local requeue = Config.Matchmaking.readyCheck.requeueOnFail
    for i = 1, #rc.entries do
        local entry = rc.entries[i]
        local entryOk = true
        for _, u in ipairs(entry.members) do
            if not rc.users[u] then entryOk = false end
        end

        for _, u in ipairs(entry.members) do
            local mpd = Players[u]
            if mpd and mpd.state == 'READY' then mpd.state = 'IDLE' end
            local s = srcOf(u)
            if s then
                TriggerClientEvent('m5rp:cl:matchFound', s, { cancel = true })
                if entryOk then
                    notify(s, 'warning', 'A player failed to accept. You were placed back in the queue.', 'MATCH CANCELLED')
                else
                    notify(s, 'error', 'You did not accept the match.', 'MATCH CANCELLED')
                end
            end
            if not rc.users[u] then
                Penalty.setCooldown(u, Config.Matchmaking.readyCheck.declineCooldown)
            end
        end

        if requeue and entryOk then
            -- put the entry back with its original queue time so it keeps
            -- priority, restoring every mode a random search covered
            local restore = entry.groupModes or { rc.mode }
            for _, m in ipairs(restore) do
                local clone = copy(entry)
                clone.key  = uid('Q')
                clone.mode = m
                queueList(m)[#queueList(m) + 1] = clone
            end

            for _, u in ipairs(entry.members) do
                local mpd = Players[u]
                if mpd then mpd.state = 'QUEUE' end
                local s = srcOf(u)
                if s then
                    TriggerClientEvent('m5rp:cl:queue', s, {
                        state = 'SEARCHING', mode = rc.mode, modeLabel = rc.cfg.label,
                        startedAt = entry.joinedAt
                    })
                end
            end
        end
    end
    dbg('ready check %s failed%s', rc.id, declinedBy and (' (declined by ' .. declinedBy .. ')') or ' (timeout)')
end

function Matchmaker.decline(userId, checkId)
    local rc = ReadyChecks[checkId]
    if not rc or rc.users[userId] == nil then return false end
    rc.users[userId] = false
    failReadyCheck(rc, userId)
    return true
end

--- Main matchmaking pass, called from the master loop.
function Matchmaker.tick()
    -- expand search windows and drop stale entries
    local t = ms()
    for mode, list in pairs(Queue) do
        for i = #list, 1, -1 do
            local e = list[i]
            local waited = t - e.joinedMs

            local steps = math.floor(waited / Config.Matchmaking.expandInterval)
            e.range     = math.min(Config.Matchmaking.mmrRangeStart + steps * Config.Matchmaking.mmrRangeStep,
                                   Config.Matchmaking.mmrRangeMax)
            e.rankRange = math.min(Config.Matchmaking.rankRangeStart + steps * Config.Matchmaking.rankRangeStep,
                                   Config.Matchmaking.rankRangeMax)

            if waited > (Config.Matchmaking.maxQueueTime * 1000) then
                for _, u in ipairs(e.members) do
                    local mpd = Players[u]
                    if mpd then mpd.state = 'IDLE' end
                    local s = srcOf(u)
                    if s then
                        TriggerClientEvent('m5rp:cl:queue', s, { state = 'IDLE' })
                        notify(s, 'warning', 'No match was found. Please try again.', 'QUEUE TIMEOUT')
                    end
                end
                table.remove(list, i)
            end
        end
    end

    -- ready check expiry
    for id, rc in pairs(ReadyChecks) do
        if ms() >= rc.expires then failReadyCheck(rc, nil) end
    end

    -- try to build lobbies
    for mode, list in pairs(Queue) do
        if #list > 0 then
            local cfg = modeCfg(mode)
            if cfg then
                local guard = 0
                repeat
                    local lobby = tryBuildLobby(mode, cfg)
                    if lobby then
                        startReadyCheck(mode, cfg, lobby)
                    end
                    guard = guard + 1
                until not lobby or guard > 4
            end
        end
    end

    -- push queue timers to searching players (once per group, not per mode)
    local total = Matchmaker.searchingCount()
    local pushed = {}
    for _, list in pairs(Queue) do
        for i = 1, #list do
            local e = list[i]
            local gk = e.groupKey or e.key
            if not pushed[gk] then
                pushed[gk] = true
                for _, u in ipairs(e.members) do
                    local s = srcOf(u)
                    if s then
                        TriggerClientEvent('m5rp:cl:queue', s, {
                            state = 'SEARCHING',
                            mode = e.request or e.mode,
                            modes = e.groupModes,
                            elapsed = math.floor((ms() - e.joinedMs) / 1000),
                            searching = total,
                            estimate = math.max(10, 30 + math.floor(e.range / 12))
                        })
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 12. MATCH ENGINE
-- ============================================================================

local Matches       = {}   -- [matchId] = match
local UsedBuckets   = {}   -- [bucket]  = matchId
local Reconnects    = {}   -- [userId]  = { matchId, expires, team }

Match = {}                 -- (forward declared above)

local MapById = {}
for i = 1, #Config.Maps do MapById[Config.Maps[i].id] = Config.Maps[i] end

local function mapsForMode(mode)
    local out = {}
    for i = 1, #Config.Maps do
        local m = Config.Maps[i]
        if not m.modes or inList(m.modes, mode) then out[#out + 1] = m end
    end
    return out
end

local function allocBucket(custom)
    local from = custom and Config.Buckets.customStart or Config.Buckets.start
    local to   = custom and Config.Buckets.customMax   or Config.Buckets.max
    for b = from, to do
        if not UsedBuckets[b] then return b end
    end
    return nil
end

local function configureBucket(bucket)
    SetRoutingBucketPopulationEnabled(bucket, Config.Buckets.populationEnabled == true)
    SetRoutingBucketEntityLockdownMode(bucket, Config.Buckets.lockdownMode or 'strict')
end

local PresetById = {}
for i = 1, #Config.WeaponPresets do
    PresetById[Config.WeaponPresets[i].id] = Config.WeaponPresets[i]
end

--- Resolves the weapon list a room selected in the custom match UI.
local function presetWeapons(ids)
    local out = {}
    for i = 1, #(ids or {}) do
        local preset = PresetById[ids[i]]
        if preset and Security.weaponAllowed(preset.weapon) then
            out[#out + 1] = { name = preset.weapon, ammo = preset.ammo }
        end
    end
    return out
end

function Match.loadoutFor(m, userId)
    local base = Config.Loadouts[m.settings.loadout] or Config.Loadouts.standard

    -- a custom room with an explicit weapon selection overrides the preset
    local weapons = presetWeapons(m.settings.weapons)
    if #weapons == 0 then
        for i = 1, #base.weapons do
            local w = base.weapons[i]
            if Security.weaponAllowed(w.name) then
                weapons[#weapons + 1] = { name = w.name, ammo = w.ammo }
            end
        end
    end

    local mp = m.players[userId]

    if m.settings.matchType == 'random' and #weapons > 1 then
        -- one random weapon from the selection, rerolled every round
        weapons = { weapons[((m.round + (userId % 7)) % #weapons) + 1] }

    elseif m.settings.matchType == 'gungame' and mp then
        local level = math.min((mp.gunLevel or 0) + 1, #weapons)
        weapons = { weapons[level] }
    end

    local armor = m.settings.armor or base.armor or 0
    if m.settings.armorEnabled == false then armor = 0 end

    return {
        health  = m.settings.health or base.health or 100,
        armor   = armor,
        weapons = weapons
    }
end

local function loadoutFor(m, userId)
    return Match.loadoutFor(m, userId)
end

local function spawnPointFor(m, mp, index)
    local map = m.map
    local list
    if m.ffa then
        list = {}
        for i = 1, #map.teamA do list[#list + 1] = map.teamA[i] end
        for i = 1, #map.teamB do list[#list + 1] = map.teamB[i] end
    else
        list = (mp.team == 1) and map.teamA or map.teamB
    end
    if #list == 0 then
        return { x = map.center.x, y = map.center.y, z = map.center.z, h = 0.0 }
    end
    local v = list[((index - 1) % #list) + 1]
    return { x = v.x, y = v.y, z = v.z, h = v.w }
end

function Match.get(matchId) return Matches[matchId] end

function Match.broadcast(m, event, payload)
    for userId in pairs(m.players) do
        local s = srcOf(userId)
        if s then TriggerClientEvent(event, s, payload) end
    end
end

function Match.broadcastTeam(m, team, event, payload)
    for userId, mp in pairs(m.players) do
        if mp.team == team then
            local s = srcOf(userId)
            if s then TriggerClientEvent(event, s, payload) end
        end
    end
end

function Match.setState(m, state, seconds)
    m.state    = state
    m.stateEnd = seconds and (ms() + seconds * 1000) or nil
    dbg('match %s -> %s (%s)', m.id, state, seconds and (seconds .. 's') or 'open')
end

local function teamPlayers(m, team)
    local out = {}
    for userId, mp in pairs(m.players) do
        if mp.team == team then out[#out + 1] = mp end
    end
    return out
end

local function aliveCount(m, team)
    local n = 0
    for _, mp in pairs(m.players) do
        if mp.alive and mp.connected and (not team or mp.team == team) then n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- Avatars
--
-- Resolved server side and handed to the UI as a plain URL. The Discord bot
-- token never leaves Config_Server.lua; the client only ever sees the picture
-- address, and a default one whenever anything is missing or fails.
-- ---------------------------------------------------------------------------

local AvatarCache = {}   -- [userId] = { url = string, at = timestamp }

local function defaultAvatar()
    return Config.Avatars.default or ''
end

--- The bare discord id out of a "discord:123456789" identifier.
local function discordIdOf(pd)
    if not pd or type(pd.discord) ~= 'string' or pd.discord == '' then return nil end
    return pd.discord:match('(%d+)$')
end

--- Asks Discord for a user's avatar hash once, then caches the built URL.
--- Runs in its own thread: the HTTP call must never hold up a match tick.
local function fetchDiscordAvatar(userId, discordId)
    local cfg = Config.Avatars.discord
    if not cfg or cfg.botToken == '' then return end

    PerformHttpRequest('https://discord.com/api/v10/users/' .. discordId,
        function(status, body)
            local url = defaultAvatar()
            if status == 200 and body then
                local ok, data = pcall(json.decode, body)
                if ok and type(data) == 'table' and data.avatar then
                    local ext = tostring(data.avatar):sub(1, 2) == 'a_' and 'gif' or 'png'
                    url = ('https://cdn.discordapp.com/avatars/%s/%s.%s?size=%d')
                        :format(discordId, data.avatar, ext, cfg.size or 128)
                elseif ok and type(data) == 'table' then
                    -- no custom avatar: Discord's own default for that account
                    local n = tonumber(data.discriminator or 0) or 0
                    url = ('https://cdn.discordapp.com/embed/avatars/%d.png'):format(n % 5)
                end
            elseif status == 401 then
                err('discord avatar lookup rejected the bot token (401) — check Config.Avatars.discord.botToken')
            elseif status == 429 then
                dbg('discord avatar lookup rate limited for %s', discordId)
            end
            AvatarCache[userId] = { url = url, at = now() }
        end, 'GET', '', { Authorization = 'Bot ' .. cfg.botToken })
end

--- The picture for a player. Always returns something usable immediately; a
--- Discord lookup fills the cache in the background for the next push.
local function avatarFor(userId)
    if not Config.Avatars.enabled then return nil end

    local cached = AvatarCache[userId]
    local ttl    = (Config.Avatars.discord and Config.Avatars.discord.cacheTime) or 21600
    if cached and (now() - cached.at) < ttl then return cached.url end

    local pd = Players[userId]
    local discordId = discordIdOf(pd)
    local source = Config.Avatars.source or 'none'

    if source == 'template' and discordId and Config.Avatars.template then
        local url = Config.Avatars.template:format(discordId)
        AvatarCache[userId] = { url = url, at = now() }
        return url
    end

    if source == 'discord' and discordId then
        -- serve the default now, swap it in once Discord answers
        if not cached then
            AvatarCache[userId] = { url = defaultAvatar(), at = 0 }
            Citizen.CreateThread(function() fetchDiscordAvatar(userId, discordId) end)
        end
        return (AvatarCache[userId] or {}).url or defaultAvatar()
    end

    AvatarCache[userId] = { url = defaultAvatar(), at = now() }
    return defaultAvatar()
end

-- ---------------------------------------------------------------------------
-- Team names
-- ---------------------------------------------------------------------------

--- Names one side of a match. With 'leader' the side is named after the party
--- leader that queued it, or its highest ranked player when there is no party.
local function teamNameFor(m, team)
    local cfg = Config.TeamNames or {}
    local fixed = (cfg.fixed and cfg.fixed[team]) or (team == 2 and 'TEAM B' or 'TEAM A')
    if cfg.mode ~= 'leader' then return fixed end

    local members = teamPlayers(m, team)
    if #members == 0 then return fixed end

    local pick
    if cfg.pick == 'party' then
        for i = 1, #members do
            local pd = Players[members[i].userId]
            if pd and pd.partyId and Parties[pd.partyId]
               and Parties[pd.partyId].leader == members[i].userId then
                pick = members[i]
                break
            end
        end
    end
    if not pick then
        for i = 1, #members do
            if not pick or (members[i].rankId or 0) > (pick.rankId or 0) then pick = members[i] end
        end
    end
    if not pick then return fixed end

    if #members == 1 and cfg.soloIsPlain ~= false then return pick.name end
    return (cfg.pattern or "%s'S TEAM"):format(pick.name)
end

local function playerListPayload(m)
    local out = {}
    for userId, mp in pairs(m.players) do
        out[#out + 1] = {
            userId = userId, serverId = srcOf(userId),
            name = mp.name, team = mp.team,
            alive = mp.alive, connected = mp.connected,
            kills = mp.kills, deaths = mp.deaths, assists = mp.assists,
            headshots = mp.headshots, damage = math.floor(mp.damage),
            score = mp.score, rank = mp.rankName, rankId = mp.rankId,
            avatar = avatarFor(userId),
            ping = srcOf(userId) and (GetPlayerPing(srcOf(userId)) or 0) or 0
        }
    end
    table.sort(out, function(a, b)
        if a.team ~= b.team then return a.team < b.team end
        return a.score > b.score
    end)
    return out
end

--- Creates a match object. Shared by ranked matchmaking and custom games.
-- @param opts { mode, ranked, customId, settings, bucket, players = { {userId, team} } }
function Match.create(opts)
    local cfg = modeCfg(opts.mode)
    if not cfg then return nil, 'invalid mode' end

    local bucket = opts.bucket or allocBucket(opts.customId ~= nil)
    if not bucket then return nil, 'no free routing bucket' end

    local settings = {
        rounds        = opts.settings and opts.settings.rounds        or cfg.rounds,
        roundsToWin   = opts.settings and opts.settings.roundsToWin   or cfg.roundsToWin,
        roundTime     = opts.settings and opts.settings.roundTime     or cfg.roundTime,
        matchTime     = opts.settings and opts.settings.matchTime     or cfg.matchTime,
        killLimit     = opts.settings and opts.settings.killLimit     or cfg.killLimit or 0,
        friendlyFire  = opts.settings and opts.settings.friendlyFire  or cfg.friendlyFire or false,
        respawn       = opts.settings and opts.settings.respawn ~= nil and opts.settings.respawn or cfg.respawn,
        respawnTime   = opts.settings and opts.settings.respawnTime   or cfg.respawnTime or 4,
        lives         = opts.settings and opts.settings.lives         or cfg.lives or 1,
        health        = opts.settings and opts.settings.health        or nil,
        armor         = opts.settings and opts.settings.armor         or nil,
        movement      = opts.settings and opts.settings.movement      or 1.0,
        jump          = opts.settings and opts.settings.jump ~= false,
        minimap       = opts.settings and opts.settings.minimap       or false,
        vehicles      = opts.settings and opts.settings.vehicles      or false,
        killcam       = opts.settings and opts.settings.killcam       or false,
        overtime      = opts.settings and opts.settings.overtime ~= nil and opts.settings.overtime or cfg.overtime,
        suddenDeath   = opts.settings and opts.settings.suddenDeath ~= nil and opts.settings.suddenDeath or cfg.suddenDeath,
        headshotOneShot = opts.settings and opts.settings.headshotOneShot ~= false,
        headshotOnly  = opts.settings and opts.settings.headshotOnly == true,
        matchType     = opts.settings and opts.settings.matchType or 'normal',
        weapons       = opts.settings and opts.settings.weapons or nil,
        armorEnabled  = opts.settings and opts.settings.armorEnabled,
        loadout       = opts.settings and opts.settings.loadout       or cfg.loadout or 'standard',
        spectators    = opts.settings and opts.settings.spectators ~= false
    }

    local m = {
        id        = uid('M'),
        suddenDeath = false,
        dbId      = nil,
        mode      = opts.mode,
        cfg       = cfg,
        ranked    = opts.ranked == true,
        customId  = opts.customId,
        customDbId = opts.customDbId,
        settings  = settings,
        ffa       = cfg.type == 'ffa',
        bucket    = bucket,
        state     = 'WAITING',
        stateEnd  = nil,
        round     = 0,
        scores    = { [1] = 0, [2] = 0 },
        players   = {},
        map       = nil,
        mapOptions= {},
        mapVotes  = {},
        createdAt = now(),
        startedAt = nil,
        endedAt   = nil,
        overtimeCount = 0,
        roundStartMs  = 0,
        roundLog  = {},
        killLog   = {},
        firstBloodTaken = false,
        surrender = nil,
        lastHudPush = 0,
        forfeitTimer = {}
    }

    UsedBuckets[bucket] = m.id
    configureBucket(bucket)
    Matches[m.id] = m

    if opts.players then
        for i = 1, #opts.players do
            Match.addPlayer(m, opts.players[i].userId, opts.players[i].team)
        end
    end

    return m
end

function Match.addPlayer(m, userId, team)
    local pd = Players[userId]
    if not pd then return false end

    -- From here until the results are applied, this player's rank, RP and MMR
    -- are the ones belonging to this match's mode. Everything downstream —
    -- the pre-match snapshot below, RP.apply, the MMR update, the result
    -- payload — reads the flat fields and so lands on the right ladder.
    Player.useMode(pd, m.mode)

    m.players[userId] = {
        userId    = userId,
        name      = pd.name,
        team      = team or 1,
        rankName  = Rank.get(pd.rankId).name,
        rankId    = pd.rankId,
        alive     = false,
        connected = true,
        lives     = m.settings.lives,

        kills = 0, deaths = 0, assists = 0, headshots = 0,
        damage = 0, score = 0, clutches = 0, firstBloods = 0, roundsWon = 0,
        killStreak = 0, bestKillStreak = 0, gunLevel = 0,
        multiKill = { n = 0, ts = 0 },
        lastKiller = nil,
        nemesis = {},
        weapons = {},
        damageTaken = {},

        rpBefore   = pd.rp,
        mmrBefore  = pd.mmr,
        rankBefore = pd.rankId,

        leftEarly = false,
        afk       = false,
        afkWarned = false,
        lastActivity = ms(),
        spawnProtectUntil = 0,
        deadAt = 0,
        reconnects = 0
    }

    pd.state   = m.customId and 'CUSTOM' or 'MATCH'
    pd.matchId = m.id
    pd.team    = team or 1

    hook('onMatchJoin', {
        userId = userId, source = srcOf(userId), name = pd.name,
        matchId = m.id, mode = m.mode, ranked = m.ranked,
        custom = m.customId ~= nil, practice = false,
        team = pd.team, rankId = pd.rankId, rank = Rank.get(pd.rankId).name,
        rp = pd.rp, mmr = pd.mmr
    })
    return true
end

--- Puts one player into the match bucket and sends the setup payload.
function Match.deploy(m, userId)
    local s = srcOf(userId)
    local mp = m.players[userId]
    if not s or not mp then return end

    SetPlayerRoutingBucket(s, m.bucket)

    local roster = {}
    for uidv, other in pairs(m.players) do
        roster[#roster + 1] = {
            userId = uidv, name = other.name, team = other.team, rank = other.rankName,
            avatar = avatarFor(uidv)
        }
    end

    TriggerClientEvent('m5rp:cl:setup', s, {
        matchId   = m.id,
        mode      = m.mode,
        modeLabel = m.cfg.label,
        modeType  = m.cfg.type,
        ranked    = m.ranked,
        custom    = m.customId ~= nil,
        ffa       = m.ffa,
        team      = mp.team,
        teamNames = { [1] = teamNameFor(m, 1), [2] = teamNameFor(m, 2) },
        map = m.map and {
            id     = m.map.id,
            name   = m.map.name,
            image  = m.map.image,
            center = { x = m.map.center.x, y = m.map.center.y, z = m.map.center.z },
            radius = m.map.radius,
            height = m.map.height
        } or nil,
        roster   = roster,
        settings = {
            friendlyFire    = m.settings.friendlyFire,
            minimap         = m.settings.minimap,
            movement        = m.settings.movement,
            jump            = m.settings.jump,
            headshotOneShot = m.settings.headshotOneShot and Config.Headshot.oneShotKill,
            headshotOnly    = m.settings.headshotOnly,
            matchType       = m.settings.matchType,
            respawn         = m.settings.respawn,
            spawnProtection = Config.Match.spawnProtection,
            roundsToWin     = m.settings.roundsToWin,
            killLimit       = m.settings.killLimit,
            boundaryWarning = Config.Match.boundary.warningTime
        }
    })
end

--- Builds a match from a completed ready check.
function Match.createFromReady(rc)
    local players = {}
    for i = 1, #rc.list do
        local userId = rc.list[i]
        local team   = rc.ffa and 1 or rc.teamOf[userId]
        players[#players + 1] = { userId = userId, team = team }
    end

    local m, reason = Match.create({
        mode = rc.mode, ranked = true, players = players
    })
    if not m then
        err('failed to create match: %s', tostring(reason))
        for i = 1, #rc.list do
            local mpd = Players[rc.list[i]]
            if mpd then mpd.state = 'IDLE' end
            local s = srcOf(rc.list[i])
            if s then
                TriggerClientEvent('m5rp:cl:matchFound', s, { cancel = true })
                notify(s, 'error', 'The match could not be created. Please queue again.', 'ERROR')
            end
        end
        return
    end

    if m.ffa then
        local i = 0
        for userId, mp in pairs(m.players) do
            i = i + 1
            mp.team = i
        end
    end

    -- record opponents for the anti boost analyser
    for a in pairs(m.players) do
        RecentOpp[a] = RecentOpp[a] or {}
        for b in pairs(m.players) do
            if a ~= b then RecentOpp[a][b] = now() end
        end
    end

    Match.startMapVote(m)

    Logger.send('matchStart', 'Ranked Match Started',
        ('**%s** • Map vote started • `%s`'):format(m.cfg.label, m.id), nil, {
            { name = 'Players', value = tostring(count(m.players)), inline = true },
            { name = 'Bucket', value = tostring(m.bucket), inline = true }
        })
end

-- ---------------------------------------------------------------------------
-- Map vote
-- ---------------------------------------------------------------------------

function Match.startMapVote(m)
    -- close the accept popup for everyone before anything else happens
    Match.broadcast(m, 'm5rp:cl:matchFound', { done = true })

    local pool = mapsForMode(m.mode)
    if #pool == 0 then
        err('no map supports mode %s', m.mode)
        Match.abort(m, 'NO_MAP')
        return
    end

    if not Config.MapVote.enabled or #pool == 1 then
        m.map = pool[math.random(#pool)]
        Match.beginSetup(m)
        return
    end

    shuffle(pool)
    m.mapOptions = {}
    for i = 1, math.min(Config.MapVote.options, #pool) do
        m.mapOptions[#m.mapOptions + 1] = pool[i]
    end
    m.mapVotes = {}

    Match.setState(m, 'MAP_VOTE', Config.MapVote.duration)

    local options = {}
    for i = 1, #m.mapOptions do
        options[#options + 1] = {
            id = m.mapOptions[i].id, name = m.mapOptions[i].name, image = m.mapOptions[i].image
        }
    end

    for userId in pairs(m.players) do
        local s = srcOf(userId)
        if s then
            TriggerClientEvent('m5rp:cl:mapVote', s, {
                matchId = m.id, options = options,
                duration = Config.MapVote.duration, votes = {}
            })
        end
    end
end

function Match.vote(m, userId, mapId)
    if m.state ~= 'MAP_VOTE' then return false end
    if not m.players[userId] then return false end
    local valid = false
    for i = 1, #m.mapOptions do
        if m.mapOptions[i].id == mapId then valid = true break end
    end
    if not valid then return false end

    m.mapVotes[userId] = mapId

    local tally = {}
    for _, id in pairs(m.mapVotes) do tally[id] = (tally[id] or 0) + 1 end
    Match.broadcast(m, 'm5rp:cl:mapVote', { matchId = m.id, votes = tally, update = true })
    return true
end

function Match.resolveMapVote(m)
    local tally, best, bestN = {}, nil, -1
    for _, id in pairs(m.mapVotes) do tally[id] = (tally[id] or 0) + 1 end

    local tied = {}
    for id, n in pairs(tally) do
        if n > bestN then bestN, best, tied = n, id, { id }
        elseif n == bestN then tied[#tied + 1] = id end
    end

    local chosenId
    if #tied > 1 then
        chosenId = tied[math.random(#tied)]
    else
        chosenId = best
    end

    if not chosenId then
        chosenId = m.mapOptions[math.random(#m.mapOptions)].id
    end

    m.map = MapById[chosenId] or m.mapOptions[1]
    Match.broadcast(m, 'm5rp:cl:mapVote', { matchId = m.id, result = m.map.id, close = true })
    Match.beginSetup(m)
end

-- ---------------------------------------------------------------------------
-- Setup / rounds
-- ---------------------------------------------------------------------------

function Match.beginSetup(m)
    Match.setState(m, 'STARTING', Config.Match.warmupTime)
    m.startedAt = now()

    for userId in pairs(m.players) do
        Match.deploy(m, userId)
    end

    -- persist the match row early so kills can reference it
    m.dbId = DB.insert([[INSERT INTO m5_matches
        (match_uid, season_id, mode, map_id, ranked, custom_id, state, bucket, started_at)
        VALUES (?, ?, ?, ?, ?, ?, 'STARTING', ?, ?)]],
        { m.id, Season.id(), m.mode, m.map and m.map.id or '', m.ranked and 1 or 0,
          m.customDbId or 0, m.bucket, sqlDate(m.startedAt) })

    Match.spawnAll(m, false)
    Match.pushHud(m, true)
end

function Match.spawnAll(m, respawnOnly)
    local index = { [1] = 0, [2] = 0 }
    local ffaIndex = 0

    for userId, mp in pairs(m.players) do
        if mp.connected and (not respawnOnly or not mp.alive) then
            local idx
            if m.ffa then
                ffaIndex = ffaIndex + 1
                idx = ffaIndex
            else
                local t = mp.team == 2 and 2 or 1
                index[t] = index[t] + 1
                idx = index[t]
            end

            mp.alive  = true
            mp.deadAt = 0
            mp.spawnProtectUntil = ms() + (Config.Match.spawnProtection * 1000)

            local s = srcOf(userId)
            if s then
                TriggerClientEvent('m5rp:cl:round', s, {
                    phase    = 'spawn',
                    matchId  = m.id,
                    round    = m.round,
                    spawn    = spawnPointFor(m, mp, idx),
                    loadout  = loadoutFor(m, userId),
                    freeze   = true,
                    protection = Config.Match.spawnProtection
                })
            end
        end
    end
end

function Match.startRound(m)
    m.round = m.round + 1
    m.roundStartMs = ms()
    m.firstBloodTaken = m.firstBloodTaken or false

    for _, mp in pairs(m.players) do
        mp.killStreak = 0
        mp.multiKill  = { n = 0, ts = 0 }
        mp.lives      = m.settings.lives
        mp.damageTaken = {}
    end

    Match.spawnAll(m, false)
    Match.setState(m, 'STARTING', Config.Match.roundStartFreeze)

    Match.broadcast(m, 'm5rp:cl:round', {
        phase   = 'countdown',
        matchId = m.id,
        round   = m.round,
        seconds = Config.Match.roundStartFreeze,
        scores  = { a = m.scores[1], b = m.scores[2] }
    })
end

function Match.goLive(m)
    Match.setState(m, 'LIVE', m.settings.roundTime)
    m.roundStartMs = ms()

    for _, mp in pairs(m.players) do
        mp.lastActivity = ms()
        mp.afkWarned = false
    end

    Match.broadcast(m, 'm5rp:cl:round', {
        phase   = 'live',
        matchId = m.id,
        round   = m.round,
        time    = m.settings.roundTime
    })
    Match.pushHud(m, true)
end

--- Ends the current round and records it.
function Match.endRound(m, winner, reason)
    if m.state ~= 'LIVE' then return end

    local duration = math.floor((ms() - m.roundStartMs) / 1000)

    if winner == 1 or winner == 2 then
        m.scores[winner] = m.scores[winner] + 1
    end

    -- clutch detection: a single survivor of the winning team who had 2+ enemies alive
    if winner and not m.ffa then
        local survivors = {}
        for _, mp in pairs(m.players) do
            if mp.alive and mp.team == winner then survivors[#survivors + 1] = mp end
        end
        if #survivors == 1 and m.clutchCandidate == survivors[1].userId then
            survivors[1].clutches = survivors[1].clutches + 1
            Match.broadcast(m, 'm5rp:cl:event', {
                type = 'CLUTCH', player = survivors[1].name
            })
        end
        for _, mp in pairs(m.players) do
            if mp.team == winner then mp.roundsWon = mp.roundsWon + 1 end
        end
    end
    m.clutchCandidate = nil

    m.roundLog[#m.roundLog + 1] = {
        round = m.round, winner = winner or 0, duration = duration,
        reason = reason or 'ELIMINATION', a = m.scores[1], b = m.scores[2]
    }

    if m.dbId then
        DB.insert('INSERT INTO m5_match_rounds (match_id, round_no, winner, duration, reason, score_a, score_b) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { m.dbId, m.round, winner or 0, duration, reason or 'ELIMINATION', m.scores[1], m.scores[2] })
    end

    Match.setState(m, 'ROUND_END', Config.Match.roundEndTime)

    Match.broadcast(m, 'm5rp:cl:round', {
        phase   = 'end',
        matchId = m.id,
        round   = m.round,
        winner  = winner or 0,
        reason  = reason or 'ELIMINATION',
        scores  = { a = m.scores[1], b = m.scores[2] },
        scoreboard = playerListPayload(m)
    })
    Match.pushHud(m, true)
end

--- Determines whether the match is decided.
function Match.checkMatchOver(m)
    local s = m.settings
    local a, b = m.scores[1], m.scores[2]

    if m.cfg.type == 'ffa' or m.cfg.type == 'deathmatch' then
        if s.killLimit > 0 then
            if m.ffa then
                for _, mp in pairs(m.players) do
                    if mp.kills >= s.killLimit then return true, mp.team end
                end
            else
                if a >= s.killLimit then return true, 1 end
                if b >= s.killLimit then return true, 2 end
            end
        end
        return false
    end

    local toWin = s.roundsToWin
    if m.overtimeCount > 0 then
        -- overtime is won by a two round margin
        local need = Config.Match.overtime.winBy
        if a - b >= need and a >= toWin then return true, 1 end
        if b - a >= need and b >= toWin then return true, 2 end

        if (a + b) >= s.rounds then
            -- the extra rounds are used up: either decide it or add another half
            if m.suddenDeath or m.overtimeCount >= Config.Match.overtime.maxOvertimes then
                if a == b then return true, 0 end
                return true, a > b and 1 or 2
            end
            return false, nil, true
        end
        return false
    end

    if a >= toWin then return true, 1 end
    if b >= toWin then return true, 2 end

    local played = a + b
    if played >= s.rounds then
        if a == b then
            if s.overtime and Config.Match.overtime.enabled then
                return false, nil, true   -- trigger overtime
            end
            return true, 0
        end
        return true, a > b and 1 or 2
    end
    return false
end

-- ---------------------------------------------------------------------------
-- HUD
-- ---------------------------------------------------------------------------

function Match.pushHud(m, force)
    if not force and (ms() - m.lastHudPush) < 900 then return end
    m.lastHudPush = ms()

    local timeLeft = 0
    if m.stateEnd then timeLeft = math.max(0, math.floor((m.stateEnd - ms()) / 1000)) end

    local payload = {
        matchId  = m.id,
        state    = m.state,
        round    = m.round,
        maxRounds= m.settings.rounds,
        scores   = { a = m.scores[1], b = m.scores[2] },
        time     = timeLeft,
        aliveA   = aliveCount(m, 1),
        aliveB   = aliveCount(m, 2),
        teamA    = teamNameFor(m, 1),
        teamB    = teamNameFor(m, 2),
        overtime = m.overtimeCount > 0,
        killLimit= m.settings.killLimit,
        ffa      = m.ffa,
        scoreboard = playerListPayload(m)
    }

    for userId, mp in pairs(m.players) do
        local s = srcOf(userId)
        if s then
            payload.team  = mp.team
            payload.alive = mp.alive
            payload.ping  = GetPlayerPing(s) or 0
            TriggerClientEvent('m5rp:cl:hud', s, payload)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Kill / death handling
-- ---------------------------------------------------------------------------

local function addKillFeed(m, killerName, victimName, weapon, headshot, killerTeam, victimTeam)
    Match.broadcast(m, 'm5rp:cl:killfeed', {
        killer = killerName, victim = victimName, weapon = weapon,
        headshot = headshot, killerTeam = killerTeam, victimTeam = victimTeam
    })

    -- the server has already resolved this kill, so the hook sees the truth
    local killerId, victimId
    for userId, mp in pairs(m.players) do
        if mp.name == killerName then killerId = userId end
        if mp.name == victimName then victimId = userId end
    end
    hook('onKill', {
        matchId = m.id,
        killerUserId = killerId, killerName = killerName,
        victimUserId = victimId, victimName = victimName,
        weapon = weapon, headshot = headshot == true
    })
end

local function combatEvent(m, mp, kind, extra)
    local cfg = Config.CombatEvents[kind]
    if cfg and cfg.enabled == false then return end
    Match.broadcast(m, 'm5rp:cl:event', {
        type = kind:upper(), player = mp and mp.name or nil, extra = extra
    })
    if cfg and cfg.xp and mp then
        mp.pendingXP = (mp.pendingXP or 0) + cfg.xp
    end
end

--- Registers a validated kill. Server authoritative, called only from the
--- combat validation layer (section 13).
function Match.registerKill(m, killerId, victimId, weapon, headshot, distance)
    local victim = m.players[victimId]
    if not victim or not victim.alive then return false end
    if m.state ~= 'LIVE' then return false end

    local killer = killerId and m.players[killerId] or nil
    local suicide = (killerId == victimId) or (killer == nil)

    victim.alive  = false
    victim.deaths = victim.deaths + 1
    victim.deadAt = ms()
    victim.killStreak = 0

    if killer and not suicide then
        local friendly = (not m.ffa) and killer.team == victim.team
        if friendly and not m.settings.friendlyFire then
            -- teamkill with FF disabled should never have been validated
            return false
        end

        killer.kills = killer.kills + 1
        killer.score = killer.score + (headshot and 120 or 100)
        if headshot then killer.headshots = killer.headshots + 1 end

        killer.weapons[weapon] = (killer.weapons[weapon] or 0) + 1

        -- streaks / multikills
        killer.killStreak = killer.killStreak + 1
        if killer.killStreak > killer.bestKillStreak then
            killer.bestKillStreak = killer.killStreak
        end

        local t = ms()
        local window = Config.CombatEvents.doubleKill.window or 5000
        if (t - killer.multiKill.ts) <= window then
            killer.multiKill.n = killer.multiKill.n + 1
        else
            killer.multiKill.n = 1
        end
        killer.multiKill.ts = t

        if killer.multiKill.n == 2 then combatEvent(m, killer, 'doubleKill')
        elseif killer.multiKill.n == 3 then combatEvent(m, killer, 'tripleKill')
        elseif killer.multiKill.n >= 4 then combatEvent(m, killer, 'quadraKill') end

        if Config.CombatEvents.killStreak.enabled then
            for _, step in ipairs(Config.CombatEvents.killStreak.steps) do
                if killer.killStreak == step then
                    combatEvent(m, killer, 'killStreak', step)
                end
            end
        end

        -- first blood
        if not m.firstBloodTaken then
            m.firstBloodTaken = true
            killer.firstBloods = killer.firstBloods + 1
            combatEvent(m, killer, 'firstBlood')
        end

        -- revenge / nemesis
        if victim.lastKiller == killerId then
            -- killer killed the same victim again
            killer.nemesis[victimId] = (killer.nemesis[victimId] or 0) + 1
            if Config.CombatEvents.nemesis.enabled
               and killer.nemesis[victimId] == Config.CombatEvents.nemesis.threshold then
                combatEvent(m, killer, 'nemesis', victim.name)
            end
        end
        if killer.lastKiller == victimId then
            combatEvent(m, killer, 'revenge')
            killer.lastKiller = nil
        end
        victim.lastKiller = killerId

        -- assists: everyone else who damaged the victim recently
        for otherId, info in pairs(victim.damageTaken) do
            if otherId ~= killerId and (ms() - info.ts) <= 8000 then
                local assister = m.players[otherId]
                if assister and (m.ffa or assister.team ~= victim.team) then
                    assister.assists = assister.assists + 1
                    assister.score = assister.score + 30
                end
            end
        end
        victim.damageTaken = {}

        addKillFeed(m, killer.name, victim.name, weapon, headshot, killer.team, victim.team)

        -- gun game: every kill advances the killer to the next weapon
        if m.settings.matchType == 'gungame' then
            local ladder = presetWeapons(m.settings.weapons)
            if #ladder == 0 then ladder = (Config.Loadouts[m.settings.loadout] or Config.Loadouts.standard).weapons end
            killer.gunLevel = (killer.gunLevel or 0) + 1

            if killer.gunLevel >= #ladder then
                Match.endMatch(m, killer.team, 'GUN_GAME')
                return true
            end

            local ks = srcOf(killerId)
            if ks then
                TriggerClientEvent('m5rp:cl:round', ks, {
                    phase = 'loadout', matchId = m.id,
                    loadout = Match.loadoutFor(m, killerId),
                    gunLevel = killer.gunLevel + 1, gunTotal = #ladder
                })
            end
        end
    else
        addKillFeed(m, nil, victim.name, weapon or 'SUICIDE', false, nil, victim.team)
        victim.score = victim.score - 25
    end

    -- persist the kill row (capped)
    if m.dbId and #m.killLog < Config.Database.maxKillRowsPerMatch then
        m.killLog[#m.killLog + 1] = {
            round = m.round, killer = (killer and killerId) or 0, victim = victimId,
            weapon = weapon or '', headshot = headshot and 1 or 0,
            distance = distance or 0, ts = now()
        }
    end

    -- tell the victim client to die and enter spectator
    local vs = srcOf(victimId)
    if vs then
        TriggerClientEvent('m5rp:cl:die', vs, {
            matchId  = m.id,
            killer   = killer and killer.name or nil,
            killerId = killer and killerId or nil,
            weapon   = weapon,
            headshot = headshot,
            respawn  = m.settings.respawn,
            respawnTime = m.settings.respawnTime,
            spectateDelay = Config.SpectatorRules.deathDelay
        })
    end

    -- clutch candidate tracking (last player alive on a team)
    if not m.ffa then
        for team = 1, 2 do
            local alive = {}
            for uidv, mp2 in pairs(m.players) do
                if mp2.alive and mp2.team == team then alive[#alive + 1] = uidv end
            end
            if #alive == 1 and aliveCount(m, team == 1 and 2 or 1) >= 2 then
                m.clutchCandidate = alive[1]
            end
        end
    end

    Match.pushHud(m, true)
    Match.evaluateRound(m)
    return true
end

--- Round / match termination checks after a death or a score change.
function Match.evaluateRound(m)
    if m.state ~= 'LIVE' then return end

    if m.cfg.type == 'ffa' or m.cfg.type == 'deathmatch' then
        if not m.ffa then
            -- team deathmatch keeps a team kill score
            local a, b = 0, 0
            for _, mp in pairs(m.players) do
                if mp.team == 1 then a = a + mp.kills else b = b + mp.kills end
            end
            m.scores[1], m.scores[2] = a, b
        end
        local over, winner = Match.checkMatchOver(m)
        if over then Match.endMatch(m, winner, 'KILL_LIMIT') end
        return
    end

    -- elimination modes
    local aliveA = aliveCount(m, 1)
    local aliveB = aliveCount(m, 2)

    if aliveA == 0 and aliveB == 0 then
        Match.endRound(m, 0, 'DRAW')
    elseif aliveA == 0 then
        Match.endRound(m, 2, 'ELIMINATION')
        Match.checkAce(m, 2)
    elseif aliveB == 0 then
        Match.endRound(m, 1, 'ELIMINATION')
        Match.checkAce(m, 1)
    end
end

--- An ace is one player killing the entire enemy team in a single round.
function Match.checkAce(m, winnerTeam)
    if not Config.CombatEvents.ace.enabled then return end
    local enemyTeam = winnerTeam == 1 and 2 or 1
    local enemyCount = #teamPlayers(m, enemyTeam)
    if enemyCount < 3 then return end

    for _, mp in pairs(m.players) do
        if mp.team == winnerTeam and mp.multiKill.n >= enemyCount then
            mp.aces = (mp.aces or 0) + 1
            combatEvent(m, mp, 'ace')
            if Config.Global.announce.aces then
                Logger.send('matchEnd', 'ACE', ('**%s** aced the round in `%s`'):format(mp.name, m.id))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Match end / finalise
-- ---------------------------------------------------------------------------

local function mvpScore(mp)
    local w = Config.MVP.weights
    return mp.kills * w.kills
         + mp.deaths * w.deaths
         + mp.damage * w.damage
         + mp.headshots * w.headshots
         + mp.roundsWon * w.roundsWon
         + mp.clutches * w.clutches
         + mp.assists * w.assists
         + mp.firstBloods * w.firstBloods
end

local function pickMVP(m, winner)
    if not Config.MVP.enabled then return nil end
    local best, bestScore = nil, -math.huge
    for userId, mp in pairs(m.players) do
        if not Config.MVP.winnerOnly or m.ffa or mp.team == winner then
            local sc = mvpScore(mp)
            if sc > bestScore then best, bestScore = userId, sc end
        end
    end
    return best
end

--- Starts an extra half. The last allowed overtime becomes a single decisive
--- round when sudden death is enabled.
function Match.beginOvertime(m)
    m.overtimeCount = m.overtimeCount + 1

    local sudden = m.settings.suddenDeath
               and Config.Match.overtime.suddenDeath
               and m.overtimeCount >= Config.Match.overtime.maxOvertimes

    if sudden then
        m.suddenDeath = true
        m.settings.rounds = m.settings.rounds + 1
    else
        m.settings.rounds = m.settings.rounds + (Config.Match.overtime.roundsPerHalf * 2)
    end

    Match.broadcast(m, 'm5rp:cl:event', {
        type = sudden and 'SUDDEN_DEATH' or 'OVERTIME',
        extra = m.overtimeCount
    })
    Match.startRound(m)
end

function Match.endMatch(m, winner, reason)
    if m.state == 'MATCH_END' or m.state == 'CLEANUP' then return end

    m.endedAt = now()
    Match.setState(m, 'MATCH_END', Config.Match.matchEndTime)

    local mvpId = pickMVP(m, winner)
    if mvpId and m.players[mvpId] then m.players[mvpId].mvp = true end

    local results = Match.finalize(m, winner, reason, mvpId)

    local scoreboard = playerListPayload(m)
    local mvpEntry = mvpId and m.players[mvpId] or nil

    for userId, mp in pairs(m.players) do
        local s = srcOf(userId)
        if s then
            local r = results[userId]
            TriggerClientEvent('m5rp:cl:end', s, {
                matchId  = m.id,
                result   = m.ffa and (mp.team == winner and 'VICTORY' or 'DEFEAT')
                            or (winner == 0 and 'DRAW' or (mp.team == winner and 'VICTORY' or 'DEFEAT')),
                scores   = { a = m.scores[1], b = m.scores[2] },
                yourTeam = mp.team,
                reason   = reason,
                mvp      = mvpEntry and {
                    name = mvpEntry.name, kills = mvpEntry.kills, deaths = mvpEntry.deaths,
                    headshots = mvpEntry.headshots, damage = math.floor(mvpEntry.damage),
                    isYou = (mvpId == userId)
                } or nil,
                rp       = r and r.rp or nil,
                rank     = r and r.rank or nil,
                stats    = {
                    kills = mp.kills, deaths = mp.deaths, assists = mp.assists,
                    headshots = mp.headshots, damage = math.floor(mp.damage),
                    score = mp.score, clutches = mp.clutches
                },
                scoreboard = scoreboard,
                ranked   = m.ranked
            })
        end
    end

    -- Everything the system owed has been paid out by now, so a hook here can
    -- safely add its own rewards on top.
    do
        local players = {}
        for userId, mp in pairs(m.players) do
            local r = results[userId]
            players[#players + 1] = {
                userId = userId, name = mp.name, team = mp.team,
                kills = mp.kills, deaths = mp.deaths, assists = mp.assists,
                headshots = mp.headshots, damage = math.floor(mp.damage),
                score = mp.score,
                won = (winner ~= 0 and mp.team == winner),
                rpDelta = (r and r.rp and r.rp.delta) or 0
            }
        end
        hook('onMatchEnd', {
            matchId = m.id, mode = m.mode, ranked = m.ranked,
            winner = winner, scores = { a = m.scores[1], b = m.scores[2] },
            mvp = mvpId, players = players
        })
    end

    Logger.send('matchEnd', 'Match Finished',
        ('**%s** • `%s` • Map: %s • Score %d - %d • Winner: %s'):format(
            m.cfg.label, m.id, m.map and m.map.name or '?',
            m.scores[1], m.scores[2],
            winner == 0 and 'DRAW' or ('TEAM ' .. (winner == 1 and 'A' or 'B'))), nil, {
        { name = 'Duration', value = ('%ds'):format((m.endedAt or now()) - (m.startedAt or now())), inline = true },
        { name = 'MVP', value = mvpEntry and mvpEntry.name or '—', inline = true },
        { name = 'Ranked', value = m.ranked and 'Yes' or 'No', inline = true }
    })
end

--- Writes every result row, applies RP / MMR / stats / rewards.
function Match.finalize(m, winner, reason, mvpId)
    local results = {}
    local duration = (m.endedAt or now()) - (m.startedAt or now())

    -- lobby averages used by the RP performance model
    local n, sumKills, sumDamage, sumHS, sumKD = 0, 0, 0, 0, 0
    local teamScore = { [1] = 0, [2] = 0 }
    local teamMMR   = { [1] = { sum = 0, n = 0 }, [2] = { sum = 0, n = 0 } }
    local teamRank  = { [1] = { sum = 0, n = 0 }, [2] = { sum = 0, n = 0 } }

    for userId, mp in pairs(m.players) do
        n = n + 1
        sumKills  = sumKills + mp.kills
        sumDamage = sumDamage + mp.damage
        sumHS     = sumHS + mp.headshots
        sumKD     = sumKD + (mp.deaths > 0 and (mp.kills / mp.deaths) or mp.kills)
        local t = (mp.team == 2) and 2 or 1
        teamScore[t] = teamScore[t] + math.max(0, mp.score)
        teamMMR[t].sum = teamMMR[t].sum + mp.mmrBefore; teamMMR[t].n = teamMMR[t].n + 1
        teamRank[t].sum = teamRank[t].sum + mp.rankBefore; teamRank[t].n = teamRank[t].n + 1
    end
    if n == 0 then return results end

    local avgKills  = sumKills / n
    local avgDamage = sumDamage / n
    local avgHS     = sumHS / n
    local avgKD     = sumKD / n

    local avgMMR = {
        [1] = teamMMR[1].n > 0 and (teamMMR[1].sum / teamMMR[1].n) or Config.MMR.startValue,
        [2] = teamMMR[2].n > 0 and (teamMMR[2].sum / teamMMR[2].n) or Config.MMR.startValue
    }
    local avgRank = {
        [1] = teamRank[1].n > 0 and (teamRank[1].sum / teamRank[1].n) or 0,
        [2] = teamRank[2].n > 0 and (teamRank[2].sum / teamRank[2].n) or 0
    }
    local balanced = math.abs(avgMMR[1] - avgMMR[2]) <= Config.RankedPoints.weights.balancedThresholdMMR

    -- persist the match summary
    if m.dbId then
        DB.update([[UPDATE m5_matches SET state = 'MATCH_END', team_a_score = ?, team_b_score = ?,
                    winner = ?, rounds_played = ?, overtime = ?, avg_mmr_a = ?, avg_mmr_b = ?,
                    balanced = ?, mvp_user_id = ?, duration = ?, end_reason = ?, ended_at = ?
                    WHERE id = ?]],
            { m.scores[1], m.scores[2], winner or 0, m.round, m.overtimeCount > 0 and 1 or 0,
              math.floor(avgMMR[1]), math.floor(avgMMR[2]), balanced and 1 or 0,
              mvpId or 0, duration, reason or '', sqlDate(m.endedAt or now()), m.dbId })

        for i = 1, #m.killLog do
            local k = m.killLog[i]
            DB.insert('INSERT INTO m5_match_kills (match_id, round_no, killer, victim, weapon, headshot, distance, ts) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                { m.dbId, k.round, k.killer, k.victim, k.weapon, k.headshot, k.distance, k.ts })
        end
    end

    for userId, mp in pairs(m.players) do
        local pd = Players[userId]
        local team = (mp.team == 2) and 2 or 1
        local won  = m.ffa and (mp.team == winner) or (winner ~= 0 and mp.team == winner)
        local draw = (winner == 0)

        local enemyTeam = team == 1 and 2 or 1
        local rpResult, rpBreakdown, newMMR

        if pd then
            -- A player who reconnected mid-match came back on the pool the hub
            -- opens with, so pin the ladder to this match's mode again before
            -- anything is credited to it.
            Player.useMode(pd, m.mode)

            -- ---------------- MMR ----------------
            local kd = mp.deaths > 0 and (mp.kills / mp.deaths) or mp.kills
            local perf = clamp(((kd / math.max(0.01, avgKD)) - 1), -1, 1)
            newMMR = MMR.calculate(pd, avgMMR[team], avgMMR[enemyTeam], won, perf)

            pd.mmr = newMMR
            if newMMR > pd.peakMMR then pd.peakMMR = newMMR end
            pd.mmrGames = pd.mmrGames + 1
            pd.uncertainty = math.max(Config.MMR.uncertaintyMin,
                                      pd.uncertainty - Config.MMR.uncertaintyDecay)
            pd.dirtyMMR = true

            -- ---------------- RP ----------------
            if m.ranked and not mp.leftEarly then
                if Config.Placement.enabled and not pd.placementDone then
                    pd.placementPlayed = pd.placementPlayed + 1
                    pd.placementData[#pd.placementData + 1] = {
                        won = won and 1 or 0,
                        kd = round(kd, 2),
                        hs = mp.kills > 0 and round(mp.headshots / mp.kills, 2) or 0,
                        dmg = math.floor(mp.damage),
                        mvp = (mvpId == userId) and 1 or 0,
                        oppMMR = math.floor(avgMMR[enemyTeam])
                    }
                    pd.dirtyRank = true

                    if pd.placementPlayed >= Config.Placement.matches then
                        rpResult = Match.completePlacement(pd)
                    else
                        rpResult = {
                            placement = true,
                            played = pd.placementPlayed,
                            total = Config.Placement.matches,
                            before = pd.rp, after = pd.rp, delta = 0
                        }
                    end
                else
                    local delta, breakdown = RP.calculate({
                        pd = pd, won = won, draw = draw,
                        roundsWon = m.ffa and mp.kills or m.scores[team],
                        roundsLost = m.ffa and 0 or m.scores[enemyTeam],
                        mvp = (mvpId == userId),
                        kills = mp.kills, deaths = mp.deaths, damage = mp.damage,
                        headshots = mp.headshots, clutches = mp.clutches,
                        objective = mp.firstBloods,
                        avgKills = avgKills, avgDamage = avgDamage,
                        avgHeadshots = avgHS, avgKD = avgKD,
                        teamScoreShare = teamScore[team] > 0 and (math.max(0, mp.score) / teamScore[team]) or 0.25,
                        allyMMR = avgMMR[team], enemyMMR = avgMMR[enemyTeam],
                        allyRank = avgRank[team], enemyRank = avgRank[enemyTeam],
                        winStreak = pd.stats.win_streak, loseStreak = pd.stats.lose_streak,
                        balanced = balanced
                    })
                    rpBreakdown = breakdown
                    rpResult = RP.apply(pd, delta, won and 'WIN' or (draw and 'DRAW' or 'LOSS'))
                    rpResult.breakdown = breakdown
                end
            end

            -- ---------------- stats ----------------
            local st = pd.stats
            st.matches   = st.matches + 1
            st.kills     = st.kills + mp.kills
            st.deaths    = st.deaths + mp.deaths
            st.assists   = st.assists + mp.assists
            st.headshots = st.headshots + mp.headshots
            st.damage    = st.damage + math.floor(mp.damage)
            st.clutches  = st.clutches + mp.clutches
            st.aces      = st.aces + (mp.aces or 0)
            st.first_bloods = st.first_bloods + mp.firstBloods
            st.rounds_won = st.rounds_won + mp.roundsWon
            st.rounds_played = st.rounds_played + m.round
            st.playtime  = st.playtime + duration

            if mvpId == userId then st.mvp = st.mvp + 1 end

            if draw then
                st.draws = st.draws + 1
            elseif won then
                st.wins = st.wins + 1
                st.win_streak = st.win_streak + 1
                st.lose_streak = 0
                if st.win_streak > st.best_win_streak then st.best_win_streak = st.win_streak end
                if Config.Global.announce.winStreaks > 0
                   and st.win_streak == Config.Global.announce.winStreaks then
                    Logger.send('matchEnd', 'Win Streak',
                        ('**%s** is on a %d match win streak'):format(pd.name, st.win_streak), pd)
                end
            else
                st.losses = st.losses + 1
                st.lose_streak = st.lose_streak + 1
                st.win_streak = 0
            end

            for w, c in pairs(mp.weapons) do
                st.weapon_stats[w] = (st.weapon_stats[w] or 0) + c
            end
            if m.map then
                st.map_stats[m.map.id] = (st.map_stats[m.map.id] or 0) + 1
            end
            Player.refreshFavourites(pd)

            pd.playtime = pd.playtime + duration
            pd.dirtyStats  = true
            pd.dirtyPlayer = true

            -- ---------------- rewards / xp ----------------
            Match.grantMatchRewards(m, pd, mp, won, draw, mvpId == userId)

            results[userId] = {
                rp = rpResult and {
                    before = rpResult.before, after = rpResult.after,
                    delta  = rpResult.delta,
                    placement = rpResult.placement, played = rpResult.played,
                    total = rpResult.total, breakdown = rpBreakdown
                } or nil,
                rank = {
                    before = Rank.get(mp.rankBefore).name,
                    after  = Rank.get(pd.rankId).name,
                    id     = pd.rankId,
                    up     = rpResult and rpResult.rankUp or false,
                    down   = rpResult and rpResult.rankDown or false,
                    color  = Rank.get(pd.rankId).color,
                    progress = Rank.progress(pd.rp, pd.rankId, pd.placementDone)
                }
            }

            if rpResult and rpResult.rankUp then
                Logger.send('rankUp', 'Rank Up',
                    ('**%s** promoted to **%s**'):format(pd.name, Rank.get(pd.rankId).name), pd)
                if Rank.get(pd.rankId).tier == 'RADIANT' and Config.Global.announce.radiantPromotion then
                    TriggerClientEvent('chat:addMessage', -1, {
                        color = { 255, 233, 168 },
                        multiline = true,
                        args = { 'M5 RANKED', ('%s has reached RADIANT'):format(pd.name) }
                    })
                end
            elseif rpResult and rpResult.rankDown then
                Logger.send('rankDown', 'Rank Down',
                    ('**%s** demoted to **%s**'):format(pd.name, Rank.get(pd.rankId).name), pd)
            end

            if rpResult and rpResult.delta and rpResult.delta ~= 0 then
                Logger.send(rpResult.delta > 0 and 'rpGain' or 'rpLoss',
                    rpResult.delta > 0 and 'RP Gained' or 'RP Lost',
                    ('`%s` • %s%d RP (%d → %d)'):format(m.id,
                        rpResult.delta > 0 and '+' or '', rpResult.delta,
                        rpResult.before, rpResult.after), pd)
            end
        end

        -- ---------------- match player row ----------------
        if m.dbId then
            DB.insert([[INSERT INTO m5_match_players
                (match_id, user_id, name, team, kills, deaths, assists, headshots, damage, score,
                 clutches, first_bloods, rounds_won, mvp, rp_before, rp_after, rp_change,
                 mmr_before, mmr_after, rank_before, rank_after, result, left_early, afk, fav_weapon)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE kills = VALUES(kills), deaths = VALUES(deaths)]],
                { m.dbId, userId, mp.name, mp.team, mp.kills, mp.deaths, mp.assists,
                  mp.headshots, math.floor(mp.damage), mp.score, mp.clutches, mp.firstBloods,
                  mp.roundsWon, (mvpId == userId) and 1 or 0,
                  mp.rpBefore, pd and pd.rp or mp.rpBefore,
                  (pd and pd.rp or mp.rpBefore) - mp.rpBefore,
                  mp.mmrBefore, pd and pd.mmr or mp.mmrBefore,
                  mp.rankBefore, pd and pd.rankId or mp.rankBefore,
                  draw and 'DRAW' or (won and 'WIN' or 'LOSS'),
                  mp.leftEarly and 1 or 0, mp.afk and 1 or 0,
                  (function()
                      local bw, bn = '', 0
                      for w, c in pairs(mp.weapons) do if c > bn then bw, bn = w, c end end
                      return bw
                  end)() })
        end

        if pd then Player.save(pd, false) end
    end

    -- anti boost pass
    if Config.AntiBoost.enabled and Config.AntiBoost.analyseOnMatchEnd and m.ranked then
        for userId in pairs(m.players) do
            AntiBoost.analyse(userId, m)
        end
    end

    return results
end

--- Finishes placement and assigns the initial rank.
function Match.completePlacement(pd)
    local data = pd.placementData or {}
    local nData = #data
    if nData == 0 then return nil end

    local wins, kdSum, hsSum, dmgSum, mvpSum, oppSum = 0, 0, 0, 0, 0, 0
    for i = 1, nData do
        wins   = wins + (data[i].won or 0)
        kdSum  = kdSum + (data[i].kd or 0)
        hsSum  = hsSum + (data[i].hs or 0)
        dmgSum = dmgSum + (data[i].dmg or 0)
        mvpSum = mvpSum + (data[i].mvp or 0)
        oppSum = oppSum + (data[i].oppMMR or Config.MMR.startValue)
    end

    local W = Config.Placement.weights
    local winRate = wins / nData
    local kd      = clamp((kdSum / nData) / 2.0, 0, 1)
    local hs      = clamp(hsSum / nData, 0, 1)
    local dmg     = clamp((dmgSum / nData) / 2500, 0, 1)
    local mvp     = clamp(mvpSum / nData, 0, 1)
    local opp     = clamp(((oppSum / nData) - Config.MMR.min) /
                          math.max(1, Config.MMR.max - Config.MMR.min), 0, 1)

    local score = winRate * W.winRate + kd * W.kd + hs * W.headshotPct
                + dmg * W.damage + mvp * W.mvp + opp * W.opponentMMR

    local rankId = 1
    for i = 1, #Config.Placement.resultTable do
        if score >= Config.Placement.resultTable[i].minScore then
            rankId = Config.Placement.resultTable[i].rankId
        end
    end

    local rank = Rank.get(rankId)
    pd.placementDone = true
    pd.rp        = rank.rpRequired
    pd.rankId    = rank.id
    pd.division  = rank.division
    pd.highestRankId = math.max(pd.highestRankId, rank.id)
    pd.highestRP = math.max(pd.highestRP, pd.rp)
    pd.rankProtection = Config.RankSettings.rankProtectionGames
    pd.dirtyRank = true

    Logger.send('rankUp', 'Placement Complete',
        ('**%s** placed **%s** (score %.2f)'):format(pd.name, rank.name, score), pd)

    return {
        before = 0, after = pd.rp, delta = pd.rp,
        rankBefore = 0, rankAfter = rank.id,
        rankUp = true, rankDown = false,
        placementComplete = true, score = round(score, 3)
    }
end

-- ---------------------------------------------------------------------------
-- Cleanup / abort / leaving
-- ---------------------------------------------------------------------------

function Match.cleanup(m)
    Match.setState(m, 'CLEANUP', Config.Match.cleanupTime)

    for userId, mp in pairs(m.players) do
        local pd = Players[userId]
        if pd then
            pd.state   = 'IDLE'
            pd.matchId = nil
            pd.team    = 0
        end
        local s = srcOf(userId)
        if s then
            SetPlayerRoutingBucket(s, 0)
            TriggerClientEvent('m5rp:cl:cleanup', s, { matchId = m.id })
        end
    end

    if m.customId then
        CustomGames.onMatchEnd(m)
    end

    UsedBuckets[m.bucket] = nil
    Matches[m.id] = nil
    dbg('match %s cleaned up', m.id)
end

function Match.abort(m, reason)
    Match.broadcast(m, 'm5rp:cl:notify', {
        kind = 'error', title = 'MATCH CANCELLED',
        message = 'The match was cancelled (' .. (reason or 'unknown') .. ').'
    })
    if m.dbId then
        DB.update("UPDATE m5_matches SET state = 'CLEANUP', end_reason = ?, ended_at = ? WHERE id = ?",
            { reason or 'ABORTED', sqlDate(), m.dbId })
    end
    Match.cleanup(m)
end

--- Removes a player from a live match (disconnect, AFK kick, admin move).
-- @param reason 'DISCONNECT' | 'AFK' | 'ADMIN' | 'LEAVE'
function Match.removePlayer(m, userId, reason)
    local mp = m.players[userId]
    if not mp then return end

    hook('onMatchLeave', {
        userId = userId, source = srcOf(userId), name = mp.name,
        matchId = m.id, reason = reason or 'LEAVE'
    })

    mp.connected = false
    mp.alive     = false
    mp.leftEarly = true
    if reason == 'AFK' then mp.afk = true end

    local pd = Players[userId]
    if pd then
        pd.state   = 'IDLE'
        pd.matchId = nil
    end

    local s = srcOf(userId)
    if s then
        SetPlayerRoutingBucket(s, 0)
        TriggerClientEvent('m5rp:cl:cleanup', s, { matchId = m.id })
    end

    -- Ranked penalties only apply to live ranked matches
    if m.ranked and m.state ~= 'MATCH_END' and m.state ~= 'CLEANUP' then
        if reason == 'DISCONNECT' and Config.Reconnect.enabled
           and mp.reconnects < Config.Reconnect.maxReconnects then
            Reconnects[userId] = {
                matchId = m.id, expires = now() + Config.Reconnect.window,
                team = mp.team, kills = mp.kills, deaths = mp.deaths
            }
            mp.reconnects = mp.reconnects + 1
            Match.broadcast(m, 'm5rp:cl:notify', {
                kind = 'warning', title = 'PLAYER DISCONNECTED',
                message = ('%s disconnected — %ds to reconnect.'):format(mp.name, Config.Reconnect.window)
            })
        else
            Penalty.apply(userId, reason == 'AFK' and 'AFK' or 'LEAVE', m.dbId,
                          m.state == 'WAITING' or m.state == 'MAP_VOTE' or m.state == 'STARTING')
        end
    end

    Match.pushHud(m, true)
    Match.evaluateRound(m)
    Match.checkForfeit(m)
end

--- Ends the match when a team can no longer field enough players.
function Match.checkForfeit(m)
    if m.state == 'MATCH_END' or m.state == 'CLEANUP' then return end
    if m.ffa then
        local remaining = 0
        for _, mp in pairs(m.players) do if mp.connected then remaining = remaining + 1 end end
        if remaining <= 1 then
            local winner = 0
            for _, mp in pairs(m.players) do if mp.connected then winner = mp.team end end
            Match.endMatch(m, winner, 'FORFEIT')
        end
        return
    end

    local connected = { [1] = 0, [2] = 0 }
    for _, mp in pairs(m.players) do
        if mp.connected then
            local t = mp.team == 2 and 2 or 1
            connected[t] = connected[t] + 1
        end
    end

    for team = 1, 2 do
        if connected[team] < Config.Match.minPlayersToContinue then
            if not m.forfeitTimer[team] then
                m.forfeitTimer[team] = ms() + (Config.Match.abandonForfeitDelay * 1000)
                Match.broadcast(m, 'm5rp:cl:notify', {
                    kind = 'warning', title = 'TEAM INCOMPLETE',
                    message = ('Team %s is short handed. Forfeit in %ds.'):format(
                        team == 1 and 'A' or 'B', Config.Match.abandonForfeitDelay)
                })
            elseif ms() >= m.forfeitTimer[team] then
                Match.endMatch(m, team == 1 and 2 or 1, 'FORFEIT')
                return
            end
        else
            m.forfeitTimer[team] = nil
        end
    end
end

--- Restores a player who reconnected inside the window.
function Match.tryReconnect(userId)
    local info = Reconnects[userId]
    if not info then return false, 'No match to reconnect to.' end
    if info.expires < now() then
        Reconnects[userId] = nil
        return false, 'The reconnect window has expired.'
    end

    local m = Matches[info.matchId]
    if not m or m.state == 'CLEANUP' or m.state == 'MATCH_END' then
        Reconnects[userId] = nil
        return false, 'That match has already ended.'
    end

    local mp = m.players[userId]
    if not mp then
        Reconnects[userId] = nil
        return false, 'You are no longer part of that match.'
    end

    Reconnects[userId] = nil
    mp.connected = true
    mp.leftEarly = false

    local pd = Players[userId]
    if pd then
        pd.state   = m.customId and 'CUSTOM' or 'MATCH'
        pd.matchId = m.id
        pd.team    = mp.team
    end

    Match.deploy(m, userId)

    -- Rejoin as a spectator until the next round when rounds are elimination based
    if m.state == 'LIVE' and not m.settings.respawn then
        mp.alive = false
        local s = srcOf(userId)
        if s then
            TriggerClientEvent('m5rp:cl:spectate', s, { matchId = m.id, enable = true, team = mp.team })
        end
    else
        Match.spawnAll(m, true)
    end

    Match.broadcast(m, 'm5rp:cl:notify', {
        kind = 'success', title = 'PLAYER RECONNECTED',
        message = ('%s reconnected to the match.'):format(mp.name)
    })
    Match.pushHud(m, true)
    return true
end

-- ---------------------------------------------------------------------------
-- Surrender
-- ---------------------------------------------------------------------------

function Match.startSurrender(m, userId)
    local cfg = Config.Match.surrender
    if not cfg.enabled then return false, 'Surrender is disabled.' end
    if m.state ~= 'LIVE' and m.state ~= 'ROUND_END' then return false, 'Not available right now.' end
    if m.round < cfg.minRound then
        return false, _Lf('Available from round %d.', cfg.minRound)
    end
    if m.surrender and m.surrender.expires > ms() then return false, 'A vote is already running.' end
    if m.surrenderCooldown and m.surrenderCooldown > ms() then return false, 'Please wait before voting again.' end

    local mp = m.players[userId]
    if not mp then return false end

    m.surrender = {
        team = mp.team, votes = { [userId] = true },
        expires = ms() + cfg.voteDuration * 1000
    }

    local total = 0
    for _, o in pairs(m.players) do
        if o.team == mp.team and o.connected then total = total + 1 end
    end

    Match.broadcastTeam(m, mp.team, 'm5rp:cl:event', {
        type = 'SURRENDER_VOTE', extra = { yes = 1, total = total, duration = cfg.voteDuration }
    })
    return true
end

function Match.surrenderVote(m, userId, agree)
    if not m.surrender or m.surrender.expires <= ms() then return false end
    local mp = m.players[userId]
    if not mp or mp.team ~= m.surrender.team then return false end

    m.surrender.votes[userId] = agree and true or false

    local yes, total = 0, 0
    for uidv, o in pairs(m.players) do
        if o.team == m.surrender.team and o.connected then
            total = total + 1
            if m.surrender.votes[uidv] then yes = yes + 1 end
        end
    end

    Match.broadcastTeam(m, m.surrender.team, 'm5rp:cl:event', {
        type = 'SURRENDER_VOTE', extra = { yes = yes, total = total }
    })

    if total > 0 and (yes / total) >= Config.Match.surrender.requiredRatio then
        local winner = m.surrender.team == 1 and 2 or 1
        m.surrender = nil
        Match.endMatch(m, winner, 'SURRENDER')
    end
    return true
end

-- ---------------------------------------------------------------------------
-- AFK
-- ---------------------------------------------------------------------------

function Match.checkAFK(m)
    if not Config.AFK.enabled then return end
    if inList(Config.AFK.ignoreStates, m.state) then return end

    local t = ms()
    for userId, mp in pairs(m.players) do
        if mp.connected and (mp.alive or m.settings.respawn) then
            local idle = (t - mp.lastActivity) / 1000

            if idle >= Config.AFK.kickAfter then
                Logger.send('afk', 'AFK Removal',
                    ('**%s** was removed from `%s` for inactivity'):format(mp.name, m.id), Players[userId])
                notifyUser(userId, 'error', 'You were removed from the match for inactivity.', 'AFK')
                Match.removePlayer(m, userId, 'AFK')
            elseif idle >= Config.AFK.warningAfter and not mp.afkWarned then
                mp.afkWarned = true
                local s = srcOf(userId)
                if s then
                    TriggerClientEvent('m5rp:cl:event', s, {
                        type = 'AFK_WARNING',
                        extra = math.floor(Config.AFK.kickAfter - idle)
                    })
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Per match tick (driven by the master loop)
-- ---------------------------------------------------------------------------

function Match.tick(m)
    local t = ms()

    if m.state == 'MAP_VOTE' then
        if m.stateEnd and t >= m.stateEnd then
            Match.resolveMapVote(m)
        end
        return
    end

    if m.state == 'STARTING' then
        if m.stateEnd and t >= m.stateEnd then
            if m.round == 0 then
                Match.startRound(m)
            else
                Match.goLive(m)
            end
        end
        return
    end

    if m.state == 'LIVE' then
        Match.checkAFK(m)
        Match.pushHud(m, false)

        -- respawn handling for deathmatch style modes
        if m.settings.respawn then
            for userId, mp in pairs(m.players) do
                if mp.connected and not mp.alive and mp.deadAt > 0
                   and (t - mp.deadAt) >= (m.settings.respawnTime * 1000) then
                    mp.alive = true
                    mp.deadAt = 0
                    mp.spawnProtectUntil = t + (Config.Match.spawnProtection * 1000)
                    local s = srcOf(userId)
                    if s then
                        TriggerClientEvent('m5rp:cl:round', s, {
                            phase = 'respawn', matchId = m.id,
                            spawn = spawnPointFor(m, mp, math.random(1, 5)),
                            loadout = loadoutFor(m, userId),
                            protection = Config.Match.spawnProtection
                        })
                    end
                end
            end
        end

        -- surrender vote expiry
        if m.surrender and m.surrender.expires <= t then
            m.surrender = nil
            m.surrenderCooldown = t + Config.Match.surrender.cooldown * 1000
        end

        -- hard match duration limit
        if m.startedAt and (now() - m.startedAt) > Config.Match.maxMatchDuration then
            Match.endMatch(m, m.scores[1] == m.scores[2] and 0 or (m.scores[1] > m.scores[2] and 1 or 2), 'TIME_LIMIT')
            return
        end

        if m.stateEnd and t >= m.stateEnd then
            if m.cfg.type == 'ffa' or m.cfg.type == 'deathmatch' then
                local winner = 0
                if m.ffa then
                    local best, bestK = 0, -1
                    for _, mp in pairs(m.players) do
                        if mp.kills > bestK then best, bestK = mp.team, mp.kills end
                    end
                    winner = best
                else
                    winner = m.scores[1] == m.scores[2] and 0 or (m.scores[1] > m.scores[2] and 1 or 2)
                end
                Match.endMatch(m, winner, 'TIME')
            else
                -- round timer expired: the team with more players alive takes it
                local aliveA, aliveB = aliveCount(m, 1), aliveCount(m, 2)
                local winner = 0
                if aliveA > aliveB then winner = 1
                elseif aliveB > aliveA then winner = 2 end
                Match.endRound(m, winner, 'TIME')
            end
        end
        return
    end

    if m.state == 'ROUND_END' then
        if m.stateEnd and t >= m.stateEnd then
            local over, winner, needOvertime = Match.checkMatchOver(m)
            if over then
                Match.endMatch(m, winner, m.overtimeCount > 0 and 'OVERTIME' or 'ROUNDS')
            elseif needOvertime and m.settings.overtime and Config.Match.overtime.enabled then
                Match.beginOvertime(m)
            else
                Match.startRound(m)
            end
        end
        return
    end

    if m.state == 'MATCH_END' then
        if m.stateEnd and t >= m.stateEnd then
            Match.cleanup(m)
        end
        return
    end
end

-- ============================================================================
-- 13. COMBAT VALIDATION
-- ============================================================================
-- Every kill, every point of damage and every headshot is decided here.
-- Clients only *report* observations; nothing they send is trusted directly.

local Combat = {}

local function matchOfPlayer(pd)
    if not pd or not pd.matchId then return nil end
    return Matches[pd.matchId]
end

--- Shared validation for an attacker/victim pair inside a match.
-- Returns match, attackerEntry, victimEntry or nil + reason.
local function validatePair(attackerPd, victimSrc, weapon)
    if not attackerPd then return nil, 'no attacker' end

    local victimUserId = SrcToUser[victimSrc]
    if not victimUserId then return nil, 'unknown victim' end
    if victimUserId == attackerPd.userId then return nil, 'self damage' end

    local victimPd = Players[victimUserId]
    if not victimPd then return nil, 'victim not loaded' end

    local m = matchOfPlayer(attackerPd)
    if not m then return nil, 'attacker not in a match' end
    if victimPd.matchId ~= m.id then return nil, 'victim in another match' end
    if m.state ~= 'LIVE' then return nil, 'match not live' end

    local a = m.players[attackerPd.userId]
    local v = m.players[victimUserId]
    if not a or not v then return nil, 'roster mismatch' end
    if not a.connected or not v.connected then return nil, 'disconnected' end
    if not v.alive then return nil, 'victim already down' end
    if not a.alive and not m.settings.respawn then return nil, 'attacker is dead' end

    -- friendly fire
    if not m.ffa and a.team == v.team and not m.settings.friendlyFire then
        return nil, 'friendly fire disabled'
    end

    -- weapon whitelist
    if weapon and not Security.weaponAllowed(weapon) then
        return nil, 'weapon not allowed: ' .. tostring(weapon)
    end

    -- spawn protection / anti spawn kill
    if v.spawnProtectUntil > ms() then return nil, 'victim spawn protected' end

    return m, a, v, victimUserId
end

--- Attacker reports firing a weapon (throttled client side). The report also
--- carries the traced target and whether the trace landed on the head, which is
--- kept purely as corroboration — a hit still only counts once the victim
--- confirms taking damage.
function Combat.shot(pd, data)
    if not pd then return end
    local weapon = type(data) == 'table' and data.weapon or data
    if type(weapon) ~= 'string' then weapon = nil end
    if weapon and not Security.weaponAllowed(weapon) then return end

    pd.lastShot = {
        ts     = ms(),
        weapon = weapon,
        target = type(data) == 'table' and tonumber(data.target) or nil,
        head   = type(data) == 'table' and data.head == true or false,
        dist   = type(data) == 'table' and tonumber(data.dist) or 0.0
    }
    local m = matchOfPlayer(pd)
    if m then
        local mp = m.players[pd.userId]
        if mp then mp.lastActivity = ms() end
    end
end

--- The VICTIM reports the damage it took, together with who caused it. Reading
--- the health delta on the victim's own client is the only place where the
--- number is exact, and it stops an attacker from inflating their own numbers.
function Combat.damage(victimPd, data)
    if type(data) ~= 'table' then return end
    local amount = tonumber(data.amount) or 0
    if amount <= 0 or amount > Config.Security.maxSingleDamage then return end

    local attackerSrc = tonumber(data.attacker)
    if not attackerSrc then return end
    local attackerUserId = SrcToUser[attackerSrc]
    if not attackerUserId or attackerUserId == victimPd.userId then return end
    local pd = Players[attackerUserId]
    if not pd then return end

    local weapon = type(data.weapon) == 'string' and data.weapon:upper() or nil
    local m, a, v = validatePair(pd, victimPd.source, weapon)
    if not m then
        if Config.Security.logRejections then dbg('damage rejected: %s', tostring(a)) end
        return
    end

    -- Never credit environmental damage
    if data.source and inList(Config.Weapons.invalidDamageSources, tostring(data.source):upper()) then
        return
    end

    a.damage = a.damage + amount
    a.score  = a.score + math.floor(amount / 10)
    a.lastActivity = ms()

    v.damageTaken[attackerUserId] = {
        ts = ms(),
        amount = (v.damageTaken[attackerUserId] and v.damageTaken[attackerUserId].amount or 0) + amount,
        weapon = weapon
    }

    -- Corroborated headshot: the victim confirms the hit, the attacker's trace
    -- says it landed on the head. This covers the case where the engine's bone
    -- report is unreliable at long range — the kill is still decided here, and
    -- the distance never reduces its lethality.
    if Config.Headshot.enabled and Config.Headshot.oneShotKill
       and m.settings.headshotOneShot
       and not (Config.Headshot.excludeMelee and Security.isMelee(weapon))
       and not inList(Config.Headshot.excludedWeapons, weapon or '') then

        local shot = pd.lastShot
        if shot and shot.head and shot.target == victimPd.source
           and (ms() - shot.ts) <= Config.Headshot.shotWindow then

            pd.hsHistory = pd.hsHistory or {}
            local last = pd.hsHistory[victimPd.userId]
            if not last or (ms() - last) >= Config.Headshot.duplicateWindow then
                if not pd.lastKillMs or (ms() - pd.lastKillMs) >= Config.Weapons.minKillInterval then
                    pd.hsHistory[victimPd.userId] = ms()
                    pd.lastKillMs = ms()
                    Match.registerKill(m, attackerUserId, victimPd.userId, weapon, true, shot.dist or 0)
                end
            end
        end
    end
end

--- Victim reports a head impact. This is what makes a headshot lethal at any
--- distance: the server ignores the game's damage falloff entirely and decides
--- the kill itself once the hit is proven legitimate.
function Combat.headshot(victimPd, data)
    if not Config.Headshot.enabled or not Config.Headshot.oneShotKill then return end
    if type(data) ~= 'table' then return end

    local attackerSrc = tonumber(data.attacker)
    if not attackerSrc then return end

    local attackerUserId = SrcToUser[attackerSrc]
    if not attackerUserId then return end
    if attackerUserId == victimPd.userId then return end

    local attackerPd = Players[attackerUserId]
    if not attackerPd then return end

    local weapon = type(data.weapon) == 'string' and data.weapon:upper() or ''

    -- bone must be a real head bone
    local bone = tonumber(data.bone) or 0
    if bone ~= 0 and not inList(Config.Headshot.headBones, bone) then
        dbg('headshot rejected: bone %d is not a head bone', bone)
        return
    end

    -- weapon rules
    if inList(Config.Headshot.excludedWeapons, weapon) then return end
    if Config.Headshot.excludeMelee and Security.isMelee(weapon) then return end

    -- environmental damage can never be a headshot
    if data.source and inList(Config.Weapons.invalidDamageSources, tostring(data.source):upper()) then
        dbg('headshot rejected: invalid damage source %s', tostring(data.source))
        return
    end

    -- the pair must be valid (same live match, opposing sides, allowed weapon)
    local m, a, v, victimUserId = validatePair(attackerPd, victimPd.source, weapon)
    if not m then
        if Config.Security.logRejections then dbg('headshot rejected: %s', tostring(a)) end
        return
    end

    -- mode gate
    if m.customId and not Config.Headshot.enabledInCustom then return end
    if m.ranked and not Config.Headshot.enabledInRanked then return end
    if not m.settings.headshotOneShot then return end

    if Config.Headshot.requireVictimAlive and not v.alive then return end

    -- the attacker must actually have fired recently with that weapon
    local shot = attackerPd.lastShot
    if not shot or (ms() - shot.ts) > Config.Headshot.shotWindow then
        dbg('headshot rejected: no recent shot from %s', attackerPd.name)
        return
    end
    if shot.weapon and weapon ~= '' and shot.weapon ~= weapon then
        dbg('headshot rejected: weapon mismatch (%s vs %s)', tostring(shot.weapon), weapon)
        return
    end

    -- duplicate protection
    attackerPd.hsHistory = attackerPd.hsHistory or {}
    local last = attackerPd.hsHistory[victimUserId]
    if last and (ms() - last) < Config.Headshot.duplicateWindow then return end

    -- minimum interval between two validated kills from the same attacker
    if attackerPd.lastKillMs and (ms() - attackerPd.lastKillMs) < Config.Weapons.minKillInterval then
        return
    end

    attackerPd.hsHistory[victimUserId] = ms()
    attackerPd.lastKillMs = ms()

    -- distance is recorded but never used to reduce lethality
    local dist = tonumber(data.dist) or 0.0
    if dist > Config.Weapons.maxPlausibleDistance then
        AntiBoost.flag(attackerUserId, 'impossibleHeadshot', 1, {
            distance = round(dist, 1), weapon = weapon, match = m.id
        }, m.dbId)
    end

    -- Config.Headshot.ignoreDistance is the whole point: no falloff, no range
    -- check, a valid head hit is always lethal.
    Match.registerKill(m, attackerUserId, victimUserId, weapon, true, dist)
end

--- Victim reports their own death (non headshot, explosion, fall, ...).
function Combat.death(victimPd, data)
    local m = matchOfPlayer(victimPd)
    if not m or m.state ~= 'LIVE' then return end

    local v = m.players[victimPd.userId]
    if not v or not v.alive then return end

    -- HEADSHOT ONLY rooms: nothing but a validated head hit may kill, and those
    -- come through Combat.headshot rather than here.
    if m.settings.headshotOnly then
        local s = srcOf(victimPd.userId)
        if s then
            TriggerClientEvent('m5rp:cl:round', s, {
                phase = 'revive', matchId = m.id,
                health = m.settings.health or 100
            })
        end
        return
    end

    data = type(data) == 'table' and data or {}

    local killerUserId = nil
    local weapon = type(data.weapon) == 'string' and data.weapon:upper() or ''

    -- Prefer the reported killer, but only if the server can corroborate it
    local claimedSrc = tonumber(data.killer)
    if claimedSrc then
        local cid = SrcToUser[claimedSrc]
        if cid and cid ~= victimPd.userId and m.players[cid] then
            local dmg = v.damageTaken[cid]
            if dmg and (ms() - dmg.ts) <= Config.Security.killDamageWindow then
                killerUserId = cid
            end
        end
    end

    -- Otherwise fall back to whoever damaged the victim most recently
    if not killerUserId then
        local bestTs = 0
        for otherId, info in pairs(v.damageTaken) do
            if info.ts > bestTs and (ms() - info.ts) <= Config.Security.killDamageWindow then
                bestTs, killerUserId = info.ts, otherId
                weapon = info.weapon or weapon
            end
        end
    end

    -- Environmental deaths have no killer
    if data.source and inList(Config.Weapons.invalidDamageSources, tostring(data.source):upper()) then
        killerUserId = nil
    end

    if killerUserId then
        local killerPd = Players[killerUserId]
        if killerPd then
            if killerPd.lastKillMs and (ms() - killerPd.lastKillMs) < Config.Weapons.minKillInterval then
                return
            end
            killerPd.lastKillMs = ms()
        end
    end

    Match.registerKill(m, killerUserId, victimPd.userId, weapon, false, tonumber(data.dist) or 0)
end

--- Player left the combat zone and the timer ran out.
function Combat.outOfBounds(pd)
    local m = matchOfPlayer(pd)
    if not m or m.state ~= 'LIVE' then return end
    local mp = m.players[pd.userId]
    if not mp or not mp.alive then return end

    if Config.Match.boundary.action == 'teleport' then
        local s = srcOf(pd.userId)
        if s then
            -- The teleport resurrects the ped, which strips its weapons, so
            -- this has to hand the loadout back. Sending nil left a player
            -- pulled in from out of bounds standing there unarmed.
            TriggerClientEvent('m5rp:cl:round', s, {
                phase = 'respawn', matchId = m.id,
                spawn = spawnPointFor(m, mp, 1),
                loadout = loadoutFor(m, pd.userId), protection = 1
            })
        end
        return
    end

    Match.registerKill(m, nil, pd.userId, 'OUT_OF_BOUNDS', false, 0)
end

-- ============================================================================
-- 14. CUSTOM GAMES
-- ============================================================================

CustomGames = { rooms = {}, byCode = {} }

--- Short, unambiguous room code used by JOIN CODE in the UI.
local function newRoomCode()
    local cfg = Config.CustomGames.roomCode
    for _ = 1, 40 do
        local code = ''
        for _ = 1, cfg.length do
            local i = math.random(#cfg.alphabet)
            code = code .. cfg.alphabet:sub(i, i)
        end
        if not CustomGames.byCode[code] then return code end
    end
    return tostring(math.random(1000, 9999))
end

local function roomPayload(room, includePrivate)
    local players = {}
    for userId, entry in pairs(room.players) do
        local pd = Players[userId]
        players[#players + 1] = {
            userId = userId,
            name   = pd and pd.name or entry.name,
            team   = entry.team,
            ready  = entry.ready,
            host   = (userId == room.hostId),
            rank   = pd and Rank.get(pd.rankId).name or 'Unranked',
            spectator = entry.spectator == true
        }
    end
    table.sort(players, function(a, b)
        if a.team ~= b.team then return a.team < b.team end
        return a.name < b.name
    end)

    local map = MapById[room.mapId]
    return {
        id       = room.id,
        code     = room.code,
        name     = room.name,
        host     = Players[room.hostId] and Players[room.hostId].name or '?',
        hostId   = room.hostId,
        mode     = room.mode,
        modeLabel= (Config.Modes[room.mode] or {}).label or room.mode,
        map      = room.mapId,
        mapName  = map and map.name or room.mapId,
        players  = #players,
        maxPlayers = room.maxPlayers,
        locked   = room.locked,
        hasPassword = room.password ~= '',
        state    = room.state,
        ranked   = room.ranked,
        roster   = includePrivate and players or nil,
        settings = includePrivate and room.settings or nil
    }
end

function CustomGames.list()
    local out = {}
    for _, room in pairs(CustomGames.rooms) do
        out[#out + 1] = roomPayload(room, false)
    end
    table.sort(out, function(a, b) return a.players > b.players end)
    return out
end

function CustomGames.sync(room)
    local payload = roomPayload(room, true)
    for userId in pairs(room.players) do
        local s = srcOf(userId)
        if s then TriggerClientEvent('m5rp:cl:custom', s, { room = payload }) end
    end
end

function CustomGames.of(userId)
    for _, room in pairs(CustomGames.rooms) do
        if room.players[userId] then return room end
    end
    return nil
end

local function clampSetting(key, value, fallback)
    local lim = Config.CustomGames.limits[key]
    local v = tonumber(value)
    if not v then return fallback end
    if lim then return clamp(v, lim.min, lim.max) end
    return v
end

function CustomGames.create(userId, data)
    if not Config.CustomGames.enabled then return false, 'Custom games are disabled.' end
    local pd = Players[userId]
    if not pd then return false, 'Player not loaded.' end
    if pd.state ~= 'IDLE' then return false, 'Leave your current activity first.' end
    if Bans.check(userId, 'CUSTOM') then return false, 'You are banned from custom games.' end
    if count(CustomGames.rooms) >= Config.CustomGames.maxRooms then
        return false, 'The custom game server is full.'
    end
    if Config.CustomGames.requirePermission
       and not vRP.hasPermission({ userId, Config.Permissions.createCustom }) then
        return false, 'You do not have permission to create custom games.'
    end
    if CustomGames.of(userId) then return false, 'You are already in a room.' end

    data = type(data) == 'table' and data or {}
    local d = Config.CustomGames.defaults

    local mode = Config.Modes[data.mode] and data.mode or d.mode
    local mapId = MapById[data.map] and data.map or d.map

    -- weapon chips picked in the UI (validated against the preset table)
    local weapons = {}
    for _, id in ipairs(type(data.weapons) == 'table' and data.weapons or {}) do
        if PresetById[id] and not inList(weapons, id) then weapons[#weapons + 1] = id end
    end
    if #weapons == 0 then weapons = copy(d.weapons) end

    local matchType = d.matchType
    for _, t in ipairs(Config.CustomGames.matchTypes) do
        if t.id == data.matchType then matchType = t.id end
    end

    local settings = {
        matchType   = matchType,
        weapons     = weapons,
        armorEnabled= data.armorEnabled == true,
        headshotOnly= data.headshotOnly == true,
        rounds      = clampSetting('rounds', data.rounds, d.rounds),
        roundTime   = clampSetting('roundTime', data.roundTime, d.roundTime),
        matchTime   = clampSetting('matchTime', data.matchTime, d.matchTime),
        killLimit   = clampSetting('killLimit', data.killLimit, d.killLimit),
        health      = clampSetting('health', data.health, d.health),
        armor       = clampSetting('armor', data.armor, d.armor),
        movement    = clampSetting('movement', data.movement, d.movement),
        lives       = clampSetting('lives', data.lives, d.lives),
        respawnTime = clampSetting('respawnTime', data.respawnTime, d.respawnTime),
        friendlyFire= data.friendlyFire == true,
        headshotOneShot = data.headshotOneShot ~= false,
        jump        = data.jump ~= false,
        respawn     = data.respawn == true,
        spectators  = data.spectators ~= false,
        teamBalance = data.teamBalance ~= false,
        autoStart   = data.autoStart ~= false,
        minimap     = data.minimap == true,
        vehicles    = data.vehicles == true,
        killcam     = data.killcam == true,
        overtime    = data.overtime ~= false,
        suddenDeath = data.suddenDeath ~= false,
        loadout     = Config.Loadouts[data.loadout] and data.loadout or d.loadout
    }
    settings.roundsToWin = math.ceil((settings.rounds + 1) / 2)

    local ranked = false
    if data.ranked and Config.CustomGames.rankedAllowed then
        ranked = vRP.hasPermission({ userId, Config.CustomGames.rankedPermission })
    end

    local cfg = Config.Modes[mode]
    local room = {
        id        = uid('C'),
        name      = safeName(data.name, Config.CustomGames.roomNameMaxLength),
        password  = safeName(data.password, Config.CustomGames.passwordMaxLength) or '',
        hostId    = userId,
        mode      = mode,
        mapId     = mapId,
        settings  = settings,
        ranked    = ranked,
        maxPlayers= math.min(Config.CustomGames.maxPlayersPerRoom,
                             cfg.type == 'ffa' and (cfg.maxPlayers or 12) or (cfg.teamSize * 2)),
        locked    = data.locked == true,
        state     = 'LOBBY',
        players   = {},
        banned    = {},
        matchId   = nil,
        createdAt = now(),
        lastActivity = now()
    }
    if room.name == '' then room.name = (pd.name .. "'s Room") end

    room.code = newRoomCode()
    CustomGames.byCode[room.code] = room.id

    room.dbId = DB.insert([[INSERT INTO m5_custom_games
        (room_uid, name, host_id, host_name, mode, map_id, ranked, settings, players)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)]],
        { room.id, room.name, userId, pd.name, mode, mapId, ranked and 1 or 0, jsonEncode(settings) })

    CustomGames.rooms[room.id] = room
    CustomGames.join(userId, room.id, room.password)

    Logger.send('customGame', 'Custom Room Created',
        ('**%s** created **%s** (%s / %s)'):format(pd.name, room.name, mode, mapId), pd)
    return true, room.id
end

function CustomGames.join(userId, roomId, password)
    local room = CustomGames.rooms[roomId]
    if not room then return false, 'Room not found.' end
    local pd = Players[userId]
    if not pd then return false, 'Player not loaded.' end
    if room.players[userId] then return true end
    if pd.state ~= 'IDLE' then return false, 'Leave your current activity first.' end
    if Bans.check(userId, 'CUSTOM') then return false, 'You are banned from custom games.' end
    if room.banned[userId] then return false, 'You are banned from this room.' end
    if room.locked and userId ~= room.hostId then return false, 'The room is locked.' end
    if room.password ~= '' and password ~= room.password and userId ~= room.hostId then
        return false, 'Wrong password.'
    end
    if count(room.players) >= room.maxPlayers and not room.settings.spectators then
        return false, 'The room is full.'
    end

    -- auto balance into the smaller team
    local a, b = 0, 0
    for _, e in pairs(room.players) do
        if e.team == 1 then a = a + 1 else b = b + 1 end
    end
    local team = (a <= b) and 1 or 2
    local spectator = count(room.players) >= room.maxPlayers

    room.players[userId] = { team = team, ready = false, name = pd.name, spectator = spectator }
    room.lastActivity = now()
    pd.state = 'CUSTOM'

    DB.update('UPDATE m5_custom_games SET players = ? WHERE id = ?', { count(room.players), room.dbId })
    DB.insert('INSERT INTO m5_custom_game_players (game_id, user_id, name, team) VALUES (?, ?, ?, ?)',
        { room.dbId, userId, pd.name, team })

    CustomGames.sync(room)
    CustomGames.checkAutoStart(room)
    return true
end

--- Join using the short room code shown in the UI.
function CustomGames.joinByCode(userId, code, password)
    code = tostring(code or ''):upper():gsub('%s', '')
    local roomId = CustomGames.byCode[code]
    if not roomId then return false, 'No room with that code.' end
    return CustomGames.join(userId, roomId, password)
end

function CustomGames.leave(userId)
    local room = CustomGames.of(userId)
    if not room then return false end
    room.players[userId] = nil
    room.lastActivity = now()

    local pd = Players[userId]
    if pd and pd.state == 'CUSTOM' and not pd.matchId then pd.state = 'IDLE' end

    local s = srcOf(userId)
    if s then TriggerClientEvent('m5rp:cl:custom', s, { room = false }) end

    if count(room.players) == 0 then
        CustomGames.destroy(room, 'EMPTY')
        return true
    end

    if room.hostId == userId then
        for uidv in pairs(room.players) do
            room.hostId = uidv
            notifyUser(uidv, 'info', 'You are now the room host.', 'CUSTOM GAME')
            break
        end
    end

    CustomGames.sync(room)
    return true
end

function CustomGames.destroy(room, reason)
    if room.matchId and Matches[room.matchId] then
        Match.abort(Matches[room.matchId], reason or 'ROOM_CLOSED')
    end
    for userId in pairs(room.players) do
        local pd = Players[userId]
        if pd and pd.state == 'CUSTOM' then pd.state = 'IDLE' end
        local s = srcOf(userId)
        if s then
            TriggerClientEvent('m5rp:cl:custom', s, { room = false })
            notify(s, 'warning', 'The custom room was closed.', 'CUSTOM GAME')
        end
    end
    DB.update('UPDATE m5_custom_games SET ended_at = ? WHERE id = ?', { sqlDate(), room.dbId })
    if room.code then CustomGames.byCode[room.code] = nil end
    CustomGames.rooms[room.id] = nil
end

--- Host only room management.
function CustomGames.host(userId, action, data)
    local room = CustomGames.of(userId)
    if not room then return false, 'You are not in a room.' end
    if room.hostId ~= userId then return false, 'Only the host can do that.' end
    data = type(data) == 'table' and data or {}
    room.lastActivity = now()

    if action == 'kick' then
        local target = tonumber(data.userId)
        if not target or not room.players[target] then return false, 'Player not in the room.' end
        notifyUser(target, 'warning', 'You were kicked from the room.', 'CUSTOM GAME')
        CustomGames.leave(target)
        return true

    elseif action == 'ban' then
        local target = tonumber(data.userId)
        if not target or not room.players[target] then return false, 'Player not in the room.' end
        room.banned[target] = true
        notifyUser(target, 'error', 'You were banned from the room.', 'CUSTOM GAME')
        CustomGames.leave(target)
        return true

    elseif action == 'move' then
        local target = tonumber(data.userId)
        local team   = tonumber(data.team)
        if not target or not room.players[target] then return false, 'Player not in the room.' end
        if team ~= 1 and team ~= 2 then return false, 'Invalid team.' end
        room.players[target].team = team
        room.players[target].spectator = false
        CustomGames.sync(room)
        return true

    elseif action == 'spectator' then
        local target = tonumber(data.userId)
        if not target or not room.players[target] then return false, 'Player not in the room.' end
        room.players[target].spectator = data.value == true
        CustomGames.sync(room)
        return true

    elseif action == 'lock' then
        room.locked = data.value == true
        CustomGames.sync(room)
        return true

    elseif action == 'map' then
        if not MapById[data.map] then return false, 'Unknown map.' end
        room.mapId = data.map
        CustomGames.sync(room)
        return true

    elseif action == 'mode' then
        if not Config.Modes[data.mode] then return false, 'Unknown mode.' end
        room.mode = data.mode
        local cfg = Config.Modes[data.mode]
        room.maxPlayers = math.min(Config.CustomGames.maxPlayersPerRoom,
            cfg.type == 'ffa' and (cfg.maxPlayers or 12) or (cfg.teamSize * 2))
        CustomGames.sync(room)
        return true

    elseif action == 'settings' then
        local s = room.settings
        local d = data.settings or {}
        s.rounds      = clampSetting('rounds', d.rounds, s.rounds)
        s.roundTime   = clampSetting('roundTime', d.roundTime, s.roundTime)
        s.matchTime   = clampSetting('matchTime', d.matchTime, s.matchTime)
        s.killLimit   = clampSetting('killLimit', d.killLimit, s.killLimit)
        s.health      = clampSetting('health', d.health, s.health)
        s.armor       = clampSetting('armor', d.armor, s.armor)
        s.movement    = clampSetting('movement', d.movement, s.movement)
        s.lives       = clampSetting('lives', d.lives, s.lives)
        s.respawnTime = clampSetting('respawnTime', d.respawnTime, s.respawnTime)
        if d.friendlyFire    ~= nil then s.friendlyFire    = d.friendlyFire == true end
        if d.headshotOneShot ~= nil then s.headshotOneShot = d.headshotOneShot == true end
        if d.jump            ~= nil then s.jump            = d.jump == true end
        if d.respawn         ~= nil then s.respawn         = d.respawn == true end
        if d.spectators      ~= nil then s.spectators      = d.spectators == true end
        if d.teamBalance     ~= nil then s.teamBalance     = d.teamBalance == true end
        if d.autoStart       ~= nil then s.autoStart       = d.autoStart == true end
        if d.minimap         ~= nil then s.minimap         = d.minimap == true end
        if d.vehicles        ~= nil then s.vehicles        = d.vehicles == true end
        if d.killcam         ~= nil then s.killcam         = d.killcam == true end
        if d.overtime        ~= nil then s.overtime        = d.overtime == true end
        if d.suddenDeath     ~= nil then s.suddenDeath     = d.suddenDeath == true end
        if d.loadout and Config.Loadouts[d.loadout] then s.loadout = d.loadout end
        if d.armorEnabled ~= nil then s.armorEnabled = d.armorEnabled == true end
        if d.headshotOnly ~= nil then s.headshotOnly = d.headshotOnly == true end
        if d.matchType then
            for _, t in ipairs(Config.CustomGames.matchTypes) do
                if t.id == d.matchType then s.matchType = t.id end
            end
        end
        if type(d.weapons) == 'table' then
            local picked = {}
            for _, id in ipairs(d.weapons) do
                if PresetById[id] and not inList(picked, id) then picked[#picked + 1] = id end
            end
            if #picked > 0 then s.weapons = picked end
        end
        s.roundsToWin = math.ceil((s.rounds + 1) / 2)
        DB.update('UPDATE m5_custom_games SET settings = ? WHERE id = ?',
            { jsonEncode(s), room.dbId })
        CustomGames.sync(room)
        return true

    elseif action == 'start' then
        return CustomGames.start(room)

    elseif action == 'stop' then
        if room.matchId and Matches[room.matchId] then
            Match.abort(Matches[room.matchId], 'HOST_STOPPED')
        end
        room.state = 'LOBBY'
        room.matchId = nil
        CustomGames.sync(room)
        return true

    elseif action == 'restartRound' then
        local m = room.matchId and Matches[room.matchId]
        if not m then return false, 'No live match.' end
        m.round = m.round - 1
        Match.startRound(m)
        return true

    elseif action == 'transfer' then
        local target = tonumber(data.userId)
        if not target or not room.players[target] then return false, 'Player not in the room.' end
        room.hostId = target
        CustomGames.sync(room)
        return true
    end

    return false, 'Unknown action.'
end

function CustomGames.checkAutoStart(room)
    if not room.settings.autoStart or room.state ~= 'LOBBY' then return end
    local cfg = Config.Modes[room.mode]
    local needed = cfg.type == 'ffa' and (cfg.minPlayers or 4) or (cfg.teamSize * 2)
    local active = 0
    for _, e in pairs(room.players) do
        if not e.spectator then active = active + 1 end
    end
    if active >= needed then CustomGames.start(room) end
end

function CustomGames.start(room)
    if room.state ~= 'LOBBY' then return false, 'The match is already running.' end

    local players = {}
    for userId, e in pairs(room.players) do
        if not e.spectator and Players[userId] then
            players[#players + 1] = { userId = userId, team = e.team }
        end
    end
    if #players < 2 then return false, 'At least two players are required.' end

    -- team balance
    if room.settings.teamBalance and Config.Modes[room.mode].type ~= 'ffa' then
        table.sort(players, function(a, b)
            return (Players[a.userId].mmr or 0) > (Players[b.userId].mmr or 0)
        end)
        for i = 1, #players do
            players[i].team = (i % 2 == 1) and 1 or 2
        end
    end

    local m, reason = Match.create({
        mode       = room.mode,
        ranked     = room.ranked,
        customId   = room.id,
        customDbId = room.dbId,
        settings   = room.settings,
        players    = players
    })
    if not m then return false, reason or 'Could not create the match.' end

    m.map = MapById[room.mapId] or mapsForMode(room.mode)[1]
    if not m.map then
        Match.abort(m, 'NO_MAP')
        return false, 'That map does not support this mode.'
    end

    if m.ffa then
        local i = 0
        for _, mp in pairs(m.players) do i = i + 1; mp.team = i end
    end

    room.state   = 'LIVE'
    room.matchId = m.id
    CustomGames.sync(room)

    Match.beginSetup(m)

    Logger.send('customGame', 'Custom Match Started',
        ('**%s** • %s • %s • %d players'):format(room.name, room.mode, room.mapId, #players))
    return true
end

function CustomGames.onMatchEnd(m)
    local room = CustomGames.rooms[m.customId]
    if not room then return end
    room.state   = 'LOBBY'
    room.matchId = nil
    room.lastActivity = now()

    for userId, mp in pairs(m.players) do
        if room.players[userId] then
            DB.update([[UPDATE m5_custom_game_players SET kills = ?, deaths = ?, headshots = ?, result = ?
                        WHERE game_id = ? AND user_id = ?]],
                { mp.kills, mp.deaths, mp.headshots,
                  mp.team == m.lastWinner and 'WIN' or 'LOSS', room.dbId, userId })
            local pd = Players[userId]
            if pd then pd.state = 'CUSTOM' end
        end
    end
    CustomGames.sync(room)
end

function CustomGames.tick()
    local t = now()
    for id, room in pairs(CustomGames.rooms) do
        if room.state == 'LOBBY' and count(room.players) == 0
           and (t - room.lastActivity) > Config.CustomGames.idleTimeout then
            CustomGames.destroy(room, 'IDLE')
        end
    end
end

-- ============================================================================
-- 15. TRAINING
-- ============================================================================

local Training = { players = {} }

function Training.start(userId, kind)
    if not Config.Training.enabled then return false, 'Training is disabled.' end
    local pd = Players[userId]
    if not pd or pd.state ~= 'IDLE' then return false, 'Leave your current activity first.' end

    local mode = Config.Training.modes[kind] or Config.Training.modes.range
    local s = srcOf(userId)
    if not s then return false end

    pd.state = 'TRAINING'
    Training.players[userId] = { kind = kind, startedAt = now() }

    SetPlayerRoutingBucket(s, Config.Training.bucket)
    configureBucket(Config.Training.bucket)

    local base = Config.Loadouts[Config.Training.loadout] or Config.Loadouts.training
    TriggerClientEvent('m5rp:cl:training', s, {
        enable  = true,
        kind    = kind,
        label   = mode.label,
        spawn   = { x = Config.Training.spawn.x, y = Config.Training.spawn.y,
                    z = Config.Training.spawn.z, h = Config.Training.spawn.w },
        loadout = { health = base.health, armor = base.armor, weapons = base.weapons },
        targets = mode.targets, spacing = mode.spacing, time = mode.time,
        headshotOneShot = Config.Headshot.enabledInTraining and Config.Headshot.oneShotKill
    })
    return true
end

function Training.stop(userId)
    local pd = Players[userId]
    Training.players[userId] = nil
    if pd and pd.state == 'TRAINING' then pd.state = 'IDLE' end
    local s = srcOf(userId)
    if s then
        SetPlayerRoutingBucket(s, 0)
        TriggerClientEvent('m5rp:cl:training', s, { enable = false })
    end
    return true
end

-- ============================================================================
-- 15b. BOT MATCH  (staff only, never ranked)
-- ============================================================================
--
-- Runs the real match presentation for one player against local AI peds. The
-- server owns the session: rounds, score, timers, the win condition and every
-- transition. The client owns only what a server cannot do — creating peds and
-- giving them combat AI — and reports the two outcomes it alone can observe:
-- a bot went down, or the round timed out on its side.
--
-- Those reports are not provable, which is exactly why nothing is at stake: a
-- bot match writes no RP, no MMR, no stats and no match row, and only staff
-- holding the action's permission can start one.

local BotMatch = { sessions = {} }   -- [userId] = session

local function botDifficulty(key)
    local d = Config.BotMatch.bots.difficulties
    return d[key] or d[Config.BotMatch.bots.defaultDifficulty] or d.normal
end

--- The map a bot match runs on: the requested one, the configured default, or
--- the first map that supports 1v1.
local function botMap(requested)
    local m = requested and MapById[requested]
    if m then return m end
    m = Config.BotMatch.defaultMap and MapById[Config.BotMatch.defaultMap]
    if m then return m end
    local list = mapsForMode('1v1')
    return list[1] or Config.Maps[1]
end

local function botPush(sess, event, payload)
    local s = srcOf(sess.userId)
    if s then TriggerClientEvent(event, s, payload) end
end

--- Score line for the HUD and the end screen.
local function botScoreboard(sess)
    local pd = Players[sess.userId]
    return {
        {
            userId = sess.userId, serverId = srcOf(sess.userId),
            name = pd and pd.name or 'PLAYER', team = 1,
            kills = sess.kills, deaths = sess.deaths, assists = 0,
            headshots = sess.headshots, damage = sess.damage or 0,
            score = sess.kills * 100,
            rank = pd and Rank.get(pd.rankId).name or '',
            avatar = avatarFor(sess.userId),
            alive = sess.alive, connected = true, ping = 0
        },
        {
            userId = -1, serverId = nil,
            name = Config.BotMatch.bots.namePrefix .. ' TEAM', team = 2,
            kills = sess.deaths, deaths = sess.kills, assists = 0,
            headshots = 0, damage = 0, score = sess.deaths * 100,
            -- no avatar for the bot side: the initial reads better than the
            -- default Discord logo repeated on every row
            rank = sess.difficulty.label, avatar = nil,
            alive = sess.botsAlive > 0, connected = true, ping = 0
        }
    }
end

local function botHud(sess, throttle)
    -- the live state pushes every tick; one update a second is plenty
    if throttle then
        if sess.lastHud and (ms() - sess.lastHud) < 1000 then return end
        sess.lastHud = ms()
    else
        sess.lastHud = ms()
    end

    botPush(sess, 'm5rp:cl:hud', {
        state = sess.state,
        alive = sess.alive,
        round = sess.round,
        rounds = sess.rounds,
        scores = { a = sess.scores[1], b = sess.scores[2] },
        teamA = Players[sess.userId] and Players[sess.userId].name or 'YOU',
        teamB = ('%s x%d'):format(Config.BotMatch.bots.namePrefix, sess.botCount),
        aliveA = sess.alive and 1 or 0,
        aliveB = sess.botsAlive,
        maxRounds = sess.rounds,
        time = sess.stateEnd and math.max(0, sess.stateEnd - now()) or 0,
        botsAlive = sess.botsAlive,
        scoreboard = botScoreboard(sess)
    })
end

--- Spawns (or respawns) the bots and puts the player on the opposite side.
local function botBeginRound(sess)
    sess.round     = sess.round + 1
    sess.alive     = true
    sess.botsAlive = sess.botCount
    sess.state     = 'COUNTDOWN'
    sess.stateEnd  = now() + Config.BotMatch.countdown

    local map  = sess.map
    local mine = (map.teamA and map.teamA[1]) or map.spectator
    local diff = sess.difficulty

    -- player side
    local base = Config.Loadouts[Config.BotMatch.loadout] or Config.Loadouts.duel
    botPush(sess, 'm5rp:cl:round', {
        matchId = sess.id, phase = 'spawn', freeze = true,
        spawn = { x = mine.x, y = mine.y, z = mine.z, h = mine.w },
        loadout = { health = base.health, armor = base.armor, weapons = base.weapons },
        protection = 0
    })

    -- bot side: the client creates the peds at these points
    local spots = {}
    local pool  = map.teamB or map.teamA or {}
    for i = 1, sess.botCount do
        local p = pool[((i - 1) % math.max(1, #pool)) + 1]
        if p then spots[#spots + 1] = { x = p.x, y = p.y, z = p.z, h = p.w } end
    end

    botPush(sess, 'm5rp:cl:bots', {
        matchId = sess.id,
        spawn   = true,
        round   = sess.round,
        model   = Config.BotMatch.bots.model,
        namePrefix = Config.BotMatch.bots.namePrefix,
        spots   = spots,
        bot     = {
            health = diff.health, armor = diff.armor, accuracy = diff.accuracy,
            reaction = diff.reaction, weapon = diff.weapon,
            combatMovement = diff.combatMovement, alertness = diff.alertness
        },
        headshotOneShot = Config.BotMatch.headshotOneShot and Config.Headshot.oneShotKill
    })

    botPush(sess, 'm5rp:cl:round', {
        matchId = sess.id, phase = 'countdown', round = sess.round,
        seconds = Config.BotMatch.countdown, scores = sess.scores
    })
    botHud(sess)
end

local function botGoLive(sess)
    sess.state    = 'LIVE'
    sess.stateEnd = Config.BotMatch.roundTime > 0
                    and (now() + Config.BotMatch.roundTime) or nil
    botPush(sess, 'm5rp:cl:bots', { matchId = sess.id, release = true })
    botPush(sess, 'm5rp:cl:round', {
        matchId = sess.id, phase = 'live', round = sess.round,
        time = Config.BotMatch.roundTime
    })
    botHud(sess)
end

--- Ends the current round. `winner` is 1 for the player, 2 for the bots,
--- 0 for a draw.
local function botEndRound(sess, winner, reason)
    if sess.state == 'ROUND_END' or sess.state == 'MATCH_END' then return end

    if winner == 1 or winner == 2 then sess.scores[winner] = sess.scores[winner] + 1 end

    sess.state    = 'ROUND_END'
    sess.stateEnd = now() + Config.BotMatch.roundEndDelay

    botPush(sess, 'm5rp:cl:bots', { matchId = sess.id, clear = true })
    botPush(sess, 'm5rp:cl:round', {
        matchId = sess.id, phase = 'end', round = sess.round,
        winner = winner, reason = reason, scores = sess.scores,
        scoreboard = botScoreboard(sess)
    })
    botHud(sess)
end

function BotMatch.finish(sess, reason)
    if sess.state == 'MATCH_END' then return end
    sess.state    = 'MATCH_END'
    sess.stateEnd = now() + Config.BotMatch.endDelay

    local winner = sess.scores[1] > sess.scores[2] and 1
                or (sess.scores[2] > sess.scores[1] and 2 or 0)

    local pd = Players[sess.userId]

    botPush(sess, 'm5rp:cl:bots', { matchId = sess.id, clear = true })
    -- Exactly the shape a real match sends. It used to differ in three ways —
    -- WIN/LOSS instead of VICTORY/DEFEAT, scores as {[1],[2]} instead of
    -- {a,b}, and no stats block — so the result screen showed an untranslated
    -- word, an empty score and five zeroes.
    botPush(sess, 'm5rp:cl:end', {
        matchId  = sess.id,
        winner   = winner,
        yourTeam = 1,
        result   = winner == 1 and 'VICTORY' or (winner == 2 and 'DEFEAT' or 'DRAW'),
        reason   = reason or 'COMPLETE',
        ranked   = false,
        practice = true,
        scores   = { a = sess.scores[1], b = sess.scores[2] },
        teamA    = pd and pd.name or 'YOU',
        teamB    = ('%s x%d'):format(Config.BotMatch.bots.namePrefix, sess.botCount),
        stats    = {
            kills = sess.kills, deaths = sess.deaths, assists = 0,
            headshots = sess.headshots, damage = sess.damage or 0,
            score = sess.kills * 100, clutches = 0
        },
        scoreboard = botScoreboard(sess),
        rp  = nil,
        mvp = nil
    })
end

--- Tears the session down and puts the player back in the world.
function BotMatch.stop(userId, reason)
    local sess = BotMatch.sessions[userId]
    if not sess then return false, 'No bot match is running.' end

    BotMatch.sessions[userId] = nil
    UsedBuckets[sess.bucket] = nil

    local pd = Players[userId]
    if pd and pd.state == 'BOTMATCH' then
        pd.state    = 'IDLE'
        pd.matchId  = nil
        pd.team     = 0
    end

    local s = srcOf(userId)
    if s then
        TriggerClientEvent('m5rp:cl:bots', s, { matchId = sess.id, clear = true })
        TriggerClientEvent('m5rp:cl:cleanup', s, { matchId = sess.id })
        SetPlayerRoutingBucket(s, 0)
    end

    if Config.BotMatch.logToWebhook then
        Logger.send('adminActions', 'Bot Match Ended', nil, pd, {
            { name = 'Result', value = ('%d - %d'):format(sess.scores[1], sess.scores[2]) },
            { name = 'Rounds', value = tostring(sess.round) },
            { name = 'Difficulty', value = sess.difficultyKey },
            { name = 'Reason', value = reason or 'stopped' }
        })
    end
    return true
end

function BotMatch.start(pd, opts)
    if not Config.BotMatch.enabled then return false, 'Bot matches are disabled.' end
    if not pd then return false, 'Player not found.' end
    if BotMatch.sessions[pd.userId] then return false, 'You are already in a bot match.' end
    if pd.state ~= 'IDLE' then return false, 'Leave your current activity first.' end

    local s = srcOf(pd.userId)
    if not s then return false, 'You must be in game to start one.' end

    opts = opts or {}
    local diffKey = Config.BotMatch.bots.difficulties[opts.difficulty]
                    and opts.difficulty or Config.BotMatch.bots.defaultDifficulty
    local count = math.floor(tonumber(opts.bots) or Config.BotMatch.bots.count)
    count = clamp(count, 1, Config.BotMatch.maxBots)

    local rounds = math.floor(tonumber(opts.rounds) or Config.BotMatch.rounds)
    rounds = clamp(rounds, 1, 15)

    local map = botMap(opts.map)
    if not map then return false, 'No map is available.' end

    -- Each session needs its own world. Sharing one bucket would drop two
    -- admins practising at the same time into each other's match.
    local bucket
    for b = Config.BotMatch.bucket, Config.BotMatch.bucket + 63 do
        if not UsedBuckets[b] then bucket = b break end
    end
    if not bucket then return false, 'No free routing bucket for a bot match.' end

    local sess = {
        id        = uid('B'),
        userId    = pd.userId,
        bucket    = bucket,
        map       = map,
        rounds    = rounds,
        -- best of N: 1->1, 3->2, 5->3, 7->4. Derived from the chosen round
        -- count rather than the config, which would cap a 7 round pick at 3.
        roundsToWin = math.floor(rounds / 2) + 1,
        botCount  = count,
        botsAlive = 0,
        difficultyKey = diffKey,
        difficulty = botDifficulty(diffKey),
        round     = 0,
        scores    = { [1] = 0, [2] = 0 },
        kills = 0, deaths = 0, headshots = 0, damage = 0,
        alive     = false,
        state     = 'WAITING',
        stateEnd  = now() + 2,
        startedAt = now()
    }
    BotMatch.sessions[pd.userId] = sess
    UsedBuckets[sess.bucket] = sess.id

    pd.state   = 'BOTMATCH'
    pd.matchId = nil
    pd.team    = 1

    SetPlayerRoutingBucket(s, sess.bucket)
    configureBucket(sess.bucket)

    TriggerClientEvent('m5rp:cl:setup', s, {
        matchId   = sess.id,
        mode      = '1v1',
        modeLabel = ('BOT MATCH · %s'):format(sess.difficulty.label),
        modeType  = 'team',
        ranked    = false,
        custom    = true,
        practice  = true,
        ffa       = false,
        team      = 1,
        map = { id = map.id, name = map.name, image = map.image,
                center = { x = map.center.x, y = map.center.y, z = map.center.z },
                radius = map.radius },
        roster = {
            { userId = pd.userId, name = pd.name, team = 1, rank = Rank.get(pd.rankId).name },
            { userId = -1, name = ('%s x%d'):format(Config.BotMatch.bots.namePrefix, count),
              team = 2, rank = sess.difficulty.label }
        },
        settings = {
            friendlyFire    = false,
            minimap         = false,
            movement        = 1.0,
            jump            = true,
            headshotOneShot = Config.BotMatch.headshotOneShot and Config.Headshot.oneShotKill,
            headshotOnly    = false,
            matchType       = 'normal',
            respawn         = false,
            spawnProtection = 0,
            roundsToWin     = sess.roundsToWin,
            killLimit       = 0,
            boundaryWarning = Config.Match.boundary.warningTime
        }
    })

    log('bot match started: user %d, %d bot(s), %s, map %s',
        pd.userId, count, diffKey, map.id)
    return true, {
        rounds = rounds, bots = count, difficulty = sess.difficulty.label, map = map.name
    }
end

--- The player died. Called from the combat path, which already owns deaths.
function BotMatch.playerDied(userId)
    local sess = BotMatch.sessions[userId]
    if not sess or sess.state ~= 'LIVE' then return false end
    sess.alive  = false
    sess.deaths = sess.deaths + 1

    botPush(sess, 'm5rp:cl:killfeed', {
        killer = Config.BotMatch.bots.namePrefix, killerTeam = 2,
        victim = Players[userId] and Players[userId].name or 'YOU', victimTeam = 1,
        headshot = false
    })
    botEndRound(sess, 2, 'ELIMINATION')
    return true
end

--- A bot went down. Only the starting client can observe this.
function BotMatch.botDown(userId, headshot)
    local sess = BotMatch.sessions[userId]
    if not sess or sess.state ~= 'LIVE' then return false end
    if sess.botsAlive <= 0 then return false end

    sess.botsAlive = sess.botsAlive - 1
    sess.kills     = sess.kills + 1
    if headshot then sess.headshots = sess.headshots + 1 end
    -- The server cannot measure damage to a ped that lives on one client, so
    -- this counts the health pool actually destroyed rather than inventing a
    -- number. It is a practice session; nothing is recorded from it.
    sess.damage = (sess.damage or 0)
                + (sess.difficulty.health or 0) + (sess.difficulty.armor or 0)

    botPush(sess, 'm5rp:cl:killfeed', {
        killer = Players[userId] and Players[userId].name or 'YOU', killerTeam = 1,
        victim = Config.BotMatch.bots.namePrefix, victimTeam = 2,
        headshot = headshot == true
    })

    if sess.botsAlive <= 0 then
        botEndRound(sess, 1, 'ELIMINATION')
    else
        botHud(sess)
    end
    return true
end

--- Drives every running session. Called from the master loop.
function BotMatch.tick()
    for userId, sess in pairs(BotMatch.sessions) do
        local s = srcOf(userId)
        if not s then
            BotMatch.stop(userId, 'disconnected')
        elseif sess.stateEnd and now() >= sess.stateEnd then
            if sess.state == 'WAITING' then
                botBeginRound(sess)
            elseif sess.state == 'COUNTDOWN' then
                botGoLive(sess)
            elseif sess.state == 'LIVE' then
                botEndRound(sess, 0, 'TIME')          -- nobody closed it out
            elseif sess.state == 'ROUND_END' then
                local done = sess.scores[1] >= sess.roundsToWin
                          or sess.scores[2] >= sess.roundsToWin
                          or sess.round >= sess.rounds
                if done then BotMatch.finish(sess, 'COMPLETE') else botBeginRound(sess) end
            elseif sess.state == 'MATCH_END' then
                BotMatch.stop(userId, 'finished')
            end
        elseif sess.state == 'LIVE' then
            botHud(sess, true)
        end
    end
end

-- ============================================================================
-- 15c. STORE — cards and titles
-- ============================================================================
--
-- Cosmetics only: a card is the banner behind the lobby slot, a title is a
-- word beside the name. Neither touches gameplay.
--
-- Prices, ownership and the balance live here. The client sends nothing but
-- "buy this id" / "equip this id" — it never sends a price, never sends a
-- balance, and cannot equip something it does not own.

Store = { cache = {} }   -- [userId] = { coins, <kind> = id, owned = { kind = {id=true} } }

-- Every kind the store sells, in one place. Adding another is a line here plus
-- a list in the config and a column on m5_player_store — nothing below this
-- knows the difference between a card and a frame.
local STORE_KINDS = {
    { kind = 'card',   list = 'cards',   column = 'card',   fallback = 'default' },
    { kind = 'title',  list = 'titles',  column = 'title',  fallback = 'none' },
    { kind = 'effect', list = 'effects', column = 'effect', fallback = 'none' },
    { kind = 'frame',  list = 'frames',  column = 'frame',  fallback = 'none' },
    { kind = 'avatar', list = 'avatars', column = 'avatar', fallback = 'none' }
}

local StoreById = {}          -- [kind][id] = def
local StoreKind = {}          -- [kind] = the entry above
for _, k in ipairs(STORE_KINDS) do
    StoreKind[k.kind] = k
    StoreById[k.kind] = {}
    for _, def in ipairs(Config.Store[k.list] or {}) do
        StoreById[k.kind][def.id] = def
    end
end

local function storeDef(kind, id)
    local by = StoreById[kind]
    return by and by[id] or nil
end

local function storeList(kind)
    local k = StoreKind[kind]
    return k and (Config.Store[k.list] or {}) or {}
end

--- Anything priced at 0, and anything flagged default, belongs to everyone.
local function isFree(def)
    return def and (def.default == true or (tonumber(def.price) or 0) <= 0)
end

function Store.load(userId)
    if Store.cache[userId] then return Store.cache[userId] end

    local row = DB.single('SELECT * FROM m5_player_store WHERE user_id = ?', { userId })
    if not row then
        DB.insert('INSERT IGNORE INTO m5_player_store (user_id, coins) VALUES (?, ?)',
            { userId, Config.Store.currency.starting or 0 })
        row = { coins = Config.Store.currency.starting or 0 }
    end

    local owned = {}
    for _, k in ipairs(STORE_KINDS) do owned[k.kind] = {} end

    local rows = DB.query('SELECT kind, item_id FROM m5_player_items WHERE user_id = ?',
        { userId }) or {}
    for i = 1, #rows do
        local k = tostring(rows[i].kind)
        if owned[k] then owned[k][tostring(rows[i].item_id)] = true end
    end

    -- free items are never written to the table; they are simply always owned
    for _, k in ipairs(STORE_KINDS) do
        for _, def in ipairs(storeList(k.kind)) do
            if isFree(def) then owned[k.kind][def.id] = true end
        end
    end

    local data = { coins = math.max(0, tonumber(row.coins) or 0), owned = owned }
    for _, k in ipairs(STORE_KINDS) do
        local want = row[k.column]
        data[k.kind] = storeDef(k.kind, want) and want or k.fallback
    end
    Store.cache[userId] = data
    return data
end

function Store.forget(userId)
    Store.cache[userId] = nil
end

--- The payload the Store page renders from. Prices come from here, never from
--- the client, and `owned` is what decides whether BUY or EQUIP is shown.
function Store.payload(userId)
    local d = Store.load(userId)

    local function pack(kind)
        local out = {}
        for _, def in ipairs(storeList(kind)) do
            local rarity = Config.Store.rarities[def.rarity or 'common']
                        or Config.Store.rarities.common
            out[#out + 1] = {
                id = def.id, name = def.name,
                rarity = def.rarity or 'common',
                rarityLabel = rarity and rarity.label or 'COMMON',
                rarityColor = rarity and rarity.color or '#8B93A3',
                price = tonumber(def.price) or 0,
                image = def.image or '',
                color = def.color,
                color2 = def.color2,
                -- how it is drawn; the interface builds the rest from these
                anim = def.anim, speed = def.speed,
                style = def.style, width = def.width, art = def.art,
                glow = def.glow, animated = def.animated == true,
                owned = d.owned[kind][def.id] == true,
                equipped = d[kind] == def.id
            }
        end
        return out
    end

    local out = {
        enabled  = Config.Store.enabled,
        currency = Config.Store.currency.label or 'COINS',
        coins    = d.coins
    }
    for _, k in ipairs(STORE_KINDS) do
        out[k.list]     = pack(k.kind)   -- cards, titles, effects, frames
        out['equipped' .. k.kind] = d[k.kind]
    end
    return out
end

--- Writes the wallet and the equipped pair. Small and rare, so it goes
--- straight through rather than waiting for the batch flush.
local function storeSave(userId)
    local d = Store.cache[userId]
    if not d then return end

    local cols, marks, upd, args = { 'user_id', 'coins' }, { '?', '?' },
                                   { 'coins = VALUES(coins)' }, { userId, d.coins }
    for _, k in ipairs(STORE_KINDS) do
        cols[#cols + 1]  = k.column
        marks[#marks + 1] = '?'
        upd[#upd + 1]    = ('%s = VALUES(%s)'):format(k.column, k.column)
        args[#args + 1]  = d[k.kind]
    end

    DB.write(('INSERT INTO m5_player_store (%s) VALUES (%s) ON DUPLICATE KEY UPDATE %s')
        :format(table.concat(cols, ', '), table.concat(marks, ','), table.concat(upd, ', ')),
        args)
end

--- Adds (or removes, with a negative amount) coins. Returns the new balance.
function Store.addCoins(userId, amount)
    local d = Store.load(userId)
    local max = Config.Store.currency.max or 10000000
    d.coins = clamp(math.floor(d.coins + (tonumber(amount) or 0)), 0, max)
    storeSave(userId)
    return d.coins
end

function Store.buy(userId, kind, id)
    if not Config.Store.enabled then return false, 'The store is closed.' end
    if not StoreKind[kind] then return false, 'Unknown item.' end

    local def = storeDef(kind, id)
    if not def then return false, 'Unknown item.' end

    local d = Store.load(userId)
    if d.owned[kind][id] then return false, 'You already own that.' end

    local price = tonumber(def.price) or 0
    if price <= 0 then return false, 'Unknown item.' end
    if d.coins < price then return false, 'Not enough coins.' end

    d.coins = d.coins - price
    d.owned[kind][id] = true

    DB.write([[INSERT IGNORE INTO m5_player_items (user_id, kind, item_id, price_paid)
               VALUES (?,?,?,?)]], { userId, kind, id, price })
    storeSave(userId)

    log('store: user %d bought %s "%s" for %d', userId, kind, id, price)
    return true, { coins = d.coins, kind = kind, id = id }
end

function Store.equip(userId, kind, id)
    if not StoreKind[kind] then return false, 'Unknown item.' end

    local def = storeDef(kind, id)
    if not def then return false, 'Unknown item.' end

    local d = Store.load(userId)
    if not d.owned[kind][id] then return false, 'You do not own that.' end

    d[kind] = id
    storeSave(userId)
    return true, { kind = kind, id = id }
end

--- What other players see: the equipped cosmetics, resolved for display.
function Store.cosmetics(userId)
    local d = Store.cache[userId]
    if not d then return nil end

    local card   = storeDef('card',   d.card)
    local title  = storeDef('title',  d.title)
    local effect = storeDef('effect', d.effect)
    local frame  = storeDef('frame',  d.frame)
    local avatar = storeDef('avatar', d.avatar)

    -- A frame and an avatar decoration are the same recipe worn in two
    -- places, so they are packed the same way and the interface only has to
    -- learn it once.
    local function worn(def)
        if not def or def.id == 'none' then return nil end
        return {
            style    = def.style or 'solid',
            art      = def.art,
            color    = def.color,
            color2   = def.color2,
            width    = def.width,
            glow     = def.glow,
            animated = def.animated == true or nil,
            speed    = def.speed
        }
    end

    return {
        card      = d.card,
        cardImage = card and card.image or '',
        title     = (title and title.id ~= 'none') and title.name or nil,
        titleColor= title and title.color or nil,
        -- The interface draws both itself, so it gets the recipe rather than
        -- an id it would have to know the meaning of. A frame nobody has
        -- written CSS for still works: it is only numbers and colours.
        effect       = (effect and effect.id ~= 'none') and (effect.anim or effect.id) or nil,
        effectColor  = effect and effect.color or nil,
        effectColor2 = effect and effect.color2 or nil,
        effectSpeed  = effect and effect.speed or nil,

        -- the border round the card, and the decoration round the portrait:
        -- two separate slots, bought and worn on their own
        frame        = worn(frame),
        avatar       = worn(avatar)
    }
end

-- ============================================================================
-- 16. REWARDS / XP / MISSIONS / ACHIEVEMENTS
-- ============================================================================

Rewards = {}

local function xpForLevel(level)
    local L = Config.Rewards.levels
    return math.floor(L.baseXP * (L.growth ^ (level - 1)))
end

--- Grants a single reward payload. Everything happens server side.
function Rewards.grant(pd, reward, seasonId, rewardKey)
    if not pd or type(reward) ~= 'table' then return false end
    local key = rewardKey or ('%s_%s'):format(reward.type, tostring(reward.value))

    if Config.Rewards.uniquePerSeason then
        local exists = DB.scalar(
            'SELECT COUNT(*) FROM m5_player_rewards WHERE user_id = ? AND reward_key = ? AND season_id = ?',
            { pd.userId, key, seasonId or 0 })
        if (tonumber(exists) or 0) > 0 then return false end
    end

    local applied = false
    if reward.type == 'money' then
        applied = vRP.giveMoney({ pd.userId, tonumber(reward.value) or 0 })
    elseif reward.type == 'item' or reward.type == 'weapon' then
        applied = vRP.giveInventoryItem({ pd.userId, reward.value, reward.amount or 1, true })
    elseif reward.type == 'group' then
        applied = vRP.addUserGroup({ pd.userId, reward.value })
    elseif reward.type == 'title' then
        if not inList(pd.titles, reward.value) then
            pd.titles[#pd.titles + 1] = reward.value
            pd.dirtyPlayer = true
        end
        applied = true
    elseif reward.type == 'badge' then
        if not inList(pd.badges, reward.value) then
            pd.badges[#pd.badges + 1] = reward.value
            pd.dirtyPlayer = true
        end
        applied = true
    elseif reward.type == 'frame' then
        pd.frame = reward.value
        pd.dirtyPlayer = true
        applied = true
    elseif reward.type == 'effect' or reward.type == 'vehicle' then
        -- stored for the player to claim from the rewards tab
        applied = true
    end

    DB.insert([[INSERT INTO m5_player_rewards (user_id, reward_key, season_id, type, value, claimed, claimed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE claimed = VALUES(claimed)]],
        { pd.userId, key, seasonId or 0, reward.type, jsonEncode(reward),
          applied and 1 or 0, applied and sqlDate() or nil })

    return applied
end

function Rewards.addXP(pd, amount)
    if not Config.Rewards.levels.enabled or amount <= 0 then return end
    local L = Config.Rewards.levels
    pd.xp = pd.xp + amount
    pd.dirtyPlayer = true

    local leveled = false
    while pd.level < L.maxLevel and pd.xp >= xpForLevel(pd.level) do
        pd.xp = pd.xp - xpForLevel(pd.level)
        pd.level = pd.level + 1
        leveled = true

        local rewards = L.levelRewards[pd.level]
        if rewards then
            for i = 1, #rewards do
                Rewards.grant(pd, rewards[i], 0, ('level_%d_%d'):format(pd.level, i))
            end
        end
    end

    if leveled then
        notifyUser(pd.userId, 'success', 'You reached level %d', 'LEVEL UP', pd.level)
    end
end

--- Called from Match.finalize for every participant.
function Match.grantMatchRewards(m, pd, mp, won, draw, isMVP)
    if not Config.Rewards.enabled then return end
    local R = Config.Rewards.perMatch

    if m.ranked then
        local money = won and R.winMoney or R.lossMoney
        if isMVP then money = money + R.mvpMoney end
        if money > 0 then vRP.giveMoney({ pd.userId, money }) end
    end

    local xp = (won and R.xpWin or R.xpLoss)
             + mp.kills * R.xpPerKill
             + mp.headshots * R.xpPerHeadshot
             + (isMVP and R.xpMVP or 0)
             + (mp.pendingXP or 0)
    Rewards.addXP(pd, xp)

    Missions.progress(pd, {
        matches = 1,
        wins = won and 1 or 0,
        kills = mp.kills,
        headshots = mp.headshots,
        damage = math.floor(mp.damage),
        mvp = isMVP and 1 or 0
    })

    Achievements.check(pd)
end

-- ---------------------------------------------------------------------------
-- Missions
-- ---------------------------------------------------------------------------

Missions = {}

local function dailyPeriod() return os.date('!%Y%m%d') end
local function weeklyPeriod() return os.date('!%Y-W%W') end

function Missions.ensure(pd)
    if not Config.Missions.enabled then return end
    for _, kind in ipairs({ 'daily', 'weekly' }) do
        local cfg = Config.Missions[kind]
        local period = kind == 'daily' and dailyPeriod() or weeklyPeriod()

        local rows = DB.query('SELECT * FROM m5_player_missions WHERE user_id = ? AND kind = ? AND period = ?',
            { pd.userId, kind, period }) or {}
        if #rows == 0 then
            local pool = copy(cfg.pool)
            shuffle(pool)
            for i = 1, math.min(cfg.count, #pool) do
                DB.insert([[INSERT IGNORE INTO m5_player_missions
                    (user_id, mission_key, kind, progress, target, period) VALUES (?, ?, ?, 0, ?, ?)]],
                    { pd.userId, pool[i].key, kind, pool[i].target, period })
            end
        end
    end
end

function Missions.list(userId)
    local out = { daily = {}, weekly = {} }
    if not Config.Missions.enabled then return out end

    for _, kind in ipairs({ 'daily', 'weekly' }) do
        local period = kind == 'daily' and dailyPeriod() or weeklyPeriod()
        local rows = DB.query('SELECT * FROM m5_player_missions WHERE user_id = ? AND kind = ? AND period = ?',
            { userId, kind, period }) or {}
        for i = 1, #rows do
            local r = rows[i]
            local def
            for _, entry in ipairs(Config.Missions[kind].pool) do
                if entry.key == r.mission_key then def = entry break end
            end
            out[kind][#out[kind] + 1] = {
                key = r.mission_key,
                label = def and def.label or r.mission_key,
                progress = r.progress, target = r.target,
                completed = toBool(r.completed), claimed = toBool(r.claimed),
                xp = def and def.xp or 0, money = def and def.money or 0
            }
        end
    end
    return out
end

function Missions.progress(pd, deltas)
    if not Config.Missions.enabled then return end
    Missions.ensure(pd)

    for _, kind in ipairs({ 'daily', 'weekly' }) do
        local period = kind == 'daily' and dailyPeriod() or weeklyPeriod()
        local rows = DB.query('SELECT * FROM m5_player_missions WHERE user_id = ? AND kind = ? AND period = ? AND completed = 0',
            { pd.userId, kind, period }) or {}

        for i = 1, #rows do
            local r = rows[i]
            local def
            for _, entry in ipairs(Config.Missions[kind].pool) do
                if entry.key == r.mission_key then def = entry break end
            end
            if def and deltas[def.stat] and deltas[def.stat] > 0 then
                local value = math.min(r.target, r.progress + deltas[def.stat])
                local done  = value >= r.target
                DB.update('UPDATE m5_player_missions SET progress = ?, completed = ? WHERE id = ?',
                    { value, done and 1 or 0, r.id })
                if done then
                    Rewards.addXP(pd, def.xp or 0)
                    if def.money and def.money > 0 then vRP.giveMoney({ pd.userId, def.money }) end
                    DB.update('UPDATE m5_player_missions SET claimed = 1 WHERE id = ?', { r.id })
                    notifyUser(pd.userId, 'success',
                        ('Mission complete: %s'):format(def.label), 'MISSION')
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Achievements
-- ---------------------------------------------------------------------------

Achievements = {}

function Achievements.check(pd)
    local unlocked = DB.query('SELECT achievement FROM m5_player_achievements WHERE user_id = ?',
        { pd.userId }) or {}
    local have = {}
    for i = 1, #unlocked do have[unlocked[i].achievement] = true end

    for i = 1, #Config.Achievements do
        local a = Config.Achievements[i]
        if not have[a.key] then
            local value = pd.stats[a.stat] or 0
            if value >= a.target then
                DB.insert('INSERT IGNORE INTO m5_player_achievements (user_id, achievement) VALUES (?, ?)',
                    { pd.userId, a.key })
                Rewards.addXP(pd, a.xp or 0)
                notifyUser(pd.userId, 'success', 'Achievement unlocked: %s', 'ACHIEVEMENT', a.label)
            end
        end
    end
end

function Achievements.list(userId)
    local rows = DB.query('SELECT achievement, unlocked_at FROM m5_player_achievements WHERE user_id = ?',
        { userId }) or {}
    local have = {}
    for i = 1, #rows do have[rows[i].achievement] = rows[i].unlocked_at end

    local out = {}
    for i = 1, #Config.Achievements do
        local a = Config.Achievements[i]
        out[#out + 1] = {
            key = a.key, label = a.label, desc = a.desc,
            unlocked = have[a.key] ~= nil, at = have[a.key]
        }
    end
    return out
end

-- ============================================================================
-- 17. ANTI BOOSTING
-- ============================================================================

AntiBoost = {}

function AntiBoost.flag(userId, kind, severity, details, matchId, targetId)
    if not Config.AntiBoost.enabled then return end
    local pd = Players[userId]
    DB.insert([[INSERT INTO m5_anti_boost_flags
        (user_id, name, target_id, type, severity, details, match_id) VALUES (?, ?, ?, ?, ?, ?, ?)]],
        { userId, pd and pd.name or '', targetId or 0, kind, severity or 1,
          jsonEncode(details or {}), matchId or 0 })

    Logger.send('antiBoost', 'Anti-Boost Flag',
        ('Detector **%s** (severity %d)'):format(kind, severity or 1), pd, {
            { name = 'Details', value = ('```%s```'):format(jsonEncode(details or {}):sub(1, 900)), inline = false }
        })
end

--- Runs the detector suite over the player's recent history.
function AntiBoost.analyse(userId, m)
    if not Config.AntiBoost.enabled then return end
    local D = Config.AntiBoost.detectors
    local sample = Config.AntiBoost.sampleSize

    local rows = DB.query([[SELECT mp.*, mt.duration, mt.id AS mid, mt.ended_at
                            FROM m5_match_players mp
                            JOIN m5_matches mt ON mt.id = mp.match_id
                            WHERE mp.user_id = ? AND mt.ranked = 1
                            ORDER BY mp.match_id DESC LIMIT ?]], { userId, sample }) or {}
    if #rows < 5 then return end

    local matchIds = {}
    for i = 1, #rows do matchIds[#matchIds + 1] = rows[i].match_id end

    -- ---- repeated opponents ------------------------------------------------
    if D.repeatedOpponent.enabled and #matchIds > 0 then
        local placeholders = string.rep('?,', #matchIds - 1) .. '?'
        local params = {}
        for i = 1, #matchIds do params[i] = matchIds[i] end
        params[#params + 1] = userId

        local opp = DB.query(([[SELECT user_id, COUNT(*) AS n FROM m5_match_players
                                WHERE match_id IN (%s) AND user_id <> ?
                                GROUP BY user_id ORDER BY n DESC LIMIT 5]]):format(placeholders), params) or {}
        for i = 1, #opp do
            if tonumber(opp[i].n) >= D.repeatedOpponent.threshold then
                AntiBoost.flag(userId, 'repeatedOpponent', D.repeatedOpponent.severity, {
                    opponent = opp[i].user_id, encounters = opp[i].n, sample = #rows
                }, m and m.dbId, opp[i].user_id)
            end
        end
    end

    -- ---- repeated victim ---------------------------------------------------
    if D.repeatedVictim.enabled then
        local vic = DB.query([[SELECT victim, COUNT(*) AS n FROM m5_match_kills
                               WHERE killer = ? GROUP BY victim ORDER BY n DESC LIMIT 3]], { userId }) or {}
        for i = 1, #vic do
            if tonumber(vic[i].n) >= D.repeatedVictim.threshold then
                AntiBoost.flag(userId, 'repeatedVictim', D.repeatedVictim.severity, {
                    victim = vic[i].victim, kills = vic[i].n
                }, m and m.dbId, vic[i].victim)
            end
        end
    end

    -- ---- short matches -----------------------------------------------------
    if D.shortMatches.enabled then
        local short = 0
        for i = 1, #rows do
            if (tonumber(rows[i].duration) or 999) < D.shortMatches.minDuration then
                short = short + 1
            end
        end
        if short >= D.shortMatches.threshold then
            AntiBoost.flag(userId, 'shortMatches', D.shortMatches.severity,
                { count = short, sample = #rows }, m and m.dbId)
        end
    end

    -- ---- intentional losses ------------------------------------------------
    if D.intentionalLoss.enabled then
        local bad = 0
        for i = 1, #rows do
            local k = tonumber(rows[i].kills) or 0
            local d = tonumber(rows[i].deaths) or 0
            if d >= D.intentionalLoss.minDeaths and (k / math.max(1, d)) <= D.intentionalLoss.maxKD then
                bad = bad + 1
            end
        end
        if bad >= D.intentionalLoss.threshold then
            AntiBoost.flag(userId, 'intentionalLoss', D.intentionalLoss.severity,
                { matches = bad, sample = #rows }, m and m.dbId)
        end
    end

    -- ---- win trading -------------------------------------------------------
    if D.winTrading.enabled then
        local alternating, last = 0, nil
        for i = 1, #rows do
            local res = rows[i].result
            if last and res ~= last and (res == 'WIN' or res == 'LOSS') then
                alternating = alternating + 1
            end
            last = res
        end
        if alternating >= (D.winTrading.threshold * 2) then
            AntiBoost.flag(userId, 'winTrading', D.winTrading.severity,
                { alternations = alternating, sample = #rows }, m and m.dbId)
        end
    end

    -- ---- alternate accounts ------------------------------------------------
    if D.altAccount.enabled then
        local pd = Players[userId]
        if pd and pd.ipHash ~= '' and D.altAccount.matchOnIP then
            local others = DB.query([[SELECT user_id, name, created_at FROM m5_players
                                      WHERE ip_hash = ? AND user_id <> ? LIMIT 5]],
                { pd.ipHash, userId }) or {}
            if #others > 0 then
                AntiBoost.flag(userId, 'altAccount', D.altAccount.severity,
                    { linked = others }, m and m.dbId)
            end
        end
    end

    -- ---- abnormal RP gain --------------------------------------------------
    if D.abnormalRP.enabled then
        local gained = DB.scalar([[SELECT SUM(mp.rp_change) FROM m5_match_players mp
                                   JOIN m5_matches mt ON mt.id = mp.match_id
                                   WHERE mp.user_id = ? AND mt.ended_at >= ?]],
            { userId, sqlDate(now() - 3600) }) or 0
        if (tonumber(gained) or 0) > D.abnormalRP.rpPerHour then
            AntiBoost.flag(userId, 'abnormalRP', D.abnormalRP.severity,
                { rpLastHour = gained }, m and m.dbId)
        end
    end

    -- ---- impossible headshot ratio ----------------------------------------
    if D.impossibleHeadshot.enabled then
        local kills, hs = 0, 0
        for i = 1, #rows do
            kills = kills + (tonumber(rows[i].kills) or 0)
            hs    = hs + (tonumber(rows[i].headshots) or 0)
        end
        if kills >= D.impossibleHeadshot.minKills
           and (hs / math.max(1, kills)) >= D.impossibleHeadshot.headshotRatio then
            AntiBoost.flag(userId, 'impossibleHeadshot', D.impossibleHeadshot.severity,
                { kills = kills, headshots = hs, ratio = round(hs / kills, 3) }, m and m.dbId)
        end
    end
end

function AntiBoost.suspicious(limit)
    return DB.query([[SELECT f.user_id, p.name, SUM(f.severity) AS score, COUNT(*) AS flags,
                             MAX(f.created_at) AS last_flag
                      FROM m5_anti_boost_flags f
                      LEFT JOIN m5_players p ON p.user_id = f.user_id
                      WHERE f.reviewed = 0
                      GROUP BY f.user_id, p.name
                      HAVING score >= ?
                      ORDER BY score DESC LIMIT ?]],
        { Config.AntiBoost.reviewThreshold, limit or 50 }) or {}
end

-- ============================================================================
-- 18. LEADERBOARDS / PROFILES / HISTORY
-- ============================================================================

local Board = { cache = {} }   -- [key] = { at = ms, data = {} }

local function cached(key, ttl, builder)
    local c = Board.cache[key]
    if c and (ms() - c.at) < ttl then return c.data end
    local data = builder()
    Board.cache[key] = { at = ms(), data = data }
    return data
end

local function decorateRow(row, showMMR)
    local rank = Rank.get(tonumber(row.rank_id) or 0)
    local wins   = tonumber(row.wins) or 0
    local losses = tonumber(row.losses) or 0
    local kills  = tonumber(row.kills) or 0
    local deaths = tonumber(row.deaths) or 0
    local hs     = tonumber(row.headshots) or 0
    return {
        userId    = row.user_id,
        name      = row.name or ('User ' .. tostring(row.user_id)),
        rp        = tonumber(row.rp) or 0,
        rankId    = rank.id,
        rank      = rank.name,
        rankColor = rank.color,
        tier      = rank.tier,
        mmr       = showMMR and (tonumber(row.mmr) or 0) or nil,
        wins      = wins,
        losses    = losses,
        matches   = tonumber(row.matches) or (wins + losses),
        winRate   = (wins + losses) > 0 and round((wins / (wins + losses)) * 100, 1) or 0,
        kd        = deaths > 0 and round(kills / deaths, 2) or kills,
        kills     = kills,
        deaths    = deaths,
        headshots = hs,
        hsPercent = kills > 0 and round((hs / kills) * 100, 1) or 0,
        mvp       = tonumber(row.mvp) or 0,
        streak    = tonumber(row.win_streak) or 0,
        level     = tonumber(row.level) or 1
    }
end

--- The RP ladder for one pool. With per-mode ranks there is no single global
--- ladder any more, so the caller always names the pool it wants.
function Board.global(page, showMMR, pool)
    local size   = Config.Database.pageSize
    local offset = math.max(0, (page or 1) - 1) * size
    pool = pool or defaultPool()
    return cached(('global_%s_%d_%s'):format(pool, page or 1, tostring(showMMR)),
        Config.Database.leaderboardCacheTime, function()
        local rows = DB.query([[SELECT r.user_id, r.rp, r.rank_id, p.name, p.level,
                                       s.wins, s.losses, s.matches, s.kills, s.deaths,
                                       s.headshots, s.mvp, s.win_streak, m.mmr
                                FROM m5_player_ranks r
                                LEFT JOIN m5_players p ON p.user_id = r.user_id
                                LEFT JOIN m5_player_stats s ON s.user_id = r.user_id AND s.season_id = r.season_id
                                LEFT JOIN m5_player_mmr m ON m.user_id = r.user_id AND m.season_id = r.season_id AND m.mode = r.mode
                                WHERE r.season_id = ? AND r.mode = ? AND r.placement_done = 1
                                ORDER BY r.rp DESC, s.wins DESC
                                LIMIT ? OFFSET ?]], { Season.id(), pool, size, offset }) or {}
        local out = {}
        for i = 1, #rows do
            local e = decorateRow(rows[i], showMMR)
            e.position = offset + i
            out[#out + 1] = e
        end
        return out
    end)
end

--- Period boards are built from RP gained inside the window.
function Board.period(kind, page, showMMR)
    local since = kind == 'daily' and sqlDate(now() - 86400) or sqlDate(now() - 604800)
    local size   = Config.Database.pageSize
    local offset = math.max(0, (page or 1) - 1) * size

    -- the badge next to a name is the player's rank on the default ladder;
    -- without the mode predicate a player with three ranks appears three times
    return cached(('period_%s_%d'):format(kind, page or 1),
        Config.Database.leaderboardCacheTime, function()
        local rows = DB.query([[SELECT mp.user_id, p.name, p.level, r.rank_id, r.rp,
                                       SUM(mp.rp_change) AS gained,
                                       SUM(mp.kills) AS kills, SUM(mp.deaths) AS deaths,
                                       SUM(mp.headshots) AS headshots, SUM(mp.mvp) AS mvp,
                                       SUM(CASE WHEN mp.result = 'WIN' THEN 1 ELSE 0 END) AS wins,
                                       SUM(CASE WHEN mp.result = 'LOSS' THEN 1 ELSE 0 END) AS losses,
                                       COUNT(*) AS matches
                                FROM m5_match_players mp
                                JOIN m5_matches mt ON mt.id = mp.match_id
                                LEFT JOIN m5_players p ON p.user_id = mp.user_id
                                LEFT JOIN m5_player_ranks r ON r.user_id = mp.user_id AND r.season_id = mt.season_id AND r.mode = ?
                                WHERE mt.ranked = 1 AND mt.ended_at >= ?
                                GROUP BY mp.user_id, p.name, p.level, r.rank_id, r.rp
                                ORDER BY gained DESC
                                LIMIT ? OFFSET ?]], { defaultPool(), since, size, offset }) or {}
        local out = {}
        for i = 1, #rows do
            local e = decorateRow(rows[i], showMMR)
            e.position = offset + i
            e.gained   = tonumber(rows[i].gained) or 0
            out[#out + 1] = e
        end
        return out
    end)
end

--- Per mode ladder. RP stays a single season ladder, but the board can be
--- narrowed to one mode: points are the RP earned inside that mode and the
--- kill/death columns only count matches of that mode.
function Board.byMode(mode, page, showMMR)
    local size   = Config.Database.pageSize
    local offset = math.max(0, (page or 1) - 1) * size
    local pool   = Player.poolOf(mode)

    return cached(('mode_%s_%d_%s'):format(tostring(mode), page or 1, tostring(showMMR)),
        Config.Database.leaderboardCacheTime, function()
        local rows = DB.query([[SELECT mp.user_id, p.name, p.level, r.rank_id, m.mmr,
                                       SUM(mp.rp_change) AS points,
                                       SUM(mp.kills) AS kills, SUM(mp.deaths) AS deaths,
                                       SUM(mp.headshots) AS headshots, SUM(mp.mvp) AS mvp,
                                       SUM(CASE WHEN mp.result = 'WIN' THEN 1 ELSE 0 END) AS wins,
                                       SUM(CASE WHEN mp.result = 'LOSS' THEN 1 ELSE 0 END) AS losses,
                                       COUNT(*) AS matches
                                FROM m5_match_players mp
                                JOIN m5_matches mt ON mt.id = mp.match_id
                                LEFT JOIN m5_players p ON p.user_id = mp.user_id
                                LEFT JOIN m5_player_ranks r ON r.user_id = mp.user_id AND r.season_id = mt.season_id AND r.mode = ?
                                LEFT JOIN m5_player_mmr m ON m.user_id = mp.user_id AND m.season_id = mt.season_id AND m.mode = ?
                                WHERE mt.ranked = 1 AND mt.mode = ? AND mt.season_id = ?
                                GROUP BY mp.user_id, p.name, p.level, r.rank_id, m.mmr
                                ORDER BY points DESC, wins DESC
                                LIMIT ? OFFSET ?]],
            { pool, pool, mode, Season.id(), size, offset }) or {}

        local out = {}
        for i = 1, #rows do
            local e = decorateRow(rows[i], showMMR)
            e.position = offset + i
            e.points   = tonumber(rows[i].points) or 0
            out[#out + 1] = e
        end
        return out
    end)
end

--- The "YOUR STATISTICS" card next to the per mode board.
function Board.modeStats(userId, mode)
    local row = DB.single([[SELECT SUM(mp.kills) AS kills, SUM(mp.deaths) AS deaths,
                                   SUM(mp.rp_change) AS points, COUNT(*) AS matches,
                                   SUM(CASE WHEN mp.result = 'WIN' THEN 1 ELSE 0 END) AS wins
                            FROM m5_match_players mp
                            JOIN m5_matches mt ON mt.id = mp.match_id
                            WHERE mp.user_id = ? AND mt.mode = ? AND mt.season_id = ?]],
        { userId, mode, Season.id() })

    local kills  = tonumber(row and row.kills) or 0
    local deaths = tonumber(row and row.deaths) or 0
    local pd     = Players[userId]

    return {
        mode      = mode,
        wins      = tonumber(row and row.wins) or 0,
        matches   = tonumber(row and row.matches) or 0,
        kills     = kills,
        deaths    = deaths,
        points    = tonumber(row and row.points) or 0,
        kd        = deaths > 0 and round(kills / deaths, 2) or kills,
        rank      = pd and (pd.placementDone and Rank.get(pd.rankId).name or 'Unranked') or 'Unranked',
        rankId    = pd and (pd.placementDone and pd.rankId or 0) or 0,
        rankColor = pd and Rank.get(pd.rankId).color or '#5A616D'
    }
end

function Board.season(seasonId, page)
    local size   = Config.Database.pageSize
    local offset = math.max(0, (page or 1) - 1) * size
    local rows = DB.query([[SELECT sp.*, p.level FROM m5_season_players sp
                            LEFT JOIN m5_players p ON p.user_id = sp.user_id
                            WHERE sp.season_id = ?
                            ORDER BY sp.final_rp DESC LIMIT ? OFFSET ?]],
        { seasonId or Season.id(), size, offset }) or {}
    local out = {}
    for i = 1, #rows do
        local rank = Rank.get(tonumber(rows[i].final_rank_id) or 0)
        out[#out + 1] = {
            position = offset + i,
            userId = rows[i].user_id, name = rows[i].name,
            rp = rows[i].final_rp, rank = rank.name, rankColor = rank.color,
            rankId = rank.id, tier = rank.tier,
            wins = rows[i].wins, losses = rows[i].losses, kd = rows[i].kd,
            level = rows[i].level or 1
        }
    end
    return out
end

--- "Friends" board = the players you recently played with.
function Board.recent(userId, showMMR)
    local rows = DB.query([[SELECT DISTINCT mp2.user_id, p.name, p.level, r.rank_id, r.rp,
                                   s.wins, s.losses, s.matches, s.kills, s.deaths,
                                   s.headshots, s.mvp, s.win_streak
                            FROM m5_match_players mp1
                            JOIN m5_match_players mp2 ON mp2.match_id = mp1.match_id AND mp2.user_id <> mp1.user_id
                            LEFT JOIN m5_players p ON p.user_id = mp2.user_id
                            LEFT JOIN m5_player_ranks r ON r.user_id = mp2.user_id AND r.season_id = ? AND r.mode = ?
                            LEFT JOIN m5_player_stats s ON s.user_id = mp2.user_id AND s.season_id = ?
                            WHERE mp1.user_id = ?
                            ORDER BY mp2.match_id DESC LIMIT 25]],
        { Season.id(), defaultPool(), Season.id(), userId }) or {}
    local out = {}
    for i = 1, #rows do
        local e = decorateRow(rows[i], showMMR)
        e.position = i
        out[#out + 1] = e
    end
    return out
end

function Board.myPosition(userId, pool)
    pool = pool or (Players[userId] and Players[userId].pool) or defaultPool()
    local rp = DB.scalar('SELECT rp FROM m5_player_ranks WHERE user_id = ? AND season_id = ? AND mode = ?',
        { userId, Season.id(), pool })
    if not rp then return 0 end
    local above = DB.scalar('SELECT COUNT(*) FROM m5_player_ranks WHERE season_id = ? AND mode = ? AND placement_done = 1 AND rp > ?',
        { Season.id(), pool, rp }) or 0
    return (tonumber(above) or 0) + 1
end

-- ---------------------------------------------------------------------------
-- Profile
-- ---------------------------------------------------------------------------

local function buildProfile(userId, showMMR, pool)
    local seasonId = Season.id()
    local pd = Players[userId]
    pool = pool or (pd and pd.pool) or defaultPool()

    local prow = pd and {
        name = pd.name, level = pd.level, xp = pd.xp,
        titles = pd.titles, badges = pd.badges,
        active_title = pd.activeTitle, frame = pd.frame,
        commendations = pd.commendations
    } or DB.single('SELECT * FROM m5_players WHERE user_id = ?', { userId })
    if not prow then return nil end

    local live = pd and Player.poolData(pd, pool) or nil
    local rrow = live and {
        rp = live.rp, rank_id = live.rankId, highest_rank_id = live.highestRankId,
        highest_rp = live.highestRP, placement_done = live.placementDone and 1 or 0,
        placement_played = live.placementPlayed
    } or DB.single('SELECT * FROM m5_player_ranks WHERE user_id = ? AND season_id = ? AND mode = ?',
        { userId, seasonId, pool })
        or { rp = 0, rank_id = 0, highest_rank_id = 0, highest_rp = 0, placement_done = 0, placement_played = 0 }

    local srow = pd and pd.stats
        or DB.single('SELECT * FROM m5_player_stats WHERE user_id = ? AND season_id = ?', { userId, seasonId })
        or emptyStats()

    local mrow = live and { mmr = live.mmr, peak_mmr = live.peakMMR }
        or DB.single('SELECT * FROM m5_player_mmr WHERE user_id = ? AND season_id = ? AND mode = ?',
            { userId, seasonId, pool })
        or { mmr = Config.MMR.startValue, peak_mmr = Config.MMR.startValue }

    local kills  = tonumber(srow.kills) or 0
    local deaths = tonumber(srow.deaths) or 0
    local wins   = tonumber(srow.wins) or 0
    local losses = tonumber(srow.losses) or 0
    local rank   = Rank.get(tonumber(rrow.rank_id) or 0)
    local placementDone = toBool(rrow.placement_done)

    local history = DB.query([[SELECT s.number, s.name, sp.final_rp, sp.final_rank_id, sp.rank_name
                               FROM m5_season_players sp
                               JOIN m5_seasons s ON s.id = sp.season_id
                               WHERE sp.user_id = ? ORDER BY s.number DESC LIMIT 10]], { userId }) or {}

    local favWeapon = srow.fav_weapon
    if type(srow.weapon_stats) == 'string' then
        local ws = jsonDecode(srow.weapon_stats, {})
        local bw, bn = '', 0
        for w, c in pairs(ws) do if c > bn then bw, bn = w, c end end
        favWeapon = bw
    end

    return {
        userId    = userId,
        name      = prow.name,
        level     = tonumber(prow.level) or 1,
        xp        = tonumber(prow.xp) or 0,
        xpNeeded  = xpForLevel(tonumber(prow.level) or 1),
        titles    = type(prow.titles) == 'table' and prow.titles or jsonDecode(prow.titles, {}),
        badges    = type(prow.badges) == 'table' and prow.badges or jsonDecode(prow.badges, {}),
        activeTitle = prow.active_title or '',
        frame     = prow.frame or 'default',
        commendations = tonumber(prow.commendations) or 0,

        rp        = tonumber(rrow.rp) or 0,
        rank      = placementDone and rank.name or 'Unranked',
        rankId    = placementDone and rank.id or 0,
        rankColor = placementDone and rank.color or '#5A616D',
        tier      = placementDone and rank.tier or 'UNRANKED',
        progress  = Rank.progress(tonumber(rrow.rp) or 0, tonumber(rrow.rank_id) or 0, placementDone),
        highestRank = Rank.get(tonumber(rrow.highest_rank_id) or 0).name,
        highestRP = tonumber(rrow.highest_rp) or 0,
        placement = {
            done = placementDone,
            played = tonumber(rrow.placement_played) or 0,
            total = Config.Placement.matches
        },
        mmr       = showMMR and (tonumber(mrow.mmr) or 0) or nil,
        peakMMR   = showMMR and (tonumber(mrow.peak_mmr) or 0) or nil,

        stats = {
            matches   = tonumber(srow.matches) or 0,
            wins      = wins,
            losses    = losses,
            draws     = tonumber(srow.draws) or 0,
            winRate   = (wins + losses) > 0 and round((wins / (wins + losses)) * 100, 1) or 0,
            kills     = kills,
            deaths    = deaths,
            assists   = tonumber(srow.assists) or 0,
            kd        = deaths > 0 and round(kills / deaths, 2) or kills,
            headshots = tonumber(srow.headshots) or 0,
            hsPercent = kills > 0 and round(((tonumber(srow.headshots) or 0) / kills) * 100, 1) or 0,
            damage    = tonumber(srow.damage) or 0,
            mvp       = tonumber(srow.mvp) or 0,
            winStreak = tonumber(srow.win_streak) or 0,
            bestStreak= tonumber(srow.best_win_streak) or 0,
            clutches  = tonumber(srow.clutches) or 0,
            aces      = tonumber(srow.aces) or 0,
            firstBloods = tonumber(srow.first_bloods) or 0,
            favWeapon = favWeapon or '',
            favMap    = srow.fav_map or '',
            playtime  = tonumber(srow.playtime) or 0
        },

        seasons = history,
        position = Board.myPosition(userId),
        achievements = Achievements.list(userId)
    }
end

function Board.profile(userId, showMMR)
    return cached(('profile_%d_%s'):format(userId, tostring(showMMR)),
        Config.Database.profileCacheTime, function()
            return buildProfile(userId, showMMR)
        end)
end

-- ---------------------------------------------------------------------------
-- Match history
-- ---------------------------------------------------------------------------

function Board.history(userId, page)
    local size   = Config.Database.historyPageSize
    local offset = math.max(0, (page or 1) - 1) * size

    local rows = DB.query([[SELECT mp.*, mt.mode, mt.map_id, mt.team_a_score, mt.team_b_score,
                                   mt.winner, mt.ended_at, mt.duration, mt.ranked, mt.id AS mid
                            FROM m5_match_players mp
                            JOIN m5_matches mt ON mt.id = mp.match_id
                            WHERE mp.user_id = ?
                            ORDER BY mp.match_id DESC LIMIT ? OFFSET ?]],
        { userId, size, offset }) or {}

    local out = {}
    for i = 1, #rows do
        local r = rows[i]
        local mine  = tonumber(r.team) == 2 and r.team_b_score or r.team_a_score
        local other = tonumber(r.team) == 2 and r.team_a_score or r.team_b_score
        local map = MapById[r.map_id]
        out[#out + 1] = {
            matchId   = r.mid,
            mode      = (Config.Modes[r.mode] or {}).label or r.mode,
            map       = map and map.name or r.map_id,
            mapId     = r.map_id,
            result    = r.result,
            score     = { mine = mine, other = other },
            rpChange  = tonumber(r.rp_change) or 0,
            rpAfter   = tonumber(r.rp_after) or 0,
            kills     = tonumber(r.kills) or 0,
            deaths    = tonumber(r.deaths) or 0,
            assists   = tonumber(r.assists) or 0,
            headshots = tonumber(r.headshots) or 0,
            damage    = tonumber(r.damage) or 0,
            mvp       = toBool(r.mvp),
            ranked    = toBool(r.ranked),
            duration  = tonumber(r.duration) or 0,
            date      = r.ended_at
        }
    end
    return out
end

function Board.matchDetail(matchId)
    local mt = DB.single('SELECT * FROM m5_matches WHERE id = ?', { matchId })
    if not mt then return nil end

    local players = DB.query([[SELECT mp.*, p.level FROM m5_match_players mp
                               LEFT JOIN m5_players p ON p.user_id = mp.user_id
                               WHERE mp.match_id = ? ORDER BY mp.team, mp.score DESC]], { matchId }) or {}
    local rounds = DB.query('SELECT * FROM m5_match_rounds WHERE match_id = ? ORDER BY round_no', { matchId }) or {}

    local roster = {}
    for i = 1, #players do
        local p = players[i]
        local kills, deaths = tonumber(p.kills) or 0, tonumber(p.deaths) or 0
        roster[#roster + 1] = {
            userId = p.user_id, name = p.name, team = tonumber(p.team) or 1,
            kills = kills, deaths = deaths, assists = tonumber(p.assists) or 0,
            headshots = tonumber(p.headshots) or 0, damage = tonumber(p.damage) or 0,
            score = tonumber(p.score) or 0, mvp = toBool(p.mvp),
            rpChange = tonumber(p.rp_change) or 0,
            kd = deaths > 0 and round(kills / deaths, 2) or kills,
            rank = Rank.get(tonumber(p.rank_after) or 0).name,
            result = p.result
        }
    end

    local map = MapById[mt.map_id]
    return {
        matchId = mt.id,
        mode    = (Config.Modes[mt.mode] or {}).label or mt.mode,
        map     = map and map.name or mt.map_id,
        scores  = { a = mt.team_a_score, b = mt.team_b_score },
        winner  = mt.winner,
        duration= mt.duration,
        ranked  = toBool(mt.ranked),
        date    = mt.ended_at,
        overtime= toBool(mt.overtime),
        roster  = roster,
        rounds  = rounds
    }
end

--- Live matches list (admin dashboard / spectator picker).
function Board.liveMatches()
    local out = {}
    for id, m in pairs(Matches) do
        out[#out + 1] = {
            id = id, mode = m.cfg.label, map = m.map and m.map.name or '—',
            state = m.state, round = m.round,
            scores = { a = m.scores[1], b = m.scores[2] },
            players = count(m.players), ranked = m.ranked,
            bucket = m.bucket, custom = m.customId ~= nil
        }
    end
    table.sort(out, function(a, b) return a.players > b.players end)
    return out
end

-- ============================================================================
-- 19. ADMIN
-- ============================================================================

local Admin = {}

function Admin.level(userId)
    if vRP.hasPermission({ userId, Config.Permissions.superAdmin }) then return 'super' end
    if vRP.hasPermission({ userId, Config.Permissions.admin }) then return 'admin' end
    if vRP.hasPermission({ userId, Config.Permissions.moderator }) then return 'moderator' end
    return nil
end

--- Single gate for every admin action.
-- superAdmin unlocks everything; the generic admin permission does too unless
-- Config.Permissions.adminGrantsAll is turned off; otherwise the action's own
-- permission is required.
function Admin.can(userId, action)
    if vRP.hasPermission({ userId, Config.Permissions.superAdmin }) then return true end

    local def = Config.AdminActions[action]
    if not def then return false end

    if Config.Permissions.adminGrantsAll
       and vRP.hasPermission({ userId, Config.Permissions.admin }) then
        return true
    end

    return vRP.hasPermission({ userId, def.permission }) == true
end

--- The set of actions a given staff member may perform. Sent to the panel so
--- it only renders controls the caller can actually use.
function Admin.allowed(userId)
    local out = {}
    for action, def in pairs(Config.AdminActions) do
        if Admin.can(userId, action) then
            out[action] = {
                label      = def.label,
                group      = def.group,
                permission = def.permission,
                reason     = def.reason == true,
                confirm    = def.confirm == true
            }
        end
    end
    return out
end

--- Writes one audit row and mirrors it to Discord.
function Admin.audit(adminPd, action, target, data)
    data = data or {}
    local def = Config.AdminActions[action] or {}

    DB.insert([[INSERT INTO m5_admin_logs
        (admin_id, admin_name, action, target_id, target_name, amount,
         before_value, after_value, reason, details)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { adminPd.userId, adminPd.name, action,
          target and target.userId or 0, target and target.name or '',
          data.amount or 0, data.before or 0, data.after or 0,
          safeName(data.reason or '', Config.AdminLimits.reasonMaxLen),
          jsonEncode(data.details or {}) })

    local fields = {
        { name = 'Admin', value = ('%s (`%d`)'):format(adminPd.name, adminPd.userId), inline = true },
        { name = 'Action', value = def.label or action, inline = true }
    }
    if target then
        fields[#fields + 1] = { name = 'Target', value = ('%s (`%d`)'):format(target.name or '?', target.userId), inline = true }
    end
    if data.amount and data.amount ~= 0 then
        fields[#fields + 1] = { name = 'Amount', value = tostring(data.amount), inline = true }
    end
    if data.before or data.after then
        fields[#fields + 1] = { name = 'Change', value = ('%d → %d'):format(data.before or 0, data.after or 0), inline = true }
    end
    if data.reason and data.reason ~= '' then
        fields[#fields + 1] = { name = 'Reason', value = data.reason, inline = false }
    end

    Logger.send('adminActions', def.label or action, nil, nil, fields)
end

--- Validates a reason when the action demands one.
local function checkReason(action, reason)
    local def = Config.AdminActions[action]
    if not def or not def.reason then return true, safeName(reason or '', Config.AdminLimits.reasonMaxLen) end

    reason = safeName(reason or '', Config.AdminLimits.reasonMaxLen)
    if #reason < (Config.AdminLimits.reasonMinLen or 1) then
        return false, nil, 'A reason is required for this action.'
    end
    return true, reason
end

function Admin.canSeeMMR(userId)
    if Config.MMR.visibleTo == 'none' then return false end
    if vRP.hasPermission({ userId, Config.Permissions.superAdmin }) then return true end
    if Config.MMR.visibleTo == 'moderator' then return Admin.level(userId) ~= nil end
    return vRP.hasPermission({ userId, Config.Permissions.admin })
        or vRP.hasPermission({ userId, Config.Permissions.viewMMR })
end

function Admin.dashboard(userId)
    local searching = {}
    for mode, list in pairs(Queue) do
        for i = 1, #list do
            local e = list[i]
            for _, u in ipairs(e.members) do
                local pd = Players[u]
                searching[#searching + 1] = {
                    userId = u, name = pd and pd.name or '?',
                    mode = mode, waited = math.floor((ms() - e.joinedMs) / 1000),
                    rank = pd and Rank.get(pd.rankId).name or '?',
                    mmr = pd and pd.mmr or 0
                }
            end
        end
    end

    local bans = DB.query([[SELECT id, user_id, name, type, reason, admin, expiry, duration
                            FROM m5_rank_bans WHERE active = 1 ORDER BY id DESC LIMIT 50]]) or {}

    local seasons = DB.query('SELECT id, number, name, start_at, end_at, active FROM m5_seasons ORDER BY id DESC LIMIT 12') or {}

    local maps = {}
    for i = 1, #Config.Maps do
        maps[#maps + 1] = { id = Config.Maps[i].id, name = Config.Maps[i].name, modes = Config.Maps[i].modes }
    end

    local modes = {}
    for key, cfg in pairs(Config.Modes) do
        modes[#modes + 1] = { id = key, label = cfg.label, teamSize = cfg.teamSize,
                              enabled = cfg.enabled ~= false, ranked = cfg.ranked == true }
    end

    local audit = {}
    if Admin.can(userId, 'auditLog') then
        audit = DB.query([[SELECT action, admin_name, target_name, amount, reason, created_at
                           FROM m5_admin_logs ORDER BY id DESC LIMIT 30]]) or {}
    end

    return {
        allowed     = Admin.allowed(userId),
        level       = Admin.level(userId),
        audit       = audit,
        searching   = searching,
        matches     = Board.liveMatches(),
        rooms       = CustomGames.list(),
        bans        = bans,
        suspicious  = AntiBoost.suspicious(50),
        seasons     = seasons,
        maps        = maps,
        modes       = modes,
        frozen      = Config.Global.rankedFrozen,
        -- only the labels the panel needs, and only for staff who reached here
        botMatch    = {
            enabled = Config.BotMatch.enabled,
            maxBots = Config.BotMatch.maxBots,
            running = BotMatch.sessions[userId] ~= nil,
            difficulties = (function()
                local out = {}
                for key, d in pairs(Config.BotMatch.bots.difficulties) do
                    out[#out + 1] = {
                        id = key, label = d.label, accuracy = d.accuracy or 0,
                        isDefault = key == Config.BotMatch.bots.defaultDifficulty
                    }
                end
                -- easiest first, so a custom set of presets still reads in order
                table.sort(out, function(a, b) return a.accuracy < b.accuracy end)
                return out
            end)()
        },
        season      = Season.current and {
            id = Season.current.id, name = Season.current.name,
            number = Season.current.number, endsAt = Season.endsAt
        } or nil,
        online      = count(Players)
    }
end

--- Resolves a target from a user id or an online player name.
--- Admin targets are resolved by user id only. Name matching is deliberately
--- not supported: two players can share a display name, and a partial match
--- could silently point a ban or an RP wipe at the wrong account.
local function resolveTarget(value)
    local id = tonumber(value)
    if not id then return nil end

    id = math.floor(id)
    if id <= 0 then return nil end

    if Players[id] then return id end
    if DB.scalar('SELECT user_id FROM m5_players WHERE user_id = ?', { id }) then return id end
    return nil
end

--- Saves immediately and pushes a fresh payload to the player, so an admin
--- edit shows up on their screen at once instead of after a reconnect.
function Player.pushUpdate(userId)
    local pd = Players[userId]
    if not pd then return false end

    Player.save(pd, false)
    Board.cache = {}

    local s = srcOf(userId)
    if not s then return false end
    TriggerClientEvent('m5rp:cl:boot', s, Server_BootPayload(pd))
    return true
end

--- Reads the rank row straight back and compares it with what is in memory.
--- Used after a staff grant: a change that did not reach the database has to be
--- visible right then, not discovered by the player after the next restart.
--- Returns nil when everything matches, or a description of the mismatch.
function Player.verifyRank(userId)
    local pd = Players[userId]
    if not pd then return nil end

    local seasonId = Season.id()
    if seasonId == 0 then
        return 'no active season — the change is held in memory and not saved'
    end

    local row = DB.single(
        'SELECT rp, rank_id, placement_done FROM m5_player_ranks WHERE user_id = ? AND season_id = ? AND mode = ?',
        { userId, seasonId, pd.pool })

    if not row then
        err('VERIFY FAILED: no m5_player_ranks row for user %d season %d pool %s after saving',
            userId, seasonId, pd.pool)
        return ('the database has no rank row for season %d, ladder %s'):format(seasonId, pd.pool)
    end

    local storedRank, storedRP = tonumber(row.rank_id) or -1, tonumber(row.rp) or -1
    if storedRank ~= pd.rankId or storedRP ~= pd.rp then
        err('VERIFY FAILED: user %d memory rank=%d rp=%d but database rank=%d rp=%d (season %d)',
            userId, pd.rankId, pd.rp, storedRank, storedRP, seasonId)
        return ('saved value does not match: database has rank %d / %d RP'):format(storedRank, storedRP)
    end

    -- The row can carry the right rank and still display as Unranked if this
    -- flag does not survive the round trip, so it is checked the same way.
    if toBool(row.placement_done) ~= (pd.placementDone and true or false) then
        err('VERIFY FAILED: user %d placement_done stored as %s (%s) but memory has %s',
            userId, tostring(row.placement_done), type(row.placement_done),
            tostring(pd.placementDone))
        return 'placement flag did not round-trip — the player would load as Unranked'
    end

    return nil
end

--- Loads a player row into the cache for offline edits.
local function withPlayer(userId, fn)
    local pd = Players[userId]
    local temporary = false
    if not pd then
        pd = Player.load(userId, nil)
        temporary = true
    end

    local result = fn(pd)

    if temporary then
        -- offline: write straight through and drop the cache entry again
        Player.save(pd, true)
    else
        -- online: persist now and refresh the player's interface
        Player.pushUpdate(userId)
    end

    -- Confirm the change actually reached the database. Staff actions are rare,
    -- so one extra read is cheap next to a grant that quietly does nothing.
    if type(result) == 'table' then
        local wasCached = Players[userId] ~= nil
        if not wasCached then Players[userId] = pd end   -- verify reads the cache
        result.verifyError = Player.verifyRank(userId)
        if not wasCached then Players[userId] = nil end
    end

    return result
end

function Admin.handle(adminPd, action, data)
    action = tostring(action or '')
    data   = type(data) == 'table' and data or {}

    local def = Config.AdminActions[action]
    if not def then return false, 'Unknown admin action.' end
    if not Admin.can(adminPd.userId, action) then
        return false, _Lf('No permission (%s).', def.permission)
    end

    local okReason, reason, reasonErr = checkReason(action, data.reason)
    if not okReason then return false, reasonErr end

    -- Resolves the target and returns a compact identity for the audit row.
    local function target()
        local id = resolveTarget(data.target)
        if not id then return nil end
        local pd = Players[id]
        return id, { userId = id, name = pd and pd.name
            or (DB.scalar('SELECT name FROM m5_players WHERE user_id = ?', { id }) or ('User ' .. id)) }
    end

    -- ================================================== monitoring
    if action == 'dashboard' then
        return true, Admin.dashboard(adminPd.userId)

    elseif action == 'playerLookup' then
        local id, who = target()
        if not id then return false, 'No player with that ID.' end
        local profile = buildProfile(id, Admin.canSeeMMR(adminPd.userId))
        if not profile then return false, 'No data for that player.' end
        profile.bans  = Bans.get(id)
        profile.flags = DB.query('SELECT * FROM m5_anti_boost_flags WHERE user_id = ? ORDER BY id DESC LIMIT 25', { id }) or {}
        profile.cooldown = Penalty.cooldownLeft(id)
        profile.online = srcOf(id) ~= nil
        profile.audit = DB.query([[SELECT action, admin_name, amount, reason, created_at
                                   FROM m5_admin_logs WHERE target_id = ?
                                   ORDER BY id DESC LIMIT 15]], { id }) or {}
        return true, profile

    elseif action == 'auditLog' then
        local rows = DB.query([[SELECT * FROM m5_admin_logs
                                ORDER BY id DESC LIMIT 100]]) or {}
        return true, { rows = rows }

    elseif action == 'spectate' then
        local m = Matches[data.matchId]
        if not m then return false, 'Match not found.' end
        local src = adminPd.source
        if not src then return false end

        SetPlayerRoutingBucket(src, m.bucket)
        local targets = {}
        for uidv, mp in pairs(m.players) do
            local ts = srcOf(uidv)
            if ts then targets[#targets + 1] = { serverId = ts, name = mp.name, team = mp.team } end
        end
        TriggerClientEvent('m5rp:cl:spectate', src, {
            matchId = m.id, enable = true, staff = true, targets = targets,
            map = m.map and { center = { x = m.map.center.x, y = m.map.center.y, z = m.map.center.z } } or nil
        })
        adminPd.spectatingMatch = m.id
        Admin.audit(adminPd, action, nil, { details = { match = m.id } })
        return true, { ok = true }

    elseif action == 'stopSpectate' then
        local src = adminPd.source
        if src then
            SetPlayerRoutingBucket(src, 0)
            TriggerClientEvent('m5rp:cl:spectate', src, { enable = false })
        end
        adminPd.spectatingMatch = nil
        return true, { ok = true }

    -- ================================================== match control
    elseif action == 'endMatch' then
        local m = Matches[data.matchId]
        if not m then return false, 'Match not found.' end
        local winner = m.scores[1] == m.scores[2] and 0 or (m.scores[1] > m.scores[2] and 1 or 2)
        Match.endMatch(m, winner, 'ADMIN')
        Admin.audit(adminPd, action, nil, { reason = reason, details = { match = m.id } })
        return true, { ok = true }

    elseif action == 'restartRound' then
        local m = Matches[data.matchId]
        if not m then return false, 'Match not found.' end
        m.round = math.max(0, m.round - 1)
        Match.startRound(m)
        Admin.audit(adminPd, action, nil, { details = { match = m.id } })
        return true, { ok = true }

    elseif action == 'movePlayer' then
        local id, who = target()
        local m = Matches[data.matchId]
        if not id or not m or not m.players[id] then return false, 'Invalid target.' end
        local team = tonumber(data.team)
        if team ~= 1 and team ~= 2 then return false, 'Invalid team.' end
        m.players[id].team = team
        if Players[id] then Players[id].team = team end
        Match.pushHud(m, true)
        Admin.audit(adminPd, action, who, { details = { match = m.id, team = team } })
        return true, { ok = true }

    elseif action == 'kickFromMatch' then
        local id, who = target()
        local tpd = id and Players[id]
        if not tpd or not tpd.matchId then return false, 'That player is not in a match.' end
        Match.removePlayer(Matches[tpd.matchId], id, 'ADMIN')
        Admin.audit(adminPd, action, who, { reason = reason })
        notifyUser(id, 'error', 'You were removed from the match: %s', 'ADMIN', reason)
        return true, { ok = true }

    elseif action == 'closeRoom' then
        local room = CustomGames.rooms[data.roomId]
        if not room then return false, 'Room not found.' end
        local name = room.name
        CustomGames.destroy(room, 'ADMIN')
        Admin.audit(adminPd, action, nil, { reason = reason, details = { room = name } })
        return true, { ok = true }

    elseif action == 'freeze' then
        Config.Global.rankedFrozen = data.value == true
        if Config.Global.rankedFrozen then
            for mode in pairs(Queue) do
                local list = queueList(mode)
                for i = #list, 1, -1 do
                    for _, u in ipairs(list[i].members) do Matchmaker.leave(u) end
                end
            end
        end
        Admin.audit(adminPd, action, nil, {
            details = { frozen = Config.Global.rankedFrozen }, reason = reason })
        return true, { frozen = Config.Global.rankedFrozen }

    elseif action == 'startBotMatch' then
        -- always for the caller: the session lives on their client, so it
        -- cannot be started on somebody else's behalf
        local ok, res = BotMatch.start(adminPd, {
            difficulty = data.difficulty, bots = data.bots,
            rounds = data.rounds, map = data.map
        })
        if not ok then return false, res end
        Admin.audit(adminPd, action, nil, { details = res, reason = reason })
        return true, res

    elseif action == 'stopBotMatch' then
        local ok, res = BotMatch.stop(adminPd.userId, 'stopped by admin')
        if not ok then return false, res end
        Admin.audit(adminPd, action, nil, { reason = reason })
        return true, { ok = true }

    -- ================================================== points
    elseif action == 'addRP' or action == 'removeRP' then
        local id, who = target()
        if not id then return false, 'No player with that ID.' end

        local amount = math.abs(math.floor(tonumber(data.amount) or 0))
        if amount <= 0 then return false, 'Enter an amount.' end
        local cap = (action == 'addRP') and Config.AdminLimits.maxRPGrant or Config.AdminLimits.maxRPDeduct
        if amount > cap then return false, _Lf('Maximum is %d RP per action.', cap) end

        local delta = (action == 'addRP') and amount or -amount

        return true, withPlayer(id, function(pd)
            local inPlacement = not pd.placementDone
            local result = RP.apply(pd, delta, action == 'addRP' and 'ADMIN_GRANT' or 'ADMIN_DEDUCT')
            -- a player still in placement keeps no visible rank
            if inPlacement then pd.rankId, pd.division = 0, 0 end
            pd.dirtyRank = true

            Admin.audit(adminPd, action, who, {
                amount = delta, before = result.before, after = result.after, reason = reason })
            notifyUser(id, delta > 0 and 'success' or 'warning',
                ('%s%d RP — %s'):format(delta > 0 and '+' or '', delta, reason), 'RANKED')

            return { rp = pd.rp, delta = delta, rank = Rank.get(pd.rankId).name,
                     before = result.before, after = result.after }
        end)

    elseif action == 'setRP' then
        local id, who = target()
        local value = tonumber(data.value)
        if not id or not value then return false, 'Invalid target or value.' end

        -- a grant now names the ladder it lands on; without one it goes to the
        -- ladder the hub opens with, which is what an admin sees on the card
        local pool = Player.poolOf(Config.Modes[data.mode] and data.mode or nil)

        return true, withPlayer(id, function(pd)
            Player.usePool(pd, pool)
            local before = pd.rp
            pd.rp = clamp(math.floor(value), Config.RankSettings.minRP, Config.RankSettings.maxRP)
            local rank = Rank.fromRP(pd.rp)
            pd.rankId, pd.division = rank.id, rank.division
            pd.placementDone = true
            pd.dirtyRank = true

            Admin.audit(adminPd, action, who,
                { before = before, after = pd.rp, amount = pd.rp - before, reason = reason,
                  details = { pool = pool } })
            notifyUser(id, 'info', 'Your RP was set to %d — %s', 'RANKED', pd.rp, reason)
            return { rp = pd.rp, rank = rank.name, pool = pool }
        end)

    elseif action == 'setRank' then
        local id, who = target()
        local rankId = tonumber(data.rankId)
        if not id or not RankById[rankId] then return false, 'Invalid target or rank.' end

        local pool = Player.poolOf(Config.Modes[data.mode] and data.mode or nil)

        return true, withPlayer(id, function(pd)
            Player.usePool(pd, pool)
            local rank = Rank.get(rankId)
            local before = pd.rp
            local beforeRank = pd.rankId
            pd.rankId, pd.division = rank.id, rank.division
            pd.rp = rank.rpRequired

            if rank.id == 0 then
                -- rank 0 means "send them back to placement"
                pd.placementDone   = false
                pd.placementPlayed = 0
                pd.placementData   = {}
            else
                pd.placementDone = true
                pd.highestRankId = math.max(pd.highestRankId, rank.id)
            end
            pd.dirtyRank = true

            Admin.audit(adminPd, action, who,
                { before = before, after = pd.rp, reason = reason,
                  details = { rank = rank.name, pool = pool } })
            notifyUser(id, 'info', 'Your rank was set to %s — %s', 'RANKED', rank.name, reason)
            -- always logged: a grant that does not stick is the first thing to
            -- check in the console, and `m5rankinfo <userId>` shows the rest
            log('rank set: user %d -> %s (id %d, rp %d) by %s, season %d',
                id, rank.name, rank.id, pd.rp, adminPd.name, Season.id())
            hook('onRankChange', {
                userId = id, name = pd.name,
                from = { id = beforeRank, name = Rank.get(beforeRank).name },
                to   = { id = rank.id, name = rank.name },
                rp = pd.rp, promoted = rank.id > beforeRank
            })
            return { rank = rank.name, rp = pd.rp }
        end)

    elseif action == 'giveCoins' or action == 'takeCoins' then
        local id, who = target()
        local amount = math.floor(tonumber(data.amount) or 0)
        if not id then return false, 'No player with that ID.' end
        if amount <= 0 then return false, 'Enter an amount.' end

        local cap = Config.AdminLimits.maxCoinGrant or 100000
        if amount > cap then
            return false, _Lf('Maximum is %d coins per action.', cap)
        end

        local delta = (action == 'giveCoins') and amount or -amount
        local before = Store.load(id).coins
        local after  = Store.addCoins(id, delta)

        Admin.audit(adminPd, action, who,
            { before = before, after = after, amount = delta, reason = reason })
        notifyUser(id, action == 'giveCoins' and 'success' or 'warning',
            '%s%d coins — %s', 'STORE',
            delta > 0 and '+' or '', math.abs(delta), reason)

        -- push the new balance so the store updates without a reconnect
        local s2 = srcOf(id)
        if s2 then
            TriggerClientEvent('m5rp:cl:data', s2, { what = 'store', store = Store.payload(id) })
        end
        Player.pushUpdate(id)
        return true, { coins = after, delta = delta }

    elseif action == 'addXP' then
        local id, who = target()
        local amount = math.floor(tonumber(data.amount) or 0)
        if not id then return false, 'No player with that ID.' end
        if amount <= 0 then return false, 'Enter an amount.' end
        if amount > Config.AdminLimits.maxXPGrant then
            return false, _Lf('Maximum is %d XP per action.', Config.AdminLimits.maxXPGrant)
        end

        return true, withPlayer(id, function(pd)
            local before = pd.level
            Rewards.addXP(pd, amount)
            Admin.audit(adminPd, action, who,
                { amount = amount, before = before, after = pd.level, reason = reason })
            notifyUser(id, 'success', '+%d XP — %s', 'PROGRESSION', amount, reason)
            return { level = pd.level, xp = pd.xp }
        end)

    elseif action == 'resetStats' then
        local id, who = target()
        if not id then return false, 'No player with that ID.' end
        local seasonId = Season.id()
        DB.update('DELETE FROM m5_player_stats WHERE user_id = ? AND season_id = ?', { id, seasonId })
        DB.update('DELETE FROM m5_player_ranks WHERE user_id = ? AND season_id = ?', { id, seasonId })
        DB.update('DELETE FROM m5_player_mmr WHERE user_id = ? AND season_id = ?', { id, seasonId })
        Players[id] = nil
        local s = srcOf(id)
        if s then
            local fresh = Player.load(id, s)
            TriggerClientEvent('m5rp:cl:boot', s, Server_BootPayload(fresh))
        end
        Admin.audit(adminPd, action, who, { reason = reason })
        notifyUser(id, 'warning', 'Your season stats were reset — %s', 'RANKED', reason)
        return true, { ok = true }

    -- ================================================== punishments
    elseif action == 'ban' then
        local id, who = target()
        if not id then return false, 'No player with that ID.' end

        local duration = math.max(0, math.floor(tonumber(data.duration) or 0))
        Bans.add(id, {
            type = inList(Config.RankBan.types, data.type) and data.type or 'RANKED',
            mode = data.mode or '',
            duration = duration,
            reason = reason, evidence = data.evidence, notes = data.notes,
            admin = adminPd.name, adminId = adminPd.userId,
            name = who and who.name or nil
        })
        Matchmaker.leave(id)
        local tpd = Players[id]
        if tpd and tpd.matchId and Matches[tpd.matchId] then
            Match.removePlayer(Matches[tpd.matchId], id, 'ADMIN')
        end
        Admin.audit(adminPd, action, who,
            { amount = duration, reason = reason, details = { type = data.type or 'RANKED' } })
        return true, { ok = true }

    elseif action == 'unban' then
        local id, who = target()
        if not id then return false, 'No player with that ID.' end
        Bans.remove(id, tonumber(data.banId), adminPd.name)
        Admin.audit(adminPd, action, who, { reason = reason })
        return true, { ok = true }

    elseif action == 'clearCooldown' then
        local id, who = target()
        if not id then return false, 'No player with that ID.' end
        Penalty.cooldowns[id] = nil
        Admin.audit(adminPd, action, who, { reason = reason })
        notifyUser(id, 'success', 'Your queue cooldown was cleared.', 'RANKED')
        return true, { ok = true }

    elseif action == 'reviewFlag' then
        DB.update('UPDATE m5_anti_boost_flags SET reviewed = 1, admin = ? WHERE id = ?',
            { adminPd.name, tonumber(data.flagId) or 0 })
        Admin.audit(adminPd, action, nil, { details = { flag = data.flagId } })
        return true, { ok = true }

    -- ================================================== system
    elseif action == 'newSeason' then
        Seasons.rollover(adminPd.name)
        Admin.audit(adminPd, action, nil, { reason = reason })
        return true, { ok = true }

    elseif action == 'toggleMode' then
        local cfg = Config.Modes[data.mode]
        if not cfg then return false, 'Unknown mode.' end
        cfg.enabled = data.value == true
        Admin.audit(adminPd, action, nil, { details = { mode = data.mode, enabled = cfg.enabled } })
        return true, { ok = true }
    end

    return false, 'Unknown admin action.'
end

-- ---------------------------------------------------------------------------
-- Season rollover
-- ---------------------------------------------------------------------------

Seasons = {}

function Seasons.rollover(byAdmin)
    if not Config.Seasons.enabled then return end
    local old = Season.current
    if not old then Season.create() return end

    if Config.Seasons.waitForLiveMatches and count(Matches) > 0 then
        dbg('season rollover postponed: %d live matches', count(Matches))
        return
    end

    log('season rollover starting (season #%s)', tostring(old.number))
    Player.saveAll()

    -- archive
    if Config.Seasons.archiveLeaderboard then
        -- Only the default ladder is archived into m5_season_players: that
        -- table is keyed by (season, user) and holds one final placement, and
        -- widening it would rewrite every history screen built on it.
        local rows = DB.query([[SELECT r.user_id, r.rp, r.rank_id, r.highest_rank_id, p.name,
                                       s.wins, s.losses, s.kills, s.deaths
                                FROM m5_player_ranks r
                                LEFT JOIN m5_players p ON p.user_id = r.user_id
                                LEFT JOIN m5_player_stats s ON s.user_id = r.user_id AND s.season_id = r.season_id
                                WHERE r.season_id = ? AND r.mode = ?
                                ORDER BY r.rp DESC]], { old.id, defaultPool() }) or {}

        for i = 1, #rows do
            local r = rows[i]
            local kills, deaths = tonumber(r.kills) or 0, tonumber(r.deaths) or 0
            DB.insert([[INSERT INTO m5_season_players
                (season_id, user_id, name, final_rp, final_rank_id, rank_name, highest_rank_id,
                 placement, wins, losses, kd)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE final_rp = VALUES(final_rp), placement = VALUES(placement)]],
                { old.id, r.user_id, r.name or '', r.rp, r.rank_id,
                  Rank.get(tonumber(r.rank_id) or 0).name, r.highest_rank_id, i,
                  r.wins or 0, r.losses or 0,
                  deaths > 0 and round(kills / deaths, 2) or kills })

            -- season rewards
            if Config.Seasons.distributeRewards and Config.Rewards.enabled then
                local tier = Rank.get(tonumber(r.highest_rank_id) or 0).tier
                local pack = Config.Rewards.season[tier]
                if pack then
                    withPlayer(tonumber(r.user_id), function(pd)
                        for k = 1, #pack do
                            Rewards.grant(pd, pack[k], old.id,
                                ('season_%d_%s_%d'):format(old.id, tier, k))
                        end
                    end)
                end
            end
        end
    end

    DB.update('UPDATE m5_seasons SET active = 0, finalized = 1 WHERE id = ?', { old.id })

    -- reset
    local R = Config.Seasons.reset
    local newId = Season.create()

    if R.mode ~= 'none' then
        -- every ladder rolls over on its own terms: a soft reset applies to
        -- each one separately, so a Gold 1v1 and a Silver 2v2 both carry
        local rows = DB.query('SELECT user_id, mode, rp, highest_rank_id FROM m5_player_ranks WHERE season_id = ?',
            { old.id }) or {}
        for i = 1, #rows do
            local newRP = 0
            if R.mode == 'soft' then
                newRP = clamp(math.floor((tonumber(rows[i].rp) or 0) * R.softFactor) + R.softOffset,
                              Config.RankSettings.minRP, Config.RankSettings.maxRP)
            end
            local rank = R.mode == 'soft' and Rank.fromRP(newRP) or Rank.get(0)
            DB.insert([[INSERT INTO m5_player_ranks
                (user_id, season_id, mode, rp, rank_id, division, placement_done, placement_played, placement_data)
                VALUES (?, ?, ?, ?, ?, ?, ?, 0, '[]')
                ON DUPLICATE KEY UPDATE rp = VALUES(rp)]],
                { rows[i].user_id, newId, rows[i].mode or defaultPool(), newRP,
                  R.mode == 'soft' and rank.id or 0,
                  R.mode == 'soft' and rank.division or 0,
                  (R.resetPlacement or R.mode == 'hard') and 0 or 1 })
        end

        if R.keepMMR then
            local mrows = DB.query('SELECT user_id, mode, mmr, peak_mmr FROM m5_player_mmr WHERE season_id = ?',
                { old.id }) or {}
            for i = 1, #mrows do
                local carried = math.floor(((tonumber(mrows[i].mmr) or Config.MMR.startValue) * R.mmrSoftFactor)
                                + (Config.MMR.startValue * (1 - R.mmrSoftFactor)))
                DB.insert([[INSERT INTO m5_player_mmr (user_id, season_id, mode, mmr, uncertainty, games, peak_mmr)
                            VALUES (?, ?, ?, ?, ?, 0, ?)
                            ON DUPLICATE KEY UPDATE mmr = VALUES(mmr)]],
                    { mrows[i].user_id, newId, mrows[i].mode or defaultPool(),
                      carried, Config.MMR.uncertaintyStart, carried })
            end
        end
    end

    -- reload every online player against the new season
    for userId, pd in pairs(Players) do
        local s = pd.source
        Players[userId] = nil
        if s then
            local fresh = Player.load(userId, s)
            TriggerClientEvent('m5rp:cl:boot', s, Server_BootPayload(fresh))
        end
    end

    Board.cache = {}
    Logger.send('adminActions', 'Season Rollover',
        ('Season #%s archived, season #%s started%s'):format(
            tostring(old.number), tostring(Season.current and Season.current.number),
            byAdmin and (' by **' .. byAdmin .. '**') or ''))
    log('season rollover complete')
end

-- ============================================================================
-- 20. NET EVENTS
-- ============================================================================

--- One ladder, in the same shape the hub already draws the header from.
local function poolSummary(e)
    local done = e.placementDone
    return {
        rp        = e.rp,
        rank      = done and Rank.get(e.rankId).name or 'Unranked',
        rankId    = done and e.rankId or 0,
        rankColor = done and Rank.get(e.rankId).color or '#5A616D',
        tier      = done and Rank.get(e.rankId).tier or 'UNRANKED',
        progress  = Rank.progress(e.rp, e.rankId, done),
        highestRank = Rank.get(e.highestRankId).name,
        placement = {
            done = done, played = e.placementPlayed,
            total = Config.Placement.matches, enabled = Config.Placement.enabled
        }
    }
end

local function poolsForClient(pd)
    Player.syncPool(pd)
    local out = {}
    -- always include the ladder the hub opens on, even for a brand new player
    out[defaultPool()] = poolSummary(Player.poolData(pd, defaultPool()))
    for name, e in pairs(pd.pools) do out[name] = poolSummary(e) end
    return out
end

local function modePoolMap()
    local out = {}
    for key, cfg in pairs(Config.Modes) do
        if cfg.enabled ~= false then out[key] = Player.poolOf(key) end
    end
    return out
end

--- Everything the client and the NUI need on open. Sensitive server config
--- (webhooks, formulas, thresholds) is never part of this payload.
function Server_BootPayload(pd)
    local showMMR = Admin.canSeeMMR(pd.userId)

    local modes = {}
    for i = 1, #Config.RankedQueueModes do
        local key = Config.RankedQueueModes[i]
        local cfg = Config.Modes[key]
        if cfg and cfg.enabled ~= false then
            modes[#modes + 1] = {
                id = key, label = cfg.label, description = cfg.description,
                teamSize = cfg.teamSize, type = cfg.type,
                rounds = cfg.rounds, roundsToWin = cfg.roundsToWin
            }
        end
    end

    local allModes = {}
    for key, cfg in pairs(Config.Modes) do
        if cfg.enabled ~= false then
            allModes[#allModes + 1] = {
                id = key, label = cfg.label, description = cfg.description,
                teamSize = cfg.teamSize, type = cfg.type
            }
        end
    end
    table.sort(allModes, function(a, b) return a.id < b.id end)

    local maps = {}
    for i = 1, #Config.Maps do
        maps[#maps + 1] = {
            id = Config.Maps[i].id, name = Config.Maps[i].name,
            image = Config.Maps[i].image, modes = Config.Maps[i].modes
        }
    end

    local weaponPresets = {}
    for i = 1, #Config.WeaponPresets do
        local w = Config.WeaponPresets[i]
        weaponPresets[#weaponPresets + 1] = { id = w.id, label = w.label }
    end

    local matchTypes = {}
    for i = 1, #Config.CustomGames.matchTypes do
        local t = Config.CustomGames.matchTypes[i]
        matchTypes[#matchTypes + 1] = { id = t.id, label = t.label, description = t.description }
    end

    local loadouts = {}
    for key, l in pairs(Config.Loadouts) do
        loadouts[#loadouts + 1] = { id = key, health = l.health, armor = l.armor, weapons = #l.weapons }
    end

    local ban = Bans.check(pd.userId, 'RANKED')

    return {
        player = {
            userId    = pd.userId,
            name      = pd.name,
            level     = pd.level,
            xp        = pd.xp,
            xpNeeded  = xpForLevel(pd.level),
            rp        = pd.rp,
            rank      = pd.placementDone and Rank.get(pd.rankId).name or 'Unranked',
            rankId    = pd.placementDone and pd.rankId or 0,
            rankColor = pd.placementDone and Rank.get(pd.rankId).color or '#5A616D',
            tier      = pd.placementDone and Rank.get(pd.rankId).tier or 'UNRANKED',
            progress  = Rank.progress(pd.rp, pd.rankId, pd.placementDone),
            highestRank = Rank.get(pd.highestRankId).name,
            placement = {
                done = pd.placementDone,
                played = pd.placementPlayed,
                total = Config.Placement.matches,
                enabled = Config.Placement.enabled
            },
            mmr       = showMMR and pd.mmr or nil,
            titles    = pd.titles,
            badges    = pd.badges,
            activeTitle = pd.activeTitle,
            frame     = pd.frame,
            settings  = pd.settings,
            position  = Board.myPosition(pd.userId),
            coins     = Store.load(pd.userId).coins,
            cosmetics = Store.cosmetics(pd.userId)
        },
        stats   = Board.profile(pd.userId, showMMR),

        -- Per-mode ranks. `pools` is every ladder this player has, `modePool`
        -- maps a mode to its ladder, and `pool` is the one the header opens
        -- on. The hub switches header and progress purely from these — no
        -- round trip when the player flips between mode tabs.
        pools    = poolsForClient(pd),
        modePool = modePoolMap(),
        pool     = defaultPool(),
        perModeRanks = (Config.RankPools or {}).perMode ~= false,

        ranks   = rankTableForClient(),
        rankPath= Config.RankPath,
        modes   = modes,
        allModes= allModes,
        partyQueue = {
            autoMode        = Config.PartyQueue.autoMode,
            lockToPartySize = Config.PartyQueue.lockToPartySize,
            fullTeamOnly    = ((Config.PartyQueue.teamMatching or {}).mode == 'fullTeam')
        },
        maps    = maps,
        loadouts= loadouts,
        weaponPresets = weaponPresets,
        matchTypes    = matchTypes,
        customDefaults = Config.CustomGames.defaults,
        customLimits   = Config.CustomGames.limits,
        maxParty = Config.Party.maxSize,
        missions= Missions.list(pd.userId),
        season  = Season.current and {
            id = Season.current.id, name = Season.current.name,
            number = Season.current.number, endsAt = Season.endsAt
        } or nil,
        adminActions = Admin.level(pd.userId) and Admin.allowed(pd.userId) or nil,
        rankBanTypes = Config.RankBan.types,
        banDurations = Config.RankBan.presetDurations,
        permissions = {
            admin        = vRP.hasPermission({ pd.userId, Config.Permissions.admin }),
            superAdmin   = vRP.hasPermission({ pd.userId, Config.Permissions.superAdmin }),
            moderator    = Admin.level(pd.userId) ~= nil,
            spectate     = vRP.hasPermission({ pd.userId, Config.Permissions.spectate }),
            createCustom = not Config.CustomGames.requirePermission
                           or vRP.hasPermission({ pd.userId, Config.Permissions.createCustom }),
            viewMMR      = showMMR
        },
        status = {
            frozen      = Config.Global.rankedFrozen,
            cooldown    = Penalty.cooldownLeft(pd.userId),
            banned      = ban and {
                type = ban.type, reason = ban.reason,
                expiry = ban.expiry, permanent = ban.expiry == 0
            } or nil,
            reconnect   = Reconnects[pd.userId] ~= nil,
            searching   = Matchmaker.searchingCount(),
            customGames = Config.CustomGames.enabled,
            training    = Config.Training.enabled
        }
    }
end

--- Resolves the calling player, applying the rate limit for the given bucket.
local function caller(bucket)
    local src = source
    local pd  = pdOf(src)
    if not pd then return nil end
    if bucket and not Security.allow(pd, bucket) then return nil end
    pd.lastSeen = ms()
    return pd, src
end

RegisterNetEvent('m5rp:sv:boot', function()
    local pd, src = caller('menu')
    if not pd then return end
    TriggerClientEvent('m5rp:cl:boot', src, Server_BootPayload(pd))
end)

RegisterNetEvent('m5rp:sv:queue', function(action, mode)
    local pd, src = caller('queue')
    if not pd then return end

    if action == 'join' then
        local ok, reason = Matchmaker.join(pd.userId, tostring(mode or ''))
        if not ok then notify(src, 'error', reason, 'QUEUE') end
    elseif action == 'leave' then
        Matchmaker.leave(pd.userId)
    end
end)

RegisterNetEvent('m5rp:sv:ready', function(checkId, accept)
    local pd = caller('queue')
    if not pd then return end
    if accept then
        Matchmaker.accept(pd.userId, checkId)
    else
        Matchmaker.decline(pd.userId, checkId)
    end
end)

RegisterNetEvent('m5rp:sv:mapVote', function(mapId)
    local pd = caller('menu')
    if not pd or not pd.matchId then return end
    local m = Matches[pd.matchId]
    if m then Match.vote(m, pd.userId, tostring(mapId or '')) end
end)

RegisterNetEvent('m5rp:sv:party', function(action, data)
    local pd, src = caller('party')
    if not pd then return end
    data = type(data) == 'table' and data or {}

    local ok, reason
    if action == 'create' then
        ok = PartyMgr.create(pd.userId) ~= nil
    elseif action == 'invite' then
        local target = resolveTarget(data.target)
        if not target then
            ok, reason = false, 'No player with that ID.'
        else
            ok, reason = PartyMgr.invite(pd.userId, target)
        end
    elseif action == 'accept' then
        ok, reason = PartyMgr.accept(pd.userId)
    elseif action == 'decline' then
        ok = PartyMgr.decline(pd.userId)
    elseif action == 'leave' then
        ok = PartyMgr.leave(pd.userId)
    elseif action == 'kick' then
        ok, reason = PartyMgr.kick(pd.userId, tonumber(data.target))
    elseif action == 'transfer' then
        ok, reason = PartyMgr.transfer(pd.userId, tonumber(data.target))
    elseif action == 'ready' then
        ok = PartyMgr.setReady(pd.userId, data.value == true)
    end

    if reason then notify(src, 'error', reason, 'PARTY') end
end)

RegisterNetEvent('m5rp:sv:custom', function(action, data)
    local pd, src = caller('custom')
    if not pd then return end
    data = type(data) == 'table' and data or {}

    local ok, reason
    if action == 'list' then
        TriggerClientEvent('m5rp:cl:custom', src, { list = CustomGames.list() })
        return
    elseif action == 'create' then
        ok, reason = CustomGames.create(pd.userId, data)
    elseif action == 'join' then
        ok, reason = CustomGames.join(pd.userId, tostring(data.roomId or ''), tostring(data.password or ''))
    elseif action == 'joinCode' then
        ok, reason = CustomGames.joinByCode(pd.userId, data.code, tostring(data.password or ''))
    elseif action == 'leave' then
        ok = CustomGames.leave(pd.userId)
    else
        ok, reason = CustomGames.host(pd.userId, action, data)
    end

    if not ok and reason then notify(src, 'error', reason, 'CUSTOM GAME') end
end)

RegisterNetEvent('m5rp:sv:combat', function(kind, data)
    local src = source
    local pd  = pdOf(src)
    if not pd then return end

    if kind == 'shot' then
        if not Security.allow(pd, 'damage') then return end
        Combat.shot(pd, data)
    elseif kind == 'dmg' then
        if not Security.allow(pd, 'damage') then return end
        Combat.damage(pd, data)
    elseif kind == 'hs' then
        if not Security.allow(pd, 'headshot') then return end
        Combat.headshot(pd, data)
    elseif kind == 'death' then
        if not Security.allow(pd, 'kill') then return end
        -- a bot match keeps its own score and never touches the ranked path
        if BotMatch.sessions[pd.userId] then
            BotMatch.playerDied(pd.userId)
        else
            Combat.death(pd, data)
        end
    elseif kind == 'oob' then
        if not Security.allow(pd, 'kill') then return end
        Combat.outOfBounds(pd)
    end
end)

--- The only thing a bot match takes from the client: a bot going down, which
--- the server cannot observe because the peds are local to that client. The
--- session is looked up by the caller's own id, so nobody can report into
--- anyone else's match, and the result is worth nothing anyway.
RegisterNetEvent('m5rp:sv:bot', function(action, data)
    local pd = caller('kill')
    if not pd then return end
    if tostring(action) == 'down' then
        BotMatch.botDown(pd.userId, type(data) == 'table' and data.headshot == true)
    end
end)

--- Store. The client sends an id and nothing else: the price, the balance and
--- whether the item is owned are all resolved here.
RegisterNetEvent('m5rp:sv:store', function(action, kind, id)
    local pd, src = caller('default')
    if not pd then return end

    action = tostring(action or '')
    kind   = tostring(kind or '')
    id     = tostring(id or '')

    local ok, res
    if action == 'buy' then
        ok, res = Store.buy(pd.userId, kind, id)
        if ok then
            notify(src, 'success', 'Purchase complete.', 'STORE')
        else
            notify(src, 'error', res, 'STORE')
        end
    elseif action == 'equip' then
        ok, res = Store.equip(pd.userId, kind, id)
        if not ok then notify(src, 'error', res, 'STORE') end
    else
        return
    end

    -- always answer with the authoritative state, successful or not
    TriggerClientEvent('m5rp:cl:data', src, {
        what = 'store', store = Store.payload(pd.userId) })
    if ok then
        Player.pushUpdate(pd.userId)
        -- a card or a title is on show to the whole party, so push the roster
        -- again rather than making everyone else wait for the next change
        if action == 'equip' then PartyMgr.sync(PartyMgr.get(pd.userId)) end
    end
end)

--- Activity heartbeat used by the AFK detector.
RegisterNetEvent('m5rp:sv:activity', function()
    local src = source
    local pd  = pdOf(src)
    if not pd or not pd.matchId then return end
    local m = Matches[pd.matchId]
    if not m then return end
    local mp = m.players[pd.userId]
    if mp then mp.lastActivity = ms() end
end)

RegisterNetEvent('m5rp:sv:fetch', function(what, data)
    local pd, src = caller(what == 'leaderboard' and 'leaderboard' or 'profile')
    if not pd then return end
    data = type(data) == 'table' and data or {}
    local showMMR = Admin.canSeeMMR(pd.userId)
    local page = math.max(1, math.min(50, tonumber(data.page) or 1))

    if what == 'leaderboard' then
        local board = tostring(data.board or 'global'):lower()
        local mode  = Config.Modes[data.mode] and data.mode or nil
        local rows, mine

        if board == 'daily' or board == 'weekly' then
            rows = Board.period(board, page, showMMR)
        elseif board == 'season' then
            rows = Board.season(tonumber(data.seasonId) or Season.id(), page)
        elseif board == 'friends' then
            rows = Board.recent(pd.userId, showMMR)
        elseif mode then
            rows = Board.byMode(mode, page, showMMR)
            mine = Board.modeStats(pd.userId, mode)
        else
            rows = Board.global(page, showMMR, Player.poolOf(data.mode))
        end

        TriggerClientEvent('m5rp:cl:data', src, {
            what = 'leaderboard', board = board, mode = mode, page = page,
            pool = Player.poolOf(mode), rows = rows,
            you = Board.myPosition(pd.userId, Player.poolOf(mode)), stats = mine
        })

    elseif what == 'profile' then
        local target = tonumber(data.userId) or pd.userId
        TriggerClientEvent('m5rp:cl:data', src, {
            what = 'profile', profile = Board.profile(target, showMMR and target == pd.userId)
        })

    elseif what == 'history' then
        TriggerClientEvent('m5rp:cl:data', src, {
            what = 'history', page = page,
            rows = Board.history(tonumber(data.userId) or pd.userId, page)
        })

    elseif what == 'matchDetail' then
        TriggerClientEvent('m5rp:cl:data', src, {
            what = 'matchDetail', detail = Board.matchDetail(tonumber(data.matchId) or 0)
        })

    elseif what == 'rewards' then
        local rows = DB.query('SELECT * FROM m5_player_rewards WHERE user_id = ? ORDER BY id DESC LIMIT 60',
            { pd.userId }) or {}
        TriggerClientEvent('m5rp:cl:data', src, {
            what = 'rewards', rows = rows,
            missions = Missions.list(pd.userId),
            achievements = Achievements.list(pd.userId),
            season = Config.Rewards.season
        })

    elseif what == 'store' then
        TriggerClientEvent('m5rp:cl:data', src, {
            what = 'store', store = Store.payload(pd.userId) })

    elseif what == 'liveMatches' then
        TriggerClientEvent('m5rp:cl:data', src, { what = 'liveMatches', rows = Board.liveMatches() })

    elseif what == 'hallOfFame' then
        local rows = DB.query([[SELECT sp.*, s.number, s.name AS season_name FROM m5_season_players sp
                                JOIN m5_seasons s ON s.id = sp.season_id
                                WHERE sp.placement = 1 ORDER BY s.number DESC LIMIT 20]]) or {}
        TriggerClientEvent('m5rp:cl:data', src, { what = 'hallOfFame', rows = rows })
    end
end)

RegisterNetEvent('m5rp:sv:admin', function(action, data)
    local pd, src = caller('admin')
    if not pd then return end
    local ok, result = Admin.handle(pd, tostring(action or ''), data)
    if ok then
        -- A change that did not reach the database must be reported now, not
        -- discovered by the player after the next restart.
        if type(result) == 'table' and result.verifyError then
            notify(src, 'error', 'NOT SAVED — %s. Check the server console.',
                'ADMIN', result.verifyError)
        end
        -- Admin.audit already wrote the row and the webhook
        TriggerClientEvent('m5rp:cl:data', src, { what = 'admin', action = action, result = result })
    else
        notify(src, 'error', result or 'Action failed.', 'ADMIN')
    end
end)

RegisterNetEvent('m5rp:sv:settings', function(settings)
    local pd = caller('settings')
    if not pd or type(settings) ~= 'table' then return end
    -- only store known keys, values are clamped client side and re-checked here
    local clean = {}
    for k, v in pairs(settings) do
        if type(k) == 'string' and #k <= 32
           and (type(v) == 'string' or type(v) == 'number' or type(v) == 'boolean') then
            if type(v) == 'string' then v = v:sub(1, 32) end
            clean[k] = v
        end
    end
    pd.settings = clean
    pd.dirtyPlayer = true
end)

RegisterNetEvent('m5rp:sv:action', function(action, data)
    local pd, src = caller('menu')
    if not pd then return end
    data = type(data) == 'table' and data or {}

    if action == 'surrender' then
        local m = pd.matchId and Matches[pd.matchId]
        if not m then return end
        local ok, reason = Match.startSurrender(m, pd.userId)
        if not ok and reason then notify(src, 'error', reason, 'SURRENDER') end

    elseif action == 'surrenderVote' then
        local m = pd.matchId and Matches[pd.matchId]
        if m then Match.surrenderVote(m, pd.userId, data.value == true) end

    elseif action == 'reconnect' then
        local ok, reason = Match.tryReconnect(pd.userId)
        if not ok then notify(src, 'error', reason, 'RECONNECT') end

    elseif action == 'leaveMatch' then
        -- the same button ends a bot match, so there is one way out
        if BotMatch.sessions[pd.userId] then
            BotMatch.stop(pd.userId, 'left')
        else
            local m = pd.matchId and Matches[pd.matchId]
            if m then Match.removePlayer(m, pd.userId, 'LEAVE') end
        end

    elseif action == 'training' then
        if data.enable then
            local ok, reason = Training.start(pd.userId, tostring(data.kind or 'range'))
            if not ok and reason then notify(src, 'error', reason, 'TRAINING') end
        else
            Training.stop(pd.userId)
        end

    elseif action == 'report' then
        local target = resolveTarget(data.target)
        if not target or target == pd.userId then return end
        DB.update('UPDATE m5_players SET reports = reports + 1 WHERE user_id = ?', { target })
        AntiBoost.flag(target, 'playerReport', 1, {
            by = pd.userId, byName = pd.name,
            reason = safeName(data.reason or '', 120)
        }, nil, pd.userId)
        notify(src, 'success', 'Your report has been submitted.', 'REPORT')

    elseif action == 'commend' then
        local target = resolveTarget(data.target)
        if not target or target == pd.userId then return end
        if pd.commendedThisMatch == pd.matchId then return end
        pd.commendedThisMatch = pd.matchId
        DB.update('UPDATE m5_players SET commendations = commendations + 1 WHERE user_id = ?', { target })
        local tpd = Players[target]
        if tpd then tpd.commendations = tpd.commendations + 1 end
        notify(src, 'success', 'Commendation sent.', 'COMMEND')

    elseif action == 'avoid' then
        local target = resolveTarget(data.target)
        if not target then return end
        Avoid[pd.userId] = Avoid[pd.userId] or {}
        local n = count(Avoid[pd.userId])
        if n >= Config.Matchmaking.avoidListSize then
            notify(src, 'warning', 'Your avoid list is full.', 'AVOID')
            return
        end
        Avoid[pd.userId][target] = now() + Config.Matchmaking.avoidDuration
        notify(src, 'success', 'Player added to your avoid list.', 'AVOID')

    elseif action == 'setTitle' then
        local title = tostring(data.title or '')
        if title == '' or inList(pd.titles, title) then
            pd.activeTitle = title
            pd.dirtyPlayer = true
        end

    elseif action == 'claimReward' then
        local key = tostring(data.key or '')
        local row = DB.single('SELECT * FROM m5_player_rewards WHERE user_id = ? AND reward_key = ? AND claimed = 0',
            { pd.userId, key })
        if not row then
            notify(src, 'error', 'Nothing to claim.', 'REWARDS')
            return
        end
        local reward = jsonDecode(row.value, {})
        if Rewards.grant(pd, reward, tonumber(row.season_id) or 0, key) then
            notify(src, 'success', 'Reward claimed.', 'REWARDS')
        end

    elseif action == 'spectateTeam' then
        local m = pd.matchId and Matches[pd.matchId]
        if not m or not Config.SpectatorRules.enabled then return end
        local mp = m.players[pd.userId]
        if not mp or mp.alive then return end
        local targets = {}
        for uidv, other in pairs(m.players) do
            if other.alive and other.connected
               and (not Config.SpectatorRules.teamOnly or m.ffa or other.team == mp.team) then
                local ts = srcOf(uidv)
                if ts then targets[#targets + 1] = { serverId = ts, name = other.name, team = other.team } end
            end
        end
        TriggerClientEvent('m5rp:cl:spectate', src, {
            matchId = m.id, enable = #targets > 0, targets = targets, team = mp.team
        })
    end
end)

-- ============================================================================
-- 21. COMMANDS
-- ============================================================================

local function cmdPlayer(src)
    local pd = pdOf(src)
    if not pd then
        if src > 0 then
            TriggerClientEvent('chatMessage', src, '^1[M5RP]^7 Your PvP profile is not loaded yet.')
        end
        return nil
    end
    return pd
end

local function registerCommand(entry, handler)
    if not entry or not entry.enabled then return end
    RegisterCommand(entry.name, function(src, args, raw)
        if src == 0 then
            -- console
            if entry.permission then
                print('[M5RP] this command must be used in game')
                return
            end
        end
        local pd = cmdPlayer(src)
        if not pd then return end
        if entry.permission and not vRP.hasPermission({ pd.userId, entry.permission }) then
            notify(src, 'error', 'You do not have permission to use this command.', 'M5 RANKED')
            return
        end
        handler(pd, src, args, raw)
    end, false)
end

registerCommand(Config.Commands.pvp, function(pd, src)
    TriggerClientEvent('m5rp:cl:openMenu', src)
end)

registerCommand(Config.Commands.rank, function(pd, src)
    local rank = pd.placementDone and Rank.get(pd.rankId) or Rank.get(0)
    local progress = Rank.progress(pd.rp, pd.rankId, pd.placementDone)
    notify(src, 'info', '%s — %d RP%s', 'YOUR RANK',
        rank.name, pd.rp,
        progress.next and _Lf(' • %d RP to %s', progress.needed, progress.next) or '')
end)

registerCommand(Config.Commands.leaderboard, function(pd, src)
    TriggerClientEvent('m5rp:cl:openMenu', src, 'leaderboard')
end)

registerCommand(Config.Commands.customgame, function(pd, src)
    TriggerClientEvent('m5rp:cl:openMenu', src, 'custom')
end)

registerCommand(Config.Commands.reconnectpvp, function(pd, src)
    local ok, reason = Match.tryReconnect(pd.userId)
    if not ok then notify(src, 'error', reason, 'RECONNECT') end
end)

registerCommand(Config.Commands.pvpadmin, function(pd, src)
    if not Admin.level(pd.userId) then
        notify(src, 'error', 'You do not have access to the admin panel.', 'ADMIN')
        return
    end
    TriggerClientEvent('m5rp:cl:openMenu', src, 'admin')
end)

registerCommand(Config.Commands.rankban, function(pd, src, args)
    -- /rankban <userId|name> <minutes> <reason...>
    if #args < 3 then
        notify(src, 'warning', 'Usage: /%s <userId> <minutes> <reason>', 'RANK BAN', Config.Commands.rankban.name)
        return
    end
    local ok, result = Admin.handle(pd, 'ban', {
        target   = args[1],
        duration = math.max(0, math.floor((tonumber(args[2]) or 0) * 60)),
        reason   = table.concat(args, ' ', 3),
        type     = 'RANKED'
    })
    notify(src, ok and 'success' or 'error',
        ok and 'Ranked ban applied.' or tostring(result), 'RANK BAN')
end)

registerCommand(Config.Commands.rankunban, function(pd, src, args)
    if #args < 1 then
        notify(src, 'warning', 'Usage: /%s <userId>', 'RANK UNBAN', Config.Commands.rankunban.name)
        return
    end
    local ok, result = Admin.handle(pd, 'unban', { target = args[1] })
    notify(src, ok and 'success' or 'error',
        ok and 'Ranked bans removed.' or tostring(result), 'RANK UNBAN')
end)

registerCommand(Config.Commands.setrank, function(pd, src, args)
    if #args < 3 then
        notify(src, 'warning', 'Usage: /%s <userId> <rankId 0-23> <reason>', 'SET RANK', Config.Commands.setrank.name)
        return
    end
    local ok, result = Admin.handle(pd, 'setRank', {
        target = args[1], rankId = tonumber(args[2]), reason = table.concat(args, ' ', 3) })
    notify(src, ok and 'success' or 'error',
        ok and ('Rank set to %s.'):format(result.rank) or tostring(result), 'SET RANK')
end)

registerCommand(Config.Commands.setrp, function(pd, src, args)
    if #args < 3 then
        notify(src, 'warning', 'Usage: /%s <userId> <rp> <reason>', 'SET RP', Config.Commands.setrp.name)
        return
    end
    local ok, result = Admin.handle(pd, 'setRP', {
        target = args[1], value = tonumber(args[2]), reason = table.concat(args, ' ', 3) })
    notify(src, ok and 'success' or 'error',
        ok and ('RP set to %d (%s).'):format(result.rp, result.rank) or tostring(result), 'SET RP')
end)

-- Compensate or deduct RP straight from chat.
registerCommand(Config.Commands.givepvprp, function(pd, src, args)
    if #args < 3 then
        notify(src, 'warning', 'Usage: /givepvprp <userId> <amount> <reason>', 'RP')
        return
    end
    local amount = tonumber(args[2]) or 0
    local ok, result = Admin.handle(pd, amount >= 0 and 'addRP' or 'removeRP', {
        target = args[1], amount = math.abs(amount), reason = table.concat(args, ' ', 3) })
    notify(src, ok and 'success' or 'error',
        ok and ('%s%d RP → %d total.'):format(result.delta > 0 and '+' or '', result.delta, result.rp)
             or tostring(result), 'RP')
end)

registerCommand(Config.Commands.pvpstatus, function(pd, src)
    local live, queued = count(Matches), Matchmaker.searchingCount()
    notify(src, 'info', ('Matches: %d • Searching: %d • Rooms: %d • Online profiles: %d • Season: %s')
        :format(live, queued, count(CustomGames.rooms), count(Players),
                Season.current and Season.current.name or 'none'), 'PVP STATUS')
    print(('[M5RP] status — matches:%d queued:%d rooms:%d players:%d buckets:%d')
        :format(live, queued, count(CustomGames.rooms), count(Players), count(UsedBuckets)))
end)

--- Server console only: prints what a player's rank looks like in memory next
--- to what is actually stored, so "the grant did not stick" can be answered
--- with evidence instead of a guess. Usage: m5rankinfo <userId>
RegisterCommand('m5rankinfo', function(src, args)
    if src ~= 0 then return end            -- console only, never a chat command

    local userId = tonumber(args and args[1])
    if not userId then
        print('[M5RP] usage: m5rankinfo <userId>')
        return
    end

    local seasonId = Season.id()
    print(('[M5RP] ---- rank report for user %d ----'):format(userId))
    print(('[M5RP] season: %s (id %d)')
        :format(Season.current and Season.current.name or 'NONE', seasonId))

    local pd = Players[userId]
    if pd then
        Player.syncPool(pd)
        print(('[M5RP] active ladder: %s'):format(tostring(pd.pool)))
        for pool, e in pairs(pd.pools) do
            local d = pd.poolDirty[pool] or {}
            print(('[M5RP] memory  [%s]: rp=%d rankId=%d (%s) placementDone=%s dirty=%s')
                :format(pool, e.rp, e.rankId, Rank.get(e.rankId).name,
                        tostring(e.placementDone), tostring(d.rank == true)))
        end
    else
        print('[M5RP] memory : not loaded (player offline)')
    end

    local rows = DB.query('SELECT * FROM m5_player_ranks WHERE user_id = ? AND season_id = ?',
        { userId, seasonId }) or {}
    if #rows > 0 then
        for i = 1, #rows do
            local row = rows[i]
            -- the Lua type matters: oxmysql hands TINYINT(1) back as a boolean
            -- on current versions and as a number on older ones
            print(('[M5RP] database[%s]: rp=%s rank_id=%s (%s) placement_done=%s (lua type: %s -> %s)')
                :format(tostring(row.mode), tostring(row.rp), tostring(row.rank_id),
                        Rank.get(tonumber(row.rank_id) or 0).name, tostring(row.placement_done),
                        type(row.placement_done), tostring(toBool(row.placement_done))))
        end
    else
        print(('[M5RP] database: NO ROW for season %d'):format(seasonId))
    end

    if rows[1] and rows[1].mode == nil then
        print('[M5RP] ^3WARNING: this table has no `mode` column — the per-mode rank ' ..
              'migration has not run. Restart the resource with ' ..
              'Config.Database.autoCreateTables on, or run the ALTERs by hand.')
    end

    -- rows written before the season was known are the classic cause of a
    -- grant that reappears as Unranked on the next join
    local orphan = DB.single('SELECT * FROM m5_player_ranks WHERE user_id = ? AND season_id = 0',
        { userId })
    if orphan then
        print(('[M5RP] ^3WARNING: a season-0 row exists for this player (rp=%s rank_id=%s). ' ..
               'It was written before the season loaded and is never read back. ' ..
               'Re-grant the rank, then delete it.')
            :format(tostring(orphan.rp), tostring(orphan.rank_id)))
    end
    print('[M5RP] --------------------------------')
end, true)

-- ============================================================================
-- 22. LIFECYCLE & MASTER LOOP
-- ============================================================================

--- vRP fires this once the user is fully loaded and spawned.
AddEventHandler('vRP:playerSpawn', function(user_id, source, first_spawn)
    if not first_spawn then return end
    local src = source
    Citizen.CreateThread(function()
        -- Never load a profile before the schema and the active season are
        -- known, or its per-season rows would be stamped with season 0.
        if not waitForBoot() then
            err('player %s spawned but the resource never finished booting', tostring(user_id))
            return
        end

        local pd = Player.load(user_id, src)
        if not pd then return end
        Bans.load(user_id)
        Missions.ensure(pd)

        -- offer a reconnect if the player dropped out of a live match
        local info = Reconnects[user_id]
        if info and info.expires > now() and Matches[info.matchId] then
            TriggerClientEvent('m5rp:cl:notify', src, {
                kind = 'warning', title = 'RECONNECT AVAILABLE',
                message = ('You can rejoin your match (/%s)'):format(Config.Commands.reconnectpvp.name)
            })
        end
        TriggerClientEvent('m5rp:cl:boot', src, Server_BootPayload(pd))
    end)
end)

AddEventHandler('vRP:playerLeave', function(user_id, source)
    local pd = Players[user_id]
    if not pd then return end

    Matchmaker.leave(user_id, true)

    for _, rc in pairs(ReadyChecks) do
        if rc.users[user_id] ~= nil then
            rc.users[user_id] = false
            failReadyCheck(rc, user_id)
            break
        end
    end

    if pd.partyId then PartyMgr.leave(user_id) end

    if pd.matchId and Matches[pd.matchId] then
        Match.removePlayer(Matches[pd.matchId], user_id, 'DISCONNECT')
    end

    if CustomGames.of(user_id) then CustomGames.leave(user_id) end
    if Training.players[user_id] then Training.stop(user_id) end
    if BotMatch.sessions[user_id] then BotMatch.stop(user_id, 'disconnected') end
    Store.forget(user_id)

    SrcToUser[pd.source or source] = nil
    UserToSrc[user_id] = nil

    Player.save(pd, true)
end)

-- Safety net: a raw drop that vRP did not report yet.
AddEventHandler('playerDropped', function()
    local src = source
    local userId = SrcToUser[src]
    if not userId then return end
    SrcToUser[src] = nil
    local pd = Players[userId]
    if pd and pd.source == src then
        TriggerEvent('vRP:playerLeave', userId, src)
    end
end)

-- ---------------------------------------------------------------------------
-- Master loop: one thread drives every periodic subsystem.
-- ---------------------------------------------------------------------------

local TICK = Config.Match.tickInterval or 250

Citizen.CreateThread(function()
    -- boot sequence
    Citizen.Wait(1500)

    DB.init()
    Season.load()

    -- From here on a profile can be loaded safely: the tables exist and
    -- Season.id() returns the real season instead of 0.
    Boot.ready = true

    registerVrpMenu()

    -- pick up players who were already connected (resource restart)
    for _, playerSrc in ipairs(GetPlayers()) do
        local src = tonumber(playerSrc)
        -- A player who is still connecting has no identifiers yet. Handing that
        -- to vRP fails inside the framework, so skip them here and let
        -- vRP:playerSpawn pick them up instead.
        if src and GetPlayerName(src) and GetNumPlayerIdentifiers(src) > 0 then
            local ok, userId = pcall(function() return vRP.getUserId({ src }) end)
            if ok and userId then
                local pd = Player.load(userId, src)
                if pd then
                    Bans.load(userId)
                    TriggerClientEvent('m5rp:cl:boot', src, Server_BootPayload(pd))
                end
            end
        end
    end

    log('M5 Ranked PvP is ready (%d ranks, %d modes, %d maps)',
        #Config.Ranks, count(Config.Modes), #Config.Maps)

    local acc = { mm = 0, flush = 0, hook = 0, season = 0, rooms = 0, afk = 0 }

    while true do
        Citizen.Wait(TICK)
        local dt = TICK

        -- ---- match state machines --------------------------------------
        for _, m in pairs(Matches) do
            local ok, e = pcall(Match.tick, m)
            if not ok then
                err('match tick failed (%s): %s', tostring(m.id), tostring(e))
                Logger.send('errors', 'Match Tick Error', tostring(e))
            end
        end

        -- ---- bot matches (staff practice sessions) ----------------------
        if next(BotMatch.sessions) then
            local ok, e = pcall(BotMatch.tick)
            if not ok then err('bot match tick failed: %s', tostring(e)) end
        end

        -- ---- matchmaking -----------------------------------------------
        acc.mm = acc.mm + dt
        if acc.mm >= Config.Matchmaking.tickInterval then
            acc.mm = 0
            local ok, e = pcall(Matchmaker.tick)
            if not ok then err('matchmaking tick failed: %s', tostring(e)) end
        end

        -- ---- custom room housekeeping ----------------------------------
        acc.rooms = acc.rooms + dt
        if acc.rooms >= 15000 then
            acc.rooms = 0
            pcall(CustomGames.tick)

            -- expired reconnect windows
            for userId, info in pairs(Reconnects) do
                if info.expires <= now() then
                    Reconnects[userId] = nil
                    local m = Matches[info.matchId]
                    if m and m.state ~= 'CLEANUP' and m.state ~= 'MATCH_END' then
                        Penalty.apply(userId, 'LEAVE', m.dbId, false)
                    end
                end
            end

            -- audit log retention
            local keepDays = Config.AdminLimits.auditRetentionDays or 0
            if keepDays > 0 then
                DB.update('DELETE FROM m5_admin_logs WHERE created_at < ?',
                    { sqlDate(now() - keepDays * 86400) })
            end

            -- expired avoid entries
            for userId, list in pairs(Avoid) do
                for other, expiry in pairs(list) do
                    if expiry <= now() then list[other] = nil end
                end
            end
        end

        -- ---- batched database flush ------------------------------------
        acc.flush = acc.flush + dt
        if acc.flush >= Config.Database.flushInterval then
            acc.flush = 0
            local ok, e = pcall(Player.saveAll)
            if not ok then err('flush failed: %s', tostring(e)) end
        end

        -- ---- discord webhooks ------------------------------------------
        acc.hook = acc.hook + dt
        if acc.hook >= Config.Webhooks.batchInterval then
            acc.hook = 0
            pcall(Logger.flush)
        end

        -- ---- season rollover -------------------------------------------
        acc.season = acc.season + dt
        if acc.season >= Config.Seasons.checkInterval then
            acc.season = 0
            if Config.Seasons.enabled and Season.endsAt > 0 and now() >= Season.endsAt then
                local ok, e = pcall(Seasons.rollover, nil)
                if not ok then err('season rollover failed: %s', tostring(e)) end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Shutdown
-- ---------------------------------------------------------------------------

--- Shutdown is best effort and must never be the only place a change is
--- written. A stopping resource is torn down as soon as its handlers return,
--- so an awaited query here can fail to resume and everything after it is
--- skipped. That is why staff actions and match results save the moment they
--- happen; this handler only catches whatever the interval flush has not
--- reached yet. The two markers below make it obvious in the console whether
--- the save actually completed.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= RES then return end

    -- players first: their profiles are what matters if the runtime is cut off
    local pending = count(Players)
    log('resource stopping — saving %d profiles', pending)
    Player.saveAll()
    log('resource stopped — %d profiles saved', pending)

    for _, m in pairs(Matches) do
        for userId in pairs(m.players) do
            local s = srcOf(userId)
            if s then SetPlayerRoutingBucket(s, 0) end
        end
        if m.dbId then
            DB.update("UPDATE m5_matches SET state = 'CLEANUP', end_reason = 'RESOURCE_STOP', ended_at = ? WHERE id = ?",
                { sqlDate(), m.dbId })
        end
    end

    for userId in pairs(Training.players) do
        local s = srcOf(userId)
        if s then SetPlayerRoutingBucket(s, 0) end
    end

    for userId in pairs(BotMatch.sessions) do
        local s = srcOf(userId)
        if s then
            TriggerClientEvent('m5rp:cl:bots', s, { clear = true })
            SetPlayerRoutingBucket(s, 0)
        end
    end

    Logger.flush()
end)

-- ---------------------------------------------------------------------------
-- Exports — for other resources. Read only, nothing here changes state.
-- ---------------------------------------------------------------------------

exports('isInMatch', function(userId)
    local pd = Players[tonumber(userId) or -1]
    return pd ~= nil and pd.matchId ~= nil and Matches[pd.matchId] ~= nil
end)

exports('getMatchInfo', function(userId)
    local pd = Players[tonumber(userId) or -1]
    if not pd or not pd.matchId then return nil end
    local m = Matches[pd.matchId]
    if not m then return nil end
    return {
        matchId = m.id, mode = m.mode, ranked = m.ranked,
        custom = m.customId ~= nil, state = m.state, round = m.round,
        scores = { a = m.scores[1], b = m.scores[2] },
        team = pd.team, map = m.map and m.map.id or nil
    }
end)

exports('getPlayerRank', function(userId)
    local pd = Players[tonumber(userId) or -1]
    if not pd then return nil end
    return {
        rankId = pd.rankId, rank = Rank.get(pd.rankId).name,
        rp = pd.rp, mmr = pd.mmr, level = pd.level,
        placementDone = pd.placementDone
    }
end)

exports('getPlayerStats', function(userId)
    local pd = Players[tonumber(userId) or -1]
    return pd and pd.stats or nil
end)

-- Keep the winner reference for custom game bookkeeping.
local _endMatch = Match.endMatch
Match.endMatch = function(m, winner, reason)
    m.lastWinner = winner
    return _endMatch(m, winner, reason)
end

