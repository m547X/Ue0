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

-- Where the eye is, so the client can drop the face pointing away from it.
-- It is the *rendered* camera that is asked, not the gameplay one: the board
-- editor can push a scripted camera, and the face that is drawn has to follow
-- whatever is actually on screen.
CAM = { x = 0.0, y = -10.0, z = 30.0 }
local CAM_CALLS = 0
function GetFinalRenderedCamCoord() CAM_CALLS = CAM_CALLS + 1; return CAM end
function GetGameplayCamCoord() return CAM end
function camCalls() local n = CAM_CALLS; CAM_CALLS = 0; return n end

-- GTA's text alignment flags survive the draw that set them, so a right
-- justified column leaks into the next left one unless every draw states its
-- own alignment. That is invisible in code review and obvious on screen, so
-- the flags are recorded per draw here.
local CENTRE, RIGHT = nil, nil
ALIGNMENTS = {}
-- captured now, so swapping the global tostring later to count the code's own
-- string building does not count this stub's
local rawTostring = tostring

function SetTextCentre(v) CENTRE = v; DRAWS = DRAWS + 1 end
function SetTextRightJustify(v) RIGHT = v; DRAWS = DRAWS + 1 end
function SetTextWrap() DRAWS = DRAWS + 1 end
function EndTextCommandDisplayText()
  DRAWS = DRAWS + 1
  ALIGNMENTS[#ALIGNMENTS + 1] = rawTostring(CENTRE) .. '/' .. rawTostring(RIGHT)
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
-- the net handlers are kept, so the ones the server actually calls can be
-- called here too rather than only read
HANDLERS = {}
RegisterNetEvent = function(name, fn) if fn then HANDLERS[name] = fn end end
AddEventHandler = noop
function GetCurrentResourceName() return 'M5_RankedPvP' end

-- the board is a web page painted onto a texture; the page itself is checked
-- in the browser by tests/ui_world_board.js, so here it is only counted
DUIS, PUSHED, DESTROYED = 0, 0, 0
-- CEF opens the page a moment after it is asked to; the client has to wait for
-- that before it sends anything or draws anything
PAGE_OPEN, BLANKED = true, 0
function CreateDui() DUIS = DUIS + 1; return 100 + DUIS end
function GetDuiHandle() return 'handle' end
function CreateRuntimeTxd() return 1 end
function CreateRuntimeTextureFromDuiHandle() return 1 end
function IsDuiAvailable() return PAGE_OPEN end
function SendDuiMessage(_, payload) PUSHED = PUSHED + 1; LAST_PUSH = payload end
function SetDuiUrl(_, url) if url == 'about:blank' then BLANKED = BLANKED + 1 end end
function DestroyDui() DESTROYED = DESTROYED + 1 end
function DrawSpritePoly() DRAWS = DRAWS + 1 end
json = { encode = function(t) return t end }
local CLOCK = 0
function ms() return CLOCK end
function advance(n) CLOCK = CLOCK + n end

Config = { UI = { colors = {} }, Brand = {}, WorldBoard = {
  enabled = true,
  screens = { enabled = true, distance = 18.0, rows = 10, opacity = 255,
              textureWidth = 1280, textureHeight = 720, keepAlive = 60,
              spots = { { pos = vector3(0, 0, 0), title = 'TOP', enabled = true,
                          h = 0.0, pitch = 0.0, width = 6.0 } } },
  podium  = { enabled = true, distance = 25.0, showNames = true,
              fallback = 'a_m_y_skater_01',
              spots = { { pos = vector3(2, 0, 0), h = 0.0 },
                        { pos = vector3(4, 0, 0), h = 0.0 },
                        { pos = vector3(6, 0, 0), h = 0.0 } } } } }

-- the slice hands back the tick and the table it keeps its rows and peds in
local wbTick, WB, DUI, wbLayout
do
  local a = CL:find('local WB = {', 1, true)
  local b = CL:find('Citizen.CreateThread(function()\n    if not wbOn() then return end', a, true)
  assert(a and b, 'could not slice the world board')
  wbTick, WB, DUI, wbLayout =
    assert(load(CL:sub(a, b - 1) .. '\nreturn wbTick, WB, DUI, wbLayout', 'wb'))()
end

local function rows(n)
  local out = {}
  for i = 1, n do
    out[i] = { position = i, name = 'P' .. i, rp = 1000 - i, rank = 'Gold',
               color = '#d2a23c', ped = 0,
               kills = 10 * i, deaths = i, wins = i, losses = 1, kd = 1.5 }
  end
  return out
end

local function tick(x, y, z, acc)
  DRAWS = 0
  return wbTick(vector3(x, y or 0, z or 0), acc or 0)
end

-- ==========================================================================
-- 0. a board with nobody on it is still a board
-- ==========================================================================
-- A fresh server has no qualified players, and this used to return before
-- drawing anything — so the spot was simply empty and read as broken rather
-- than as an empty table.
WB.ready, WB.rows = false, {}
local sleep = tick(0)
check('before the server has said anything, nothing is drawn', DRAWS, 0)
check('  and the thread sleeps',                               sleep, 2000)

WB.ready, WB.rows = true, {}
sleep = tick(0)
check('a board with no players still draws its frame', DRAWS > 0, true)
check('  and runs at frame rate while you look at it', sleep, 0)

-- ==========================================================================
-- 1. what it costs when nobody is near it
-- ==========================================================================
-- This is the whole question. A board on the other side of the map must not
-- wake the thread up, and must not draw anything.
WB.rows = rows(10)

sleep = tick(500)
check('a board far away sleeps for two seconds', sleep, 2000)
check('  and draws nothing at all',              DRAWS, 0)

-- the band where it starts looking more often reaches half again as far as
-- the board is visible from, so approaching one is picked up before it should
-- already be on screen
sleep = tick(25)
check('walking towards it starts checking more often', sleep, 400)
check('  but still draws nothing',                     DRAWS, 0)

sleep = tick(40)
check('further out than that it goes back to sleep',   sleep, 2000)

sleep = tick(5)
check('standing in front of it runs at frame rate', sleep, 0)
check('  and that is when it draws',                DRAWS > 0, true)

-- what a player standing in front of it pays, every frame, for as long as
-- they stand there: two triangles and one question about where the eye is
camCalls()
DRAWS = 0
tick(5)
check('  which costs two triangles, not four',  DRAWS, 2)
check('  and asks for the camera once a frame', camCalls(), 1)

-- facing away is as good as being far away: the distance check alone would
-- have kept drawing a board behind the player's head
VISIBLE = false
sleep = tick(5)
check('turning away from it stops the drawing', DRAWS, 0)
check('  and lets the thread sleep again',      sleep, 400)
VISIBLE = true

-- and an empty one still costs nothing from a distance
WB.rows = {}
sleep = tick(500)
check('an empty board far away still sleeps', sleep, 2000)
check('  and draws nothing',                  DRAWS, 0)
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
-- 2b. the page behind the board
-- ==========================================================================
-- The texture is a running browser page. It is worth what it costs only while
-- somebody can see it, and repainting it is paid by every machine looking at
-- the board — so it is built on demand, pushed only when the numbers actually
-- change, and handed back once nobody has been near for a while.
Config.WorldBoard.screens.enabled = true
Config.WorldBoard.podium.enabled = false

DUI.made, DUI.ready, DUI.lastKey = false, false, ''
DUIS, PUSHED, DESTROYED = 0, 0, 0

tick(500)
check('a board nobody is near builds no page', DUIS, 0)

tick(5)
check('walking up to it builds one', DUIS, 1)
check('  and paints the rows onto it once', PUSHED, 1)

tick(5)
tick(5)
check('standing there does not build another', DUIS, 1)
check('  and does not repaint it either',      PUSHED, 1)

-- the same rows arriving again are the same picture
WBPUSH = PUSHED
WB.rows = rows(10)
tick(5)
check('rows that say the same thing are not repainted', PUSHED, WBPUSH)

-- CEF does not open the page the instant it is asked to. A message sent before
-- it is there is dropped on the floor, and a texture drawn before it is there
-- is whatever happened to be in that memory — so neither happens until the
-- page says it is open.
DUI.made, DUI.ready, DUI.live, DUI.avail = false, false, false, false
DUI.dirty, DUI.msg, DUI.lastKey = false, nil, ''
DUIS, PUSHED, DESTROYED, BLANKED = 0, 0, 0, 0
PAGE_OPEN = false

tick(5)
check('a page that has not opened yet is not painted', PUSHED, 0)
check('  and nothing is drawn onto it',                DRAWS, 0)

PAGE_OPEN = true
tick(5)
check('once it opens the rows go on',       PUSHED, 1)
check('  and that is when the board draws', DRAWS > 0, true)

-- walking away blanks the page rather than tearing the texture out from under
-- the handle it was built from: destroying the browser would leave the runtime
-- texture pointing at nothing, and the name it was made under cannot be reused
tick(500)
advance(61000)
tick(500)
check('walking away for a minute blanks the page', BLANKED, 1)
check('  but the browser itself is kept',           DESTROYED, 0)
check('  and nothing is drawn while it is parked',  DRAWS, 0)

tick(5)
check('coming back does not build a second one', DUIS, 1)
check('  and the rows are put back on it',       PUSHED, 2)
check('  and it draws again',                    DRAWS > 0, true)

-- ==========================================================================
-- ==========================================================================
-- 2c. what a frame in front of the board costs
-- ==========================================================================
-- The board redraws every frame while somebody stands at it, and the numbers on
-- it change once every few minutes. Turning each cell into a string on every
-- frame was eighty string allocations a frame; they are built once when the
-- rows arrive instead.
Config.WorldBoard.screens.enabled = true
Config.WorldBoard.podium.enabled = false
WB.rows = rows(10)
for i = 1, #WB.rows do            -- the client formats these when they arrive
  local row = WB.rows[i]
  row.cells = {}
  for n = 1, 8 do row.cells[n] = tostring(n) end
  row.r, row.g, row.b = 210, 160, 60
end

STRINGS = 0
local realTostring = tostring
tostring = function(v) STRINGS = STRINGS + 1 return realTostring(v) end
tick(5, 0, 0, 0)
tostring = realTostring
check('a frame at the board builds no strings', STRINGS, 0)
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

-- ==========================================================================
-- 6. the board an admin placed is the board everybody sees
-- ==========================================================================
-- The editor saves the layout to the server, which keeps it and sends it to
-- every player with the rows. For a while nobody read it off the payload, so
-- a placed board existed only for the admin who placed it, only until they
-- reconnected — everyone else kept the example coordinates out of the config
-- and stood in an empty street wondering where the board was.
local onBoard = HANDLERS['m5rp:cl:worldBoard']
check('the client listens for the board', type(onBoard), 'function')

local SAVED = {
  screens = { { pos = { x = 300.0, y = 300.0, z = 30.0 }, title = 'PLACED',
                enabled = true, h = 90.0, pitch = 0.0, width = 6.0,
                rows = 10, opacity = 255, distance = 18.0 } },
  podium = { { pos = { x = 302.0, y = 300.0, z = 29.0 }, h = 90.0 } },
  screensEnabled = true, podiumEnabled = true, podiumDistance = 25.0
}

onBoard({ rows = rows(10), season = 'S1', layout = SAVED })
check('a saved layout is taken off the payload', wbLayout(), SAVED)
check('  and it is the placed board that is listed',
      wbLayout().screens[1].title, 'PLACED')

-- and it is not only stored, it is what gets drawn
DRAWS = 0
wbTick(vector3(0, 0, 0), 0)
check('nothing is drawn where the config example was', DRAWS, 0)
DRAWS = 0
local placedSleep = select(1, wbTick(vector3(300, 300, 30), 0))
check('the board is drawn where it was placed', DRAWS > 0, true)
check('  and the thread wakes up for it',        placedSleep, 0)

-- Resetting it in the editor sends a payload with no layout on it, and that
-- has to put the config back rather than leave the placed one standing.
onBoard({ rows = rows(10), season = 'S1' })
check('a reset puts the config back', wbLayout().screens[1].title, 'TOP')
DRAWS = 0
wbTick(vector3(0, 0, 0), 0)
check('  and the board is back where the config puts it', DRAWS > 0, true)

-- ==========================================================================
-- 7. asking for the rows is not a one-off
-- ==========================================================================
-- The client asks the server for the board a few seconds after it starts. If
-- the player's profile has not finished loading by then the server drops the
-- question, and asking once meant the board never appeared for that player at
-- all — for the rest of the session, with nothing said about it.
local askBlock = CL:match('while true do%s*\n%s*local sleep = WB_FAR.-Citizen%.Wait%(sleep%)')
check('the ask loop is in the file', askBlock ~= nil, true)
check('  it keeps asking until the server answers',
      askBlock:find('if not WB.ready then', 1, true) ~= nil, true)
check('  on a timer rather than every frame',
      askBlock:find('WB_ASK_EVERY', 1, true) ~= nil, true)
check('  and says so out loud if the answer never comes',
      askBlock:find('WB.warned', 1, true) ~= nil, true)

-- The server hands it over at boot as well, so a client whose question was
-- dropped gets the board anyway without having to ask again.
check('the server pushes the board when a player loads in',
      SV:find('TriggerClientEvent(\'m5rp:cl:boot\', src, Server_BootPayload(pd))\n\n        if WorldBoard.on() then', 1, true) ~= nil, true)

print()
print(fails == 0 and ('ALL PASS (%d checks)'):format(checks)
                 or ('%d FAILED'):format(fails))
os.exit(fails == 0 and 0 or 1)
