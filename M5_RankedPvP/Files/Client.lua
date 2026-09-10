--[[
    ============================================================================
     M5 Ranked PvP — Files/Client.lua
    ----------------------------------------------------------------------------
     Client side presentation and input layer.

     The client never decides anything that matters: it renders, it listens and
     it *reports* observations. RP, ranks, kills, MVP and headshot validation
     are all resolved on the server.

     Thread policy
        · One always-on proximity thread with an adaptive wait (3000ms when far
          away, 0ms only while the marker is actually on screen).
        · One match thread that only exists while the player is inside a match.
          It runs per frame exclusively during a live round while the player is
          alive — that is where bullet detection has to happen — and drops to
          200ms in every other state.
        · One spectator thread that only exists while spectating.

     Layout of this file
        01  State
        02  Helpers
        03  NUI bridge
        04  Boot / data events
        05  Open menu (marker, command, keybind, vRP menu)
        06  Match lifecycle
        07  Combat detection (headshot, damage, death)
        08  Boundary
        09  HUD
        10  Spectator
        11  Training
        11b Bot match (staff practice)
        12  Notifications & misc events
    ============================================================================
]]

-- ============================================================================
-- 01. STATE
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Text (Locale.lua)
--
-- The English line is the key. Everything the player reads — here, in the
-- notifications the server sends, and in the interface — is resolved through
-- this one table, so Locale.lua is the only file to edit to change wording.
-- ---------------------------------------------------------------------------
local Lang = Locale.default or 'en'

local function localeTable(code)
    return (Locale and Locale[code]) or (Locale and Locale[Locale.fallback or 'en']) or {}
end

--- Translates one line, or returns it unchanged when there is no translation.
local function _L(str)
    if type(str) ~= 'string' then return str end
    return localeTable(Lang)[str] or str
end

--- Translates then formats. The pattern has to be translated before the
--- values go in, or the placeholders would be filled into the English line.
local function _Lf(str, ...)
    local ok, res = pcall(string.format, _L(str), ...)
    return ok and res or _L(str)
end

--- Notifications can be pinned to one language with Locale.notifications,
--- independently of the language the player set the interface to.
local function notifyLang()
    return Locale.notifications or Lang
end

local function _Ln(str)
    if type(str) ~= 'string' then return str end
    return localeTable(notifyLang())[str] or str
end

local function _Lnf(str, ...)
    local ok, res = pcall(string.format, _Ln(str), ...)
    return ok and res or _Ln(str)
end

--- Legacy shim: Config.Text keys still work, but resolve through Locale.
local L = setmetatable({}, { __index = function(_, key)
    local legacy = (Config.Text and Config.Text.en and Config.Text.en[key]) or key
    return _L(legacy)
end })

