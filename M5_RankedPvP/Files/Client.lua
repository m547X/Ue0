

local Lang = Locale.default or 'en'

local function localeTable(code)
    return (Locale and Locale[code]) or (Locale and Locale[Locale.fallback or 'en']) or {}
end

local function _L(str)
    if type(str) ~= 'string' then return str end
    return localeTable(Lang)[str] or str
end

local function _Lf(str, ...)
    local ok, res = pcall(string.format, _L(str), ...)
    return ok and res or _L(str)
end

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

local L = setmetatable({}, { __index = function(_, key)
    local legacy = (Config.Text and Config.Text.en and Config.Text.en[key]) or key
    return _L(legacy)
end })

local function localePayload()
    local langs, tables = {}, {}
    for _, entry in ipairs(Locale.available or {}) do
        langs[#langs + 1] = { id = entry.id, label = entry.label }
        tables[entry.id]  = Locale[entry.id] or {}
    end
    return {
        language  = Lang,
        notifyLanguage = notifyLang(),
        languages = langs,
        strings   = tables,
        rtl       = Locale.rtl or {}
    }
end

local State = {
    booted     = false,
    menuOpen   = false,
    menuPage   = nil,
    uiLocked   = false,
    promptFocus   = false,
    promptPending = false,

    profile    = nil,

    inMatch    = false,
    matchId    = nil,
    matchState = 'NONE',
    team       = 0,
    ffa        = false,
    alive      = false,
    frozen     = false,
    roundLive  = false,

    map        = nil,
    settings   = {},
    roster     = {},

    spectating = false,
    spectateTargets = {},
    spectateIndex   = 1,
    spectateFree    = false,
    spectateCam     = nil,

    training   = false,
    trainingProps = {},

    bots        = {},
    botsActive  = false,
    botsHeld    = false,
    botMatchId  = nil,
    botHeadshot = false,

    outside      = false,
    outsideUntil = 0,

    lastHealth   = 200,
    lastArmor    = 0,
    lastShotAt   = 0,
    lastDamageBy = nil,
    lastDamageAt = 0,
    hitmarkerUntil = 0,
    hitmarkerHead  = false,
    reportedDeath  = false,
    spawnProtectUntil = 0,

    lastActivityPush = 0,
    lastCamHeading   = 0.0,
    lastPos          = vector3(0.0, 0.0, 0.0),

    nearPoint = false
}

local blipHandle = nil
local matchThreadRunning = false
local spectateThreadRunning = false

local clearBots
local idleVisualGuard

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

local function hook(name, data)
    local fn = M5 and M5.Client and M5.Client[name]
    if type(fn) == 'function' then
        local ok, e = pcall(fn, data)
        if not ok and not (Config.Console and Config.Console.errors == false) then
            print(('^1[M5RP][error] Export.lua M5.Client.%s failed: %s^7')
                :format(name, tostring(e)))
        end
    end
    TriggerEvent('m5rp:' .. name, data)
end

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

local UNARMED_HASH = GetHashKey('WEAPON_UNARMED')

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

local loadoutSeq = 0

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
        if primary then SetCurrentPedWeapon(ped, primary, true) end

        State.lastHealth = GetEntityHealth(ped)
        State.lastArmor  = GetPedArmour(ped)
        return primary
    end

    local primary = give()
    if not settle or not primary then return end

    local window = ((Config.Loadout and Config.Loadout.settleSeconds) or 3.0) * 1000
    Citizen.CreateThread(function()
        local until_ = ms() + window
        while ms() < until_ do
            Citizen.Wait(0)
            if seq ~= loadoutSeq then return end
            if not HasPedGotWeapon(playerPed(), primary, false) then
                give()
            end
        end
    end)
end

local nextRearm = 0

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

    local t = ms()
    if t < nextRearm then return end
    if not State.inMatch or not State.alive then return end

    local cfg = Config.Loadout or {}
    if cfg.rearmWhenEmpty == false then return end

    local lo = State.loadout
    if not lo or not lo.weapons or #lo.weapons == 0 then return end
    nextRearm = t + math.floor(((cfg.rearmEvery or 1.0) * 1000))

    if holdingNothing(ped) then
        dbg('re-arming: the player was left with none of their loadout')
        applyLoadout(lo, false)
        return
    end

    local ok, held = GetCurrentPedWeapon(ped, true)
    if ok and held ~= UNARMED_HASH then return end

    local first = GetHashKey(lo.weapons[1].name)
    if HasPedGotWeapon(ped, first, false) then
        dbg('re-arming: the loadout was there but the hands were empty')
        SetCurrentPedWeapon(ped, first, true)
    end
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

    Citizen.CreateThread(function()
        local timeout = ms() + 5000
        while not HasCollisionLoadedAroundEntity(ped) and ms() < timeout do
            RequestCollisionAtCoord(spawn.x, spawn.y, spawn.z)
            Citizen.Wait(50)
        end
    end)
end

local returnPoint = nil

local function rememberPoint()
    if State.inMatch or State.training then return end
    local cfg = Config.Return or {}
    if cfg.enabled == false then return end

    local ped = playerPed()
    local pos = GetEntityCoords(ped)
    local max = cfg.maxHeight or 900.0

    if pos.z > max then returnPoint = nil return end

    returnPoint = { x = pos.x, y = pos.y, z = pos.z, h = GetEntityHeading(ped) }
end

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

local activeEffects = {}
local blurOn = false

local function screenEffect(name, duration)
    if not Config.Effects.enabled or not name then return end
    if duration and duration > 0 then
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

local function clearScreenEffects()
    for name in pairs(activeEffects) do StopScreenEffect(name) end
    activeEffects = {}
    StopAllScreenEffects()
    AnimpostfxStopAll()
    TriggerScreenblurFadeOut(0)
    ClearTimecycleModifier()
    ClearExtraTimecycleModifier()
    SetTransitionTimecycleModifier('default', 0.5)
    ResetScenarioTypesEnabled()
    blurOn = false
end

local function nui(payload)
    SendNUIMessage(payload)
end

local showBoundary, hideBoundary, clearBoundary
local setHeadBones

local function setFocus(on)
    SetNuiFocus(on, on)
    SetNuiFocusKeepInput(false)
end

local promptToken = 0

local function promptKeepsInput()
    local c = Config.Prompt
    return not c or c.keepInput ~= false
end

local function applyPromptFocus()
    if State.menuOpen then return end
    local on = State.promptFocus == true
    SetNuiFocus(on, on)
    SetNuiFocusKeepInput(on and promptKeepsInput() or false)
end

local function setPromptFocus(on)
    State.promptFocus = on and true or false
    applyPromptFocus()
    nui({ action = 'promptFocus', on = State.promptFocus })
end

local function clearPrompt()
    promptToken = promptToken + 1
    State.promptPending = false
    setPromptFocus(false)
end

function promptKeyLabel()
    local c = Config.Prompt
    local k = c and c.key
    if not k or k.enabled == false then return nil end
    return tostring(k.key or 'LMENU'):upper()
end

local function togglePromptFocus()
    if not State.promptPending then return end
    if State.menuOpen then return end
    setPromptFocus(not State.promptFocus)
end

local function openMenu(page)
    if State.menuOpen then return end
    if State.inMatch and State.roundLive and State.alive then
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

local wbwAbort

local function closeMenu(force)
    if State.uiLocked and not force then return end
    if wbwAbort then wbwAbort() end
    if blurOn then
        TriggerScreenblurFadeOut(180)
        blurOn = false
    end
    if not State.menuOpen then return end
    State.menuOpen = false
    setFocus(false)
    nui({ action = 'close' })
    applyPromptFocus()
end

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb('ok')
end)

RegisterNUICallback('promptDone', function(_, cb)
    clearPrompt()
    cb('ok')
end)

if promptKeyLabel() then
    RegisterCommand('m5rp_prompt', togglePromptFocus, false)
    RegisterKeyMapping('m5rp_prompt',
        (Config.Prompt.key.label or 'M5 Ranked PvP — Answer an invitation'),
        'keyboard', promptKeyLabel())
end

RegisterNUICallback('queue', function(data, cb)
    TriggerServerEvent('m5rp:sv:queue', data.action, data.mode, data.autoFill == true)
    cb('ok')
end)

RegisterNUICallback('ready', function(data, cb)
    TriggerServerEvent('m5rp:sv:ready', data.id, data.accept == true)
    cb('ok')
end)

RegisterNUICallback('mapVote', function(data, cb)
    if data.kind then
        TriggerServerEvent('m5rp:sv:mapVote', data.kind, data.choice)
    else
        TriggerServerEvent('m5rp:sv:mapVote', data.mapId)
    end
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
    TriggerServerEvent('m5rp:sv:store', data.action, data.kind, data.id)
    cb('ok')
end)

RegisterNUICallback('settings', function(data, cb)
    if data and data.settings then
        TriggerServerEvent('m5rp:sv:settings', data.settings)

        local picked = data.settings.language
        if picked and Locale[picked] and picked ~= Lang then
            Lang = picked
            SendNUIMessage({ action = 'locale', data = localePayload() })
        end
    end
    cb('ok')
end)

RegisterNUICallback('roomCode', function(_, cb)
    TriggerServerEvent('m5rp:sv:roomCode')
    cb('ok')
end)

RegisterNUICallback('action', function(data, cb)
    TriggerServerEvent('m5rp:sv:action', data.action, data)
    if data.action == 'leaveMatch' or data.action == 'training' then
        closeMenu()
    end
    cb('ok')
end)

RegisterNetEvent('m5rp:cl:boot', function(payload)
    State.booted  = true
    State.profile = payload
    nui({ action = 'boot', data = payload, theme = Config.UI, brand = Config.Brand })
end)

RegisterNetEvent('m5rp:cl:data', function(payload)
    nui({ action = 'data', data = payload })
end)

RegisterNetEvent('m5rp:cl:party', function(payload)
    if payload and payload.invite then
        local c = Config.Prompt or {}

        nui({ action = 'prime', theme = Config.UI, brand = Config.Brand,
              sounds = Config.Sounds, text = L, locale = localePayload(),
              defaults = Config.DefaultSettings })
        nui({ action = 'party', data = payload, promptKey = promptKeyLabel() })

        promptToken = promptToken + 1
        State.promptPending = true

        if c.focusOnArrival == true then
            setPromptFocus(true)
        else
            setPromptFocus(false)
        end

        if c.sound ~= false then
            PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
        end

        local mine = promptToken
        local secs = tonumber(payload.invite.timeout) or 30
        Citizen.SetTimeout(math.floor(secs * 1000) + 2000, function()
            if promptToken == mine then clearPrompt() end
        end)
        return
    end

    nui({ action = 'party', data = payload })
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
    if payload and payload.options then
        State.uiLocked = true
        if not State.menuOpen then
            State.menuOpen = true
            setFocus(true)
            nui({ action = 'open', page = 'ranked', theme = Config.UI, brand = Config.Brand, sounds = Config.Sounds,
                  text = L, locale = localePayload(), defaults = Config.DefaultSettings,
                  silent = true })
        end
    end

    nui({ action = 'mapVote', data = payload })

    if payload and (payload.close or payload.result) then
        State.uiLocked = false
        closeMenu(true)
    end
end)

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

        if State.inMatch or State.spectating or State.training then
            State.nearPoint = false
            Citizen.Wait(2000)
            goto continue
        end

        do
            local ped  = playerPed()
            local pos  = GetEntityCoords(ped)
            local dx, dy, dz = pos.x - point.x, pos.y - point.y, pos.z - point.z
            local distSq = dx * dx + dy * dy + dz * dz

            if distSq > 22500.0 then
                wait = T.idleFar
                State.nearPoint = false
            elseif distSq > 2500.0 then
                wait = T.idleMid
                State.nearPoint = false
            elseif distSq > cfg.drawDistance * cfg.drawDistance then
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

                if distSq <= cfg.distance * cfg.distance then
                    State.nearPoint = true
                    drawMarkerText(point.x, point.y, point.z + 0.9, L.openPrompt)
                    if IsControlJustReleased(0, 38) then
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

