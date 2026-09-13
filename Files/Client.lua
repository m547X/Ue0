LocationManager = {}
local _spots      = {}
local _activeId   = nil
local function log(msg)
    if not (Config.Debug and Config.Debug.client) then
        return
    end
    print('^3[M5_iCreator/Location]^0 ' .. tostring(msg))
end
function LocationManager.Init()
    _spots = {}
    for _, spot in ipairs(Config.DefaultSpots or {}) do
        table.insert(_spots, spot)
    end
    local custom = GlobalState.CustomSpots
    if custom then
        for _, spot in ipairs(custom) do
            table.insert(_spots, spot)
        end
    end
    if #_spots > 0 and not _activeId then
        _activeId = _spots[1].id
    end
    log('Initialized with ' .. #_spots .. ' spots.')
end
function LocationManager.GetAll()
    return _spots
end
function LocationManager.GetById(id)
    for _, s in ipairs(_spots) do
        if s.id == id then return s end
    end
    return nil
end
function LocationManager.GetActive()
    return LocationManager.GetById(_activeId)
end
function LocationManager.SetActiveById(id)
    if LocationManager.GetById(id) then
        _activeId = id
        return true
    end
    return false
end
function LocationManager.Upsert(spot)
    for i, s in ipairs(_spots) do
        if s.id == spot.id then
            _spots[i] = spot
            if _activeId == spot.id then end
            return
        end
    end
    table.insert(_spots, spot)
end
function LocationManager.Remove(id)
    for i, s in ipairs(_spots) do
        if s.id == id then
            table.remove(_spots, i)
            if _activeId == id then
                _activeId = _spots[1] and _spots[1].id or nil
            end
            return
        end
    end
end
function LocationManager.GenerateId()
    return 'spot_' .. tostring(GetGameTimer())
end
function LocationManager.LoadSpot(spot)
    if spot.ipl then
        for _, ipl in ipairs(spot.ipl) do
            if not IsIplActive(ipl) then
                RequestIpl(ipl)
            end
        end
        if spot.ipl[1] then
            local t = 0
            while not IsIplActive(spot.ipl[1]) and t < 80 do
                Wait(100)
                t = t + 1
            end
        end
    end
    if spot.interiorCoords then
        local ic = spot.interiorCoords
        local interiorId = GetInteriorAtCoords(ic.x, ic.y, ic.z)
        if spot.interiorProps then
            for _, prop in ipairs(spot.interiorProps) do
                EnableInteriorProp(interiorId, prop)
            end
        end
    end
    if spot.weather and spot.weather ~= '' then
        SetWeatherTypePersist(spot.weather)
        SetWeatherTypeNow(spot.weather)
        SetWeatherTypeNowPersist(spot.weather)
    end
    if spot.timeHour then
        NetworkOverrideClockTime(spot.timeHour, spot.timeMin or 0, 0)
    end
end
function LocationManager.TeleportPlayer(spot)
    local ped = PlayerPedId()
    local pc  = spot.playerCoords
    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(pc.x, pc.y, pc.z)
    local t = 0
    while not HasCollisionLoadedAroundEntity(ped) and t < 30 do
        Wait(100)
        t = t + 1
    end
    DoScreenFadeOut(500)
    Wait(550)
    SetEntityCoords(ped, pc.x, pc.y, pc.z, false, false, false, false)
    SetEntityHeading(ped, pc.w or 0.0)
    DoScreenFadeIn(700)
    FreezeEntityPosition(ped, false)
end
PreviewManager = {}
VehiclePlacer  = {}
local _pvActive  = false
local _pvVeh     = nil
local _pvCam     = nil
local _pvSpot    = nil
local _pvRotate  = false
local _vpActive  = false
local _vpVeh     = nil
local _vpOnSave  = nil
local _vpOnCancel = nil
local KEY_STAMP  = 74
local KEY_SAVE   = 201
-- 202 = Backspace، 177 = Backspace/ESC، 200 = ESC.
-- الرقم 200 وحده يفتح قائمة اللعبة عندما لا تكون الأزرار معطّلة،
-- لذلك نقبل الثلاثة معاً في كل مكان يُستخدم فيه الإلغاء.
local CANCEL_KEYS = { 202, 177, 200 }
function IsCancelPressed(disabled)
    for _, key in ipairs(CANCEL_KEYS) do
        if disabled then
            if IsDisabledControlJustPressed(0, key) then return true end
        elseif IsControlJustPressed(0, key) then
            return true
        end
    end
    return false
end
-- انتظار يمكن قطعه: يرجع false إذا توقفت الجلسة أثناء الانتظار.
function WaitOrStop(ms, stillRunning)
    local waited = 0
    while waited < ms do
        if not stillRunning() then return false end
        Wait(50)
        waited = waited + 50
    end
    return stillRunning()
end
RegisterFontFile('A9eelsh')
fontId = RegisterFontId('A9eelsh')
local function log(m)
    if not (Config.Debug and Config.Debug.client) then
        return
    end
    print('^5[Preview]^0 ' .. tostring(m))
end
local function DrawHUDLine(text, x, y, r, g, b)
    SetTextFont(fontId)
    SetTextScale(0.33, 0.33)
    SetTextColour(r or 0, g or 210, b or 255, 245)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end
local function SafeDelete(ent)
    if ent and DoesEntityExist(ent) then DeleteEntity(ent) end
end
local function SpawnPreviewVehicle(model, vc)
    local hash = GetHashKey(model or Config.DefaultTestVehicle)
    if not IsModelInCdimage(hash) then
        log('Model not found in CDImage: ' .. tostring(model))
        return nil
    end
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 50 do Wait(100); t = t + 1 end
    if not HasModelLoaded(hash) then return nil end
    local veh = CreateVehicle(hash, vc.x, vc.y, vc.z, vc.w or 0.0, false, true)
    FreezeEntityPosition(veh, true)
    SetEntityCollision(veh, false, false)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleEngineOn(veh, true, true, false)
    SetModelAsNoLongerNeeded(hash)
    return veh
end
function PreviewManager.Start(spot, model)
    if _pvActive then PreviewManager.Stop() end
    _pvActive = true
    _pvSpot   = spot
    _pvRotate = false
    LocationManager.LoadSpot(spot)
    LocationManager.TeleportPlayer(spot)
    Wait(600)
    _pvVeh = SpawnPreviewVehicle(model, spot.vehicleCoords)
    local cfg = spot.camera
    _pvCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        cfg.pos.x, cfg.pos.y, cfg.pos.z,
        cfg.rot.x, 0.0,       cfg.rot.z,
        cfg.fov or 50.0, false, 0)
    SetCamActive(_pvCam, true)
    RenderScriptCams(true, false, 0, true, true)
    local vc = spot.vehicleCoords
    SetFocusPosAndVel(vc.x, vc.y, vc.z, 0.0, 0.0, 0.0)
    DisplayHud(false)
    DisplayRadar(false)
    Citizen.CreateThread(function()
        while _pvActive do
            local l = spot.light
            if l then
                local p, c = l.pos, l.color or {r=255,g=255,b=255}
                DrawLightWithRange(p.x, p.y, p.z+2.0,
                    c.r, c.g, c.b, l.range or 35.0, l.intensity or 12.0)
                DrawLightWithRange(p.x-6.0, p.y+4.0, p.z+3.0,
                    200, 220, 255, 20.0, 5.0)
            end
            Wait(0)
        end
    end)
    log('Preview started: ' .. spot.name)
