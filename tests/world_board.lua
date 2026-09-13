-- The leaderboard board standing in the world, and the top three standing next
-- to it. The thing that matters most here is what it costs when nobody is
-- looking at it, so that is what most of this measures — on the real wbTick out
-- of the shipped client.
--
--   lua5.4 tests/world_board.lua
local CL = io.open('M5_RankedPvP/Files/Client.lua'):read('a')
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
-- A vector3 with the distance operator the client uses, so #(a - b) is a real
-- distance and not a stub that always agrees.
local vmt = {}
vmt.__index = vmt
vmt.__sub = function(a, b)
  return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmt)
end
vmt.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vmt) end

-- every draw call the client can make, counted rather than performed
local DRAWS = 0
local function counted() DRAWS = DRAWS + 1 end
SetDrawOrigin, ClearDrawOrigin = counted, counted
DrawRect, SetTextFont, SetTextScale, SetTextColour = counted, counted, counted, counted
BeginTextCommandDisplayText, AddTextComponentSubstringPlayerName = counted, counted

-- is the board in front of the camera? the test drives this directly
local VISIBLE = true
function World3dToScreen2d() return VISIBLE end

-- GTA's text alignment flags survive the draw that set them, so a right
-- justified column leaks into the next left one unless every draw states its
-- own alignment. That is invisible in code review and obvious on screen, so
-- the flags are recorded per draw here.
local CENTRE, RIGHT = nil, nil
ALIGNMENTS = {}