--- The bundle every NUI open() needs: the active language, its whole string
--- table and whether it reads right to left. Sending the table means the
--- interface never keeps a dictionary of its own — Locale.lua is the only
--- source of wording anywhere in the resource.
local function localePayload()
    local langs, tables = {}, {}
    for _, entry in ipairs(Locale.available or {}) do
        langs[#langs + 1] = { id = entry.id, label = entry.label }
        tables[entry.id]  = Locale[entry.id] or {}
    end
    return {
        language  = Lang,
        -- toasts raised inside the interface follow this, not `language`
        notifyLanguage = notifyLang(),
        languages = langs,
        -- every table, not just the active one: the interface can then switch
        -- language instantly instead of waiting on a round trip to Lua, which
        -- would leave it showing the previous language until the reply landed
        strings   = tables,
        rtl       = Locale.rtl or {}
    }
end


local State = {
    booted     = false,
    menuOpen   = false,
    menuPage   = nil,

    profile    = nil,   -- boot payload

    inMatch    = false,
    matchId    = nil,
    matchState = 'NONE',
    team       = 0,
    ffa        = false,
    alive      = false,
    frozen     = false,
    roundLive  = false,

    map        = nil,   -- { center, radius }
    settings   = {},    -- match settings from the server
    roster     = {},    -- [serverId] = { name, team }

    spectating = false,
    spectateTargets = {},
    spectateIndex   = 1,
    spectateFree    = false,
    spectateCam     = nil,

    training   = false,
    trainingProps = {},

    -- bot match (staff practice): local peds, reported by this client only
    bots        = {},
    botsActive  = false,
    botsHeld    = false,
    botMatchId  = nil,
    botHeadshot = false,

    -- boundary
    outside      = false,
    outsideUntil = 0,

    -- combat bookkeeping
    lastHealth   = 200,
    lastArmor    = 0,
    lastShotAt   = 0,
    lastDamageBy = nil,
    lastDamageAt = 0,
    hitmarkerUntil = 0,
    hitmarkerHead  = false,
    reportedDeath  = false,
    spawnProtectUntil = 0,

    -- afk activity
    lastActivityPush = 0,
    lastCamHeading   = 0.0,
    lastPos          = vector3(0.0, 0.0, 0.0),

    -- proximity
    nearPoint = false
}

local blipHandle = nil
local matchThreadRunning = false
local spectateThreadRunning = false

-- ============================================================================
-- 02. HELPERS
-- ============================================================================

-- Both are defined further down but used by code above them, so the locals
-- have to exist first.
local clearBots
local idleVisualGuard

-- ---------------------------------------------------------------------------
-- The natives on the per frame path, held as upvalues.
--
-- A native is a global, and every call through a global name is a hash lookup
-- in the environment table. The match loop runs these sixty times a second,
-- some of them several times over, so binding them once here turns each of
-- those lookups into a register read. Nothing else changes: these are the
-- same functions under the same names.
-- ---------------------------------------------------------------------------
local GetGameTimer          = GetGameTimer
local PlayerPedId           = PlayerPedId
local PlayerId              = PlayerId
local GetEntityCoords       = GetEntityCoords
local GetEntityHealth       = GetEntityHealth
local GetPedArmour          = GetPedArmour
local IsEntityDead          = IsEntityDead
local IsPedShooting         = IsPedShooting
local IsControlPressed      = IsControlPressed
local DisableControlAction  = DisableControlAction
local GetActivePlayers      = GetActivePlayers
local GetPlayerPed          = GetPlayerPed
local GetPlayerServerId     = GetPlayerServerId
local DoesEntityExist       = DoesEntityExist
local GetGameplayCamRot     = GetGameplayCamRot
local GetCurrentPedWeapon   = GetCurrentPedWeapon
local math_abs, math_floor, math_max, math_sqrt =
      math.abs, math.floor, math.max, math.sqrt

local function ms() return GetGameTimer() end

local function dbg(fmt, ...)
    if Config.Debug then print(('[M5RP] ' .. fmt):format(...)) end
end

local function playerPed() return PlayerPedId() end

-- ---------------------------------------------------------------------------
-- Integration hooks (Export.lua)
--
-- Calls the matching M5.Client hook and fires the same moment as an event, so
-- other resources can listen without touching this file. Errors inside a hook
-- are printed and swallowed — nothing there may break the match.
-- ---------------------------------------------------------------------------
local function hook(name, data)
    local fn = M5 and M5.Client and M5.Client[name]
    if type(fn) == 'function' then
        local ok, e = pcall(fn, data)
        if not ok then print(('[M5RP] Export.lua M5.Client.%s failed: %s'):format(name, tostring(e))) end
    end
    TriggerEvent('m5rp:' .. name, data)
end

--- The whitelist the server validates against, hashed once.
---
--- This used to be a table literal walked with GetHashKey on every lookup —
--- a fresh 33 entry table and up to 33 native calls, on the HUD tick five
--- times a second and again on every death. Hashing it once at load turns
--- that into a single table read.
local WEAPON_NAME_BY_HASH = {}
do
    local names = {
        'WEAPON_UNARMED','WEAPON_KNIFE','WEAPON_BAT',
        'WEAPON_PISTOL','WEAPON_PISTOL_MK2','WEAPON_COMBATPISTOL','WEAPON_APPISTOL',
        'WEAPON_HEAVYPISTOL','WEAPON_VINTAGEPISTOL','WEAPON_SNSPISTOL',
        'WEAPON_MICROSMG','WEAPON_SMG','WEAPON_SMG_MK2','WEAPON_ASSAULTSMG',
        'WEAPON_COMBATPDW','WEAPON_MACHINEPISTOL',
        'WEAPON_ASSAULTRIFLE','WEAPON_ASSAULTRIFLE_MK2','WEAPON_CARBINERIFLE',
        'WEAPON_CARBINERIFLE_MK2','WEAPON_ADVANCEDRIFLE','WEAPON_SPECIALCARBINE',
        'WEAPON_BULLPUPRIFLE','WEAPON_COMPACTRIFLE',
        'WEAPON_PUMPSHOTGUN','WEAPON_SAWNOFFSHOTGUN','WEAPON_ASSAULTSHOTGUN','WEAPON_HEAVYSHOTGUN',
        'WEAPON_SNIPERRIFLE','WEAPON_HEAVYSNIPER','WEAPON_MARKSMANRIFLE',
        'WEAPON_COMBATMG','WEAPON_MG'
    }
    for i = 1, #names do
        WEAPON_NAME_BY_HASH[GetHashKey(names[i])] = names[i]
    end
end

local function weaponNameFromHash(hash)
    return WEAPON_NAME_BY_HASH[hash]
end

local function currentWeaponName(ped)
    local ok, hash = GetCurrentPedWeapon(ped or playerPed(), true)
    if not ok then return 'WEAPON_UNARMED' end
    return WEAPON_NAME_BY_HASH[hash] or 'WEAPON_UNARMED'
end

local function serverIdOfPed(ped)
    local plr = NetworkGetPlayerIndexFromPed(ped)
    if plr == -1 or plr == nil then return nil end
    return GetPlayerServerId(plr)
end

local function isPlayerPed(ped)
    return ped and ped ~= 0 and DoesEntityExist(ped) and IsPedAPlayer(ped)
end

-- Bumped on every loadout. A settle thread that finds a newer number has been
-- overtaken by a later spawn and gets out of the way instead of fighting it.
local loadoutSeq = 0

--- Applies a loadout handed down by the server.
---
--- `settle` is for the loadouts handed out on a spawn. NetworkResurrectLocalPlayer
--- does not finish on the frame it is called: the engine keeps working on the
--- ped over the next few, and strips its weapons as part of that. A loadout
--- given on the same frame is therefore sometimes wiped a moment later and the
--- player lands empty handed with nothing to explain it. Watching the primary
--- weapon for a few frames and handing it back if it vanishes closes that
--- window; away from a respawn there is nothing to race, so it is skipped.
local function applyLoadout(loadout, settle)
    loadoutSeq = loadoutSeq + 1
    local seq = loadoutSeq

    State.loadout = loadout

    local function give()
        local ped = playerPed()
        RemoveAllPedWeapons(ped, true)
        if not loadout then return nil end

        SetEntityMaxHealth(ped, (loadout.health or 100) + 100)
        SetEntityHealth(ped, (loadout.health or 100) + 100)
        SetPedArmour(ped, loadout.armor or 0)

        local primary
        if loadout.weapons then
            for i = 1, #loadout.weapons do
                local w = loadout.weapons[i]
                local hash = GetHashKey(w.name)
                GiveWeaponToPed(ped, hash, w.ammo or 100, false, i == 1)
                if i == 1 then primary = hash end
            end
        end
        -- put it in their hands, not on their back
        if primary then SetCurrentPedWeapon(ped, primary, true) end

        State.lastHealth = GetEntityHealth(ped)
        State.lastArmor  = GetPedArmour(ped)
        return primary
    end

    local primary = give()
    if not settle or not primary then return end

    -- A respawn is not over on the frame it starts, and other resources tend
    -- to re-apply their own inventory on spawn too, so the window is measured
    -- in seconds rather than in frames.
    local window = ((Config.Loadout and Config.Loadout.settleSeconds) or 3.0) * 1000
    Citizen.CreateThread(function()
        local until_ = ms() + window
        while ms() < until_ do
            Citizen.Wait(0)
            -- a newer loadout owns the ped now
            if seq ~= loadoutSeq then return end
            if not HasPedGotWeapon(playerPed(), primary, false) then
                -- whatever took it took everything, so hand the whole loadout
                -- back rather than patching one weapon in
                give()
            end
        end
    end)
end

--- Puts the last loadout back on a player who somehow ended up holding nothing.
---
--- The settle window above covers the spawn itself. This covers the rest of the
--- round: nothing in a match disarms a player legitimately — the weapon wheel
--- is disabled and weapons cannot be dropped — so an empty hand mid fight is
--- always something else's doing, and the player has no way to recover from it.
local nextRearm = 0

--- True when the ped is holding none of the loadout it was given.
local function holdingNothing(ped)
    local lo = State.loadout
    if not lo or not lo.weapons or #lo.weapons == 0 then return false end
    ped = ped or playerPed()
    for i = 1, #lo.weapons do
        if HasPedGotWeapon(ped, GetHashKey(lo.weapons[i].name), false) then return false end
    end
    return true
end

local function rearmGuard(ped)
    local cfg = Config.Loadout or {}
    if cfg.rearmWhenEmpty == false then return end
    -- Not `roundLive`, and not `not frozen`. A round based match spawns the
    -- player frozen and only goes live once the countdown runs out, so those
    -- two conditions switched the guard off for the whole freeze — which is
    -- exactly the window where a spawn strips the ped and nobody notices
    -- until the round has already started.
    if not State.inMatch or not State.alive then return end

    -- the clock before the loadout: this runs every frame and only does its
    -- work once a second, so the cheapest test comes first
    local t = ms()
    if t < nextRearm then return end

    local lo = State.loadout
    if not lo or not lo.weapons or #lo.weapons == 0 then return end
    nextRearm = t + math.floor(((cfg.rearmEvery or 1.0) * 1000))

    if not holdingNothing(ped) then return end

    -- holding nothing from the loadout: put it back
    dbg('re-arming: the player was left with none of their loadout')
    applyLoadout(lo, false)
end

local function teleport(spawn, freeze)
    local ped = playerPed()
    SetEntityCoordsNoOffset(ped, spawn.x, spawn.y, spawn.z, false, false, false)
    SetEntityHeading(ped, spawn.h or 0.0)
    NetworkResurrectLocalPlayer(spawn.x, spawn.y, spawn.z, spawn.h or 0.0, true, false)
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)

    if freeze then
        FreezeEntityPosition(ped, true)
        State.frozen = true
    end

    -- give the world a moment then release the collision
    Citizen.CreateThread(function()
        local timeout = ms() + 5000
        while not HasCollisionLoadedAroundEntity(ped) and ms() < timeout do
            RequestCollisionAtCoord(spawn.x, spawn.y, spawn.z)
            Citizen.Wait(50)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Coming back
--
-- A match and the training range both take the player out of the world and
-- put them somewhere else. What used to happen at the end was nothing: they
-- were left standing in an empty arena, or on whatever the bucket dropped
-- them into. These two remember where they came from and put them back.
-- ---------------------------------------------------------------------------
local returnPoint = nil

--- Records where the player is standing, for as long as it takes to get back.
--- Called on the way out, and only then — a second call while already away
--- would record the arena rather than the world.
local function rememberPoint()
    if State.inMatch or State.training then return end
    local cfg = Config.Return or {}
    if cfg.enabled == false then return end

    local ped = playerPed()
    local pos = GetEntityCoords(ped)
    local max = cfg.maxHeight or 900.0

    -- Somewhere in the sky is not a place anybody chose to be, and sending
    -- them back to it would be worse than leaving them where they are.
    if pos.z > max then returnPoint = nil return end

    returnPoint = { x = pos.x, y = pos.y, z = pos.z, h = GetEntityHeading(ped) }
end

--- Puts the player back. `which` names the way out, so each one can be turned
--- off on its own: 'afterTraining', 'afterMatch' or 'afterSurrender'.
local function returnHome(which)
    local cfg = Config.Return or {}
    if cfg.enabled == false then return end
    if which and cfg[which] == false then return end

    local target
    if cfg.useCoords and cfg.coords then
        target = { x = cfg.coords.x, y = cfg.coords.y, z = cfg.coords.z,
                   h = cfg.coords.w or 0.0 }
    else
        target = returnPoint
    end

    returnPoint = nil
    if not target then return end
    teleport(target, false)
end

-- Looped effects run until something stops them. Every one started without a
-- duration is remembered here so it can always be cleared, whatever happens
-- next — leaving the match, disconnecting, the resource restarting. Without
-- this, walking out of the combat zone and then leaving the match left the
-- boundary tint burned onto the screen with no way back.
local activeEffects = {}
local blurOn = false

local function screenEffect(name, duration)
    if not Config.Effects.enabled or not name then return end
    if duration and duration > 0 then
        -- StartScreenEffect takes milliseconds. Dividing by 1000 made every
        -- timed effect last about a millisecond, so none of them were visible.
        StartScreenEffect(name, duration, false)
    else
        StartScreenEffect(name, 0, true)
        activeEffects[name] = true
    end
end

local function stopScreenEffect(name)
    if not name then return end
    StopScreenEffect(name)
    activeEffects[name] = nil
end

--- Clears every looped effect this resource started. Safe to call at any time.
local function clearScreenEffects()
    for name in pairs(activeEffects) do StopScreenEffect(name) end
    activeEffects = {}
    -- belt and braces: an effect started before a resource restart is not in
    -- the table above, and the player has no other way to get rid of it
    StopAllScreenEffects()
    AnimpostfxStopAll()
    TriggerScreenblurFadeOut(0)
    ClearTimecycleModifier()
    ClearExtraTimecycleModifier()
    SetTransitionTimecycleModifier('default', 0.5)
    ResetScenarioTypesEnabled()
    blurOn = false
end

-- ============================================================================
-- 03. NUI BRIDGE
-- ============================================================================

local function nui(payload)
    SendNUIMessage(payload)
end

-- Forward declaration. The out-of-bounds panel is owned by the boundary code
-- much further down, but the match events above it have to be able to take the
-- panel down, and a local declared later is not in scope up here.
local showBoundary, hideBoundary, clearBoundary

local function setFocus(on)
    SetNuiFocus(on, on)
    SetNuiFocusKeepInput(false)
end

local function openMenu(page)
    if State.menuOpen then return end
    if State.inMatch and State.roundLive and State.alive then
        -- the hub cannot be opened during a live round while alive
        nui({ action = 'toast', kind = 'warning', message = L.alreadyInMatch })
        return
    end

    State.menuOpen = true
    State.menuPage = page

    if not State.booted then
        TriggerServerEvent('m5rp:sv:boot')
    end

    setFocus(true)
    nui({
        action = 'open',
        page   = page,
        theme  = Config.UI,
        -- the server name rides with every open, exactly like the theme does.
        -- Leaving it out here left the markup's placeholder name on screen for
        -- anyone who opened the hub the normal way.
        brand  = Config.Brand,
        sounds = Config.Sounds,
        text   = L,
        locale = localePayload(),
        defaults = Config.DefaultSettings,
        blur   = Config.UI.blurBackground
    })

    if Config.UI.blurBackground then
        TriggerScreenblurFadeIn(180)
        blurOn = true
    end
end

local function closeMenu()
    -- the blur is dropped even when the menu was already considered closed:
    -- the popups that grab focus on their own set menuOpen without ever
    -- touching the blur, and one missed fade-out leaves the screen hazy.
    if blurOn then
        TriggerScreenblurFadeOut(180)
        blurOn = false
    end
    if not State.menuOpen then return end
    State.menuOpen = false
    setFocus(false)
    nui({ action = 'close' })
end

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb('ok')
end)

RegisterNUICallback('queue', function(data, cb)
    TriggerServerEvent('m5rp:sv:queue', data.action, data.mode, data.autoFill == true)
    cb('ok')
end)

RegisterNUICallback('ready', function(data, cb)
    TriggerServerEvent('m5rp:sv:ready', data.id, data.accept == true)
    cb('ok')
end)

RegisterNUICallback('mapVote', function(data, cb)
    TriggerServerEvent('m5rp:sv:mapVote', data.mapId)
    cb('ok')
end)

RegisterNUICallback('party', function(data, cb)
    TriggerServerEvent('m5rp:sv:party', data.action, data)
    cb('ok')
end)

RegisterNUICallback('custom', function(data, cb)
    TriggerServerEvent('m5rp:sv:custom', data.action, data)
    cb('ok')
end)

