--[[
    m5_suspicious - Configuration
    All tunable values live here. Nothing security-relevant is read from the client.
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

-- Locale used for the built-in strings (see Config.Locale below).
Config.Language = "en"

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
Config.RiskLevels = {
    { name = "LOW",      max = 29,  color = 2 },  -- chat colour index (client side)
    { name = "MEDIUM",   max = 59,  color = 5 },
    { name = "HIGH",     max = 79,  color = 17 },
    { name = "CRITICAL", max = 100, color = 6 },
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
Config.MenuKey       = ""                    -- optional RegisterKeyMapping key, "" to disable
Config.MenuPageSize  = 10
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
        connecting_check    = "Running security checks...",
        connecting_done     = "Welcome!",

        banned_hwid         = "You are banned from this server.\n\nReason: %s\nBan ID: #%s\nExpires: %s",
        banned_license      = "You are banned from this server.\n\nReason: %s\nBan ID: #%s\nExpires: %s",
        ban_permanent       = "Never",

        no_permission       = "You do not have permission to do that.",
        rate_limited        = "You are doing that too fast.",

        alert_title         = "SUSPICIOUS PLAYER",
        alert_body          = "Name: %s\nServer ID: %s\nUser ID: %s\n\nRisk Score: %s/100\nRisk Level: %s\n\nVPN/Proxy: %s\nNew Account: %s\nShared IP: %s\nShared HWID: %s\n\nDiscord: %s\nFiveM ID: %s",
        alert_yes           = "YES",
        alert_no            = "NO",
        alert_unknown       = "UNKNOWN",
        alert_none          = "N/A",

        menu_title          = "Suspicious Players",
        menu_empty          = "No suspicious players recorded.",
        menu_details        = "View Details",
        menu_ban_hwid       = "Ban HWID",
        menu_ban_license    = "Ban License",
        menu_ban_player     = "Ban Player (HWID + License)",
        menu_ignore         = "Ignore",
        menu_refresh        = "Refresh",
        menu_unban          = "Unban",
        menu_back           = "Back",
        menu_offline        = "offline",

        action_ok           = "Done: %s",
        action_failed       = "Action failed: %s",
        action_offline      = "That player is offline - stored tokens will be used.",
        action_no_tokens    = "No tokens stored for that player.",

        reason_prompt       = "Type the ban reason in chat, or /cancel",
        reason_default      = "Suspicious activity",
    },
}

-- Reason labels used by the score engine (shown in the menu and on Discord).
Config.ReasonLabels = {
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
}
