-- What the vote actually does to the match: which map, which weapon, and
-- whether a kill takes a headshot. On the real resolveMapVote and the real
-- option picker out of the shipped file.
--
--   lua5.4 tests/vote_resolve.lua
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

-- ------------------------------------------------------------------ engine
function inList(list, value)
  for i = 1, #list do if list[i] == value then return true end end
  return false
end
function shuffle(t)
  for i = #t, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end
  return t
end
function err() end

MapById = {
  dust  = { id = 'dust',  name = 'DUST' },
  neon1 = { id = 'neon1', name = 'NEON 1' },
  lego  = { id = 'lego',  name = 'LEGO' }
}
PresetById = {
  sniper = { id = 'sniper', label = 'Sniper',  weapon = 'WEAPON_SNIPERRIFLE' },
  smg    = { id = 'smg',    label = 'SMG',     weapon = 'WEAPON_SMG' },
  knife  = { id = 'knife',  label = 'Knife',   weapon = 'WEAPON_KNIFE' },
  mg     = { id = 'mg',     label = 'Combat MG', weapon = 'WEAPON_COMBATMG' }
}
Security = { weaponAllowed = function() return true end }
function mapsForMode() return { MapById.dust, MapById.neon1, MapById.lego } end

Config = {
  WeaponPresets = { PresetById.sniper, PresetById.smg, PresetById.knife, PresetById.mg },
  MapVote = {
    enabled = true, options = 3, duration = 20,
    weapons  = { enabled = true, options = 3, always = {}, exclude = {} },
    headshot = { enabled = true, default = false }
  }
}

local BROADCAST, SETUP = nil, 0
Match = {
  broadcast  = function(_, _, data) BROADCAST = data end,
  beginSetup = function() SETUP = SETUP + 1 end
}

-- the real winner picker, the real defaults, the real resolve, and the real
-- weapon option picker
do
  local a = SV:find('local function weaponVoteOptions()', 1, true)
  local b = SV:find('function Match.startMapVote(m)', a, true)
  local c = SV:find('function Match.applyVoteDefaults(m)', 1, true)
  local dd = SV:find('local function voteGroups(m)', c, true)
  local e = SV:find('local function tallyOf(votes)', 1, true)
  local f = SV:find('function Match.vote(m, userId, kind, choice)', e, true)
  local g = SV:find('function Match.resolveMapVote(m)', 1, true)
  local h = SV:find('function Match.beginSetup(m)', g, true)
  assert(a and b and c and dd and e and f and g and h, 'could not slice the vote code')

  local src = SV:sub(a, b - 1) .. '\n' .. SV:sub(e, f - 1) .. '\n'
           .. SV:sub(c, dd - 1) .. '\n' .. SV:sub(g, h - 1)
           .. '\nreturn weaponVoteOptions'
  weaponVoteOptions = assert(load(src, 'resolve', 't',
                      setmetatable({ Match = Match }, { __index = _G })))()
end

local function match(opts)
  opts = opts or {}
  BROADCAST, SETUP = nil, 0
  return {
    id = 'm1', ranked = true, settings = {},
    mapOptions    = opts.noMap and {} or { MapById.dust, MapById.neon1, MapById.lego },
    weaponOptions = opts.noWeapon and {} or { 'sniper', 'smg', 'knife' },
    ruleVote      = opts.noRule ~= true,
    mapVotes = opts.mapVotes or {}, weaponVotes = opts.weaponVotes or {},
    ruleVotes = opts.ruleVotes or {},
    map = opts.map
  }
end

