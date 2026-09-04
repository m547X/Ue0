--[[
    ============================================================================
     M5 Ranked PvP — Config_Client.lua
    ----------------------------------------------------------------------------
     CLIENT SIDE SETTINGS ONLY.
     Never place sensitive data here (permissions, webhooks, RP formulas, ...).
     Everything in this file is readable by any player.
    ============================================================================
]]

Config = {}

Config.ResourceName = 'M5_RankedPvP'
Config.Debug        = false

-- ============================================================================
-- 1. LANGUAGE / TEXT
-- ============================================================================

Config.Language = 'en' -- 'en' | 'ar'

Config.Text = {
    en = {
        openPrompt      = '[E] Open M5 Ranked PvP',
        returnToZone    = 'RETURN TO COMBAT ZONE',
        warning         = 'WARNING',
        matchFound      = 'MATCH FOUND',
        searching       = 'SEARCHING FOR MATCH',
        roundStart      = 'GO',
        victory         = 'VICTORY',
        defeat          = 'DEFEAT',
        draw            = 'DRAW',
        overtime        = 'OVERTIME',
        suddenDeath     = 'SUDDEN DEATH',
        spectating      = 'SPECTATING',
        eliminated      = 'ELIMINATED',
        afkWarning      = 'AFK WARNING — MOVE NOW',
        reconnect       = 'RECONNECT TO MATCH',
        noPermission    = 'You do not have access to this feature.',
        alreadyInMatch  = 'You are already in a match.'
    },
    ar = {
        openPrompt      = '[E] فتح M5 Ranked PvP',
        returnToZone    = 'عد إلى منطقة القتال',
        warning         = 'تحذير',
        matchFound      = 'تم إيجاد مباراة',
        searching       = 'جاري البحث عن مباراة',
        roundStart      = 'ابدأ',
        victory         = 'فوز',
        defeat          = 'خسارة',
        draw            = 'تعادل',
        overtime        = 'وقت إضافي',
        suddenDeath     = 'الموت المفاجئ',
        spectating      = 'مشاهدة',
        eliminated      = 'تم إقصاؤك',
        afkWarning      = 'تحذير خمول — تحرك الآن',
        reconnect       = 'العودة إلى المباراة',
        noPermission    = 'ليس لديك صلاحية.',
        alreadyInMatch  = 'أنت بالفعل داخل مباراة.'
    }
}

-- ============================================================================
-- 2. OPEN MENU — location / command / keybind / vRP menu
-- ============================================================================

Config.OpenMenu = {

    location = {
        enabled = true,

        coords = vector3(
            -1035.42,
            -2733.18,
            13.75
        ),

        distance     = 2.0,   -- interaction distance
        drawDistance = 15.0,  -- marker draw distance

        marker = {
            enabled = true,
            type    = 1,
            scale   = vector3(1.0, 1.0, 1.0),
            color   = { r = 255, g = 40, b = 70, a = 110 },
            zOffset = -0.95,
            bobUpAndDown = false,
            rotate  = false
        },

        blip = {
            enabled = true,
            sprite  = 304,
            color   = 1,
            scale   = 0.8,
            display = 4,
            shortRange = true,
            name    = 'M5 Ranked PvP'
        }
    },

    -- vRP main menu entry (server side registration, toggled from here for convenience)
    vrpRegisterMenu = {
        enabled     = true,
        name        = 'PvP Ranked',
        description = 'Open the M5 Ranked PvP competitive hub'
    },

    command = {
        enabled = true,
        name    = 'pvp'
    },

    keybind = {
        enabled = true,
        key     = 'F6',
        label   = 'M5 Ranked PvP — Open Menu'
    },

    -- The search dock stays on screen after the hub is closed. NUI without
    -- focus cannot receive clicks, so this key cancels the search from the
    -- game world; the dock's X still works while the hub is open.
    cancelKeybind = {
        enabled = true,
        key     = 'F7',
        label   = 'M5 Ranked PvP — Cancel Search'
    }
}

-- ============================================================================
-- 2b. TRAINING
-- ============================================================================

