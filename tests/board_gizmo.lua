-- Dragging the board by its handles.
--
--   lua5.4 tests/board_gizmo.lua
--
-- The gizmo is split across two sides and neither can see the other: the
-- client knows where the handles are in the world, the page knows where the
-- cursor is. So the page sends a cursor position and the client does the rest
-- — which means every bug here is a silent one. Grab the red arrow and the
-- board slides north. Grab it on the far side of the screen and it slides the
-- wrong way. Nothing throws either time.
--
-- So the real handle maths, hit testing and drag conversion are sliced out of
-- Client.lua and driven against a camera that can be pointed by hand.

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
  check(name, math.abs(got - want) <= (slack or 0.02), true)
end

-- ==========================================================================
-- a camera that projects, so "where is that handle on screen" has an answer
-- ==========================================================================
-- A plain orthographic-ish camera looking down -Y from above: world X goes
-- right across the screen, world Z goes up it, and world Y is into it. That is
-- enough to tell a correct projection from a mirrored one.
local CAM = { x = 0.0, y = -20.0, z = 30.0 }
local SCALE = 0.05                      -- screen units per metre

function GetGameplayCamCoord() return CAM end
function GetAspectRatio() return 16 / 9 end

function GetScreenCoordFromWorldCoord(x, y, z)
  -- behind the camera never projects, which the picker has to survive
  if y <= CAM.y then return false, 0.0, 0.0 end
  return true, 0.5 + (x - CAM.x) * SCALE, 0.5 - (z - CAM.z) * SCALE
end

local DRAWN = { lines = 0, markers = 0, text = {} }
function DrawLine() DRAWN.lines = DRAWN.lines + 1 end
function DrawMarker() DRAWN.markers = DRAWN.markers + 1 end
function drawMarkerText(_, _, _, t) DRAWN.text[#DRAWN.text + 1] = t end
function playerPed() return 1 end
function GetEntityCoords() return { x = 0.0, y = 0.0, z = 30.0 } end
function GetEntityHeading() return 0.0 end
function StartShapeTestRay() return 1 end
function GetShapeTestResult() return 2, 0, { x = 0.0, y = 0.0, z = 0.0 } end
function GetGroundZFor_3dCoord() return true, 29.0 end
function GetGameplayCamRot() return { x = 0.0, y = 0.0, z = 0.0 } end

-- ==========================================================================
-- the slice
-- ==========================================================================
local ENV = setmetatable({}, { __index = _G })
ENV.Config = { WorldBoard = { screens = { textureWidth = 1280, textureHeight = 720 } } }
-- a vector3 whose subtraction hands back another vector3, so #(a - b) is a
-- real distance rather than the zero a plain table returns
local vmt = {}
vmt.__sub = function(a, b)
  return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmt)
end
vmt.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
ENV.vec3 = function(p)
  return setmetatable({ x = p.x + 0.0, y = p.y + 0.0, z = p.z + 0.0 }, vmt)
end
ENV.wbwRepaint = function() end
ENV.nui = function() end

-- the board's own size and corner maths, which the size handles sit on
do
  local a = CL:find('local function screenSize(spot)', 1, true)
  local b = CL:find('local function drawScreen(spot', a, true)
  assert(a and b, 'could not slice the board geometry')
  local fns = assert(load(CL:sub(a, b - 1)
    .. '\nreturn screenSize, screenCorners', 'geo', 't', ENV))()
  ENV.screenSize, ENV.screenCorners = fns, select(2, load(CL:sub(a, b - 1)
    .. '\nreturn screenSize, screenCorners', 'geo', 't', ENV)())
end
ENV.DUI = { w = 1280, h = 720 }

-- the editor's selection, stubbed to hand back one item under test
local ITEM, KIND = nil, 's'
ENV.wbwSel = function() return KIND, 1, ITEM end
ENV.WBW = { mode = 'move', speed = 1.0 }