RegisterNUICallback('fetch', function(data, cb)
    TriggerServerEvent('m5rp:sv:fetch', data.what, data)
    cb('ok')
end)

RegisterNUICallback('admin', function(data, cb)
    TriggerServerEvent('m5rp:sv:admin', data.action, data)
    cb('ok')
end)

RegisterNUICallback('store', function(data, cb)
    -- id only: the price and the balance are the server's business
    TriggerServerEvent('m5rp:sv:store', data.action, data.kind, data.id)
    cb('ok')
end)

RegisterNUICallback('settings', function(data, cb)
    if data and data.settings then
        TriggerServerEvent('m5rp:sv:settings', data.settings)

        -- Follow the player's choice here as well, so the notifications this
        -- file and the server produce switch language with the interface.
        local picked = data.settings.language
        if picked and Locale[picked] and picked ~= Lang then
            Lang = picked
            SendNUIMessage({ action = 'locale', data = localePayload() })
        end
    end
    cb('ok')
end)

RegisterNUICallback('action', function(data, cb)
    TriggerServerEvent('m5rp:sv:action', data.action, data)
    if data.action == 'leaveMatch' or data.action == 'training' then
        closeMenu()
    end
    cb('ok')
end)

-- ============================================================================
-- 04. BOOT / DATA EVENTS
-- ============================================================================

RegisterNetEvent('m5rp:cl:boot', function(payload)
    State.booted  = true
    State.profile = payload
    -- the theme and the server name ride along so the HUD and overlays are
    -- styled and titled from the config even when the player never opens the hub
    nui({ action = 'boot', data = payload, theme = Config.UI, brand = Config.Brand })
end)

RegisterNetEvent('m5rp:cl:data', function(payload)
    nui({ action = 'data', data = payload })
end)

RegisterNetEvent('m5rp:cl:party', function(payload)
    nui({ action = 'party', data = payload })
    if payload and payload.invite then
        nui({ action = 'toast', kind = 'info',
              message = ('%s invited you to a party'):format(payload.invite.from) })
    end
end)

RegisterNetEvent('m5rp:cl:custom', function(payload)
    nui({ action = 'custom', data = payload })
end)

RegisterNetEvent('m5rp:cl:queue', function(payload)
    nui({ action = 'queue', data = payload })
end)

RegisterNetEvent('m5rp:cl:matchFound', function(payload)
    nui({ action = 'matchFound', data = payload })

    if payload and not payload.cancel and not payload.done then
        if not State.menuOpen then
            -- the accept popup needs focus even if the hub was closed
            State.menuOpen = true
            setFocus(true)
            nui({ action = 'open', page = 'ranked', theme = Config.UI, brand = Config.Brand, sounds = Config.Sounds,
                  text = L, locale = localePayload(), defaults = Config.DefaultSettings,
                  silent = true })
        end
        PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
    end
end)

RegisterNetEvent('m5rp:cl:mapVote', function(payload)
    nui({ action = 'mapVote', data = payload })
    if payload and payload.options and not State.menuOpen then
        State.menuOpen = true
        setFocus(true)
        nui({ action = 'open', page = 'ranked', theme = Config.UI, brand = Config.Brand, sounds = Config.Sounds,
              text = L, locale = localePayload(), defaults = Config.DefaultSettings,
              silent = true })
    end
    if payload and payload.close then
        closeMenu()
    end
end)

-- ============================================================================
-- 05. OPEN MENU — marker, command, keybind, vRP menu
-- ============================================================================

RegisterNetEvent('m5rp:cl:openMenu', function(page)
    openMenu(page)
end)

if Config.OpenMenu.command and Config.OpenMenu.command.enabled then
    RegisterCommand(Config.OpenMenu.command.name, function()
        if State.menuOpen then closeMenu() else openMenu() end
    end, false)
end

if Config.OpenMenu.keybind and Config.OpenMenu.keybind.enabled then
    RegisterCommand('m5rp_togglemenu', function()
        if State.menuOpen then closeMenu() else openMenu() end
    end, false)
    RegisterKeyMapping('m5rp_togglemenu',
        Config.OpenMenu.keybind.label or 'M5 Ranked PvP — Open Menu',
        'keyboard', Config.OpenMenu.keybind.key or 'F6')
end

-- Leaving the training range. The overlay itself has no NUI focus, so the
-- in-world exit is a key binding; the hub's Training page also carries a
-- clickable button while training is active.
local function exitTraining()
    if not State.training then return end
    TriggerServerEvent('m5rp:sv:action', 'training', { enable = false })
end

if Config.Training and Config.Training.exit and Config.Training.exit.enabled then
    local exitCfg = Config.Training.exit

    local confirmUntil = 0

    RegisterCommand('m5rp_exittraining', function()
        if not State.training then return end

        local window = exitCfg.confirmWindow or 0
        if window <= 0 then
            exitTraining()
            return
        end

        -- press twice inside the window to leave, so a stray key press during
        -- a training run does not throw the player out
        if ms() <= confirmUntil then
            confirmUntil = 0
            exitTraining()
        else
            confirmUntil = ms() + window
            nui({ action = 'training', data = { confirm = true, seconds = math.ceil(window / 1000) } })
        end
    end, false)

    if exitCfg.keybind and exitCfg.keybind.enabled then
        RegisterKeyMapping('m5rp_exittraining',
            exitCfg.keybind.label or 'M5 Ranked PvP — Exit Training',
            'keyboard', exitCfg.keybind.key or 'BACK')
    end

    if exitCfg.command and exitCfg.command.enabled then
        RegisterCommand(exitCfg.command.name or 'exittraining', function()
            if State.training then
                exitTraining()
            else
                nui({ action = 'toast', kind = 'warning', message = 'You are not in the training range.' })
            end
        end, false)
    end
end

if Config.OpenMenu.cancelKeybind and Config.OpenMenu.cancelKeybind.enabled then
    RegisterCommand('m5rp_cancelsearch', function()
        TriggerServerEvent('m5rp:sv:queue', 'leave')
    end, false)
    RegisterKeyMapping('m5rp_cancelsearch',
        Config.OpenMenu.cancelKeybind.label or 'M5 Ranked PvP — Cancel Search',
        'keyboard', Config.OpenMenu.cancelKeybind.key or 'F7')
end

if Config.ClientCommands.toggleHud and Config.ClientCommands.toggleHud.enabled then
    RegisterCommand(Config.ClientCommands.toggleHud.name, function()
        Config.HUD.enabled = not Config.HUD.enabled
        nui({ action = 'hudVisible', value = Config.HUD.enabled })
    end, false)
end

-- ---------------------------------------------------------------------------
-- Blip
-- ---------------------------------------------------------------------------

