--[[
    ============================================================================
     M5 Ranked PvP — Config_Server.lua
    ----------------------------------------------------------------------------
     SERVER SIDE SETTINGS ONLY.
     This file is loaded exclusively as a server_script (see fxmanifest.lua) and
     is never sent to any client. Webhooks, permissions, RP formulas, anti-cheat
     thresholds and reward payloads all live here.
    ============================================================================
]]

Config = {}

Config.Debug          = false
Config.ServerName     = 'M5 Competitive'
Config.DefaultLocale  = 'en'

-- ============================================================================
-- 1. FRAMEWORK (vRP)
-- ============================================================================

Config.vRP = {
    -- Register an entry inside the vRP main menu
    registerMenu = {
        enabled     = true,
        menu        = 'main',       -- vRP menu builder target
        name        = 'PvP Ranked',
        description = 'M5 Ranked PvP — Competitive Hub'
    }

    -- Display names come from GetPlayerName only. vRP.getUserIdentity is
    -- callback based and cannot return through the synchronous Proxy, so it is
    -- deliberately not used anywhere in this resource.
}

-- ============================================================================
-- 2. DATABASE (oxmysql)
-- ============================================================================

Config.Database = {
    tablePrefix          = 'm5_',
    autoCreateTables     = true,   -- run the schema on resource start if missing
    -- Batched writes: stats are flushed on this interval instead of per event.
    flushInterval        = 30000,  -- ms
    -- Cache lifetime for read-mostly data
    leaderboardCacheTime = 60000,  -- ms
    profileCacheTime     = 30000,  -- ms
    -- Rows fetched per leaderboard / history page
    pageSize             = 25,
    historyPageSize      = 12,
    -- Maximum rows kept in the kill log per match (protection against spam)
    maxKillRowsPerMatch  = 800
}

-- ============================================================================
-- 3. PERMISSIONS (vRP permission strings)
-- ============================================================================

Config.Permissions = {
    -- ------------------------------------------------------------------
    -- SUPER PERMISSION
    -- A player holding this can perform EVERY admin action below without
    -- needing any of the individual permissions. Give it to owners only.
    -- ------------------------------------------------------------------
    superAdmin = 'pvp.all',

    -- Holding the generic admin permission also unlocks every action.
    -- Set to false if you want strict per action control even for admins.
    adminGrantsAll = true,

    -- ---- gameplay -----------------------------------------------------
    openMenu      = 'pvp.menu',
    createCustom  = 'pvp.custom.create',
    spectate      = 'pvp.spectate',
    viewMMR       = 'pvp.mmr',

    -- ---- staff tiers ---------------------------------------------------
    -- moderator: opens the admin panel in read only unless given more
    -- admin: full staff, subject to adminGrantsAll
    moderator     = 'pvp.moderator',
    admin         = 'pvp.admin',

    -- ---- legacy aliases (kept so existing setups keep working) --------
    manageBans    = 'pvp.bans',
    manageSeasons = 'pvp.seasons',
    manageRewards = 'pvp.rewards',
    manageMaps    = 'pvp.maps',
    modifyRP      = 'pvp.rp.modify'
}

-- ============================================================================
-- 3b. ADMIN ACTIONS — one permission per action
-- ============================================================================
-- Every entry in the admin panel is declared here. The server refuses any
-- action whose permission the caller does not hold, and the panel only renders
-- the controls the caller is allowed to use.
--
--   permission : vRP permission string required for the action
--   label      : shown in the panel and in the audit log
--   reason     : true = a reason is mandatory
--   confirm    : true = the panel asks for confirmation first
--   group      : which panel section the control belongs to

Config.AdminActions = {
    -- ---- monitoring ---------------------------------------------------
    dashboard     = { permission = 'pvp.admin.view',         label = 'View Dashboard',      group = 'monitor' },
    playerLookup  = { permission = 'pvp.admin.view',         label = 'Player Lookup',       group = 'monitor' },
    spectate      = { permission = 'pvp.admin.spectate',     label = 'Spectate Match',      group = 'monitor' },
    stopSpectate  = { permission = 'pvp.admin.spectate',     label = 'Stop Spectating',     group = 'monitor' },

    -- ---- match control -------------------------------------------------
    endMatch      = { permission = 'pvp.admin.match.end',    label = 'Force End Match',     group = 'match', confirm = true, reason = true },
    restartRound  = { permission = 'pvp.admin.match.round',  label = 'Restart Round',       group = 'match' },
    movePlayer    = { permission = 'pvp.admin.match.move',   label = 'Move Player Team',    group = 'match' },
    kickFromMatch = { permission = 'pvp.admin.match.kick',   label = 'Kick From Match',     group = 'match', reason = true },
    closeRoom     = { permission = 'pvp.admin.custom.close', label = 'Close Custom Room',   group = 'match', confirm = true },
    freeze        = { permission = 'pvp.admin.freeze',       label = 'Freeze Ranked Queue', group = 'match', confirm = true },
    startBotMatch = { permission = 'pvp.admin.botmatch',     label = 'Start Bot Match',     group = 'match' },
    stopBotMatch  = { permission = 'pvp.admin.botmatch',     label = 'Stop Bot Match',      group = 'match' },

    -- ---- points ---------------------------------------------------------
    addRP         = { permission = 'pvp.admin.rp.add',       label = 'Compensate RP',       group = 'points', reason = true },
    removeRP      = { permission = 'pvp.admin.rp.remove',    label = 'Deduct RP',           group = 'points', reason = true },
    setRP         = { permission = 'pvp.admin.rp.set',       label = 'Set RP',              group = 'points', reason = true },
    setRank       = { permission = 'pvp.admin.rank.set',     label = 'Set Rank',            group = 'points', reason = true },
    addXP         = { permission = 'pvp.admin.xp',           label = 'Grant XP',            group = 'points', reason = true },
    giveCoins     = { permission = 'pvp.admin.coins',        label = 'Give Coins',          group = 'points', reason = true },
    takeCoins     = { permission = 'pvp.admin.coins',        label = 'Take Coins',          group = 'points', reason = true },
    resetStats    = { permission = 'pvp.admin.stats.reset',  label = 'Reset Season Stats',  group = 'points', confirm = true, reason = true },

    -- ---- punishments ----------------------------------------------------
    ban           = { permission = 'pvp.admin.ban',          label = 'Ranked Ban',          group = 'punish', reason = true },
    unban         = { permission = 'pvp.admin.unban',        label = 'Remove Ranked Ban',   group = 'punish' },
    clearCooldown = { permission = 'pvp.admin.cooldown',     label = 'Clear Queue Cooldown',group = 'punish' },
    reviewFlag    = { permission = 'pvp.admin.antiboost',    label = 'Review Anti-Boost Flag', group = 'punish' },

    -- ---- system ---------------------------------------------------------
    newSeason     = { permission = 'pvp.admin.season',       label = 'Start New Season',    group = 'system', confirm = true },
    toggleMode    = { permission = 'pvp.admin.mode',         label = 'Enable / Disable Mode', group = 'system' },
    auditLog      = { permission = 'pvp.admin.audit',        label = 'View Audit Log',      group = 'system' }
}

-- Limits applied to point adjustments, so a typo cannot wreck a ladder.
Config.AdminLimits = {
    maxRPGrant   = 2000,   -- per single addRP
    maxRPDeduct  = 2000,   -- per single removeRP
    maxXPGrant   = 100000,
    maxCoinGrant = 100000,   -- per single Give Coins / Take Coins
    reasonMinLen = 3,
    reasonMaxLen = 200,
    -- Keep audit rows for this many days (0 = forever)
    auditRetentionDays = 90
}

-- Anyone may open the menu when this is true (openMenu permission ignored)
Config.PublicMenu = true

-- ============================================================================
-- 4. DISCORD WEBHOOKS
-- ============================================================================
-- Leave a value empty ('') to disable that specific log channel.

Config.Webhooks = {
    enabled = true,

    botName   = 'M5 Ranked PvP',
    avatar    = '',
    -- Logs are queued and sent in batches to avoid rate limits.
    batchInterval = 4000,
    maxQueue      = 400,

    urls = {
        matchStart   = '',
        matchEnd     = '',
        rpGain       = '',
        rpLoss       = '',
        rankUp       = '',
        rankDown     = '',
        leave        = '',
        afk          = '',
        rankBan      = '',
        unban        = '',
        rpModify     = '',
        customGame   = '',
        antiBoost    = '',
        adminActions = '',
        errors       = ''
    },

    colors = {
        matchStart   = 3447003,
        matchEnd     = 3066993,
        rpGain       = 3066993,
        rpLoss       = 15158332,
        rankUp       = 16766720,
        rankDown     = 10038562,
        leave        = 15158332,
        afk          = 15105570,
        rankBan      = 10038562,
        unban        = 3066993,
        rpModify     = 16776960,
        customGame   = 2123412,
        antiBoost    = 15158332,
        adminActions = 9807270,
        errors       = 16711680
    }
}