end
function PreviewManager.Stop()
    if not _pvActive then return end
    _pvActive = false
    _pvRotate = false
    SafeDelete(_pvVeh) ; _pvVeh = nil
    if _pvCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(_pvCam, false)
        _pvCam = nil
    end
    ClearFocus()
    DisplayHud(true)
    DisplayRadar(true)
    log('Preview stopped.')
end
function PreviewManager.ChangeVehicle(model)
    if not _pvActive or not _pvSpot then return end
    SafeDelete(_pvVeh)
    _pvVeh = SpawnPreviewVehicle(model, _pvSpot.vehicleCoords)
end
function PreviewManager.ToggleRotation(speed)
    _pvRotate = not _pvRotate
    if _pvRotate then
        Citizen.CreateThread(function()
            while _pvRotate and _pvActive and _pvVeh and DoesEntityExist(_pvVeh) do
                SetEntityHeading(_pvVeh, GetEntityHeading(_pvVeh) + (speed or 0.4))
                Wait(0)
            end
        end)
    end
end
function PreviewManager.IsActive()   return _pvActive  end
function PreviewManager.IsRotating() return _pvRotate  end
function PreviewManager.GetSpot()    return _pvSpot    end
function VehiclePlacer.Start(spot, onSave, onCancel)
    if _vpActive then return end
    _vpActive   = true
    _vpOnSave   = onSave
    _vpOnCancel = onCancel
    LocationManager.LoadSpot(spot)
    LocationManager.TeleportPlayer(spot)
    Wait(600)
    _vpVeh = SpawnPreviewVehicle(Config.DefaultTestVehicle, spot.vehicleCoords)
    Citizen.CreateThread(function()
        while _vpActive do
            DrawHUDLine('[ H ]  Place vehicle at your position',     0.5, 0.87, 0,   210, 255)
            DrawHUDLine('[ Enter ]  Save vehicle position',          0.5, 0.90, 100, 255, 100)
            DrawHUDLine('[ Backspace ]  Cancel placement',           0.5, 0.93, 255, 150,  80)
            if IsControlJustPressed(0, KEY_STAMP) then
                local ped = PlayerPedId()
                local co  = GetEntityCoords(ped)
                local h   = GetEntityHeading(ped)
                if _vpVeh and DoesEntityExist(_vpVeh) then
                    SetEntityCoords(_vpVeh, co.x, co.y, co.z, false, false, false, false)
                    SetEntityHeading(_vpVeh, h)
                end
            end
            if IsControlJustPressed(0, KEY_SAVE) and _vpVeh and DoesEntityExist(_vpVeh) then
                local co = GetEntityCoords(_vpVeh)
                local h  = GetEntityHeading(_vpVeh)
                VehiclePlacer._Finish({ x=co.x, y=co.y, z=co.z, w=h }, true)
                return
            end
            if IsCancelPressed(false) then
                VehiclePlacer._Finish(nil, false)
                return
            end
            Wait(0)
        end
    end)
end
function VehiclePlacer._Finish(coords, confirmed)
    _vpActive = false
    SafeDelete(_vpVeh) ; _vpVeh = nil
    if confirmed and _vpOnSave   then _vpOnSave(coords)   end
    if not confirmed and _vpOnCancel then _vpOnCancel()   end
end
function VehiclePlacer.IsActive() return _vpActive end
CameraEditor = {}
local _active    = false
local _cam       = nil
local _pos       = vector3(0, 0, 0)
local _rot       = vector3(0, 0, 0)
local _fov       = 50.0
local _onSave    = nil
local _onCancel  = nil
local CTRL = {
    MOUSE_LR      = 1,
    MOUSE_UD      = 2,
    FORWARD       = 32,
    BACKWARD      = 33,
    LEFT          = 34,
    RIGHT         = 35,
    UP            = 22,
    DOWN          = 36,
    FAST          = 21,
    SCROLL_UP     = 14,
    SCROLL_DOWN   = 15,
    SAVE          = 201,
    CANCEL        = 200,
}
local function DrawLine(text, x, y, r, g, b)
    SetTextFont(4)
    SetTextScale(0.32, 0.32)
    SetTextColour(r or 0, g or 210, b or 255, 245)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end
