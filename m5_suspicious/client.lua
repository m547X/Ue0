--[[
    m5_suspicious - client side
    ---------------------------------------------------------------
    Pure presentation. It never decides who is an admin and never sends
    anything the server does not re-validate. The only outgoing data is
    a record id, an action name, a duration index and a reason string.
]]

local L = Config.Locale[Config.Language] or Config.Locale.en

-- ============================================================
--  Drawing helpers
-- ============================================================

local function drawText(text, x, y, scale, font, r, g, b, a, align)
    SetTextFont(font or 4)
    SetTextScale(scale, scale)
    SetTextColour(r or 255, g or 255, b or 255, a or 255)
    SetTextEntry("STRING")
    if align == "center" then
        SetTextCentre(true)
    elseif align == "right" then
        SetTextWrap(0.0, x)
        SetTextRightJustify(true)
    end
    AddTextComponentString(text)
    DrawText(x, y)
end

local function drawRect(x, y, w, h, r, g, b, a)
    DrawRect(x + w / 2, y + h / 2, w, h, r, g, b, a)
end

local LEVEL_RGB = {
    LOW      = { 120, 200, 120 },
    MEDIUM   = { 235, 200, 90  },
    HIGH     = { 240, 150, 60  },
    CRITICAL = { 235, 70,  70  },
}

local function levelColor(level)
    local c = LEVEL_RGB[level] or LEVEL_RGB.LOW
    return c[1], c[2], c[3]
end

-- ============================================================
--  Notifications
-- ============================================================

local function notify(msg, kind)
    local prefix = kind == "error" and "~r~" or (kind == "success" and "~g~" or "~y~")
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName(prefix .. msg)
    EndTextCommandThefeedPostTicker(false, true)
end

RegisterNetEvent("m5_suspicious:notify", function(msg, kind)
    if type(msg) ~= "string" then return end
    notify(msg, kind)
end)

-- ============================================================
--  Suspicious player alert (admins only - the server picks the targets)
-- ============================================================

local alerts = {}

