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
        12  Notifications & misc events
    ============================================================================
]]

-- ============================================================================
-- 01. STATE
-- ============================================================================

local L = Config.Text[Config.Language] or Config.Text.en

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

local function ms() return GetGameTimer() end

local function dbg(fmt, ...)
    if Config.Debug then print(('[M5RP] ' .. fmt):format(...)) end
end

local function playerPed() return PlayerPedId() end

local function weaponNameFromHash(hash)
    -- resolve the readable name from the whitelist so the server always gets a
    -- name it can validate instead of a raw hash
    for _, name in ipairs({
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
    }) do
        if GetHashKey(name) == hash then return name end
    end
    return nil
end

local function currentWeaponName()
    local ok, hash = GetCurrentPedWeapon(playerPed(), true)
    if not ok then return 'WEAPON_UNARMED' end
    return weaponNameFromHash(hash) or 'WEAPON_UNARMED'
end

local function serverIdOfPed(ped)
    local plr = NetworkGetPlayerIndexFromPed(ped)
    if plr == -1 or plr == nil then return nil end
    return GetPlayerServerId(plr)
end

local function isPlayerPed(ped)
    return ped and ped ~= 0 and DoesEntityExist(ped) and IsPedAPlayer(ped)
end

--- Applies a loadout handed down by the server.
local function applyLoadout(loadout)
    local ped = playerPed()
    RemoveAllPedWeapons(ped, true)
    if not loadout then return end

    SetEntityMaxHealth(ped, (loadout.health or 100) + 100)
    SetEntityHealth(ped, (loadout.health or 100) + 100)
    SetPedArmour(ped, loadout.armor or 0)

    if loadout.weapons then
        for i = 1, #loadout.weapons do
            local w = loadout.weapons[i]
            GiveWeaponToPed(ped, GetHashKey(w.name), w.ammo or 100, false, i == 1)
        end
    end

    State.lastHealth = GetEntityHealth(ped)
    State.lastArmor  = GetPedArmour(ped)
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

local function screenEffect(name, duration)
    if not Config.Effects.enabled or not name then return end
    if duration then
        StartScreenEffect(name, duration / 1000, false)
    else
        StartScreenEffect(name, 0, true)
    end
end

local function stopScreenEffect(name)
    if name then StopScreenEffect(name) end
end

-- ============================================================================
-- 03. NUI BRIDGE
-- ============================================================================

local function nui(payload)
    SendNUIMessage(payload)
end

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
        sounds = Config.Sounds,
        text   = L,
        language = Config.Language,
        defaults = Config.DefaultSettings,
        blur   = Config.UI.blurBackground
    })

    if Config.UI.blurBackground then
        TriggerScreenblurFadeIn(180)
    end
end

local function closeMenu()
    if not State.menuOpen then return end
    State.menuOpen = false
    setFocus(false)
    nui({ action = 'close' })
    TriggerScreenblurFadeOut(180)
end

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb('ok')
end)

