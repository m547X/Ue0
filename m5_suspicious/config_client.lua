--[[
    m5_suspicious - CLIENT configuration
    ---------------------------------------------------------------
    This file is downloaded by every player, so it contains ONLY
    presentation settings. No webhook, no salt, no API key, no
    permission name, no scoring weight - those live in
    config_server.lua and never leave the server.
]]

Config = {}

-- ============================================================
--  Language
-- ============================================================

-- Language used for the menu and the on-screen alerts: "en" or "ar".
--
-- IMPORTANT: the in-game menu is drawn with the native GTA V fonts, which
-- contain NO Arabic glyphs - Arabic there renders as boxes. Keep this on "en"
-- unless you run a resource that replaces the game fonts with an Arabic-capable
-- one, or you rebuild the menu as NUI.
--
-- The connection screen and ban messages are NOT affected: they are rendered by
-- CEF and display Arabic correctly. Their language is set separately with
-- Config.KickLanguage in config_server.lua.
--
-- This value must match Config.MenuLanguage in config_server.lua, otherwise the
-- notifications sent by the server will be in a different language than the menu.
Config.Language = "en"

-- ============================================================
--  Menu
-- ============================================================

-- Optional key binding for the menu ("" disables it, the /suspicious command
-- always works). The server still checks the permission before anything opens.
Config.MenuKey = ""

-- Rows shown per page in the list view.
Config.MenuPageSize = 10

-- ============================================================
--  Ban duration labels
-- ============================================================

-- Display only. The client sends the *index* of the selected entry and the
-- server reads the real duration from Config.BanDurations in config_server.lua.
-- KEEP BOTH LISTS IN THE SAME ORDER.
Config.BanDurationLabels = {
    "Permanent",
    "30 Days",
    "7 Days",
    "24 Hours",
}

-- ============================================================
--  Colours per risk level
-- ============================================================

Config.LevelColors = {
    LOW      = { 120, 200, 120 },
    MEDIUM   = { 235, 200, 90  },
    HIGH     = { 240, 150, 60  },
    CRITICAL = { 235, 70,  70  },
}

-- ============================================================
--  Alert appearance
-- ============================================================

Config.Alert = {
    -- Screen position and size (0.0 - 1.0).
    X = 0.735,
    Y = 0.280,
    W = 0.245,
    H = 0.185,
    -- Gap between stacked alerts.
    Gap = 0.012,
}

-- ============================================================
--  Strings rendered by the client
-- ============================================================

Config.Locale = {
    en = {
        alert_title      = "SUSPICIOUS PLAYER",
        alert_body       = "Name: %s\nServer ID: %s\nUser ID: %s\n\nRisk Score: %s/100\nRisk Level: %s\n\nVPN/Proxy: %s\nNew Account: %s\nShared IP: %s\nShared HWID: %s\n\nDiscord: %s\nFiveM ID: %s",
        alert_yes        = "YES",
        alert_no         = "NO",
        alert_unknown    = "UNKNOWN",
        alert_none       = "N/A",

        menu_title       = "Suspicious Players",
        menu_empty       = "No suspicious players recorded.",
        menu_details     = "View Details",
        menu_ban_hwid    = "Ban HWID",
        menu_ban_license = "Ban License",
        menu_ban_player  = "Ban Player (HWID + License)",
        menu_ignore      = "Ignore",
        menu_refresh     = "Refresh",
        menu_back        = "Back",
        menu_offline     = "offline",

        hint_list        = "[UP/DOWN] navigate   [Enter] open   [Backspace] close   [R] refresh",
        hint_detail      = "[UP/DOWN] action   [LEFT/RIGHT] duration   [Enter] confirm   [Backspace] back",

        reason_prompt    = "Type the ban reason",
        reason_default   = "Suspicious activity",

        row_level        = "Risk Level",
        row_reasons      = "Reasons",
        row_ip           = "IP",
        row_vpn          = "VPN / Proxy",
        row_new          = "New Account",
        row_shared_ip    = "Shared IP",
        row_shared_hwid  = "Shared HWID",
        row_tokens       = "HWID Tokens",
        row_license      = "License",
        row_discord      = "Discord",
        row_fivem        = "FiveM ID",
        row_steam        = "Steam",
        row_location     = "Location",
        row_first_seen   = "First Detected",
        row_status       = "Status",
        row_online       = "Online",
    },

    -- ------------------------------------------------------------
    --  العربية - تحتاج خطاً يدعم العربية داخل اللعبة (انظر الملاحظة أعلى الملف)
    -- ------------------------------------------------------------
    ar = {
        alert_title      = "لاعب مشبوه",
        alert_body       = "الاسم: %s\nرقم السيرفر: %s\nرقم المستخدم: %s\n\nدرجة الخطورة: %s/100\nمستوى الخطورة: %s\n\nVPN/بروكسي: %s\nحساب جديد: %s\nIP مشترك: %s\nHWID مشترك: %s\n\nديسكورد: %s\nمعرّف FiveM: %s",
        alert_yes        = "نعم",
        alert_no         = "لا",
        alert_unknown    = "غير معروف",
        alert_none       = "غير متوفر",

        menu_title       = "اللاعبون المشبوهون",
        menu_empty       = "لا يوجد لاعبون مشبوهون مسجلون.",
        menu_details     = "عرض التفاصيل",
        menu_ban_hwid    = "حظر HWID",
        menu_ban_license = "حظر License",
        menu_ban_player  = "حظر اللاعب (HWID + License)",
        menu_ignore      = "تجاهل",
        menu_refresh     = "تحديث",
        menu_back        = "رجوع",
        menu_offline     = "غير متصل",

        hint_list        = "[أعلى/أسفل] تنقل   [Enter] فتح   [Backspace] إغلاق   [R] تحديث",
        hint_detail      = "[أعلى/أسفل] إجراء   [يسار/يمين] المدة   [Enter] تأكيد   [Backspace] رجوع",

        reason_prompt    = "اكتب سبب الحظر",
        reason_default   = "نشاط مشبوه",

        row_level        = "مستوى الخطورة",
        row_reasons      = "الأسباب",
        row_ip           = "الآي بي",
        row_vpn          = "VPN / بروكسي",
        row_new          = "حساب جديد",
        row_shared_ip    = "IP مشترك",
        row_shared_hwid  = "HWID مشترك",
        row_tokens       = "عدد التوكنات",
        row_license      = "License",
        row_discord      = "ديسكورد",
        row_fivem        = "معرّف FiveM",
        row_steam        = "ستيم",
        row_location     = "الموقع",
        row_first_seen   = "أول رصد",
        row_status       = "الحالة",
        row_online       = "متصل",
    },
}