-- ============================================================================
-- 5. RANKS
-- ============================================================================
-- `rpRequired` is the cumulative RP needed to enter that division.
-- Order matters: the list must be sorted ascending by rpRequired.

Config.Ranks = {
    { id = 0,  tier = 'UNRANKED',  division = 0, name = 'Unranked',      rpRequired = 0,    color = '#5A616D' },

    { id = 1,  tier = 'IRON',      division = 1, name = 'Iron I',        rpRequired = 0,    color = '#7C7C80' },
    { id = 2,  tier = 'IRON',      division = 2, name = 'Iron II',       rpRequired = 100,  color = '#7C7C80' },
    { id = 3,  tier = 'IRON',      division = 3, name = 'Iron III',      rpRequired = 200,  color = '#7C7C80' },

    { id = 4,  tier = 'BRONZE',    division = 1, name = 'Bronze I',      rpRequired = 300,  color = '#A3703C' },
    { id = 5,  tier = 'BRONZE',    division = 2, name = 'Bronze II',     rpRequired = 400,  color = '#A3703C' },
    { id = 6,  tier = 'BRONZE',    division = 3, name = 'Bronze III',    rpRequired = 500,  color = '#A3703C' },

    { id = 7,  tier = 'SILVER',    division = 1, name = 'Silver I',      rpRequired = 600,  color = '#B9C1CC' },
    { id = 8,  tier = 'SILVER',    division = 2, name = 'Silver II',     rpRequired = 700,  color = '#B9C1CC' },
    { id = 9,  tier = 'SILVER',    division = 3, name = 'Silver III',    rpRequired = 800,  color = '#B9C1CC' },

    { id = 10, tier = 'GOLD',      division = 1, name = 'Gold I',        rpRequired = 900,  color = '#E8B33C' },
    { id = 11, tier = 'GOLD',      division = 2, name = 'Gold II',       rpRequired = 1000, color = '#E8B33C' },
    { id = 12, tier = 'GOLD',      division = 3, name = 'Gold III',      rpRequired = 1100, color = '#E8B33C' },

    { id = 13, tier = 'PLATINUM',  division = 1, name = 'Platinum I',    rpRequired = 1200, color = '#37C2D8' },
    { id = 14, tier = 'PLATINUM',  division = 2, name = 'Platinum II',   rpRequired = 1300, color = '#37C2D8' },
    { id = 15, tier = 'PLATINUM',  division = 3, name = 'Platinum III',  rpRequired = 1400, color = '#37C2D8' },

    { id = 16, tier = 'DIAMOND',   division = 1, name = 'Diamond I',     rpRequired = 1500, color = '#8E6BFF' },
    { id = 17, tier = 'DIAMOND',   division = 2, name = 'Diamond II',    rpRequired = 1620, color = '#8E6BFF' },
    { id = 18, tier = 'DIAMOND',   division = 3, name = 'Diamond III',   rpRequired = 1740, color = '#8E6BFF' },

    { id = 19, tier = 'ASCENDANT', division = 1, name = 'Ascendant I',   rpRequired = 1860, color = '#22C97C' },
    { id = 20, tier = 'ASCENDANT', division = 2, name = 'Ascendant II',  rpRequired = 1990, color = '#22C97C' },
    { id = 21, tier = 'ASCENDANT', division = 3, name = 'Ascendant III', rpRequired = 2120, color = '#22C97C' },

    { id = 22, tier = 'IMMORTAL',  division = 0, name = 'Immortal',      rpRequired = 2260, color = '#E0304E' },
    { id = 23, tier = 'RADIANT',   division = 0, name = 'Radiant',       rpRequired = 2600, color = '#FFE9A8' }
}

-- Rank tier order used by the progress path in the UI
Config.RankPath = {
    'IRON', 'BRONZE', 'SILVER', 'GOLD', 'PLATINUM',
    'DIAMOND', 'ASCENDANT', 'IMMORTAL', 'RADIANT'
}

Config.RankSettings = {
    -- RP floor: a player can never fall below the base RP of their tier
    demotionProtection   = true,
    -- Number of matches after promotion where a demotion is blocked
    rankProtectionGames  = 2,
    -- After N consecutive losses the RP loss is reduced by this factor
    loseStreakProtection = { enabled = true, afterLosses = 3, lossMultiplier = 0.6 },
    -- Radiant is capped to the top N players of the season (0 = uncapped)
    radiantSlots         = 25,
    -- Absolute RP boundaries
    minRP = 0,
    maxRP = 9999
}

-- ============================================================================
-- 6. RANKED POINTS (RP)
-- ============================================================================

Config.RankedPoints = {
    winBase  = 20,
    lossBase = 18,

    minimumGain = 8,
    maximumGain = 40,

    minimumLoss = 5,
    maximumLoss = 45,

    mvpBonus            = 5,
    headshotBonusLimit  = 4,

    winStreakBonus = 3,

    leavePenalty = 35,
    afkPenalty   = 25,

    -- ------------------------------------------------------------------
    -- Weighted performance model.
    -- Final RP = base  ± roundDiff  ± skillDelta  + performance  + bonuses
    -- ------------------------------------------------------------------
    weights = {
        -- Round difference (dominance). Each round of margin adds/removes RP.
        roundDiffPerRound   = 1.2,
        roundDiffMax        = 8,

        -- Opponent strength: (avgEnemyMMR - avgAllyMMR) / mmrScale * factor
        mmrScale            = 100,
        mmrFactorWin        = 4.0,   -- beating stronger teams gives more
        mmrFactorLoss       = 3.0,   -- losing to stronger teams costs less

        -- Rank gap (average enemy rank id - own rank id)
        rankGapFactor       = 0.8,
        rankGapMax          = 6,

        -- Individual performance vs the lobby average (0.0 .. 2.0 normalised)
        kdWeight            = 3.0,
        killsWeight         = 2.5,
        damageWeight        = 2.0,
        headshotWeight      = 1.5,
        clutchWeight        = 1.5,
        objectiveWeight     = 1.5,

        -- Team contribution share (your score / team score)
        teamShareWeight     = 2.0,

        -- Balanced match modifier: unbalanced games are worth less
        unbalancedPenalty   = 0.75,
        balancedThresholdMMR= 250,

        -- Performance can never move the result the wrong way
        maxPerformanceBonus = 12,
        maxPerformanceMalus = 10
    },

    -- Placement matches award no RP but seed MMR
    placementRPPerWin  = 0,
    -- Extra RP for short win streaks (index = streak length, capped)
    streakTable = { [3] = 3, [5] = 6, [8] = 9, [12] = 12 },

    -- Custom games never award RP unless Config.CustomGames.rankedAllowed
    customGameRP = false
}

-- ============================================================================
-- 7. MMR (hidden)
-- ============================================================================

Config.MMR = {
    startValue      = 1000,
    min             = 100,
    max             = 5000,

    -- Elo style K factor, scaled by confidence
    kBase           = 32,
    kPlacement      = 64,     -- during placement matches
    kHighRank       = 20,     -- above highRankThreshold
    highRankThreshold = 2000,

    -- Uncertainty decays as the player plays more matches
    uncertaintyStart  = 350,
    uncertaintyMin    = 60,
    uncertaintyDecay  = 12,   -- per completed match

    -- Performance influence on MMR (0 = pure win/loss elo)
    performanceFactor = 0.35,

    -- MMR shown to staff only
    visibleTo = 'admin' -- 'admin' | 'moderator' | 'none'
}

-- ============================================================================
-- 8. PLACEMENT
-- ============================================================================