local function createBlip()
    local cfg = Config.OpenMenu.location
    if not cfg.enabled or not cfg.blip.enabled then return end
    if blipHandle then return end

    blipHandle = AddBlipForCoord(cfg.coords.x, cfg.coords.y, cfg.coords.z)
    SetBlipSprite(blipHandle, cfg.blip.sprite)
    SetBlipColour(blipHandle, cfg.blip.color)
    SetBlipScale(blipHandle, cfg.blip.scale)
    SetBlipDisplay(blipHandle, cfg.blip.display or 4)
    SetBlipAsShortRange(blipHandle, cfg.blip.shortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(cfg.blip.name)
    EndTextCommandSetBlipName(blipHandle)
end

-- ---------------------------------------------------------------------------
-- Proximity thread (adaptive wait — this is the only always-on thread)
-- ---------------------------------------------------------------------------

local function drawMarkerText(x, y, z, text)
    SetDrawOrigin(x, y, z, 0)
    SetTextFont(4)
    SetTextScale(0.34, 0.34)
    SetTextColour(255, 255, 255, 220)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

Citizen.CreateThread(function()
    Citizen.Wait(2000)

    local cfg = Config.OpenMenu.location
    local markerOn = cfg.enabled == true

    if markerOn then createBlip() end

    local T = Config.Timing
    local point = cfg.coords

    while true do
        local wait = T.idleFar

        idleVisualGuard()

        if not markerOn then
            Citizen.Wait(5000)
            goto continue
        end

        -- the interaction point is disabled while the player is busy
        if State.inMatch or State.spectating or State.training then
            State.nearPoint = false
            Citizen.Wait(2000)
            goto continue
        end

        do
            local ped  = playerPed()
            local pos  = GetEntityCoords(ped)
            local dist = #(pos - point)

            if dist > 150.0 then
                wait = T.idleFar
                State.nearPoint = false
            elseif dist > 50.0 then
                wait = T.idleMid
                State.nearPoint = false
            elseif dist > cfg.drawDistance then
                wait = T.idleNear
                State.nearPoint = false
            else
                wait = T.active

                if cfg.marker.enabled then
                    DrawMarker(
                        cfg.marker.type,
                        point.x, point.y, point.z + (cfg.marker.zOffset or -0.95),
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        cfg.marker.scale.x, cfg.marker.scale.y, cfg.marker.scale.z,
                        cfg.marker.color.r, cfg.marker.color.g, cfg.marker.color.b, cfg.marker.color.a,
                        cfg.marker.bobUpAndDown == true, false, 2,
                        cfg.marker.rotate == true, nil, nil, false)
                end

                if dist <= cfg.distance then
                    State.nearPoint = true
                    drawMarkerText(point.x, point.y, point.z + 0.9, L.openPrompt)
                    if IsControlJustReleased(0, 38) then -- E
                        openMenu()
                    end
                else
                    State.nearPoint = false
                end
            end
        end

        ::continue::
        Citizen.Wait(wait)
    end
end)

-- ============================================================================
-- 06. MATCH LIFECYCLE
-- ============================================================================

local startMatchThread   -- forward declaration
local stopSpectate       -- forward declaration

RegisterNetEvent('m5rp:cl:setup', function(data)
    -- before anything sets State.inMatch: this is the last moment the player
    -- is still standing where they queued from
    rememberPoint()

    State.inMatch    = true
    State.matchId    = data.matchId
    State.matchState = 'STARTING'
    State.team       = data.team or 1
    State.ffa        = data.ffa == true
    State.map        = data.map
    State.settings   = data.settings or {}
    State.alive      = false
    State.reportedDeath = false
    clearBoundary()

    State.roster = {}
    if data.roster then
        for i = 1, #data.roster do
            State.roster[data.roster[i].userId] = data.roster[i]
        end
    end

    closeMenu()

    local sbCfg = (Config.HUD and Config.HUD.scoreboard) or {}
    data.scoreboardHint = (sbCfg.enabled ~= false and sbCfg.showHint ~= false)
                          and (sbCfg.display or 'TAB') or nil
    -- the NUI draws the showcase and both HUD cards from these
    data.hudCfg = {
        showcase = Config.HUD.showcase,
        player   = Config.HUD.player,
        weapon   = Config.HUD.weapon,
        banner   = Config.HUD.banner,
        show     = {
            health = Config.HUD.showHealth  ~= false,
            armor  = Config.HUD.showArmor   ~= false,
            ammo   = Config.HUD.showAmmo    ~= false,
            weapon = Config.HUD.showWeapon  ~= false,
            ping   = Config.HUD.showPing    ~= false,
            timer  = Config.HUD.showRoundTimer ~= false
        }
    }
    nui({ action = 'matchSetup', data = data })
    nui({ action = 'hudVisible', value = Config.HUD.enabled })

    if Config.HUD.hideMinimap and not State.settings.minimap then
        DisplayRadar(false)
    end

    TriggerEvent(Config.HUD.externalHudEvent, false)

    -- movement / jump modifiers coming from a custom room
    local ped = playerPed()
    SetRunSprintMultiplierForPlayer(PlayerId(), State.settings.movement or 1.0)
    SetPedCanRagdoll(ped, false)
    SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
    NetworkSetFriendlyFireOption(true)
    SetCanAttackFriendly(ped, State.settings.friendlyFire == true, false)

    hook('onMatchJoin', {
        matchId = data.matchId, mode = data.mode, modeLabel = data.modeLabel,
        ranked = data.ranked == true, custom = data.custom == true,
        practice = data.practice == true, team = State.team, ffa = State.ffa,
        map = data.map and { id = data.map.id, name = data.map.name } or nil,
        players = data.roster and #data.roster or 0
    })

    startMatchThread()
end)

RegisterNetEvent('m5rp:cl:round', function(data)
    if data.matchId and data.matchId ~= State.matchId then return end

    if data.phase == 'spawn' or data.phase == 'respawn' then
        nui({ action = 'scoreboard', show = false })   -- the break is over
        State.alive = true
        State.reportedDeath = false
        clearBoundary()
        State.spawnProtectUntil = ms() + ((data.protection or 0) * 1000)
        stopSpectate()

        if data.spawn then teleport(data.spawn, data.freeze == true) end
        -- settle: the teleport above resurrected the ped, and the engine is
        -- still finishing with it for the next few frames
        if data.loadout then applyLoadout(data.loadout, true) end

        local ped = playerPed()
        State.lastHealth = GetEntityHealth(ped)
        State.lastArmor  = GetPedArmour(ped)

        nui({ action = 'round', data = { phase = data.phase, protection = data.protection } })

    elseif data.phase == 'countdown' then
        State.roundLive = false
        State.frozen    = true
        FreezeEntityPosition(playerPed(), true)
        screenEffect(Config.Effects.countdownEffect, 1200)
        nui({ action = 'round', data = {
            phase = 'countdown', round = data.round,
            seconds = data.seconds, scores = data.scores
        } })

    elseif data.phase == 'live' then
        State.roundLive = true
        State.frozen    = false
        FreezeEntityPosition(playerPed(), false)
        -- release the freeze restrictions
        DisablePlayerFiring(PlayerId(), false)
        SetPlayerCanDoDriveBy(PlayerId(), true)
        nui({ action = 'round', data = { phase = 'live', round = data.round, time = data.time } })
        hook('onRoundStart', { matchId = State.matchId, round = data.round, time = data.time })

    elseif data.phase == 'loadout' then
        -- gun game promotion
        if data.loadout then applyLoadout(data.loadout) end
        nui({ action = 'event', data = {
            type = 'KILLSTREAK', extra = data.gunLevel
        } })

    elseif data.phase == 'rearm' then
        -- the answer to the client having asked for its loadout back; the
        -- server decided what is in it, the same as on any spawn
        if data.loadout then
            applyLoadout(data.loadout, true)
            nui({ action = 'toast', kind = 'ok',
                  title = _L('LOADOUT'), message = _L('Your weapons were given back.') })
        end

    elseif data.phase == 'revive' then
        -- headshot only rooms: body damage never kills
        local ped = playerPed()
        local maxH = (data.health or 100) + 100
        SetEntityHealth(ped, maxH)
        State.lastHealth = maxH

    elseif data.phase == 'end' then
        State.roundLive = false
        -- the boundary check stops running between rounds, so its tint has to
        -- be dropped here or it stays up through the whole break
        clearBoundary()
        nui({ action = 'round', data = {
            phase = 'end', round = data.round, winner = data.winner,
            reason = data.reason, scores = data.scores,
            myTeam = State.team, scoreboard = data.scoreboard
        } })

        local sbCfg = (Config.HUD and Config.HUD.scoreboard) or {}
        if sbCfg.enabled ~= false and sbCfg.autoOnRoundEnd then
            nui({ action = 'scoreboard', show = true })
        end

        hook('onRoundEnd', {
            matchId = State.matchId, round = data.round, winner = data.winner,
            reason = data.reason, scores = data.scores
        })
    end
end)

RegisterNetEvent('m5rp:cl:hud', function(data)
    State.matchState = data.state or State.matchState
    State.alive      = data.alive == true

    -- keep a serverId -> team/name map so nameplates and the kill feed colour
    -- correctly without any extra traffic
    if data.scoreboard then
        State.teamOfServerId = {}
        State.nameOfServerId = {}
        for i = 1, #data.scoreboard do
            local row = data.scoreboard[i]
            if row.serverId then
                State.teamOfServerId[row.serverId] = row.team
                State.nameOfServerId[row.serverId] = row.name
            end
        end
    end

    nui({ action = 'hud', data = data })
end)

RegisterNetEvent('m5rp:cl:killfeed', function(data)
    nui({ action = 'killfeed', data = data })
end)

RegisterNetEvent('m5rp:cl:event', function(data)
    nui({ action = 'event', data = data })
end)

RegisterNetEvent('m5rp:cl:end', function(data)
    State.roundLive = false
    State.matchState = 'MATCH_END'

    -- The match is over, so the match HUD goes with it. Leaving it up put the
    -- round timer, the scores and the ammo counter behind the result panel.
    nui({ action = 'hudVisible', value = false })
    nui({ action = 'scoreboard', show = false })

    local rc = (Config.HUD and Config.HUD.result) or {}
    nui({ action = 'matchEnd', data = data,
          dismissHint = rc.enabled ~= false and (rc.display or 'BACKSPACE') or nil,
          autoClose   = rc.autoClose,
          -- the promotion screen waits behind the result and is closed by the
          -- same key, so it gets the same hint
          rankCfg     = (Config.HUD and Config.HUD.rankChange) or {} })
    hook('onMatchEnd', {
        matchId = data.matchId, result = data.result,
        scores = data.scores, rp = data.rp
    })

    -- The result is an overlay, not a menu: no NUI focus, no cursor. That also
    -- means the panel cannot be clicked away, so the dismiss key below is the
    -- way out — taking focus here would lock the mouse the instant a match
    -- ends, which is the worst possible moment for it.
end)

--- Hold-free dismiss for the result panel. ESC cannot be bound in FiveM (the
--- pause menu owns it), so the default is BACKSPACE; the player can rebind it
--- under Settings > Key Bindings > FiveM.
CreateThread(function()
    local rc = (Config.HUD and Config.HUD.result) or {}
    if rc.enabled == false then return end

    RegisterCommand('m5rp_closeresult', function()
        nui({ action = 'closeResult' })
    end, false)

    RegisterKeyMapping('m5rp_closeresult',
        rc.label or 'M5 Ranked PvP — Close Result', 'keyboard', rc.key or 'BACK')
end)

RegisterNetEvent('m5rp:cl:cleanup', function(data)
    if data and data.matchId and data.matchId ~= State.matchId then return end

    State.inMatch    = false
    State.matchId    = nil
    State.matchState = 'NONE'
    State.roundLive  = false
    State.alive      = false
    State.team       = 0
    State.map        = nil
    State.loadout    = nil
    State.settings   = {}
    State.roster     = {}
    clearBoundary()

    hook('onMatchLeave', {
        matchId = data and data.matchId or State.matchId,
        reason = (data and data.reason) or 'END'
    })

    stopSpectate()
    clearBots()
    clearScreenEffects()

    local ped = playerPed()
    FreezeEntityPosition(ped, false)
    State.frozen = false
    RemoveAllPedWeapons(ped, true)
    SetEntityInvincible(ped, false)
    SetPedCanRagdoll(ped, true)
    SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
    SetPlayerHealthRechargeMultiplier(PlayerId(), 1.0)
    SetEntityMaxHealth(ped, 200)
    SetEntityHealth(ped, 200)
    SetPedArmour(ped, 0)
    ClearPedBloodDamage(ped)

    DisplayRadar(true)
    stopScreenEffect(Config.Effects.outOfBoundsEffect)
    stopScreenEffect(Config.Effects.deathEffect)
    ClearTimecycleModifier()

    TriggerEvent(Config.HUD.externalHudEvent, true)

    nui({ action = 'hudVisible', value = false })
    nui({ action = 'matchCleanup' })

    -- Back to where they came from. Withdrawing is its own way out, so it has
    -- its own switch: a server can send everyone to a lobby at the end of a
    -- match and still leave a player who walked out where they stood.
    local reason = (data and data.reason) or 'END'
    returnHome(reason == 'LEAVE' and 'afterSurrender' or 'afterMatch')

    -- refresh the profile so the hub shows the new RP straight away
    TriggerServerEvent('m5rp:sv:boot')
end)

-- ============================================================================
-- 07. COMBAT DETECTION
-- ============================================================================
-- Reports only. The server decides who died.

local HEAD_BONES = {}
for _, bone in ipairs({ 31086, 39317, 12844, 20178, 21550 }) do HEAD_BONES[bone] = true end

local SHOT_REPORT_INTERVAL = 220
local lastShotReport = 0

--- Attacker side raycast. It runs on the frame the weapon fires and tells the
--- server which player was under the crosshair and whether the impact landed on
--- the head. The server keeps it only as corroboration — a hit is still only
--- counted once the victim confirms taking damage.
local function traceShot(ped)
    ped = ped or playerPed()
    local camCoords = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local cosRx = math.abs(math.cos(rx))
    local dir = vector3(-math.sin(rz) * cosRx, math.cos(rz) * cosRx, math.sin(rx))

    local dest = camCoords + (dir * 1200.0)
    local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z,
                                  dest.x, dest.y, dest.z, 12, ped, 4)
    local _, hit, endCoords, _, entity = GetShapeTestResult(ray)

    if hit ~= 1 or not isPlayerPed(entity) or entity == ped then return nil end

    local targetSrc = serverIdOfPed(entity)
    if not targetSrc then return nil end

    local headCoords = GetPedBoneCoords(entity, 31086, 0.0, 0.0, 0.0)
    local headHit = #(endCoords - headCoords) <= 0.24

    return {
        target = targetSrc,
        head   = headHit,
        dist   = #(GetEntityCoords(ped) - GetEntityCoords(entity))
    }