Config.Training = {
    -- How the player leaves the training range.
    exit = {
        enabled = true,

        -- Key binding. The player can rebind it in
        -- FiveM: Settings > Key Bindings > FiveM.
        keybind = {
            enabled = true,
            key     = 'BACK',                              -- backspace
            display = 'BACKSPACE',                         -- shown in the on screen hint
            label   = 'M5 Ranked PvP — Exit Training'
        },

        -- Chat command, e.g. /exittraining
        command = {
            enabled = true,
            name    = 'exittraining'
        },

        -- On screen hint inside the training panel
        hint = {
            enabled = true,
            text    = 'EXIT TRAINING'
        },

        -- Press the key twice inside this window (ms) to leave.
        -- 0 = a single press exits immediately.
        confirmWindow = 2500
    }
}

-- ============================================================================
-- 3. ADAPTIVE THREAD TIMING (performance)
-- ============================================================================
-- The proximity thread scales its wait time with the distance to the point,
-- so it costs almost nothing when nobody is around.

Config.Timing = {
    idleFar     = 3000, -- > 150m from the point
    idleMid     = 1000, -- 50m .. 150m
    idleNear    = 250,  -- drawDistance .. 50m
    active      = 0,    -- inside drawDistance (marker rendering requires per frame)
    hudTick     = 200,  -- HUD refresh while inside a match
    matchTick   = 250,  -- match logic (zone bounds, afk, spectator)
    spectateTick= 0     -- spectator camera (only while spectating)
}

-- ============================================================================
-- 3b. BRAND — the name shown at the top of the hub
-- ============================================================================
--
-- Drawn above the page title, exactly where "FUTURE RP / MATCHMAKING" sits in
-- the reference. `name` is plain and `accent` is tinted with your accent
-- colour, so "FUTURE" + "RP" reads as one name in two tones.
--
Config.Brand = {
    enabled = true,

    name   = 'FUTURE',   -- plain half
    accent = 'RP',       -- tinted half; set to '' for a single-colour name

    -- The small line underneath. Leave it as it is to always read
    -- MATCHMAKING like the reference, or set it to '' to show the name of the
    -- page you are on instead (LEADERBOARD, STORE, ...).
    subtitle = 'MATCHMAKING'
}

-- ============================================================================
-- 4. UI / THEME
-- ============================================================================