Config.Placement = {
    enabled = true,
    matches = 5,

    -- Rank id assigned per performance score bucket after placements
    -- score = weighted (winrate, kd, hs%, damage, mvp, opponent strength)
    resultTable = {
        { minScore = 0.00, rankId = 1  }, -- Iron I
        { minScore = 0.20, rankId = 3  }, -- Iron III
        { minScore = 0.32, rankId = 5  }, -- Bronze II
        { minScore = 0.42, rankId = 7  }, -- Silver I
        { minScore = 0.52, rankId = 9  }, -- Silver III
        { minScore = 0.60, rankId = 11 }, -- Gold II
        { minScore = 0.68, rankId = 13 }, -- Platinum I
        { minScore = 0.76, rankId = 15 }, -- Platinum III
        { minScore = 0.84, rankId = 16 }, -- Diamond I
        { minScore = 0.92, rankId = 18 }  -- Diamond III
    },

    -- Weighting used to compute the placement score
    weights = {
        winRate     = 0.40,
        kd          = 0.20,
        headshotPct = 0.12,
        damage      = 0.13,
        mvp         = 0.07,
        opponentMMR = 0.08
    }
}

-- ============================================================================
-- 9. GAME MODES
-- ============================================================================

Config.Modes = {

    ['1v1'] = {
        label       = '1V1',
        description = 'Pure aim duel. First to 7 rounds.',
        teamSize    = 1,
        teams       = 2,
        ranked      = true,
        type        = 'rounds',           -- rounds | deathmatch | ffa | snd
        rounds      = 13,                 -- best of
        roundsToWin = 7,
        roundTime   = 90,
        matchTime   = 1800,
        killLimit   = 0,
        respawn     = false,
        lives       = 1,
        friendlyFire= false,
        overtime    = true,
        suddenDeath = true,
        loadout     = 'duel',
        enabled     = true
    },

    ['2v2'] = {
        label = '2V2', description = 'Duo tactical rounds.',
        teamSize = 2, teams = 2, ranked = true, type = 'rounds',
        rounds = 13, roundsToWin = 7, roundTime = 100, matchTime = 2400,
        killLimit = 0, respawn = false, lives = 1, friendlyFire = false,
        overtime = true, suddenDeath = true, loadout = 'standard', enabled = true
    },

    ['3v3'] = {
        label = '3V3', description = 'Trio competitive rounds.',
        teamSize = 3, teams = 2, ranked = true, type = 'rounds',
        rounds = 13, roundsToWin = 7, roundTime = 110, matchTime = 2700,
        killLimit = 0, respawn = false, lives = 1, friendlyFire = false,
        overtime = true, suddenDeath = true, loadout = 'standard', enabled = true
    },

    ['4v4'] = {
        label = '4V4', description = 'Squad rounds.',
        teamSize = 4, teams = 2, ranked = true, type = 'rounds',
        rounds = 15, roundsToWin = 8, roundTime = 120, matchTime = 3000,
        killLimit = 0, respawn = false, lives = 1, friendlyFire = false,
        overtime = true, suddenDeath = true, loadout = 'standard', enabled = true
    },

    ['5v5'] = {
        label = '5V5', description = 'The flagship competitive mode.',
        teamSize = 5, teams = 2, ranked = true, type = 'rounds',
        rounds = 25, roundsToWin = 13, roundTime = 120, matchTime = 3600,
        killLimit = 0, respawn = false, lives = 1, friendlyFire = false,
        overtime = true, suddenDeath = true, loadout = 'standard', enabled = true
    },

    ['ffa'] = {
        label = 'FREE FOR ALL', description = 'Everyone for themselves.',
        teamSize = 1, teams = 8, ranked = true, type = 'ffa',
        rounds = 1, roundsToWin = 1, roundTime = 600, matchTime = 600,
        killLimit = 30, respawn = true, respawnTime = 3, lives = 0,
        friendlyFire = true, overtime = false, suddenDeath = false,
        loadout = 'standard', minPlayers = 4, maxPlayers = 12, enabled = true
    },

    ['tdm'] = {
        label = 'TEAM DEATHMATCH', description = 'Team based kill race.',
        teamSize = 5, teams = 2, ranked = true, type = 'deathmatch',
        rounds = 1, roundsToWin = 1, roundTime = 600, matchTime = 600,
        killLimit = 75, respawn = true, respawnTime = 4, lives = 0,
        friendlyFire = false, overtime = true, suddenDeath = false,
        loadout = 'standard', enabled = true
    },

    ['snd'] = {
        label = 'SEARCH & DESTROY', description = 'Plant or defuse. No respawns.',
        teamSize = 5, teams = 2, ranked = true, type = 'snd',
        rounds = 13, roundsToWin = 7, roundTime = 135, matchTime = 3600,
        killLimit = 0, respawn = false, lives = 1, friendlyFire = false,
        overtime = true, suddenDeath = true, loadout = 'standard',
        plantTime = 4, defuseTime = 6, bombTimer = 40, enabled = true
    }
}

-- Modes offered inside the ranked queue (order preserved in the UI)
Config.RankedQueueModes = { '1v1', '2v2', '3v3', '5v5', 'tdm', 'snd' }

-- ============================================================================
-- 9b. PARTY QUEUE BEHAVIOUR
-- ============================================================================
-- Controls how the ranked queue reacts to the size of your party.

Config.PartyQueue = {

    -- The selected mode follows the party size automatically: invite a friend
    -- while on 1V1 and the queue switches to 2V2, a third makes it 3V3, and so
    -- on. Set to false to keep whatever the player picked.
    autoMode = true,

    -- Lock the queue to the mode that matches the party size exactly.
    --   true  : a party of 2 may only search 2V2
    --   false : a party of 2 may search 2V2 and anything larger (3V3, 5V5 …),
    --           and the missing slots are filled by matchmaking
    lockToPartySize = true,

    -- Modes whose team size is smaller than the party can never be searched,
    -- regardless of the setting above (a party of 3 cannot play 1V1).

    -- How the opposing side is put together.
    teamMatching = {
        -- 'any'      : the enemy team is assembled from whatever is waiting —
        --              another party, two solos, a duo plus a solo, and so on.
        -- 'fullTeam' : a complete party only ever faces another complete party.
        --              A duo searching 2V2 waits for a second duo searching
        --              2V2 instead of being handed two solo players, and solos
        --              keep matching among themselves as usual.
        mode = 'fullTeam',

        -- If no matching full team turns up within this many seconds, the
        -- party is matched the normal way instead of waiting forever.
        -- 0 = never fall back, keep waiting for a real team.
        fallbackAfter = 60
    }
}

-- ============================================================================
-- 10. LOADOUTS / WEAPON META
-- ============================================================================

Config.Loadouts = {
    duel = {
        health = 100,
        armor  = 100,
        weapons = {
            { name = 'WEAPON_PISTOL',        ammo = 250 },
            { name = 'WEAPON_CARBINERIFLE',  ammo = 300 }
        }
    },
    standard = {
        health = 100,
        armor  = 100,
        weapons = {
            { name = 'WEAPON_PISTOL',        ammo = 250 },
            { name = 'WEAPON_CARBINERIFLE',  ammo = 300 },
            { name = 'WEAPON_PUMPSHOTGUN',   ammo = 40  }
        }
    },
    sniper = {
        health = 100,
        armor  = 50,
        weapons = {
            { name = 'WEAPON_SNIPERRIFLE',   ammo = 40 },
            { name = 'WEAPON_PISTOL',        ammo = 100 }
        }
    },
    pistol = {
        health = 100, armor = 50,
        weapons = { { name = 'WEAPON_PISTOL', ammo = 200 } }
    },
    training = {
        health = 200, armor = 100,
        weapons = {
            { name = 'WEAPON_CARBINERIFLE', ammo = 2000 },
            { name = 'WEAPON_PISTOL',       ammo = 2000 },
            { name = 'WEAPON_SNIPERRIFLE',  ammo = 500  }
        }
    }
}

-- Weapons offered as pickable chips in the custom match UI.
-- `weapon` must also be present in Config.Weapons.allowed below.
Config.WeaponPresets = {
    { id = 'pistol_mk2',    label = 'Pistol MK2',    weapon = 'WEAPON_PISTOL_MK2',   ammo = 250 },
    { id = 'combat_mg',     label = 'Combat MG',     weapon = 'WEAPON_COMBATMG',     ammo = 400 },
    { id = 'assault_rifle', label = 'Assault Rifle', weapon = 'WEAPON_ASSAULTRIFLE', ammo = 300 },
    { id = 'sniper',        label = 'Sniper',        weapon = 'WEAPON_SNIPERRIFLE',  ammo = 50  },
    { id = 'shotgun',       label = 'Shotgun',       weapon = 'WEAPON_PUMPSHOTGUN',  ammo = 40  },
    { id = 'smg',           label = 'SMG',           weapon = 'WEAPON_SMG',          ammo = 250 },
    { id = 'knife',         label = 'Knife',         weapon = 'WEAPON_KNIFE',        ammo = 1   }
}

