--[[
    m5_suspicious - SERVER configuration
    ---------------------------------------------------------------
    This file is NEVER sent to a client. Everything sensitive lives
    here: permissions, scoring weights, the HWID salt, the VPN API
    key and the Discord webhooks.
    Presentation settings are in config_client.lua.
]]

Config = {}

-- ============================================================
--  General
-- ============================================================

-- vRP permission required to see alerts / open the menu / take actions.
Config.AdminPermission = "admin.permission"

-- Permission required for the destructive actions (ban / unban).
-- Set to the same value as AdminPermission if you do not want a split.
Config.BanPermission = "admin.permission"

-- Language used for strings that are STORED or LOGGED: "en" or "ar".
Config.Language = "ar"

-- Language of the connection screen and the ban/kick messages.
-- These are rendered by CEF and display Arabic correctly.
Config.KickLanguage = "ar"

-- Language of the notifications the server pushes to an admin's screen.
-- Must match Config.Language in config_client.lua. Note that the in-game
-- fonts have no Arabic glyphs, so "ar" here shows boxes - see config_client.lua.
Config.MenuLanguage = "en"

-- Language used for the Discord embeds. Discord renders Arabic fine.
Config.LogLanguage = "ar"

-- Print extra information to the server console.
Config.Debug = false

-- ============================================================
--  Thresholds
-- ============================================================

-- A player is stored as "suspicious" and reported once the score reaches this.
Config.SuspiciousThreshold = 60

-- Score at which the alert is escalated (louder alert / @here on Discord).
Config.CriticalThreshold = 80

-- Risk levels. Evaluated top to bottom, the first matching `max` wins.
-- Colours per level are a client concern, see Config.LevelColors in config_client.lua.
Config.RiskLevels = {
    { name = "LOW",      max = 29  },
    { name = "MEDIUM",   max = 59  },
    { name = "HIGH",     max = 79  },
    { name = "CRITICAL", max = 100 },
}

-- ============================================================
--  Feature switches
-- ============================================================

Config.EnableVPNCheck      = true
Config.EnableDiscordLogs   = true
Config.EnableInGameAlerts  = true
Config.EnableGeoLookup     = true   -- country / region / city (same request as the VPN check)

-- ============================================================
--  Risk score weights (0 - 100 total, the score is clamped)
-- ============================================================

Config.RiskScore = {
    VPN            = 30,   -- VPN / proxy / hosting range detected
    NewAccount     = 15,   -- first time we ever see this player
    MissingFiveM   = 10,   -- no fivem: identifier
    MissingDiscord = 10,   -- no discord: identifier
    MissingSteam   = 5,    -- no steam: identifier
    SharedHWID     = 30,   -- one of the tokens belongs to another user_id
    SharedIP       = 15,   -- the IP belongs to another user_id
    FewTokens      = 10,   -- suspiciously low amount of tokens (spoofed client)
    BannedHWID     = 100,  -- token matches an active HWID ban
    BannedLicense  = 100,  -- license matches an active license ban
}

-- Extra weight per additional shared account, capped.
Config.SharedAccountStep = {
    HWID    = 5,   -- per extra user_id sharing a token
    IP      = 3,   -- per extra user_id sharing the IP
    MaxHWID = 20,
    MaxIP   = 12,
}

-- An account is "new" when it has been seen for less than this many hours.
Config.NewAccountHours = 24

-- Below this token count the client is considered tampered with.
Config.MinExpectedTokens = 2

-- ============================================================
--  HWID
-- ============================================================

Config.HWID = {
    Enabled     = true,
    CheckOnJoin = true,   -- reject banned tokens during playerConnecting
    Permanent   = true,   -- default ban duration when the admin does not pick one
    StoreTokens = true,   -- remember the tokens of every player (needed for Ban HWID)
    MaxTokens   = 16,     -- hard cap, protects the DB against token flooding
    -- Tokens are never stored raw: only a salted SHA-256 hash + a masked preview.
    -- CHANGE THIS SALT ONCE, BEFORE THE FIRST LAUNCH. Changing it later
    -- invalidates every stored hash (existing bans stop matching).
    Salt        = "CHANGE_ME_TO_A_LONG_RANDOM_STRING",
    -- Masking used for display: first N and last N characters of the raw token.
    MaskHead    = 8,
    MaskTail    = 6,
}

-- Preset durations offered in the ban menu (minutes, 0 = permanent).
-- The client only ever sends the INDEX of the chosen entry; the authoritative
-- duration is read here. Keep this list in the same order as
-- Config.BanDurationLabels in config_client.lua.
Config.BanDurations = {
    { label = "Permanent", minutes = 0 },
    { label = "30 Days",   minutes = 60 * 24 * 30 },
    { label = "7 Days",    minutes = 60 * 24 * 7 },
    { label = "24 Hours",  minutes = 60 * 24 },
}