end

local function reportShot(force, ped)
    local t = ms()
    if not force and (t - lastShotReport) < SHOT_REPORT_INTERVAL then return end
    lastShotReport = t
    State.lastShotAt = t

    ped = ped or playerPed()
    local trace = traceShot(ped)
    TriggerServerEvent('m5rp:sv:combat', 'shot', {
        weapon = currentWeaponName(ped),
        target = trace and trace.target or nil,
        head   = trace and trace.head or false,
        dist   = trace and trace.dist or 0.0
    })

    if trace and Config.Effects.hitmarker then
        State.hitmarkerUntil = t + Config.Effects.hitmarkerTime
        State.hitmarkerHead  = trace.head
        nui({ action = 'hitmarker', head = trace.head })
    end
end

--- Damage taken on the victim's own machine, where the numbers are exact.
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    if not State.inMatch or not State.roundLive then return end

    local ped      = playerPed()
    local victim   = args[1]
    local attacker = args[2]

    if victim ~= ped then return end
    if not isPlayerPed(attacker) or attacker == ped then return end

    local attackerSrc = serverIdOfPed(attacker)
    if not attackerSrc then return end

    -- spawn protection is enforced by the server too, this only avoids traffic
    if State.spawnProtectUntil > ms() then return end

    local weaponHash = args[7] or args[5]
    local weapon = weaponNameFromHash(weaponHash)
    if not weapon then
        local ok, h = GetCurrentPedWeapon(attacker, true)
        if ok then weapon = weaponNameFromHash(h) end
    end

    State.lastDamageBy = attackerSrc
    State.lastDamageAt = ms()

    local hasBone, bone = GetPedLastDamageBone(ped)
    local isHead = hasBone and HEAD_BONES[bone] == true

    if isHead and Config.Headshot.enabled and Config.Headshot.oneShotKill
       and State.settings.headshotOneShot ~= false then
        -- Distance is deliberately not part of the decision. A real head hit is
        -- lethal at 10 m and at 500 m alike; the server does the final check.
        TriggerServerEvent('m5rp:sv:combat', 'hs', {
            attacker = attackerSrc,
            weapon   = weapon,
            bone     = bone,
            dist     = #(GetEntityCoords(ped) - GetEntityCoords(attacker))
        })
    end
end)

--- Per frame combat scan. Only ever runs inside a live round while alive.
local function combatScan(ped)
    ped = ped or playerPed()

    -- ---- shooting ------------------------------------------------------
    if IsPedShooting(ped) then
        reportShot(false, ped)
    end

    -- ---- damage taken --------------------------------------------------
    local health = GetEntityHealth(ped)
    local armor  = GetPedArmour(ped)
    local lost   = (State.lastHealth - health) + (State.lastArmor - armor)

    if lost > 0 then
        if State.lastDamageBy and (ms() - State.lastDamageAt) <= 1500 then
            TriggerServerEvent('m5rp:sv:combat', 'dmg', {
                attacker = State.lastDamageBy,
                amount   = math.floor(lost),
                weapon   = nil
            })
        end
        nui({ action = 'damaged', amount = math.floor(lost) })
    end

    -- HEADSHOT ONLY: body damage is reported for statistics, then undone. Only
    -- a validated head hit can kill, and that kill comes from the server.
    if State.settings.headshotOnly and State.alive then
        local maxH = (State.settings.health or 100) + 100
        if health < maxH then
            SetEntityHealth(ped, maxH)
            health = maxH
        end
        if armor < (State.settings.armor or 0) then
            SetPedArmour(ped, State.settings.armor or 0)
            armor = State.settings.armor or 0
        end
    end

    State.lastHealth = health
    State.lastArmor  = armor

    -- ---- death ---------------------------------------------------------
    if (IsEntityDead(ped) or health <= 0) and not State.reportedDeath then
        State.reportedDeath = true
        State.alive = false

        local killer = nil
        if State.lastDamageBy and (ms() - State.lastDamageAt) <= 5000 then
            killer = State.lastDamageBy
        end

        TriggerServerEvent('m5rp:sv:combat', 'death', {
            killer = killer,
            weapon = currentWeaponName(ped)
        })
    end
end

--- The server tells the client to die. This is what makes a headshot lethal
--- regardless of the damage the engine actually applied.
RegisterNetEvent('m5rp:cl:die', function(data)
    if data.matchId and data.matchId ~= State.matchId then return end

    State.alive = false
    State.reportedDeath = true

    local ped = playerPed()
    if not IsEntityDead(ped) then
        SetEntityHealth(ped, 0)
    end

    screenEffect(Config.Effects.deathEffect, 1500)

    nui({ action = 'death', data = {
        killer = data.killer, weapon = data.weapon, headshot = data.headshot,
        respawn = data.respawn, respawnTime = data.respawnTime
    } })

    hook('onDeath', {
        matchId = State.matchId, killer = data.killer, weapon = data.weapon,
        headshot = data.headshot == true, respawn = data.respawn == true
    })

    if not data.respawn and Config.Spectator.enabled then
        Citizen.SetTimeout((data.spectateDelay or 2) * 1000, function()
            if not State.alive and State.inMatch then
                TriggerServerEvent('m5rp:sv:action', 'spectateTeam', {})
            end
        end)
    end
end)

-- ============================================================================
-- 08. BOUNDARY
-- ============================================================================

--- The out-of-bounds panel has one owner. Every path that hides it goes
--- through here, and the state is tracked so a repeated call costs nothing.
local boundaryShown = false

local boundarySeconds, boundaryDistance = -1, -1

showBoundary = function(seconds, distance)
    -- The panel shows whole seconds and whole metres, and this is called on
    -- every frame the player is outside. Only a message that would change
    -- something on screen is worth sending.
    if boundaryShown and seconds == boundarySeconds and distance == boundaryDistance then
        return
    end
    boundaryShown = true
    boundarySeconds, boundaryDistance = seconds, distance
    nui({ action = 'boundary', active = true, seconds = seconds, distance = distance })
end

hideBoundary = function()
    if not boundaryShown then return end
    boundaryShown = false
    boundarySeconds, boundaryDistance = -1, -1
    nui({ action = 'boundary', active = false })
    stopScreenEffect(Config.Effects.outOfBoundsEffect)
end

--- Resets the boundary state completely: used by anything that moves the
--- player itself, rather than leaving the flag and the panel to disagree.
clearBoundary = function()
    State.outside = false
    hideBoundary()
end

local function boundaryCheck(pos)
    if not State.map or not State.map.center or not State.map.radius then return end
    -- Nothing to measure until the player has actually been put in the arena.
    -- Between the match setup and the spawn teleport they are still standing
    -- wherever they were, hundreds of metres away, and warning them about a
    -- zone they have not been placed in yet is what started this.
    if not State.alive then clearBoundary() return end

    pos = pos or GetEntityCoords(playerPed())
    local c = State.map.center

    -- A combat zone is a cylinder, not a sphere. Measuring in three dimensions
    -- meant every metre climbed was a metre stolen from the radius, so on an
    -- arena with ramps, roofs or an upper deck a player standing in the middle
    -- of the map could read as being outside it. Height is checked on its own,
    -- with a limit generous enough to ignore normal arena geometry and tight
    -- enough to still catch someone who has left the map entirely.
    local dx, dy = pos.x - c.x, pos.y - c.y
    local flat   = math_sqrt(dx * dx + dy * dy)
    local climb  = math_abs(pos.z - c.z)
    local vLimit = State.map.height or Config.Boundary.verticalLimit or 200.0

    local overFlat  = flat  - State.map.radius
    local overClimb = climb - vLimit
    local dist = math_max(overFlat, overClimb) + State.map.radius

    if overFlat > 0 or overClimb > 0 then
        if not State.outside then
            State.outside = true
            State.outsideUntil = ms() + ((State.settings.boundaryWarning or Config.Boundary.countdownFrom) * 1000)
            if Config.Boundary.tintScreen then
                screenEffect(Config.Effects.outOfBoundsEffect)
            end
        end

        local left = math_max(0, math.ceil((State.outsideUntil - ms()) / 1000))
        showBoundary(left, math_floor(dist - State.map.radius))

        if ms() >= State.outsideUntil then
            State.outside = false
            hideBoundary()
            TriggerServerEvent('m5rp:sv:combat', 'oob')
        end
    else
        -- Unconditional, not `elseif State.outside`. The warning used to be
        -- taken down only when this function was the one that put it up, so a
        -- spawn clearing State.outside behind its back left the panel on
        -- screen with nothing able to remove it — which is exactly what a
        -- player saw at the start of a match, warned about a distance measured
        -- before the spawn teleport had landed. Being inside is now enough.
        State.outside = false
        hideBoundary()
    end
end

