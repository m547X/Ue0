-- What the per-frame work in a live round actually costs.
--
--   lua5.4 tests/bench_hotpath.lua
--
-- The match thread runs at Wait(0) while a round is live, so everything it
-- calls runs about sixty times a second on every player's machine. This runs
-- the real functions out of the shipped client against counted stubs, so the
-- numbers below are native calls and table allocations per frame — the two
-- things that actually cost anything in a FiveM client script.
--
-- It is a benchmark, not a pass/fail test, except for the budget at the end:
-- if a change pushes the per-frame native count back up, that fails.
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

-- ------------------------------------------------------------------ engine
NATIVES = 0
ALLOCS  = 0

local vmt = {}
vmt.__index = vmt
vmt.__sub = function(a, b)
  ALLOCS = ALLOCS + 1
  return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmt)
end
vmt.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function vector3(x, y, z)
  ALLOCS = ALLOCS + 1
  return setmetatable({ x = x, y = y, z = z }, vmt)
end

--- Every native the hot path can reach, counted. A native call from a script
--- crosses into the game and back, which is the expensive part.
local function native(ret)
  return function() NATIVES = NATIVES + 1 return ret end
end

PLAYERS = { 0, 1, 2, 3, 4, 5, 6, 7 }
function GetActivePlayers()
  NATIVES = NATIVES + 1
  ALLOCS = ALLOCS + 1               -- the native hands back a fresh table
  local out = {}
  for i = 1, #PLAYERS do out[i] = PLAYERS[i] end
  return out
end

GetPlayerServerId   = function(p) NATIVES = NATIVES + 1 return p + 10 end
GetPlayerPed        = function(p) NATIVES = NATIVES + 1 return p + 100 end
DoesEntityExist     = native(true)
GetEntityCoords     = function() NATIVES = NATIVES + 1 return vector3(5, 5, 0) end
GetGameplayCamRot   = function() NATIVES = NATIVES + 1 return vector3(0, 0, 90) end
IsPedShooting       = native(false)
IsControlPressed    = native(false)
ON_SCREEN = true
World3dToScreen2d   = function() NATIVES = NATIVES + 1 return ON_SCREEN end
SetDrawOrigin, ClearDrawOrigin = native(), native()
SetTextFont, SetTextScale, SetTextColour = native(), native(), native()
SetTextCentre, SetTextOutline = native(), native()
BeginTextCommandDisplayText = native()
AddTextComponentSubstringPlayerName = native()
EndTextCommandDisplayText = native()
math_abs = math.abs

CLOCK = 1000
function ms() return CLOCK end
function playerPed() NATIVES = NATIVES + 1 return 100 end
function TriggerServerEvent() end

Config = {
  Display = { teammateNameplates = true, nameplateDistance = 60.0,
              enemyNameplates = false, disableWeaponWheel = true }
}

State = {
  team = 1, ffa = false,
  teamOfServerId = { [10] = 1, [11] = 1, [12] = 2, [13] = 1,
                     [14] = 2, [15] = 1, [16] = 2, [17] = 2 },
  nameOfServerId = { [10] = 'A', [11] = 'B', [12] = 'C', [13] = 'D',
                     [14] = 'E', [15] = 'F', [16] = 'G', [17] = 'H' },
  lastPos = vector3(0, 0, 0), lastCamHeading = 0, lastActivityPush = 0
}

local drawTeammateTags, pushActivity
do
  local a = CL:find('local ACTIVITY_MOVE_SQ', 1, true)
  local b = CL:find('startMatchThread = function()', a, true)
  assert(a and b, 'could not slice the per-frame functions')
  local src = CL:sub(a, b - 1)
  pushActivity, drawTeammateTags = assert(load(
    src .. '\nreturn pushActivity, drawTeammateTags', 'hot'))()
end

--- One frame of the two functions that walk the roster. Sixteen milliseconds
--- pass, because a frame is where the whole cost lives and several of these
--- functions only do their work once a clock has moved on.
local function frame(shooting)
  CLOCK = CLOCK + 16
  NATIVES, ALLOCS = 0, 0
  local ped = 100
  local pos = vector3(5, 5, 0)
  NATIVES, ALLOCS = 0, 0            -- discount the setup
  drawTeammateTags(ped, pos)
  pushActivity(ped, pos, shooting)
  return NATIVES, ALLOCS
end

