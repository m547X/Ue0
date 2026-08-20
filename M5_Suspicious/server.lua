--[[ ============================================================
     M5_Suspicious  |  Server
     ------------------------------------------------------------
     كل قرار أمني يُتخذ هنا. الكلاينت مجرد واجهة عرض: يستقبل
     بيانات مفلترة مسبقاً، ولا يرسل إلا رقم سجل + اسم إجراء،
     ويُعاد التحقق منهما بالكامل في الأسفل.
     ============================================================ ]]

-- الـ Proxy مستخدم فقط لفحص الصلاحيات. كل ما عداه يُقرأ من SQL مباشرة.
local Proxy = module("vrp", "lib/Proxy")
vRP = Proxy.getInterface("vRP")

--- Locale lookup with a safe fallback chain: requested -> default -> en.
local function locale(lang)
    return Config.Locale[lang] or Config.Locale[Config.Language] or Config.Locale.en
end

local L  = locale(Config.Language)        -- general / stored strings
local LK = locale(Config.KickLanguage)    -- connection screen + kick messages (CEF, Arabic-safe)
local LM = locale(Config.MenuLanguage)    -- anything the client renders with the game fonts
local LG = Config.LogLabels[Config.LogLanguage] or Config.LogLabels.en   -- Discord embeds

-- ============================================================
--  0. Small helpers
-- ============================================================

local function dbg(...)
    if Config.Debug then
        print(("[M5_Suspicious] %s"):format(table.concat({ ... }, " ")))
    end
end

local function warn(msg)
    print(("[M5_Suspicious] ^3WARN^7 %s"):format(msg))
end

local function err(msg)
    print(("[M5_Suspicious] ^1ERROR^7 %s"):format(msg))
end

--- Clamp a number into a range.
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--- Trim + hard length limit for any free-text coming from a player.
local function sanitize(text, maxLen)
    if type(text) ~= "string" then return "" end
    text = text:gsub("[%z\1-\8\11\12\14-\31]", "")   -- control chars
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if #text > (maxLen or 128) then
        text = text:sub(1, maxLen or 128)
    end
    return text
end

-- ============================================================
--  1. SHA-256 (pure Lua 5.4, used to hash tokens before storage)
-- ============================================================

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local MASK32 = 0xFFFFFFFF

local function rrot(x, n)
    return ((x >> n) | (x << (32 - n))) & MASK32
end

local function sha256(message)
    local h1, h2, h3, h4 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h5, h6, h7, h8 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

    local len = #message
    local msg = message .. "\128" .. string.rep("\0", (55 - len) % 64) .. string.pack(">I8", len * 8)

    local w = {}
    for block = 1, #msg, 64 do
        for i = 0, 15 do
            w[i + 1] = string.unpack(">I4", msg, block + i * 4)
        end
        for i = 17, 64 do
            local v1, v2 = w[i - 15], w[i - 2]
            local s0 = rrot(v1, 7) ~ rrot(v1, 18) ~ (v1 >> 3)
            local s1 = rrot(v2, 17) ~ rrot(v2, 19) ~ (v2 >> 10)
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & MASK32
        end

        local a, b, c, d, e, f, g, h = h1, h2, h3, h4, h5, h6, h7, h8
        for i = 1, 64 do
            local S1  = rrot(e, 6) ~ rrot(e, 11) ~ rrot(e, 25)
            local ch  = (e & f) ~ ((~e & MASK32) & g)
            local t1  = (h + S1 + ch + K[i] + w[i]) & MASK32
            local S0  = rrot(a, 2) ~ rrot(a, 13) ~ rrot(a, 22)
            local maj = (a & b) ~ (a & c) ~ (b & c)
            local t2  = (S0 + maj) & MASK32
            h, g, f, e = g, f, e, (d + t1) & MASK32
            d, c, b, a = c, b, a, (t1 + t2) & MASK32
        end

        h1 = (h1 + a) & MASK32; h2 = (h2 + b) & MASK32
        h3 = (h3 + c) & MASK32; h4 = (h4 + d) & MASK32
        h5 = (h5 + e) & MASK32; h6 = (h6 + f) & MASK32
        h7 = (h7 + g) & MASK32; h8 = (h8 + h) & MASK32
    end

    return ("%08x%08x%08x%08x%08x%08x%08x%08x"):format(h1, h2, h3, h4, h5, h6, h7, h8)
end

--- Salted hash of a raw token. The raw value never leaves this function.
local function hashToken(raw)
    return sha256(Config.HWID.Salt .. "|" .. raw)
end

--- 8ca357ca...2b686b - safe to show in game and on Discord.
local function maskToken(raw)
    local head, tail = Config.HWID.MaskHead, Config.HWID.MaskTail
    if #raw <= head + tail then
        return raw:sub(1, 4) .. "..."
    end
    return raw:sub(1, head) .. "..." .. raw:sub(-tail)
end

local function maskIP(ip)
    if not ip or ip == "" then return "unknown" end
    local a, b = ip:match("^(%d+)%.(%d+)%.")
    if a then return ("%s.%s.x.x"):format(a, b) end
    return ip:sub(1, 8) .. "..."
end

-- ============================================================
--  2. Identifier & token collection
-- ============================================================