-- ==========================================================================
-- 1. the winners become the match
-- ==========================================================================
local m = match({
  mapVotes    = { [1] = 'neon1', [2] = 'neon1', [3] = 'dust' },
  weaponVotes = { [1] = 'smg',   [2] = 'smg' },
  ruleVotes   = { [1] = 'head',  [2] = 'head', [3] = 'full' }
})
Match.resolveMapVote(m)
check('the map with the most votes is the map',   m.map.id, 'neon1')
check('the weapon with the most votes is loaded', m.settings.weapons[1], 'smg')
check('  as the only weapon, not added to a list', #m.settings.weapons, 1)
check('headshot only wins and is applied',        m.settings.headshotOnly, true)
check('the match is then set up',                 SETUP, 1)

-- and the result that goes to the players names all three
check('the result names the map',    BROADCAST.result, 'neon1')
check('  the weapon, readably',      BROADCAST.weaponName, 'SMG')
check('  and the rule',              BROADCAST.rule, 'head')
check('  and closes the screen',     BROADCAST.close, true)

-- full body wins the other way round
m = match({ ruleVotes = { [1] = 'full', [2] = 'full', [3] = 'head' } })
Match.resolveMapVote(m)
check('full body wins and headshot only is off', m.settings.headshotOnly, false)

-- ==========================================================================
-- 2. nobody voted
-- ==========================================================================
-- The timer ran out with an empty tally. Every group still has to produce an
-- answer, because the match starts either way.
m = match()
Match.resolveMapVote(m)
check('a map is still chosen',     m.map ~= nil, true)
check('  from what was offered',   MapById[m.map.id] ~= nil, true)
check('a weapon is still chosen',  m.settings.weapons ~= nil and #m.settings.weapons, 1)
check('  from what was offered',   inList({ 'sniper', 'smg', 'knife' }, m.settings.weapons[1]), true)
check('the rule falls to the configured default', m.settings.headshotOnly, false)

Config.MapVote.headshot.default = true
m = match()
Match.resolveMapVote(m)
check('a different default is honoured', m.settings.headshotOnly, true)
Config.MapVote.headshot.default = false

-- ==========================================================================
-- 3. groups that were never asked about are left alone
-- ==========================================================================
m = match({ noWeapon = true, noRule = true, map = nil })
Match.resolveMapVote(m)
check('no weapon vote leaves the loadout alone', m.settings.weapons, nil)
check('  and the rule takes the default',        m.settings.headshotOnly, false)
check('  the map is still decided',              m.map ~= nil, true)

-- a mode with one map: the map was picked before the vote and must survive it
m = match({ noMap = true, map = MapById.lego })
Match.resolveMapVote(m)
check('a map picked before the vote is not overwritten', m.map.id, 'lego')

-- ==========================================================================
-- 4. which weapons get offered
-- ==========================================================================
local opts = weaponVoteOptions()
check('the vote offers as many weapons as asked for', #opts, 3)
local uniq = {}
for _, id in ipairs(opts) do uniq[id] = (uniq[id] or 0) + 1 end
local dupes = 0
for _, n in pairs(uniq) do if n > 1 then dupes = dupes + 1 end end
check('  with no weapon offered twice', dupes, 0)

Config.MapVote.weapons.options = 0
check('0 means offer everything', #weaponVoteOptions(), 4)
Config.MapVote.weapons.options = 3

Config.MapVote.weapons.exclude = { 'knife', 'mg' }
opts = weaponVoteOptions()
check('an excluded weapon is never offered',
      inList(opts, 'knife') or inList(opts, 'mg'), false)
check('  and the rest still are', #opts, 2)
Config.MapVote.weapons.exclude = {}

-- `always` pins a weapon into every vote, however the shuffle falls
Config.MapVote.weapons.always = { 'sniper' }
Config.MapVote.weapons.options = 2
local everyTime = true
for _ = 1, 50 do if not inList(weaponVoteOptions(), 'sniper') then everyTime = false end end
check('a weapon in `always` is in every vote', everyTime, true)
check('  and it counts towards the total',     #weaponVoteOptions(), 2)
Config.MapVote.weapons.always = {}
Config.MapVote.weapons.options = 3

-- one weapon is not a vote
Config.MapVote.weapons.exclude = { 'smg', 'knife', 'mg' }
check('a single weapon is not put to a vote', weaponVoteOptions(), nil)
Config.MapVote.weapons.exclude = {}

Config.MapVote.weapons.enabled = false
check('switched off, no weapons are offered', weaponVoteOptions(), nil)
Config.MapVote.weapons.enabled = true

-- a weapon the security layer refuses is never offered, whatever the config says
Security.weaponAllowed = function(w) return w ~= 'WEAPON_SNIPERRIFLE' end
Config.MapVote.weapons.options = 0
check('a weapon security refuses is not offered',
      inList(weaponVoteOptions(), 'sniper'), false)
Security.weaponAllowed = function() return true end
Config.MapVote.weapons.options = 3

print()
print(fails == 0 and ('ALL PASS (%d checks)'):format(checks)
                 or ('%d FAILED'):format(fails))
os.exit(fails == 0 and 0 or 1)
