-- Ten players and one spawn point per side: where does everybody land?
-- On the real spawnPointFor out of the shipped file.
--
--   lua5.4 tests/spawns.lua
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
local function near(a, b) return math.abs(a - b) < 0.001 end

Config = { Match = { spawnSpread = 1.8 } }

local spawnPointFor
do
  local a = SV:find('local function spawnPointFor(m, mp, index)', 1, true)
  local b = SV:find('function Match.get(matchId)', a, true)
  assert(a and b, 'could not slice spawnPointFor')
  spawnPointFor = assert(load(SV:sub(a, b - 1) ..
                 '\nreturn spawnPointFor', 'spawn', 't',
                 setmetatable({}, { __index = _G })))()
end

local function point(x, y, z, w) return { x = x, y = y, z = z, w = w } end

-- ==========================================================================
-- 1. enough spawn points: everybody gets their own, untouched
-- ==========================================================================
local m = { ffa = false, map = {
  center = { x = 0, y = 0, z = 0 },
  teamA  = { point(10, 0, 5, 0), point(12, 0, 5, 0), point(14, 0, 5, 0) },
  teamB  = { point(-10, 0, 5, 180) }
} }
local mp = { team = 1 }
check('the first player is on the first point',  spawnPointFor(m, mp, 1).x, 10)
check('the second on the second',                spawnPointFor(m, mp, 2).x, 12)
check('the third on the third',                  spawnPointFor(m, mp, 3).x, 14)
check('  and the heading comes from the point',  spawnPointFor(m, mp, 1).h, 0)
check('  and the height is left alone',          spawnPointFor(m, mp, 1).z, 5)

-- ==========================================================================
-- 2. one point, five players: a line, not a pile
-- ==========================================================================
-- Every map in the config ships one spawn per side, so a 5v5 used to put five
-- players inside each other. In a respawn mode that is a free kill every time.
m = { ffa = false, map = {
  center = { x = 0, y = 0, z = 0 },
  teamA  = { point(100, 200, 30, 0) },        -- heading 0 is north, so right is +X
  teamB  = { point(-100, 200, 30, 180) }
} }
local xs = {}
for i = 1, 5 do xs[i] = spawnPointFor(m, mp, i).x end

check('the first player is still exactly on the point', xs[1], 100)
check('the second is moved aside',      near(xs[2], 100 - 1.8), true)
check('the third the other way',        near(xs[3], 100 + 1.8), true)
check('the fourth further out',         near(xs[4], 100 - 3.6), true)
check('the fifth further the other way', near(xs[5], 100 + 3.6), true)

local same = 0
for i = 1, 5 do for j = i + 1, 5 do if near(xs[i], xs[j]) then same = same + 1 end end end
check('no two players share a spot', same, 0)

-- the spread is sideways, so the line still faces the same way into the arena
for i = 1, 5 do
  local s = spawnPointFor(m, mp, i)
  if not (near(s.y, 200) and near(s.h, 0) and near(s.z, 30)) then
    check(('player %d keeps the point facing and height'):format(i), false, true)
  end
end
check('the whole line faces the way the point faced', true, true)

-- and it spreads along the facing, whichever way that is
m.map.teamA = { point(0, 0, 30, 90) }         -- facing east, so right is -Y
check('a point facing east spreads north and south',
      near(spawnPointFor(m, mp, 2).y, -1.8) and near(spawnPointFor(m, mp, 2).x, 0), true)

-- ==========================================================================
-- 3. the edges
-- ==========================================================================
m = { ffa = false, map = { center = { x = 7, y = 8, z = 9 }, teamA = {}, teamB = {} } }
local s = spawnPointFor(m, mp, 1)
check('a map with no spawn points falls back to the centre',
      s.x == 7 and s.y == 8 and s.z == 9, true)

-- a free for all draws from both lists
m = { ffa = true, map = {
  center = { x = 0, y = 0, z = 0 },
  teamA  = { point(1, 0, 0, 0), point(2, 0, 0, 0) },
  teamB  = { point(3, 0, 0, 0), point(4, 0, 0, 0) }
} }
check('a free for all uses every point on the map', spawnPointFor(m, mp, 4).x, 4)
check('  and only spreads once they run out',
      near(spawnPointFor(m, mp, 5).x, 1 - 1.8), true)

-- turning the spread off puts them back on top of each other
Config.Match.spawnSpread = 0
m = { ffa = false, map = { center = { x = 0, y = 0, z = 0 },
      teamA = { point(50, 50, 10, 0) }, teamB = {} } }
check('spread 0 is the old behaviour', spawnPointFor(m, mp, 3).x, 50)
Config.Match.spawnSpread = 1.8

print()
print(fails == 0 and ('ALL PASS (%d checks)'):format(checks)
                 or ('%d FAILED'):format(fails))
os.exit(fails == 0 and 0 or 1)
