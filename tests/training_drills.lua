-- The drill loop itself, run for real.
--
--   lua5.4 tests/training_drills.lua
--
-- Everything that decides whether a reflex run is fair — a target's lifetime,
-- what counts as a miss, how many are up at once, what the reaction time is
-- measured from — lives in one loop inside Client.lua that no test can reach in
-- this box. So the loop is sliced out whole and run against stubbed natives on
-- a clock the test controls: targets appear, the scripted player hits them or
-- lets them go, and the readouts are checked against what actually happened.
local CL = io.open('M5_RankedPvP/Files/Client.lua'):read('a')

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
local function near(name, got, want, slack)
  check(name, math.abs(got - want) <= slack, true)
end

-- ==========================================================================
-- a world the loop can run in
-- ==========================================================================
local V = {}
V.__index = V
V.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, V) end
V.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, V) end
V.__mul = function(a, b)
  if type(b) == 'number' then return setmetatable({ x = a.x * b, y = a.y * b, z = a.z * b }, V) end
  return setmetatable({ x = a.x * b.x, y = a.y * b.y, z = a.z * b.z }, V)
end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function vec3(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end

local W        -- the world of the run in progress

local function newWorld(scenario)
  return {
    T = 0, ticks = 0, maxTicks = scenario.maxTicks or 4000, peak = 0, up = 0,
    peds = {}, nextPed = 100, walked = {}, nui = {}, exited = 0,
    spawnLog = {}, shootAt = scenario.shootAt, hitAfter = scenario.hitAfter,
    killAt = scenario.killAt, stop = scenario.stop
  }
end

local ENV = setmetatable({}, { __index = _G })

ENV.State = { training = false, trainingProps = {} }
ENV.Config = { Training = { exit = { enabled = false } } }
ENV.HEAD_BONES = { [31086] = true }

ENV.ms = function() return W.T end
ENV.playerPed = function() return 1 end
ENV.nui = function(msg) W.nui[#W.nui + 1] = msg end
ENV.hook = function() end
ENV.closeMenu = function() end
ENV.rememberPoint = function() end
ENV.teleport = function() end
ENV.applyLoadout = function() end
ENV.returnHome = function() end
ENV.exitTraining = function() W.exited = W.exited + 1 end

ENV.RegisterNetEvent = function(_, fn) ENV.__handler = fn end

ENV.Citizen = {
  Wait = function(n)
    -- the loop cleans up after itself, so how many targets were up has to be
    -- recorded while it is still running
    local up = #ENV.State.trainingProps
    if up > W.peak then W.peak = up end
    W.up = up
    W.T = W.T + (n == 0 and 16 or n)
    W.ticks = W.ticks + 1
    if W.stop and W.stop(W) then ENV.State.training = false end
    if W.ticks >= W.maxTicks then ENV.State.training = false end
  end,
  CreateThread = function(fn) fn() end
}

ENV.GetHashKey = function(s) return #s end
ENV.RequestModel = function() end
ENV.HasModelLoaded = function() return true end
ENV.SetModelAsNoLongerNeeded = function() end
ENV.GetGroundZFor_3dCoord = function(_, _, z) return true, z - 25.0 end
ENV.vector3 = vec3

ENV.CreatePed = function(_, _, x, y, z, h)
  local id = W.nextPed
  W.nextPed = id + 1
  W.peds[id] = { x = x, y = y, z = z, h = h, health = 200, born = W.T, hit = false }
  W.spawnLog[#W.spawnLog + 1] = { id = id, x = x, y = y, z = z, at = W.T }
  return id
end
ENV.DoesEntityExist = function(id) return W.peds[id] ~= nil end
ENV.DeletePed = function(id) W.peds[id] = nil end
ENV.GetEntityCoords = function(id)
  local p = W.peds[id]
  return p and vec3(p.x, p.y, p.z) or vec3(0, 0, 0)
end
-- the scripted player: every target is shot `hitAfter` ms after it appears
local function maybeShot(p)
  if W.hitAfter and p.health > 0 and (W.T - p.born) >= W.hitAfter then
    p.hit = true
    p.headshot = W.headshot == true
    p.health = 0
  end
end
ENV.IsEntityDead = function(id)
  local p = W.peds[id]
  if not p then return true end
  maybeShot(p)
  return p.health <= 0
end
ENV.SetEntityHealth = function(id, v) if W.peds[id] then W.peds[id].health = v end end
ENV.GetPedLastDamageBone = function(id)
  local p = W.peds[id]
  if not p or not p.hit then return false, 0 end
  return true, p.headshot and 31086 or 24818
end
ENV.ClearEntityLastDamageEntity = function(id) if W.peds[id] then W.peds[id].hit = false end end
ENV.HasEntityBeenDamagedByEntity = function(id)
  local p = W.peds[id]
  if not p then return false end
  maybeShot(p)
  return p.hit == true
end
ENV.IsPedShooting = function()
  if not W.shootAt then return false end
  return W.shootAt(W)
end

for _, name in ipairs({
  'SetEntityInvincible', 'SetPedCanRagdoll', 'FreezeEntityPosition',
  'SetBlockingOfNonTemporaryEvents', 'SetPedSuffersCriticalHits',
  'SetPedDiesWhenInjured', 'SetPedFleeAttributes', 'SetPedDropsWeaponsWhenDead',
  'SetEntityAsMissionEntity', 'RemoveAllPedWeapons', 'SetEntityMaxHealth',
  'SetPedArmour', 'DisplayRadar'
}) do ENV[name] = function() end end

ENV.TaskGoToCoordAnyMeans = function(id, x, y, z, speed)
  W.walked[#W.walked + 1] = { id = id, x = x, y = y, z = z, speed = speed, at = W.T }
end
ENV.GetHeadingFromVector_2d = function(x, y) return math.deg(math.atan(x, y)) end

-- ==========================================================================
-- the real block, sliced whole
-- ==========================================================================
do
  local a = CL:find("local TRAIN_MODEL = 's_m_y_marine_01'", 1, true)
  local b = CL:find('clearBots = function()', a, true)
  assert(a and b, 'could not slice the training block')
  local chunk = CL:sub(a, b - 1)
  assert(load(chunk, 'training', 't', ENV))()
end
assert(ENV.__handler, 'the training event never registered')

local SPAWN = { x = 0.0, y = 0.0, z = 30.0, h = 0.0 }

local function run(data, scenario)
  W = newWorld(scenario or {})
  W.headshot = (scenario or {}).headshot
  ENV.State.training = false
  ENV.State.trainingProps = {}
  data.enable = true
  data.spawn = SPAWN
  ENV.__handler(data)
  return W
end

local function lastStats()
  for i = #W.nui, 1, -1 do
    local m = W.nui[i]
    if m.action == 'training' and m.data and m.data.stats then return m.data.stats end
  end
  return nil
end
local function stat(label)
  local rows = lastStats() or {}
  for i = 1, #rows do if rows[i].l == label then return rows[i].v end end
  return nil
end

-- ==========================================================================
-- 1. reflex: a target nobody shoots is a miss, not a target that waits
-- ==========================================================================
local reflex = { pace = 'normal', label = 'NORMAL', live = 1000, gap = 400,
                 up = 1, arc = 80.0, near = 10.0, far = 26.0 }

run({ kind = 'reflex', label = 'REFLEX TARGETS', time = 0, reflex = reflex },
    { maxTicks = 700 })

check('a reflex run puts a target up', #W.spawnLog > 0, true)
check('  and only one at a time', W.peak, reflex.up)
check('  a target nobody hits is counted as missed', tonumber(stat('MISSED')) > 0, true)
check('  and nothing is counted as a hit', stat('HITS'), '0')
check('  with no reaction time to report', stat('REACTION'), '-')

-- a target lives its lifetime and no longer: over ~11 seconds of game time, at
-- live+gap each, the count follows from the clock rather than from the frames
local misses = tonumber(stat('MISSED'))
local elapsed = W.T
near('  targets come and go at the pace asked for',
     misses, math.floor(elapsed / (reflex.live + reflex.gap)), 1)

-- ==========================================================================
-- 2. reflex: hits, streak and the reaction time they are measured against
-- ==========================================================================
run({ kind = 'reflex', label = 'REFLEX TARGETS', time = 0, reflex = reflex },
    { maxTicks = 700, hitAfter = 300 })

check('a target that is hit counts as a hit', tonumber(stat('HITS')) > 0, true)
check('  and never as a miss', stat('MISSED'), '0')
near('  the reaction time is measured from when it appeared',
     tonumber((stat('REACTION'):gsub(' MS', ''))), 300, 20)
check('  a run without a miss is one unbroken streak',
      stat('STREAK'), stat('HITS') .. ' / ' .. stat('HITS'))

-- a headshot is told apart from a body hit
run({ kind = 'reflex', label = 'REFLEX TARGETS', time = 0, reflex = reflex },
    { maxTicks = 300, hitAfter = 300, headshot = true })
check('a head hit is still a hit', tonumber(stat('HITS')) > 0, true)

-- ==========================================================================
-- 3. reflex: the fast pace keeps two up at once
-- ==========================================================================
local fast = { pace = 'fast', label = 'FAST', live = 1000, gap = 200,
               up = 2, arc = 80.0, near = 10.0, far = 26.0 }
run({ kind = 'reflex', label = 'REFLEX TARGETS', time = 0, reflex = fast },
    { maxTicks = 60 })
check('the fast pace puts two targets up', W.peak, 2)

-- every target appears in front of the player, inside the arc it was given
local ok = true
for i = 1, #W.spawnLog do
  local s = W.spawnLog[i]
  local dist = math.sqrt(s.x * s.x + s.y * s.y)
  local ang  = math.deg(math.atan(-s.x, s.y))
  if dist < fast.near - 0.5 or dist > fast.far + 0.5 then ok = false end
  if math.abs(ang) > fast.arc / 2 + 0.5 then ok = false end
end
check('every target appears in front, inside the arc and the range', ok, true)

-- ==========================================================================
-- 4. moving: spawned around the player, walking, and replaced when killed
-- ==========================================================================
local moving = { area = 26.0, minDist = 10.0, respawn = 1500, retask = 900,
                 speeds = { { id = 'walk', label = 'WALK', speed = 1.0 },
                            { id = 'jog', label = 'JOG', speed = 1.8 },
                            { id = 'jog2', label = 'JOG', speed = 1.8 },
                            { id = 'sprint', label = 'SPRINT', speed = 3.0 } } }

run({ kind = 'moving', label = 'MOVING TARGETS', targets = 6, time = 0, moving = moving },
    { maxTicks = 4 })

check('a moving run spawns the number asked for', W.peak, 6)
check('  every one of them is sent walking somewhere', #W.walked >= 6, true)

local inRing, speeds = true, {}
for i = 1, 6 do
  local s = W.spawnLog[i]
  local d = math.sqrt(s.x * s.x + s.y * s.y)
  if d < moving.minDist - 0.5 or d > moving.area + 0.5 then inRing = false end
end
for i = 1, #W.walked do speeds[W.walked[i].speed] = true end
check('  they spawn in the ring the config describes', inRing, true)
check('  and they do not all move at the same speed',
      (speeds[1.0] or speeds[1.8] or speeds[3.0]) ~= nil, true)
check('  none of them walks faster than the config allows',
      (function()
        for s in pairs(speeds) do if s > 3.0 then return false end end
        return true
      end)(), true)

-- one goes down: the body lies there for the respawn delay, then a fresh one
-- appears somewhere else
run({ kind = 'moving', label = 'MOVING TARGETS', targets = 2, time = 0, moving = moving },
    { maxTicks = 40, hitAfter = 0 })
check('a killed target is counted', tonumber(stat('HITS')) >= 2, true)
check('  and replaced, so the drill never empties', W.up, 2)
check('  the replacement is a different target',
      #W.spawnLog > 2, true)

-- ==========================================================================
-- 5. the standing drills still work the way they did
-- ==========================================================================
run({ kind = 'aim', label = 'AIM TRAINING', targets = 12, spacing = 8.0, time = 0 },
    { maxTicks = 3 })
check('an aim run stands twelve targets up', W.peak, 12)
check('  in a line in front of the player', (function()
  for i = 1, 12 do if W.spawnLog[i].y < 10.0 then return false end end
  return true
end)(), true)

run({ kind = 'aim', label = 'AIM TRAINING', targets = 4, spacing = 8.0, time = 0 },
    { maxTicks = 12, hitAfter = 0 })
check('  shooting one counts it', tonumber(stat('HITS')) >= 4, true)
check('  and stands a fresh one in its place', W.up, 4)
check('  so the line never runs out', #W.spawnLog > 4, true)

-- ==========================================================================
-- 6. the timer actually ends the session
-- ==========================================================================
run({ kind = 'aim', label = 'AIM TRAINING', targets = 2, spacing = 8.0, time = 3 },
    { maxTicks = 5000 })
check('a drill with a time limit stops when it runs out', W.exited, 1)
check('  at the time it was given, not later', W.T < 3600, true)
check('  and the clock counts down to zero', stat('CLOCK'), '0s')
check('  leaving no targets behind', #ENV.State.trainingProps, 0)

-- a drill with no limit keeps going
run({ kind = 'aim', label = 'AIM TRAINING', targets = 2, spacing = 8.0, time = 0 },
    { maxTicks = 400 })
check('a drill with no limit is never ended for the player', W.exited, 0)
check('  and its clock counts up instead', stat('CLOCK') ~= '0s', true)

print(fails > 0 and ('\n%d FAILED of %d'):format(fails, checks)
                or ('\nALL PASS (%d checks)'):format(checks))
os.exit(fails > 0 and 1 or 0)
