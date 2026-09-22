-- Where the board actually hangs.
--
--   lua5.4 tests/world_board_quad.lua
--
-- The board is a web page painted onto a texture and stretched over two
-- triangles out in the world. Nothing about that is visible from the code: if
-- the corners are wound the wrong way it is invisible from the front, if the
-- UVs are swapped it is mirrored, and if the height is not derived from the
-- texture the picture is stretched. So the real corner maths is sliced out of
-- Client.lua and the quad it produces is measured.
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
  check(name, math.abs(got - want) <= (slack or 0.001), true)
end

-- ==========================================================================
-- the slice, and just enough of a world for it to run in
-- ==========================================================================
local ENV = setmetatable({}, { __index = _G })
local POLY = {}

ENV.Config = { WorldBoard = { screens = { textureWidth = 1280, textureHeight = 720 } },
               UI = { colors = {} }, Brand = {} }
ENV.WB = { rows = {}, season = 'SEASON 1' }
ENV.vec3 = function(p) return { x = p.x + 0.0, y = p.y + 0.0, z = p.z + 0.0 } end
ENV.json = { encode = function(t) return t end }
CLOCK = 0
ENV.ms = function() return CLOCK end
ENV.GetCurrentResourceName = function() return 'M5_RankedPvP' end
ENV.CreateDui = function() return 1 end
ENV.GetDuiHandle = function() return 'handle' end
ENV.CreateRuntimeTxd = function() return 1 end
ENV.CreateRuntimeTextureFromDuiHandle = function() return 1 end
SENT, URLS, AVAIL = {}, {}, false
ENV.IsDuiAvailable = function() return AVAIL end
ENV.SendDuiMessage = function(_, m) SENT[#SENT + 1] = m end
ENV.SetDuiUrl = function(_, u) URLS[#URLS + 1] = u end
ENV.DestroyDui = function() end

-- the corner maths is the only trigonometry in the hot path, so it is counted
local TRIG = 0
ENV.math = setmetatable({ rad = function(d) TRIG = TRIG + 1; return math.rad(d) end },
                        { __index = math })

ENV.DrawSpritePoly = function(x1,y1,z1, x2,y2,z2, x3,y3,z3, r,g,b,a, txd, tex,
                              u1,v1,w1, u2,v2,w2, u3,v3,w3)
  POLY[#POLY + 1] = {
    p = { { x1,y1,z1 }, { x2,y2,z2 }, { x3,y3,z3 } },
    uv = { { u1,v1 }, { u2,v2 }, { u3,v3 } },
    a = a, txd = txd, tex = tex
  }
end

do
  local a = CL:find('local DUI = {', 1, true)
  local b = CL:find('local function wbDespawn()', a, true)
  assert(a and b, 'could not slice the board drawing')
  local chunk = CL:sub(a, b - 1)
    .. '\nreturn { corners = screenCorners, size = screenSize, draw = drawScreen,'
    .. '         create = duiCreate, destroy = duiDestroy, push = duiPush,'
    .. '         flush = duiFlush, park = duiPark, dui = DUI }'
  M = assert(load(chunk, 'board', 't', ENV))()
end

-- ==========================================================================
-- 1. the shape of it
-- ==========================================================================
local spot = { pos = { x = 100.0, y = 200.0, z = 30.0 }, h = 0.0, pitch = 0.0,
               width = 8.0, opacity = 255 }

local w, h = M.size(spot)
check('the width is the one that was asked for', w, 8.0)
near('  and the height keeps the texture undistorted', h, 8.0 * (720 / 1280))
check('  a height written by hand is used instead',
      select(2, M.size({ pos = spot.pos, width = 8.0, height = 3.0 })), 3.0)

local tlx, tly, tlz, trx, try, trz, brx, bry, brz, blx, bly, blz = M.corners(spot)

near('the board is centred on its position, east to west',
     (tlx + trx + brx + blx) / 4, 100.0)
near('  north to south', (tly + try + bry + bly) / 4, 200.0)
near('  and in height',  (tlz + trz + brz + blz) / 4, 30.0)

near('it is as wide as it was told to be',
     math.sqrt((trx - tlx) ^ 2 + (try - tly) ^ 2), 8.0)
near('  and as tall as the texture makes it', tlz - blz, 8.0 * (720 / 1280))
check('  the top edge is level',    math.abs(tlz - trz) < 0.001, true)
check('  and the bottom edge too',  math.abs(blz - brz) < 0.001, true)
check('  it stands upright with no tilt asked for',
      math.abs(tlx - blx) < 0.001 and math.abs(tly - bly) < 0.001, true)

-- at heading 0 the board runs east to west, so it is read facing north
near('facing 0 lays it along the east-west axis', math.abs(try - tly), 0.0)
near('  spanning x',                              math.abs(trx - tlx), 8.0)

-- turning it 90 degrees swings it onto the other axis
local turned = { pos = spot.pos, h = 90.0, pitch = 0.0, width = 8.0 }
local a1x, a1y, _, b1x, b1y = M.corners(turned)
near('turning it a quarter swings it onto the north-south axis',
     math.abs(b1y - a1y), 8.0)
near('  and it no longer spans x', math.abs(b1x - a1x), 0.0)

-- tilting leans the top away without changing where it is centred
local tilted = { pos = spot.pos, h = 0.0, pitch = 30.0, width = 8.0 }
local t2x, t2y, t2z, _, _, _, _, _, _, b2x, b2y, b2z = M.corners(tilted)
check('tilting leans the top off the vertical', math.abs(t2y - b2y) > 0.1, true)
near('  and the middle stays where it was', (t2z + b2z) / 2, 30.0)
check('  a tilted board is shorter in height than it is long',
      (t2z - b2z) < (8.0 * (720 / 1280)), true)

-- ==========================================================================
-- 2. what is actually drawn
-- ==========================================================================
POLY = {}
M.draw(spot)
check('nothing is drawn before the texture exists', #POLY, 0)

check('the board is built on demand', M.create(), true)

-- CEF takes a moment to open the page. Anything sent before it is there is
-- lost, and a texture drawn before it is there is whatever was in memory.
POLY = {}
M.flush()
M.draw(spot)
check('nothing is drawn while the page is still opening', #POLY, 0)
check('  and nothing is sent to it either',                #SENT, 0)

-- But it cannot wait for ever. A browser that never reports itself available —
-- and there is no way to tell that apart from one that is merely slow — used
-- to mean a board that was never drawn at all, which looks exactly like a
-- board that was never placed. After a few seconds it is drawn regardless:
-- blank is visible and can be reasoned about, invisible cannot.
POLY = {}
CLOCK = 10000
M.draw(spot)
check('a page that never opens still gets a board', #POLY > 0, true)
check('  and still nothing has been sent to it',    #SENT, 0)
CLOCK = 0

AVAIL = true
M.flush()
check('the rows are sent once the page is open', #SENT, 1)
M.flush(); M.flush()
check('  and only once',                         #SENT, 1)

POLY = {}
M.draw(spot)

check('a quad is two triangles a side', #POLY, 4)
check('  drawn from the board texture', POLY[1].txd, 'm5rp_board_txd')
check('  and it is the one the page was painted into', POLY[1].tex, 'm5rp_board')
check('  at the opacity the layout asked for', POLY[1].a, 255)

-- the first two cover the whole texture between them, right way up
local seen = {}
for i = 1, 2 do
  for n = 1, 3 do
    seen[POLY[i].uv[n][1] .. ',' .. POLY[i].uv[n][2]] = true
  end
end
check('the front face covers the whole picture',
      seen['0.0,0.0'] and seen['1.0,0.0'] and seen['1.0,1.0'] and seen['0.0,1.0'], true)

-- the top-left corner of the texture is drawn at the top-left corner of the
-- board, which is what keeps the picture the right way up and not mirrored
local function cornerOf(tri, u, v)
  for n = 1, 3 do
    if tri.uv[n][1] == u and tri.uv[n][2] == v then return tri.p[n] end
  end
end
local topLeft = cornerOf(POLY[1], 0.0, 0.0)
near('the top of the picture is at the top of the board', topLeft[3], tlz)
near('  and its left edge at the left edge', topLeft[1], tlx)

-- the back two are the same quad wound the other way, so the board is not
-- invisible from behind
local front = {}
for n = 1, 3 do front[POLY[1].p[n][1] .. ':' .. POLY[1].p[n][3]] = true end
local sharedBack = 0
for n = 1, 3 do
  if front[POLY[3].p[n][1] .. ':' .. POLY[3].p[n][3]] then sharedBack = sharedBack + 1 end
end
check('the back face is the same quad, wound the other way', sharedBack, 3)
check('  and it is not the same winding as the front',
      POLY[1].p[1][1] ~= POLY[3].p[1][1] or POLY[1].p[1][3] ~= POLY[3].p[1][3], true)

-- ==========================================================================
-- 2b. both windings, every time
-- ==========================================================================
-- A flat panel has two sides and you can only stand on one of them, so for a
-- while only the facing pair was drawn — two triangles instead of four, and
-- the saving is real. It is not worth it.
--
-- DRAW_SPRITE_POLY is single sided, and which winding the engine treats as
-- the front is not something a script can ask. Get it the wrong way round and
-- the facing pair is the culled one — so the board is invisible from the
-- front AND from the back, while every flag in the client says it is being
-- drawn. That is exactly what it looks like when a board was never placed,
-- and there is nothing on screen to tell the two apart.
--
-- Four triangles a frame is not a cost worth that risk, so both windings are
-- drawn and one of them is guaranteed to be the one that shows.
POLY = {}
M.draw(spot, 100.0, 190.0, 30.0)
check('standing in front of it, both windings go out', #POLY, 4)
check('  and the readable one is among them',
      cornerOf(POLY[1], 0.0, 0.0) ~= nil, true)

POLY = {}
M.draw(spot, 100.0, 210.0, 30.0)
check('standing behind it, the same four', #POLY, 4)

POLY = {}
M.draw(spot)
check('with no eye given, still four', #POLY, 4)

-- the corners are eight sines and cosines; they do not change while the board
-- hangs there, so they are worked out once and kept
local moving = { pos = { x = 5.0, y = 6.0, z = 7.0 }, h = 41.0, pitch = 3.0,
                 width = 5.0, opacity = 255 }
TRIG = 0
M.corners(moving)
check('the corner maths runs the first time', TRIG > 0, true)
local firstRun = TRIG
for _ = 1, 50 do M.corners(moving) end
check('  and not again while nothing has moved', TRIG, firstRun)

local before = { M.corners(moving) }
moving.h = 42.0
local after = { M.corners(moving) }
check('  but moving it works them out afresh', TRIG > firstRun, true)
check('  and the board really did turn', before[1] ~= after[1], true)

-- ==========================================================================
-- 3. the texture is given back
-- ==========================================================================
-- walking away parks the page on a blank one rather than tearing the texture
-- out from under the handle it was built from
M.park()
check('walking away blanks the page', URLS[#URLS], 'about:blank')
POLY = {}
M.draw(spot)
check('  and nothing is drawn while it is parked', #POLY, 0)

SENT = {}
M.create()
check('coming back points it at the board again',
      URLS[#URLS]:find('board.html', 1, true) ~= nil, true)
check('  and nothing is sent until it has opened', #SENT, 0)
M.flush()
check('  then the rows go out once more',          #SENT, 1)

M.destroy()
check('stopping the resource forgets the page', M.dui.ready, false)
POLY = {}
M.draw(spot)
check('  and nothing is drawn after that', #POLY, 0)

print(fails > 0 and ('\n%d FAILED of %d'):format(fails, checks)
                or ('\nALL PASS (%d checks)'):format(checks))
os.exit(fails > 0 and 1 or 0)