local function DrawHUD()
    local lines = {
        { ('Pos  %.3f  %.3f  %.3f'):format(_pos.x, _pos.y, _pos.z) },
        { ('Rot  %.2f  0.00  %.2f'):format(_rot.x, _rot.z) },
        { ('FOV  %.1f deg'):format(_fov) },
        { '' },
        { 'WASD  =  Move   |  Space / Ctrl  =  Up / Down', 255, 255, 100 },
        { 'Mouse  =  Look  |  Scroll  =  FOV', 255, 255, 100 },
        { 'Shift  =  Fast  |  Enter  =  Save  |  Backspace  =  Cancel', 255, 200, 100 },
    }
    local y = 0.020
    for _, row in ipairs(lines) do
        DrawLine(row[1], 0.013, y, row[2], row[3], row[4])
        y = y + 0.028
    end
end
local function CalcVectors()
    local pitchRad   = math.rad(_rot.x)
    local headingRad = math.rad(_rot.z)
    local sinH = math.sin(headingRad)
    local cosH = math.cos(headingRad)
    local cosP = math.cos(pitchRad)
    local sinP = math.sin(pitchRad)
    local forward = vector3(-sinH * cosP,  cosH * cosP,  sinP)
    local right   = vector3( cosH,         sinH,         0.0)
    return forward, right
end
function CameraEditor.Start(spot, onSave, onCancel)
    if _active then return end
    _active   = true
    _onSave   = onSave
    _onCancel = onCancel
    local cfg = spot.camera
    _pos = vector3(cfg.pos.x, cfg.pos.y, cfg.pos.z)
    _rot = vector3(cfg.rot.x, 0.0, cfg.rot.z)
    _fov = cfg.fov or 50.0
    _cam = CreateCamWithParams(
        'DEFAULT_SCRIPTED_CAMERA',
        _pos.x, _pos.y, _pos.z,
        _rot.x, 0.0,    _rot.z,
        _fov, false, 0
    )
    SetCamActive(_cam, true)
    RenderScriptCams(true, false, 0, true, true)
    Citizen.CreateThread(function()
        while _active do
            DisableAllControlActions(0)
            local mX = GetDisabledControlNormal(0, CTRL.MOUSE_LR)
            local mY = GetDisabledControlNormal(0, CTRL.MOUSE_UD)
            _rot = vector3(
                math.max(-89.9, math.min(89.9, _rot.x - mY * Config.CameraEditor.rotateSpeed * 8.0)),
                0.0,
                _rot.z - mX * Config.CameraEditor.rotateSpeed * 8.0
            )
            local speed = IsDisabledControlPressed(0, CTRL.FAST)
                and Config.CameraEditor.fastMoveSpeed
                or  Config.CameraEditor.moveSpeed
            local forward, right = CalcVectors()
            local delta          = vector3(0, 0, 0)
            if IsDisabledControlPressed(0, CTRL.FORWARD)  then delta = delta + forward * speed end
            if IsDisabledControlPressed(0, CTRL.BACKWARD) then delta = delta - forward * speed end
            if IsDisabledControlPressed(0, CTRL.LEFT)     then delta = delta - right   * speed end
            if IsDisabledControlPressed(0, CTRL.RIGHT)    then delta = delta + right   * speed end
            if IsDisabledControlPressed(0, CTRL.UP)       then
                delta = vector3(delta.x, delta.y, delta.z + speed)
            end
            if IsDisabledControlPressed(0, CTRL.DOWN)     then
                delta = vector3(delta.x, delta.y, delta.z - speed)
            end
            _pos = _pos + delta
            if IsDisabledControlJustPressed(0, CTRL.SCROLL_UP) then
                _fov = math.max(Config.CameraEditor.fovMin, _fov - Config.CameraEditor.fovStep)
            end
            if IsDisabledControlJustPressed(0, CTRL.SCROLL_DOWN) then
                _fov = math.min(Config.CameraEditor.fovMax, _fov + Config.CameraEditor.fovStep)
            end
            SetCamCoord(_cam, _pos.x, _pos.y, _pos.z)
            SetCamRot(_cam, _rot.x, 0.0, _rot.z, 2)
            SetCamFov(_cam, _fov)
            DrawHUD()
            if IsDisabledControlJustPressed(0, CTRL.SAVE) then
                CameraEditor.Save()
                return
            end
            if IsCancelPressed(true) then
                CameraEditor.Cancel()
                return
            end
            Wait(0)
        end
    end)
end
function CameraEditor.Save()
    if not _active then return end
    _active = false
    local saved = CameraEditor.GetCurrentData()
    CameraEditor._Cleanup()
    if _onSave then _onSave(saved) end
end
function CameraEditor.Cancel()
    if not _active then return end
    _active = false
    CameraEditor._Cleanup()
    if _onCancel then _onCancel() end
end
function CameraEditor.GetCurrentData()
    return {
        pos = { x = _pos.x, y = _pos.y, z = _pos.z },
        rot = { x = _rot.x, y = 0.0,    z = _rot.z },
        fov = _fov,
    }
end
function CameraEditor.IsActive()
    return _active
end
function CameraEditor._Cleanup()
    RenderScriptCams(false, false, 0, true, true)
    if _cam then
        DestroyCam(_cam, false)
        _cam = nil
    end
end
UIManager = {}
local _open = false
function UIManager.Open()
    if _open then return end
    _open = true
    SetNuiFocus(true, true)
    UIManager.SyncSpots()
    UIManager.SyncStats()
    SendNUIMessage({ action = 'open' })
end
function UIManager.Close()
    if not _open then return end
    _open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end
function UIManager.Toggle()
    if _open then UIManager.Close() else UIManager.Open() end
