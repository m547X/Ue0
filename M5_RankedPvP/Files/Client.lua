


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
    local cfg = Config.Loadout or {}
    if cfg.rearmWhenEmpty == false then return end
    if not State.inMatch or not State.alive then return end

    local t = ms()
    if t < nextRearm then return end

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

local function setFocus(on)
    SetNuiFocus(on, on)
    SetNuiFocusKeepInput(false)
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

local function closeMenu()
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


local HEAD_BONES = {}
for _, bone in ipairs({ 31086, 39317, 12844, 20178, 21550 }) do HEAD_BONES[bone] = true end

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

    if isHead and Config.Headshot.enabled and Config.Headshot.oneShotKill
       and State.settings.headshotOneShot ~= false then
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


local function pushActivity(ped, pos)
    ped = ped or playerPed()
    pos = pos or GetEntityCoords(ped)
    local heading = GetGameplayCamRot(2).z

    local movedOk = #(pos - State.lastPos) >= 1.5
    local camOk   = math_abs(((heading - State.lastCamHeading + 180) % 360) - 180) >= 4.0
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

local function drawTeammateTags(myPed, myPos)
    if not Config.Display.teammateNameplates or State.ffa then return end

    local teams = State.teamOfServerId
    if not teams then return end

    local myTeam = State.team
    local names  = State.nameOfServerId
    local range  = Config.Display.nameplateDistance
    myPed = myPed or playerPed()
    myPos = myPos or GetEntityCoords(myPed)

    for _, player in ipairs(GetActivePlayers()) do
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