local M
do
  local a = CL:find('local WBG = { hot = nil', 1, true)
  local b = CL:find('local function wbpAim()', a, true)
  assert(a and b, 'could not slice the gizmo')
  M = assert(load(CL:sub(a, b - 1)
    .. '\nreturn { handles = wbgHandles, pick = wbgPick, draw = wbwGizmo,'
    .. '          down = wbgDragStart, move = wbgDragMove, up = wbgDragEnd,'
    .. '          state = WBG }', 'gizmo', 't', ENV))()
end

local function screen(over)
  local it = { pos = { x = 0.0, y = 0.0, z = 30.0 }, h = 0.0, pitch = 0.0,
               width = 6.0, opacity = 255 }
  for k, v in pairs(over or {}) do it[k] = v end
  ITEM, KIND = it, 's'
  ENV.WBW.mode, ENV.WBW.speed = 'move', 1.0
  return it
end

-- where a handle sits on screen, for aiming the cursor at it
local function at(id)
  for _, h in ipairs(M.handles()) do
    if h.id == id then
      local _, sx, sy = GetScreenCoordFromWorldCoord(h.x, h.y, h.z)
      return sx, sy
    end
  end
end

-- ==========================================================================
-- 1. the three arrows are there and point the right way
-- ==========================================================================
local it = screen()
local hs = M.handles()
check('moving offers one handle per axis', #hs, 3)
check('  named for the axes',
      hs[1].id .. hs[2].id .. hs[3].id, 'xyz')
check('  and labelled',
      hs[1].label .. hs[2].label .. hs[3].label, 'XYZ')
check('  in red, green and blue',
      ('%d/%d/%d'):format(hs[1].r, hs[2].g, hs[3].b), '235/222/248')

check('the X arrow reaches east of the board',  hs[1].x > it.pos.x, true)
check('  the Y arrow north',                    hs[2].y > it.pos.y, true)
check('  and the Z arrow straight up',          hs[3].z > it.pos.z, true)

-- the arrows are a constant size on screen, so they do not vanish at range
local far = screen({ pos = { x = 0.0, y = 200.0, z = 30.0 } })
local nearHs, farHs = nil, M.handles()
screen()
nearHs = M.handles()
check('a distant board gets longer arrows, so they stay the same on screen',
      (farHs[1].x - far.pos.x) > (nearHs[1].x - 0.0), true)

-- ==========================================================================
-- 2. clicking picks the handle under the cursor, and only then
-- ==========================================================================
screen()
local sx, sy = at('x')
check('the cursor on the X arrow picks X', (M.pick(sx, sy) or {}).id, 'x')
local zx, zy = at('z')
check('  on the Z arrow picks Z',          (M.pick(zx, zy) or {}).id, 'z')
check('empty screen picks nothing',        M.pick(0.02, 0.95), nil)

check('a click that hits nothing is not a grab', M.down(0.02, 0.95), false)
check('  and leaves nothing held',               M.state.drag, nil)

-- ==========================================================================
-- 3. dragging an axis moves it along that axis, and no other
-- ==========================================================================
it = screen()
sx, sy = at('x')
check('grabbing the X arrow takes hold', M.down(sx, sy), true)
check('  and remembers which one',       M.state.drag.id, 'x')

-- one metre of world along X is SCALE screen units, so drag that far
M.move(sx + SCALE * 2.0, sy)
near('dragging it two metres of screen moves it two metres east', it.pos.x, 2.0)
near('  and not a millimetre north', it.pos.y, 0.0, 0.0001)
near('  nor up',                     it.pos.z, 30.0, 0.0001)

M.move(sx, sy)
near('dragging back puts it back', it.pos.x, 0.0)
M.up()
check('letting go releases it', M.state.drag, nil)

-- the same grab on the vertical arrow
it = screen()
local zx2, zy2 = at('z')
M.down(zx2, zy2)
M.move(zx2, zy2 - SCALE * 3.0)
near('dragging the blue arrow up lifts it three metres', it.pos.z, 33.0)
M.up()

-- ==========================================================================
-- 4. the step size multiplies the drag, like it does the buttons
-- ==========================================================================
it = screen()
ENV.WBW.speed = 2.0
sx, sy = at('x')
M.down(sx, sy)
M.move(sx + SCALE * 1.0, sy)
near('a 2x step size moves twice as far for the same drag', it.pos.x, 2.0)
M.up()
ENV.WBW.speed = 1.0

-- ==========================================================================
-- 5. size: green handles are the width, red ones the height
-- ==========================================================================
it = screen()
ENV.WBW.mode = 'size'
hs = M.handles()
check('size offers four handles', #hs, 4)
local ids = {}
for _, h in ipairs(hs) do ids[h.id] = (ids[h.id] or 0) + 1 end
check('  two for width',  ids.width, 2)
check('  and two for height', ids.height, 2)

sx, sy = at('width')
M.down(sx, sy)
check('the width handle is what was grabbed', M.state.drag.id, 'width')
M.move(sx + SCALE * 1.0, sy)
check('dragging it out widens the board', it.width > 6.0, true)
M.up()

-- height starts derived from the texture; dragging it pins it
it = screen()
ENV.WBW.mode = 'size'
check('a fresh board has no height of its own', it.height, nil)
local hx, hy = at('height')
M.down(hx, hy)
M.move(hx, hy - SCALE * 1.0)
check('dragging the height handle gives it one', it.height ~= nil, true)
check('  taller than it was',
      it.height > (6.0 * (720 / 1280)), true)
M.up()

-- a width drag must not be able to shrink it to nothing
it = screen()
ENV.WBW.mode = 'size'
sx, sy = at('width')
M.down(sx, sy)
M.move(sx - SCALE * 100.0, sy)
near('the width cannot be dragged below its floor', it.width, 0.5)
M.up()

-- ==========================================================================
-- 6. rotate: a ring you grab anywhere, and left to right turns it
-- ==========================================================================
it = screen()
ENV.WBW.mode = 'rotate'
hs = M.handles()
check('rotate offers one ring', #hs, 1)
check('  which is a ring, not an arrow', hs[1].ring ~= nil, true)

local _, cx, cy = GetScreenCoordFromWorldCoord(it.pos.x, it.pos.y, it.pos.z)
check('the ring is grabbed from near the middle', M.down(cx, cy), true)
M.move(cx + 0.1, cy)
check('dragging right turns it', it.h > 0.0, true)
local turned = it.h
M.move(cx, cy)
near('  and dragging back turns it back', it.h, turned - 52.0, 1.0)
M.up()

-- tilt comes off the same ring, up and down
it = screen()
ENV.WBW.mode = 'rotate'
_, cx, cy = GetScreenCoordFromWorldCoord(it.pos.x, it.pos.y, it.pos.z)
M.down(cx, cy)
M.move(cx, cy + 0.1)
check('dragging down leans it', it.pitch ~= 0.0, true)
check('  and it cannot lean past its limit',
      it.pitch >= -60.0 and it.pitch <= 60.0, true)
M.up()

-- a person has no width and no tilt to drag
ITEM, KIND = { pos = { x = 0.0, y = 0.0, z = 30.0 }, h = 90.0 }, 'p'
ENV.WBW.mode = 'size'
check('a podium spot has no size handles', #M.handles(), 0)
ENV.WBW.mode = 'rotate'
M.down(0.5, 0.5)
M.move(0.6, 0.6)
check('turning one still works',      ITEM.h ~= 90.0, true)
check('  and it is never given a tilt', ITEM.pitch, nil)
M.up()

-- ==========================================================================
-- 7. it draws something for every handle
-- ==========================================================================
it = screen()
ENV.WBW.mode = 'move'
DRAWN = { lines = 0, markers = 0, text = {} }
M.draw()
check('the board outline and three arrows are drawn', DRAWN.lines >= 4 + 3 * 5, true)
check('  each arrow tipped with a marker',            DRAWN.markers >= 4, true)
check('  and each one labelled',
      table.concat(DRAWN.text), 'XYZ')

print(fails > 0 and ('\n%d FAILED of %d'):format(fails, checks)
                or ('\nALL PASS (%d checks)'):format(checks))
os.exit(fails > 0 and 1 or 0)
