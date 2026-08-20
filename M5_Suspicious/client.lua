--[[ ============================================================
     M5_Suspicious  |  Client
     ------------------------------------------------------------
     عرض فقط. لا يقرر من هو الأدمن، ولا يرسل شيئاً لا يعيد
     السيرفر التحقق منه. كل ما يخرج من هنا: رقم السجل، اسم
     الإجراء، رقم المدة، ونص السبب.
     ============================================================ ]]

local L = Config.Locale[Config.Language] or Config.Locale.en

local menuOpen = false

-- ============================================================
--  أدوات  |  Helpers
-- ============================================================

local function direction()
    if Config.Direction == "rtl" or Config.Direction == "ltr" then
        return Config.Direction
    end
    return Config.Language == "ar" and "rtl" or "ltr"
end

--- الإشعارات تمر عبر الـ NUI وليس شريط اللعبة، لأن خطوط GTA
--- لا تدعم العربية.
local function notify(msg, kind)
    SendNUIMessage({
        action  = "notify",
        text    = msg,
        kind    = kind or "info",
        seconds = 5,
    })
end

--- تُرسل مرة واحدة عند الإقلاع وعند تبديل اللغة.
local function pushTheme()
    SendNUIMessage({
        action        = "theme",
        theme         = Config.Theme,
        dir           = direction(),
        alertPosition = Config.Alert.Position,
    })
    SendNUIMessage({
        action    = "locale",
        locale    = L,
        durations = Config.BanDurationLabels,
        pageSize  = Config.MenuPageSize,
    })
end

CreateThread(function()
    Wait(500)
    pushTheme()
end)

-- ============================================================
--  التنبيهات  |  Alerts
-- ============================================================

RegisterNetEvent("M5_Suspicious:alert", function(data)
    if type(data) ~= "table" then return end

    SendNUIMessage({
        action  = "alert",
        data    = data,
        seconds = tonumber(data.duration) or 12,
    })

    if Config.Alert.Sound and data.sound then
        PlaySoundFrontend(-1, data.critical and "Beep_Red" or "Beep_Green",
            "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
    end
end)

RegisterNetEvent("M5_Suspicious:notify", function(msg, kind)
    if type(msg) ~= "string" then return end
    notify(msg, kind)
end)

-- ============================================================
--  اللوحة  |  Panel
-- ============================================================

local function closeMenu()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "close" })
end

RegisterNetEvent("M5_Suspicious:openMenu", function(entries)
    if type(entries) ~= "table" then return end

    SendNUIMessage({ action = "open", entries = entries })

    -- عند التحديث تكون اللوحة مفتوحة أصلاً، فلا نعيد ضبط الفوكس.
    if not menuOpen then
        menuOpen = true
        SetNuiFocus(true, true)
    end
end)

-- ============================================================
--  استدعاءات الواجهة  |  NUI callbacks
-- ============================================================

RegisterNUICallback("close", function(_, cb)
    closeMenu()
    cb("ok")
end)

RegisterNUICallback("refresh", function(_, cb)
    TriggerServerEvent("M5_Suspicious:requestList", true)
    cb("ok")
end)

RegisterNUICallback("action", function(data, cb)
    -- لا تحقق هنا: السيرفر يعيد فحص الصلاحية والهدف والمدة بالكامل.
    if type(data) == "table" and data.id and data.action then
        TriggerServerEvent("M5_Suspicious:action", {
            id       = data.id,
            action   = data.action,
            reason   = data.reason,
            duration = data.duration,
        })
    end
    cb("ok")
end)

-- ============================================================
--  الفتح  |  Opening
-- ============================================================

RegisterCommand("+M5_Suspicious_menu", function()
    if menuOpen then
        closeMenu()
        return
    end
    TriggerServerEvent("M5_Suspicious:requestList", true)
end, false)

if Config.MenuKey and Config.MenuKey ~= "" then
    RegisterKeyMapping("+M5_Suspicious_menu", "M5 - فتح لوحة اللاعبين المشبوهين", "keyboard", Config.MenuKey)
end

-- شبكة أمان: لو أُوقف المورد واللوحة مفتوحة، لا يبقى الفوكس عالقاً.
AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        SetNuiFocus(false, false)
    end
end)