Config.Weapons = {
    -- Global whitelist. Any weapon not listed here cannot deal validated damage.
    allowed = {
        'WEAPON_PISTOL', 'WEAPON_PISTOL_MK2', 'WEAPON_COMBATPISTOL',
        'WEAPON_APPISTOL', 'WEAPON_HEAVYPISTOL', 'WEAPON_VINTAGEPISTOL',
        'WEAPON_SNSPISTOL', 'WEAPON_MICROSMG', 'WEAPON_SMG', 'WEAPON_SMG_MK2',
        'WEAPON_ASSAULTSMG', 'WEAPON_COMBATPDW', 'WEAPON_MACHINEPISTOL',
        'WEAPON_ASSAULTRIFLE', 'WEAPON_ASSAULTRIFLE_MK2', 'WEAPON_CARBINERIFLE',
        'WEAPON_CARBINERIFLE_MK2', 'WEAPON_ADVANCEDRIFLE', 'WEAPON_SPECIALCARBINE',
        'WEAPON_BULLPUPRIFLE', 'WEAPON_COMPACTRIFLE', 'WEAPON_PUMPSHOTGUN',
        'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_ASSAULTSHOTGUN', 'WEAPON_HEAVYSHOTGUN',
        'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_MARKSMANRIFLE',
        'WEAPON_COMBATMG', 'WEAPON_MG', 'WEAPON_KNIFE', 'WEAPON_BAT',
        'WEAPON_UNARMED'
    },

    -- Never allowed, even if a custom game tries to enable them
    blacklisted = {
        'WEAPON_RPG', 'WEAPON_GRENADELAUNCHER', 'WEAPON_MINIGUN',
        'WEAPON_FIREWORK', 'WEAPON_RAILGUN', 'WEAPON_HOMINGLAUNCHER',
        'WEAPON_COMPACTLAUNCHER', 'WEAPON_STICKYBOMB', 'WEAPON_PROXMINE',
        'WEAPON_PIPEBOMB', 'WEAPON_MOLOTOV', 'WEAPON_GRENADE',
        'WEAPON_RAYPISTOL', 'WEAPON_RAYCARBINE', 'WEAPON_RAYMINIGUN',
        'WEAPON_EMPLAUNCHER', 'WEAPON_FLARE', 'WEAPON_PETROLCAN'
    },

    -- Damage modifier applied per player inside a match (1.0 = vanilla)
    playerDamageModifier = 1.0,

    -- Explosive / vehicle / fall damage can never be credited as a kill source
    invalidDamageSources = {
        'EXPLOSION', 'FALL', 'VEHICLE', 'DROWNING', 'FIRE', 'ELECTRIC'
    },

    -- Maximum plausible engagement distance for a bullet kill (metres).
    -- Anything beyond this is flagged, not blocked, to avoid false positives.
    maxPlausibleDistance = 600.0,

    -- Minimum milliseconds between two validated kills from the same attacker.
    minKillInterval = 120
}

-- ============================================================================
-- 11. HEADSHOT — ONE SHOT KILL, NO DISTANCE FALLOFF
-- ============================================================================

Config.Headshot = {
    enabled = true,

    oneShotKill = true,

    ignoreDistance = true,

    enabledInRanked  = true,

    enabledInCustom  = true,

    enabledInTraining= true,

    excludedWeapons  = {},

    -- Bone ids accepted as a head hit (SKEL_Head, HEAD_top, headshot bone).
    headBones = { 31086, 39317, 12844, 20178, 21550 },

    -- Server side validation window: the attacker must have fired within this
    -- many milliseconds of the reported head impact.
    shotWindow = 900,

    -- Duplicate protection window for the same attacker/victim pair.
    duplicateWindow = 400,

    -- Rate limit: maximum head-kill reports accepted per attacker per second.
    maxReportsPerSecond = 6,

    -- Reject if the victim reports a headshot while already dead / respawning
    requireVictimAlive = true,

    -- Melee weapons never trigger the one shot rule
    excludeMelee = true
}

-- ============================================================================
-- 12. MAPS
-- ============================================================================
-- Every map is isolated using its own routing bucket at runtime.

Config.Maps = {

    {
        id     = 'harbor',
        name   = 'HARBOR',
        image  = 'harbor',
        center = vector3(1208.5, -3115.6, 5.5),
        radius = 140.0,
        modes  = { '1v1', '2v2', '3v3', '4v4', '5v5', 'tdm', 'snd', 'ffa' },
        weapons = nil, -- nil = use mode loadout
        teamA = {
            vector4(1170.2, -3196.4, 5.9, 88.0),
            vector4(1175.6, -3188.1, 5.9, 92.0),
            vector4(1166.0, -3181.3, 5.9, 85.0),
            vector4(1180.4, -3202.8, 5.9, 95.0),
            vector4(1160.9, -3205.5, 5.9, 80.0)
        },
        teamB = {
            vector4(1255.1, -3040.7, 6.0, 268.0),
            vector4(1248.3, -3049.2, 6.0, 272.0),
            vector4(1259.7, -3055.8, 6.0, 265.0),
            vector4(1241.6, -3034.5, 6.0, 275.0),
            vector4(1264.8, -3029.9, 6.0, 260.0)
        },
        spectator = vector4(1208.5, -3115.6, 30.0, 180.0)
    },

    {
        id     = 'airbase',
        name   = 'AIRBASE',
        image  = 'airbase',
        center = vector3(-1855.0, 3070.0, 32.8),
        radius = 180.0,
        modes  = { '2v2', '3v3', '4v4', '5v5', 'tdm', 'ffa' },
        teamA = {
            vector4(-1930.4, 3040.1, 32.8, 60.0),
            vector4(-1924.8, 3048.6, 32.8, 62.0),
            vector4(-1936.2, 3053.9, 32.8, 58.0),
            vector4(-1918.5, 3033.7, 32.8, 65.0),
            vector4(-1941.9, 3030.2, 32.8, 55.0)
        },
        teamB = {
            vector4(-1780.6, 3110.4, 32.8, 240.0),
            vector4(-1787.2, 3102.0, 32.8, 244.0),
            vector4(-1774.1, 3096.8, 32.8, 236.0),
            vector4(-1793.5, 3117.3, 32.8, 248.0),
            vector4(-1768.9, 3121.7, 32.8, 232.0)
        },
        spectator = vector4(-1855.0, 3070.0, 60.0, 180.0)
    },

    {
        id     = 'foundry',
        name   = 'FOUNDRY',
        image  = 'foundry',
        center = vector3(2740.0, 1470.0, 24.5),
        radius = 120.0,
        modes  = { '1v1', '2v2', '3v3', 'tdm', 'snd' },
        teamA = {
            vector4(2690.5, 1430.2, 24.5, 45.0),
            vector4(2696.1, 1436.8, 24.5, 48.0),
            vector4(2684.7, 1440.4, 24.5, 42.0),
            vector4(2702.3, 1424.9, 24.5, 50.0),
            vector4(2679.8, 1425.6, 24.5, 40.0)
        },
        teamB = {
            vector4(2789.4, 1512.6, 24.5, 225.0),
            vector4(2783.0, 1505.9, 24.5, 228.0),
            vector4(2795.8, 1502.3, 24.5, 222.0),
            vector4(2777.6, 1518.1, 24.5, 230.0),
            vector4(2800.2, 1519.4, 24.5, 220.0)
        },
        spectator = vector4(2740.0, 1470.0, 50.0, 180.0)
    },

    {
        id     = 'quarry',
        name   = 'QUARRY',
        image  = 'quarry',
        center = vector3(-540.0, 2850.0, 30.0),
        radius = 160.0,
        modes  = { '3v3', '4v4', '5v5', 'tdm', 'ffa', 'snd' },
        teamA = {
            vector4(-610.5, 2800.4, 30.0, 40.0),
            vector4(-604.2, 2807.9, 30.0, 44.0),
            vector4(-616.8, 2811.5, 30.0, 36.0),
            vector4(-598.1, 2794.2, 30.0, 48.0),
            vector4(-622.4, 2795.7, 30.0, 32.0)
        },
        teamB = {
            vector4(-468.9, 2901.6, 30.0, 220.0),
            vector4(-475.3, 2894.1, 30.0, 224.0),
            vector4(-462.7, 2890.5, 30.0, 216.0),
            vector4(-481.6, 2908.2, 30.0, 228.0),
            vector4(-456.2, 2906.8, 30.0, 212.0)
        },
        spectator = vector4(-540.0, 2850.0, 60.0, 180.0)
    },

    {
        id     = 'compound',
        name   = 'COMPOUND',
        image  = 'compound',
        center = vector3(3320.0, 5170.0, 20.0),
        radius = 130.0,
        modes  = { '1v1', '2v2', '3v3', '4v4', '5v5', 'snd' },
        teamA = {
            vector4(3265.4, 5120.8, 19.6, 45.0),
            vector4(3271.9, 5127.3, 19.6, 48.0),
            vector4(3259.2, 5131.0, 19.6, 42.0),
            vector4(3278.6, 5114.5, 19.6, 52.0),
            vector4(3253.1, 5115.9, 19.6, 38.0)
        },
        teamB = {
            vector4(3374.2, 5218.5, 20.4, 225.0),
            vector4(3367.8, 5211.9, 20.4, 228.0),
            vector4(3380.5, 5208.2, 20.4, 222.0),
            vector4(3361.3, 5224.7, 20.4, 232.0),
            vector4(3386.9, 5223.4, 20.4, 218.0)
        },
        spectator = vector4(3320.0, 5170.0, 48.0, 180.0)
    }
}