RegisterNUICallback('queue', function(data, cb)
    TriggerServerEvent('m5rp:sv:queue', data.action, data.mode)
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

RegisterNUICallback('settings', function(data, cb)
    if data and data.settings then
        TriggerServerEvent('m5rp:sv:settings', data.settings)
        if data.settings.language and Config.Text[data.settings.language] then
            Config.Language = data.settings.language
            L = Config.Text[Config.Language]
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
    nui({ action = 'boot', data = payload })
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
            nui({ action = 'open', page = 'ranked', theme = Config.UI, sounds = Config.Sounds,
                  text = L, language = Config.Language, defaults = Config.DefaultSettings,
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
        nui({ action = 'open', page = 'ranked', theme = Config.UI, sounds = Config.Sounds,
              text = L, language = Config.Language, defaults = Config.DefaultSettings,
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
    if not cfg.enabled then return end

    createBlip()

    local T = Config.Timing
    local point = cfg.coords

    while true do
        local wait = T.idleFar

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
    State.inMatch    = true
    State.matchId    = data.matchId
    State.matchState = 'STARTING'
    State.team       = data.team or 1
    State.ffa        = data.ffa == true
    State.map        = data.map
    State.settings   = data.settings or {}
    State.alive      = false
    State.reportedDeath = false
    State.outside    = false

    State.roster = {}
    if data.roster then
        for i = 1, #data.roster do
            State.roster[data.roster[i].userId] = data.roster[i]
        end
    end

    closeMenu()

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

    startMatchThread()
end)

RegisterNetEvent('m5rp:cl:round', function(data)
    if data.matchId and data.matchId ~= State.matchId then return end

    if data.phase == 'spawn' or data.phase == 'respawn' then
        State.alive = true
        State.reportedDeath = false
        State.outside = false
        State.spawnProtectUntil = ms() + ((data.protection or 0) * 1000)
        stopSpectate()

        if data.spawn then teleport(data.spawn, data.freeze == true) end
        if data.loadout then applyLoadout(data.loadout) end

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
        nui({ action = 'round', data = { phase = 'live', round = data.round, time = data.time } })

    elseif data.phase == 'loadout' then
        -- gun game promotion
        if data.loadout then applyLoadout(data.loadout) end
        nui({ action = 'event', data = {
            type = 'KILLSTREAK', extra = data.gunLevel
        } })

    elseif data.phase == 'revive' then
        -- headshot only rooms: body damage never kills
        local ped = playerPed()
        local maxH = (data.health or 100) + 100
        SetEntityHealth(ped, maxH)
        State.lastHealth = maxH

    elseif data.phase == 'end' then
        State.roundLive = false
        nui({ action = 'round', data = {
            phase = 'end', round = data.round, winner = data.winner,
            reason = data.reason, scores = data.scores,
            myTeam = State.team, scoreboard = data.scoreboard
        } })
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

    nui({ action = 'matchEnd', data = data })

    if not State.menuOpen then
        State.menuOpen = true
        setFocus(true)
        nui({ action = 'open', page = 'matchEnd', theme = Config.UI, sounds = Config.Sounds,
              text = L, language = Config.Language, defaults = Config.DefaultSettings,
              silent = true })
    end
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
    State.settings   = {}
    State.roster     = {}
    State.outside    = false

    stopSpectate()

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
local function traceShot()
    local ped = playerPed()
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

local function reportShot(force)
    local t = ms()
    if not force and (t - lastShotReport) < SHOT_REPORT_INTERVAL then return end
    lastShotReport = t
    State.lastShotAt = t

    local trace = traceShot()
    TriggerServerEvent('m5rp:sv:combat', 'shot', {
        weapon = currentWeaponName(),
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
local function combatScan()
    local ped = playerPed()

    -- ---- shooting ------------------------------------------------------
    if IsPedShooting(ped) then
        reportShot(false)
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
            weapon = currentWeaponName()
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

local function boundaryCheck()
    if not State.map or not State.map.center or not State.map.radius then return end

    local pos = GetEntityCoords(playerPed())
    local c   = State.map.center
    local dist = #(pos - vector3(c.x, c.y, c.z))

    if dist > State.map.radius then
        if not State.outside then
            State.outside = true
            State.outsideUntil = ms() + ((State.settings.boundaryWarning or Config.Boundary.countdownFrom) * 1000)
            if Config.Boundary.tintScreen then
                screenEffect(Config.Effects.outOfBoundsEffect)
            end
        end

        local left = math.max(0, math.ceil((State.outsideUntil - ms()) / 1000))
        nui({ action = 'boundary', active = true, seconds = left,
              distance = math.floor(dist - State.map.radius) })

        if ms() >= State.outsideUntil then
            State.outside = false
            nui({ action = 'boundary', active = false })
            stopScreenEffect(Config.Effects.outOfBoundsEffect)
            TriggerServerEvent('m5rp:sv:combat', 'oob')
        end
    elseif State.outside then
        State.outside = false
        nui({ action = 'boundary', active = false })
        stopScreenEffect(Config.Effects.outOfBoundsEffect)
    end
end

-- ============================================================================
-- 09. MATCH THREAD
-- ============================================================================

local function pushActivity()
    -- The AFK detector is fed from real inputs: movement, camera, shooting and
    -- interaction. Nothing is sent while nothing happens.
    local ped = playerPed()
    local pos = GetEntityCoords(ped)
    local heading = GetGameplayCamRot(2).z

    local movedOk = #(pos - State.lastPos) >= 1.5
    local camOk   = math.abs(((heading - State.lastCamHeading + 180) % 360) - 180) >= 4.0
    local acted   = IsPedShooting(ped) or IsControlPressed(0, 24) or IsControlPressed(0, 25)
                    or IsControlPressed(0, 38)

    if movedOk or camOk or acted then
        State.lastPos = pos
        State.lastCamHeading = heading
        local t = ms()
        if (t - State.lastActivityPush) > 3000 then
            State.lastActivityPush = t
            TriggerServerEvent('m5rp:sv:activity')
        end
    end
end

local function applyMatchRestrictions()
    if Config.Display.disableWeaponWheel then
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

local function drawTeammateTags()
    if not Config.Display.teammateNameplates or State.ffa then return end

    local myPos = GetEntityCoords(playerPed())
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= playerPed() and DoesEntityExist(ped) then
            local sid = GetPlayerServerId(player)
            local pos = GetEntityCoords(ped)
            local dist = #(myPos - pos)
            if dist <= Config.Display.nameplateDistance then
                -- teams are resolved from the HUD scoreboard sent by the server
                if State.teamOfServerId and State.teamOfServerId[sid] == State.team then
                    local name = State.nameOfServerId and State.nameOfServerId[sid] or ''
                    SetDrawOrigin(pos.x, pos.y, pos.z + 1.05, 0)
                    SetTextFont(4)
                    SetTextScale(0.30, 0.30)
                    SetTextColour(46, 217, 195, 200)
                    SetTextCentre(true)
                    SetTextOutline()
                    BeginTextCommandDisplayText('STRING')
                    AddTextComponentSubstringPlayerName(name)
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

        while State.inMatch do
            local liveCombat = State.roundLive and State.alive and not State.spectating
            local wait = liveCombat and 0 or 200

            if liveCombat then
                combatScan()
                applyMatchRestrictions()
                boundaryCheck()
                pushActivity()

                -- spawn protection shimmer
                if State.spawnProtectUntil > ms() then
                    SetEntityInvincible(playerPed(), true)
                    SetEntityAlpha(playerPed(), Config.Effects.spawnProtectionAlpha, false)
                else
                    if State.spawnProtectUntil ~= 0 then
                        State.spawnProtectUntil = 0
                        SetEntityInvincible(playerPed(), false)
                        ResetEntityAlpha(playerPed())
                    end
                end

                drawTeammateTags()

                hudAcc = hudAcc + 16
                if hudAcc >= Config.Timing.hudTick then
                    hudAcc = 0
                    local ped = playerPed()
                    local ok, weapon = GetCurrentPedWeapon(ped, true)
                    local ammo = ok and GetAmmoInPedWeapon(ped, weapon) or 0
                    local clip = 0
                    if ok then
                        local has, clipAmmo = GetAmmoInClip(ped, weapon)
                        clip = has and clipAmmo or 0
                    end
                    nui({ action = 'localHud', data = {
                        health = math.max(0, GetEntityHealth(ped) - 100),
                        armor  = GetPedArmour(ped),
                        weapon = currentWeaponName(),
                        ammo   = ammo, clip = clip
                    } })
                end
            else
                -- non combat states: keep the restrictions but stay cheap
                if State.frozen then
                    FreezeEntityPosition(playerPed(), true)
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
        State.training = false
        clearTrainingTargets()
        local ped = playerPed()
        RemoveAllPedWeapons(ped, true)
        SetEntityMaxHealth(ped, 200)
        SetEntityHealth(ped, 200)
        SetPedArmour(ped, 0)
        DisplayRadar(true)
        nui({ action = 'training', data = { active = false } })
        nui({ action = 'hudVisible', value = false })
        return
    end

    State.training = true
    closeMenu()

    if data.spawn then teleport(data.spawn, false) end
    if data.loadout then applyLoadout(data.loadout) end

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
-- 12. NOTIFICATIONS & MISC
-- ============================================================================

RegisterNetEvent('m5rp:cl:notify', function(data)
    nui({ action = 'toast', kind = data.kind or 'info',
          message = data.message, title = data.title })
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
    TriggerScreenblurFadeOut(0)
    clearTrainingTargets()

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

