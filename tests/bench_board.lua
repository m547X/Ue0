-- What the world board costs, per frame, on the machine of somebody standing
-- in front of it.
--
--   lua5.4 tests/bench_board.lua
--
-- The board is a browser painted into a texture. That browser is the floor and
-- no amount of Lua makes it cheaper — what Lua decides is how often it is
-- asked to exist, and how much work is done around it every frame while
-- somebody stands there reading it. This runs the real wbTick out of the
-- shipped client against counted stubs and prints both.
--
-- It is a benchmark, not a pass/fail test, except for the budgets at the end.
local CL = io.open('M5_RankedPvP/Files/Client.lua'):read('a')

local fails, checks = 0, 0
local function check(name, got, want)
  checks = checks + 1
  if got ~= want then
    fails = fails + 1
    print(('FAIL %-58s got=%s want=%s'):format(name, tostring(got), tostring(want)))
  else
    print(('ok   %-58s %s'):format(name, tostring(got)))
  end
end

-- ------------------------------------------------------------------ engine
NATIVES, ALLOCS = 0, 0

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

local function native(ret)
  return function() NATIVES = NATIVES + 1 return ret end
end

VISIBLE = true
function World3dToScreen2d() NATIVES = NATIVES + 1 return VISIBLE end
function GetFinalRenderedCamCoord()
  NATIVES = NATIVES + 1
  return vector3(0.0, -8.0, 30.0)
end
POLYS = 0
function DrawSpritePoly() POLYS = POLYS + 1 NATIVES = NATIVES + 1 end
SetDrawOrigin, ClearDrawOrigin = native(), native()
DrawRect = native()
SetTextFont, SetTextScale, SetTextColour = native(), native(), native()
SetTextCentre, SetTextRightJustify, SetTextWrap = native(), native(), native()
BeginTextCommandDisplayText = native()
AddTextComponentSubstringPlayerName = native()
EndTextCommandDisplayText = native()

DoesEntityExist = native(true)
PED_AT = { x = 3.0, y = 0.0, z = 28.0 }
GetEntityCoords = function()
  NATIVES = NATIVES + 1
  return vector3(PED_AT.x, PED_AT.y, PED_AT.z)
end
IsModelInCdimage, IsModelAPed = native(true), native(true)
GetHashKey = function(s) NATIVES = NATIVES + 1 return #s end
RequestModel, HasModelLoaded = native(), native(true)
SetModelAsNoLongerNeeded = native()
CreatePed = (function() local n = 0 return function() n = n + 1 NATIVES = NATIVES + 1 return n end end)()
DeleteEntity = native()
function playerPed() NATIVES = NATIVES + 1 return 1 end
local noop = function() end
SetEntityInvincible, SetBlockingOfNonTemporaryEvents, SetPedCanRagdoll = noop, noop, noop
SetPedCanBeTargetted, SetPedCanBeDraggedOut, SetPedDiesWhenInjured = noop, noop, noop
SetPedFleeAttributes, SetPedCombatAttributes, SetEntityNoCollisionEntity = noop, noop, noop
FreezeEntityPosition, SetEntityCanBeDamaged, SetPedConfigFlag = noop, noop, noop
SetEntityAsMissionEntity = noop
RequestAnimDict, HasAnimDictLoaded, TaskPlayAnim, RemoveAnimDict =
  noop, function() return true end, noop, noop
Citizen = { Wait = noop }
RegisterNetEvent, AddEventHandler = noop, noop
function GetCurrentResourceName() return 'M5_RankedPvP' end

-- the browser, counted rather than opened
BROWSERS, PAINTS = 0, 0
function CreateDui() BROWSERS = BROWSERS + 1 NATIVES = NATIVES + 1 return 100 end
GetDuiHandle = native('handle')
CreateRuntimeTxd = native(1)
CreateRuntimeTextureFromDuiHandle = native(1)
IsDuiAvailable = native(true)
function SendDuiMessage() PAINTS = PAINTS + 1 NATIVES = NATIVES + 1 end
SetDuiUrl = native()
DestroyDui = native()
json = { encode = function(t) return 'json' end }

local CLOCK = 0
function ms() return CLOCK end

