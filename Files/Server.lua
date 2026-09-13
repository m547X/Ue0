local thumbs      = {}
local customSpots = {}
local DATA_PATHS  = {
    thumbnails = 'Files/Data/thumbnails.json',
    spots      = 'Files/Data/spots.json',
    garage     = 'Files/Data/garage.lua',
}
local Proxy       = module('vrp', 'lib/Proxy')
local vRP         = Proxy.getInterface('vRP')
Config            = Config or {}

if not Config.License then
    M5 = {}
    load(LoadResourceFile(GetCurrentResourceName(), 'Config.lua'))()
end

-- إعدادات السيرفر الحساسة (التوكنات وروابط الـ API والويب هوك ومسار ملف الجراج).
-- إذا لم يُضَف ServerConfig.lua داخل server_scripts نقوم بتحميله هنا يدوياً.
if not ServerConfig then
    local raw = LoadResourceFile(GetCurrentResourceName(), 'ServerConfig.lua')
    if raw then
        local chunk = load(raw)
        if chunk then chunk() end
    end
end
if not ServerConfig then
    print('^1[M5_iCreator/Server]^0 ServerConfig.lua not found - using Config.lua fallbacks.')
end
ServerConfig = ServerConfig or {}

local ApiLink = 'https://filesafety.net/api/v1/licenses/check' -- api



local ProductName = "M5_iCreator" -->> Script Name

local LicenseKey = Config.License -->> LicenseKey

local StoreAvatar = "https://github.com/xM547/BANK/raw/main/MU-Store-1.png"

local ProductUUID = '49d86e6a-9a9c-4ca7-a4aa-c338d0f53770' -->> ProductUUID

local ValidResponse = 'Good License'                       -->> ValidResponse

local InvalidResponse = 'Wrong License'                    -->> InvalidResponse



local logValidResponse =
"https://discord.com/api/webhooks/1516587898214940772/qu5DbkphLAA_-rM4TA4QL4fWcCcjYFW0yx0JmGQ9FlyLwPTqBzF7jLKeujP1NWXTb4TP"                              -->> لوق التشغيل الصحيح

local logInvalidResponse =
"https://discord.com/api/webhooks/1516587901993877554/ePwDi6iHP0FU4TOJK91a_PEcXZXke92dXX3KKMFEWamU9drJw_dvMiFSxhOSaK5yEfeN"                              -->> لوق التشغيل بدون تفعيل

local logNotfoundkey =
"https://discord.com/api/webhooks/1516587914627256390/Tx-X4kR0IJbc6aQZEIFxKuswNA4xnkGvBRBmMFQyZXp20lm_w4EYpoO0tN38ofrmD8I2"                              -->> لوق تشغيل بدون رخصه صحيحه

local logScriptchangedname =
"https://discord.com/api/webhooks/1516587918570033324/KxN6Xw7Flcgh8KJ74pgEYRBEAfJP7U3z7csOGR_jRBkRxvP338pCIP_-jypZnypSEkAB"                              -->> لوق تغير اسم السكربت

local logerror =
"https://discord.com/api/webhooks/1516587921572888689/MIcfGb413bC_YF7htLchqoWNY1kG7lBUajpZCGSqE27MfTadk0U_4cvrhdrf9gwQ9hcm"                              -->> لوق ايرور