end
function UIManager.IsOpen() return _open end
function UIManager.SyncSpots()
    local all    = LocationManager.GetAll()
    local active = LocationManager.GetActive()
    local list   = {}
    for _, s in ipairs(all) do
        table.insert(list, {
            id          = s.id,
            name        = s.name,
            isActive    = active and active.id == s.id,
            isDefault   = s.isDefault or false,
            weather     = s.weather     or 'EXTRASUNNY',
            timeHour    = s.timeHour    or 12,
            timeMin     = s.timeMin     or 0,
            autoRotate  = s.autoRotate  or false,
            rotateSpeed = s.rotateSpeed or 0.4,
            vehicleCoords = s.vehicleCoords,
        })
    end
    SendNUIMessage({ action = 'updateSpots', spots = list })
    if active then
        SendNUIMessage({ action = 'activeSpot', name = active.name })
    end
end
-- إحصائية مصدر السيارات: الإجمالي وكم سيارة ما زالت بدون صورة.
function UIManager.SyncStats()
    local vehicles = GlobalState.VehiclesFromDB or {}
    local images   = GlobalState.VehicleImages  or {}
    local pending  = 0
    for _, v in ipairs(vehicles) do
        local img = images[v.model]
        if not img or not img.url or img.url == '' then
            pending = pending + 1
        end
    end
    SendNUIMessage({
        action  = 'vehicleStats',
        source  = GlobalState.VehicleSource or 'config',
        total   = #vehicles,
        pending = pending,
    })
end
function UIManager.Status(msg, isErr)
    SendNUIMessage({ action = 'status', message = msg, isError = isErr or false })