--- Prints where you are relative to the current map's zone.
---
--- The imported arenas came without a boundary size, so every radius in the
--- config is a guess. Rather than leaving it at that: stand at the edge of the
--- playable area and run this. It reports the horizontal distance from the
--- centre, so the radius that arena actually wants is that number plus a
--- little headroom.
RegisterCommand('pvpzone', function()
    local m = State.map
    if not m or not m.center or not m.radius then
        print('[M5RP] not in a match or training session with a map')
        nui({ action = 'toast', kind = 'warning', message = _L('No live match.'),
              title = _L('MATCH') })
        return
    end

    local pos = GetEntityCoords(playerPed())
    local dx, dy = pos.x - m.center.x, pos.y - m.center.y
    local flat  = math.sqrt(dx * dx + dy * dy)
    local climb = pos.z - m.center.z
    local vLimit = m.height or Config.Boundary.verticalLimit or 200.0

    local line = ('%s | flat %.1fm of %.0fm | height %+.1fm of %.0fm | %s')
        :format(m.name or m.id or '?', flat, m.radius, climb, vLimit,
                (flat > m.radius or math.abs(climb) > vLimit) and 'OUTSIDE' or 'inside')
    print('[M5RP] ' .. line)
    print(('[M5RP] centre %.3f %.3f %.3f — you %.3f %.3f %.3f')
        :format(m.center.x, m.center.y, m.center.z, pos.x, pos.y, pos.z))
    nui({ action = 'toast', kind = 'info', message = line, title = 'ZONE' })
end, false)

-- ============================================================================
-- 09. MATCH THREAD
-- ============================================================================

local function pushActivity(ped, pos)
    -- The AFK detector is fed from real inputs: movement, camera, shooting and
    -- interaction. Nothing is sent while nothing happens.
    ped = ped or playerPed()
    pos = pos or GetEntityCoords(ped)
    local heading = GetGameplayCamRot(2).z

    local movedOk = #(pos - State.lastPos) >= 1.5
    local camOk   = math_abs(((heading - State.lastCamHeading + 180) % 360) - 180) >= 4.0
    -- short circuit order matters here: three of these are natives, and the
    -- first one that answers yes ends the question
    local acted   = movedOk or camOk
                    or IsPedShooting(ped) or IsControlPressed(0, 24)
                    or IsControlPressed(0, 25) or IsControlPressed(0, 38)

    if acted then
        State.lastPos = pos
        State.lastCamHeading = heading
        local t = ms()
        if (t - State.lastActivityPush) > 3000 then
            State.lastActivityPush = t
            TriggerServerEvent('m5rp:sv:activity')
        end
    end
end

-- read once: the config does not change while the resource runs, and this is
-- called on every frame of every round
local NO_WEAPON_WHEEL = Config.Display.disableWeaponWheel == true

local function applyMatchRestrictions()
    if NO_WEAPON_WHEEL then
        DisableControlAction(0, 37, true)   -- weapon wheel
        DisableControlAction(0, 157, true)  -- weapon slots 1..
        DisableControlAction(0, 158, true)
        DisableControlAction(0, 160, true)
        DisableControlAction(0, 164, true)
        DisableControlAction(0, 165, true)
    end
    if not State.settings.jump then
        DisableControlAction(0, 22, true)   -- jump
    end
    if not State.settings.vehicles then
        DisableControlAction(0, 23, true)   -- enter vehicle
        DisableControlAction(0, 75, true)   -- exit vehicle
    end
    -- no phone / no radio inside a match
    DisableControlAction(0, 288, true)
    DisableControlAction(0, 289, true)
    DisableControlAction(0, 170, true)
    DisableControlAction(0, 167, true)
end

local function drawTeammateTags(myPed, myPos)
    if not Config.Display.teammateNameplates or State.ffa then return end

    -- Nothing to draw until the server has sent a scoreboard to resolve teams
    -- from, and this runs every frame — so it leaves before touching a native.
    local teams = State.teamOfServerId
    if not teams then return end

    local myTeam = State.team
    local names  = State.nameOfServerId
    local range  = Config.Display.nameplateDistance
    myPed = myPed or playerPed()
    myPos = myPos or GetEntityCoords(myPed)

    for _, player in ipairs(GetActivePlayers()) do
        -- The team is a table read; the ped, its coordinates and the distance
        -- are three natives and a vector. Asking the cheap question first
        -- skips all of that for everyone who is not on your side, which on a
        -- busy server is nearly everyone.
        local sid = GetPlayerServerId(player)
        if teams[sid] == myTeam then
            local ped = GetPlayerPed(player)
            if ped ~= myPed and DoesEntityExist(ped) then
                local pos = GetEntityCoords(ped)
                if #(myPos - pos) <= range then
                    SetDrawOrigin(pos.x, pos.y, pos.z + 1.05, 0)
                    SetTextFont(4)
                    SetTextScale(0.30, 0.30)
                    SetTextColour(46, 217, 195, 200)
                    SetTextCentre(true)
                    SetTextOutline()
                    BeginTextCommandDisplayText('STRING')
                    AddTextComponentSubstringPlayerName(names and names[sid] or '')
                    EndTextCommandDisplayText(0.0, 0.0)
                    ClearDrawOrigin()
                end
            end
        end
    end
end

startMatchThread = function()
    if matchThreadRunning then return end
    matchThreadRunning = true

    Citizen.CreateThread(function()
        local hudAcc = 0
        -- the last card the interface was sent, so an unchanged one is not
        -- sent again. It lives with the thread, so a new match always pushes.
        local lastHud = {}

        while State.inMatch do
            local liveCombat = State.roundLive and State.alive and not State.spectating
            -- The freeze also has to run per frame: DisablePlayerFiring and
            -- DisableControlAction only hold for the frame they are called on,
            -- so at 200ms the trigger would work between checks.
            local wait = (liveCombat or State.frozen) and 0 or 200

            if liveCombat then
                -- One PlayerPedId for the whole frame. Every helper below used
                -- to ask for it again — a dozen native calls a frame, and more
                -- inside the nameplate loop — for a value that cannot change
                -- between them.
                local ped = playerPed()
                -- and one GetEntityCoords: the zone check, the AFK detector
                -- and the nameplates each asked for the same position
                local pos = GetEntityCoords(ped)

                combatScan(ped)
                applyMatchRestrictions()
                boundaryCheck(pos)
                rearmGuard(ped)
                pushActivity(ped, pos)

                -- spawn protection shimmer
                if State.spawnProtectUntil > ms() then
                    SetEntityInvincible(ped, true)
                    SetEntityAlpha(ped, Config.Effects.spawnProtectionAlpha, false)
                else
                    if State.spawnProtectUntil ~= 0 then
                        State.spawnProtectUntil = 0
                        SetEntityInvincible(ped, false)
                        ResetEntityAlpha(ped)
                    end
                end

                drawTeammateTags(ped, pos)

                hudAcc = hudAcc + 16
                if hudAcc >= Config.Timing.hudTick then
                    hudAcc = 0
                    local ok, weapon = GetCurrentPedWeapon(ped, true)
                    local ammo = ok and GetAmmoInPedWeapon(ped, weapon) or 0
                    local clip, clipMax = 0, 0
                    if ok then
                        local has, clipAmmo = GetAmmoInClip(ped, weapon)
                        clip = has and clipAmmo or 0
                        -- the magazine bar needs the capacity, not just the count
                        clipMax = GetMaxAmmoInClip(ped, weapon, true) or 0
                    end
                    local health = math.max(0, GetEntityHealth(ped) - 100)
                    local armor  = GetPedArmour(ped)
                    local name   = (ok and WEAPON_NAME_BY_HASH[weapon]) or 'WEAPON_UNARMED'

                    -- A player who is standing still with a full magazine
                    -- sends the same six numbers five times a second. Each
                    -- one is a JSON encode, a message into CEF and a full
                    -- pass over the health, armour and magazine bars — for a
                    -- card that is already showing exactly this. Sending it
                    -- only when something moved costs one comparison.
                    if health ~= lastHud.health or armor ~= lastHud.armor
                       or clip ~= lastHud.clip or ammo ~= lastHud.ammo
                       or clipMax ~= lastHud.clipMax or name ~= lastHud.weapon then
                        lastHud.health, lastHud.armor = health, armor
                        lastHud.clip, lastHud.ammo, lastHud.clipMax = clip, ammo, clipMax
                        lastHud.weapon = name
                        nui({ action = 'localHud', data = {
                            health = health, armor = armor,
                            weapon = name, weaponHash = ok and weapon or nil,
                            ammo   = ammo, clip = clip, clipMax = clipMax
                        } })
                    end
                end
            else
                -- non combat states: keep the restrictions but stay cheap
                if State.frozen then
                    local ped = playerPed()
                    FreezeEntityPosition(ped, true)
                    -- the countdown is part of the spawn, and a ped stripped
                    -- during it used to stay stripped until the round started
                    rearmGuard(ped)

                    -- No shooting before the round goes live. The server
                    -- already refuses damage while the match is not LIVE, so
                    -- this is the half that stops the weapon firing at all —
                    -- no wasted magazine, no shot into a frozen opponent.
                    DisablePlayerFiring(PlayerId(), true)
                    SetPlayerCanDoDriveBy(PlayerId(), false)
                    DisableControlAction(0, 24,  true)   -- attack
                    DisableControlAction(0, 25,  true)   -- aim
                    DisableControlAction(0, 47,  true)   -- throw / detonate
                    DisableControlAction(0, 58,  true)   -- throw grenade
                    DisableControlAction(0, 140, true)   -- melee light
                    DisableControlAction(0, 141, true)   -- melee heavy
                    DisableControlAction(0, 142, true)   -- melee alternate
                    DisableControlAction(0, 257, true)   -- attack 2
                    DisableControlAction(0, 263, true)   -- melee attack 1
                    DisableControlAction(0, 264, true)   -- melee attack 2
                end
                if State.inMatch and not State.alive and not State.spectating then
                    boundaryCheck()
                end
            end

            Citizen.Wait(wait)
        end

        matchThreadRunning = false
    end)
end

-- ============================================================================
-- 10. SPECTATOR
-- ============================================================================

local function spectateTargetPed()
    local entry = State.spectateTargets[State.spectateIndex]
    if not entry then return nil end
    local player = GetPlayerFromServerId(entry.serverId)
    if player == -1 then return nil end
    local ped = GetPlayerPed(player)
    if not DoesEntityExist(ped) then return nil end
    return ped, entry
end

local function spectateNext(step)
    if #State.spectateTargets == 0 then return end
    State.spectateIndex = State.spectateIndex + step
    if State.spectateIndex > #State.spectateTargets then State.spectateIndex = 1 end
    if State.spectateIndex < 1 then State.spectateIndex = #State.spectateTargets end

    local ped, entry = spectateTargetPed()
    if ped then
        NetworkSetInSpectatorMode(true, ped)
        nui({ action = 'spectate', data = {
            active = true, name = entry.name, team = entry.team,
            index = State.spectateIndex, total = #State.spectateTargets
        } })
    end