--- Returns every player token as a plain array. Wraps the two natives so the
--- rest of the file has a single entry point (and a hard cap on the count).
function GetPlayerTokens(src)
    local tokens, n = {}, GetNumPlayerTokens(src)
    if not n or n <= 0 then return tokens end
    for i = 0, math.min(n, Config.HWID.MaxTokens) - 1 do
        local token = GetPlayerToken(src, i)
        if token and token ~= "" then
            tokens[#tokens + 1] = token
        end
    end
    return tokens
end

local function collectIdentifiers(src)
    local ids = {
        license = nil, license2 = nil, discord = nil,
        steam = nil, fivem = nil, ip = nil, xbl = nil, live = nil,
    }
    local raw = {}
    for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
        raw[#raw + 1] = identifier
        local kind, value = identifier:match("^([^:]+):(.+)$")
        if kind then
            if kind == "license" and not ids.license then
                ids.license = identifier
            elseif ids[kind] == nil and ids[kind] ~= false then
                ids[kind] = identifier
            end
            if kind == "ip" then ids.ip = value end
        end
    end
    ids.raw = raw
    return ids
end

local function idValue(identifier)
    if not identifier then return nil end
    return (identifier:match("^[^:]+:(.+)$"))
end

-- ============================================================
--  3. Database layer
-- ============================================================

local DB = {}

local function query(sql, params)
    local ok, res = pcall(function()
        return MySQL.query.await(sql, params)
    end)
    if not ok then
        err(("query failed: %s"):format(tostring(res)))
        return nil
    end
    return res
end

local function insert(sql, params)
    local ok, res = pcall(function()
        return MySQL.insert.await(sql, params)
    end)
    if not ok then
        err(("insert failed: %s"):format(tostring(res)))
        return nil
    end
    return res
end

local function execute(sql, params)
    local ok, res = pcall(function()
        return MySQL.update.await(sql, params)
    end)
    if not ok then
        err(("execute failed: %s"):format(tostring(res)))
        return nil
    end
    return res
end

-- ---------- ban cache -------------------------------------------------
-- The full ban list is small (a few thousand rows at most) and is only
-- refreshed on a timer or when this server changes it, so a join costs
-- zero database round trips for the ban check.

local BanCache = {
    hwid    = {},   -- [token_hash] = ban row
    license = {},   -- [license]    = ban row
    loadedAt = 0,
}

local function rowExpired(row)
    if not row.expires_at then return false end
    local ts = row.expires_at
    if type(ts) == "number" then
        -- oxmysql may hand back a ms timestamp
        return (ts > 1e12 and ts / 1000 or ts) <= os.time()
    end
    local y, mo, d, hh, mm, ss = tostring(ts):match("(%d+)-(%d+)-(%d+)[T ](%d+):(%d+):(%d+)")
    if not y then return false end
    return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                     hour = tonumber(hh), min = tonumber(mm), sec = tonumber(ss) }) <= os.time()
end