Config = { UI = { colors = {} }, Brand = {}, WorldBoard = {
  enabled = true,
  screens = { enabled = true, distance = 35.0, rows = 10, opacity = 255,
              textureWidth = 1280, textureHeight = 720, keepAlive = 60,
              spots = { { pos = vector3(0, 0, 30), title = 'TOP', enabled = true,
                          h = 0.0, pitch = 0.0, width = 7.4 } } },
  podium  = { enabled = true, distance = 25.0, showNames = true,
              fallback = 'a_m_y_skater_01',
              spots = { { pos = vector3(2, 0, 28), h = 0.0 },
                        { pos = vector3(4, 0, 28), h = 0.0 },
                        { pos = vector3(6, 0, 28), h = 0.0 } } } } }

local wbTick, WB
do
  local a = CL:find('local WB = {', 1, true)
  local b = CL:find('Citizen.CreateThread(function()\n    if not wbOn() then return end', a, true)
  assert(a and b, 'could not slice the world board')
  wbTick, WB = assert(load(CL:sub(a, b - 1) .. '\nreturn wbTick, WB', 'wb'))()
end

WB.ready, WB.off = true, false
WB.rows = {}
for i = 1, 10 do
  WB.rows[i] = { position = i, name = 'P' .. i, rp = 1000 - i, rank = 'Gold',
                 color = '#d2a23c', ped = 0, plate = '#' .. i .. ' P' .. i,
                 under = 'GOLD', r = 200, g = 200, b = 200,
                 kills = i, deaths = i, wins = i, losses = i, kd = 1 }
end

local acc = 0
local function frame(x, y, z)
  CLOCK = CLOCK + 16
  local me = vector3(x, y, z)        -- the thread's own read, not the board's
  NATIVES, ALLOCS, POLYS = 0, 0, 0
  local sleep
  sleep, acc = wbTick(me, acc)
  return NATIVES, ALLOCS, sleep, POLYS
end

-- ==========================================================================
-- what it costs where
-- ==========================================================================
print('--- one frame of the world board ---')

-- far away: the thread is asleep and nothing is touched
local n, a, sleep = frame(600, 600, 30)
local farN, farA, farSleep = frame(600, 600, 30)
print(('across the map      %d natives, %d allocations, sleeps %dms')
  :format(farN, farA, farSleep))

-- standing in front of it, reading it
frame(0, -8, 30)                       -- the frame that builds the browser
frame(0, -8, 30)
local nearN, nearA, _, nearPoly = frame(0, -8, 30)
print(('standing at it      %d natives, %d allocations  (%d/s)')
  :format(nearN, nearA, nearN * 60))

-- the peds have spawned by now; their nameplates are the other half
acc = 900
frame(0, -8, 30)
local plateN = select(1, frame(0, -8, 30))
print(('  with three plates  %d natives  (%d/s)'):format(plateN, plateN * 60))

-- looking away from it while standing right there
VISIBLE = false
local awayN, awayA, awaySleep, awayPoly = frame(0, -8, 30)
VISIBLE = true
print(('looking away        %d natives, sleeps %dms'):format(awayN, awaySleep))
print()

-- ==========================================================================
-- the budget
-- ==========================================================================
check('across the map it costs nothing at all', farN, 0)
check('  and sleeps two seconds between looks', farSleep, 2000)

-- One browser, however many frames are drawn from it. This is the whole point
-- of the design: the texture is free to look at and only costs when it changes.
check('one browser, not one per frame', BROWSERS, 1)
check('  and it is painted only when the rows change', PAINTS, 1)

-- Four DrawSpritePoly, the camera once, and the on-screen test once. Every
-- other frame reads the corners out of the cache rather than working out eight
-- sines and cosines again.
check('a frame in front of it is under ten natives', nearN <= 10, true)
check('  and allocates only the camera vector',      nearA, 1)
check('  drawing the quad both ways round',         nearPoly, 4)

-- The plates are the expensive half and they are the half that is optional:
-- Config.WorldBoard.podium.showNames = false takes all of it away.
check('the three nameplates are the expensive part', plateN > nearN, true)
check('  and even with them it stays under eighty',  plateN <= 80, true)

-- Looking away costs five questions — the centre of the board and its four
-- corners — and draws nothing. That is the price of a board that does not
-- disappear when you walk up to it and its middle leaves the screen.
-- Looking away draws nothing. It still asks five questions about the board —
-- its centre and its four corners — and one per ped, which is what a board
-- that does not vanish when you walk up to it costs.
check('looking away draws nothing at all', awayPoly, 0)
check('  and costs under ten natives',      awayN <= 10, true)

print()
print(fails > 0 and ('%d FAILED of %d'):format(fails, checks)
                or ('ALL PASS (%d checks)'):format(checks))
os.exit(fails > 0 and 1 or 0)