-- ============================================================
--  Auto ban (disabled by default - never auto-ban on a single indicator)
-- ============================================================

Config.AutoBan = {
    Enabled   = false,
    -- Minimum score. Keep it high: a VPN alone must never be enough.
    Threshold = 100,
    -- Minimum number of *distinct* reasons required on top of the score.
    MinReasons = 3,
    -- "license", "hwid" or "both"
    Type      = "both",
    -- 0 = permanent
    Minutes   = 0,
    Reason    = "Automatic ban - risk score threshold exceeded",
}

-- ============================================================
--  VPN / Proxy detection
-- ============================================================

Config.VPN = {
    -- "ip-api" (free, no key, 45 req/min), "proxycheck" or "vpnapi"
    Provider = "ip-api",
    ApiKey   = "",
    -- Milliseconds to wait for the API before giving up. On timeout the player
    -- is NOT flagged; the connection continues normally.
    Timeout  = 4000,
    -- Cache lifetime per IP, in minutes.
    CacheMinutes = 720,
    -- Treat datacenter / hosting ranges as a VPN hit.
    FlagHosting = true,
    -- Never check these (LAN, loopback, whitelisted ranges) - Lua patterns.
    Whitelist = {
        "^127%.", "^10%.", "^192%.168%.", "^172%.1[6-9]%.", "^172%.2%d%.", "^172%.3[01]%.",
    },
}

-- ============================================================
--  Discord webhooks (leave empty to disable an individual log)
-- ============================================================

Config.Webhook = "YOUR_WEBHOOK"

Config.Webhooks = {
    Suspicious   = "",  -- falls back to Config.Webhook when empty
    HWIDBan      = "",
    HWIDDetected = "",
    Unban        = "",
    Error        = "",
}

Config.WebhookName   = "m5_suspicious"
Config.WebhookAvatar = ""
-- Ping this role id on CRITICAL detections ("" = no ping).
Config.WebhookCriticalRole = ""

Config.WebhookColors = {
    Suspicious   = 16776960,  -- yellow
    Critical     = 15158332,  -- red
    HWIDBan      = 10038562,  -- dark red
    HWIDDetected = 15105570,  -- orange
    Unban        = 3066993,   -- green
    Error        = 9807270,   -- grey
}

-- Show the (masked) IP inside Discord logs. Set to false to hide it entirely.
Config.WebhookShowIP = true

-- ============================================================
--  In-game alerts
-- ============================================================

Config.Alerts = {
    -- Only alert when the score is at least this high.
    MinScore   = 60,
    -- Also play a sound for the admins.
    Sound      = true,
    -- Seconds the on-screen notification stays visible.
    Duration   = 12,
    -- Never send an alert about the same user_id more than once per N seconds.
    Cooldown   = 300,
}

-- ============================================================
--  Menu / commands
-- ============================================================

Config.Command       = "suspicious"          -- /suspicious
-- How many entries the menu pulls from the DB.
Config.MenuHistory   = 50
-- Also include entries that were already handled.
Config.MenuShowHandled = false

-- ============================================================
--  Rate limiting (server side, per player)
-- ============================================================

Config.RateLimit = {
    -- Maximum admin events per window, per player.
    Events   = 12,
    Window   = 10,   -- seconds
    -- Consecutive violations before the player is logged/kicked.
    Strikes  = 5,
    KickOnAbuse = true,
    KickReason  = "Security violation",
}

-- ============================================================
--  Performance
-- ============================================================

Config.Cache = {
    -- Ban list cache lifetime in seconds. The cache is invalidated
    -- immediately whenever a ban/unban happens on this server.
    BanList  = 300,
    -- Suspicious list cache lifetime in seconds (menu refresh).
    Menu     = 15,
}

-- ============================================================
--  Messages (everything shown to a human)
-- ============================================================

Config.Locale = {
    en = {
        -- Connection screen / kick messages (CEF - Arabic renders correctly)
        connecting_check = "Running security checks...",
        connecting_done  = "Welcome!",
        banned_hwid      = "You are banned from this server.\n\nReason: %s\nBan ID: #%s\nExpires: %s",
        banned_license   = "You are banned from this server.\n\nReason: %s\nBan ID: #%s\nExpires: %s",
        ban_permanent    = "Never",

        -- Notifications pushed to an admin's screen (drawn with the game fonts)
        no_permission    = "You do not have permission to do that.",
        rate_limited     = "You are doing that too fast.",
        action_ok        = "Done: %s",
        action_failed    = "Action failed: %s",
        action_ignored   = "Marked as ignored",
        action_no_tokens = "No tokens stored for that player.",
        action_not_found = "record not found",

        -- Stored in the database when the admin leaves the reason empty
        reason_default   = "Suspicious activity",
    },

    -- ------------------------------------------------------------
    --  العربية
    -- ------------------------------------------------------------
    ar = {
        connecting_check = "جارٍ إجراء الفحوصات الأمنية...",
        connecting_done  = "أهلاً بك!",
        banned_hwid      = "أنت محظور من هذا السيرفر.\n\nالسبب: %s\nرقم الحظر: #%s\nينتهي في: %s",
        banned_license   = "أنت محظور من هذا السيرفر.\n\nالسبب: %s\nرقم الحظر: #%s\nينتهي في: %s",
        ban_permanent    = "دائم",

        no_permission    = "ليست لديك صلاحية للقيام بذلك.",
        rate_limited     = "أنت تكرر هذا الإجراء بسرعة كبيرة.",
        action_ok        = "تم: %s",
        action_failed    = "فشل الإجراء: %s",
        action_ignored   = "تم وضعه كمتجاهَل",
        action_no_tokens = "لا توجد توكنات مخزنة لهذا اللاعب.",
        action_not_found = "السجل غير موجود",

        reason_default   = "نشاط مشبوه",
    },
}