PerformHttpRequest(ApiLink, function(status, response, headers)
    if (GetCurrentResourceName() == ProductName) then
        if response == ValidResponse and LicenseKey ~= nil then
            function SendWebHook(title, color, link)
                PerformHttpRequest("https://filesafety.net/api/ip", function(err, text, head)
                    local embeds = {
                        {
                            ["color"] = color,
                            ['title'] = title,
                            fields = {
                                {
                                    ["name"] = "**Product Name**",
                                    ["value"] = '**[``' .. ProductName .. '``]**',
                                    inline = false
                                },
                                {
                                    ["name"] = "**Resource Name**",
                                    ["value"] = '**[``' .. GetCurrentResourceName() .. '``]**',
                                    inline = false
                                },
                                {
                                    ["name"] = "**Licenes**",
                                    ["value"] = '**[``' .. LicenseKey .. '``]**',
                                    inline = false
                                },
                                {
                                    ["name"] = "**Server Name**",
                                    ["value"] = '**[``' .. GetConvar("sv_hostname") .. '``]**',
                                    inline = false
                                },
                                {
                                    ["name"] = "**Server IP**",
                                    ["value"] = '**[``' .. text .. '``]**',
                                    inline = false
                                },
                            },
                            ["timestamp"] = os.date('!%Y-%m-%dT%H:%M:%S'),
                            ["footer"] = {
                                ["text"] = "[Made With Love By M547]",
                                ["icon_url"] = StoreAvatar,
                            },
                            ["thumbnail"] = {
                                ["url"] = Config.ServerLogo
                            },
                        }
                    }

                    PerformHttpRequest(link, function(err, text, headers) end, 'POST',
                        json.encode({ username = ProductName, embeds = embeds, avatar_url = StoreAvatar }),
                        { ['Content-Type'] = 'application/json' })
                end, 'GET', '')
            end

            local function log(msg, color)
                if not (Config.Debug and Config.Debug.server) then
                    return
                end
                color = color or '^2'
                print(color .. '[M5_iCreator/Server]^0 ' .. tostring(msg))
            end
            local function warn(msg)
                print('^1[M5_iCreator/Server]^0 ' .. tostring(msg))
            end
            local function hasOwnerPermission(source)
                for i = 0, GetNumPlayerIdentifiers(source) - 1 do
                    local identifier = GetPlayerIdentifier(source, i)
                    if identifier and Config.owners and Config.owners[identifier] then
                        return true, identifier
                    end
                end
                return false, nil
            end
            local function hasVrpPermission(source)
                if not vRP then
                    return false, nil
                end
                local user_id = vRP.getUserId({ source })
                if not user_id then
                    return false, nil
                end
                return vRP.hasPermission({ user_id, Config.vRPPermission }), user_id
            end
            local function hasPermission(source)
                if Config.PermissionMode == 'vrp' then
                    return hasVrpPermission(source)
                end
                return hasOwnerPermission(source)
            end
            local function syncPermissionState(source)
                local allowed, detail = hasPermission(source)
                Player(source).state.screenshotperms = allowed == true
                return allowed, detail
            end
            local function syncPlayerLoad(source, reason, delay)
                source = tonumber(source)
                if not source or source <= 0 then
                    return
                end
                Citizen.CreateThread(function()
                    if delay and delay > 0 then
                        Wait(delay)
                    end
                    if not GetPlayerName(source) then
                        return
                    end
                    local allowed, detail = syncPermissionState(source)
                    TriggerClientEvent('M5_iCreator:syncSpots', source, customSpots)
                    log(('Synced player %d on %s | permission=%s | detail=%s'):format(
                        source,
                        reason or 'load',
                        tostring(allowed),
                        tostring(detail)
                    ))
                end)
            end
            local function syncAllPlayers(reason, delay)
                for _, player in ipairs(GetPlayers()) do
                    syncPlayerLoad(tonumber(player), reason, delay)
                end
            end
            local function resolveSpawnSource(...)
                local candidates = { ... }
                for _, candidate in ipairs(candidates) do
                    local source = tonumber(candidate)
                    if source and source > 0 and GetPlayerName(source) then
                        return source
                    end
                end
                return nil
            end
            AddEventHandler('playerJoining', function()
                syncPlayerLoad(source, 'playerJoining', 1500)
            end)
            RegisterNetEvent('M5_iCreator:playerSpawned')
            AddEventHandler('M5_iCreator:playerSpawned', function()
                syncPlayerLoad(source, 'playerSpawned', 500)
            end)
            AddEventHandler('vRP:playerSpawn', function(user_id, player, first_spawn)
                local src = resolveSpawnSource(player, source, user_id)
                if not src then
                    return
                end
                syncPlayerLoad(src, first_spawn and 'vRP first spawn' or 'vRP spawn', 500)
            end)
            RegisterCommand(Config.Commands.getperms, function(source)
                if source == 0 then
                    log('Cannot run from server console.', '^1')
                    return
                end
                local allowed, detail = syncPermissionState(source)
                if allowed then
                    log(string.format(
                        'Granted: player %d (%s) [%s]',
                        source,
                        GetPlayerName(source),
                        tostring(detail)
                    ))
                    TriggerClientEvent('chat:addMessage', source, {
                        args = {
                            '^2[M5_iCreator]^0 Permissions granted! ' ..
                            'Use /' .. Config.Commands.ui .. ' to open the UI.'
                        }
                    })
                    return
                end
                log(string.format('Denied: player %d (%s)', source, GetPlayerName(source)), '^1')
                TriggerClientEvent('chat:addMessage', source, {
                    args = { '^1[M5_iCreator]^0 Access denied.' }
                })
            end)
            RegisterCommand(Config.Commands.reset, function(source)
                if source == 0 then
                    log('Cannot reset a player counter from the server console.', '^1')
                    return
                end
                local allowed = hasPermission(source)
                if not allowed then
                    TriggerClientEvent('chat:addMessage', source, {
                        args = { '^1[M5_iCreator]^0 Access denied.' }
                    })
                    return
                end
                Player(source).state.screenshotnum = 1
                TriggerClientEvent('M5_iCreator:resetScreenshotCounter', source)
                log(('Reset screenshot counter for player %d (%s)'):format(source, GetPlayerName(source)))
            end)
            RegisterNetEvent('M5_iCreator:syncPermissionState')
            AddEventHandler('M5_iCreator:syncPermissionState', function()
                local src = source
                if src == 0 then
                    return
                end
                syncPermissionState(src)
            end)

            -- ══════════════════════════════════════════════════════════════
            --  الإعدادات: مصدرها ServerConfig.lua (سيرفر فقط)
            --  ونرجع إلى Config.lua فقط لتوافق الإصدارات القديمة.
            -- ══════════════════════════════════════════════════════════════
            local SAVE_MODE    = ServerConfig.save or Config.save or 'json'
            local WEBHOOK      = ServerConfig.DiscordWebHook or Config.DiscordWebHook or ''
            local API          = ServerConfig.SaveAPI or Config.SaveAPI or {}
            local GH           = ServerConfig.GitHub or Config.GitHub or {}
            local GARAGE       = ServerConfig.GarageExport or Config.GarageExport or {}
            local GF           = ServerConfig.GarageFile or {}
            local SOURCE       = ServerConfig.VehicleSource
                or (Config.useSQLvehicle and 'sql' or 'config')
            local vehicleInfo  = {}
            local chunkBuffers = {}

            -- ─── التخزين: json / kvp / api ────────────────────────────
            local function countThumbs()
                local c = 0
                for _ in pairs(thumbs) do c = c + 1 end
                return c
            end
            local function apiHeaders()
                local h = { ['Content-Type'] = 'application/json' }
                for k, v in pairs(API.headers or {}) do
                    if v and v ~= '' then h[k] = v end
                end
                return h
            end
            local function apiReady()
                return SAVE_MODE == 'api' and API.saveUrl and API.saveUrl ~= ''
            end
            local function decodeThumbPayload(body)
                if not body or body == '' then return nil end
                local ok, data = pcall(json.decode, body)
                if not ok or type(data) ~= 'table' then return nil end
                if type(data.thumbnails) == 'table' then return data.thumbnails end
                if type(data.data) == 'table' then return data.data end
                return data
            end
            local function saveThumbFile()
                local ok = SaveResourceFile(
                    GetCurrentResourceName(),
                    DATA_PATHS.thumbnails,
                    json.encode(thumbs),
                    -1
                )
                if not ok then warn('Failed to save thumbnails.json!') end
            end
            local function apiSend(payload)
                PerformHttpRequest(API.saveUrl, function(code, body)
                    if code and code >= 200 and code < 300 then
                        log(('API save ok (%s).'):format(tostring(code)))
                    else
                        warn(('API save failed (%s): %s'):format(tostring(code), tostring(body)))
                    end
                end, API.method or 'POST', json.encode(payload), apiHeaders())
            end
            -- model اختياري: يُمرَّر لإرسال سيارة واحدة فقط عند perVehicle.
            local function SaveThumbnails(model)
                if SAVE_MODE == 'kvp' then
                    SetResourceKvp('thumbnails', json.encode(thumbs))
                    return
                end
                if SAVE_MODE == 'api' then
                    if not apiReady() then
                        warn('ServerConfig.save = "api" but SaveAPI.saveUrl is empty - saving to json instead.')
                        saveThumbFile()
                        return
                    end
                    if API.perVehicle and model and thumbs[model] then
                        local entry = thumbs[model]
                        apiSend({
                            resource = GetCurrentResourceName(),
                            model    = model,
                            name     = entry.name,
                            price    = entry.price,
                            garage   = entry.garage,
                            category = entry.category,
                            url      = entry.url,
                            id       = entry.id,
                            savedAt  = entry.savedAt,
                        })
                    else
                        apiSend({
                            resource   = GetCurrentResourceName(),
                            count      = countThumbs(),
                            thumbnails = thumbs,
                        })
                    end
                    if API.mirrorToFile then saveThumbFile() end
                    return
                end
                saveThumbFile()
            end
            local function LoadThumbnails(done)
                done = done or function() end
                local function finish()
                    log(('Loaded %d thumbnail entries.'):format(countThumbs()))
                    done()
                end
                if SAVE_MODE == 'kvp' then
                    thumbs = json.decode(GetResourceKvpString('thumbnails') or '{}') or {}
                    return finish()
                end
                if SAVE_MODE == 'api' and API.loadUrl and API.loadUrl ~= '' then
                    PerformHttpRequest(API.loadUrl, function(code, body)
                        local data = nil
                        if code and code >= 200 and code < 300 then
                            data = decodeThumbPayload(body)
                        end
                        if data then
                            thumbs = data
                        else
                            warn(('API load failed (%s) - falling back to thumbnails.json.'):format(tostring(code)))
                            local raw = LoadResourceFile(GetCurrentResourceName(), DATA_PATHS.thumbnails)
                            thumbs = json.decode(raw or '{}') or {}
                        end
                        finish()
                    end, 'GET', '', apiHeaders())
                    return
                end
                local raw = LoadResourceFile(GetCurrentResourceName(), DATA_PATHS.thumbnails)
                thumbs = json.decode(raw or '{}') or {}
                return finish()
            end
            local function LoadCustomSpots()
                local raw   = LoadResourceFile(GetCurrentResourceName(), DATA_PATHS.spots) or '{}'
                local data  = json.decode(raw) or {}
                customSpots = data.spots or {}
                log(('Loaded %d custom spots.'):format(#customSpots))
            end
            local function SaveCustomSpots()
                local ok = SaveResourceFile(
                    GetCurrentResourceName(),
                    DATA_PATHS.spots,
                    json.encode({ spots = customSpots }),
                    -1
                )
                if not ok then warn('Failed to save spots.json!') end
            end

            -- ─── GitHub Contents API ──────────────────────────────────
            local GH_EXT = { jpg = 'jpg', jpeg = 'jpg', png = 'png', webp = 'webp' }
            local function ghToken()
                if GH.token and GH.token ~= '' then return GH.token end
                return GetConvar('m5_github_token', '')
            end
            local function ghHeaders()
                return {
                    ['Authorization']        = 'Bearer ' .. ghToken(),
                    ['Accept']               = 'application/vnd.github+json',
                    ['X-GitHub-Api-Version'] = '2022-11-28',
                    ['User-Agent']           = GetCurrentResourceName(),
                    ['Content-Type']         = 'application/json',
                }
            end
            local function ghPath(model, ext)
                local dir = tostring(GH.path or '')
                dir = dir:gsub('^/+', '')
                dir = dir:gsub('/+$', '')
                local file = ('%s.%s'):format(model, ext)
                if dir ~= '' then return dir .. '/' .. file end
                return file
            end
            local function ghPublicUrl(path, downloadUrl)
                local branch = GH.branch or 'main'
                local mode   = GH.urlMode or 'raw'
                if mode == 'cdn' then
                    return ('https://cdn.jsdelivr.net/gh/%s/%s@%s/%s'):format(GH.owner, GH.repo, branch, path)
                end
                if mode == 'download' and downloadUrl and downloadUrl ~= '' then
                    return downloadUrl
                end
                return ('https://raw.githubusercontent.com/%s/%s/%s/%s'):format(GH.owner, GH.repo, branch, path)
            end
            local function GithubUpload(meta, content, cb)
                if ghToken() == '' then
                    return cb(nil, 'GitHub token is empty (ServerConfig.GitHub.token or convar m5_github_token)')
                end
                if not GH.owner or GH.owner == '' or not GH.repo or GH.repo == '' then
                    return cb(nil, 'ServerConfig.GitHub.owner / repo is empty')
                end
                local enc     = tostring(meta.encoding or 'jpg'):lower()
                local ext     = GH_EXT[enc] or 'jpg'
                local branch  = GH.branch or 'main'
                local path    = ghPath(meta.model, ext)
                local api     = ('https://api.github.com/repos/%s/%s/contents/%s'):format(GH.owner, GH.repo, path)
                local message = tostring(GH.commitMessage or 'M5_iCreator: %MODEL% thumbnail')
                message = message:gsub('%%MODEL%%', meta.model)
                local function put(sha)
                    local body = { message = message, content = content, branch = branch }
                    if sha then body.sha = sha end
                    PerformHttpRequest(api, function(code, res)
                        if code == 200 or code == 201 then
                            local downloadUrl
                            local ok, decoded = pcall(json.decode, res or '{}')
                            if ok and type(decoded) == 'table' and type(decoded.content) == 'table' then
                                downloadUrl = decoded.content.download_url
                            end
                            cb(ghPublicUrl(path, downloadUrl))
                        else
                            cb(nil, ('HTTP %s: %s'):format(tostring(code), tostring(res)))
                        end
                    end, 'PUT', json.encode(body), ghHeaders())
                end
                if GH.overwrite == false then
                    return put(nil)
                end
                -- الملف الموجود مسبقاً يحتاج sha حتى يُستبدل.
                PerformHttpRequest(api .. '?ref=' .. branch, function(code, res)
                    local sha
                    if code == 200 then
                        local ok, decoded = pcall(json.decode, res or '{}')
                        if ok and type(decoded) == 'table' then sha = decoded.sha end
                    end
                    put(sha)
                end, 'GET', '', ghHeaders())
            end

            -- ══════════════════════════════════════════════════════════════
            --  قراءة السيارات من ملف الجراج
            -- ══════════════════════════════════════════════════════════════
            -- سطر السيارة:  ["model"] = { "name", price, "<img src='...'/>..." },
            -- سطر الجراج :  ["Sonic-garage"] = {
            -- سطر _config لا يطابق أياً منهما لأن مفتاحه بدون أقواس مربعة،
            -- وقائمة cfg.garages (الإحداثيات) كذلك لأنها بدون ["key"] =.
            local VEH_PAT  = '%[%s*"([^"]+)"%s*%]%s*=%s*{%s*"(.-)"%s*,%s*(%-?[%d%.]+)%s*,%s*"(.-)"%s*}'
            local VEH_PAT2 = '%[%s*"([^"]+)"%s*%]%s*=%s*{%s*"(.-)"%s*,%s*(%-?[%d%.]+)%s*}'
            local HEAD_PAT = '^%s*%[%s*"([^"]+)"%s*%]%s*=%s*{%s*$'

            local garageRaw      = nil   -- محتوى ملف الجراج كما هو
            local garageEntries  = {}    -- كل السيارات بالترتيب
            local garageModels   = {}    -- model -> أول ظهور للسيارة
            local garageNames    = {}    -- أسماء الجراجات الموجودة

            local function imageFromDesc(desc)
                if not desc or desc == '' then return '' end
                local src = desc:match("src%s*=%s*'([^']*)'")
                if src then return src end
                src = desc:match('src%s*=%s*\\"([^\\"]*)')
                return src or ''
            end
            local function listHas(list, value)
                for _, v in ipairs(list or {}) do
                    if v == value then return true end
                end
                return false
            end
            local function garageAllowed(name)
                if not name then return false end
                local only = GF.garages or {}
                if #only > 0 and not listHas(only, name) then return false end
                if listHas(GF.skipGarages, name) then return false end
                return true
            end
            local function ReadGarageFile()
                local path = GF.path
                if not path or path == '' then
                    warn('ServerConfig.GarageFile.path is empty.')
                    return nil
                end
                local resource = GF.resource
                if not resource or resource == '' then
                    resource = GetCurrentResourceName()
                end
                local raw = LoadResourceFile(resource, path)
                if not raw or raw == '' then
                    warn(('Could not read "%s" from resource "%s". Check ServerConfig.GarageFile.')
                        :format(path, resource))
                    return nil
                end
                return raw
            end
            local function ParseGarageFile()
                garageEntries, garageModels, garageNames = {}, {}, {}
                garageRaw = ReadGarageFile()
                if not garageRaw then return false end
                local current = nil
                for line in garageRaw:gmatch('[^\r\n]+') do
                    local head = line:match(HEAD_PAT)
                    if head then
                        current = head
                        garageNames[#garageNames + 1] = head
                    else
                        local model, name, price, desc = line:match(VEH_PAT)
                        if not model then
                            model, name, price = line:match(VEH_PAT2)
                            desc = nil
                        end
                        if model and current then
                            local entry = {
                                model  = model,
                                name   = (name and name ~= '') and name or model,
                                price  = tonumber(price) or 0,
                                img    = imageFromDesc(desc),
                                garage = current,
                            }
                            garageEntries[#garageEntries + 1] = entry
                            if not garageModels[model] then garageModels[model] = entry end
                        end
                    end
                end
                log(('Garage file parsed: %d garages | %d vehicle lines | %d unique models.')
                    :format(#garageNames, #garageEntries, (function()
                        local c = 0
                        for _ in pairs(garageModels) do c = c + 1 end
                        return c
                    end)()))
                return true
            end
            -- السيارات المطلوب تصويرها: بدون تكرار، والتي لا صورة لها فقط.
            local function GarageVehicleList()
                local list, seen = {}, {}
                for _, v in ipairs(garageEntries) do
                    if garageAllowed(v.garage) and not seen[v.model] then
                        local saved  = thumbs[v.model] and thumbs[v.model].url and thumbs[v.model].url ~= ''
                        local skip   = false
                        if GF.onlyMissingImages ~= false and v.img ~= '' then skip = true end
                        if GF.skipSaved ~= false and saved then skip = true end
                        if not skip then
                            seen[v.model] = true
                            list[#list + 1] = {
                                model    = v.model,
                                name     = v.name,
                                price    = v.price,
                                garage   = v.garage,
                                category = 'garage',
                            }
                        end
                    end
                end
                return list
            end

            -- ─── تحميل قائمة السيارات حسب المصدر ──────────────────────
            local function LoadVehicles()
                local list = {}
                vehicleInfo = {}
                if SOURCE == 'garage' then
                    ParseGarageFile()
                    list = GarageVehicleList()
                    for model, v in pairs(garageModels) do
                        vehicleInfo[model] = {
                            name     = v.name,
                            price    = v.price,
                            garage   = v.garage,
                            category = 'garage',
                        }
                    end
                else
                    local rawVehicles
                    if SOURCE == 'sql' or Config.useSQLvehicle then
                        rawVehicles = MySQL.Sync.fetchAll('SELECT * FROM ' .. Config.vehicle_table) or {}
                    else
                        rawVehicles = Config.SqlVehicleTable or {}
                    end
                    for _, v in ipairs(rawVehicles) do
                        if Config.Category == 'all' or v.category == Config.Category then
                            list[#list + 1] = v
                            vehicleInfo[v.model] = {
                                name     = v.name,
                                price    = v.price,
                                category = v.category,
                            }
                        end
                    end
                end
                GlobalState.VehiclesFromDB = list
                GlobalState.VehicleSource  = SOURCE
                return list
            end

            -- ══════════════════════════════════════════════════════════════
            --  جدول الجراج + الويب هوك
            -- ══════════════════════════════════════════════════════════════
            local function escapeQuotes(value)
                local out = tostring(value or '')
                out = out:gsub('\\', '\\\\')
                out = out:gsub('"', '\\"')
                return out
            end
            -- الأسعار القادمة من قاعدة البيانات قد تكون 50000.0 فنكتبها 50000.
            local function formatPrice(value)
                local price = tonumber(value) or 0
                if price % 1 == 0 then
                    return ('%d'):format(price)
                end
                return tostring(price)
            end
            local function garageEntry(model)
                local t     = thumbs[model] or {}
                local vi    = vehicleInfo[model] or {}
                local name  = t.name or vi.name or model
                local price = tonumber(t.price) or tonumber(vi.price) or tonumber(GARAGE.defaultPrice) or 0
                return name, price, t.url or '', t.garage or vi.garage
            end
            local function BuildGarageLine(model)
                local name, price, url = garageEntry(model)
                local priceText = formatPrice(price)
                local desc = ("<img src='%s' width='%d' height='%d'/><br/> %s : %s <br/>"):format(
                    url,
                    tonumber(GARAGE.imgWidth) or 300,
                    tonumber(GARAGE.imgHeight) or 300,
                    priceText,
                    GARAGE.priceLabel or 'السعر'
                )
                return ('    ["%s"] = { "%s", %s, "%s" },'):format(
                    model, escapeQuotes(name), priceText, escapeQuotes(desc))
            end
            -- بناء جدول جراج جديد (يُستخدم مع مصدر config / sql).
            local function BuildGarageBlock()
                local models = {}
                for model, entry in pairs(thumbs) do
                    if type(entry) == 'table' and entry.url and entry.url ~= '' then
                        models[#models + 1] = model
                    end
                end
                if GARAGE.includeMissing then
                    for model in pairs(vehicleInfo) do
                        local entry = thumbs[model]
                        if not entry or not entry.url or entry.url == '' then
                            models[#models + 1] = model
                        end
                    end
                end
                table.sort(models)
                local gname = GARAGE.garageName or 'M5-garage'
                local lines = { ('["%s"] = {'):format(gname) }
                if GARAGE.includeConfig ~= false and GARAGE.configLine and GARAGE.configLine ~= '' then
                    local cfgLine = tostring(GARAGE.configLine)
                    cfgLine = cfgLine:gsub('%%GARAGE%%', gname)
                    cfgLine = cfgLine:gsub('%%VTYPE%%', GARAGE.vtype or 'car')
                    lines[#lines + 1] = ('    _config = %s,'):format(cfgLine)
                end
                for _, model in ipairs(models) do
                    lines[#lines + 1] = BuildGarageLine(model)
                end
                lines[#lines + 1] = '},'
                return table.concat(lines, '\n'), #models
            end
            -- إعادة بناء ملف الجراج الأصلي بعد تعبئة روابط الصور الجديدة.
            -- نحافظ على الملف كما هو ونستبدل src='' فقط.
            local function BuildUpdatedGarageFile()
                if not garageRaw then
                    if not ParseGarageFile() then return nil, 0, {} end
                end
                local changed, byGarage = 0, {}
                local current = nil
                local out = garageRaw:gsub('[^\r\n]+', function(line)
                    local head = line:match(HEAD_PAT)
                    if head then
                        current = head
                        return nil
                    end
                    local model, _, _, desc = line:match(VEH_PAT)
                    if not model then return nil end
                    if not garageAllowed(current) then return nil end
                    local entry = thumbs[model]
                    local url   = entry and entry.url
                    if not url or url == '' then return nil end
                    if imageFromDesc(desc) ~= '' and not GF.overwriteExisting then return nil end
                    local safe = url:gsub('%%', '%%%%')
                    local newLine, n = line:gsub("src%s*=%s*'[^']*'", "src='" .. safe .. "'", 1)
                    if n == 0 then return nil end
                    changed = changed + 1
                    byGarage[current] = byGarage[current] or {}
                    table.insert(byGarage[current], (newLine:gsub('^%s+', '    ')))
                    return newLine
                end)
                return out, changed, byGarage
            end
            local function garageWebhook()
                local hook = GARAGE.webhook
                if not hook or hook == '' then hook = WEBHOOK end
                if not hook or hook == '' or hook:find('xxxxxxxx') then return nil end
                return hook
            end
            local function PostWebhook(hook, payload)
                if not hook or hook == '' then return end
                payload.username   = payload.username or ProductName
                payload.avatar_url = payload.avatar_url or StoreAvatar
                PerformHttpRequest(hook, function() end, 'POST',
                    json.encode(payload), { ['Content-Type'] = 'application/json' })
            end
            -- إشعار الصورة المحفوظة (ServerConfig.DiscordWebHook).
            local function SendThumbnailWebhook(model)
                local hook = WEBHOOK
                if not hook or hook == '' or hook:find('xxxxxxxx') then return end
                local name, price, url = garageEntry(model)
                PostWebhook(hook, {
                    embeds = { {
                        title       = 'Vehicle Thumbnail Saved',
                        description = ('**Model:** `%s`\n**Name:** %s\n**Price:** `%s`\n**URL:** %s')
                            :format(model, name, formatPrice(price), url),
                        color       = 3447003,
                        image       = (url ~= '') and { url = url } or nil,
                        timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                    } }
                })
            end
            -- ويب هوك الجراج: سطر السيارة الجاهز للنسخ مع الصورة والاسم والسعر.
            local function SendGarageLineWebhook(model)
                if not GARAGE.enabled or not GARAGE.sendEach then return end
                local hook = garageWebhook()
                if not hook then return end
                local name, price, url, garage = garageEntry(model)
                PostWebhook(hook, {
                    embeds = { {
                        title       = name,
                        description = ('```lua\n%s\n```'):format(BuildGarageLine(model)),
                        color       = 3066993,
                        fields      = {
                            { name = 'Model',  value = ('`%s`'):format(model),               inline = true },
                            { name = 'Price',  value = ('`%s`'):format(formatPrice(price)),  inline = true },
                            { name = 'Garage', value = ('`%s`'):format(garage or GARAGE.garageName or '-'), inline = true },
                        },
                        image       = (url ~= '') and { url = url } or nil,
                        timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                        footer      = { text = '[Made With Love By M547]', icon_url = StoreAvatar },
                    } }
                })
            end
            -- ديسكورد يحدّ الرسالة بـ 2000 حرف، لذلك نقسّم الناتج على أجزاء.
            local function SendChunks(hook, header, body)
                local chunks, current = {}, ''
                for line in body:gmatch('[^\r\n]+') do
                    if #current + #line + 1 > 1600 then
                        chunks[#chunks + 1] = current
                        current = ''
                    end
                    current = current .. line .. '\n'
                end
                if current ~= '' then chunks[#chunks + 1] = current end
                Citizen.CreateThread(function()
                    if header then
                        PostWebhook(hook, { embeds = { header } })
                        Wait(700)
                    end
                    for _, chunk in ipairs(chunks) do
                        PostWebhook(hook, { content = ('```lua\n%s```'):format(chunk) })
                        Wait(900)
                    end
                end)
            end
            local function ExportGarage()
                local hook = garageWebhook()
                if SOURCE == 'garage' then
                    local content, changed, byGarage = BuildUpdatedGarageFile()
                    if not content then
                        warn('Garage export failed: could not read the garage file.')
                        return 0
                    end
                    if GARAGE.saveFile ~= false then
                        local ok = SaveResourceFile(GetCurrentResourceName(), DATA_PATHS.garage, content, -1)
                        if not ok then warn('Failed to save garage.lua!') end
                    end
                    if hook and changed > 0 then
                        local body = {}
                        for name, lines in pairs(byGarage) do
                            body[#body + 1] = ('["%s"] = {'):format(name)
                            for _, l in ipairs(lines) do body[#body + 1] = l end
                            body[#body + 1] = '},'
                        end
                        SendChunks(hook, {
                            title       = 'Garage File Updated',
                            description = ('**Source:** `%s/%s`\n**Updated vehicles:** `%d`\n**File:** `%s`')
                                :format(GF.resource or '-', GF.path or '-', changed, DATA_PATHS.garage),
                            color       = 15844367,
                            timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                            footer      = { text = '[Made With Love By M547]', icon_url = StoreAvatar },
                        }, table.concat(body, '\n'))
                    end
                    log(('Garage export done (%d vehicles updated).'):format(changed))
                    return changed
                end
                local block, count = BuildGarageBlock()
                if GARAGE.saveFile ~= false then
                    local ok = SaveResourceFile(GetCurrentResourceName(), DATA_PATHS.garage, block, -1)
                    if not ok then warn('Failed to save garage.lua!') end
                end
                if hook then
                    SendChunks(hook, {
                        title       = 'Garage Table',
                        description = ('**Garage:** `%s`\n**Vehicles:** `%d`')
                            :format(GARAGE.garageName or '-', count),
                        color       = 15844367,
                        timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                        footer      = { text = '[Made With Love By M547]', icon_url = StoreAvatar },
                    }, block)
                else
                    log('Garage export: no webhook configured, saved to file only.', '^3')
                end
                log(('Garage export done (%d vehicles).'):format(count))
                return count
            end

            -- ─── حفظ صورة سيارة واحدة ─────────────────────────────────
            local function StoreThumbnail(data)
                local vi = vehicleInfo[data.model] or {}
                thumbs[data.model] = {
                    url      = data.img,
                    id       = data.id,
                    name     = data.name     or vi.name,
                    price    = tonumber(data.price) or tonumber(vi.price),
                    garage   = data.garage   or vi.garage,
                    category = data.category or vi.category,
                    savedAt  = os.time(),
                }
                local images = GlobalState.VehicleImages or {}
                images[data.model] = thumbs[data.model]
                GlobalState.VehicleImages = images
                SaveThumbnails(data.model)
                SendThumbnailWebhook(data.model)
                SendGarageLineWebhook(data.model)
                log(('Saved thumbnail: %s -> %s'):format(data.model, data.img))
            end

            Citizen.CreateThread(function()
                Wait(300)
                local loaded = false
                LoadThumbnails(function() loaded = true end)
                local waited = 0
                while not loaded and waited < 100 do
                    Wait(100)
                    waited = waited + 1
                end
                if not loaded then
                    warn('Thumbnail loading timed out - continuing with an empty list.')
                end
                LoadCustomSpots()
                local vehicles = LoadVehicles()
                local vehicleImages = {}
                for modelName, thumb in pairs(thumbs) do
                    vehicleImages[modelName] = thumb
                end
                GlobalState.VehicleImages = vehicleImages
                GlobalState.CustomSpots   = customSpots
                log(string.format(
                    'Ready - %d vehicles | source=%s | %d spots | %d thumbnails | storage=%s | host=%s',
                    #vehicles, tostring(SOURCE), #customSpots, countThumbs(),
                    tostring(SAVE_MODE), tostring(Config.ImageHost or 'fivemanage')
                ))
                syncAllPlayers('resource start', 500)
            end)
            -- تنظيف الأجزاء المعلّقة التي لم تكتمل.
            Citizen.CreateThread(function()
                while true do
                    Wait(60000)
                    local now = os.time()
                    for key, buf in pairs(chunkBuffers) do
                        if now - (buf.at or now) > 120 then
                            chunkBuffers[key] = nil
                            log('Dropped an incomplete upload buffer: ' .. key, '^3')
                        end
                    end
                end
            end)
            RegisterNetEvent('M5_iCreator:upsertSpot')
            AddEventHandler('M5_iCreator:upsertSpot', function(spot)
                local src = source
                if not hasPermission(src) then return end
                if not spot or not spot.id then return end
                if spot.isDefault then return end
                spot = json.decode(json.encode(spot))
                local found = false
                for i, s in ipairs(customSpots) do
                    if s.id == spot.id then
                        customSpots[i] = spot
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(customSpots, spot)
                end
                GlobalState.CustomSpots = customSpots
                SaveCustomSpots()
                TriggerClientEvent('M5_iCreator:syncSpots', -1, customSpots)
                log(('Upserted spot "%s" (by player %d)'):format(spot.name or spot.id, src))
            end)
            RegisterNetEvent('M5_iCreator:deleteSpot')
            AddEventHandler('M5_iCreator:deleteSpot', function(id)
                local src = source
                if not hasPermission(src) then return end
                for i, s in ipairs(customSpots) do
                    if s.id == id then
                        log(('Deleted spot "%s" (by player %d)'):format(s.name or id, src))
                        table.remove(customSpots, i)
                        break
                    end
                end
                GlobalState.CustomSpots = customSpots
                SaveCustomSpots()
                TriggerClientEvent('M5_iCreator:syncSpots', -1, customSpots)
            end)
            RegisterNetEvent('renzu_vehthumb:save')
            AddEventHandler('renzu_vehthumb:save', function(data)
                local src = source
                if src ~= 0 and not hasPermission(src) then return end
                if not data or not data.model or not data.img then return end
                StoreThumbnail(data)
            end)
            -- استقبال أجزاء الصورة القادمة من اللاعب ثم رفعها إلى GitHub.
            RegisterNetEvent('M5_iCreator:githubChunk')
            AddEventHandler('M5_iCreator:githubChunk', function(chunk)
                local src = source
                if not hasPermission(src) then return end
                if type(chunk) ~= 'table' or type(chunk.uid) ~= 'string' then return end
                if type(chunk.data) ~= 'string' or #chunk.data > 200000 then return end
                local index, total = tonumber(chunk.index), tonumber(chunk.total)
                if not index or not total then return end
                if total < 1 or total > 500 or index < 1 or index > total then return end
                local key = ('%d:%s'):format(src, chunk.uid)
                local buf = chunkBuffers[key]
                if not buf then
                    buf = { parts = {}, count = 0, total = total, size = 0, at = os.time() }
                    chunkBuffers[key] = buf
                end
                if buf.parts[index] then return end
                buf.parts[index] = chunk.data
                buf.count = buf.count + 1
                buf.size  = buf.size + #chunk.data
                buf.at    = os.time()
                if buf.size > (tonumber(GH.maxBytes) or 12000000) then
                    chunkBuffers[key] = nil
                    warn('GitHub upload cancelled: image payload is too large.')
                    return
                end
                if type(chunk.meta) == 'table' and type(chunk.meta.model) == 'string' then
                    buf.meta = chunk.meta
                end
                if buf.count < buf.total or not buf.meta then return end
                chunkBuffers[key] = nil
                local meta    = buf.meta
                local content = table.concat(buf.parts)
                GithubUpload(meta, content, function(url, err)
                    if not url then
                        warn(('GitHub upload failed for %s: %s'):format(meta.model, tostring(err)))
                        TriggerClientEvent('M5_iCreator:uploadResult', src, meta.model, nil, err)
                        return
                    end
                    StoreThumbnail({
                        model    = meta.model,
                        img      = url,
                        name     = meta.name,
                        price    = meta.price,
                        garage   = meta.garage,
                        category = meta.category,
                    })
                    TriggerClientEvent('M5_iCreator:uploadResult', src, meta.model, url)
                end)
            end)
            RegisterNetEvent('M5_iCreator:exportGarage')
            AddEventHandler('M5_iCreator:exportGarage', function(auto)
                local src = source
                if src ~= 0 and not hasPermission(src) then return end
                if not GARAGE.enabled then return end
                -- auto = true يعني أن الطلب تلقائي بعد انتهاء جلسة التصوير.
                if auto == true and not GARAGE.sendOnFinish then return end
                ExportGarage()
            end)
            RegisterNetEvent('M5_iCreator:reloadVehicles')
            AddEventHandler('M5_iCreator:reloadVehicles', function()
                local src = source
                if src ~= 0 and not hasPermission(src) then return end
                local vehicles = LoadVehicles()
                TriggerClientEvent('M5_iCreator:vehiclesUpdated', -1)
                log(('Vehicle list reloaded: %d vehicles from "%s".'):format(#vehicles, tostring(SOURCE)))
            end)
            if Config.Commands and Config.Commands.export then
                RegisterCommand(Config.Commands.export, function(source)
                    if source ~= 0 and not hasPermission(source) then
                        TriggerClientEvent('chat:addMessage', source, {
                            args = { '^1[M5_iCreator]^0 Access denied.' }
                        })
                        return
                    end
                    local count = ExportGarage()
                    local msg = ('^2[M5_iCreator]^0 Garage export done (%d vehicles) -> %s')
                        :format(count, DATA_PATHS.garage)
                    if source == 0 then
                        print(msg)
                    else
                        TriggerClientEvent('chat:addMessage', source, { args = { msg } })
                    end
                end)
            end
            if Config.Commands and Config.Commands.reload then
                RegisterCommand(Config.Commands.reload, function(source)
                    if source ~= 0 and not hasPermission(source) then
                        TriggerClientEvent('chat:addMessage', source, {
                            args = { '^1[M5_iCreator]^0 Access denied.' }
                        })
                        return
                    end
                    local vehicles = LoadVehicles()
                    TriggerClientEvent('M5_iCreator:vehiclesUpdated', -1)
                    local msg = ('^2[M5_iCreator]^0 Loaded %d vehicles from "%s".')
                        :format(#vehicles, tostring(SOURCE))
                    if source == 0 then
                        print(msg)
                    else
                        TriggerClientEvent('chat:addMessage', source, { args = { msg } })
                    end
                end)
            end
            exports('GetVehicleThumbnail', function(model)
                return thumbs[model]
            end)
            exports('GetAllThumbnails', function()
                return thumbs
            end)
            exports('BuildGarageTable', function()
                if SOURCE == 'garage' then
                    return (BuildUpdatedGarageFile())
                end
                return (BuildGarageBlock())
            end)
            exports('ExportGarage', function()
                return ExportGarage()
            end)
            exports('ReloadVehicles', function()
                return #LoadVehicles()
            end)




            SendWebHook("Good License", 3066993, logValidResponse)
            Citizen.Wait(8000)
            for i = 1, 1 do
                print(string.format([[
           ^6________________________________________________________________________ ^7
           ^6\_______________________________________________________________________\^7

           ^2███╗░░░███╗███████╗ ^7
           ^2████╗░████║██╔════╝ ^7 ^2Working License, have a nice day^7
           ^2██╔████╔██║██████╗░ ^7 ^2Name Scripts: ^7%s^7
           ^2██║╚██╔╝██║╚════██╗ ^7 ^6 ==================================
           ^2██║░╚═╝░██║██████╔╝ ^7 ^1Made By: ^7Made By M547^7
           ^2╚═╝░░░░░╚═╝╚═════╝ ^7  ^1Discord: ^7discord.gg/MUS^7

           ^6________________________________________________________________________ ^7
           ^6\_______________________________________________________________________\^7
           ]], ProductName))
            end
        elseif (response == InvalidResponse) and LicenseKey ~= nil then
            SendWebHook("Wrong License", 15158332, logInvalidResponse)
            Citizen.Wait(8000)
            print([[
   ^6________________________________________________________________________ ^7
   ^6\_______________________________________________________________________\^7

   ^1███╗░░░███╗███████╗^7
   ^1████╗░████║██╔════╝^7 ^1Wrong License
   ^1██╔████╔██║██████╗░^7 ^1Contact With M547
   ^1██║╚██╔╝██║╚════██╗^7 ^1==================================
   ^1██║░╚═╝░██║██████╔╝^7 ^1Made By: ^7Made By M547^7
   ^1╚═╝░░░░░╚═╝╚═════╝^7 ^1Discord: ^7discord.gg/MUS^7

   ^6________________________________________________________________________ ^7
   ^6\_______________________________________________________________________\^7
   ]])
            print('^1[M&U STORE] cmd will be closed 5s^0')
            Citizen.Wait(1000)
            print('^1[M&U STORE] cmd will be closed 4s^0')
            Citizen.Wait(1000)
            print('^1[M&U STORE] cmd will be closed 3s^0')
            Citizen.Wait(1000)
            print('^1[M&U STORE] cmd will be closed 2s^0')
            Citizen.Wait(1000)
            print('^1[M&U STORE] cmd will be closed 1s^0')
            Citizen.Wait(1000)
            StopResource(GetCurrentResourceName())
            StopResource("vrp")
        elseif (response == "Invalid License") and LicenseKey ~= nil then
            SendWebHook("Not Found Key", 15105570, logNotfoundkey)
            Citizen.Wait(8000)
            print([[
   ^6________________________________________________________________________ ^7
   ^6\_______________________________________________________________________\^7

   ^1███╗░░░███╗███████╗^7
   ^1████╗░████║██╔════╝^7 ^1Not Found License
   ^1██╔████╔██║██████╗░^7 ^1Add The License And try again
   ^1██║╚██╔╝██║╚════██╗^7 ^1==================================
   ^1██║░╚═╝░██║██████╔╝^7 ^1Made By: ^7Made By M547^7
   ^1╚═╝░░░░░╚═╝╚═════╝^7 ^1Discord: ^7discord.gg/MUS^7

   ^6________________________________________________________________________ ^7
   ^6\_______________________________________________________________________\^7
   ]])
            print('^1[M&U STORE] cmd will be closed 5s^0')
            Citizen.Wait(1000)
            print('^1[M&U STORE] cmd will be closed 4s^0')
            Citizen.Wait(1000)
            print('^1[M&U STORE] cmd will be closed 3s^0')
            Citizen.Wait(1000)
            print('^1[M&U STORE] cmd will be closed 2s^0')
            Citizen.Wait(1000)
            print('^1[M&U STORE] cmd will be closed 1s^0')
            Citizen.Wait(1000)
            StopResource(GetCurrentResourceName())
            StopResource("vrp")
        else
            SendWebHook("Error", 15105570, logerror)
            Citizen.Wait(8000)
            print([[
   ^6________________________________________________________________________ ^7
   ^6\_______________________________________________________________________\^7

   ^1███╗░░░███╗███████╗^7
   ^1████╗░████║██╔════╝^7 ^1Error Please Try Again Later
   ^1██╔████╔██║██████╗░^7 ^1Contact With M547
   ^1██║╚██╔╝██║╚════██╗^7 ^1==================================
   ^1██║░╚═╝░██║██████╔╝^7 ^1Made By: ^7Made By M547^7
   ^1╚═╝░░░░░╚═╝╚═════╝^7 ^1Discord: ^7discord.gg/MUS^7

   ^6________________________________________________________________________ ^7
   ^6\_______________________________________________________________________\^7
   ]])
            print('^1[M&U STORE] cmd will be closed 5s^0')
            Citizen.Wait(1000)
            print('^1[M&U STORE] cmd will be closed 4s^0')
            Citizen.Wait(1000)
            print('^1[M&U STORE] cmd will be closed 3s^0')
            Citizen.Wait(1000)
            print('^1[M&U STORE] cmd will be closed 2s^0')
            Citizen.Wait(1000)
            print('^1[M&U STORE] cmd will be closed 1s^0')
            Citizen.Wait(1000)
            StopResource(GetCurrentResourceName())
        end
    else
        SendWebHook("Script changed name", 15105570, logScriptchangedname)
        Citizen.Wait(8000)
        print([[
   ^6________________________________________________________________________ ^7
   ^6\_______________________________________________________________________\^7

   ^1███╗░░░███╗███████╗^7
   ^1████╗░████║██╔════╝^7 ^1Don't Change The Script Name
   ^1██╔████╔██║██████╗░^7 ^1Don't Change The Script Name
   ^1██║╚██╔╝██║╚════██╗^7 ^1==================================
   ^1██║░╚═╝░██║██████╔╝^7 ^1Made By: ^7Made By M547^7
   ^1╚═╝░░░░░╚═╝╚═════╝^7 ^1Discord: ^7discord.gg/MUS^7

   ^6________________________________________________________________________ ^7
   ^6\_______________________________________________________________________\^7
   ]])
        print('^1[M&U STORE] cmd will be closed 5s^0')
        Citizen.Wait(1000)
        print('^1[M&U STORE] cmd will be closed 4s^0')
        Citizen.Wait(1000)
        print('^1[M&U STORE] cmd will be closed 3s^0')
        Citizen.Wait(1000)
        print('^1[M&U STORE] cmd will be closed 2s^0')
        Citizen.Wait(1000)
        print('^1[M&U STORE] cmd will be closed 1s^0')
        Citizen.Wait(1000)
        StopResource(GetCurrentResourceName())
        StopResource("vrp")
    end
end, 'POST', json.encode({ product = ProductUUID, license = LicenseKey }), { ['Content-Type'] = 'application/json' })