local startMatchThread
local stopSpectate

RegisterNetEvent('m5rp:cl:setup', function(data)
    rememberPoint()

    State.inMatch    = true
    State.matchId    = data.matchId
    State.matchState = 'STARTING'
    State.team       = data.team or 1
    State.ffa        = data.ffa == true
    State.map        = data.map
    State.settings   = data.settings or {}
    setHeadBones(State.settings.headBones)
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
        nui({ action = 'scoreboard', show = false })
        State.alive = true
        State.reportedDeath = false
        clearBoundary()
        State.spawnProtectUntil = ms() + ((data.protection or 0) * 1000)
        stopSpectate()

        if data.spawn then teleport(data.spawn, data.freeze == true) end

        if data.freeze ~= true then
            State.frozen = false
            FreezeEntityPosition(playerPed(), false)
            DisablePlayerFiring(PlayerId(), false)
            SetPlayerCanDoDriveBy(PlayerId(), true)
        end

        do
            local ped = playerPed()
            if IsPedRagdoll(ped) or IsPedFalling(ped) or IsPedDeadOrDying(ped, true) then
                ClearPedTasksImmediately(ped)
                SetPedCanRagdoll(ped, true)
            end
        end

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
        DisablePlayerFiring(PlayerId(), false)
        SetPlayerCanDoDriveBy(PlayerId(), true)
        nui({ action = 'round', data = { phase = 'live', round = data.round, time = data.time } })
        hook('onRoundStart', { matchId = State.matchId, round = data.round, time = data.time })

    elseif data.phase == 'loadout' then
        if data.loadout then applyLoadout(data.loadout) end
        nui({ action = 'event', data = {
            type = 'KILLSTREAK', extra = data.gunLevel
        } })

    elseif data.phase == 'rearm' then
        if data.loadout then
            applyLoadout(data.loadout, true)
            nui({ action = 'toast', kind = 'ok',
                  title = _L('LOADOUT'), message = _L('Your weapons were given back.') })
        end

    elseif data.phase == 'revive' then
        local ped = playerPed()
        local maxH = (data.health or 100) + 100
        SetEntityHealth(ped, maxH)
        State.lastHealth = maxH

    elseif data.phase == 'end' then
        State.roundLive = false
        State.frozen    = true
        FreezeEntityPosition(playerPed(), true)
        DisablePlayerFiring(PlayerId(), true)
        SetPlayerCanDoDriveBy(PlayerId(), false)
        clearBoundary()
        nui({ action = 'round', data = {
            phase = 'end', round = data.round, winner = data.winner,
            reason = data.reason, scores = data.scores,
            myTeam = State.team, scoreboard = data.scoreboard
        } })

        hook('onRoundEnd', {
            matchId = State.matchId, round = data.round, winner = data.winner,
            reason = data.reason, scores = data.scores
        })
    end
end)

RegisterNetEvent('m5rp:cl:hud', function(data)
    State.matchState = data.state or State.matchState
    State.alive      = data.alive == true

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

    nui({ action = 'hudVisible', value = false })
    nui({ action = 'scoreboard', show = false })

    local rc = (Config.HUD and Config.HUD.result) or {}
    nui({ action = 'matchEnd', data = data,
          dismissHint = rc.enabled ~= false and (rc.display or 'BACKSPACE') or nil,
          autoClose   = rc.autoClose,
          rankCfg     = (Config.HUD and Config.HUD.rankChange) or {} })
    hook('onMatchEnd', {
        matchId = data.matchId, result = data.result,
        scores = data.scores, rp = data.rp
    })

end)

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

    if not (data and data.keepScreens) then
        nui({ action = 'hudVisible', value = false })
        nui({ action = 'matchCleanup' })
    end

    local reason = (data and data.reason) or 'END'
    returnHome(reason == 'LEAVE' and 'afterSurrender' or 'afterMatch')

    TriggerServerEvent('m5rp:sv:boot')
end)

RegisterNetEvent('m5rp:cl:endScreens', function()
    nui({ action = 'hudVisible', value = false })
    nui({ action = 'matchCleanup' })
end)

local DEFAULT_HEAD_BONES = { 31086, 39317, 12844, 20178, 21550 }
local HEAD_BONES = {}
for _, bone in ipairs(DEFAULT_HEAD_BONES) do HEAD_BONES[bone] = true end

function setHeadBones(list)
    HEAD_BONES = {}
    local src = (type(list) == 'table' and #list > 0) and list or DEFAULT_HEAD_BONES
    for i = 1, #src do HEAD_BONES[src[i]] = true end
end

local SHOT_REPORT_INTERVAL = 220
local lastShotReport = 0

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

    if isHead and State.settings.headshotOneShot == true then
        TriggerServerEvent('m5rp:sv:combat', 'hs', {
            attacker = attackerSrc,
            weapon   = weapon,
            bone     = bone,
            dist     = #(GetEntityCoords(ped) - GetEntityCoords(attacker))
        })
    end
end)

local function comaFloor()
    local c = Config.Coma
    if not c or c.enabled == false then return nil end
    local v = tonumber(c.health)
    if not v or v <= 0 then return nil end
    return v
end

local function displayHealth(ped)
    local raw = GetEntityHealth(ped) - 100
    if raw < 0 then raw = 0 end

    local floor = comaFloor()
    if not floor or Config.Coma.rescaleHud == false then return raw end

    local maxHp = tonumber(State.settings and State.settings.health) or 100
    if maxHp <= floor then return raw end
    if raw <= floor then return 0 end
    return math.floor(((raw - floor) / (maxHp - floor)) * maxHp + 0.5)
end

local function isDown(ped, health)
    if IsEntityDead(ped) then return true end

    local hp = (health or GetEntityHealth(ped)) - 100
    if hp <= 0 then return true end

    local floor = comaFloor()
    if floor and Config.Coma.countsAsDeath ~= false then
        return hp <= floor
    end
    return false
end

local function combatScan(ped, shooting)
    ped = ped or playerPed()

    if shooting == nil then shooting = IsPedShooting(ped) end
    if shooting then
        reportShot(false, ped)
    end

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

    if isDown(ped, health) and not State.reportedDeath then
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

        nui({ action = 'localHud', data = { vitalsOnly = true, health = 0, armor = 0 } })
    end
end

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

local boundaryShown = false

local boundarySeconds, boundaryDistance = -1, -1

showBoundary = function(seconds, distance)
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

clearBoundary = function()
    State.outside = false
    hideBoundary()
end

local function boundaryCheck(pos)
    if not State.map or not State.map.center or not State.map.radius then return end
    if not State.alive then clearBoundary() return end

    pos = pos or GetEntityCoords(playerPed())
    local c = State.map.center

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
        State.outside = false
        hideBoundary()
    end
end

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

local ACTIVITY_MOVE_SQ  = 1.5 * 1.5
local ACTIVITY_PROBE_MS = 250
local nextActivityProbe = 0

local function pushActivity(ped, pos, shooting)
    local t = ms()
    if t < nextActivityProbe then return end
    nextActivityProbe = t + ACTIVITY_PROBE_MS

    ped = ped or playerPed()
    pos = pos or GetEntityCoords(ped)

    local last = State.lastPos
    local dx, dy, dz = pos.x - last.x, pos.y - last.y, pos.z - last.z
    local moved = (dx * dx + dy * dy + dz * dz) >= ACTIVITY_MOVE_SQ

    local heading
    local acted = moved
    if not acted then
        if shooting == nil then shooting = IsPedShooting(ped) end
        heading = GetGameplayCamRot(2).z
        acted = math_abs(((heading - State.lastCamHeading + 180) % 360) - 180) >= 4.0
             or shooting or IsControlPressed(0, 24)
             or IsControlPressed(0, 25) or IsControlPressed(0, 38)
    end

    if acted then
        State.lastPos = pos
        if heading then State.lastCamHeading = heading end
        if (t - State.lastActivityPush) > 3000 then
            State.lastActivityPush = t
            TriggerServerEvent('m5rp:sv:activity')
        end
    end
end

local NO_WEAPON_WHEEL = Config.Display.disableWeaponWheel == true

local function applyMatchRestrictions()
    if NO_WEAPON_WHEEL then
        DisableControlAction(0, 37, true)
        DisableControlAction(0, 157, true)
        DisableControlAction(0, 158, true)
        DisableControlAction(0, 160, true)
        DisableControlAction(0, 164, true)
        DisableControlAction(0, 165, true)
    end
    if not State.settings.jump then
        DisableControlAction(0, 22, true)
    end
    if not State.settings.vehicles then
        DisableControlAction(0, 23, true)
        DisableControlAction(0, 75, true)
    end
    DisableControlAction(0, 288, true)
    DisableControlAction(0, 289, true)
    DisableControlAction(0, 170, true)
    DisableControlAction(0, 167, true)
end

local TAG_ROSTER_EVERY = 500
local tagRoster, tagRosterAt, tagRosterTeam = {}, 0, nil

local function refreshTagRoster(teams, myTeam)
    tagRosterAt   = ms()
    tagRosterTeam = myTeam
    local n = 0
    local players = GetActivePlayers()
    for i = 1, #players do
        local player = players[i]
        local sid = GetPlayerServerId(player)
        if teams[sid] == myTeam then
            n = n + 1
            local e = tagRoster[n]
            if e then e.player, e.sid = player, sid
            else tagRoster[n] = { player = player, sid = sid } end
        end
    end
    for i = #tagRoster, n + 1, -1 do tagRoster[i] = nil end
end