RegisterNetEvent("m5_suspicious:alert", function(data)
    if type(data) ~= "table" then return end

    alerts[#alerts + 1] = {
        data    = data,
        expires = GetGameTimer() + (tonumber(data.duration) or 12) * 1000,
    }

    if data.sound then
        PlaySoundFrontend(-1, data.critical and "Beep_Red" or "Beep_Green", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
    end
end)

CreateThread(function()
    while true do
        if #alerts == 0 then
            Wait(500)
        else
            local now = GetGameTimer()
            for i = #alerts, 1, -1 do
                if alerts[i].expires <= now then table.remove(alerts, i) end
            end

            local y = 0.28
            for _, alert in ipairs(alerts) do
                local d = alert.data
                local r, g, b = levelColor(d.level)
                local x, w, h = 0.735, 0.245, 0.185

                drawRect(x, y, w, h, 0, 0, 0, 190)
                drawRect(x, y, 0.004, h, r, g, b, 255)
                drawRect(x, y, w, 0.028, r, g, b, 90)

                drawText(("~y~⚠ %s"):format(d.title), x + 0.012, y + 0.004, 0.42, 4, 255, 255, 255, 255)
                drawText(("%d/100  %s"):format(d.score, d.level), x + w - 0.012, y + 0.004, 0.42, 4, r, g, b, 255, "right")

                local body = L.alert_body:format(
                    d.name or "?", d.serverId or "?", d.userId or "?",
                    d.score, d.level,
                    d.vpn, d.newAcc, d.sharedIP, d.sharedHW,
                    d.discord, d.fivem
                )

                local line = y + 0.036
                for text in (body .. "\n"):gmatch("(.-)\n") do
                    drawText(text, x + 0.012, line, 0.31, 4, 235, 235, 235, 235)
                    line = line + 0.0165
                end

                y = y + h + 0.012
            end

            Wait(0)
        end
    end
end)

-- ============================================================
--  Menu
-- ============================================================

local menu = {
    open     = false,
    view     = "list",   -- "list" | "detail" | "actions"
    entries  = {},
    index    = 1,
    page     = 1,
    selected = nil,
    actionIndex = 1,
    durationIndex = 1,
}

local ACTIONS = {
    { key = "details",     label = function() return L.menu_details end },
    { key = "ban_hwid",    label = function() return L.menu_ban_hwid end,    confirm = true },
    { key = "ban_license", label = function() return L.menu_ban_license end, confirm = true },
    { key = "ban_player",  label = function() return L.menu_ban_player end,  confirm = true },
    { key = "ignore",      label = function() return L.menu_ignore end },
    { key = "refresh",     label = function() return L.menu_refresh end },
}

local function closeMenu()
    menu.open = false
    menu.view = "list"
    menu.selected = nil
end

RegisterNetEvent("m5_suspicious:openMenu", function(entries)
    if type(entries) ~= "table" then return end
    menu.entries = entries
    menu.open = true
    if menu.index > #entries then menu.index = math.max(1, #entries) end
    if menu.view == "detail" or menu.view == "actions" then
        -- keep the current selection alive across a refresh
        local id = menu.selected and menu.selected.id
        menu.selected = nil
        for _, entry in ipairs(entries) do
            if entry.id == id then menu.selected = entry break end
        end
        if not menu.selected then menu.view = "list" end
    end
end)

local function askReason()
    AddTextEntry("M5_REASON", L.reason_prompt)
    DisplayOnscreenKeyboard(1, "M5_REASON", "", L.reason_default, "", "", "", 100)
    while UpdateOnscreenKeyboard() == 0 do
        DisableAllControlActions(0)
        Wait(0)
    end
    if UpdateOnscreenKeyboard() == 1 then
        return GetOnscreenKeyboardResult() or L.reason_default
    end
    return nil
end

local function sendAction(action)
    local entry = menu.selected
    if not entry then return end
    TriggerServerEvent("m5_suspicious:action", {
        id       = entry.id,
        action   = action,
        reason   = menu.pendingReason,
        duration = menu.durationIndex,
    })
    menu.pendingReason = nil
end

-- ---------- rendering ----------

local function drawList()
    local x, y, w = 0.30, 0.16, 0.40
    local pageSize = Config.MenuPageSize
    local total    = #menu.entries
    local pages    = math.max(1, math.ceil(total / pageSize))
    menu.page      = math.min(math.max(1, math.ceil(menu.index / pageSize)), pages)

    drawRect(x, y, w, 0.045, 20, 20, 20, 230)
    drawText("~y~" .. L.menu_title, x + w / 2, y + 0.010, 0.55, 4, 255, 255, 255, 255, "center")
    drawText(("%d/%d"):format(menu.page, pages), x + w - 0.010, y + 0.014, 0.34, 4, 180, 180, 180, 255, "right")

    local rowY = y + 0.048
    if total == 0 then
        drawRect(x, rowY, w, 0.032, 0, 0, 0, 190)
        drawText(L.menu_empty, x + 0.012, rowY + 0.006, 0.36, 4, 200, 200, 200, 255)
        return
    end

    local first = (menu.page - 1) * pageSize + 1
    local last  = math.min(first + pageSize - 1, total)

    for i = first, last do
        local entry    = menu.entries[i]
        local selected = i == menu.index
        local r, g, b  = levelColor(entry.level)

        drawRect(x, rowY, w, 0.032, selected and 45 or 0, selected and 45 or 0, selected and 45 or 0, selected and 235 or 185)
        drawRect(x, rowY, 0.0035, 0.032, r, g, b, 255)

        drawText(("%s ~s~[%s] %s"):format(selected and "~y~>" or " ", entry.serverId or "?", entry.name or "?"),
            x + 0.012, rowY + 0.006, 0.34, 4, 235, 235, 235, 255)
        drawText(("%d  %s%s"):format(entry.score, entry.level, entry.online and "" or (" ~c~(" .. L.menu_offline .. ")")),
            x + w - 0.010, rowY + 0.006, 0.34, 4, r, g, b, 255, "right")

        rowY = rowY + 0.034
    end

    drawRect(x, rowY, w, 0.030, 20, 20, 20, 210)
    drawText("~c~[↑↓] navigate   [Enter] open   [Backspace] close   [R] refresh",
        x + w / 2, rowY + 0.005, 0.30, 4, 200, 200, 200, 255, "center")
end

local function yesNo(v)
    if v == 1 then return "~r~" .. L.alert_yes end
    if v == 0 then return "~g~" .. L.alert_no end
    return "~c~" .. L.alert_unknown
end

local function drawDetail()
    local entry = menu.selected
    if not entry then menu.view = "list" return end

    local x, y, w = 0.28, 0.14, 0.44
    local r, g, b = levelColor(entry.level)

    drawRect(x, y, w, 0.045, 20, 20, 20, 235)
    drawText(("~y~%s ~s~(ID %s / UID %s)"):format(entry.name or "?", entry.serverId or "?", entry.userId or "-"),
        x + 0.012, y + 0.010, 0.46, 4, 255, 255, 255, 255)
    drawText(("%d/100  %s"):format(entry.score, entry.level), x + w - 0.010, y + 0.012, 0.42, 4, r, g, b, 255, "right")

    local rows = {
        { "Risk Level",      ("~s~%s%d/100 - %s"):format("", entry.score, entry.level) },
        { "Reasons",         #entry.reasons > 0 and table.concat(entry.reasons, ", ") or "-" },
        { "IP",              entry.ip },
        { "VPN / Proxy",     yesNo(entry.vpn) },
        { "New Account",     entry.newAcc and ("~r~" .. L.alert_yes) or ("~g~" .. L.alert_no) },
        { "Shared IP",       tostring(entry.sharedIP) },
        { "Shared HWID",     tostring(entry.sharedHW) },
        { "HWID Tokens",     tostring(entry.tokens) },
        { "License",         entry.license },
        { "Discord",         entry.discord },
        { "FiveM ID",        entry.fivem },
        { "Steam",           entry.steam },
        { "Location",        entry.location },
        { "First Detected",  entry.firstSeen },
        { "Status",          ("%s (%s)"):format(entry.status, entry.handledBy) },
        { "Online",          entry.online and ("~g~" .. L.alert_yes) or ("~c~" .. L.alert_no) },
    }

    local rowY = y + 0.048
    for _, row in ipairs(rows) do
        drawRect(x, rowY, w, 0.026, 0, 0, 0, 180)
        drawText("~c~" .. row[1], x + 0.012, rowY + 0.004, 0.31, 4, 180, 180, 180, 255)
        drawText(tostring(row[2] or "-"), x + 0.150, rowY + 0.004, 0.31, 4, 235, 235, 235, 255)
        rowY = rowY + 0.028
    end

    rowY = rowY + 0.008
    for i, action in ipairs(ACTIONS) do
        if action.key ~= "details" then
            local selected = i == menu.actionIndex
            drawRect(x, rowY, w, 0.028, selected and 60 or 15, selected and 60 or 15, selected and 60 or 15, 225)
            drawText((selected and "~y~> " or "  ") .. "~s~[" .. action.label() .. "]",
                x + 0.012, rowY + 0.005, 0.33, 4, 235, 235, 235, 255)
            if action.confirm then
                drawText("~c~" .. Config.BanDurations[menu.durationIndex].label,
                    x + w - 0.010, rowY + 0.005, 0.31, 4, 200, 200, 200, 255, "right")
            end
            rowY = rowY + 0.030
        end
    end

    drawRect(x, rowY, w, 0.030, 20, 20, 20, 210)
    drawText("~c~[↑↓] action   [←→] duration   [Enter] confirm   [Backspace] back",
        x + w / 2, rowY + 0.005, 0.30, 4, 200, 200, 200, 255, "center")
end

-- ---------- input ----------

local function selectableActions()
    local out = {}
    for i, action in ipairs(ACTIONS) do
        if action.key ~= "details" then out[#out + 1] = i end
    end
    return out
end

CreateThread(function()
    while true do
        if not menu.open then
            Wait(250)
        else
            DisableControlAction(0, 1, true)   -- look
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)  -- attack
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 106, true)

            if menu.view == "list" then
                drawList()

                if IsControlJustPressed(0, 172) then           -- up
                    menu.index = menu.index > 1 and menu.index - 1 or math.max(1, #menu.entries)
                elseif IsControlJustPressed(0, 173) then       -- down
                    menu.index = menu.index < #menu.entries and menu.index + 1 or 1
                elseif IsControlJustPressed(0, 191) or IsControlJustPressed(0, 201) then  -- enter
                    local entry = menu.entries[menu.index]
                    if entry then
                        menu.selected = entry
                        menu.actionIndex = selectableActions()[1] or 2
                        menu.view = "detail"
                    end
                elseif IsControlJustPressed(0, 177) then       -- backspace
                    closeMenu()
                elseif IsControlJustPressed(0, 45) then        -- R
                    TriggerServerEvent("m5_suspicious:requestList", true)
                end

            elseif menu.view == "detail" then
                drawDetail()

                local selectable = selectableActions()
                local pos = 1
                for i, idx in ipairs(selectable) do
                    if idx == menu.actionIndex then pos = i break end
                end

                if IsControlJustPressed(0, 172) then
                    pos = pos > 1 and pos - 1 or #selectable
                    menu.actionIndex = selectable[pos]
                elseif IsControlJustPressed(0, 173) then
                    pos = pos < #selectable and pos + 1 or 1
                    menu.actionIndex = selectable[pos]
                elseif IsControlJustPressed(0, 174) then       -- left
                    menu.durationIndex = menu.durationIndex > 1 and menu.durationIndex - 1 or #Config.BanDurations
                elseif IsControlJustPressed(0, 175) then       -- right
                    menu.durationIndex = menu.durationIndex < #Config.BanDurations and menu.durationIndex + 1 or 1
                elseif IsControlJustPressed(0, 177) then
                    menu.view = "list"
                elseif IsControlJustPressed(0, 191) or IsControlJustPressed(0, 201) then
                    local action = ACTIONS[menu.actionIndex]
                    if action then
                        if action.key == "refresh" then
                            TriggerServerEvent("m5_suspicious:requestList", true)
                        elseif action.confirm then
                            local reason = askReason()
                            if reason then
                                menu.pendingReason = reason
                                sendAction(action.key)
                                menu.view = "list"
                            end
                        else
                            sendAction(action.key)
                            menu.view = "list"
                        end
                    end
                end
            end

            Wait(0)
        end
    end
end)

-- ============================================================
--  Opening the menu (the server checks the permission)
-- ============================================================

RegisterCommand("+m5_suspicious_menu", function()
    TriggerServerEvent("m5_suspicious:requestList", true)
end, false)

if Config.MenuKey and Config.MenuKey ~= "" then
    RegisterKeyMapping("+m5_suspicious_menu", "Open the suspicious players menu", "keyboard", Config.MenuKey)
end
