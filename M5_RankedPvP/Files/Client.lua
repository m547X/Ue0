

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

local function closeMenu(force)
    if State.uiLocked and not force then return end
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

local function isDown(ped)
    if IsEntityDead(ped) then return true end

    local hp = GetEntityHealth(ped) - 100
    if hp <= 0 then return true end

    local floor = comaFloor()
    if floor and Config.Coma.countsAsDeath ~= false then
        return hp <= floor
    end
    return false
end

local function combatScan(ped)
    ped = ped or playerPed()

    if IsPedShooting(ped) then
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

    if isDown(ped) and not State.reportedDeath then
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

local ACTIVITY_MOVE_SQ = 1.5 * 1.5

local function pushActivity(ped, pos)
    ped = ped or playerPed()
    pos = pos or GetEntityCoords(ped)

    local last = State.lastPos
    local dx, dy, dz = pos.x - last.x, pos.y - last.y, pos.z - last.z
    local moved = (dx * dx + dy * dy + dz * dz) >= ACTIVITY_MOVE_SQ

    local heading
    local acted = moved
    if not acted then
        heading = GetGameplayCamRot(2).z
        acted = math_abs(((heading - State.lastCamHeading + 180) % 360) - 180) >= 4.0
             or IsPedShooting(ped) or IsControlPressed(0, 24)
             or IsControlPressed(0, 25) or IsControlPressed(0, 38)
    end

    if acted then
        State.lastPos = pos
        if heading then State.lastCamHeading = heading end
        local t = ms()
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

                combatScan(ped)
                applyMatchRestrictions()
                boundaryCheck(pos)
                rearmGuard(ped)
                pushActivity(ped, pos)

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
            { l = 'TIME',      v = st.clock }
        }
    end

    local rate = st.hits > 0 and math.floor((st.headshots / st.hits) * 100) or 0
    return {
        { l = 'HITS',      v = tostring(st.hits) },
        { l = 'HEADSHOTS', v = tostring(st.headshots) },
        { l = 'HS RATE',   v = rate .. '%' },
        { l = 'TIME',      v = st.clock }
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
    spawned = false,
    sent    = false,
    layout  = nil,
    edit    = nil
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
        local scc = c.screens or {}
        local pcc = c.podium  or {}
        wbFromConfig.screensEnabled = scc.enabled ~= false
        wbFromConfig.podiumEnabled  = pcc.enabled ~= false
        for i = 1, #wbFromConfig.screens do
            local spot = (scc.spots or {})[i]
            if spot then wbFromConfig.screens[i].enabled = spot.enabled ~= false end
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
            scale    = tonumber(sc.scale) or 1.0,
            width    = 1.0,
            rows     = tonumber(sc.rows) or 10,
            opacity  = tonumber(sc.opacity) or 190,
            distance = tonumber(sc.distance) or 18.0
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

local WB_COLS = {
    { key = 'position', head = '#',      w = 0.000, align = 'left',   tint = true  },
    { key = 'name',     head = 'PLAYER', w = 0.026, align = 'left'                 },
    { key = 'kills',    head = 'K',      w = 0.560, align = 'right'                },
    { key = 'deaths',   head = 'D',      w = 0.660, align = 'right'                },
    { key = 'wins',     head = 'W',      w = 0.760, align = 'right', good = true   },
    { key = 'losses',   head = 'L',      w = 0.845, align = 'right', bad  = true   },
    { key = 'kd',       head = 'K/D',    w = 0.930, align = 'right', warm = true   },
    { key = 'rp',       head = 'RP',     w = 1.000, align = 'right', tint = true   }
}

local function drawScreen(spot, dist)
    local far   = tonumber(spot.distance) or 18.0
    local scale = (tonumber(spot.scale) or 1.0) * (1.0 - (dist / (far * 2.4)))
    if scale < 0.22 then scale = 0.22 end

    local shown = math.min(tonumber(spot.rows) or 10, #WB.rows)
    local alpha = math.floor(tonumber(spot.opacity) or 190)

    local lineH = 0.020 * scale
    local width = 0.230 * scale * (tonumber(spot.width) or 1.0)
    local head  = 0.042 * scale
    local hdr   = 0.016 * scale
    local body  = lineH * math.max(shown, 1)
    local total = head + hdr + body + (0.012 * scale)

    local left  = -(width / 2) + (0.010 * scale)
    local right =  (width / 2) - (0.010 * scale)
    local span  = right - left

    local function colX(c)
        return left + (span * c.w)
    end

    SetDrawOrigin(spot.pos.x, spot.pos.y, spot.pos.z, 0)

    DrawRect(0.0, 0.0, width, total, 8, 10, 14, alpha)
    DrawRect(0.0, -(total / 2) + (head / 2), width, head, 150, 28, 42, math.min(255, alpha + 45))
    DrawRect(0.0, -(total / 2) + head, width, 0.0016 * scale, 210, 45, 60, 255)

    wbText(spot.title or 'LEADERBOARD', 0.0, -(total / 2) + (head / 2) - (0.012 * scale),
           0.46 * scale, 245, 245, 250, 255, 'centre')
    if WB.season then
        wbText(WB.season, 0.0, -(total / 2) + (head / 2) + (0.004 * scale),
               0.26 * scale, 205, 175, 180, 210, 'centre')
    end

    local y = -(total / 2) + head + (0.004 * scale)

    for i = 1, #WB_COLS do
        local c = WB_COLS[i]
        wbText(c.head, colX(c), y, 0.25 * scale, 150, 158, 170, 220, c.align, right)
    end
    y = y + hdr
    DrawRect(0.0, y - (0.002 * scale), width - (0.008 * scale), 0.0008 * scale, 90, 96, 108, 160)

    if shown == 0 then
        wbText('NO PLAYERS ON THE BOARD YET', 0.0, y + (lineH * 0.6),
               0.30 * scale, 150, 158, 170, 210, 'centre')
        ClearDrawOrigin()
        return
    end

    for i = 1, shown do
        local row = WB.rows[i]
        local r, g, b = row.r or 220, row.g or 220, row.b or 225
        local cells = row.cells

        if i <= 3 then
            DrawRect(0.0, y + (lineH / 2) - (0.002 * scale), width - (0.008 * scale),
                     lineH, r, g, b, 38)
        elseif i % 2 == 0 then
            DrawRect(0.0, y + (lineH / 2) - (0.002 * scale), width - (0.008 * scale),
                     lineH, 255, 255, 255, 8)
        end

        for n = 1, #WB_COLS do
            local c  = WB_COLS[n]
            local cr, cg, cb = 225, 228, 234
            if c.tint then cr, cg, cb = r, g, b
            elseif c.good then cr, cg, cb = 70, 210, 140
            elseif c.bad  then cr, cg, cb = 220, 80, 90
            elseif c.warm then cr, cg, cb = 235, 190, 90 end

            wbText(cells and cells[n] or '-', colX(c), y,
                   0.29 * scale, cr, cg, cb, 255, c.align, right)
        end

        y = y + lineH
    end

    ClearDrawOrigin()
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

                    WB.peds[#WB.peds + 1] = ped
                end
            end
        end
    end

    WB.spawned = #WB.peds > 0
end

local function wbFormatRows()
    for i = 1, #WB.rows do
        local row = WB.rows[i]
        local cells = {}
        for n = 1, #WB_COLS do
            local v = row[WB_COLS[n].key]
            cells[n] = (v == nil) and '-' or tostring(v)
        end
        row.cells = cells
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
    wbFormatRows()
    if WB.spawned then
        local cfg = wbPodium()
        if cfg then wbSpawn(cfg) else wbDespawn() end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    wbDespawn()
end)

local WB_FAR  = 2000
local WB_NEAR = 400

function wbTick(me, podiumAcc)
    local sleep = WB_FAR

    if not WB.ready then return sleep, podiumAcc end

    local screens = wbScreens()
    if screens then
        for i = 1, #screens do
            local spot = screens[i]
            local far  = tonumber(spot.distance) or 18.0
            if spot.enabled ~= false and spot.pos then
                local d = #(me - vec3(spot.pos))
                if d <= far then
                    if World3dToScreen2d(spot.pos.x, spot.pos.y, spot.pos.z) then
                        sleep = 0
                        drawScreen(spot, d)
                    elseif sleep > WB_NEAR then
                        sleep = WB_NEAR
                    end
                elseif d <= far * 2.5 and sleep > WB_NEAR then
                    sleep = WB_NEAR
                end
            end
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
        local near = false
        for i = 1, #podium.podium do
            local spot = podium.podium[i]
            if spot.pos and #(me - vec3(spot.pos)) <= podium.podiumDistance then
                near = true break
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
            local p   = WB.peds[i]
            local row = WB.rows[i]
            if row and DoesEntityExist(p) then
                local pos = GetEntityCoords(p)
                if #(me - pos) <= 14.0
                   and World3dToScreen2d(pos.x, pos.y, pos.z + 1.05) then
                    sleep = 0
                    SetDrawOrigin(pos.x, pos.y, pos.z + 1.05, 0)
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

        if not WB.sent then
            local ped = playerPed()
            if ped and ped ~= 0 and not IsPedInjured(ped) then
                WB.sent = true
                TriggerServerEvent('m5rp:sv:worldBoard', GetEntityModel(ped))
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
        print(('  screen : pos = vector3(%.2f, %.2f, %.2f)')
            :format(c.x, c.y, c.z + 1.35))
        print(('  podium : { pos = vector3(%.2f, %.2f, %.2f), h = %.1f, anim = nil },')
            :format(c.x, c.y, c.z, h))
        print('[M5RP] the screen line floats at eye height; the podium line stands on the ground')
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
            scale = tonumber(s.scale) or 1.0, width = tonumber(s.width) or 1.0,
            rows = tonumber(s.rows) or 10, opacity = tonumber(s.opacity) or 190,
            distance = tonumber(s.distance) or 18.0
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

local function wbEditPush()
    nui({ action = 'boardEdit', layout = WB.edit,
          here = (function()
              local c = GetEntityCoords(playerPed())
              return { x = c.x, y = c.y, z = c.z,
                       h = GetEntityHeading(playerPed()) }
          end)() })
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
            scale = 1.0, width = 1.0, rows = 10, opacity = 190, distance = 18.0
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

RegisterNUICallback('boardEdit', function(data, cb)
    local action = tostring(data and data.action or '')

    if action == 'update' then
        WB.edit = data.layout
        if WB.spawned then
            local p = wbPodium()
            if p then wbSpawn(p) else wbDespawn() end
        end

    elseif action == 'here' then
        wbEditPush()

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