function DB.refreshBanCache(force)
    if not force and (os.time() - BanCache.loadedAt) < Config.Cache.BanList then
        return
    end

    local hwid = query("SELECT id, token, token_mask, user_id, player_name, reason, banned_by, created_at, expires_at FROM hwid_bans WHERE active = 1", {})
    local lic  = query("SELECT id, license, user_id, player_name, reason, banned_by, created_at, expires_at FROM license_bans WHERE active = 1", {})

    if hwid == nil and lic == nil then
        -- keep whatever we had; do not open the gates because the DB blinked
        warn("ban cache refresh failed, keeping the previous cache")
        return
    end

    local h, l = {}, {}
    for _, row in ipairs(hwid or {}) do
        if not rowExpired(row) then h[row.token] = row end
    end
    for _, row in ipairs(lic or {}) do
        if not rowExpired(row) then l[row.license] = row end
    end

    BanCache.hwid, BanCache.license, BanCache.loadedAt = h, l, os.time()
    dbg(("ban cache: %d hwid / %d license"):format(#(hwid or {}), #(lic or {})))
end

local function invalidateBanCache()
    BanCache.loadedAt = 0
    DB.refreshBanCache(true)
end

-- ---------- writes ----------------------------------------------------

function DB.storeTokens(userId, license, tokenHashes)
    if not Config.HWID.StoreTokens then return end
    for _, t in ipairs(tokenHashes) do
        execute([[
            INSERT INTO player_tokens (user_id, license, token_hash, token_mask)
            VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE last_seen = NOW(), seen_count = seen_count + 1, license = VALUES(license)
        ]], { userId, license, t.hash, t.mask })
    end
end

function DB.storeHistory(info)
    execute([[
        INSERT INTO player_history (user_id, player_name, license, ip, discord, steam, fivem, country, region, city, token_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            last_seen = NOW(), join_count = join_count + 1, player_name = VALUES(player_name),
            ip = VALUES(ip), discord = VALUES(discord), steam = VALUES(steam), fivem = VALUES(fivem),
            country = VALUES(country), region = VALUES(region), city = VALUES(city),
            token_count = VALUES(token_count)
    ]], {
        info.user_id, info.name, info.license, info.ip, info.discord, info.steam, info.fivem,
        info.country, info.region, info.city, info.token_count,
    })
end

--- Everything the risk engine needs, in three queries instead of N.
function DB.gatherIntel(userId, license, ip, tokenHashes)
    local out = { sharedHWID = 0, sharedIP = 0, firstSeen = nil, joinCount = 0 }

    if #tokenHashes > 0 then
        local placeholders = {}
        local params = {}
        for _, t in ipairs(tokenHashes) do
            placeholders[#placeholders + 1] = "?"
            params[#params + 1] = t.hash
        end
        params[#params + 1] = userId or -1
        local rows = query(([[
            SELECT COUNT(DISTINCT user_id) AS c
            FROM player_tokens
            WHERE token_hash IN (%s) AND user_id IS NOT NULL AND user_id <> ?
        ]]):format(table.concat(placeholders, ",")), params)
        out.sharedHWID = (rows and rows[1] and tonumber(rows[1].c)) or 0
    end

    if ip and ip ~= "" then
        local rows = query([[
            SELECT COUNT(DISTINCT user_id) AS c
            FROM player_history
            WHERE ip = ? AND user_id IS NOT NULL AND user_id <> ?
        ]], { ip, userId or -1 })
        out.sharedIP = (rows and rows[1] and tonumber(rows[1].c)) or 0
    end

    local rows = query([[
        SELECT MIN(first_seen) AS first_seen, SUM(join_count) AS joins
        FROM player_history
        WHERE (user_id IS NOT NULL AND user_id = ?) OR license = ?
    ]], { userId or -1, license })
    if rows and rows[1] then
        out.firstSeen = rows[1].first_seen
        out.joinCount = tonumber(rows[1].joins) or 0
    end

    return out
end

-- ---------- vRP identity, resolved from SQL ---------------------------
-- vRP 0.5 answers proxy calls through a SHARED upvalue (proxy_rdata). When
-- the proxy handler errors, the caller silently receives the PREVIOUS call's
-- return value - i.e. another player's user_id. During playerConnecting that
-- handler does error, so identity is read straight from vRP's own tables.

local srcUserId = {}   -- [src] = user_id | false (resolved, none found)

function DB.userIdByIdentifiers(identifiers)
    if type(identifiers) ~= "table" or #identifiers == 0 then return nil end

    local holes, params = {}, {}
    for _, id in ipairs(identifiers) do
        holes[#holes + 1] = "?"
        params[#params + 1] = id
    end

    local rows = query(("SELECT %s AS uid FROM %s WHERE %s IN (%s) LIMIT 1"):format(
        Config.VRP.UserIdColumn, Config.VRP.IdentifiersTable,
        Config.VRP.IdentifierColumn, table.concat(holes, ",")), params)

    return rows and rows[1] and tonumber(rows[1].uid) or nil
end

--- Cached per source. Cleared on drop.
function DB.userIdOf(src)
    local cached = srcUserId[src]
    if cached ~= nil then return cached or nil end

    local userId = DB.userIdByIdentifiers(GetPlayerIdentifiers(src) or {})
    srcUserId[src] = userId or false
    return userId
end

--- Replacement for vRP.getUserSource, without the proxy.
function DB.sourceOf(userId)
    if not userId then return nil end
    for _, src in ipairs(GetPlayers()) do
        src = tonumber(src)
        if DB.userIdOf(src) == userId then return src end
    end
    return nil
end

--- Replacement for vRP.getUserIdentity, without the proxy.
function DB.identityOf(userId)
    if not userId then return nil end
    local rows = query(("SELECT firstname, name FROM %s WHERE user_id = ? LIMIT 1"):format(
        Config.VRP.IdentitiesTable), { userId })
    return rows and rows[1] or nil
end

AddEventHandler("playerDropped", function()
    srcUserId[source] = nil
end)

function DB.logAction(action, target, admin, details)
    insert([[
        INSERT INTO suspicious_actions (action, target_user, target_name, admin_user, admin_name, details)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { action, target.user_id, target.name, admin.user_id, admin.name, details })
end

-- ============================================================
--  4. IP intelligence (VPN / proxy / geo) - never blocking, never fatal
-- ============================================================

local IPIntel = {}
local ipMemCache = {}   -- [ip] = { vpn = -1/0/1, country, region, city, isp, at }

local function ipWhitelisted(ip)
    for _, pattern in ipairs(Config.VPN.Whitelist) do
        if ip:match(pattern) then return true end
    end
    return false
end

local function httpGet(url, timeout)
    local done, result = false, nil
    PerformHttpRequest(url, function(status, body)
        result = { status = status, body = body }
        done = true
    end, "GET", "", { ["User-Agent"] = "M5_Suspicious" })

    local waited = 0
    while not done and waited < timeout do
        Wait(50)
        waited = waited + 50
    end
    return result
end

--- Returns { vpn = -1|0|1, country, region, city, isp }.
--- vpn = -1 means "unknown" and is deliberately NOT scored.
function IPIntel.lookup(ip)
    local unknown = { vpn = -1 }
    if not Config.EnableVPNCheck or not ip or ip == "" or ipWhitelisted(ip) then
        return unknown
    end

    local mem = ipMemCache[ip]
    if mem and (os.time() - mem.at) < Config.VPN.CacheMinutes * 60 then
        return mem
    end

    local cached = query("SELECT vpn, country, region, city, isp, UNIX_TIMESTAMP(checked_at) AS ts FROM ip_intel_cache WHERE ip = ?", { ip })
    if cached and cached[1] and (os.time() - (tonumber(cached[1].ts) or 0)) < Config.VPN.CacheMinutes * 60 then
        local row = { vpn = tonumber(cached[1].vpn) or -1, country = cached[1].country,
                      region = cached[1].region, city = cached[1].city, isp = cached[1].isp, at = os.time() }
        ipMemCache[ip] = row
        return row
    end

    local provider, url = Config.VPN.Provider, nil
    if provider == "ip-api" then
        url = ("http://ip-api.com/json/%s?fields=status,country,regionName,city,isp,proxy,hosting"):format(ip)
    elseif provider == "proxycheck" then
        url = ("https://proxycheck.io/v2/%s?vpn=1&asn=1&key=%s"):format(ip, Config.VPN.ApiKey)
    elseif provider == "vpnapi" then
        url = ("https://vpnapi.io/api/%s?key=%s"):format(ip, Config.VPN.ApiKey)
    else
        warn(("unknown VPN provider '%s'"):format(tostring(provider)))
        return unknown
    end

    local res = httpGet(url, Config.VPN.Timeout)
    if not res or res.status ~= 200 or not res.body then
        warn(("VPN lookup failed for %s (provider %s) - player not flagged"):format(maskIP(ip), provider))
        return unknown
    end

    local ok, data = pcall(json.decode, res.body)
    if not ok or type(data) ~= "table" then
        warn("VPN lookup returned malformed JSON - player not flagged")
        return unknown
    end

    local out = { vpn = -1, at = os.time() }
    if provider == "ip-api" then
        if data.status == "success" then
            out.vpn = (data.proxy or (Config.VPN.FlagHosting and data.hosting)) and 1 or 0
            out.country, out.region, out.city, out.isp = data.country, data.regionName, data.city, data.isp
        end
    elseif provider == "proxycheck" then
        local entry = data[ip]
        if data.status == "ok" and type(entry) == "table" then
            out.vpn = (entry.proxy == "yes" or (Config.VPN.FlagHosting and entry.type == "Hosting")) and 1 or 0
            out.country, out.region, out.city, out.isp = entry.country, entry.region, entry.city, entry.provider
        else
            -- "denied" = bad key or quota exhausted, "error" = malformed query.
            -- Surface it: silently scoring every player as "unknown" hides a
            -- broken key for weeks.
            warn(("proxycheck returned status '%s'%s - check Config.VPN.ApiKey"):format(
                tostring(data.status), data.message and (": " .. tostring(data.message)) or ""))
        end
    elseif provider == "vpnapi" then
        local sec, loc = data.security, data.location
        if type(sec) == "table" then
            out.vpn = (sec.vpn or sec.proxy or sec.tor or (Config.VPN.FlagHosting and sec.relay)) and 1 or 0
            if type(loc) == "table" then
                out.country, out.region, out.city = loc.country, loc.region, loc.city
            end
        end
    end

    if not Config.EnableGeoLookup then
        out.country, out.region, out.city, out.isp = nil, nil, nil, nil
    end

    ipMemCache[ip] = out
    execute([[
        INSERT INTO ip_intel_cache (ip, vpn, country, region, city, isp, checked_at)
        VALUES (?, ?, ?, ?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE vpn = VALUES(vpn), country = VALUES(country), region = VALUES(region),
                                city = VALUES(city), isp = VALUES(isp), checked_at = NOW()
    ]], { ip, out.vpn, out.country, out.region, out.city, out.isp })

    return out
end

-- ============================================================
--  5. Discord webhooks
-- ============================================================

local Discord = {}

local function webhookFor(kind)
    local url = Config.Webhooks[kind]
    if url == nil or url == "" then url = Config.Webhook end
    if url == "YOUR_WEBHOOK" or url == "" then return nil end
    return url
end

function Discord.send(kind, embed, ping)
    if not Config.EnableDiscordLogs then return end
    local url = webhookFor(kind)
    if not url then return end

    local payload = {
        username   = Config.WebhookName,
        avatar_url = (Config.WebhookAvatar ~= "" and Config.WebhookAvatar) or nil,
        content    = (ping and Config.WebhookCriticalRole ~= "")
                        and ("<@&%s>"):format(Config.WebhookCriticalRole) or nil,
        embeds     = { embed },
    }

    PerformHttpRequest(url, function(status)
        if status ~= 200 and status ~= 204 then
            warn(("discord webhook '%s' responded with %s"):format(kind, tostring(status)))
        end
    end, "POST", json.encode(payload), { ["Content-Type"] = "application/json" })
end

local function field(name, value, inline)
    return { name = name, value = (value == nil or value == "") and "-" or tostring(value), inline = inline ~= false }
end

-- ============================================================
--  6. Risk engine
-- ============================================================

local function levelFor(score)
    for _, lvl in ipairs(Config.RiskLevels) do
        if score <= lvl.max then return lvl end
    end
    return Config.RiskLevels[#Config.RiskLevels]
end

--- Computes the score from an already-gathered profile.
--- Returns score (0-100), level table, reasons array.
local function computeRisk(profile)
    local score, reasons = 0, {}
    local W = Config.RiskScore

    local function add(key, points)
        if points <= 0 then return end
        score = score + points
        reasons[#reasons + 1] = key
    end

    if profile.bannedHWID    then add("BannedHWID", W.BannedHWID) end
    if profile.bannedLicense then add("BannedLicense", W.BannedLicense) end

    if profile.vpn == 1 then add("VPN", W.VPN) end

    if profile.newAccount then add("NewAccount", W.NewAccount) end

    if not profile.fivem   then add("MissingFiveM", W.MissingFiveM) end
    if not profile.discord then add("MissingDiscord", W.MissingDiscord) end
    if not profile.steam   then add("MissingSteam", W.MissingSteam) end

    if profile.tokenCount < Config.MinExpectedTokens then
        add("FewTokens", W.FewTokens)
    end

    if profile.sharedHWID > 0 then
        local extra = clamp((profile.sharedHWID - 1) * Config.SharedAccountStep.HWID, 0, Config.SharedAccountStep.MaxHWID)
        add("SharedHWID", W.SharedHWID + extra)
    end

    if profile.sharedIP > 0 then
        local extra = clamp((profile.sharedIP - 1) * Config.SharedAccountStep.IP, 0, Config.SharedAccountStep.MaxIP)
        add("SharedIP", W.SharedIP + extra)
    end

    return clamp(score, 0, 100), levelFor(clamp(score, 0, 100)), reasons
end

--- Translates reason keys into readable labels for the given language.
local function reasonLabels(reasons, lang)
    local labels = Config.ReasonLabels[lang or Config.Language] or Config.ReasonLabels.en
    local out = {}
    for _, key in ipairs(reasons) do
        out[#out + 1] = labels[key] or key
    end
    return out
end

-- ============================================================
--  7. Admin resolution & in-game alerts
-- ============================================================

local adminCache = { list = {}, at = 0 }

--- Permission is the one thing that genuinely has to go through vRP.
--- Guard it: ask for a permission nobody can hold first. A `true` there means
--- the proxy is replaying a stale result, so refuse everything this call.
local function vrpHasPermission(userId, permission)
    local ok, probe = pcall(function()
        return vRP.hasPermission({ userId, Config.VRP.ProbePermission })
    end)
    if not ok or probe == true then
        err("vRP proxy returned a stale/invalid result - permission denied for safety")
        return false
    end

    local ok2, granted = pcall(function()
        return vRP.hasPermission({ userId, permission })
    end)
    return ok2 and granted == true
end

local function isAdmin(src, permission)
    if not src or src <= 0 then return false end
    local userId = DB.userIdOf(src)
    if not userId then return false end
    return vrpHasPermission(userId, permission or Config.AdminPermission), userId
end

local function getAdmins()
    if (os.time() - adminCache.at) < 15 then
        return adminCache.list
    end
    local list = {}
    for _, src in ipairs(GetPlayers()) do
        src = tonumber(src)
        if isAdmin(src) then list[#list + 1] = src end
    end
    adminCache.list, adminCache.at = list, os.time()
    return list
end

local lastAlert = {}   -- [user_id or license] = os.time()

local function sendAlert(profile)
    if not Config.EnableInGameAlerts then return end
    if profile.score < Config.Alerts.MinScore then return end

    local key = tostring(profile.user_id or profile.license)
    if lastAlert[key] and (os.time() - lastAlert[key]) < Config.Alerts.Cooldown then
        return
    end
    lastAlert[key] = os.time()

    -- Raw values only: the client renders them with its own locale, so the
    -- menu language is owned entirely by config_client.lua.
    local payload = {
        name     = profile.name,
        serverId = profile.server_id,
        userId   = profile.user_id,
        score    = profile.score,
        level    = profile.level.name,
        vpn      = profile.vpn,                  -- 1 / 0 / -1
        newAcc   = profile.newAccount,           -- boolean
        sharedIP = profile.sharedIP,
        sharedHW = profile.sharedHWID,
        discord  = idValue(profile.discordId),   -- nil when missing
        fivem    = idValue(profile.fivemId),
        duration = Config.Alerts.Duration,
        sound    = Config.Alerts.Sound,
        critical = profile.score >= Config.CriticalThreshold,
    }

    for _, src in ipairs(getAdmins()) do
        TriggerClientEvent("M5_Suspicious:alert", src, payload)
    end
end

-- ============================================================
--  8. Connection pipeline
-- ============================================================

local function expiryText(expires, permanentWord)
    if not expires then return permanentWord or L.ban_permanent end
    return tostring(expires)
end

--- Full analysis. Runs inside the deferral thread.
local function analyse(src, name)
    local ids    = collectIdentifiers(src)
    local rawTokens = GetPlayerTokens(src)

    local tokens = {}
    for _, raw in ipairs(rawTokens) do
        tokens[#tokens + 1] = { hash = hashToken(raw), mask = maskToken(raw) }
    end

    local license = idValue(ids.license)
    local ip      = ids.ip

    -- vRP user id, if the player already exists. Read from SQL, never through
    -- the vRP proxy: during playerConnecting the proxy handler errors and the
    -- caller silently gets the previous player's id.
    local userId = DB.userIdByIdentifiers(ids.raw)

    DB.refreshBanCache(false)

    -- ---- ban checks (cheap, cached, no query) ----
    local bannedHWID, matchedToken
    if Config.HWID.Enabled and Config.HWID.CheckOnJoin then
        for _, t in ipairs(tokens) do
            local ban = BanCache.hwid[t.hash]
            if ban then bannedHWID, matchedToken = ban, t; break end
        end
    end
    local bannedLicense = license and BanCache.license[license] or nil

    local profile = {
        source     = src,
        server_id  = src,
        name       = name,
        user_id    = userId,
        license    = license,
        ip         = ip,
        discordId  = ids.discord,
        steamId    = ids.steam,
        fivemId    = ids.fivem,
        discord    = ids.discord,
        steam      = ids.steam,
        fivem      = ids.fivem,
        tokens     = tokens,
        tokenCount = #tokens,
        bannedHWID = bannedHWID,
        bannedLicense = bannedLicense,
        vpn        = -1,
        sharedHWID = 0,
        sharedIP   = 0,
        newAccount = false,
    }

    -- A banned player is rejected before we spend anything on APIs.
    if bannedHWID or bannedLicense then
        profile.matchedToken = matchedToken
        profile.score, profile.level, profile.reasons = computeRisk(profile)
        return profile, true
    end

    local intel = DB.gatherIntel(userId, license, ip, tokens)
    profile.sharedHWID = intel.sharedHWID
    profile.sharedIP   = intel.sharedIP
    profile.firstSeen  = intel.firstSeen
    profile.joinCount  = intel.joinCount
    profile.newAccount = (intel.joinCount or 0) == 0

    if not profile.newAccount and intel.firstSeen then
        local rows = query("SELECT TIMESTAMPDIFF(HOUR, ?, NOW()) AS h", { intel.firstSeen })
        local hours = rows and rows[1] and tonumber(rows[1].h)
        if hours and hours < Config.NewAccountHours then
            profile.newAccount = true
        end
    end

    local ipIntel = IPIntel.lookup(ip)
    profile.vpn     = ipIntel.vpn
    profile.country = ipIntel.country
    profile.region  = ipIntel.region
    profile.city    = ipIntel.city
    profile.isp     = ipIntel.isp

    profile.score, profile.level, profile.reasons = computeRisk(profile)
    return profile, false
end

local function logDetection(profile)
    local id = insert([[
        INSERT INTO suspicious_players
            (user_id, player_name, server_id, license, ip, discord, steam, fivem,
             risk_score, risk_level, reasons, vpn, new_account, shared_ip, shared_hwid,
             token_count, country, region, city)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        profile.user_id, profile.name, profile.server_id, profile.license, profile.ip,
        idValue(profile.discordId), idValue(profile.steamId), idValue(profile.fivemId),
        profile.score, profile.level.name, json.encode(profile.reasons),
        profile.vpn, profile.newAccount and 1 or 0, profile.sharedIP, profile.sharedHWID,
        profile.tokenCount, profile.country, profile.region, profile.city,
    })
    return id
end

local function webhookSuspicious(profile)
    local labels = reasonLabels(profile.reasons, Config.LogLanguage)
    local critical = profile.score >= Config.CriticalThreshold
    Discord.send("Suspicious", {
        title = (critical and "🚨 " or "⚠️ ") .. LG.suspicious,
        color = critical and Config.WebhookColors.Critical or Config.WebhookColors.Suspicious,
        fields = {
            field(LG.name, profile.name),
            field(LG.server_id, profile.server_id),
            field(LG.user_id, profile.user_id or "-"),
            field(LG.score, ("%d/100"):format(profile.score)),
            field(LG.level, profile.level.name),
            field(LG.tokens, profile.tokenCount),
            field(LG.ip, Config.WebhookShowIP and maskIP(profile.ip) or LG.hidden),
            field(LG.vpn, profile.vpn == 1 and LG.yes or (profile.vpn == 0 and LG.no or LG.unknown)),
            field(LG.location, profile.country and
                ("%s / %s"):format(profile.country, profile.city or "-") or "-"),
            field(LG.discord, idValue(profile.discordId)),
            field(LG.fivem, idValue(profile.fivemId)),
            field(LG.license, profile.license and (profile.license:sub(1, 20) .. "...") or "-"),
            field(LG.shared, ("%d / %d"):format(profile.sharedIP, profile.sharedHWID)),
            field(LG.reasons, "• " .. table.concat(labels, "\n• "), false),
        },
        footer = { text = os.date("%Y-%m-%d %H:%M:%S") },
    }, critical)
end

local function webhookHWIDDetected(profile)
    local ban = profile.bannedHWID
    Discord.send("HWIDDetected", {
        title = "🚨 " .. LG.hwid_detect,
        color = Config.WebhookColors.HWIDDetected,
        fields = {
            field(LG.player, profile.name),
            field(LG.server_id, profile.server_id),
            field(LG.matched_token, profile.matchedToken and profile.matchedToken.mask or ban.token_mask),
            field(LG.original_ban, "#" .. tostring(ban.id)),
            field(LG.original_player, ("%s (%s)"):format(ban.player_name or "-", ban.user_id or "-")),
            field(LG.reason, ban.reason, false),
            field(LG.expires, expiryText(ban.expires_at, LG.permanent), false),
        },
        footer = { text = os.date("%Y-%m-%d %H:%M:%S") },
    })
end

-- forward declaration, defined in section 9
local applyBan

AddEventHandler("playerConnecting", function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    deferrals.update(LK.connecting_check)

    local okRun, profile, rejected = pcall(analyse, src, name)
    if not okRun then
        -- Never let an internal failure lock players out of the server.
        err(("analysis crashed: %s"):format(tostring(profile)))
        Discord.send("Error", {
            title = "⚠️ " .. LG.error,
            color = Config.WebhookColors.Error,
            fields = { field(LG.message, tostring(profile), false) },
        })
        deferrals.done()
        return
    end

    if rejected then
        local ban = profile.bannedHWID or profile.bannedLicense
        local template = profile.bannedHWID and LK.banned_hwid or LK.banned_license
        local reason = template:format(ban.reason or "-", ban.id, expiryText(ban.expires_at, LK.ban_permanent))

        if profile.bannedHWID then
            webhookHWIDDetected(profile)
            DB.logAction("hwid_blocked", { user_id = profile.user_id, name = profile.name },
                { user_id = nil, name = "system" },
                ("matched ban #%s (%s)"):format(ban.id, profile.matchedToken and profile.matchedToken.mask or "-"))
        else
            DB.logAction("license_blocked", { user_id = profile.user_id, name = profile.name },
                { user_id = nil, name = "system" }, ("matched ban #%s"):format(ban.id))
        end

        deferrals.done(reason)
        return
    end

    -- Remember what we saw. Cheap enough to do for everyone, and it is what
    -- makes "shared HWID / shared IP / new account" meaningful later on.
    DB.storeHistory({
        user_id = profile.user_id, name = profile.name, license = profile.license, ip = profile.ip,
        discord = idValue(profile.discordId), steam = idValue(profile.steamId), fivem = idValue(profile.fivemId),
        country = profile.country, region = profile.region, city = profile.city,
        token_count = profile.tokenCount,
    })
    DB.storeTokens(profile.user_id, profile.license, profile.tokens)

    if profile.score >= Config.SuspiciousThreshold then
        profile.recordId = logDetection(profile)
        webhookSuspicious(profile)
        sendAlert(profile)

        if Config.AutoBan.Enabled
            and profile.score >= Config.AutoBan.Threshold
            and #profile.reasons >= Config.AutoBan.MinReasons then
            applyBan(profile, Config.AutoBan.Type, Config.AutoBan.Minutes,
                Config.AutoBan.Reason, { user_id = nil, name = "auto" })
            deferrals.done(LK.banned_license:format(Config.AutoBan.Reason, "auto", LK.ban_permanent))
            return
        end
    end

    deferrals.update(LK.connecting_done)
    deferrals.done()
end)

-- Alerts for admins that were already in game are handled above; an admin who
-- joins after a detection simply opens the menu.
AddEventHandler("playerDropped", function()
    adminCache.at = 0
end)

-- ============================================================
--  9. Ban / unban logic
-- ============================================================

local function expiryFromMinutes(minutes)
    if not minutes or minutes <= 0 then return nil end
    return os.date("%Y-%m-%d %H:%M:%S", os.time() + minutes * 60)
end

--- Collects the tokens to ban: live ones when the player is online,
--- otherwise the stored hashes.
local function tokensForTarget(target)
    local out = {}

    local src = target.source or DB.sourceOf(target.user_id)

    if src and GetPlayerName(src) then
        for _, raw in ipairs(GetPlayerTokens(src)) do
            out[#out + 1] = { hash = hashToken(raw), mask = maskToken(raw) }
        end
    end

    if #out == 0 then
        local rows = query([[
            SELECT token_hash, token_mask FROM player_tokens
            WHERE (user_id IS NOT NULL AND user_id = ?) OR (license IS NOT NULL AND license = ?)
            ORDER BY last_seen DESC LIMIT ?
        ]], { target.user_id or -1, target.license, Config.HWID.MaxTokens })
        for _, row in ipairs(rows or {}) do
            out[#out + 1] = { hash = row.token_hash, mask = row.token_mask }
        end
    end

    return out
end

--- kind: "hwid" | "license" | "both"
--- Returns ok, message, info
applyBan = function(target, kind, minutes, reason, admin)
    reason = sanitize(reason, 200)
    if reason == "" then reason = L.reason_default end
    local expires = expiryFromMinutes(minutes)
    local groupId = ("%d-%d"):format(os.time(), math.random(1000, 9999))
    local banned = { hwid = 0, license = false, ids = {}, masks = {} }

    if kind == "hwid" or kind == "both" then
        if not Config.HWID.Enabled then
            return false, "HWID bans are disabled in the config"
        end
        local tokens = tokensForTarget(target)
        if #tokens == 0 then
            if kind == "hwid" then return false, LM.action_no_tokens end
        end
        for _, t in ipairs(tokens) do
            local id = insert([[
                INSERT INTO hwid_bans (token, token_mask, user_id, player_name, reason, banned_by, banned_by_id, group_id, expires_at, active)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
                ON DUPLICATE KEY UPDATE active = 1, reason = VALUES(reason), banned_by = VALUES(banned_by),
                                        banned_by_id = VALUES(banned_by_id), group_id = VALUES(group_id),
                                        expires_at = VALUES(expires_at), created_at = NOW()
            ]], { t.hash, t.mask, target.user_id, target.name, reason, admin.name or "console", admin.user_id, groupId, expires })
            banned.hwid = banned.hwid + 1
            banned.ids[#banned.ids + 1] = id
            banned.masks[#banned.masks + 1] = t.mask
        end
    end

    if (kind == "license" or kind == "both") and target.license then
        insert([[
            INSERT INTO license_bans (license, user_id, player_name, reason, banned_by, banned_by_id, expires_at, active)
            VALUES (?, ?, ?, ?, ?, ?, ?, 1)
            ON DUPLICATE KEY UPDATE active = 1, reason = VALUES(reason), banned_by = VALUES(banned_by),
                                    banned_by_id = VALUES(banned_by_id), expires_at = VALUES(expires_at), created_at = NOW()
        ]], { target.license, target.user_id, target.name, reason, admin.name or "console", admin.user_id, expires })
        banned.license = true
    end

    if banned.hwid == 0 and not banned.license then
        return false, LM.action_no_tokens
    end

    invalidateBanCache()

    DB.logAction("ban_" .. kind, target, admin,
        ("tokens=%d license=%s expires=%s reason=%s"):format(
            banned.hwid, tostring(banned.license), expires or "never", reason))

    Discord.send("HWIDBan", {
        title = "🔨 " .. (kind == "license" and LG.license_ban or LG.hwid_ban),
        color = Config.WebhookColors.HWIDBan,
        fields = {
            field(LG.player, target.name or "-"),
            field(LG.user_id, target.user_id or "-"),
            field(LG.server_id, target.source or "-"),
            field(LG.banned_by, admin.name or "console"),
            field(LG.reason, reason, false),
            field(LG.tokens, banned.hwid),
            field(LG.license_banned, banned.license and LG.yes or LG.no),
            field(LG.status, expires and (LG.temporary_until .. " " .. expires) or LG.permanent),
            field(LG.masked_tokens, #banned.masks > 0 and table.concat(banned.masks, "\n") or "-", false),
        },
        footer = { text = os.date("%Y-%m-%d %H:%M:%S") },
    })

    -- Drop the player if they are still connected.
    local src = target.source or DB.sourceOf(target.user_id)
    if src and GetPlayerName(src) then
        DropPlayer(src, LK.banned_hwid:format(reason, banned.ids[1] or "-", expires or LK.ban_permanent))
    end

    return true, ("%d token(s)%s banned"):format(banned.hwid, banned.license and " + license" or "")
end

local function unbanHWID(banId, admin)
    local rows = query("SELECT id, group_id, token_mask, user_id, player_name FROM hwid_bans WHERE id = ?", { banId })
    if not rows or not rows[1] then return false, "Ban not found" end
    local row = rows[1]

    if row.group_id then
        execute("UPDATE hwid_bans SET active = 0, unbanned_by = ?, unbanned_at = NOW() WHERE group_id = ? AND active = 1",
            { admin.name or "console", row.group_id })
    else
        execute("UPDATE hwid_bans SET active = 0, unbanned_by = ?, unbanned_at = NOW() WHERE id = ?",
            { admin.name or "console", banId })
    end

    invalidateBanCache()
    DB.logAction("unban_hwid", { user_id = row.user_id, name = row.player_name }, admin, "ban #" .. banId)
    Discord.send("Unban", {
        title = "✅ " .. LG.hwid_unban,
        color = Config.WebhookColors.Unban,
        fields = {
            field(LG.ban_id, "#" .. banId),
            field(LG.player, row.player_name or "-"),
            field(LG.user_id, row.user_id or "-"),
            field(LG.unbanned_by, admin.name or "console"),
        },
    })
    return true, "Unbanned"
end

local function unbanLicense(license, admin)
    local affected = execute("UPDATE license_bans SET active = 0, unbanned_by = ?, unbanned_at = NOW() WHERE license = ? AND active = 1",
        { admin.name or "console", license })
    if not affected or affected == 0 then return false, "No active ban for that license" end
    invalidateBanCache()
    DB.logAction("unban_license", { user_id = nil, name = license }, admin, license)
    Discord.send("Unban", {
        title = "✅ " .. LG.license_unban,
        color = Config.WebhookColors.Unban,
        fields = { field(LG.license, license), field(LG.unbanned_by, admin.name or "console") },
    })
    return true, "Unbanned"
end

-- ============================================================
--  10. Admin API (net events) - permission + rate limited
-- ============================================================

local rate = {}   -- [src] = { count, window, strikes }

local function rateLimited(src)
    local now = os.time()
    local entry = rate[src]
    if not entry or (now - entry.window) >= Config.RateLimit.Window then
        rate[src] = { count = 1, window = now, strikes = entry and entry.strikes or 0 }
        return false
    end
    entry.count = entry.count + 1
    if entry.count > Config.RateLimit.Events then
        entry.strikes = entry.strikes + 1
        if Config.RateLimit.KickOnAbuse and entry.strikes >= Config.RateLimit.Strikes then
            warn(("kicking %s for event spam"):format(GetPlayerName(src) or src))
            DropPlayer(src, Config.RateLimit.KickReason)
        end
        return true
    end
    return false
end

AddEventHandler("playerDropped", function()
    rate[source] = nil
end)

--- Wraps a handler with the permission + rate-limit checks.
--- The handler receives (src, adminUserId, adminName, ...).
local function guarded(permissionKey, handler)
    return function(...)
        local src = source
        if rateLimited(src) then
            TriggerClientEvent("M5_Suspicious:notify", src, LM.rate_limited, "error")
            return
        end
        local allowed, userId = isAdmin(src, permissionKey)
        if not allowed then
            warn(("unauthorized event from %s (%s)"):format(GetPlayerName(src) or "?", src))
            TriggerClientEvent("M5_Suspicious:notify", src, LM.no_permission, "error")
            return
        end
        local identity = DB.identityOf(userId)
        local adminName = identity and ("%s %s"):format(identity.firstname or "", identity.name or "")
                          or (GetPlayerName(src) or "admin")
        handler(src, userId, sanitize(adminName, 90), ...)
    end
end

-- ---------- menu list -------------------------------------------------

local menuCache = { data = nil, at = 0 }

local function buildMenu(force)
    if not force and menuCache.data and (os.time() - menuCache.at) < Config.Cache.Menu then
        return menuCache.data
    end

    local statusFilter = Config.MenuShowHandled and "" or "WHERE status = 'pending'"
    local rows = query(([[
        SELECT id, user_id, player_name, server_id, license, ip, discord, steam, fivem,
               risk_score, risk_level, reasons, vpn, new_account, shared_ip, shared_hwid,
               token_count, country, region, city, status, handled_by, created_at
        FROM suspicious_players
        %s
        ORDER BY created_at DESC
        LIMIT ?
    ]]):format(statusFilter), { Config.MenuHistory }) or {}

    local list = {}
    for _, row in ipairs(rows) do
        local okDec, reasons = pcall(json.decode, row.reasons or "[]")
        if not okDec or type(reasons) ~= "table" then reasons = {} end

        local online = row.user_id ~= nil and DB.sourceOf(row.user_id) ~= nil

        list[#list + 1] = {
            id       = row.id,
            userId   = row.user_id,
            name     = row.player_name,
            serverId = row.server_id,
            score    = row.risk_score,
            level    = row.risk_level,
            reasons  = reasonLabels(reasons, Config.MenuLanguage),
            -- Only masked / partial values are ever shipped to a client.
            ip       = maskIP(row.ip),
            license  = row.license and (row.license:sub(1, 24) .. "...") or "-",
            discord  = row.discord or "-",
            fivem    = row.fivem or "-",
            steam    = row.steam or "-",
            tokens   = row.token_count,
            firstSeen = tostring(row.created_at),
            vpn      = tonumber(row.vpn) or -1,
            newAcc   = row.new_account == 1,
            sharedIP = row.shared_ip,
            sharedHW = row.shared_hwid,
            location = row.country and ("%s / %s / %s"):format(row.country, row.region or "-", row.city or "-") or "-",
            status   = row.status,
            handledBy = row.handled_by or "-",
            online   = online,
        }
    end

    menuCache.data, menuCache.at = list, os.time()
    return list
end

RegisterNetEvent("M5_Suspicious:requestList", guarded(Config.AdminPermission, function(src, _, _, force)
    TriggerClientEvent("M5_Suspicious:openMenu", src, buildMenu(force == true))
end))

-- ---------- resolve a menu row into a real target ---------------------

local function targetFromRecord(recordId)
    local rows = query("SELECT id, user_id, player_name, license FROM suspicious_players WHERE id = ?", { recordId })
    if not rows or not rows[1] then return nil end
    local row = rows[1]

    local src = DB.sourceOf(row.user_id)

    return {
        recordId = row.id,
        user_id  = row.user_id,
        name     = row.player_name,
        license  = row.license,
        source   = src,   -- resolved server side; the client's value is ignored
    }
end

local function markHandled(recordId, adminName, status)
    execute("UPDATE suspicious_players SET status = ?, handled_by = ?, handled_at = NOW() WHERE id = ?",
        { status, adminName, recordId })
    menuCache.at = 0
end

RegisterNetEvent("M5_Suspicious:action", guarded(Config.BanPermission, function(src, adminUserId, adminName, payload)
    if type(payload) ~= "table" then return end

    local recordId = tonumber(payload.id)
    local action   = tostring(payload.action or "")
    if not recordId then return end

    local target = targetFromRecord(recordId)
    if not target then
        TriggerClientEvent("M5_Suspicious:notify", src, LM.action_failed:format(LM.action_not_found), "error")
        return
    end

    local admin = { user_id = adminUserId, name = adminName }

    if action == "ignore" then
        markHandled(recordId, adminName, "ignored")
        DB.logAction("ignore", target, admin, "record #" .. recordId)
        TriggerClientEvent("M5_Suspicious:notify", src, LM.action_ok:format(LM.action_ignored), "success")
        TriggerClientEvent("M5_Suspicious:openMenu", src, buildMenu(true))
        return
    end

    local kind
    if action == "ban_hwid" then kind = "hwid"
    elseif action == "ban_license" then kind = "license"
    elseif action == "ban_player" then kind = "both"
    else
        warn(("unknown action '%s' from %s"):format(action, src))
        return
    end

    -- Duration comes from the config table by index, never as a raw number.
    local duration = Config.BanDurations[tonumber(payload.duration) or 1] or Config.BanDurations[1]
    local minutes  = duration.minutes
    if Config.HWID.Permanent and payload.duration == nil then minutes = 0 end

    local ok, message = applyBan(target, kind, minutes, payload.reason, admin)
    if ok then
        markHandled(recordId, adminName, "actioned")
        TriggerClientEvent("M5_Suspicious:notify", src, LM.action_ok:format(message), "success")
        TriggerClientEvent("M5_Suspicious:openMenu", src, buildMenu(true))
    else
        TriggerClientEvent("M5_Suspicious:notify", src, LM.action_failed:format(message), "error")
    end
end))

-- ============================================================
--  11. Commands
-- ============================================================

RegisterCommand(Config.Command, function(src)
    if src == 0 then
        print("[M5_Suspicious] this command is in-game only, use 'suspicious_list'")
        return
    end
    if not isAdmin(src) then
        TriggerClientEvent("M5_Suspicious:notify", src, LM.no_permission, "error")
        return
    end
    TriggerClientEvent("M5_Suspicious:openMenu", src, buildMenu(true))
end, false)

RegisterCommand("suspicious_list", function(src)
    if src ~= 0 then return end
    for _, entry in ipairs(buildMenu(true)) do
        print(("#%d  %s (uid %s)  score %d  %s  [%s]"):format(
            entry.id, entry.name or "?", tostring(entry.userId), entry.score, entry.level, entry.status))
    end
end, true)

RegisterCommand("unbanhwid", function(src, args)
    local admin = { user_id = nil, name = "console" }
    if src ~= 0 then
        local allowed, userId = isAdmin(src, Config.BanPermission)
        if not allowed then
            TriggerClientEvent("M5_Suspicious:notify", src, LM.no_permission, "error")
            return
        end
        admin = { user_id = userId, name = GetPlayerName(src) }
    end
    local id = tonumber(args[1])
    if not id then
        print("usage: unbanhwid <ban id>")
        return
    end
    local ok, msg = unbanHWID(id, admin)
    if src == 0 then print(msg) else
        TriggerClientEvent("M5_Suspicious:notify", src, msg, ok and "success" or "error")
    end
end, true)

RegisterCommand("unbanlicense", function(src, args)
    local admin = { user_id = nil, name = "console" }
    if src ~= 0 then
        local allowed, userId = isAdmin(src, Config.BanPermission)
        if not allowed then
            TriggerClientEvent("M5_Suspicious:notify", src, LM.no_permission, "error")
            return
        end
        admin = { user_id = userId, name = GetPlayerName(src) }
    end
    local license = sanitize(args[1], 80)
    if license == "" then
        print("usage: unbanlicense <license:...>")
        return
    end
    local ok, msg = unbanLicense(license, admin)
    if src == 0 then print(msg) else
        TriggerClientEvent("M5_Suspicious:notify", src, msg, ok and "success" or "error")
    end
end, true)

-- ============================================================
--  12. Exports & housekeeping
-- ============================================================

exports("banHWID", function(userId, reason, minutes, adminName)
    return applyBan({ user_id = userId, name = nil, license = nil }, "hwid",
        minutes or 0, reason, { user_id = nil, name = adminName or "script" })
end)

exports("banPlayer", function(userId, license, reason, minutes, adminName)
    return applyBan({ user_id = userId, license = license }, "both",
        minutes or 0, reason, { user_id = nil, name = adminName or "script" })
end)

exports("isHWIDBanned", function(src)
    DB.refreshBanCache(false)
    for _, raw in ipairs(GetPlayerTokens(src)) do
        local ban = BanCache.hwid[hashToken(raw)]
        if ban then return true, ban.id, ban.reason end
    end
    return false
end)

CreateThread(function()
    Wait(2000)

    if Config.HWID.Salt == "CHANGE_ME_TO_A_LONG_RANDOM_STRING" then
        warn("Config.HWID.Salt is still the default value - change it before going live.")
    end
    if Config.Webhook == "YOUR_WEBHOOK" and Config.EnableDiscordLogs then
        warn("Discord logs are enabled but no webhook is configured.")
    end

    -- Fail loudly if the vRP tables are named differently in this fork:
    -- without them every player looks like a brand new account.
    local probe = query(("SELECT 1 AS ok FROM %s LIMIT 1"):format(Config.VRP.IdentifiersTable), {})
    if probe == nil then
        err(("cannot read %s - set Config.VRP.* to match your vRP tables, "):format(Config.VRP.IdentifiersTable)
            .. "user_id will be NULL for everyone until then")
    end

    DB.refreshBanCache(true)

    -- Periodic maintenance: expire bans, prune the in-memory IP cache.
    while true do
        Wait(60 * 1000)

        execute("UPDATE hwid_bans SET active = 0 WHERE active = 1 AND expires_at IS NOT NULL AND expires_at <= NOW()")
        execute("UPDATE license_bans SET active = 0 WHERE active = 1 AND expires_at IS NOT NULL AND expires_at <= NOW()")
        DB.refreshBanCache(true)

        local now = os.time()
        for ip, entry in pairs(ipMemCache) do
            if (now - (entry.at or 0)) > Config.VPN.CacheMinutes * 60 then
                ipMemCache[ip] = nil
            end
        end
        for key, at in pairs(lastAlert) do
            if (now - at) > Config.Alerts.Cooldown * 2 then lastAlert[key] = nil end
        end
    end
end)