-- Training area (single bucket, no ranked impact)
Config.Training = {
    enabled = true,
    bucket  = 90000,
    spawn   = vector4(1208.5, -3115.6, 5.5, 180.0),
    loadout = 'training',
    modes   = {
        aim      = { label = 'AIM TRAINING',      targets = 12, spacing = 8.0,  time = 120 },
        headshot = { label = 'HEADSHOT TRAINING', targets = 8,  spacing = 12.0, time = 120 },
        range    = { label = 'FREE RANGE',        targets = 0,  spacing = 0.0,  time = 0   }
    }
}

-- ============================================================================
-- 12a. BOT MATCH  (staff only)
-- ============================================================================
--
-- A practice duel against AI opponents, started from the admin panel. It runs
-- the real match presentation — private bucket, map spawns, rounds, HUD, kill
-- feed, end screen — so a mode or a map can be checked with one person.
--
-- It is deliberately UNRANKED and cannot be made ranked. The bots are local
-- peds on the starting player's client, which is the only place a ped can be
-- created and given combat AI, so their deaths are reported by that client
-- rather than proven by the server. Nothing may ride on a client's word, so a
-- bot match awards no RP, no MMR, no stats, no match history — and it is
-- limited to staff who hold the permission below.
--
Config.BotMatch = {
    enabled = true,

    -- The permission lives on the admin action itself, so there is one source
    -- of truth: Config.AdminActions.startBotMatch.permission ('pvp.admin.botmatch').
    -- Anyone holding Config.Permissions.superAdmin also passes while
    -- Config.Permissions.adminGrantsAll is true.

    -- First bucket of the range used for these sessions. Each running bot
    -- match takes the next free one (64 are reserved from here) so two staff
    -- practising at once never share a world.
    bucket = 90100,

    -- Map: an id from Config.Maps, or nil to let the starter pick (the panel
    -- offers the list and falls back to the first map that supports the mode).
    defaultMap = nil,

    -- Round structure, mirroring a normal 1v1. Rounds needed to win are
    -- derived from the round count (best of N), so there is no separate knob
    -- that could disagree with the number picked in the panel.
    rounds        = 5,       -- default; the panel offers 1, 3, 5, 7 and 9
    roundTime     = 120,     -- seconds, 0 = unlimited
    countdown     = 5,       -- freeze before a round goes live
    roundEndDelay = 5,       -- pause on the round result before the next one
    endDelay      = 12,      -- how long the match end screen stays before cleanup

    -- The human side
    loadout        = 'duel',
    headshotOneShot = true,  -- same one shot headshot rule as a real match

    -- Hard ceiling. The bots are local peds, so a large number costs the
    -- starting player frames and nobody else.
    maxBots = 5,

    bots = {
        count = 1,           -- default, overridable per start up to maxBots
        model = 's_m_y_marine_01',
        namePrefix = 'BOT',

        -- Presets offered in the panel. accuracy is 0-100, reaction is the
        -- shooting rate multiplier, and combatMovement is 0 stationary,
        -- 1 defensive, 2 advance, 3 suicidal.
        difficulties = {
            easy = {
                label = 'EASY',
                health = 150, armor = 0,   accuracy = 15, reaction = 0.35,
                weapon = 'WEAPON_PISTOL',       combatMovement = 1, alertness = 0
            },
            normal = {
                label = 'NORMAL',
                health = 200, armor = 50,  accuracy = 35, reaction = 0.6,
                weapon = 'WEAPON_PISTOL_MK2',   combatMovement = 2, alertness = 2
            },
            hard = {
                label = 'HARD',
                health = 200, armor = 100, accuracy = 60, reaction = 0.85,
                weapon = 'WEAPON_CARBINERIFLE', combatMovement = 2, alertness = 3
            },
            insane = {
                label = 'INSANE',
                health = 200, armor = 100, accuracy = 85, reaction = 1.0,
                weapon = 'WEAPON_CARBINERIFLE', combatMovement = 3, alertness = 3
            }
        },
        defaultDifficulty = 'normal'
    },

    -- Post the result to the adminActions webhook like any other staff action
    logToWebhook = true
}

-- ============================================================================
-- 13. MAP VOTING
-- ============================================================================

Config.MapVote = {
    enabled     = true,
    options     = 3,
    duration    = 20,   -- seconds
    tieBreaker  = 'random',
    -- Maps played in the last N matches by these players are de-prioritised
    avoidRepeat = 2
}

-- ============================================================================
-- 14. MATCHMAKING
-- ============================================================================

Config.Matchmaking = {
    enabled = true,

    tickInterval = 2000, -- ms between matchmaking passes

    -- Search window expansion
    mmrRangeStart   = 120,
    mmrRangeStep    = 60,     -- added every expandInterval
    mmrRangeMax     = 1200,
    expandInterval  = 8000,   -- ms

    rankRangeStart  = 2,      -- rank ids
    rankRangeStep   = 1,
    rankRangeMax    = 12,

    -- Ping preference (0 disables)
    maxPing         = 200,
    pingRangeMax    = 350,
    pingRelaxAfter  = 30000,

    -- Ready check
    readyCheck = {
        enabled  = true,
        duration = 15,      -- seconds to accept
        -- Player is put on cooldown when failing to accept
        declineCooldown = 120,
        -- Requeue the accepting players automatically with queue priority
        requeueOnFail   = true
    },

    -- Party constraints
    maxPartyRankGap = 5,       -- rank id difference inside a party
    partyRankGapEnabled = true,

    -- Queue restrictions
    minPlayersToStart = nil,   -- nil = derived from the mode
    maxQueueTime      = 600,   -- seconds before the player is dropped from queue

    -- Avoid list: players recently avoided are not matched together
    avoidListSize     = 5,
    avoidDuration     = 3600,  -- seconds

    -- Backfill players who left before the match went live
    allowBackfill     = true,
    backfillWindow    = 45     -- seconds after match start
}

-- ============================================================================
-- 15. MATCH FLOW
-- ============================================================================

-- ============================================================================
-- 15b. PLAYER AVATARS  (match HUD and scoreboard)
-- ============================================================================
--
-- Each player in the HUD and the TAB scoreboard shows a picture. Where it
-- comes from is up to you.
--
Config.Avatars = {
    enabled = true,

    -- Shown whenever a real picture cannot be resolved. Use a local file under
    -- Files/ui/img/ (add it to the `files` list in fxmanifest.lua) or any URL.
    default = 'https://cdn.discordapp.com/embed/avatars/0.png',

    -- How to resolve a picture. First match wins, and any step may be off.
    --
    --   'discord'  ask Discord for the real avatar of the player's linked
    --              account. Needs a bot token; see below.
    --   'template' build a URL from the player's discord id yourself, with no
    --              API call at all. %s is replaced by the bare discord id.
    --   'none'     always use `default`.
    --
    source = 'discord',

    -- Only used when source = 'template'
    template = 'https://my-cdn.example.com/avatars/%s.png',

    discord = {
        -- A bot token from https://discord.com/developers/applications.
        -- The bot needs no permissions and no server membership — reading a
        -- user's public avatar only requires the token itself.
        --
        -- LEAVE THIS EMPTY and the system falls back to `default` silently.
        -- Never put the token anywhere that reaches the client; this file is
        -- server only, which is why it lives here.
        botToken = '',

        -- Discord rate limits hard, so results are cached. Seconds.
        cacheTime = 21600,          -- 6 hours

        -- Size of the requested image (power of two, 16 - 4096)
        size = 128
    }
}