Config.UI = {

    -- ------------------------------------------------------------------
    -- COLOURS
    -- Every colour the interface uses lives here. They are pushed into the
    -- NUI as CSS variables the moment the hub opens, so changing a value
    -- here restyles the whole script — menu, HUD, kill feed, overlays and
    -- native drawings alike. Accepts any CSS colour (#hex, rgb(), hsl()).
    -- ------------------------------------------------------------------
    colors = {
        -- brand accent
        accent      = '#2E9BE6',   -- primary blue
        accentDark  = '#1B6FB0',   -- gradient end / pressed state
        accentSoft  = 'rgba(46,155,230,.16)', -- tinted fills
        accentGlow  = 'rgba(46,155,230,.45)', -- glows and shadows

        -- surfaces
        background  = '#080B10',   -- page ground
        panel       = '#0D131B',   -- cards, modals
        panelAlt    = '#121A24',   -- raised rows
        panelDeep   = '#070A0F',   -- inputs, wells

        -- lines
        edge        = 'rgba(70,150,220,.24)',  -- accented borders
        edgeSoft    = 'rgba(255,255,255,.07)', -- neutral borders

        -- type
        text        = '#EAF1F8',
        textDim     = '#8FA0B4',
        textFaint   = '#5C6B7D',

        -- states
        win         = '#2FDD9B',
        lose        = '#FF3B4E',
        gold        = '#F5C542',

        -- teams (players may override these in Settings)
        teamA       = '#3FA9FF',
        teamB       = '#FF4757',

        -- avatar tile gradient
        avatarFrom  = '#2E9BE6',
        avatarTo    = '#1B6FB0',

        -- light tips of gradients and small accents
        accentLight = '#7FD0FF',   -- bright end of accent bars
        winLight    = '#8CF5CE',   -- bright end of the health bar
        levelBadge  = '#2E9BE6',   -- level pill on the avatar
        leaderMark  = '#F5C542'    -- party leader crown
    },

    -- Corner rounding used across the interface (px)
    radius = 10,

    -- Rank colours. The server sends the authoritative list on boot; these
    -- are the fallback used before the payload arrives.
    rankColors = {
        UNRANKED  = '#5A616D',
        IRON      = '#7C7C80',
        BRONZE    = '#A3703C',
        SILVER    = '#B9C1CC',
        GOLD      = '#E8B33C',
        PLATINUM  = '#37C2D8',
        DIAMOND   = '#8E6BFF',
        ASCENDANT = '#22C97C',
        IMMORTAL  = '#E0304E',
        RADIANT   = '#FFE9A8'
    },

    animations = {
        enabled        = true,
        pageFade       = 180,
        counterSpeed   = 900,   -- RP counter roll duration (ms)
        rankUpDuration = 5200
    },

    scale = 1.0,           -- global UI scale multiplier
    blurBackground = true, -- blur the game behind the hub

    -- Decorative layers behind the hub
    decor = {
        grain     = true,  -- fine film grain
        vignette  = true,  -- darkened corners
        glow      = true   -- accent glow bloom
    }
}

-- ============================================================================
-- 5. HUD
-- ============================================================================

Config.HUD = {
    enabled          = true,
    scale            = 1.0,
    showPing         = true,
    showAlivePlayers = true,
    showAmmo         = true,
    showHealth       = true,
    showArmor        = true,
    showWeapon       = true,
    showRoundTimer   = true,

    -- Shown over the arena between the deploy and the first countdown: the map
    -- name, both team names and every player on them. The countdown closes it
    -- early, so `duration` is only the cap for a slow start.
    showcase = {
        enabled  = true,
        duration = 8,        -- seconds
        showIds  = true      -- print the player id next to the name
    },

    -- Player card, bottom left of the match HUD.
    player = {
        enabled  = true,
        showId   = true,
        segments = 10        -- ticks across the health and armour bars
    },

    -- Weapon card, bottom right of the match HUD.
    weapon = {
        enabled  = true,
        segments = 12,       -- ticks across the magazine bar
        -- Optional artwork per weapon. Put the files under Files/ui/img/ and
        -- point at them with nui://m5_rankedpvp/Files/ui/img/<file>. Anything
        -- not listed here falls back to a drawn silhouette, so this can stay
        -- empty and the panel still looks finished.
        images = {
            -- ['WEAPON_PISTOL_MK2']   = 'nui://m5_rankedpvp/Files/ui/img/pistol_mk2.png',
            -- ['WEAPON_CARBINERIFLE'] = 'nui://m5_rankedpvp/Files/ui/img/carbine.png',
        }
    },

    -- Full scoreboard shown while a key is held during a match.
    -- The key is registered with FiveM's keybinding system, so a player can
    -- rebind it under Settings > Key Bindings > FiveM > M5 Ranked PvP.
    scoreboard = {
        enabled  = true,
        key      = 'TAB',            -- default binding
        display  = 'TAB',            -- what the hint at the bottom shows
        label    = 'M5 Ranked PvP — Scoreboard',
        showHint = true,
        -- Show it automatically during the round-end and match-end pauses
        autoOnRoundEnd = true
    },

    -- Hold a key to leave the match. A hold rather than a press so it can
    -- never be hit by accident mid fight, and it is bound through FiveM's
    -- keybinding system so the player can move it off X.
    surrender = {
        enabled  = true,
        key      = 'X',
        display  = 'X',
        label    = 'M5 Ranked PvP — Surrender (hold)',
        holdTime = 5,                 -- seconds the key must stay down
        -- Refuse while the round is still counting down, so nobody quits
        -- before the first shot by leaning on the key.
        blockDuringCountdown = true
    },

    killFeed = {
        enabled   = true,
        position  = 'right', -- 'right' | 'left'
        maxLines  = 6,
        lifetime  = 6000,
        showHeadshotIcon = true
    },

    -- Disable the GTA minimap while inside a match (mode can override)
    hideMinimap = true,
    -- Hide the default vRP/HUD elements event (fired for other resources to hook)
    externalHudEvent = 'm5rp:hud:external'
}

-- ============================================================================
-- 6. SOUNDS
-- ============================================================================
-- name = the file-less native frontend sound (soundset), or an html5 key played
-- by the NUI. `nui = true` plays a synthesised WebAudio cue from app.js.

Config.Sounds = {
    enabled = true,
    volume  = 0.55,

    click        = { nui = true,  key = 'click' },
    hover        = { nui = true,  key = 'hover' },
    open         = { nui = true,  key = 'open' },
    close        = { nui = true,  key = 'close' },
    queueStart   = { nui = true,  key = 'queue' },
    matchFound   = { nui = true,  key = 'found' },
    accept       = { nui = true,  key = 'accept' },
    countdown    = { nui = true,  key = 'tick' },
    roundStart   = { nui = true,  key = 'go' },
    roundWin     = { nui = true,  key = 'roundwin' },
    roundLoss    = { nui = true,  key = 'roundloss' },
    kill         = { nui = true,  key = 'kill' },
    headshot     = { nui = true,  key = 'headshot' },
    victory      = { nui = true,  key = 'victory' },
    defeat       = { nui = true,  key = 'defeat' },
    rankUp       = { nui = true,  key = 'rankup' },
    rankDown     = { nui = true,  key = 'rankdown' },
    error        = { nui = true,  key = 'error' },
    warning      = { nui = true,  key = 'warning' }
}

-- ============================================================================
-- 7. CAMERA / SPECTATOR
-- ============================================================================

Config.Spectator = {
    enabled          = true,
    followDistance   = 2.4,
    followHeight     = 0.65,
    smoothing        = 0.12,
    freecamSpeed     = 0.6,
    freecamFastSpeed = 2.2,
    showOverlay      = true,

    keys = {
        next      = 174, -- LEFT ARROW  (INPUT_CELLPHONE_LEFT)
        prev      = 175, -- RIGHT ARROW
        toggleCam = 22,  -- SPACE
        exit      = 202  -- BACKSPACE
    }
}

-- ============================================================================
-- 8. VISUAL EFFECTS
-- ============================================================================

Config.Effects = {
    enabled = true,

    -- Screen effect applied while the countdown runs
    countdownEffect = 'MinigameTransitionIn',

    -- Damage / death feedback
    deathEffect     = 'DeathFailOut',
    hitmarker       = true,
    hitmarkerTime   = 140,
    headshotMarkerColor = { r = 255, g = 60, b = 70 },
    hitmarkerColor      = { r = 255, g = 255, b = 255 },

    -- Out of bounds screen tint
    outOfBoundsEffect = 'DeathFailMPDark',

    -- Spawn protection shimmer
    spawnProtectionAlpha = 120
}

-- ============================================================================
-- 9. MAP BOUNDARY (client presentation only, logic is server driven)
-- ============================================================================

Config.Boundary = {
    warningText   = 'RETURN TO COMBAT ZONE',
    countdownFrom = 5,
    drawArrow     = true,
    tintScreen    = true,
    pulseHud      = true
}

-- ============================================================================
-- 10. DISPLAY / MISC
-- ============================================================================

Config.Display = {
    -- Nameplates above teammates while in a match
    teammateNameplates = true,
    nameplateDistance  = 60.0,

    -- Show the enemy team nameplates (usually off for competitive integrity)
    enemyNameplates    = false,

    -- Force first person while inside a ranked match
    forceFirstPerson   = false,

    -- Disable radio / weapon wheel inside matches
    disableWeaponWheel = true,

    -- Draw a small marker above the last player who damaged you
    showDamageSource   = false
}

-- ============================================================================
-- 11. CLIENT COMMANDS (openers only — gameplay commands are server side)
-- ============================================================================

Config.ClientCommands = {
    -- Toggle the personal HUD
    toggleHud = { enabled = true, name = 'pvphud' }
}

-- ============================================================================
-- 12. DEFAULT PERSONAL SETTINGS (stored in NUI localStorage, synced on demand)
-- ============================================================================

Config.DefaultSettings = {
    uiVolume        = 55,
    musicVolume     = 25,
    killSounds      = true,
    hudSize         = 100,
    killFeedPos     = 'right',
    showPing        = true,
    showMinimap     = false,
    teamColorA      = '#2ED9C3',
    teamColorB      = '#FF4757',
    spectatorAuto   = true,
    language        = 'en',
    visualEffects   = true,
    lowSpecMode     = false
}
