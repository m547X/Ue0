-- Everything the board editor saves was typed into a panel by a player and
-- arrives over the network, so the server treats it as a suggestion. These
-- checks run the real sanitiser: a board four hundred metres wide, or one
-- parked under the map, or a hundred of them, all have to come back refused or
-- clamped rather than stored.
--
--   lua5.4 tests/board_layout.lua
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

WorldBoard = {}
local sanitise
do
  local a = SV:find('local function sanitiseSpot(v, withHeading)', 1, true)
  local b = SV:find('function WorldBoard.saveLayout(userId, raw)', a, true)
  assert(a and b, 'could not slice the layout sanitiser')
  assert(load(SV:sub(a, b - 1), 'layout', 't',
         setmetatable({ WorldBoard = WorldBoard }, { __index = _G })))()
  sanitise = WorldBoard.sanitiseLayout
end

local function screen(over)
  local s = { pos = { x = 10, y = 20, z = 30 }, title = 'TOP', enabled = true,
              scale = 1.0, width = 1.0, rows = 10, opacity = 190, distance = 18 }
  for k, v in pairs(over or {}) do s[k] = v end
  return s
end

local function layout(over)
  local l = { screens = { screen() }, podium = { { pos = { x = 1, y = 2, z = 3 }, h = 90 } },
              screensEnabled = true, podiumEnabled = true, podiumDistance = 25 }
  for k, v in pairs(over or {}) do l[k] = v end
  return l
end

-- ==========================================================================
-- 1. an ordinary layout goes through unchanged
-- ==========================================================================
local out = sanitise(layout())
check('a normal layout is accepted', out ~= nil, true)
check('  with its screen',           #out.screens, 1)
check('  and its podium spot',       #out.podium, 1)
check('  the position is kept',      out.screens[1].pos.x, 10)
check('  the title is kept',         out.screens[1].title, 'TOP')
check('  and the facing',            out.podium[1].h, 90)

-- ==========================================================================
-- 2. numbers are clamped, not trusted
-- ==========================================================================
-- the width is metres of world now, not a percentage of a drawn panel
out = sanitise(layout({ screens = { screen({ width = 900 }) } }))
check('a board the size of a city block is clamped', out.screens[1].width, 40.0)
out = sanitise(layout({ screens = { screen({ width = -5 }) } }))
check('  and a negative one',        out.screens[1].width, 0.5)

out = sanitise(layout({ screens = { screen({ h = 400 }) } }))
check('a facing past a full turn wraps round', out.screens[1].h, 40.0)
out = sanitise(layout({ screens = { screen({ pitch = 200 }) } }))
check('a tilt past upside down is clamped',    out.screens[1].pitch, 60.0)

out = sanitise(layout({ screens = { screen({ distance = 5000 }) } }))
check('a board visible from a kilometre away is clamped', out.screens[1].distance, 200.0)

out = sanitise(layout({ screens = { screen({ rows = 999 }) } }))
check('the row count is clamped', out.screens[1].rows, 25)
out = sanitise(layout({ screens = { screen({ rows = 7.6 }) } }))
check('  and is a whole number',  out.screens[1].rows, 7)

out = sanitise(layout({ screens = { screen({ opacity = 900 }) } }))
check('the opacity stays a byte', out.screens[1].opacity, 255)

out = sanitise(layout({ podium = { { pos = { x = 1, y = 2, z = 3 }, h = 725 } } }))
check('a heading past a full turn wraps', out.podium[1].h, 5)

-- a value that is not a number at all falls back rather than propagating nil
out = sanitise(layout({ screens = { screen({ width = 'wide', rows = {} }) } }))
check('text where a number belongs falls back', out.screens[1].width, 4.0)
check('  and so does a table',                  out.screens[1].rows, 9)

-- ==========================================================================
-- 3. positions have to be real places
-- ==========================================================================
out = sanitise(layout({ screens = { screen({ pos = { x = 9e9, y = 0, z = 0 } }) } }))
check('a board past the edge of the world is dropped', #out.screens, 0)

out = sanitise(layout({ screens = { screen({ pos = { x = 0, y = 0, z = -9000 } }) } }))
check('  and one under the map',                       #out.screens, 0)

out = sanitise(layout({ screens = { screen({ pos = { x = 'here', y = 0, z = 0 } }) } }))
check('  and one with text for a coordinate',          #out.screens, 0)

-- pairs() skips a nil, so the entry is built without a pos rather than with one
out = sanitise(layout({ screens = { { title = 'NO POS', width = 1 } } }))
check('  and one with no position at all',             #out.screens, 0)

-- but dropping one bad screen keeps the good ones
out = sanitise(layout({ screens = {
  screen({ pos = { x = 9e9, y = 0, z = 0 } }), screen({ title = 'GOOD' }) } }))
check('a bad screen is dropped and the good one kept', #out.screens, 1)
check('  and it is the good one',                      out.screens[1].title, 'GOOD')

-- ==========================================================================
-- 4. the limits on how much can be stored
-- ==========================================================================
local many = {}
for i = 1, 100 do many[i] = screen() end
out = sanitise(layout({ screens = many }))
check('a hundred screens are cut to the cap', #out.screens, 12)

local lots = {}
for i = 1, 20 do lots[i] = { pos = { x = 1, y = 2, z = 3 }, h = 0 } end
out = sanitise(layout({ podium = lots }))
check('the podium is three, whatever is sent', #out.podium, 3)

local long = string.rep('x', 500)
out = sanitise(layout({ screens = { screen({ title = long }) } }))
check('a very long title is cut short', #out.screens[1].title, 48)

-- ==========================================================================
-- 5. nothing usable is nothing saved
-- ==========================================================================
check('a layout that is not a table is refused', sanitise('hello'), nil)
check('nil is refused',                          sanitise(nil), nil)
check('an empty layout is refused',
      sanitise({ screens = {}, podium = {} }), nil)
check('a layout whose every entry is bad is refused',
      sanitise({ screens = { screen({ pos = { x = 9e9, y = 0, z = 0 } }) }, podium = {} }), nil)

-- ==========================================================================
-- 6. the switches survive the trip
-- ==========================================================================
out = sanitise(layout({ podiumEnabled = false }))
check('the podium switch is carried', out.podiumEnabled, false)
out = sanitise(layout({ screensEnabled = false }))
check('  and the screens switch',     out.screensEnabled, false)
out = sanitise(layout({ screens = { screen({ enabled = false }) } }))
check('  and a single screen switch', out.screens[1].enabled, false)

-- ==========================================================================
-- 7. only somebody allowed to can save it
-- ==========================================================================
check('saving is behind a permission',
      SV:find('hasPerm(pd.userId, Config.Permissions.editBoard)', 1, true) ~= nil, true)
check('  and a refusal is logged rather than ignored',
      SV:find('tried to move the world board without permission', 1, true) ~= nil, true)
check('  what is saved is the sanitised copy, not what arrived',
      SV:find('local clean = WorldBoard.sanitiseLayout(raw)', 1, true) ~= nil, true)
check('  and everyone is told about the new layout',
      SV:find('WorldBoard.push()', 1, true) ~= nil, true)

print()
print(fails == 0 and ('ALL PASS (%d checks)'):format(checks)
                 or ('%d FAILED'):format(fails))
os.exit(fails == 0 and 0 or 1)