-- ============================================================================
-- 15c. TEAM NAMES  (match HUD and scoreboard)
-- ============================================================================
--
Config.TeamNames = {
    -- 'fixed'  the two names below, always
    -- 'leader' name each side after one of its players, e.g. "M547'S TEAM".
    --          In a 1v1 that reads as the two player names facing each other,
    --          which is usually what you want.
    mode = 'leader',

    fixed = { [1] = 'TEAM A', [2] = 'TEAM B' },

    -- Used by 'leader'. %s is the player's name.
    pattern = "%s'S TEAM",

    -- With 'leader', a team of one shows just the name instead of the pattern.
    soloIsPlain = true,

    -- Which player names the team: 'party' uses the party leader when the
    -- side queued together, otherwise the highest ranked player.
    pick = 'party'
}

Config.Match = {
    -- Global tick used by the match state machine
    tickInterval      = 250,

    warmupTime        = 10,    -- seconds after teleport before round 1
    roundStartFreeze  = 3,     -- countdown 3-2-1-GO
    roundEndTime      = 6,     -- seconds shown after each round
    matchEndTime      = 15,    -- scoreboard / MVP screen duration
    cleanupTime       = 5,

    spawnProtection   = 3,     -- seconds of invulnerability after spawn
    antiSpawnKill     = true,
    antiSpawnKillRadius = 12.0,

    -- Out of bounds
    boundary = {
        warningTime   = 5,     -- seconds before punishment
        action        = 'kill' -- 'kill' | 'teleport'
    },

    -- Surrender vote
    surrender = {
        enabled       = true,
        minRound      = 5,
        requiredRatio = 0.75,   -- share of the team that must agree
        voteDuration  = 30,
        cooldown      = 120
    },

    -- Overtime
    overtime = {
        enabled       = true,
        roundsPerHalf = 2,
        winBy         = 2,
        maxOvertimes  = 5,
        suddenDeath   = true    -- last overtime is a single decisive round
    },

    -- Match abort conditions
    minPlayersToContinue = 1,   -- per team, below this the match is forfeited
    abandonForfeitDelay  = 60,  -- seconds a team can play short handed

    -- Match record retention
    maxMatchDuration     = 5400 -- hard stop (seconds)
}

-- ============================================================================
-- 16. ROUTING BUCKETS
-- ============================================================================

Config.Buckets = {
    start          = 10000,   -- first bucket id handed to a match
    max            = 89999,
    lockdownMode   = 'strict', -- entity lockdown for match buckets
    populationEnabled = false, -- no ambient population inside matches
    -- Buckets reserved for custom games
    customStart    = 60000,
    customMax      = 79999,
    -- Bucket used by the lobby / map vote stage
    lobby          = 95000
}

-- ============================================================================
-- 17. RECONNECT
-- ============================================================================

Config.Reconnect = {
    enabled          = true,
    window           = 180,   -- seconds to come back
    restoreState     = true,  -- health, armor, weapons, score
    -- Reconnecting inside the window cancels the leave penalty
    cancelPenalty    = true,
    -- The match is paused while waiting (rounds do not advance)
    pauseMatch       = false,
    maxReconnects    = 2
}

-- ============================================================================
-- 18. AFK
-- ============================================================================

Config.AFK = {
    enabled          = true,
    checkInterval    = 5000,   -- ms
    warningAfter     = 45,     -- seconds without activity
    kickAfter        = 75,     -- seconds without activity
    -- Activity signals
    signals = {
        movement    = true,
        camera      = true,
        shooting    = true,
        interaction = true
    },
    cameraDeltaDegrees = 4.0,
    movementDistance   = 1.5,

    -- Never counted as AFK during these states
    ignoreStates = { 'WAITING', 'READY', 'MAP_VOTE', 'STARTING', 'ROUND_END', 'MATCH_END', 'CLEANUP' },
    ignoreSpectators = true,

    penalty = {
        removeFromMatch = true,
        rpPenalty       = 25,
        cooldown        = 600,   -- seconds before queueing again
        countsAsLeave   = true
    }
}

-- ============================================================================
-- 19. LEAVE PENALTY
-- ============================================================================

Config.LeavePenalty = {
    enabled = true,

    -- Rolling window used to count offences
    windowDays = 7,

    tiers = {
        { offence = 1, rp = 10, cooldown = 0,     ban = 0,      label = 'Warning' },
        { offence = 2, rp = 20, cooldown = 300,   ban = 0,      label = 'Short Cooldown' },
        { offence = 3, rp = 35, cooldown = 1800,  ban = 0,      label = 'Long Cooldown' },
        { offence = 4, rp = 50, cooldown = 0,     ban = 86400,  label = 'Ranked Ban 24h' },
        { offence = 5, rp = 60, cooldown = 0,     ban = 604800, label = 'Ranked Ban 7d' }
    },

    -- Leaving before the match goes live costs less
    preLiveMultiplier = 0.4,

    -- Grace: a disconnect that reconnects in time is not counted
    graceOnReconnect  = true
}

-- ============================================================================
-- 20. RANK BANS
-- ============================================================================

Config.RankBan = {
    types = { 'RANKED', 'MODE', 'CUSTOM', 'CHAT', 'PARTY', 'PERMANENT' },

    presetDurations = {
        { label = '1 Hour',  seconds = 3600 },
        { label = '6 Hours', seconds = 21600 },
        { label = '24 Hours',seconds = 86400 },
        { label = '3 Days',  seconds = 259200 },
        { label = '7 Days',  seconds = 604800 },
        { label = '30 Days', seconds = 2592000 },
        { label = 'Permanent', seconds = 0 }
    },

    requireReason  = true,
    requireEvidence= false,
    notifyPlayer   = true
}

-- ============================================================================
-- 21. ANTI BOOSTING
-- ============================================================================
-- Nothing here bans automatically. Detections raise a flag with evidence for
-- staff review.

Config.AntiBoost = {
    enabled = true,

    -- Analyse a player's last N matches
    sampleSize = 25,

    detectors = {
        repeatedOpponent = {
            enabled   = true,
            threshold = 6,      -- same opponent in N of the sample
            severity  = 2
        },
        repeatedVictim = {
            enabled   = true,
            threshold = 25,     -- killed the same player N times in the sample
            severity  = 2
        },
        shortMatches = {
            enabled     = true,
            minDuration = 90,   -- seconds
            threshold   = 5,    -- N suspiciously short matches
            severity    = 2
        },
        intentionalLoss = {
            enabled       = true,
            maxKD         = 0.15,
            minDeaths     = 10,
            threshold     = 3,
            severity      = 3
        },
        winTrading = {
            enabled   = true,
            threshold = 4,      -- alternating wins with the same opponent
            severity  = 3
        },
        altAccount = {
            enabled          = true,
            matchOnLicense   = false, -- same license family
            matchOnIP        = true,
            newAccountDays   = 3,
            severity         = 3
        },
        abnormalRP = {
            enabled   = true,
            rpPerHour = 260,
            severity  = 2
        },
        impossibleHeadshot = {
            enabled       = true,
            headshotRatio = 0.85,  -- % of kills that are headshots
            minKills      = 25,
            severity      = 3
        },
        linkedMatches = {
            enabled   = true,
            threshold = 5,   -- same lobby composition repeated
            severity  = 2
        }
    },

    -- Flags at or above this total severity are highlighted for admins
    reviewThreshold = 5,

    -- How often the analyser runs (per player, after a match ends)
    analyseOnMatchEnd = true,
    -- Keep raw evidence rows for N days
    evidenceRetentionDays = 30
}

-- ============================================================================
-- 22. SEASONS
-- ============================================================================

Config.Seasons = {
    enabled = true,

    -- Created automatically if no active season exists
    autoCreate = true,
    defaultDurationDays = 60,
    namePattern = 'Season %d',

    -- End of season handling
    reset = {
        mode          = 'soft',  -- 'soft' | 'hard' | 'none'
        -- Soft reset formula: newRP = floor(rp * factor) + offset (clamped)
        softFactor    = 0.55,
        softOffset    = 120,
        keepMMR       = true,
        mmrSoftFactor = 0.85,
        resetPlacement= true
    },

    -- Archive the leaderboard and hand out rewards on season end
    archiveLeaderboard = true,
    distributeRewards  = true,

    -- Checked on this interval (ms) to detect the season rollover
    checkInterval = 60000,

    -- A season never ends while matches are live; it waits for them.
    waitForLiveMatches = true
}