end
RegisterNUICallback('close', function(_, cb)
    UIManager.Close() ; cb('ok')
end)
RegisterNUICallback('selectSpot', function(data, cb)
    LocationManager.SetActiveById(data.id)
    UIManager.SyncSpots()
    cb('ok')
end)
RegisterNUICallback('previewSpot', function(data, cb)
    local spot = LocationManager.GetById(data.id)
    if not spot then UIManager.Status('Spot not found', true) ; cb('ok') return end
    Citizen.CreateThread(function()
        if PreviewManager.IsActive() then PreviewManager.Stop() end
        PreviewManager.Start(spot, data.testModel or Config.DefaultTestVehicle)
    end)
    UIManager.Status('Preview: ' .. spot.name)
    cb('ok')
end)
RegisterNUICallback('stopPreview', function(_, cb)
    PreviewManager.Stop()
    UIManager.Status('Preview stopped')
    cb('ok')
end)
RegisterNUICallback('changeTestVehicle', function(data, cb)
    if PreviewManager.IsActive() then
        PreviewManager.ChangeVehicle(data.model)
        UIManager.Status('Vehicle: ' .. data.model)
    end
    cb('ok')
end)
RegisterNUICallback('toggleRotation', function(data, cb)
    PreviewManager.ToggleRotation(data.speed or 0.4)
    local st = PreviewManager.IsRotating() and 'On' or 'Off'
    UIManager.Status('Rotation: ' .. st)
    cb('ok')
end)
RegisterNUICallback('startScreenshot', function(_, cb)
    local spot = LocationManager.GetActive()
    if not spot then UIManager.Status('Select an active spot first', true) ; cb('ok') return end
    UIManager.Close()
    Citizen.CreateThread(function()
        TriggerEvent('M5_iCreator:startScreenshot', spot)
    end)
    cb('ok')
end)
-- تصدير جدول الجراج / ملف الجراج المحدّث.
RegisterNUICallback('exportGarage', function(_, cb)
    TriggerServerEvent('M5_iCreator:exportGarage', false)
    UIManager.Status('Garage export requested')
    cb('ok')
end)
-- إعادة قراءة ملف الجراج أو قاعدة البيانات.
RegisterNUICallback('reloadVehicles', function(_, cb)
    TriggerServerEvent('M5_iCreator:reloadVehicles')
    UIManager.Status('Reloading the vehicle list...')
    cb('ok')
end)
RegisterNUICallback('loadVehicles', function(_, cb)
    local spot = LocationManager.GetActive()
    if not spot then UIManager.Status('Select an active spot first', true) ; cb('ok') return end
    UIManager.Close()
    Citizen.CreateThread(function()
        TriggerEvent('M5_iCreator:loadVehicles', spot)
    end)
    cb('ok')
end)
RegisterNUICallback('usePlayerPos', function(data, cb)
    local spot = LocationManager.GetById(data.id)
    if not spot then cb('ok') return end
    local ped  = PlayerPedId()
    local co   = GetEntityCoords(ped)
    local head = GetEntityHeading(ped)
    spot.vehicleCoords = { x = co.x, y = co.y, z = co.z, w = head }
    LocationManager.Upsert(spot)
    TriggerServerEvent('M5_iCreator:upsertSpot', spot)
    UIManager.SyncSpots()
    UIManager.Status(string.format('Vehicle spawn: %.1f, %.1f, %.1f', co.x, co.y, co.z))
    SendNUIMessage({ action = 'updateVC', coords = { x=co.x, y=co.y, z=co.z, w=head } })
    cb({ x = co.x, y = co.y, z = co.z, w = head })
end)
RegisterNUICallback('openVehiclePlacer', function(data, cb)
    local spot = LocationManager.GetById(data.id)
    if not spot then cb('ok') return end
    UIManager.Close()
    Citizen.CreateThread(function()
        if PreviewManager.IsActive() then PreviewManager.Stop() end
        VehiclePlacer.Start(
            spot,
            function(coords)
                spot.vehicleCoords = coords
                LocationManager.Upsert(spot)
                TriggerServerEvent('M5_iCreator:upsertSpot', spot)
                UIManager.Open()
                UIManager.SyncSpots()
                SendNUIMessage({ action = 'updateVC', coords = coords })
                UIManager.Status(string.format(
                    'Saved vehicle spawn: %.1f, %.1f, %.1f',
                    coords.x, coords.y, coords.z))
            end,
            function()
                UIManager.Open()
                UIManager.Status('Vehicle placement cancelled')
            end
        )
    end)
    cb('ok')
end)
RegisterNUICallback('openCameraEditor', function(data, cb)
    local spot = LocationManager.GetById(data.id)
    if not spot then cb('ok') return end
    UIManager.Close()
    Citizen.CreateThread(function()
        LocationManager.LoadSpot(spot)
        LocationManager.TeleportPlayer(spot)
        Wait(800)
        if PreviewManager.IsActive() then PreviewManager.Stop() end
        PreviewManager.Start(spot, Config.DefaultTestVehicle)
        Wait(500)
        CameraEditor.Start(spot,
            function(camData)
                spot.camera = camData
                LocationManager.Upsert(spot)
                TriggerServerEvent('M5_iCreator:upsertSpot', spot)
                PreviewManager.Stop()
                UIManager.Open()
                UIManager.Status('Saved camera: ' .. spot.name)
            end,
            function()
                PreviewManager.Stop()
                UIManager.Open()
                UIManager.Status('Camera edit cancelled')
            end
        )
    end)
    cb('ok')
end)
RegisterNUICallback('createSpot', function(data, cb)
    local ped  = PlayerPedId()
    local co   = GetEntityCoords(ped)
    local head = GetEntityHeading(ped)
    local s = {
        id            = LocationManager.GenerateId(),
        name          = data.name or 'New Spot',
        ipl           = {},
        playerCoords  = { x=co.x,       y=co.y,       z=co.z, w=head },
        vehicleCoords = { x=co.x+3.0,   y=co.y,       z=co.z, w=head },
        camera = {
            pos = { x=co.x-5.0, y=co.y-5.0, z=co.z+2.0 },
            rot = { x=-10.0, y=0.0, z=head+45.0 },
            fov = 50.0,
        },
        light = {
            pos       = { x=co.x,  y=co.y,  z=co.z+4.0 },
            color     = { r=255, g=250, b=230 },
            range     = 35.0,
            intensity = 12.0,
        },
        weather     = 'EXTRASUNNY',
        timeHour    = 12,
        timeMin     = 0,
        autoRotate  = false,
        rotateSpeed = 0.4,
        isDefault   = false,
    }
    LocationManager.Upsert(s)
    LocationManager.SetActiveById(s.id)
    TriggerServerEvent('M5_iCreator:upsertSpot', s)
    UIManager.SyncSpots()
    UIManager.Status('Created spot: ' .. s.name)
    cb({ id = s.id })
end)
RegisterNUICallback('deleteSpot', function(data, cb)
    local spot = LocationManager.GetById(data.id)
    if spot and spot.isDefault then
        UIManager.Status('Default spots cannot be deleted', true)
        cb('ok') return
    end
    LocationManager.Remove(data.id)
    TriggerServerEvent('M5_iCreator:deleteSpot', data.id)
    UIManager.SyncSpots()
    UIManager.Status('Spot deleted')
    cb('ok')
end)
RegisterNUICallback('updateSpotSettings', function(data, cb)
    local spot = LocationManager.GetById(data.id)
    if not spot then cb('ok') return end
    if data.name        then spot.name        = data.name                    end
    if data.weather     then spot.weather     = data.weather                 end
    if data.timeHour    then spot.timeHour    = tonumber(data.timeHour)      end
    if data.timeMin     then spot.timeMin     = tonumber(data.timeMin)       end
    if data.rotateSpeed then spot.rotateSpeed = tonumber(data.rotateSpeed)   end
    if data.autoRotate  ~= nil then spot.autoRotate = data.autoRotate        end
    LocationManager.Upsert(spot)
    TriggerServerEvent('M5_iCreator:upsertSpot', spot)
    UIManager.SyncSpots()
    UIManager.Status('Settings saved')
    cb('ok')
end)
RegisterNetEvent('M5_iCreator:syncSpots')
AddEventHandler('M5_iCreator:syncSpots', function(customSpots)
    for _, s in ipairs(customSpots) do
        if not s.isDefault then LocationManager.Upsert(s) end
    end
    if UIManager.IsOpen() then UIManager.SyncSpots() end
end)
-- السيرفر أعاد قراءة ملف الجراج أو قاعدة البيانات.
RegisterNetEvent('M5_iCreator:vehiclesUpdated')
AddEventHandler('M5_iCreator:vehiclesUpdated', function()
    if UIManager.IsOpen() then
        UIManager.SyncStats()
        UIManager.Status('Vehicle list updated')
    end
end)
local _hasPerms         = false
local _screenshotActive = false
local _loadActive       = false
local _screenshotNum    = 1
local _sessionReady     = false
local function log(m, c)
    if not (Config.Debug and Config.Debug.client) then
        return
    end
    print((c or '^2')..'[M5_iCreator]^0 '..tostring(m))
end
local function needPerms()
    if not _hasPerms then log('No permission. Use /'..Config.Commands.getperms,'^1') end
    return _hasPerms
end
local function HidePlayerForScreenshot(ped)
    if Config.HidePlayerDuringScreenshot == false or not DoesEntityExist(ped) then
        return nil
    end
    local state = {
        visible = IsEntityVisible(ped),
        alpha = GetEntityAlpha(ped)
    }
    SetEntityVisible(ped, false, false)
    SetEntityAlpha(ped, 0, false)
    return state
end
local function RestorePlayerAfterScreenshot(ped, state)
    if not state or not DoesEntityExist(ped) then
        return
    end
    SetEntityVisible(ped, state.visible == true, false)
    if state.alpha and state.alpha < 255 then
        SetEntityAlpha(ped, state.alpha, false)
    else
        ResetEntityAlpha(ped)
    end
end
local function ResetScreenshotCounter()
    if _screenshotActive or _loadActive then
        log('Stop the current session before resetting the counter.', '^3')
        TriggerEvent('chat:addMessage', {
            args = { '^3[M5_iCreator]^0 Stop the current session before resetting the counter.' }
        })
        return false
    end
    _screenshotNum = 1
    LocalPlayer.state.screenshotnum = 1
    SetResourceKvpInt('screenshotnum', 1)
    log('Counter reset to 1.')
    TriggerEvent('chat:addMessage', {
        args = { '^2[M5_iCreator]^0 Screenshot counter reset to 1.' }
    })
    return true