-- Reason labels used by the score engine (shown in the menu and on Discord).
Config.ReasonLabels = {
    en = {
        VPN            = "VPN / Proxy",
        NewAccount     = "New Account",
        MissingFiveM   = "Missing FiveM ID",
        MissingDiscord = "Missing Discord",
        MissingSteam   = "Missing Steam",
        SharedHWID     = "HWID shared with another account",
        SharedIP       = "IP shared with another account",
        FewTokens      = "Too few client tokens",
        BannedHWID     = "Banned HWID",
        BannedLicense  = "Banned License",
    },
    ar = {
        VPN            = "VPN / بروكسي",
        NewAccount     = "حساب جديد",
        MissingFiveM   = "معرّف FiveM مفقود",
        MissingDiscord = "ديسكورد مفقود",
        MissingSteam   = "ستيم مفقود",
        SharedHWID     = "HWID مرتبط بحساب آخر",
        SharedIP       = "IP مرتبط بحساب آخر",
        FewTokens      = "عدد التوكنات أقل من الطبيعي",
        BannedHWID     = "HWID محظور مسبقاً",
        BannedLicense  = "License محظور مسبقاً",
    },
}

-- Titles/labels used inside the Discord embeds, per language.
Config.LogLabels = {
    en = {
        suspicious   = "Suspicious Player",
        hwid_ban     = "HWID Ban",
        license_ban  = "License Ban",
        hwid_detect  = "Banned HWID Detected",
        hwid_unban   = "HWID Unban",
        license_unban = "License Unban",
        error        = "m5_suspicious error",

        name = "Name", server_id = "Server ID", user_id = "User ID",
        score = "Risk Score", level = "Risk Level", tokens = "Tokens",
        ip = "IP", vpn = "VPN", location = "Location", discord = "Discord",
        fivem = "FiveM", license = "License", shared = "Shared IP / HWID",
        reasons = "Reasons", player = "Player", banned_by = "Banned By",
        reason = "Reason", status = "Status", expires = "Expires",
        license_banned = "License Banned", masked_tokens = "Tokens (masked)",
        matched_token = "Matched Token", original_ban = "Original Ban ID",
        original_player = "Original Player", ban_id = "Ban ID",
        unbanned_by = "Unbanned By", message = "Message",
        yes = "YES", no = "NO", unknown = "UNKNOWN",
        permanent = "Permanent", temporary_until = "Temporary until",
        hidden = "hidden",
    },
    ar = {
        suspicious   = "لاعب مشبوه",
        hwid_ban     = "حظر HWID",
        license_ban  = "حظر License",
        hwid_detect  = "تم رصد HWID محظور",
        hwid_unban   = "فك حظر HWID",
        license_unban = "فك حظر License",
        error        = "خطأ في m5_suspicious",

        name = "الاسم", server_id = "رقم السيرفر", user_id = "رقم المستخدم",
        score = "درجة الخطورة", level = "مستوى الخطورة", tokens = "عدد التوكنات",
        ip = "الآي بي", vpn = "VPN", location = "الموقع", discord = "ديسكورد",
        fivem = "FiveM", license = "License", shared = "IP / HWID مشترك",
        reasons = "الأسباب", player = "اللاعب", banned_by = "بواسطة",
        reason = "السبب", status = "الحالة", expires = "ينتهي في",
        license_banned = "حظر License", masked_tokens = "التوكنات (مخفية جزئياً)",
        matched_token = "التوكن المطابق", original_ban = "رقم الحظر الأصلي",
        original_player = "اللاعب الأصلي", ban_id = "رقم الحظر",
        unbanned_by = "فُك بواسطة", message = "الرسالة",
        yes = "نعم", no = "لا", unknown = "غير معروف",
        permanent = "دائم", temporary_until = "مؤقت حتى",
        hidden = "مخفي",
    },
}