-- ============================================================================
-- 23. REWARDS
-- ============================================================================
-- type: 'money' | 'item' | 'weapon' | 'vehicle' | 'group' | 'title' | 'badge'
--       | 'frame' | 'effect'

-- ============================================================================
-- 16b. STORE — cards and titles bought with coins
-- ============================================================================
--
-- Two cosmetics, no gameplay effect of any kind:
--   cards   the banner behind the player's lobby slot
--   titles  a word shown beside their name
--
-- Coins are handed out by staff (admin panel > POINTS > Give Coins) and by
-- the per-match rewards below if you switch `earnPerMatch` on. Prices and
-- ownership are resolved on the server; the client only ever asks to buy.
--
Config.Store = {
    enabled = true,

    currency = {
        label   = 'COINS',
        starting = 0,          -- balance a brand new profile begins with
        max      = 10000000
    },

    -- Set to a number to also pay coins out per match. 0 = staff only.
    earnPerMatch = { win = 0, loss = 0, mvp = 0 },

    -- Badge colours for the little rarity tag on each item
    rarities = {
        common    = { label = 'COMMON',    color = '#8B93A3' },
        rare      = { label = 'RARE',      color = '#3FA9FF' },
        epic      = { label = 'EPIC',      color = '#C158FF' },
        legendary = { label = 'LEGENDARY', color = '#F5C542' }
    },

    -- ---- CARDS ---------------------------------------------------------
    -- `image` is any URL, or a file you ship under Files/ui/img/ (add it to
    -- the `files` block in fxmanifest.lua and use 'img/name.png').
    -- The one marked default is owned by everyone and cannot be sold.
    cards = {
        { id = 'default',     name = 'Default',          rarity = 'common',    price = 0,    image = '', default = true },
        { id = 'black_thorn', name = 'Black Thorn',      rarity = 'rare',      price = 400,  image = '' },
        { id = 'bucket',      name = 'Bucket of Trouble',rarity = 'rare',      price = 400,  image = '' },
        { id = 'bracelet',    name = 'The Bracelet',     rarity = 'rare',      price = 400,  image = '' },
        { id = 'wayfinder',   name = 'Way Finder',       rarity = 'epic',      price = 750,  image = '' },
        { id = 'op',          name = 'Op',               rarity = 'epic',      price = 750,  image = '' },
        { id = 'insidious',   name = 'Insidious',        rarity = 'legendary', price = 1500, image = '' },
        { id = 'infinity',    name = 'Infinity',         rarity = 'legendary', price = 2000, image = '' }
    },

    -- ---- TITLES --------------------------------------------------------
    -- `color` tints the title wherever the name is shown.
    titles = {
        { id = 'none',         name = '—',            rarity = 'common',    price = 0,    default = true },
        { id = 'rookie',       name = 'ROOKIE',       rarity = 'common',    price = 0,    color = '#B9C1CC' },
        { id = 'sharpshooter', name = 'SHARPSHOOTER', rarity = 'rare',      price = 300,  color = '#3FA9FF' },
        { id = 'demon',        name = 'DEMON',        rarity = 'epic',      price = 800,  color = '#C158FF' },
        { id = 'legend',       name = 'LEGEND',       rarity = 'legendary', price = 2000, color = '#F5C542' }
    }
}

Config.Rewards = {
    enabled = true,

    -- Awarded at the end of every ranked match
    perMatch = {
        winMoney  = 2500,
        lossMoney = 800,
        mvpMoney  = 1500,
        xpWin     = 120,
        xpLoss    = 45,
        xpPerKill = 6,
        xpPerHeadshot = 4,
        xpMVP     = 60
    },

    -- Season end rewards keyed by the highest tier reached
    season = {
        IRON      = { { type = 'money', value = 25000 },  { type = 'title', value = 'Iron Contender' } },
        BRONZE    = { { type = 'money', value = 50000 },  { type = 'title', value = 'Bronze Contender' } },
        SILVER    = { { type = 'money', value = 100000 }, { type = 'title', value = 'Silver Contender' } },
        GOLD      = { { type = 'money', value = 200000 }, { type = 'title', value = 'Gold Elite' }, { type = 'badge', value = 'gold_season' } },
        PLATINUM  = { { type = 'money', value = 350000 }, { type = 'title', value = 'Platinum Elite' }, { type = 'badge', value = 'plat_season' } },
        DIAMOND   = { { type = 'money', value = 600000 }, { type = 'title', value = 'Diamond Elite' }, { type = 'frame', value = 'diamond' } },
        ASCENDANT = { { type = 'money', value = 900000 }, { type = 'title', value = 'Ascendant' }, { type = 'frame', value = 'ascendant' } },
        IMMORTAL  = { { type = 'money', value = 1500000 },{ type = 'title', value = 'Immortal' }, { type = 'effect', value = 'immortal_aura' } },
        RADIANT   = { { type = 'money', value = 2500000 },{ type = 'title', value = 'Radiant' }, { type = 'effect', value = 'radiant_aura' }, { type = 'vehicle', value = 'zentorno' } }
    },

    -- Levelling
    levels = {
        enabled     = true,
        baseXP      = 1000,
        growth      = 1.12,   -- xp needed = baseXP * growth^(level-1)
        maxLevel    = 100,
        levelRewards = {
            [10]  = { { type = 'title', value = 'Rookie' } },
            [25]  = { { type = 'money', value = 100000 } },
            [50]  = { { type = 'badge', value = 'veteran' }, { type = 'money', value = 250000 } },
            [75]  = { { type = 'frame', value = 'veteran' } },
            [100] = { { type = 'title', value = 'Legend' }, { type = 'money', value = 1000000 } }
        }
    },

    -- Duplicate protection: a reward key can only be granted once per season
    uniquePerSeason = true
}

-- ============================================================================
-- 24. MISSIONS / ACHIEVEMENTS
-- ============================================================================

Config.Missions = {
    enabled = true,

    daily = {
        count = 3,
        resetHour = 0, -- UTC
        pool = {
            { key = 'daily_kills',     label = 'Get 25 kills',            target = 25, stat = 'kills',     xp = 150, money = 25000 },
            { key = 'daily_hs',        label = 'Get 10 headshots',        target = 10, stat = 'headshots', xp = 180, money = 30000 },
            { key = 'daily_wins',      label = 'Win 2 ranked matches',    target = 2,  stat = 'wins',      xp = 200, money = 40000 },
            { key = 'daily_damage',    label = 'Deal 5000 damage',        target = 5000, stat = 'damage',  xp = 150, money = 25000 },
            { key = 'daily_matches',   label = 'Play 3 matches',          target = 3,  stat = 'matches',   xp = 120, money = 20000 },
            { key = 'daily_mvp',       label = 'Earn 1 MVP',              target = 1,  stat = 'mvp',       xp = 250, money = 50000 }
        }
    },

    weekly = {
        count = 3,
        resetDay = 1, -- Monday
        pool = {
            { key = 'weekly_kills',   label = 'Get 150 kills',           target = 150, stat = 'kills',     xp = 800,  money = 150000 },
            { key = 'weekly_wins',    label = 'Win 10 ranked matches',   target = 10,  stat = 'wins',      xp = 1200, money = 250000 },
            { key = 'weekly_hs',      label = 'Get 60 headshots',        target = 60,  stat = 'headshots', xp = 1000, money = 200000 },
            { key = 'weekly_mvp',     label = 'Earn 5 MVPs',             target = 5,   stat = 'mvp',       xp = 1500, money = 300000 },
            { key = 'weekly_matches', label = 'Play 20 matches',         target = 20,  stat = 'matches',   xp = 700,  money = 120000 }
        }
    }
}