end

local function startSpectateThread()
    if spectateThreadRunning then return end
    spectateThreadRunning = true

    Citizen.CreateThread(function()
        while State.spectating do
            local keys = Config.Spectator.keys

            if IsControlJustPressed(0, keys.next) then spectateNext(1) end
            if IsControlJustPressed(0, keys.prev) then spectateNext(-1) end
            if IsControlJustPressed(0, keys.exit) then
                TriggerServerEvent('m5rp:sv:admin', 'stopSpectate', {})
                stopSpectate()
                break
            end

            -- the spectated player may have died or left
            local ped = spectateTargetPed()
            if not ped then spectateNext(1) end

            -- block every gameplay control while spectating
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true)

            Citizen.Wait(0)
        end
        spectateThreadRunning = false
    end)
end

stopSpectate = function()
    if not State.spectating then return end
    State.spectating = false
    State.spectateTargets = {}
    State.spectateFree = false

    NetworkSetInSpectatorMode(false, playerPed())

    if State.spectateCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(State.spectateCam, true)
        State.spectateCam = nil
    end

    nui({ action = 'spectate', data = { active = false } })
end

RegisterNetEvent('m5rp:cl:spectate', function(data)
    if not data or data.enable == false then
        stopSpectate()
        return
    end
    if not Config.Spectator.enabled then return end

    State.spectateTargets = data.targets or {}
    State.spectateIndex   = 1

    if #State.spectateTargets == 0 then
        -- nobody left to watch: sit on a static overview camera
        if data.map and data.map.center then
            local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
            SetCamCoord(cam, data.map.center.x, data.map.center.y, data.map.center.z + 60.0)
            SetCamRot(cam, -70.0, 0.0, 0.0, 2)
            SetCamActive(cam, true)
            RenderScriptCams(true, true, 600, true, true)
            State.spectateCam = cam
            State.spectating  = true
            nui({ action = 'spectate', data = { active = true, name = '—', overview = true } })
        end
        return
    end

    State.spectating = true
    local ped, entry = spectateTargetPed()
    if ped then
        NetworkSetInSpectatorMode(true, ped)
        nui({ action = 'spectate', data = {
            active = true, name = entry.name, team = entry.team,
            index = 1, total = #State.spectateTargets, staff = data.staff == true
        } })
    end
    startSpectateThread()
end)

-- ============================================================================
-- 11. TRAINING
-- ============================================================================

local function clearTrainingTargets()
    for i = 1, #State.trainingProps do
        local ped = State.trainingProps[i]
        if DoesEntityExist(ped) then DeletePed(ped) end
    end
    State.trainingProps = {}
end

