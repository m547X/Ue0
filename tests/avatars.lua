-- Where a player's picture comes from, and when.
--
--   lua5.4 tests/avatars.lua
--
-- Asking Discord for a picture takes a round trip, and the menu opens before
-- it comes back. So there are three ways to end up with a blank card and none
-- of them throws:
--
--   the placeholder is empty, so there is nothing to show while waiting;
--   the answer arrives and nobody is told, so the card keeps the placeholder
--   for as long as the player stays connected;
--   the bot token is empty, so the answer never comes at all and the server
--   says nothing about it.
--
-- The real avatarFor and its fetch are sliced out of Server.lua and run
-- against a Discord that can be made to answer, to fail, or to be switched off.

local SV = io.open('M5_RankedPvP/Files/Server.lua'):read('a')

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
-- a server, a Discord, and somebody to tell
-- ==========================================================================
local CLOCK = 0
local function advance(n) CLOCK = CLOCK + n end

local ENV = setmetatable({}, { __index = _G })
ENV.now = function() return CLOCK end
ENV.ms  = function() return CLOCK * 1000 end

local ERRORS = {}
ENV.err = function(fmt, ...) ERRORS[#ERRORS + 1] = select('#', ...) > 0 and fmt:format(...) or fmt end
ENV.dbg = function() end
ENV.log = function() end

-- the http call, held so the test decides when it comes back
local PENDING
ENV.PerformHttpRequest = function(url, cb, _, _, headers)
  PENDING = { url = url, cb = cb, auth = headers and headers.Authorization }
end
ENV.Citizen = { CreateThread = function(fn) fn() end }
ENV.json = { decode = function(body)
  if body == 'bad' then error('nope') end
  return load('return ' .. body)()
end }

local PUSHED = {}
ENV.Player = { pushCosmetics = function(userId) PUSHED[#PUSHED + 1] = userId end }

ENV.Players = {}
ENV.Store = { cache = {}, customImage = function() return nil end }
ENV.AvatarCache = {}

ENV.Config = { Avatars = {
  enabled = true,
  default = 'https://cdn.discordapp.com/embed/avatars/0.png',
  source  = 'discord',
  template = 'https://my-cdn.example.com/avatars/%s.png',
  discord = { botToken = 'a-token', cacheTime = 21600, size = 128 }
} }

local M
do
  local a = SV:find('local function defaultAvatar()', 1, true)
  local b = SV:find('local function customPortraitFor(userId)', a, true)
  local c = SV:find('local function avatarFor(userId, plain)', 1, true)
  local d = SV:find('local AvatarCache = {}', 1, true)
  assert(a and b and c, 'could not slice the avatar code')

  -- everything from defaultAvatar to the end of avatarFor
  local tail = SV:find('\nlocal ', c + 10)
  local chunk = SV:sub(a, b - 1) .. '\n'
    .. 'local function customPortraitFor(userId)\n'
    .. '  local d = Store and Store.cache and Store.cache[userId]\n'
    .. '  if not d or d.portrait ~= "custom" then return nil end\n'
    .. '  return Store.customImage(userId, "portrait")\n'
    .. 'end\n'
    .. SV:sub(c, tail - 1)
    .. '\nreturn { get = avatarFor, fetch = fetchDiscordAvatar }'
  M = assert(load(chunk, 'avatar', 't', ENV))()
end

local function reset(over)
  ENV.AvatarCache = {}
  ENV.Players = { [7] = { discord = 'discord:214000000000000000' } }
  PENDING, PUSHED, ERRORS = nil, {}, {}
  ENV.Config.Avatars.source = 'discord'
  ENV.Config.Avatars.enabled = true
  ENV.Config.Avatars.discord.botToken = 'a-token'
  for k, v in pairs(over or {}) do ENV.Config.Avatars[k] = v end
end

-- ==========================================================================
-- 1. there is always something to show
-- ==========================================================================
reset()
local first = M.get(7)
check('asking for a picture never comes back empty', first ~= nil and first ~= '', true)
check('  it is a real Discord placeholder, not a broken link',
      first:find('cdn.discordapp.com', 1, true) ~= nil, true)
check('  and Discord has been asked for the real one', PENDING ~= nil, true)
check('  with the bot token on it', PENDING.auth, 'Bot a-token')
check('  for the right account',
      PENDING.url, 'https://discord.com/api/v10/users/214000000000000000')

-- asking again while it is in flight must not ask twice
PENDING.asked = true
M.get(7); M.get(7); M.get(7)
check('asking again while it is in flight does not ask Discord again',
      PENDING.asked, true)

-- ==========================================================================
-- 2. when it lands, somebody is told
-- ==========================================================================
-- This is the one that reads as "the picture never loads". The answer arrives
-- and the cache is right, but the card was drawn from the placeholder and
-- nothing ever redraws it.
PENDING.cb(200, '{ avatar = "abc123", discriminator = "0" }')
local got = M.get(7)
check('the real picture replaces the placeholder',
      got, 'https://cdn.discordapp.com/avatars/214000000000000000/abc123.png?size=128')
check('  and the player is told, so their card redraws', PUSHED[1], 7)
check('  exactly once',                                  #PUSHED, 1)

-- an animated avatar is a gif, not a png
reset()
M.get(7)
PENDING.cb(200, '{ avatar = "a_9f9f", discriminator = "0" }')
check('an animated picture is asked for as a gif',
      M.get(7):find('%.gif') ~= nil, true)

-- ==========================================================================
-- 3. when it does not land
-- ==========================================================================
reset()
M.get(7)
PENDING.cb(404, nil)
check('a lookup that fails falls back rather than blanking',
      M.get(7), ENV.Config.Avatars.default)
check('  and still tells the player, so the card stops waiting', PUSHED[1], 7)

reset()
M.get(7)
PENDING.cb(401, nil)
check('a rejected token is said out loud',
      (ERRORS[1] or ''):find('token', 1, true) ~= nil, true)

reset()
M.get(7)
PENDING.cb(200, 'bad')
check('a reply that will not parse does not throw', M.get(7), ENV.Config.Avatars.default)

-- ==========================================================================
-- 4. no token at all — the quiet one
-- ==========================================================================
-- botToken is empty in the shipped config, so this is what most servers hit
-- first. It used to spawn a thread that returned immediately and said nothing,
-- and every player kept the plain placeholder for ever with no clue why.
reset()
ENV.Config.Avatars.discord.botToken = ''
local held = M.get(7)
check('with no token there is still a picture', held ~= nil and held ~= '', true)
check('  Discord is not asked at all',          PENDING, nil)
check('  and the server says why, once',
      (ERRORS[1] or ''):find('botToken', 1, true) ~= nil, true)

M.get(7); M.get(7)
check('  without repeating itself on every player', #ERRORS, 1)

-- ==========================================================================
-- 5. the other sources
-- ==========================================================================
reset({ source = 'template' })
check('a template builds the link from the id, with no round trip',
      M.get(7), 'https://my-cdn.example.com/avatars/214000000000000000.png')
check('  and asks Discord nothing', PENDING, nil)

reset({ source = 'none' })
check('source none is the default picture', M.get(7), ENV.Config.Avatars.default)

reset({ enabled = false })
check('switched off, there is no picture at all', M.get(7), nil)

-- a player with no Discord linked
reset()
ENV.Players[7] = { discord = '' }
check('a player with no Discord gets the default', M.get(7), ENV.Config.Avatars.default)

-- ==========================================================================
-- 6. the cache
-- ==========================================================================
reset()
M.get(7)
PENDING.cb(200, '{ avatar = "abc123", discriminator = "0" }')
local settled = M.get(7)
PENDING = nil
advance(3600)
check('a settled picture is not looked up again for hours', M.get(7), settled)
check('  and Discord is left alone',                        PENDING, nil)

advance(21600)
M.get(7)
check('once the cache ages out it is refreshed', PENDING ~= nil, true)

-- a granted custom portrait wins over anything Discord says
reset()
ENV.Store.cache[7] = { portrait = 'custom' }
ENV.Store.customImage = function() return 'https://my.site/me.png' end
check('a picture the player set themselves wins', M.get(7), 'https://my.site/me.png')
check('  unless the plain one is asked for', M.get(7, true) ~= 'https://my.site/me.png', true)
ENV.Store.customImage = function() return nil end

print(fails > 0 and ('\n%d FAILED of %d'):format(fails, checks)
                or ('\nALL PASS (%d checks)'):format(checks))
os.exit(fails > 0 and 1 or 0)