Config.Achievements = {
    { key = 'first_blood_10', label = 'Opening Act',    desc = 'Get 10 first bloods',      stat = 'first_bloods', target = 10,   xp = 300 },
    { key = 'ace_1',          label = 'Ace',            desc = 'Win a round alone vs all', stat = 'aces',         target = 1,    xp = 500 },
    { key = 'ace_10',         label = 'Ace Machine',    desc = 'Get 10 aces',              stat = 'aces',         target = 10,   xp = 1500 },
    { key = 'clutch_25',      label = 'Clutch King',    desc = 'Win 25 clutches',          stat = 'clutches',     target = 25,   xp = 1200 },
    { key = 'kills_1000',     label = 'Executioner',    desc = 'Get 1000 kills',           stat = 'kills',        target = 1000, xp = 2000 },
    { key = 'hs_500',         label = 'Headhunter',     desc = 'Get 500 headshots',        stat = 'headshots',    target = 500,  xp = 2000 },
    { key = 'wins_100',       label = 'Centurion',      desc = 'Win 100 matches',          stat = 'wins',         target = 100,  xp = 2500 },
    { key = 'mvp_50',         label = 'Most Valuable',  desc = 'Earn 50 MVPs',             stat = 'mvp',          target = 50,   xp = 2500 },
    { key = 'streak_10',      label = 'Unstoppable',    desc = 'Win 10 matches in a row',  stat = 'best_win_streak', target = 10, xp = 3000 }
}

-- ============================================================================
-- 25. PARTY
-- ============================================================================

Config.Party = {
    enabled       = true,
    maxSize       = 5,
    inviteTimeout = 30,      -- seconds
    requireReady  = true,
    -- Disband the party when the leader leaves instead of transferring
    disbandOnLeaderLeave = false,
    -- Party members must be within this rank id gap
    rankGap       = 5,
    rankGapEnabled= true,
    -- Distance requirement to invite (0 = anywhere on the server)
    inviteDistance= 0.0
}

-- ============================================================================
-- 26. CUSTOM GAMES
-- ============================================================================

Config.CustomGames = {
    enabled          = true,
    maxRooms         = 25,
    maxPlayersPerRoom= 20,
    requirePermission= false,   -- when true, Config.Permissions.createCustom is checked
    roomNameMaxLength= 28,
    passwordMaxLength= 20,
    idleTimeout      = 900,     -- seconds before an empty room is destroyed

    -- Custom games never affect ranked progress unless staff enable it
    rankedAllowed    = false,
    rankedPermission = 'pvp.admin',

    -- Default room settings (host can change every one of these)
    -- Short human friendly code used by JOIN CODE in the UI
    roomCode = {
        length   = 4,
        alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' -- no I/O/0/1
    },

    -- Match types offered in the custom match UI
    matchTypes = {
        { id = 'normal',  label = 'Normal',   description = 'Everyone spawns with the selected weapons.' },
        { id = 'random',  label = 'Random',   description = 'A random weapon from the selection each round.' },
        { id = 'gungame', label = 'Gun Game', description = 'Every kill advances you to the next weapon.' }
    },

    defaults = {
        mode          = '5v5',
        map           = 'harbor',
        matchType     = 'normal',
        weapons       = { 'pistol_mk2' },
        armorEnabled  = false,
        headshotOnly  = false,
        rounds        = 13,
        roundTime     = 120,
        matchTime     = 3600,
        killLimit     = 0,
        friendlyFire  = false,
        headshotOneShot = true,
        health        = 100,
        armor         = 100,
        movement      = 1.0,
        jump          = true,
        respawn       = false,
        respawnTime   = 4,
        lives         = 1,
        spectators    = true,
        teamBalance   = true,
        autoStart     = true,
        autoStartAt   = 1.0,     -- fraction of the slots filled
        minimap       = false,
        vehicles      = false,
        killcam       = false,
        overtime      = true,
        suddenDeath   = true,
        loadout       = 'standard',
        locked        = false
    },

    -- Boundaries the host cannot exceed
    limits = {
        rounds    = { min = 1,   max = 31 },
        roundTime = { min = 30,  max = 600 },
        matchTime = { min = 60,  max = 5400 },
        killLimit = { min = 0,   max = 300 },
        health    = { min = 50,  max = 200 },
        armor     = { min = 0,   max = 100 },
        movement  = { min = 0.8, max = 1.6 },
        lives     = { min = 1,   max = 10 },
        respawnTime = { min = 1, max = 30 }
    }
}

-- ============================================================================
-- 27. SPECTATOR
-- ============================================================================

Config.SpectatorRules = {
    enabled          = true,
    -- Dead players can only follow their own team
    teamOnly         = true,
    -- Staff with the spectate permission can watch everyone
    staffFreeSpectate= true,
    -- Delay before a dead player enters spectator (killcam window)
    deathDelay       = 2,
    -- Allow free camera for staff
    staffFreecam     = true
}

-- ============================================================================
-- 28. KILL FEED / EXTRA EVENTS
-- ============================================================================

Config.CombatEvents = {
    firstBlood   = { enabled = true, xp = 15 },
    doubleKill   = { enabled = true, window = 5000, xp = 20 },
    tripleKill   = { enabled = true, window = 5000, xp = 35 },
    quadraKill   = { enabled = true, window = 5000, xp = 55 },
    ace          = { enabled = true, xp = 100 },
    clutch       = { enabled = true, xp = 60 },
    revenge      = { enabled = true, xp = 10 },
    nemesis      = { enabled = true, threshold = 3 },
    killStreak   = { enabled = true, steps = { 3, 5, 7, 10, 15 } },
    commendation = { enabled = true, perMatch = 1 }
}

-- ============================================================================
-- 29. MVP
-- ============================================================================

Config.MVP = {
    enabled = true,
    weights = {
        kills      = 3.0,
        deaths     = -1.5,
        damage     = 0.012,
        headshots  = 1.5,
        objective  = 2.5,
        roundsWon  = 1.0,
        clutches   = 4.0,
        assists    = 0.8,
        firstBloods= 1.2
    },
    -- Only the winning team can take MVP when true
    winnerOnly = false
}

-- ============================================================================
-- 30. SECURITY / RATE LIMITS
-- ============================================================================

Config.Security = {
    -- Per player, per event, requests allowed inside the window
    rateLimits = {
        default      = { max = 20, window = 10000 },
        menu         = { max = 10, window = 10000 },
        queue        = { max = 8,  window = 10000 },
        party        = { max = 20, window = 10000 },
        custom       = { max = 25, window = 10000 },
        kill         = { max = 40, window = 5000  },
        damage       = { max = 200,window = 5000  },
        headshot     = { max = 30, window = 5000  },
        leaderboard  = { max = 12, window = 10000 },
        profile      = { max = 15, window = 10000 },
        admin        = { max = 40, window = 10000 },
        settings     = { max = 6,  window = 10000 },
        chat         = { max = 10, window = 10000 }
    },

    -- Automatic action when a player floods events
    floodAction   = 'ignore',   -- 'ignore' | 'kick' | 'flag'
    floodKickAfter= 6,          -- consecutive violations before the action

    -- Reject damage reports above this value (per single hit)
    maxSingleDamage = 400,
    -- Reject a kill claim if the victim was not damaged recently
    killDamageWindow= 4000,

    -- Validate that the reported weapon is actually equipped by the attacker
    validateEquippedWeapon = true,

    -- Log every rejected event
    logRejections = true
}

-- ============================================================================
-- 31. COMMANDS
-- ============================================================================

Config.Commands = {
    pvp          = { enabled = true, name = 'pvp',          permission = nil },
    rank         = { enabled = true, name = 'rank',         permission = nil },
    leaderboard  = { enabled = true, name = 'leaderboard',  permission = nil },
    customgame   = { enabled = true, name = 'customgame',   permission = nil },
    reconnectpvp = { enabled = true, name = 'reconnectpvp', permission = nil },
    -- These are gated by Config.AdminActions, not by the permission field.
    pvpadmin     = { enabled = true, name = 'pvpadmint',    permission = nil },
    rankban      = { enabled = true, name = 'rankban',      permission = nil },
    rankunban    = { enabled = true, name = 'rankunban',    permission = nil },
    setrank      = { enabled = true, name = 'setrank',      permission = nil },
    setrp        = { enabled = true, name = 'setrp',        permission = nil },
    givepvprp    = { enabled = true, name = 'givepvprp',    permission = nil },
    pvpstatus    = { enabled = true, name = 'pvpstatus',    permission = 'pvp.moderator' }
}

-- ============================================================================
-- 32. GLOBAL SWITCHES
-- ============================================================================

Config.Global = {
    -- Freeze ranked queueing (maintenance)
    rankedFrozen   = false,
    frozenMessage  = 'Ranked is temporarily disabled by the administration.',

    -- Minimum level / playtime before ranked is unlocked
    requirements = {
        enabled     = false,
        minLevel    = 0,
        minPlaytime = 0 -- seconds
    },

    -- Announce big events in the server chat
    announce = {
        radiantPromotion = true,
        aces             = true,
        winStreaks       = 10
    }
}