local function drawTeammateTags(myPed, myPos)
    if not Config.Display.teammateNameplates or State.ffa then return end

    local teams = State.teamOfServerId
    if not teams then return end

    local myTeam = State.team
    local names  = State.nameOfServerId
    local range  = Config.Display.nameplateDistance
    local rangeSq = range * range
    myPed = myPed or playerPed()
    myPos = myPos or GetEntityCoords(myPed)

    local t = ms()
    if tagRosterTeam ~= myTeam or (t - tagRosterAt) >= TAG_ROSTER_EVERY then
        refreshTagRoster(teams, myTeam)
    end

    local mx, my, mz = myPos.x, myPos.y, myPos.z

    for i = 1, #tagRoster do
        local sid = tagRoster[i].sid
        if teams[sid] == myTeam then
            local ped = GetPlayerPed(tagRoster[i].player)
            if ped ~= myPed and DoesEntityExist(ped) then
                local pos = GetEntityCoords(ped)
                local dx, dy, dz = mx - pos.x, my - pos.y, mz - pos.z

                if (dx * dx + dy * dy + dz * dz) <= rangeSq
                   and World3dToScreen2d(pos.x, pos.y, pos.z + 1.05) then
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
        local lastHud = {}

        while State.inMatch do
            local liveCombat = State.roundLive and State.alive and not State.spectating
            local wait = (liveCombat or State.frozen) and 0 or 200

            if liveCombat then
                local ped = playerPed()
                local pos = GetEntityCoords(ped)
                local shooting = IsPedShooting(ped)

                combatScan(ped, shooting)
                applyMatchRestrictions()
                boundaryCheck(pos)
                rearmGuard(ped)
                pushActivity(ped, pos, shooting)

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
                        clipMax = GetMaxAmmoInClip(ped, weapon, true) or 0
                    end
                    local health = displayHealth(ped)
                    local armor  = GetPedArmour(ped)
                    local name   = (ok and WEAPON_NAME_BY_HASH[weapon]) or 'WEAPON_UNARMED'

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
                if State.frozen then
                    local ped = playerPed()
                    FreezeEntityPosition(ped, true)
                    rearmGuard(ped)

                    DisablePlayerFiring(PlayerId(), true)
                    SetPlayerCanDoDriveBy(PlayerId(), false)
                    DisableControlAction(0, 24,  true)
                    DisableControlAction(0, 25,  true)
                    DisableControlAction(0, 47,  true)
                    DisableControlAction(0, 58,  true)
                    DisableControlAction(0, 140, true)
                    DisableControlAction(0, 141, true)
                    DisableControlAction(0, 142, true)
                    DisableControlAction(0, 257, true)
                    DisableControlAction(0, 263, true)
                    DisableControlAction(0, 264, true)
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

            local ped = spectateTargetPed()
            if not ped then spectateNext(1) end

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

local TRAIN_MODEL = 's_m_y_marine_01'

local function clearTrainingTargets()
    for i = 1, #State.trainingProps do
        local rec = State.trainingProps[i]
        local ped = rec and rec.ped
        if ped and DoesEntityExist(ped) then DeletePed(ped) end
    end
    State.trainingProps = {}
end

local function trainingModel()
    local model = GetHashKey(TRAIN_MODEL)
    RequestModel(model)
    local timeout = ms() + 5000
    while not HasModelLoaded(model) and ms() < timeout do Citizen.Wait(20) end
    if not HasModelLoaded(model) then return nil end
    return model
end

local function trainingGroundZ(x, y, z)
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 25.0, false)
    if ok and gz and gz > -150.0 and math.abs(gz - z) < 40.0 then return gz + 1.0 end
    return z
end

local function trainingSpot(origin, minDist, maxDist)
    local lo   = minDist or 0.0
    local span = math.max(0.0, (maxDist or lo) - lo)
    local ang  = math.random() * math.pi * 2.0
    local dist = lo + math.random() * span
    local x = origin.x + math.cos(ang) * dist
    local y = origin.y + math.sin(ang) * dist
    return x, y, trainingGroundZ(x, y, origin.z)
end

local function trainingArcSpot(origin, spec)
    local half = math.rad(spec.arc or 80.0) * 0.5
    local ang  = math.rad(origin.h or 0.0) + (math.random() * 2.0 - 1.0) * half
    local near = spec.near or 10.0
    local dist = near + math.random() * math.max(0.0, (spec.far or 26.0) - near)
    local x = origin.x - math.sin(ang) * dist
    local y = origin.y + math.cos(ang) * dist
    return x, y, trainingGroundZ(x, y, origin.z)
end