local function spawnTrainingTargets(origin, count, spacing, headshotOnly)
    clearTrainingTargets()
    if count <= 0 then return end

    local model = GetHashKey('s_m_y_marine_01')
    RequestModel(model)
    local timeout = ms() + 5000
    while not HasModelLoaded(model) and ms() < timeout do Citizen.Wait(20) end
    if not HasModelLoaded(model) then return end

    local heading = origin.h or 0.0
    local rad = math.rad(heading)
    local forward = vector3(-math.sin(rad), math.cos(rad), 0.0)
    local right   = vector3(math.cos(rad), math.sin(rad), 0.0)

    for i = 1, count do
        local offset = ((i - 1) - (count - 1) / 2) * 2.2
        local dist   = spacing * (headshotOnly and (1 + (i % 4)) or 1)
        local pos = vector3(origin.x, origin.y, origin.z)
                  + (forward * (10.0 + dist))
                  + (right * offset)

        local ped = CreatePed(4, model, pos.x, pos.y, pos.z, heading + 180.0, false, false)
        SetEntityInvincible(ped, false)
        SetPedCanRagdoll(ped, false)
        FreezeEntityPosition(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedSuffersCriticalHits(ped, true)
        SetPedDiesWhenInjured(ped, true)
        SetEntityAsMissionEntity(ped, true, true)
        State.trainingProps[#State.trainingProps + 1] = ped
    end

    SetModelAsNoLongerNeeded(model)
end

RegisterNetEvent('m5rp:cl:training', function(data)
    if not data or data.enable == false then
        local wasTraining = State.training
        State.training = false
        clearTrainingTargets()
        if wasTraining then hook('onTrainingEnd', {}) end
        local ped = playerPed()
        RemoveAllPedWeapons(ped, true)
        SetEntityMaxHealth(ped, 200)
        SetEntityHealth(ped, 200)
        SetPedArmour(ped, 0)
        DisplayRadar(true)
        nui({ action = 'training', data = { active = false } })
        nui({ action = 'hudVisible', value = false })
        if wasTraining then returnHome('afterTraining') end
        return
    end

    -- while still standing in the world, before the range takes over
    rememberPoint()

    State.training = true
    closeMenu()
    hook('onTrainingStart', { kind = data.kind, label = data.label })

    if data.spawn then teleport(data.spawn, false) end
    if data.loadout then applyLoadout(data.loadout, true) end

    spawnTrainingTargets(data.spawn, data.targets or 0, data.spacing or 8.0,
                         data.kind == 'headshot')

    local exitCfg = (Config.Training and Config.Training.exit) or {}
    nui({ action = 'training', data = {
        active = true, label = data.label, kind = data.kind,
        targets = data.targets, time = data.time,
        exit = (exitCfg.enabled and exitCfg.hint and exitCfg.hint.enabled) and {
            key  = (exitCfg.keybind and exitCfg.keybind.display) or 'BACKSPACE',
            text = (exitCfg.hint and exitCfg.hint.text) or 'EXIT TRAINING',
            command = (exitCfg.command and exitCfg.command.enabled)
                      and ('/' .. (exitCfg.command.name or 'exittraining')) or nil
        } or nil
    } })

    -- lightweight training loop: respawn targets, report nothing to the server
    Citizen.CreateThread(function()
        local hits, headshots, shots = 0, 0, 0
        local startedAt = ms()

        while State.training do
            local ped = playerPed()

            for i = 1, #State.trainingProps do
                local target = State.trainingProps[i]
                if DoesEntityExist(target) and IsEntityDead(target) then
                    hits = hits + 1
                    local hasBone, bone = GetPedLastDamageBone(target)
                    if hasBone and HEAD_BONES[bone] then headshots = headshots + 1 end

                    local pos = GetEntityCoords(target)
                    local heading = GetEntityHeading(target)
                    DeletePed(target)

                    local model = GetHashKey('s_m_y_marine_01')
                    RequestModel(model)
                    local timeout = ms() + 3000
                    while not HasModelLoaded(model) and ms() < timeout do Citizen.Wait(10) end

                    local fresh = CreatePed(4, model, pos.x, pos.y, pos.z, heading, false, false)
                    SetEntityInvincible(fresh, false)
                    SetPedCanRagdoll(fresh, false)
                    FreezeEntityPosition(fresh, true)
                    SetBlockingOfNonTemporaryEvents(fresh, true)
                    SetPedSuffersCriticalHits(fresh, true)
                    SetPedDiesWhenInjured(fresh, true)
                    SetEntityAsMissionEntity(fresh, true, true)
                    State.trainingProps[i] = fresh

                    nui({ action = 'training', data = {
                        active = true, hits = hits, headshots = headshots,
                        accuracy = hits > 0 and math.floor((headshots / hits) * 100) or 0,
                        elapsed = math.floor((ms() - startedAt) / 1000)
                    } })
                end
            end

            if IsPedShooting(playerPed()) then shots = shots + 1 end
            Citizen.Wait(120)
        end

        clearTrainingTargets()
    end)
end)

-- ============================================================================
-- 11b. BOT MATCH  (staff practice)
-- ============================================================================
--
-- Only a client can create a ped and give it combat AI, so the bots live here.
-- Everything that counts — rounds, score, when a round starts and ends — stays
-- on the server; this file reports one thing back, that a bot went down, and
-- the server treats that as worthless outside a staff practice session.

clearBots = function()
    for i = 1, #State.bots do
        local ped = State.bots[i].ped
        if DoesEntityExist(ped) then DeletePed(ped) end
    end
    State.bots       = {}
    State.botsActive = false
    State.botsHeld   = false
end

--- Arms one ped: stats, weapon, accuracy and combat behaviour.
local function configureBot(ped, cfg, relationship)
    SetEntityInvincible(ped, false)
    SetPedCanRagdoll(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedSuffersCriticalHits(ped, true)
    SetPedDiesWhenInjured(ped, false)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetEntityAsMissionEntity(ped, true, true)

    SetEntityMaxHealth(ped, cfg.health or 200)
    SetEntityHealth(ped, cfg.health or 200)
    SetPedArmour(ped, cfg.armor or 0)

    GiveWeaponToPed(ped, GetHashKey(cfg.weapon or 'WEAPON_PISTOL'), 500, false, true)
    SetPedAccuracy(ped, cfg.accuracy or 30)
    SetPedShootRate(ped, math.floor((cfg.reaction or 0.6) * 100))
    SetPedCombatAbility(ped, 2)
    SetPedCombatRange(ped, 2)
    SetPedCombatMovement(ped, cfg.combatMovement or 2)
    SetPedAlertness(ped, cfg.alertness or 2)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)   -- always fight
    SetPedCombatAttributes(ped, 5,  true)   -- may use vehicles: off by task below
    SetPedCombatAttributes(ped, 0,  true)   -- use cover
    SetPedSeeingRange(ped, 200.0)
    SetPedHearingRange(ped, 200.0)
    SetPedRelationshipGroupHash(ped, relationship)
end

RegisterNetEvent('m5rp:cl:bots', function(data)
    if not data then return end

    if data.clear then
        clearBots()
        return
    end

    if data.release then
        -- the countdown is over: let them fight
        State.botsHeld = false
        local me = playerPed()
        for i = 1, #State.bots do
            local ped = State.bots[i].ped
            if DoesEntityExist(ped) and not IsEntityDead(ped) then
                FreezeEntityPosition(ped, false)
                TaskCombatPed(ped, me, 0, 16)
            end
        end
        return
    end

    if not data.spawn then return end

    clearBots()
    State.botMatchId  = data.matchId
    State.botHeadshot = data.headshotOneShot == true

    local model = GetHashKey(data.model or 's_m_y_marine_01')
    RequestModel(model)
    local timeout = ms() + 5000
    while not HasModelLoaded(model) and ms() < timeout do Citizen.Wait(20) end
    if not HasModelLoaded(model) then
        nui({ action = 'toast', kind = 'error',
              message = 'Could not load the bot model.', title = 'BOT MATCH' })
        return
    end

    -- a group of their own so they fight the player and not each other
    local group = GetHashKey('M5RP_BOTS')
    AddRelationshipGroup('M5RP_BOTS')
    SetRelationshipBetweenGroups(5, group, GetHashKey('PLAYER'))
    SetRelationshipBetweenGroups(5, GetHashKey('PLAYER'), group)
    SetRelationshipBetweenGroups(0, group, group)

    local spots = data.spots or {}
    for i = 1, #spots do
        local p = spots[i]
        local ped = CreatePed(4, model, p.x, p.y, p.z, p.h or 0.0, false, false)
        if DoesEntityExist(ped) then
            configureBot(ped, data.bot or {}, group)
            FreezeEntityPosition(ped, true)      -- held until the round goes live
            State.bots[#State.bots + 1] = { ped = ped, down = false }
        end
    end

    SetModelAsNoLongerNeeded(model)
    State.botsActive = #State.bots > 0
    State.botsHeld   = true

    if not State.botsActive then return end

    -- One watcher for the whole session. It only looks for a bot dying and
    -- tells the server; it never decides anything about the round.
    Citizen.CreateThread(function()
        while State.botsActive do
            local anyAlive = false

            for i = 1, #State.bots do
                local b = State.bots[i]
                if not b.down and DoesEntityExist(b.ped) then
                    if IsEntityDead(b.ped) or GetEntityHealth(b.ped) <= 0 then
                        b.down = true
                        local hasBone, bone = GetPedLastDamageBone(b.ped)
                        TriggerServerEvent('m5rp:sv:bot', 'down', {
                            headshot = (hasBone and HEAD_BONES[bone]) == true
                        })
                    else
                        anyAlive = true
                        -- one shot headshot applies to bots as well
                        if State.botHeadshot then
                            local hasBone, bone = GetPedLastDamageBone(b.ped)
                            if hasBone and HEAD_BONES[bone]
                               and HasEntityBeenDamagedByEntity(b.ped, playerPed(), true) then
                                ClearEntityLastDamageEntity(b.ped)
                                SetEntityHealth(b.ped, 0)
                            end
                        end
                        -- keep them engaged if they lost the target
                        if not State.botsHeld and not IsPedInCombat(b.ped, playerPed()) then
                            TaskCombatPed(b.ped, playerPed(), 0, 16)
                        end
                    end
                end
            end

            -- nothing left to watch until the next round spawns a new set
            if not anyAlive then State.botsActive = false end
            Citizen.Wait(150)
        end
    end)
end)

-- ============================================================================
-- 12. NOTIFICATIONS & MISC
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Scoreboard (hold to show)
--
-- A +/- command pair is the only way FiveM gives a "while held" binding, and
-- registering it means the player can rebind the key in the pause menu instead
-- of being stuck with TAB. It needs no NUI focus: the board is display only.
-- ---------------------------------------------------------------------------
do
    local sbCfg = (Config.HUD and Config.HUD.scoreboard) or {}
    if sbCfg.enabled ~= false then
        local function canShow()
            return State.inMatch and State.matchState ~= 'NONE'
        end

        -- Asking for the loadout back is not free, so a held key cannot ask
        -- twice a second. The server rate limits it as well.
        local nextAsk = 0

        RegisterCommand('+m5rp_scoreboard', function()
            if not canShow() then return end
            nui({ action = 'scoreboard', show = true })

            --- The same key also puts the weapon back.
            ---
            --- A respawn is sometimes overtaken by another resource applying
            --- its own inventory, and the player lands empty handed with no
            --- way out of it. The guard on the match thread catches that on
            --- its own, but only once a second and only while it is running,
            --- so this gives the player something to press rather than a wait
            --- to sit through. It asks the server, which decides what the
            --- loadout is; the client names no weapon and gets nothing it was
            --- not already meant to be holding.
            local t = ms()
            if t < nextAsk then return end
            if not State.alive or not State.loadout then return end
            if not holdingNothing() then return end
            nextAsk = t + 2000
            TriggerServerEvent('m5rp:sv:rearm')
        end, false)

        RegisterCommand('-m5rp_scoreboard', function()
            nui({ action = 'scoreboard', show = false })
        end, false)

        RegisterKeyMapping('+m5rp_scoreboard',
            sbCfg.label or 'M5 Ranked PvP — Scoreboard', 'keyboard', sbCfg.key or 'TAB')
    end
end

-- Wipe the screen clean the moment the resource starts. An effect left behind
-- by a crash, or by a build that predates the fix, survives a restart because
-- nothing was ever clearing it on the way in — only on the way out. This is
-- why restarting did not help.
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearScreenEffects()
    local ped = playerPed()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    NetworkSetInSpectatorMode(false, ped)
    SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
    SetPlayerHealthRechargeMultiplier(PlayerId(), 1.0)
    DisplayRadar(true)
end)

--- Safety net: whenever the player is idle — no match, no training, no menu,
--- not spectating — nothing of ours should be on screen. Checked on the slow
--- proximity tick, so it costs nothing.
idleVisualGuard = function()
    if State.inMatch or State.training or State.menuOpen or State.spectating then return end
    if next(activeEffects) ~= nil or blurOn then clearScreenEffects() end
end

-- ---------------------------------------------------------------------------
-- Exports — for other resources on this client. Read only.
-- ---------------------------------------------------------------------------
exports('isInMatch',   function() return State.inMatch end)
exports('isTraining',  function() return State.training end)
exports('getMatchInfo', function()
    if not State.inMatch then return nil end
    return {
        matchId = State.matchId, state = State.matchState, team = State.team,
        ffa = State.ffa, alive = State.alive, map = State.map
    }
end)

-- ---------------------------------------------------------------------------
-- Surrender — hold the key to leave the match
--
-- A +/- binding gives the hold; the ring on screen fills while the key is
-- down and the match is only left once it completes. Letting go at any point
-- cancels, so a stray tap costs nothing.
-- ---------------------------------------------------------------------------
do
    local sCfg = (Config.HUD and Config.HUD.surrender) or {}
    if sCfg.enabled ~= false then
        local holding, holdToken = false, 0

        local function canSurrender()
            if not State.inMatch or State.matchState == 'MATCH_END' then return false end
            if sCfg.blockDuringCountdown and not State.roundLive then return false end
            return true
        end

        local function stopHold()
            if not holding then return end
            holding = false
            holdToken = holdToken + 1
            nui({ action = 'surrender', data = { active = false } })
        end

        RegisterCommand('+m5rp_surrender', function()
            if holding or not canSurrender() then return end

            holding = true
            holdToken = holdToken + 1
            local token = holdToken
            local seconds = tonumber(sCfg.holdTime) or 5
            local until_ = ms() + seconds * 1000

            nui({ action = 'surrender', data = {
                active = true, seconds = seconds, key = sCfg.display or 'X'
            } })

            Citizen.CreateThread(function()
                while holding and holdToken == token do
                    if not canSurrender() then stopHold() return end

                    local left = until_ - ms()
                    if left <= 0 then
                        holding = false
                        nui({ action = 'surrender', data = { active = false } })
                        TriggerServerEvent('m5rp:sv:action', 'leaveMatch', {})
                        return
                    end

                    nui({ action = 'surrender', data = {
                        active = true, seconds = seconds,
                        key = sCfg.display or 'X',
                        progress = 1 - (left / (seconds * 1000))
                    } })
                    Citizen.Wait(60)
                end
            end)
        end, false)

        RegisterCommand('-m5rp_surrender', function() stopHold() end, false)

        RegisterKeyMapping('+m5rp_surrender',
            sCfg.label or 'M5 Ranked PvP — Surrender (hold)', 'keyboard', sCfg.key or 'X')
    end
end

-- Escape hatch. If a screen effect ever survives — a crash mid match, an old
-- build, another resource leaving one behind — this wipes the screen clean
-- without a reconnect.
RegisterCommand('pvpclear', function()
    clearScreenEffects()
    local ped = playerPed()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    DisplayRadar(true)
    State.frozen = false
    nui({ action = 'toast', kind = 'success',
          message = 'Screen effects cleared.', title = 'M5 PVP' })
end, false)

RegisterNetEvent('m5rp:cl:notify', function(data)
    -- The server sends the English line plus any values to fill in; the swap
    -- happens here because this is the side that knows the chosen language.
    local message = data.args and _Lnf(data.message, table.unpack(data.args))
                    or _Ln(data.message)
    nui({ action = 'toast', kind = data.kind or 'info',
          message = message, title = _Ln(data.title) })
end)

-- Close the hub with ESC / BACKSPACE without needing NUI focus tricks
RegisterNUICallback('escape', function(_, cb)
    closeMenu()
    cb('ok')
end)

-- Resource restart / player exit safety
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    setFocus(false)
    clearTrainingTargets()
    clearBots()
    clearScreenEffects()

    if State.spectateCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(State.spectateCam, true)
    end
    NetworkSetInSpectatorMode(false, playerPed())

    local ped = playerPed()
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    ResetEntityAlpha(ped)
    SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
    SetPlayerHealthRechargeMultiplier(PlayerId(), 1.0)
    DisplayRadar(true)
    ClearTimecycleModifier()
    stopScreenEffect(Config.Effects.outOfBoundsEffect)
    stopScreenEffect(Config.Effects.deathEffect)

    if blipHandle then RemoveBlip(blipHandle) end
end)

-- Ask the server for the profile once the player has spawned.
AddEventHandler('playerSpawned', function()
    Citizen.SetTimeout(4000, function()
        if not State.booted then TriggerServerEvent('m5rp:sv:boot') end
    end)
end)

Citizen.CreateThread(function()
    Citizen.Wait(6000)
    if not State.booted then TriggerServerEvent('m5rp:sv:boot') end
end)