function SetTextCentre(v) CENTRE = v; DRAWS = DRAWS + 1 end
function SetTextRightJustify(v) RIGHT = v; DRAWS = DRAWS + 1 end
function SetTextWrap() DRAWS = DRAWS + 1 end
function EndTextCommandDisplayText()
  DRAWS = DRAWS + 1
  ALIGNMENTS[#ALIGNMENTS + 1] = tostring(CENTRE) .. '/' .. tostring(RIGHT)
end

-- the podium
local SPAWNED, DELETED = 0, 0
local PEDS = {}
function DoesEntityExist(e) return PEDS[e] == true end
function GetEntityCoords() return vector3(0, 0, 0) end
function IsModelInCdimage() return true end
function IsModelAPed() return true end
function GetHashKey(s) return #s end
function RequestModel() end
function HasModelLoaded() return true end
function SetModelAsNoLongerNeeded() end
function CreatePed() SPAWNED = SPAWNED + 1; PEDS[SPAWNED] = true; return SPAWNED end
function DeleteEntity(e) DELETED = DELETED + 1; PEDS[e] = nil end
function playerPed() return 1 end
local noop = function() end
SetEntityInvincible, SetBlockingOfNonTemporaryEvents, SetPedCanRagdoll = noop, noop, noop
SetPedCanBeTargetted, SetPedCanBeDraggedOut, SetPedDiesWhenInjured = noop, noop, noop
SetPedFleeAttributes, SetPedCombatAttributes, SetEntityNoCollisionEntity = noop, noop, noop
FreezeEntityPosition, SetEntityCanBeDamaged, SetPedConfigFlag = noop, noop, noop
SetEntityAsMissionEntity = noop
RequestAnimDict, HasAnimDictLoaded, TaskPlayAnim, RemoveAnimDict = noop, function() return true end, noop, noop
Citizen = { Wait = noop }
RegisterNetEvent, AddEventHandler = noop, noop
function GetCurrentResourceName() return 'M5_RankedPvP' end

Config = { WorldBoard = {
  enabled = true,
  screens = { enabled = true, distance = 18.0, rows = 10, scale = 1.0, opacity = 190,
              spots = { { pos = vector3(0, 0, 0), title = 'TOP', enabled = true } } },
  podium  = { enabled = true, distance = 25.0, showNames = true,
              fallback = 'a_m_y_skater_01',
              spots = { { pos = vector3(2, 0, 0), h = 0.0 },
                        { pos = vector3(4, 0, 0), h = 0.0 },
                        { pos = vector3(6, 0, 0), h = 0.0 } } } } }

-- the slice hands back the tick and the table it keeps its rows and peds in
local wbTick, WB
do
  local a = CL:find('local WB = {', 1, true)
  local b = CL:find('Citizen.CreateThread(function()\n    if not wbOn() then return end', a, true)
  assert(a and b, 'could not slice the world board')
  wbTick, WB = assert(load(CL:sub(a, b - 1) .. '\nreturn wbTick, WB', 'wb'))()
end

local function rows(n)
  local out = {}
  for i = 1, n do
    out[i] = { position = i, name = 'P' .. i, rp = 1000 - i, rank = 'Gold',
               color = '#d2a23c', ped = 0 }
  end
  return out
end

local function tick(x, y, z, acc)
  DRAWS = 0
  return wbTick(vector3(x, y or 0, z or 0), acc or 0)
end

-- ==========================================================================
-- 1. what it costs when nobody is near it
-- ==========================================================================
-- This is the whole question. A board on the other side of the map must not
-- wake the thread up, and must not draw anything.
WB.rows = rows(10)

local sleep = tick(500)
check('a board far away sleeps for two seconds', sleep, 2000)
check('  and draws nothing at all',              DRAWS, 0)

sleep = tick(30)
check('walking towards it starts checking more often', sleep, 400)
check('  but still draws nothing',                     DRAWS, 0)

sleep = tick(5)
check('standing in front of it runs at frame rate', sleep, 0)
check('  and that is when it draws',                DRAWS > 0, true)

-- facing away is as good as being far away: the distance check alone would
-- have kept drawing a board behind the player's head
VISIBLE = false
sleep = tick(5)
check('turning away from it stops the drawing', DRAWS, 0)
check('  and lets the thread sleep again',      sleep, 400)
VISIBLE = true

-- with nothing to show there is nothing to do, however close you stand
WB.rows = {}
sleep = tick(0)
check('an empty board sleeps regardless of distance', sleep, 2000)
check('  and draws nothing',                          DRAWS, 0)
WB.rows = rows(10)

-- ==========================================================================
-- 2. the switches, which are genuinely independent of each other
-- ==========================================================================
-- Screens off with the podium on still puts the top three on their spots with
-- their names over them — that is the whole point of two switches rather than
-- one, so it is checked in both directions.
Config.WorldBoard.podium.enabled = false
Config.WorldBoard.screens.enabled = false
sleep = tick(0)
check('screens off: nothing is drawn standing on top of it', DRAWS, 0)
check('  and with the podium off too, nothing to wake for',  sleep, 2000)

Config.WorldBoard.screens.enabled = true
Config.WorldBoard.screens.spots[1].enabled = false
sleep = tick(0)
check('one screen can be switched off on its own', DRAWS, 0)
check('  and the thread goes back to sleep',       sleep, 2000)
Config.WorldBoard.screens.spots[1].enabled = true

Config.WorldBoard.enabled = false
sleep = tick(0)
check('the master switch stops everything', DRAWS, 0)
Config.WorldBoard.enabled = true

-- screens off but the podium on: the peds and their names still come
Config.WorldBoard.screens.enabled = false
Config.WorldBoard.podium.enabled = true
SPAWNED = 0
tick(5, 0, 0, 1000)
check('screens off does not switch the podium off', SPAWNED, 3)
DRAWS = 0
sleep = tick(5, 0, 0, 0)
check('  and their names are still drawn',          DRAWS > 0, true)
tick(500, 0, 0, 1000)
Config.WorldBoard.screens.enabled = true

-- and the other way round: podium off, screens on
Config.WorldBoard.podium.enabled = false
SPAWNED = 0
DRAWS = 0
sleep = tick(5, 0, 0, 1000)
check('podium off does not switch the screens off', DRAWS > 0, true)
check('  and no peds are spawned',                  SPAWNED, 0)
Config.WorldBoard.podium.enabled = true

-- ==========================================================================
-- 2b. every line states its own alignment
-- ==========================================================================
-- GTA keeps the alignment flags from one draw to the next. The RP column is
-- right justified, so without a reset the rank number on the next row lands on
-- the wrong side of the board — legible in a screenshot, invisible in review.
Config.WorldBoard.screens.enabled = true
Config.WorldBoard.podium.enabled = false
ALIGNMENTS = {}
tick(5, 0, 0, 0)
check('every line drawn states its alignment', #ALIGNMENTS > 6, true)

local unset = 0
for _, a in ipairs(ALIGNMENTS) do
  if a:find('nil') then unset = unset + 1 end
end
check('  none of them inherits it from the line before', unset, 0)

-- and the right justified column really is the only right justified one
local rights = 0
for _, a in ipairs(ALIGNMENTS) do
  if a:find('/true') then rights = rights + 1 end
end
check('  one right justified draw per row, no more',
      rights, math.min(Config.WorldBoard.screens.rows, #WB.rows))
Config.WorldBoard.podium.enabled = true

-- ==========================================================================
-- 3. the podium: three peds, spawned near and deleted far
-- ==========================================================================
SPAWNED, DELETED = 0, 0
tick(5, 0, 0, 1000)                       -- accumulator past the check interval
check('standing near spawns the top three', SPAWNED, 3)
check('  and they are remembered',          #WB.peds, 3)

local before = SPAWNED
tick(5, 0, 0, 1000)
check('standing there does not spawn them again', SPAWNED, before)

tick(500, 0, 0, 1000)
check('walking away deletes them', DELETED, 3)
check('  and forgets them',        #WB.peds, 0)

-- they come back
tick(5, 0, 0, 1000)
check('coming back spawns them again', SPAWNED, 6)

-- fewer players than podium spots: only as many peds as there are players
tick(500, 0, 0, 1000)
WB.rows = rows(2)
SPAWNED = 0
tick(5, 0, 0, 1000)
check('two players on the board means two peds, not three', SPAWNED, 2)
WB.rows = rows(10)

-- the podium can be switched off on its own, and switching it off mid-life
-- takes the peds with it
tick(500, 0, 0, 1000)
tick(5, 0, 0, 1000)
DELETED = 0
Config.WorldBoard.podium.enabled = false
tick(5, 0, 0, 1000)
check('switching the podium off removes the peds', DELETED > 0, true)
check('  and none are left',                       #WB.peds, 0)
Config.WorldBoard.podium.enabled = true

-- the accumulator means the podium is not re-checked every single frame
tick(500, 0, 0, 1000)
SPAWNED = 0
local _, acc = tick(5, 0, 0, 0)
check('the podium is not checked on every frame', SPAWNED, 0)
check('  it waits for its own interval',          acc > 0, true)

-- ==========================================================================
-- 4. the server builds it once for everybody
-- ==========================================================================
-- A board read by twenty players standing in front of it is still one query.
check('the server keeps one snapshot',
      SV:find('WorldBoard = { rows = {}, builtAt = 0', 1, true) ~= nil, true)
check('  refreshed on a timer, not per player',
      SV:find('acc.board >= every', 1, true) ~= nil, true)
check('  and not at all with nobody online',
      SV:find('if next(Players) ~= nil then', 1, true) ~= nil, true)
check('  then pushed to everyone at once',
      SV:find("TriggerClientEvent('m5rp:cl:worldBoard', -1", 1, true) ~= nil, true)
check('a player joining is sent the snapshot, not a fresh query',
      SV:find('WorldBoard.push(src)', 1, true) ~= nil, true)

-- the ped model is stored, so the podium wears the player's own skin
check('the podium skin is read from the player row',
      SV:find('p.ped_model', 1, true) ~= nil, true)
check('  which is added by a migration, not by hand',
      SV:find("ADD COLUMN `ped_model`", 1, true) ~= nil, true)
check('  and only written when it actually changed',
      SV:find('if pd and pd.pedModel ~= hash then', 1, true) ~= nil, true)

-- ==========================================================================
-- 5. nothing is left behind when the resource stops
-- ==========================================================================
check('the peds are deleted on resource stop',
      CL:find('wbDespawn()', 1, true) ~= nil, true)
-- there is more than one stop handler in the file, so this asks whether any of
-- them cleans up rather than assuming which
local cleansUp = false
for body in CL:gmatch("AddEventHandler%('onResourceStop'.-\nend%)") do
  if body:find('wbDespawn', 1, true) then cleansUp = true end
end
check('  by a stop handler', cleansUp, true)

print()
print(fails == 0 and ('ALL PASS (%d checks)'):format(checks)
                 or ('%d FAILED'):format(fails))
os.exit(fails == 0 and 0 or 1)