local function trainingTarget(model, x, y, z, h, frozen)
    local ped = CreatePed(4, model, x, y, z, h or 0.0, false, false)
    if not DoesEntityExist(ped) then return nil end
    SetEntityInvincible(ped, false)
    SetPedCanRagdoll(ped, false)
    FreezeEntityPosition(ped, frozen == true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedSuffersCriticalHits(ped, true)
    SetPedDiesWhenInjured(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetEntityAsMissionEntity(ped, true, true)
    return ped
end

local function trainingWalk(rec, origin, spec)
    rec.gx, rec.gy, rec.gz = trainingSpot(origin, 4.0, spec.area or 26.0)
    TaskGoToCoordAnyMeans(rec.ped, rec.gx, rec.gy, rec.gz, rec.speed, 0, false, 786603, 0.0)
    local p = GetEntityCoords(rec.ped)
    rec.lx, rec.ly = p.x, p.y
end

local function spawnTrainingLine(origin, count, spacing, headshotOnly, model)
    local heading = origin.h or 0.0
    local rad     = math.rad(heading)
    local forward = vector3(-math.sin(rad), math.cos(rad), 0.0)
    local right   = vector3(math.cos(rad), math.sin(rad), 0.0)

    for i = 1, count do
        local offset = ((i - 1) - (count - 1) / 2) * 2.2
        local dist   = spacing * (headshotOnly and (1 + (i % 4)) or 1)
        local pos = vector3(origin.x, origin.y, origin.z)
                  + (forward * (10.0 + dist))
                  + (right * offset)

        local ped = trainingTarget(model, pos.x, pos.y, pos.z, heading + 180.0, true)
        if ped then
            State.trainingProps[#State.trainingProps + 1] = {
                ped = ped, fixed = true,
                x = pos.x, y = pos.y, z = pos.z, h = heading + 180.0
            }
        end
    end
end

local function spawnTrainingMover(origin, spec, model)
    local x, y, z = trainingSpot(origin, spec.minDist or 10.0, spec.area or 26.0)
    local ped = trainingTarget(model, x, y, z, math.random() * 360.0, false)
    if not ped then return nil end

    local pick = spec.speeds[math.random(1, #spec.speeds)]
    local rec  = { ped = ped, speed = pick.speed or 1.0, pace = pick.label or '' }
    trainingWalk(rec, origin, spec)
    return rec
end

local function spawnTrainingReflex(origin, spec, model)
    local x, y, z = trainingArcSpot(origin, spec)
    local h = GetHeadingFromVector_2d(origin.x - x, origin.y - y)
    local ped = trainingTarget(model, x, y, z, h, true)
    if not ped then return nil end
    return { ped = ped, born = ms() }
end

local function trainingStatRows(kind, st)
    if kind == 'reflex' then
        local react = st.reactCount > 0
                      and (math.floor(st.reactTotal / st.reactCount) .. ' MS')
                      or '-'
        return {
            { l = 'HITS',     v = tostring(st.hits) },
            { l = 'MISSED',   v = tostring(st.misses) },
            { l = 'REACTION', v = react },
            { l = 'STREAK',   v = st.streak .. ' / ' .. st.bestStreak }
        }
    end

    if kind == 'moving' then
        local acc = st.shots > 0 and math.min(100, math.floor((st.hits / st.shots) * 100)) or 0
        return {
            { l = 'HITS',      v = tostring(st.hits) },
            { l = 'HEADSHOTS', v = tostring(st.headshots) },
            { l = 'ACCURACY',  v = acc .. '%' },
            { l = 'CLOCK',     v = st.clock }
        }
    end

    local rate = st.hits > 0 and math.floor((st.headshots / st.hits) * 100) or 0
    return {
        { l = 'HITS',      v = tostring(st.hits) },
        { l = 'HEADSHOTS', v = tostring(st.headshots) },
        { l = 'HS RATE',   v = rate .. '%' },
        { l = 'CLOCK',     v = st.clock }
    }
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

    rememberPoint()

    State.training = true
    closeMenu()
    hook('onTrainingStart', { kind = data.kind, label = data.label })

    if data.spawn then teleport(data.spawn, false) end
    if data.loadout then applyLoadout(data.loadout, true) end

    local origin  = data.spawn
    local kind    = data.kind
    local reflex  = data.reflex
    local moving  = data.moving
    local oneShot = data.headshotOneShot == true
    local limit   = math.max(0, math.floor(tonumber(data.time) or 0))

    clearTrainingTargets()

    local model = (origin and (reflex or moving or (data.targets or 0) > 0)) and trainingModel() or nil
    if origin and model then
        if moving and moving.speeds and #moving.speeds > 0 then
            for _ = 1, math.max(1, math.floor(tonumber(data.targets) or 6)) do
                local rec = spawnTrainingMover(origin, moving, model)
                if rec then State.trainingProps[#State.trainingProps + 1] = rec end
            end
        elseif not reflex then
            spawnTrainingLine(origin, math.floor(tonumber(data.targets) or 0),
                              tonumber(data.spacing) or 8.0, kind == 'headshot', model)
        end
    end

    local exitCfg = (Config.Training and Config.Training.exit) or {}
    nui({ action = 'training', data = {
        active = true, label = data.label, kind = kind,
        pace = reflex and reflex.label or nil,
        targets = data.targets, time = limit,
        exit = (exitCfg.enabled and exitCfg.hint and exitCfg.hint.enabled) and {
            key  = (exitCfg.keybind and exitCfg.keybind.display) or 'BACKSPACE',
            text = (exitCfg.hint and exitCfg.hint.text) or 'EXIT TRAINING',
            command = (exitCfg.command and exitCfg.command.enabled)
                      and ('/' .. (exitCfg.command.name or 'exittraining')) or nil
        } or nil
    } })

    Citizen.CreateThread(function()
        local st = {
            hits = 0, headshots = 0, misses = 0, shots = 0,
            streak = 0, bestStreak = 0, reactTotal = 0, reactCount = 0, clock = '0s'
        }
        local startedAt  = ms()
        local wasShooting = false
        local nextSpawn  = 0
        local nextTask   = 0
        local nextClock  = 0
        local dirty      = true
        local ended      = false

        local function push()
            nui({ action = 'training', data = {
                active = true, hits = st.hits, headshots = st.headshots,
                misses = st.misses, streak = st.streak,
                left = limit > 0 and math.max(0, limit - math.floor((ms() - startedAt) / 1000)) or nil,
                stats = trainingStatRows(kind, st)
            } })
        end

        local function scored(head, react)
            st.hits = st.hits + 1
            if head then st.headshots = st.headshots + 1 end
            st.streak = st.streak + 1
            if st.streak > st.bestStreak then st.bestStreak = st.streak end
            if react then
                st.reactTotal = st.reactTotal + react
                st.reactCount = st.reactCount + 1
            end
            dirty = true
        end

        push()

        while State.training do
            local me = playerPed()
            local t  = ms()

            local shooting = IsPedShooting(me)
            if shooting and not wasShooting then st.shots = st.shots + 1 end
            wasShooting = shooting

            if reflex then
                for i = #State.trainingProps, 1, -1 do
                    local rec = State.trainingProps[i]
                    local ped = rec.ped
                    if not ped or not DoesEntityExist(ped) then
                        table.remove(State.trainingProps, i)
                        nextSpawn = t + reflex.gap
                    else
                        local hit = IsEntityDead(ped)
                                    or HasEntityBeenDamagedByEntity(ped, me, true)
                        if hit then
                            local hasBone, bone = GetPedLastDamageBone(ped)
                            scored(hasBone and HEAD_BONES[bone] == true, t - rec.born)
                            DeletePed(ped)
                            table.remove(State.trainingProps, i)
                            nextSpawn = t + reflex.gap
                        elseif t - rec.born >= reflex.live then
                            st.misses = st.misses + 1
                            st.streak = 0
                            dirty = true
                            DeletePed(ped)
                            table.remove(State.trainingProps, i)
                            nextSpawn = t + reflex.gap
                        end
                    end
                end

                if origin and model and #State.trainingProps < reflex.up and t >= nextSpawn then
                    local rec = spawnTrainingReflex(origin, reflex, model)
                    if rec then State.trainingProps[#State.trainingProps + 1] = rec end
                end
            else
                for i = 1, #State.trainingProps do
                    local rec = State.trainingProps[i]
                    local ped = rec.ped

                    if ped and DoesEntityExist(ped) and not rec.down then
                        if oneShot and not IsEntityDead(ped) then
                            local hasBone, bone = GetPedLastDamageBone(ped)
                            if hasBone and HEAD_BONES[bone]
                               and HasEntityBeenDamagedByEntity(ped, me, true) then
                                ClearEntityLastDamageEntity(ped)
                                SetEntityHealth(ped, 0)
                            end
                        end

                        if IsEntityDead(ped) then
                            local hasBone, bone = GetPedLastDamageBone(ped)
                            scored(hasBone and HEAD_BONES[bone] == true, nil)
                            rec.down = true
                            rec.at   = t

                            if rec.fixed then
                                DeletePed(ped)
                                rec.ped = nil
                            end
                        end
                    end

                    if rec.down and model and (not rec.ped or not DoesEntityExist(rec.ped)) then
                        local wait = moving and moving.respawn or 0
                        if t - (rec.at or t) >= wait then
                            if moving then
                                local x, y, z = trainingSpot(origin, moving.minDist or 10.0,
                                                             moving.area or 26.0)
                                local fresh = trainingTarget(model, x, y, z, math.random() * 360.0, false)
                                if fresh then
                                    rec.ped   = fresh
                                    rec.down  = false
                                    local pick = moving.speeds[math.random(1, #moving.speeds)]
                                    rec.speed = pick.speed or 1.0
                                    rec.pace  = pick.label or ''
                                    trainingWalk(rec, origin, moving)
                                end
                            else
                                local fresh = trainingTarget(model, rec.x, rec.y, rec.z, rec.h, true)
                                if fresh then
                                    rec.ped  = fresh
                                    rec.down = false
                                end
                            end
                        end
                    elseif rec.down and rec.ped and DoesEntityExist(rec.ped)
                           and t - (rec.at or t) >= (moving and moving.respawn or 1500) then
                        DeletePed(rec.ped)
                        rec.ped = nil
                    end
                end

                if moving and t >= nextTask then
                    nextTask = t + (moving.retask or 900)
                    for i = 1, #State.trainingProps do
                        local rec = State.trainingProps[i]
                        if rec.ped and not rec.down and DoesEntityExist(rec.ped)
                           and not IsEntityDead(rec.ped) then
                            local p = GetEntityCoords(rec.ped)
                            local reached = #(p - vector3(rec.gx, rec.gy, rec.gz)) < 3.5
                            local stuck = rec.lx and (math.abs(p.x - rec.lx) + math.abs(p.y - rec.ly)) < 0.6
                            rec.lx, rec.ly = p.x, p.y
                            if reached or stuck then trainingWalk(rec, origin, moving) end
                        end
                    end
                end
            end

            if t >= nextClock then
                nextClock = t + 1000
                local elapsed = math.floor((t - startedAt) / 1000)
                st.clock = (limit > 0 and math.max(0, limit - elapsed) or elapsed) .. 's'
                dirty = true

                if limit > 0 and elapsed >= limit then
                    ended = true
                    State.training = false
                end
            end

            if dirty then
                dirty = false
                push()
            end

            Citizen.Wait(reflex and 0 or 120)
        end

        clearTrainingTargets()
        if model then SetModelAsNoLongerNeeded(model) end
        if ended then exitTraining() end
    end)
end)

clearBots = function()
    for i = 1, #State.bots do
        local ped = State.bots[i].ped
        if DoesEntityExist(ped) then DeletePed(ped) end
    end
    State.bots       = {}
    State.botsActive = false
    State.botsHeld   = false
end

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
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 5,  true)
    SetPedCombatAttributes(ped, 0,  true)
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
            FreezeEntityPosition(ped, true)
            State.bots[#State.bots + 1] = { ped = ped, down = false }
        end
    end

    SetModelAsNoLongerNeeded(model)
    State.botsActive = #State.bots > 0
    State.botsHeld   = true

    if not State.botsActive then return end

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
                        if State.botHeadshot then
                            local hasBone, bone = GetPedLastDamageBone(b.ped)
                            if hasBone and HEAD_BONES[bone]
                               and HasEntityBeenDamagedByEntity(b.ped, playerPed(), true) then
                                ClearEntityLastDamageEntity(b.ped)
                                SetEntityHealth(b.ped, 0)
                            end
                        end
                        if not State.botsHeld and not IsPedInCombat(b.ped, playerPed()) then
                            TaskCombatPed(b.ped, playerPed(), 0, 16)
                        end
                    end
                end
            end

            if not anyAlive then State.botsActive = false end
            Citizen.Wait(150)
        end
    end)
end)

do
    local sbCfg = (Config.HUD and Config.HUD.scoreboard) or {}
    if sbCfg.enabled ~= false then
        local function canShow()
            return State.inMatch and State.matchState ~= 'NONE'
        end

        local nextAsk = 0

        RegisterCommand('+m5rp_scoreboard', function()
            if not canShow() then return end
            nui({ action = 'scoreboard', show = true })

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

idleVisualGuard = function()
    if State.inMatch or State.training or State.menuOpen or State.spectating then return end
    if next(activeEffects) ~= nil or blurOn then clearScreenEffects() end
end

exports('isInMatch',   function() return State.inMatch end)
exports('isTraining',  function() return State.training end)
exports('getMatchInfo', function()
    if not State.inMatch then return nil end
    return {
        matchId = State.matchId, state = State.matchState, team = State.team,
        ffa = State.ffa, alive = State.alive, map = State.map
    }
end)

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
    local message = data.args and _Lnf(data.message, table.unpack(data.args))
                    or _Ln(data.message)
    nui({ action = 'toast', kind = data.kind or 'info',
          message = message, title = _Ln(data.title) })
end)

RegisterNUICallback('escape', function(_, cb)
    closeMenu()
    cb('ok')
end)

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

AddEventHandler('playerSpawned', function()
    Citizen.SetTimeout(4000, function()
        if not State.booted then TriggerServerEvent('m5rp:sv:boot') end
    end)
end)

Citizen.CreateThread(function()
    Citizen.Wait(6000)
    if not State.booted then TriggerServerEvent('m5rp:sv:boot') end
end)

local WB = {
    ready   = false,
    rows    = {},
    season  = nil,
    peds    = {},
    pedAt   = {},
    spawned = false,
    askAt   = 0,
    asks    = 0,
    warned  = false,
    layout  = nil,
    edit    = nil,
    awayAt  = nil
}

local function vec3(p)
    if not p then return vector3(0.0, 0.0, 0.0) end
    if p.w ~= nil or getmetatable(p) ~= nil then return p end
    return vector3(p.x + 0.0, p.y + 0.0, p.z + 0.0)
end

local function wbOn()
    local c = Config.WorldBoard
    return c ~= nil and c.enabled ~= false
end

local wbFromConfig = nil

local function wbLayout()
    if WB.edit then return WB.edit end
    if WB.layout then return WB.layout end
    local c = Config.WorldBoard or {}

    if wbFromConfig then
        local scc = c.screens
        local pcc = c.podium
        wbFromConfig.screensEnabled = not scc or scc.enabled ~= false
        wbFromConfig.podiumEnabled  = not pcc or pcc.enabled ~= false
        local spots = scc and scc.spots
        if spots then
            for i = 1, #wbFromConfig.screens do
                local spot = spots[i]
                if spot then wbFromConfig.screens[i].enabled = spot.enabled ~= false end
            end
        end
        return wbFromConfig
    end

    local sc = c.screens or {}
    local pc = c.podium  or {}

    local out = {
        screens = {}, podium = {},
        screensEnabled = sc.enabled ~= false,
        podiumEnabled  = pc.enabled ~= false,
        podiumDistance = tonumber(pc.distance) or 25.0
    }
    for i = 1, #(sc.spots or {}) do
        local spot = sc.spots[i]

        out.screens[i] = {
            pos      = spot.pos,
            title    = spot.title,
            enabled  = spot.enabled ~= false,
            h        = tonumber(spot.h) or 0.0,
            pitch    = tonumber(spot.pitch) or 0.0,
            width    = tonumber(spot.width) or 6.0,
            height   = tonumber(spot.height),
            rows     = tonumber(sc.rows) or 10,
            opacity  = tonumber(sc.opacity) or 255,
            distance = tonumber(sc.distance) or 35.0
        }
    end
    for i = 1, #(pc.spots or {}) do
        local spot = pc.spots[i]
        out.podium[i] = { pos = spot.pos, h = spot.h or 0.0, anim = spot.anim }
    end
    wbFromConfig = out
    return out
end

local function wbScreens()
    if not wbOn() then return nil end
    local l = wbLayout()
    if not l.screensEnabled or #l.screens == 0 then return nil end
    return l.screens
end

local function wbPodium()
    if not wbOn() then return nil end
    local l = wbLayout()
    if not l.podiumEnabled or #l.podium == 0 then return nil end
    return l
end

local function wbText(text, x, y, scale, r, g, b, a, align, wrapTo)
    SetTextFont(4)
    SetTextScale(0.0, scale)
    SetTextColour(r, g, b, a)
    SetTextCentre(align == 'centre')
    SetTextRightJustify(align == 'right')
    if align == 'right' then SetTextWrap(0.0, wrapTo or x) end
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function wbColour(hex)
    if type(hex) ~= 'string' then return 220, 220, 225 end
    local h = hex:gsub('#', '')
    if #h ~= 6 then return 220, 220, 225 end
    local n = tonumber(h, 16)
    if not n then return 220, 220, 225 end
    return (n >> 16) & 255, (n >> 8) & 255, n & 255
end

local DUI = {
    obj     = nil,
    handle  = nil,
    txdObj  = nil,
    txd     = 'm5rp_board_txd',
    tex     = 'm5rp_board',
    made    = false,
    ready   = false,
    live    = false,
    avail   = false,
    dirty   = false,
    msg     = nil,
    w       = 1280,
    h       = 720,
    lastKey = ''
}

local function duiSize()
    local sc = (Config.WorldBoard or {}).screens or {}
    local w = math.floor(tonumber(sc.textureWidth)  or 1280)
    local h = math.floor(tonumber(sc.textureHeight) or 720)
    if w < 256 then w = 256 elseif w > 2048 then w = 2048 end
    if h < 144 then h = 144 elseif h > 2048 then h = 2048 end
    return w, h
end

local function duiUrl()
    return ('nui://%s/Files/ui/board.html'):format(GetCurrentResourceName())
end

local function duiPush()
    local sc  = (Config.WorldBoard or {}).screens or {}
    local rows = {}
    local max  = math.floor(tonumber(sc.rows) or 10)
    for i = 1, math.min(#WB.rows, max) do rows[i] = WB.rows[i] end

    local key = tostring(#rows) .. '|' .. tostring(WB.season)
    for i = 1, #rows do
        key = key .. '|' .. tostring(rows[i].userId) .. ':' .. tostring(rows[i].rp)
              .. ':' .. tostring(rows[i].kills) .. ':' .. tostring(rows[i].deaths)
              .. ':' .. tostring(rows[i].wins) .. ':' .. tostring(rows[i].losses)
    end
    if key == DUI.lastKey then return end
    DUI.lastKey = key

    local ui    = Config.UI or {}
    local col   = ui.colors or {}
    local brand = Config.Brand or {}

    DUI.msg = json.encode({
        action = 'board',
        rows   = rows,
        max    = max,
        season = WB.season,
        title  = sc.podiumTitle,
        subtitle = sc.subtitle,
        emptyText = sc.emptyText,
        theme  = { accent = col.accent, gold = col.gold, text = col.text,
                   dim = col.dim, bg = col.bgDeep or col.bg, panel = col.panel },
        brand  = { name = brand.name, accent = brand.accent }
    })
    DUI.dirty = true
end

local function duiFlush()
    if not DUI.dirty or not DUI.live or not DUI.obj or not DUI.msg then return end
    if not DUI.avail then
        if not IsDuiAvailable(DUI.obj) then return end
        DUI.avail = true
    end
    SendDuiMessage(DUI.obj, DUI.msg)
    DUI.dirty = false
end

local function duiMakeTxd()
    for i = 0, 9 do
        local name = i == 0 and 'm5rp_board_txd' or ('m5rp_board_txd' .. i)
        local obj = CreateRuntimeTxd(name)
        if obj and obj ~= 0 then
            DUI.txd = name
            return obj
        end
    end
    return nil
end

local function duiWake()
    if not DUI.obj or DUI.live then return end
    SetDuiUrl(DUI.obj, duiUrl())
    DUI.live    = true
    DUI.avail   = false
    DUI.lastKey = ''
    duiPush()
end

local function duiCreate()
    if DUI.made then
        if DUI.ready and not DUI.live then duiWake() end
        return DUI.ready
    end
    DUI.made = true

    DUI.w, DUI.h = duiSize()
    DUI.obj = CreateDui(duiUrl(), DUI.w, DUI.h)
    if not DUI.obj then return false end

    DUI.handle = GetDuiHandle(DUI.obj)
    if not DUI.handle then return false end

    DUI.txdObj = duiMakeTxd()
    if not DUI.txdObj then return false end

    CreateRuntimeTextureFromDuiHandle(DUI.txdObj, DUI.tex, DUI.handle)

    DUI.ready, DUI.live, DUI.avail = true, true, false
    DUI.lastKey = ''
    duiPush()
    return true
end

local function duiPark()
    if not DUI.obj or not DUI.live then return end
    SetDuiUrl(DUI.obj, 'about:blank')
    DUI.live, DUI.avail, DUI.dirty = false, false, false
    DUI.lastKey = ''
end

local function duiDestroy()
    if DUI.obj then DestroyDui(DUI.obj) end
    DUI.obj, DUI.handle, DUI.txdObj = nil, nil, nil
    DUI.made, DUI.ready, DUI.live = false, false, false
    DUI.avail, DUI.dirty, DUI.msg = false, false, nil
    DUI.lastKey = ''
end

local function screenSize(spot)
    local w = tonumber(spot.width) or 4.0
    local h = tonumber(spot.height)
    if not h or h <= 0 then h = w * (DUI.h / DUI.w) end
    return w, h
end

local function screenCorners(spot)
    local p  = spot.pos
    local px, py, pz = p.x + 0.0, p.y + 0.0, p.z + 0.0
    local yd = tonumber(spot.h) or 0.0
    local td = tonumber(spot.pitch) or 0.0
    local w, h = screenSize(spot)

    local c = spot.__quad
    if c and c.px == px and c.py == py and c.pz == pz
         and c.yd == yd and c.td == td and c.w == w and c.h == h then
        return c[1], c[2], c[3], c[4],  c[5],  c[6],
               c[7], c[8], c[9], c[10], c[11], c[12]
    end

    local yaw, tilt = math.rad(yd), math.rad(td)
    local sy, cy = math.sin(yaw), math.cos(yaw)
    local st, ct = math.sin(tilt), math.cos(tilt)

    local rx, ry = cy, sy
    local ux, uy, uz = -sy * st, cy * st, ct

    local hw, hh = w * 0.5, h * 0.5
    local ax, ay = rx * hw, ry * hw
    local bx, by, bz = ux * hh, uy * hh, uz * hh

    c = {
        px - ax + bx, py - ay + by, pz + bz,
        px + ax + bx, py + ay + by, pz + bz,
        px + ax - bx, py + ay - by, pz - bz,
        px - ax - bx, py - ay - by, pz - bz,
        px = px, py = py, pz = pz, yd = yd, td = td, w = w, h = h,
        nx = ry * uz, ny = -rx * uz, nz = rx * uy - ry * ux
    }
    spot.__quad = c

    return c[1], c[2], c[3], c[4],  c[5],  c[6],
           c[7], c[8], c[9], c[10], c[11], c[12]
end

local function drawScreen(spot, ex, ey, ez)
    if not DUI.ready or not DUI.live or not DUI.avail then return end

    local a = math.floor(tonumber(spot.opacity) or 255)
    local tlx, tly, tlz, trx, try, trz, brx, bry, brz, blx, bly, blz = screenCorners(spot)

    local side = 0
    if ex then
        local c = spot.__quad
        local d = (ex - c.px) * c.nx + (ey - c.py) * c.ny + (ez - c.pz) * c.nz
        side = d >= 0.0 and 1 or -1
    end

    if side >= 0 then
        DrawSpritePoly(tlx, tly, tlz, trx, try, trz, brx, bry, brz,
                       255, 255, 255, a, DUI.txd, DUI.tex,
                       0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0)
        DrawSpritePoly(tlx, tly, tlz, brx, bry, brz, blx, bly, blz,
                       255, 255, 255, a, DUI.txd, DUI.tex,
                       0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0)
    end

    if side <= 0 then
        DrawSpritePoly(brx, bry, brz, trx, try, trz, tlx, tly, tlz,
                       255, 255, 255, a, DUI.txd, DUI.tex,
                       1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        DrawSpritePoly(blx, bly, blz, brx, bry, brz, tlx, tly, tlz,
                       255, 255, 255, a, DUI.txd, DUI.tex,
                       0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0)
    end
end

local function wbDespawn()
    for i = 1, #WB.peds do
        local p = WB.peds[i]
        if p and DoesEntityExist(p) then
            SetEntityAsMissionEntity(p, true, true)
            DeleteEntity(p)
        end
    end
    WB.peds = {}
    WB.pedAt = {}
    WB.spawned = false
end

local function wbSpawn(cfg)
    wbDespawn()

    local fallback = (Config.WorldBoard.podium or {}).fallback or 'a_m_y_skater_01'
    local count = math.min(#cfg.podium, #WB.rows)
    for i = 1, count do
        local spot = cfg.podium[i]
        local row  = WB.rows[i]

        local model = row.ped
        if not model or model == 0 or not IsModelInCdimage(model) or not IsModelAPed(model) then
            model = GetHashKey(fallback)
        end

        if IsModelInCdimage(model) and IsModelAPed(model) then
            RequestModel(model)
            local waited = 0
            while not HasModelLoaded(model) and waited < 3000 do
                Citizen.Wait(50)
                waited = waited + 50
            end

            if HasModelLoaded(model) then
                local ped = CreatePed(4, model, spot.pos.x, spot.pos.y, spot.pos.z - 1.0,
                                      spot.h or 0.0, false, false)
                SetModelAsNoLongerNeeded(model)

                if DoesEntityExist(ped) then
                    SetEntityInvincible(ped, true)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    SetPedCanRagdoll(ped, false)
                    SetPedCanBeTargetted(ped, false)
                    SetPedCanBeDraggedOut(ped, false)
                    SetPedDiesWhenInjured(ped, false)
                    SetPedFleeAttributes(ped, 0, false)
                    SetPedCombatAttributes(ped, 46, false)
                    SetEntityNoCollisionEntity(ped, playerPed(), false)
                    FreezeEntityPosition(ped, true)
                    SetEntityCanBeDamaged(ped, false)
                    SetPedConfigFlag(ped, 185, true)

                    if spot.anim and spot.anim.dict and spot.anim.name then
                        RequestAnimDict(spot.anim.dict)
                        local w = 0
                        while not HasAnimDictLoaded(spot.anim.dict) and w < 2000 do
                            Citizen.Wait(50); w = w + 50
                        end
                        if HasAnimDictLoaded(spot.anim.dict) then
                            TaskPlayAnim(ped, spot.anim.dict, spot.anim.name,
                                         8.0, -8.0, -1, 1, 0, false, false, false)
                            RemoveAnimDict(spot.anim.dict)
                        end
                    end

                    local n = #WB.peds + 1
                    WB.peds[n] = ped
                    local at = GetEntityCoords(ped)
                    WB.pedAt[n] = { x = at.x, y = at.y, z = at.z + 1.05 }
                end
            end
        end
    end

    WB.spawned = #WB.peds > 0
end

local function wbFormatRows()
    for i = 1, #WB.rows do
        local row = WB.rows[i]
        row.plate = ('#%d  %s'):format(row.position or i, row.name or '')
        row.under = ('%s \194\183 %d RP'):format(row.rank or '', row.rp or 0)
        row.r, row.g, row.b = wbColour(row.color)
    end
end

RegisterNetEvent('m5rp:cl:worldBoard', function(payload)
    if not payload then return end
    WB.ready  = true
    WB.rows   = payload.rows or {}
    WB.season = payload.season

    WB.layout = payload.layout

    wbFormatRows()
    duiPush()
    if WB.spawned then
        local cfg = wbPodium()
        if cfg then wbSpawn(cfg) else wbDespawn() end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    wbDespawn()
    duiDestroy()
end)

local WB_FAR  = 2000
local WB_NEAR = 400
local WB_ASK_EVERY = 5000

function wbTick(me, podiumAcc)
    local sleep = WB_FAR

    if not WB.ready then return sleep, podiumAcc end

    local screens = wbScreens()
    local anyNear = false
    local eyeX, eyeY, eyeZ
    if screens then
        local mx, my, mz = me.x, me.y, me.z
        for i = 1, #screens do
            local spot = screens[i]
            local p    = spot.pos
            if spot.enabled ~= false and p then
                local far = tonumber(spot.distance) or 35.0
                local dx, dy, dz = mx - p.x, my - p.y, mz - p.z
                local d2  = dx * dx + dy * dy + dz * dz
                if d2 <= far * far then
                    anyNear = true
                    if World3dToScreen2d(p.x, p.y, p.z) then
                        sleep = 0
                        if duiCreate() then
                            duiFlush()
                            if not eyeX then
                                local cam = GetFinalRenderedCamCoord()
                                eyeX, eyeY, eyeZ = cam.x, cam.y, cam.z
                            end
                            drawScreen(spot, eyeX, eyeY, eyeZ)
                        end
                    elseif sleep > WB_NEAR then
                        sleep = WB_NEAR
                    end
                elseif d2 <= (far * 1.6) * (far * 1.6) then
                    anyNear = true
                    if sleep > WB_NEAR then sleep = WB_NEAR end
                end
            end
        end
    end

    if anyNear then
        WB.awayAt = nil
    elseif DUI.live then
        local keep = math.max(0, tonumber(((Config.WorldBoard or {}).screens or {}).keepAlive) or 60)
        local t = ms()
        if not WB.awayAt then
            WB.awayAt = t
        elseif keep > 0 and (t - WB.awayAt) > (keep * 1000) then
            WB.awayAt = nil
            duiPark()
        end
    end

    local podium = wbPodium()
    if not podium then
        if WB.spawned then wbDespawn() end
        return sleep, podiumAcc
    end

    podiumAcc = podiumAcc + (sleep == 0 and 16 or sleep)
    if podiumAcc >= 900 then
        podiumAcc = 0
        local far = podium.podiumDistance * (WB.spawned and 1.25 or 1.0)
        local farSq = far * far
        local near = false
        for i = 1, #podium.podium do
            local p = podium.podium[i].pos
            if p then
                local dx, dy, dz = me.x - p.x, me.y - p.y, me.z - p.z
                if (dx * dx + dy * dy + dz * dz) <= farSq then near = true break end
            end
        end
        if near and not WB.spawned then
            wbSpawn(podium)
        elseif not near and WB.spawned then
            wbDespawn()
        end
    end

    if WB.spawned and (Config.WorldBoard.podium or {}).showNames ~= false then
        for i = 1, #WB.peds do
            local pos = WB.pedAt[i]
            local row = WB.rows[i]
            if row and pos then
                local dx, dy, dz = me.x - pos.x, me.y - pos.y, me.z - pos.z
                if (dx * dx + dy * dy + dz * dz) <= 196.0
                   and World3dToScreen2d(pos.x, pos.y, pos.z) then
                    sleep = 0
                    SetDrawOrigin(pos.x, pos.y, pos.z, 0)
                    DrawRect(0.0, 0.0, 0.058, 0.026, 8, 10, 14, 170)
                    wbText(row.plate or '', 0.0, -0.010, 0.32, 240, 240, 245, 255, 'centre')
                    wbText(row.under or '', 0.0, 0.001, 0.24,
                           row.r or 220, row.g or 220, row.b or 225, 235, 'centre')
                    ClearDrawOrigin()
                end
            end
        end
    end

    return sleep, podiumAcc
end

Citizen.CreateThread(function()
    if not wbOn() then return end
    Citizen.Wait(4000)

    local podiumAcc = 0

    while true do
        local sleep = WB_FAR

        if not WB.ready then
            local t = ms()
            if t >= (WB.askAt or 0) then
                local ped = playerPed()
                if ped and ped ~= 0 and not IsPedInjured(ped) then
                    WB.asks  = (WB.asks or 0) + 1
                    WB.askAt = t + WB_ASK_EVERY
                    TriggerServerEvent('m5rp:sv:worldBoard', GetEntityModel(ped))
                end
            end
            if WB.asks and WB.asks >= 6 and not WB.warned then
                WB.warned = true
                if not (Config.Console and Config.Console.errors == false) then
                    print('^1[M5RP][error] the world leaderboard asked the server '
                        .. 'for its rows six times and got no answer, so nothing will be '
                        .. 'drawn. Check Config.WorldBoard.enabled in Config_Server.lua, '
                        .. 'and that the resource finished starting.^7')
                end
            end
        end

        sleep, podiumAcc = wbTick(GetEntityCoords(playerPed()), podiumAcc)
        Citizen.Wait(sleep)
    end
end)

if Config.ClientCommands.coords and Config.ClientCommands.coords.enabled then
    RegisterCommand(Config.ClientCommands.coords.name, function()
        local ped = playerPed()
        local c   = GetEntityCoords(ped)
        local h   = GetEntityHeading(ped)

        print('')
        print('[M5RP] ---- ' .. Config.ClientCommands.coords.name .. ' ----')
        print(('  screen : { pos = vector3(%.2f, %.2f, %.2f), h = %.1f, pitch = 0.0, width = 6.0, enabled = true },')
            :format(c.x, c.y, c.z + 1.35, (h + 180.0) % 360.0))
        print(('  podium : { pos = vector3(%.2f, %.2f, %.2f), h = %.1f, anim = nil },')
            :format(c.x, c.y, c.z, h))
        print('[M5RP] the screen line floats at eye height and faces back at you; the podium line stands on the ground')
        print('')
    end, false)
end

local function wbEditSnapshot()
    local l = wbLayout()
    local out = { screens = {}, podium = {},
                  screensEnabled = l.screensEnabled ~= false,
                  podiumEnabled  = l.podiumEnabled ~= false,
                  podiumDistance = tonumber(l.podiumDistance) or 25.0 }
    for i = 1, #l.screens do
        local s = l.screens[i]
        out.screens[i] = {
            pos = { x = s.pos.x + 0.0, y = s.pos.y + 0.0, z = s.pos.z + 0.0 },
            title = s.title or '', enabled = s.enabled ~= false,
            h = tonumber(s.h) or 0.0, pitch = tonumber(s.pitch) or 0.0,
            width = tonumber(s.width) or 6.0,
            rows = tonumber(s.rows) or 10, opacity = tonumber(s.opacity) or 255,
            height = tonumber(s.height),
            distance = tonumber(s.distance) or 35.0
        }
    end
    for i = 1, #l.podium do
        local p = l.podium[i]
        out.podium[i] = {
            pos = { x = p.pos.x + 0.0, y = p.pos.y + 0.0, z = p.pos.z + 0.0 },
            h = tonumber(p.h) or 0.0
        }
    end
    return out
end

local function wbEditStatus()
    local l = WB.edit or wbLayout() or {}
    local me = GetEntityCoords(playerPed())

    local nearest, which
    local screens = l.screens or {}
    for i = 1, #screens do
        local p = screens[i].pos
        if p and screens[i].enabled ~= false then
            local dx, dy, dz = me.x - p.x, me.y - p.y, me.z - p.z
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            if not nearest or d < nearest then nearest, which = d, i end
        end
    end

    local seen = nil
    if nearest and screens[which] then
        seen = nearest <= (tonumber(screens[which].distance) or 35.0)
    end

    return {
        ready   = WB.ready == true,
        rows    = #(WB.rows or {}),
        page    = DUI.live == true and DUI.avail == true,
        placed  = WB.layout ~= nil,
        screens = #screens,
        nearest = nearest and math.floor(nearest + 0.5) or nil,
        which   = which,
        seen    = seen
    }
end

local function wbEditPush()
    local c = GetEntityCoords(playerPed())
    nui({ action = 'boardEdit', layout = WB.edit,
          status = wbEditStatus(),
          here = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(playerPed()) } })
end

local function wbEditOpen()
    if not wbOn() then
        nui({ action = 'toast', kind = 'warning',
              message = 'Config.WorldBoard is switched off.' })
        return
    end

    WB.edit = wbEditSnapshot()
    if #WB.edit.screens == 0 then
        WB.edit.screens[1] = {
            pos = (function()
                local c = GetEntityCoords(playerPed())
                return { x = c.x, y = c.y, z = c.z + 1.35 }
            end)(),
            title = 'LEADERBOARD', enabled = true,
            h = ((GetEntityHeading(playerPed()) + 180.0) % 360),
            pitch = 0.0, width = 6.0, rows = 9, opacity = 255, distance = 35.0
        }
    end

    State.menuOpen = true
    setFocus(true)
    nui({ action = 'open', page = 'board', theme = Config.UI, brand = Config.Brand,
          sounds = Config.Sounds, text = L, locale = localePayload(),
          defaults = Config.DefaultSettings, silent = true })
    wbEditPush()
end

local function wbEditClose(keep)
    if not keep then WB.edit = nil end
    if WB.spawned then
        local p = wbPodium()
        if p then wbSpawn(p) else wbDespawn() end
    end
    closeMenu(true)
end

local WBW = { on = false, sel = 's0', mode = 'move', speed = 1.0, walk = false }
local WBP = { on = false, kind = 's', x = 0.0, y = 0.0, z = 0.0, ok = false }
local WBC = { on = false, cam = nil, yaw = 0.0, pitch = -6.0, dist = 10.0 }
local WBW_SPEEDS = { 0.25, 0.5, 1.0, 2.0, 4.0 }
local WBW_STEP   = { x = 0.25, y = 0.25, z = 0.25, width = 0.25, h = 5.0, pitch = 2.0 }

local function wbwSel()
    local l = WB.edit
    if not l then return nil end
    local kind = WBW.sel:sub(1, 1)
    local n    = (tonumber(WBW.sel:sub(2)) or 0) + 1
    local list = (kind == 's') and l.screens or l.podium
    return kind, n, list and list[n]
end

local function wbwPayload()
    local l = WB.edit or { screens = {}, podium = {} }
    local targets = {}
    for i = 1, #(l.screens or {}) do
        targets[#targets + 1] = { id = 's' .. (i - 1), kind = 's', n = i,
                                  title = l.screens[i].title or '' }
    end
    for i = 1, #(l.podium or {}) do
        targets[#targets + 1] = { id = 'p' .. (i - 1), kind = 'p', n = i }
    end

    local kind, _, it = wbwSel()
    local item
    if it then
        item = { kind = kind,
                 x = it.pos.x + 0.0, y = it.pos.y + 0.0, z = it.pos.z + 0.0,
                 h = tonumber(it.h) or 0.0 }
        if kind == 's' then
            item.pitch  = tonumber(it.pitch) or 0.0
            item.width  = tonumber(it.width) or 6.0
            item.height = tonumber(it.height)
        end
    end

    return { action = 'boardWorld', on = WBW.on, mode = WBW.mode,
             speed = WBW.speed, sel = WBW.sel, walk = WBW.walk,
             targets = targets, item = item,
             placing = WBP.on and WBP.kind or nil,
             focused = WBC.on }
end

local function wbwRepaint()
    if WB.spawned then
        local p = wbPodium()
        if p then wbSpawn(p) else wbDespawn() end
    end
end

local function wbwNudge(axis, dir)
    local kind, _, it = wbwSel()
    if not it then return end

    local step = (WBW_STEP[axis] or 0.25) * (WBW.speed or 1.0) * (dir < 0 and -1 or 1)

    if axis == 'x' or axis == 'y' or axis == 'z' then
        it.pos[axis] = it.pos[axis] + step
    elseif axis == 'h' then
        it.h = ((((tonumber(it.h) or 0.0) + step) % 360) + 360) % 360
    elseif kind == 's' and axis == 'pitch' then
        it.pitch = math.max(-60.0, math.min(60.0, (tonumber(it.pitch) or 0.0) + step))
    elseif kind == 's' and axis == 'width' then
        it.width = math.max(0.5, math.min(40.0, (tonumber(it.width) or 6.0) + step))
    end

    if kind == 'p' then wbwRepaint() end
end

local function wbwHere()
    local kind, _, it = wbwSel()
    if not it then return end
    local ped = playerPed()
    local c   = GetEntityCoords(ped)
    local h   = GetEntityHeading(ped)
    it.pos.x, it.pos.y = c.x + 0.0, c.y + 0.0
    it.pos.z = c.z + (kind == 's' and 1.35 or 0.0)
    it.h = (kind == 'p') and h or ((h + 180.0) % 360)
    if kind == 'p' then wbwRepaint() end
end

local function wbwGoTo()
    local kind, _, it = wbwSel()
    if not it or not it.pos then return false end

    local p  = it.pos
    local hd = math.rad(tonumber(it.h) or 0.0)
    local sy, cy = math.sin(hd), math.cos(hd)

    local x, y, z, face
    if kind == 's' then
        local w    = tonumber(it.width) or 6.0
        local back = math.max(3.0, math.min(14.0, w * 1.2 + 2.0))
        x = p.x + sy * back
        y = p.y - cy * back
        z = p.z - 1.35
        face = (tonumber(it.h) or 0.0) % 360
    else
        x = p.x - sy * 2.5
        y = p.y + cy * 2.5
        z = p.z
        face = ((tonumber(it.h) or 0.0) + 180.0) % 360
    end

    local ped = playerPed()
    RequestCollisionAtCoord(x, y, z)

    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 3.0, false)
    if found and math.abs(groundZ - z) < 12.0 then z = groundZ end

    SetEntityCoordsNoOffset(ped, x, y, z + 0.1, false, false, false)
    SetEntityHeading(ped, face)

    Citizen.CreateThread(function()
        local until_ = ms() + 3000
        while ms() < until_ and not HasCollisionLoadedAroundEntity(ped) do
            RequestCollisionAtCoord(x, y, z)
            Citizen.Wait(50)
        end
    end)

    return true
end

local WBG = { hot = nil, drag = nil, cx = 0.5, cy = 0.5, sx = 0.0, sy = 0.0 }

local WBG_AXIS = {
    x = { 1.0, 0.0, 0.0, 235,  78,  78, 'X' },
    y = { 0.0, 1.0, 0.0,  92, 222, 118, 'Y' },
    z = { 0.0, 0.0, 1.0,  86, 154, 248, 'Z' }
}

local function wbgProject(x, y, z)
    local ok, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)
    if not ok then return nil end
    return sx, sy
end

local function wbgScale(it)
    local c = GetFinalRenderedCamCoord()
    local d = #(vec3({ x = c.x, y = c.y, z = c.z }) - vec3(it.pos))
    return math.max(0.5, math.min(6.0, d * 0.11))
end

local function wbgRight(it)
    local yaw = math.rad(tonumber(it.h) or 0.0)
    return math.cos(yaw), math.sin(yaw), 0.0
end

local function wbgUp(it)
    local yaw  = math.rad(tonumber(it.h) or 0.0)
    local tilt = math.rad(tonumber(it.pitch) or 0.0)
    return -math.sin(yaw) * math.sin(tilt), math.cos(yaw) * math.sin(tilt), math.cos(tilt)
end

local function wbgHandles()
    local kind, _, it = wbwSel()
    if not it then return {}, nil, nil end

    local ox, oy, oz = it.pos.x + 0.0, it.pos.y + 0.0, it.pos.z + 0.0
    local len = wbgScale(it)
    local out = {}

    if WBW.mode == 'move' then
        for _, id in ipairs({ 'x', 'y', 'z' }) do
            local a = WBG_AXIS[id]
            out[#out + 1] = { id = id,
                x = ox + a[1] * len, y = oy + a[2] * len, z = oz + a[3] * len,
                r = a[4], g = a[5], b = a[6], label = a[7],
                dx = a[1], dy = a[2], dz = a[3] }
        end

    elseif WBW.mode == 'size' and kind == 's' then
        local w, h = screenSize(it)
        local rx, ry, rz = wbgRight(it)
        local ux, uy, uz = wbgUp(it)
        local hw, hh = w * 0.5, h * 0.5
        for _, s in ipairs({ 1, -1 }) do
            out[#out + 1] = { id = 'width',
                x = ox + rx * hw * s, y = oy + ry * hw * s, z = oz + rz * hw * s,
                r = 92, g = 222, b = 118, dx = rx * s, dy = ry * s, dz = rz * s }
            out[#out + 1] = { id = 'height',
                x = ox + ux * hh * s, y = oy + uy * hh * s, z = oz + uz * hh * s,
                r = 235, g = 78, b = 78, dx = ux * s, dy = uy * s, dz = uz * s }
        end

    elseif WBW.mode == 'rotate' then
        out[#out + 1] = { id = 'h', x = ox, y = oy, z = oz,
                          r = 186, g = 132, b = 245, ring = len * 0.9 }
    end

    return out, it, kind
end

local function wbgPick(cx, cy)
    local hs = wbgHandles()
    local asp  = GetAspectRatio(false)
    if not asp or asp <= 0 then asp = 16 / 9 end

    local best, bestD = nil, math.huge
    for i = 1, #hs do
        local sx, sy = wbgProject(hs[i].x, hs[i].y, hs[i].z)
        if sx then
            local ddx = (sx - cx) * asp
            local ddy = sy - cy
            local d = math.sqrt(ddx * ddx + ddy * ddy)
            local reach = hs[i].ring and 0.13 or 0.05
            if d <= reach and d < bestD then best, bestD = hs[i], d end
        end
    end
    return best
end

local function wbgArrow(ox, oy, oz, hx, hy, hz, r, g, b, a)
    DrawLine(ox, oy, oz, hx, hy, hz, r, g, b, a)

    local vx, vy, vz = hx - ox, hy - oy, hz - oz
    local len = math.sqrt(vx * vx + vy * vy + vz * vz)
    if len < 0.01 then return end
    vx, vy, vz = vx / len, vy / len, vz / len

    local px, py, pz = -vy, vx, 0.0
    local pl = math.sqrt(px * px + py * py)
    if pl < 0.01 then px, py, pz, pl = 1.0, 0.0, 0.0, 1.0 end
    px, py = px / pl, py / pl

    local qx = vy * pz - vz * py
    local qy = vz * px - vx * pz
    local qz = vx * py - vy * px

    local back = len * 0.16
    local wide = len * 0.055
    local bx, by, bz = hx - vx * back, hy - vy * back, hz - vz * back

    for _, s in ipairs({ { px, py, pz }, { -px, -py, -pz }, { qx, qy, qz }, { -qx, -qy, -qz } }) do
        DrawLine(hx, hy, hz,
                 bx + s[1] * wide, by + s[2] * wide, bz + s[3] * wide, r, g, b, a)
    end
end

local function wbgRing(ox, oy, oz, radius, r, g, b, a)
    local prevX, prevY
    for i = 0, 24 do
        local ang = (i / 24) * math.pi * 2
        local x = ox + math.cos(ang) * radius
        local y = oy + math.sin(ang) * radius
        if prevX then DrawLine(prevX, prevY, oz, x, y, oz, r, g, b, a) end
        prevX, prevY = x, y
    end
end

local function wbwGizmo()
    local hs, it, kind = wbgHandles()
    if not it then return end

    local ox, oy, oz = it.pos.x + 0.0, it.pos.y + 0.0, it.pos.z + 0.0

    if kind == 's' then
        local ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz = screenCorners(it)
        DrawLine(ax, ay, az, bx, by, bz, 245, 197, 66, 200)
        DrawLine(bx, by, bz, cx, cy, cz, 245, 197, 66, 200)
        DrawLine(cx, cy, cz, dx, dy, dz, 245, 197, 66, 200)
        DrawLine(dx, dy, dz, ax, ay, az, 245, 197, 66, 200)
    end

    local active = WBG.drag and WBG.drag.id or WBG.hot

    for i = 1, #hs do
        local hnd = hs[i]
        local on  = (active == hnd.id)
        local a   = on and 255 or 190
        local r, g, b = hnd.r, hnd.g, hnd.b
        if on then r, g, b = 255, 255, 255 end

        if hnd.ring then
            wbgRing(ox, oy, oz, hnd.ring, r, g, b, a)
            wbgRing(ox, oy, oz, hnd.ring * 0.93, r, g, b, math.floor(a * 0.5))
        else
            wbgArrow(ox, oy, oz, hnd.x, hnd.y, hnd.z, r, g, b, a)
            DrawMarker(28, hnd.x, hnd.y, hnd.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                       on and 0.09 or 0.07, on and 0.09 or 0.07, on and 0.09 or 0.07,
                       r, g, b, a, false, false, 2, false, nil, nil, false)
            if hnd.label then
                drawMarkerText(hnd.x, hnd.y, hnd.z + 0.22, hnd.label)
            end
        end
    end

    DrawMarker(28, ox, oy, oz, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
               0.05, 0.05, 0.05, 250, 250, 250, 210,
               false, false, 2, false, nil, nil, false)
end

local function wbgDragStart(cx, cy)
    WBG.cx, WBG.cy = cx, cy
    local hnd = wbgPick(cx, cy)
    if not hnd then
        WBG.hot = nil
        return false
    end

    local _, _, it = wbwSel()
    if not it then return false end

    WBG.hot = hnd.id
    WBG.drag = { id = hnd.id, dx = hnd.dx, dy = hnd.dy, dz = hnd.dz }

    if not hnd.ring then
        local ox, oy, oz = it.pos.x + 0.0, it.pos.y + 0.0, it.pos.z + 0.0
        local s0x, s0y = wbgProject(ox, oy, oz)
        local s1x, s1y = wbgProject(ox + hnd.dx, oy + hnd.dy, oz + hnd.dz)
        if s0x and s1x then
            WBG.drag.ax, WBG.drag.ay = s1x - s0x, s1y - s0y
        else
            WBG.drag.ax, WBG.drag.ay = 0.0, 0.0
        end
    end
    return true
end

local function wbgDragMove(cx, cy)
    local mdx, mdy = cx - WBG.cx, cy - WBG.cy
    WBG.cx, WBG.cy = cx, cy

    local d = WBG.drag
    if not d then
        WBG.hot = (wbgPick(cx, cy) or {}).id
        return false
    end

    local kind, _, it = wbwSel()
    if not it then return false end

    local speed = WBW.speed or 1.0

    if d.id == 'h' then
        it.h = ((((tonumber(it.h) or 0.0) + mdx * 520.0 * speed) % 360) + 360) % 360
        if kind == 's' then
            it.pitch = math.max(-60.0, math.min(60.0,
                (tonumber(it.pitch) or 0.0) + mdy * 260.0 * speed))
        end
        if kind == 'p' then wbwRepaint() end
        return true
    end

    local den = (d.ax or 0.0) * (d.ax or 0.0) + (d.ay or 0.0) * (d.ay or 0.0)
    if den < 1e-9 then return false end
    local metres = ((mdx * d.ax) + (mdy * d.ay)) / den

    if d.id == 'x' or d.id == 'y' or d.id == 'z' then
        it.pos[d.id] = it.pos[d.id] + metres * speed
        if kind == 'p' then wbwRepaint() end

    elseif kind == 's' and d.id == 'width' then
        it.width = math.max(0.5, math.min(40.0,
            (tonumber(it.width) or 6.0) + metres * 2.0 * speed))

    elseif kind == 's' and d.id == 'height' then
        local _, cur = screenSize(it)
        it.height = math.max(0.3, math.min(30.0, cur + metres * 2.0 * speed))
    end
    return true
end

local function wbgDragEnd()
    WBG.drag = nil
end

local function wbcAim()
    if not WBC.on or not WBC.cam then return end
    local _, _, it = wbwSel()
    if not it then return end

    local tx, ty, tz = it.pos.x + 0.0, it.pos.y + 0.0, it.pos.z + 0.0
    if WBC.lx == tx and WBC.ly == ty and WBC.lz == tz
       and WBC.lyaw == WBC.yaw and WBC.lpitch == WBC.pitch and WBC.ldist == WBC.dist then
        return
    end
    WBC.lx, WBC.ly, WBC.lz = tx, ty, tz
    WBC.lyaw, WBC.lpitch, WBC.ldist = WBC.yaw, WBC.pitch, WBC.dist

    local yaw = math.rad(WBC.yaw)
    local pit = math.rad(WBC.pitch)
    local cp  = math.cos(pit)

    SetCamCoord(WBC.cam,
        tx + math.sin(yaw) * cp * WBC.dist,
        ty - math.cos(yaw) * cp * WBC.dist,
        tz - math.sin(pit) * WBC.dist)
    PointCamAtCoord(WBC.cam, tx, ty, tz)
end

local function wbcEnter()
    if WBC.on then return end
    local kind, _, it = wbwSel()
    if not it then return end

    WBC.yaw   = tonumber(it.h) or 0.0
    WBC.pitch = -6.0
    WBC.dist  = (kind == 's') and math.max(4.0, (tonumber(it.width) or 6.0) * 1.5) or 4.5

    WBC.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not WBC.cam then return end
    WBC.on = true
    WBC.lx, WBC.ly, WBC.lz = nil, nil, nil

    wbcAim()
    SetCamActive(WBC.cam, true)
    RenderScriptCams(true, true, 420, true, true)
end

local function wbcLeave()
    if not WBC.on then return end
    WBC.on = false
    RenderScriptCams(false, true, 420, true, true)
    if WBC.cam then DestroyCam(WBC.cam, false) end
    WBC.cam = nil
end

local function wbcOrbit(dx, dy)
    if not WBC.on then return end
    WBC.yaw   = (((WBC.yaw + dx * 420.0) % 360) + 360) % 360
    WBC.pitch = math.max(-80.0, math.min(80.0, WBC.pitch + dy * 260.0))
    wbcAim()
end

local function wbcZoom(dir)
    if not WBC.on then return end
    local step = math.max(0.4, WBC.dist * 0.16)
    WBC.dist = math.max(1.5, math.min(80.0, WBC.dist + (dir < 0 and -step or step)))
    wbcAim()
end

local function wbpAim()
    local cam  = GetFinalRenderedCamCoord()
    local rot  = GetFinalRenderedCamRot(2)
    local pz   = math.rad(rot.z)
    local px   = math.rad(rot.x)
    local cosx = math.cos(px)
    local dx, dy, dz = -math.sin(pz) * cosx, math.cos(pz) * cosx, math.sin(px)

    local far  = 60.0
    local ray  = StartShapeTestRay(cam.x, cam.y, cam.z,
                                   cam.x + dx * far, cam.y + dy * far, cam.z + dz * far,
                                   1 + 16 + 256, playerPed(), 4)
    local _, hit, endCoords = GetShapeTestResult(ray)

    if hit == 1 or hit == true then
        return endCoords.x + 0.0, endCoords.y + 0.0, endCoords.z + 0.0, true
    end

    local ped = playerPed()
    local c   = GetEntityCoords(ped)
    local h   = math.rad(GetEntityHeading(ped))
    local fx, fy = c.x - math.sin(h) * 6.0, c.y + math.cos(h) * 6.0
    local found, gz = GetGroundZFor_3dCoord(fx, fy, c.z + 2.0, false)
    return fx, fy, (found and gz or c.z), false
end

local function wbpTick()
    local x, y, z, hit = wbpAim()
    WBP.x, WBP.y, WBP.z, WBP.ok = x, y, z, hit

    local r, g, b = 235, 62, 62
    DrawMarker(25, x, y, z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
               0.85, 0.85, 0.85, r, g, b, 170, false, false, 2, false, nil, nil, false)
    DrawMarker(28, x, y, z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
               0.13, 0.13, 0.13, r, g, b, 235, false, false, 2, false, nil, nil, false)

    if WBP.kind == 's' then
        local top = z + 1.35
        DrawLine(x, y, z + 0.03, x, y, top, r, g, b, 150)
        DrawMarker(28, x, y, top, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                   0.08, 0.08, 0.08, 245, 197, 66, 220,
                   false, false, 2, false, nil, nil, false)
    end
end

local function wbpPlace()
    if not WBP.on or not WB.edit then return end
    local ped = playerPed()
    local h   = GetEntityHeading(ped)

    if WBP.kind == 's' then
        WB.edit.screens = WB.edit.screens or {}
        WB.edit.screens[#WB.edit.screens + 1] = {
            pos = { x = WBP.x, y = WBP.y, z = WBP.z + 1.35 },
            title = '', enabled = true,
            h = (h + 180.0) % 360, pitch = 0.0, width = 6.0,
            rows = 10, opacity = 255, distance = 35.0
        }
        WBW.sel = 's' .. (#WB.edit.screens - 1)
    else
        WB.edit.podium = WB.edit.podium or {}
        WB.edit.podium[#WB.edit.podium + 1] = { pos = { x = WBP.x, y = WBP.y, z = WBP.z }, h = h }
        WBW.sel = 'p' .. (#WB.edit.podium - 1)
        wbwRepaint()
    end

    WBP.on = false
    WBW.mode = 'move'
end

local function wbwEnter()
    if not WB.edit or WBW.on then return end
    WBW.on, WBW.walk = true, false
    nui({ action = 'close' })
    setFocus(true)
    nui(wbwPayload())

    Citizen.CreateThread(function()
        while WBW.on do
            if WBC.on then wbcAim() end
            if WBP.on then wbpTick() else wbwGizmo() end
            Wait(0)
        end
    end)
end

local function wbwLeave(back)
    WBW.on, WBW.walk = false, false
    SetNuiFocusKeepInput(false)
    wbcLeave()
    nui(wbwPayload())
    if back then
        setFocus(true)
        nui({ action = 'open', page = 'board', theme = Config.UI, brand = Config.Brand,
              sounds = Config.Sounds, text = L, locale = localePayload(),
              defaults = Config.DefaultSettings, silent = true })
        wbEditPush()
    end
end

function wbwAbort()
    if not WBW.on then return end
    WBW.on, WBW.walk = false, false
    SetNuiFocusKeepInput(false)
    wbcLeave()
    WB.edit = nil
    nui(wbwPayload())
    if WB.spawned then
        local p = wbPodium()
        if p then wbSpawn(p) else wbDespawn() end
    end
end

local function wbwWalk(on)
    if not WBW.on then return end
    if on then wbcLeave() end
    WBW.walk = on
    setFocus(not on)
    nui(wbwPayload())
end

RegisterCommand('m5rp_board_walk', function()
    if not WBW.on then return end
    wbwWalk(not WBW.walk)
end, false)
RegisterKeyMapping('m5rp_board_walk', 'M5 Ranked PvP: board editor — walk / edit', 'keyboard', 'F5')

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    wbcLeave()
end)

RegisterNUICallback('boardWorld', function(data, cb)
    local action = tostring(data and data.action or '')

    if action == 'mode' then
        local m = tostring(data.mode or 'move')
        if m == 'move' or m == 'size' or m == 'rotate' then WBW.mode = m end

    elseif action == 'speed' then
        local i = 3
        for n = 1, #WBW_SPEEDS do
            if WBW_SPEEDS[n] == WBW.speed then i = n break end
        end
        i = math.max(1, math.min(#WBW_SPEEDS, i + ((tonumber(data.dir) or 0) < 0 and -1 or 1)))
        WBW.speed = WBW_SPEEDS[i]

    elseif action == 'nudge' then
        wbwNudge(tostring(data.axis or ''), tonumber(data.dir) or 1)

    elseif action == 'here' then
        wbwHere()

    elseif action == 'goto' then
        wbcLeave()
        wbwGoTo()

    elseif action == 'pick' then
        local id = tostring(data.sel or '')
        if id:match('^[sp]%d+$') then WBW.sel = id end

    elseif action == 'walk' then
        wbwWalk(data.on == true)
        cb('ok')
        return

    elseif action == 'grab' then
        local took = (not WBP.on) and wbgDragStart(tonumber(data.x) or 0.5, tonumber(data.y) or 0.5)
        cb(took and 'grab' or 'miss')
        return

    elseif action == 'drag' then
        local moved = wbgDragMove(tonumber(data.x) or 0.5, tonumber(data.y) or 0.5)
        if moved and not WBG.drag then nui(wbwPayload()) end
        cb('ok')
        return

    elseif action == 'drop' then
        wbgDragEnd()
        nui(wbwPayload())
        cb('ok')
        return

    elseif action == 'focus' then
        if data.on == true then wbcEnter() else wbcLeave() end

    elseif action == 'orbit' then
        wbcOrbit(tonumber(data.x) or 0.0, tonumber(data.y) or 0.0)
        cb('ok')
        return

    elseif action == 'zoom' then
        wbcZoom(tonumber(data.dir) or 1)
        cb('ok')
        return

    elseif action == 'place' then
        wbcLeave()
        local k = tostring(data.kind or 's')
        WBP.kind = (k == 'p') and 'p' or 's'
        WBP.on   = true
        WBG.drag, WBG.hot = nil, nil

    elseif action == 'placeHere' then
        wbpPlace()

    elseif action == 'placeCancel' then
        WBP.on = false

    elseif action == 'autoHeight' then
        local kind, _, it = wbwSel()
        if kind == 's' and it then it.height = nil end

    elseif action == 'remove' then
        local kind, n, it = wbwSel()
        if it and WB.edit then
            local list = (kind == 's') and WB.edit.screens or WB.edit.podium
            if #list > 1 or kind == 'p' then
                table.remove(list, n)
                WBW.sel = (#(WB.edit.screens or {}) > 0) and 's0' or 'p0'
                if kind == 'p' then wbwRepaint() end
            end
        end

    elseif action == 'confirm' then
        TriggerServerEvent('m5rp:sv:boardLayout', 'save', WB.edit)
        WB.layout = WB.edit
        wbwLeave(false)
        wbEditClose(false)
        cb('ok')
        return

    elseif action == 'back' then
        wbwLeave(true)
        cb('ok')
        return
    end

    nui(wbwPayload())
    cb('ok')
end)

RegisterNUICallback('boardEdit', function(data, cb)
    local action = tostring(data and data.action or '')

    if action == 'world' then
        WB.edit = data.layout or WB.edit
        WBW.sel = tostring(data.sel or WBW.sel)
        wbwEnter()
        cb('ok')
        return

    elseif action == 'update' then
        WB.edit = data.layout
        if WB.spawned then
            local p = wbPodium()
            if p then wbSpawn(p) else wbDespawn() end
        end

    elseif action == 'here' then
        wbEditPush()

    elseif action == 'goto' then
        WBW.sel = tostring(data.sel or WBW.sel)
        if wbwGoTo() then wbEditPush() end

    elseif action == 'save' then
        TriggerServerEvent('m5rp:sv:boardLayout', 'save', data.layout)
        WB.layout = data.layout
        wbEditClose(false)

    elseif action == 'reset' then
        TriggerServerEvent('m5rp:sv:boardLayout', 'reset')
        WB.layout = nil
        wbEditClose(false)

    elseif action == 'cancel' then
        wbEditClose(false)
    end

    cb('ok')
end)

if Config.ClientCommands.board and Config.ClientCommands.board.enabled then
    RegisterCommand(Config.ClientCommands.board.name, wbEditOpen, false)
end
