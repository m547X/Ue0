-- The client can only see Config_Client.lua. Config_Server.lua is loaded under
-- server_scripts and never reaches the game, so a client reading Config.Headshot
-- is not a missing setting — it is a crash on every headshot, which is how this
-- test came to exist.
--
--   lua5.4 tests/client_config.lua
local CL   = io.open('M5_RankedPvP/Files/Client.lua'):read('a')
local CCFG = io.open('M5_RankedPvP/الاعدادات/Config_Client.lua'):read('a')
local MAN  = io.open('M5_RankedPvP/fxmanifest.lua'):read('a')

local fails, checks = 0, 0
local function check(name, got, want)
  checks = checks + 1
  if got ~= want then
    fails = fails + 1
    print(('FAIL %-56s got=%s want=%s'):format(name, tostring(got), tostring(want)))
  else
    print(('ok   %-56s %s'):format(name, tostring(got)))
  end
end

-- ==========================================================================
-- 1. the server config is server-only, and stays that way
-- ==========================================================================
-- Everything private lives in it: webhooks, permissions, the RP formulas and
-- the anti-cheat thresholds. It is listed under server_scripts and nowhere else.
local client = MAN:match('client_scripts%s*{(.-)}') or ''
local shared = MAN:match('shared_scripts%s*{(.-)}') or ''
local server = MAN:match('server_scripts%s*{(.-)}') or ''

check('Config_Server is in server_scripts', server:find('Config_Server', 1, true) ~= nil, true)
check('  and not in client_scripts',        client:find('Config_Server', 1, true) ~= nil, false)
check('  and not in shared_scripts',        shared:find('Config_Server', 1, true) ~= nil, false)
check('Config_Client is where the client can read it',
      (client .. shared):find('Config_Client', 1, true) ~= nil, true)

-- ==========================================================================
-- 2. so every Config table the client touches has to be in the client config
-- ==========================================================================
local declared = {}
for key in CCFG:gmatch('\nConfig%.([A-Za-z_]+)') do declared[key] = true end
-- Config.Debug is set in the shared header rather than as its own block
declared.Debug = declared.Debug or CCFG:find('Config.Debug', 1, true) ~= nil

local seen, missing = {}, {}
for key in CL:gmatch('Config%.([A-Z][A-Za-z_]*)') do
  if not seen[key] then
    seen[key] = true
    if not declared[key] then missing[#missing + 1] = key end
  end
end

local n = 0
for _ in pairs(seen) do n = n + 1 end
check(('the client reads %d Config tables'):format(n), n > 0, true)
check('every one of them is declared in Config_Client.lua',
      #missing == 0 and 'yes' or table.concat(missing, ', '), 'yes')

-- ==========================================================================
-- 3. the headshot rule comes from the server, per match
-- ==========================================================================
-- The client is not the authority on it and cannot see the thresholds, so it
-- is told: one flag, computed server side, sent with the match settings.
check('the client no longer reads Config.Headshot',
      CL:find('Config.Headshot', 1, true) ~= nil, false)
check('  it reads the flag the match sent instead',
      CL:find('State.settings.headshotOneShot == true', 1, true) ~= nil, true)

local SV = io.open('M5_RankedPvP/Files/Server.lua'):read('a')
check('the server folds the whole rule into one answer',
      SV:find('function Match.headshotRule(m)', 1, true) ~= nil, true)
check('  and sends that, not the raw config',
      SV:find('headshotOneShot = Match.headshotRule(m)', 1, true) ~= nil, true)
check('  along with the bones it judges by',
      SV:find('headBones       = Config.Headshot', 1, true) ~= nil, true)

-- the rule itself, run
do
  local a = SV:find('function Match.headshotRule(m)', 1, true)
  local b = SV:find('function Match.loadoutFor(m, userId)', a, true)
  local env = setmetatable({ Match = {} }, { __index = _G })
  assert(load(SV:sub(a, b - 1), 'hs', 't', env))()
  local rule = env.Match.headshotRule

  Config = { Headshot = { enabled = true, oneShotKill = true,
                          enabledInRanked = true, enabledInCustom = true } }
  env.Config = Config
  check('a ranked match with the rule on reports head hits',
        rule({ ranked = true, settings = {} }), true)

  Config.Headshot.enabled = false
  check('the rule switched off in the config stops it',
        rule({ ranked = true, settings = {} }), false)
  Config.Headshot.enabled = true

  Config.Headshot.enabledInRanked = false
  check('off for ranked stops a ranked match',
        rule({ ranked = true, settings = {} }), false)
  check('  but not a custom one',
        rule({ customId = 'c1', settings = {} }), true)
  Config.Headshot.enabledInRanked = true

  check('a match that voted it off is off',
        rule({ ranked = true, settings = { headshotOneShot = false } }), false)
  check('  and one that voted it on is on',
        rule({ ranked = true, settings = { headshotOneShot = true } }), true)

  Config.Headshot = nil
  check('no Headshot config at all is answered, not crashed',
        rule({ ranked = true, settings = {} }), false)
end

print()
print(fails == 0 and ('ALL PASS (%d checks)'):format(checks)
                 or ('%d FAILED'):format(fails))
os.exit(fails == 0 and 0 or 1)