--- Sixteen frames is a quarter of a second, which is the window the activity
--- probe works on, so this is the honest per-frame average rather than the one
--- frame in sixteen that pays for it.
local function average(frames)
  local nat, alloc = 0, 0
  for _ = 1, frames do
    local n, a = frame(false)
    nat, alloc = nat + n, alloc + a
  end
  return nat / frames, alloc / frames
end

print('--- one frame, eight players on the server, four of them teammates ---')
frame(false)                              -- warm the roster cache
local n, a = frame(false)
print(('all four in view    %d natives, %d allocations  (%d/s, %d/s)')
  :format(n, a, n * 60, a * 60))

ON_SCREEN = false
local nb, ab = frame(false)
print(('all four behind you %d natives, %d allocations  (%d/s, %d/s)')
  :format(nb, ab, nb * 60, ab * 60))
ON_SCREEN = true
print()

-- ==========================================================================
-- the budget
-- ==========================================================================
-- These are the numbers after the roster list was cached and the distance
-- checks stopped building vectors. They are not arbitrary: every one of them
-- is work that used to happen sixty times a second and now does not, and a
-- change that puts it back should say so out loud.
check('the roster is not re-fetched every frame',
      CL:find('TAG_ROSTER_EVERY', 1, true) ~= nil, true)

-- Three teammates to draw means three GetEntityCoords, and that native hands
-- back a vector — so three is the floor, not zero. What went is the roster
-- table, the eight server-id lookups and the three vector subtractions the
-- distance check used to build, and now the camera vector too: the activity
-- probe is asleep on this frame, so nothing reads the camera.
check('a frame allocates only what the natives hand back', a, 3)

-- A plate that would not land on screen is not drawn, and that is ten native
-- calls each — so looking away from your team costs a fraction of looking at
-- it. Both numbers are the budget; either one growing is a regression.
check('teammates out of view cost less than half as much', nb * 2 < n, true)
check('  and the in-view frame stays within budget',        n <= 50, true)
check('  and the out-of-view frame within its own',         nb <= 20, true)

-- A cache that refills every frame is not a cache. The roster is rebuilt only
-- when the clock has moved on, so the frames in between must not touch
-- GetActivePlayers at all.
local before = NATIVES
local seen = 0
local realGAP = GetActivePlayers
GetActivePlayers = function() seen = seen + 1 return realGAP() end
for _ = 1, 10 do frame() end
GetActivePlayers = realGAP
check('ten frames in a row rebuild the roster no more than once', seen <= 1, true)

-- ==========================================================================
-- the activity probe
-- ==========================================================================
-- Whether the player is still there is worth knowing every few hundred
-- milliseconds, not sixty times a second — the answer is only ever sent every
-- three seconds anyway. A player standing still is the expensive case, because
-- that is the one where the camera and the movement keys have to be asked, so
-- that is the one the probe is measured on.
local camReads = 0
local realCam = GetGameplayCamRot
GetGameplayCamRot = function(...) camReads = camReads + 1 return realCam(...) end

State.lastPos = vector3(5, 5, 0)          -- standing exactly where we are
State.lastCamHeading = 90                 -- and looking the same way
for _ = 1, 60 do frame(false) end         -- one second of standing still
GetGameplayCamRot = realCam
check('standing still, one second asks the camera about four times',
      camReads >= 3 and camReads <= 5, true)

-- A player who has moved is active on the position alone, so the camera and
-- the three control reads never happen at all.
State.lastPos = vector3(0, 0, 0)
CLOCK = CLOCK + 300                       -- let the probe come round again
local moving = select(1, frame(false))
CLOCK = CLOCK + 300
local still  = select(1, frame(false))    -- lastPos is now where we are
check('a player who moved skips the camera read', moving < still, true)

-- With nobody else on the server the roster is empty and the activity probe is
-- asleep on most frames, so the frame is free.
PLAYERS = { 0 }
State.teamOfServerId = { [10] = 1 }
State.team = 2                            -- so nobody, including me, is a teammate
frame(false)                              -- the team changed, so let the roster settle
local n3, a3 = average(16)
print()
print(('alone on the server %.2f natives, %.2f allocations per frame')
  :format(n3, a3))
check('alone on the server the frame is nearly free', n3 <= 1.0, true)
check('  and allocates almost nothing',               a3 <= 0.2, true)

print()
print(fails == 0 and ('ALL PASS (%d checks)'):format(checks)
                 or ('%d FAILED'):format(fails))
os.exit(fails == 0 and 0 or 1)