end
Citizen.CreateThread(function()
    Wait(1000)
    TriggerServerEvent('M5_iCreator:syncPermissionState')
end)
AddEventHandler('playerSpawned', function()
    TriggerServerEvent('M5_iCreator:playerSpawned')
end)
Citizen.CreateThread(function()
    Wait(1000)
    local t = 0
    while LocalPlayer.state.screenshotperms == nil and t < 30 do Wait(1000); t=t+1 end
    if not LocalPlayer.state.screenshotperms then
        log('Permission was not granted within 30 seconds.', '^1')
        return
    end
    _hasPerms = true
    if _sessionReady then return end
    t = 0
    while GlobalState.CustomSpots == nil and t < 50 do Wait(200); t=t+1 end
    LocationManager.Init()
    local saved = GetResourceKvpInt('screenshotnum')
    _screenshotNum = (saved and saved > 0) and saved or 1
    LocalPlayer.state.screenshotnum = _screenshotNum
    _sessionReady = true
    log(string.format('Ready | %d spots | counter #%d',
        #LocationManager.GetAll(), _screenshotNum))
end)
AddStateBagChangeHandler('screenshotperms', nil, function(bagName, _, value)
    local playerBag = ('player:%s'):format(GetPlayerServerId(PlayerId()))
    if bagName ~= playerBag then
        return
    end
    if value ~= true then
        _hasPerms = false
        return
    end
    _hasPerms = true
    if _sessionReady then return end
    Citizen.CreateThread(function()
        if _sessionReady then return end
        local t = 0
        while GlobalState.CustomSpots == nil and t < 50 do Wait(200); t=t+1 end
        LocationManager.Init()
        local saved = GetResourceKvpInt('screenshotnum')
        _screenshotNum = (saved and saved > 0) and saved or 1
        LocalPlayer.state.screenshotnum = _screenshotNum
        _sessionReady = true
    end)
end)
RegisterCommand(Config.Commands.ui, function()
    if not needPerms() then return end
    UIManager.Toggle()
end, false)
RegisterCommand(Config.Commands.start, function()
    if not needPerms()    then return end
    if _screenshotActive  then log('Session is already running.', '^3') return end
    local spot = LocationManager.GetActive()
    if not spot then log('No active spot!', '^1') return end
    TriggerEvent('M5_iCreator:startScreenshot', spot)
end, false)
RegisterCommand(Config.Commands.reset, function()
    if not needPerms() then return end
    ResetScreenshotCounter()
end, false)
RegisterNetEvent('M5_iCreator:resetScreenshotCounter')
AddEventHandler('M5_iCreator:resetScreenshotCounter', function()
    ResetScreenshotCounter()
end)
RegisterCommand(Config.Commands.getcoords, function()
    local ped = PlayerPedId()
    local co  = GetEntityCoords(ped)
    local h   = GetEntityHeading(ped)
    local cp  = GetFinalRenderedCamCoord()
    local cr  = GetFinalRenderedCamRot(2)
    local cf  = GetFinalRenderedCamFov()
    print(string.format(
        '\n^3[Coordinates]--------------------------------^0\n'..
        '^5Player^0  vector4(%.4f,%.4f,%.4f,%.4f)\n'..
        '^5Camera^0  pos(%.4f,%.4f,%.4f) rot(%.4f,%.4f,%.4f) fov %.2f\n'..
        '^3--------------------------------------------^0',
        co.x,co.y,co.z,h, cp.x,cp.y,cp.z, cr.x,cr.y,cr.z, cf))
end, false)
local function SpawnForShot(modelHash, vc)
    RequestCollisionAtCoord(vc.x, vc.y, vc.z)
    RequestModel(modelHash)
    local t = 0
    while not HasModelLoaded(modelHash) and t < 50 do
        if not _screenshotActive then return nil end
        Wait(100)
        t = t + 1
    end
    if not HasModelLoaded(modelHash) then return nil end
    local veh = CreateVehicle(modelHash, vc.x, vc.y, vc.z, vc.w or 0.0, false, true)
    if not veh or not DoesEntityExist(veh) then return nil end
    SetEntityAsMissionEntity(veh, true, true)
    FreezeEntityPosition(veh, true)
    SetEntityCollision(veh, false, false)
    SetEntityVisible(veh, true, false)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleEngineOn(veh, true, true, false)
    SetModelAsNoLongerNeeded(modelHash)
    return veh
end
-- بيانات السيارة التي تُرسل للسيرفر مع كل صورة (تُستخدم في جدول الجراج).
local function VehicleMeta(v)
    return {
        model    = v.model,
        name     = v.name,
        price    = v.price,
        garage   = v.garage,
        category = v.category,
    }
end
-- الرفع إلى FiveManage عبر screenshot-basic (الطريقة الافتراضية).
local function UploadToFiveManage(v)
    exports['screenshot-basic']:requestScreenshotUpload(
        'https://api.fivemanage.com/api/v3/file', 'file',
        { headers = { Authorization = Config.FiveManagerToken }, filename = v.model },
        function(raw)
            local ok, resp = pcall(json.decode, raw)
            if ok and resp and resp.status=='ok' and resp.data and resp.data.url then
                local payload = VehicleMeta(v)
                payload.img = resp.data.url
                payload.id  = resp.data.id
                TriggerServerEvent('renzu_vehthumb:save', payload)
                log('Uploaded: '..v.model)
            else
                log('Upload failed: '..v.model, '^1')
            end
        end)
end
-- الرفع إلى GitHub: نلتقط الصورة هنا ثم نرسلها للسيرفر على أجزاء،
-- والسيرفر هو من يتصل بـ GitHub API حتى لا يخرج التوكن من السيرفر.
-- إعدادات المستودع والتوكن كلها في ServerConfig.lua ولا يعرفها اللاعب.
local function UploadToGithub(v)
    local cap = Config.Capture or {}
    local captured, raw = false, nil
    exports['screenshot-basic']:requestScreenshot({
        encoding = cap.encoding or 'jpg',
        quality  = cap.quality  or 0.90,
    }, function(data)
        raw      = data
        captured = true
    end)
    local t = 0
    while not captured and t < 120 do Wait(50); t = t + 1 end
    if not raw or raw == '' then
        log('Screenshot capture failed: '..v.model, '^1')
        return
    end
    local b64   = raw:match('base64,(.+)') or raw
    local size  = math.max(1000, math.floor(tonumber(cap.chunkSize) or 40000))
    local total = math.ceil(#b64 / size)
    local uid   = ('%s_%d'):format(v.model, GetGameTimer())
    for i = 1, total do
        local meta = nil
        if i == total then
            meta = VehicleMeta(v)
            meta.encoding = cap.encoding or 'jpg'
        end
        TriggerServerEvent('M5_iCreator:githubChunk', {
            uid   = uid,
            index = i,
            total = total,
            data  = b64:sub((i - 1) * size + 1, i * size),
            meta  = meta,
        })
        Wait(60)
    end
    log(('Sent %s to the server in %d chunk(s).'):format(v.model, total))
end
local function UploadScreenshot(v)
    if (Config.ImageHost or 'fivemanage') == 'github' then
        UploadToGithub(v)
    else
        UploadToFiveManage(v)
    end
end
RegisterNetEvent('M5_iCreator:uploadResult')
AddEventHandler('M5_iCreator:uploadResult', function(model, url, err)
    if url then
        log(('GitHub upload done: %s -> %s'):format(model, url))
    else
        log(('GitHub upload failed: %s (%s)'):format(model, tostring(err)), '^1')
    end
end)
RegisterFontFile('A9eelsh')
fontId = RegisterFontId('A9eelsh')
local function DrawProgressHUD(label, current, total)
    local txt = string.format('%s  |  %d / %d  |  Backspace to cancel', label, current, total)
    SetTextFont(fontId)
    SetTextScale(0.32, 0.32)
    SetTextColour(0, 210, 255, 230)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(txt)
    EndTextCommandDisplayText(0.5, 0.96)
end
local function RunScreenshotLoop(spot, vc)
    local vehicles = GlobalState.VehiclesFromDB
    if not vehicles or #vehicles == 0 then
        log('VehiclesFromDB is empty! Check the config.', '^1') ; return nil
    end
    local captured = GlobalState.VehicleImages or {}
    if _screenshotNum > #vehicles then
        log(string.format('Counter(%d) > total(%d) - resetting.', _screenshotNum, #vehicles), '^3')
        _screenshotNum = 1 ; SetResourceKvpInt('screenshotnum', 1)
    end
    log(string.format('Screenshot loop: %d vehicles, starting from #%d', #vehicles, _screenshotNum))
    local lastVeh = nil
    -- فحص زر الإلغاء كل فريم، لأن الحلقة نفسها تنتظر ثوانٍ بين سيارة وأخرى.
    Citizen.CreateThread(function()
        while _screenshotActive do
            DrawProgressHUD('Screenshot', _screenshotNum - 1, #vehicles)
            if IsCancelPressed(false) then
                _screenshotActive = false
                log('Session stopped by user (Backspace).', '^3')
                TriggerEvent('chat:addMessage', {
                    args = { '^3[M5_iCreator]^0 تم إيقاف جلسة التصوير.' }
                })
            end
            Wait(0)
        end
    end)
    for i = _screenshotNum, #vehicles do
        if not _screenshotActive then log('Session stopped.') ; break end
        _screenshotNum = _screenshotNum + 1
        LocalPlayer.state.screenshotnum = _screenshotNum
        SetResourceKvpInt('screenshotnum', _screenshotNum)
        local v         = vehicles[i]
        local modelHash = GetHashKey(v.model)
        if not IsModelInCdimage(modelHash) then
            log('Missing CDImage: '..v.model, '^3')
        elseif Config.SkipCapturedVehicles and captured[v.model] then
            log('Already captured: '..v.model, '^3')
        else
            if lastVeh and DoesEntityExist(lastVeh) then DeleteEntity(lastVeh); lastVeh=nil end
            log('Spawn: '..v.model)
            local veh = SpawnForShot(modelHash, vc)
            if not veh then
                log('Load failed: '..v.model, '^1')
            else
                lastVeh = veh
                if spot.autoRotate then
                    local rv = veh
                    Citizen.CreateThread(function()
                        while DoesEntityExist(rv) and _screenshotActive do
                            SetEntityHeading(rv, GetEntityHeading(rv)+(spot.rotateSpeed or 0.4))
                            Wait(0)
                        end
                    end)
                end
                -- انتظار قابل للقطع: لا نرفع الصورة إذا أُلغيت الجلسة أثناءه.
                if WaitOrStop(Config.ScreenshotDelay, function() return _screenshotActive end) then
                    UploadScreenshot(v)
                else
                    -- نرجع العداد خطوة لأن هذه السيارة لم تُصوَّر.
                    _screenshotNum = _screenshotNum - 1
                    LocalPlayer.state.screenshotnum = _screenshotNum
                    SetResourceKvpInt('screenshotnum', _screenshotNum)
                end
            end
        end
        Wait(0)
    end
    return lastVeh
end
local function RunLoadLoop(spot, vc)
    local vehicles = GlobalState.VehiclesFromDB
    if not vehicles or #vehicles == 0 then
        log('VehiclesFromDB is empty!', '^1') ; return
    end
    log(string.format('Loading %d vehicles for testing', #vehicles))
    local lastVeh = nil
    local current = 0
    Citizen.CreateThread(function()
        while _loadActive do
            DrawProgressHUD('Test loading', current, #vehicles)
            if IsCancelPressed(false) then
                _loadActive = false
                log('Test loading stopped by user (Backspace).', '^3')
                TriggerEvent('chat:addMessage', {
                    args = { '^3[M5_iCreator]^0 تم إيقاف تلويد السيارات.' }
                })
            end
            Wait(0)
        end
    end)
    for i = 1, #vehicles do
        if not _loadActive then break end
        current = i
        local v         = vehicles[i]
        local modelHash = GetHashKey(v.model)
        if IsModelInCdimage(modelHash) then
            if lastVeh and DoesEntityExist(lastVeh) then DeleteEntity(lastVeh); lastVeh=nil end
            RequestModel(modelHash)
            local t = 0
            while not HasModelLoaded(modelHash) and t < 50 do Wait(100); t=t+1 end
            if HasModelLoaded(modelHash) then
                lastVeh = CreateVehicle(modelHash, vc.x, vc.y, vc.z, vc.w or 0.0, false, true)
                FreezeEntityPosition(lastVeh, true)
                SetEntityCollision(lastVeh, false, false)
                SetModelAsNoLongerNeeded(modelHash)
                log(string.format('[%d/%d] Loaded: %s', i, #vehicles, v.model))
            else
                log(string.format('[%d/%d] Failed: %s', i, #vehicles, v.model), '^1')
            end
        else
            log('Missing CDImage: '..v.model, '^3')
        end
        if not WaitOrStop(300, function() return _loadActive end) then break end
    end
    if lastVeh and DoesEntityExist(lastVeh) then DeleteEntity(lastVeh) end
    log('Test loading finished')
end
AddEventHandler('M5_iCreator:startScreenshot', function(spot)
    if _screenshotActive or _loadActive then return end
    if not spot then log('No spot selected.', '^1') return end
    _screenshotActive = true
    log('Starting screenshot: '..spot.name)
    local ped  = PlayerPedId()
    local retC = GetEntityCoords(ped)
    local retH = GetEntityHeading(ped)
    FreezeEntityPosition(ped, true)
    LocationManager.LoadSpot(spot)
    LocationManager.TeleportPlayer(spot)
    local pedVisibility = HidePlayerForScreenshot(ped)
    if spot.ipl and spot.ipl[1] then
        local t = 0
        while not IsIplActive(spot.ipl[1]) and t < 60 do Wait(100); t=t+1 end
    end
    local cfg = spot.camera
    local vc  = spot.vehicleCoords
    RequestCollisionAtCoord(vc.x, vc.y, vc.z)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        cfg.pos.x,cfg.pos.y,cfg.pos.z, cfg.rot.x,0.0,cfg.rot.z,
        cfg.fov or 50.0, false, 0)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    SetFocusPosAndVel(vc.x,vc.y,vc.z, 0.0,0.0,0.0)
    DisplayHud(false) ; DisplayRadar(false)
    local lightsOn = true
    Citizen.CreateThread(function()
        while lightsOn do
            local l = spot.light
            if l then
                local p,c = l.pos, l.color or {r=255,g=255,b=255}
                DrawLightWithRange(p.x,p.y,p.z+2.0, c.r,c.g,c.b, l.range or 40.0, l.intensity or 15.0)
                DrawLightWithRange(p.x-6.0,p.y+4.0,p.z+3.0, 180,200,255, 20.0, 5.0)
            end
            Wait(0)
        end
    end)
    Wait(2000)
    local lastVeh = RunScreenshotLoop(spot, vc)
    lightsOn = false ; _screenshotActive = false
    if lastVeh and DoesEntityExist(lastVeh) then DeleteEntity(lastVeh) end
    RenderScriptCams(false,false,0,true,true) ; DestroyCam(cam,false) ; ClearFocus()
    SetEntityCoords(ped,retC.x,retC.y,retC.z,false,false,false,false)
    SetEntityHeading(ped,retH) ; FreezeEntityPosition(ped,false)
    RestorePlayerAfterScreenshot(ped, pedVisibility)
    DisplayHud(true) ; DisplayRadar(true)
    -- السيرفر هو من يقرر إن كان سيرسل الناتج (ServerConfig.GarageExport).
    TriggerServerEvent('M5_iCreator:exportGarage', true)
    log('Screenshot finished | next vehicle #'.._screenshotNum)
end)
AddEventHandler('M5_iCreator:loadVehicles', function(spot)
    if _loadActive or _screenshotActive then return end
    if not spot then log('No spot selected.', '^1') return end
    _loadActive = true
    log('Starting test load: '..spot.name)
    local ped  = PlayerPedId()
    local retC = GetEntityCoords(ped)
    local retH = GetEntityHeading(ped)
    FreezeEntityPosition(ped, true)
    LocationManager.LoadSpot(spot)
    LocationManager.TeleportPlayer(spot)
    if spot.ipl and spot.ipl[1] then
        local t = 0
        while not IsIplActive(spot.ipl[1]) and t < 60 do Wait(100); t=t+1 end
    end
    local vc = spot.vehicleCoords
    RequestCollisionAtCoord(vc.x, vc.y, vc.z)
    local lightsOn = true
    Citizen.CreateThread(function()
        while lightsOn do
            local l = spot.light
            if l then
                local p,c = l.pos, l.color or {r=255,g=255,b=255}
                DrawLightWithRange(p.x,p.y,p.z+2.0, c.r,c.g,c.b, l.range or 40.0, l.intensity or 15.0)
            end
            Wait(0)
        end
    end)
    Wait(1000)
    RunLoadLoop(spot, vc)
    lightsOn = false ; _loadActive = false
    SetEntityCoords(ped,retC.x,retC.y,retC.z,false,false,false,false)
    SetEntityHeading(ped,retH) ; FreezeEntityPosition(ped,false)
    log('Test loading finished')
end)
