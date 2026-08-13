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
-- 4. UI / THEME
-- ============================================================================

Config.UI = {
    -- Base colour identity of the interface (also used by native drawings)
    colors = {
        accent      = '#FF2E4D',
        accentSoft  = '#FF6B80',
        background  = '#07080A',
        surface     = '#101216',
        surfaceAlt  = '#171A20',
        line        = '#23272F',
        text        = '#F4F6F8',
        textDim     = '#8A929E',
        win         = '#28E0A0',
        lose        = '#FF3B4E',
        teamA       = '#2ED9C3',
        teamB       = '#FF4757',
        gold        = '#FFC94A'
    },

    animations = {
        enabled        = true,
        pageFade       = 180,
        cardStagger    = 40,
        counterSpeed   = 900,   -- RP counter roll duration (ms)
        rankUpDuration = 5200
    },

    scale = 1.0,          -- global UI scale multiplier
    blurBackground = true, -- apply a screen blur behind the menu

    -- Fallback rank colours (server sends the authoritative list on boot)
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
