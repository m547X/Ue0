-- Where the placed board is kept, and who the leaderboard lists.
--
--   lua5.4 tests/board_store.lua
--
-- Two things that both read as "it does not work" and neither of which says
-- anything when it goes wrong.
--
-- A board placed with the editor is written to m5_world_board and read back on
-- the next start. If that read comes back as something other than a layout,
-- the old code stored it anyway — an empty table counts as a layout, and a
-- layout with no screens in it draws nothing and does not fall back to the
-- config either. So the board an admin placed simply vanished on restart, with
-- the console saying it had loaded.
--
-- And the leaderboard in the menu: it lists a mode's ladder, so anybody
-- holding RP in that mode belongs on it.

local SV = io.open('M5_RankedPvP/Files/Server.lua'):read('a')

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

-- ==========================================================================
-- a database that can be made to misbehave
-- ==========================================================================
local ENV = setmetatable({}, { __index = _G })

local PUSHES = 0
ENV.WorldBoard = { rows = {}, builtAt = 0, pool = nil, layout = nil,
                   push = function() PUSHES = PUSHES + 1 end }
ENV.now = function() return 0 end
ENV.ms  = function() return 0 end
ENV.sqlDate = function() return '2026-01-01 00:00:00' end

local ERRORS, LOGS = {}, {}
ENV.err = function(fmt, ...) ERRORS[#ERRORS + 1] = select('#', ...) > 0 and fmt:format(...) or fmt end
ENV.log = function(fmt, ...) LOGS[#LOGS + 1]   = select('#', ...) > 0 and fmt:format(...) or fmt end
ENV.dbg = function() end

-- the one row the table holds, and a switch to make writing to it fail
local STORED, WRITES_LAND = nil, true
ENV.DB = {
  single = function() return STORED ~= nil and { layout = STORED } or nil end,
  scalar = function() return STORED end,
  update = function(_, params)
    if WRITES_LAND then STORED = params[1] end
    return WRITES_LAND and 1 or 0
  end
}

ENV.jsonEncode = function(v)
  local function enc(t)
    if type(t) ~= 'table' then
      if type(t) == 'string' then return ('%q'):format(t) end
      return tostring(t)
    end
    local isArray = #t > 0
    local parts = {}
    if isArray then
      for i = 1, #t do parts[#parts + 1] = enc(t[i]) end
      return '[' .. table.concat(parts, ',') .. ']'
    end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for i = 1, #keys do
      parts[#parts + 1] = ('%q'):format(tostring(keys[i])) .. ':' .. enc(t[keys[i]])
    end
    return '{' .. table.concat(parts, ',') .. '}'
  end
  return enc(v)
end

--- A small real JSON reader, so what comes back out of the table is parsed
--- rather than guessed at with patterns.
local function parse(s, i)
  local function skip()
    while i <= #s and s:sub(i, i):match('%s') do i = i + 1 end
  end
  local value
  local function str()
    i = i + 1
    local out = {}
    while i <= #s and s:sub(i, i) ~= '"' do
      local c = s:sub(i, i)
      if c == '\\' then i = i + 1 c = s:sub(i, i) end
      out[#out + 1] = c
      i = i + 1
    end
    i = i + 1
    return table.concat(out)
  end
  value = function()
    skip()
    local c = s:sub(i, i)
    if c == '{' then
      i = i + 1
      local t = {}
      skip()
      if s:sub(i, i) == '}' then i = i + 1 return t end
      while true do
        skip()
        local k = str()
        skip()
        i = i + 1                                   -- the colon
        t[k] = value()
        skip()
        local d = s:sub(i, i)
        i = i + 1
        if d == '}' then return t end
        if d ~= ',' then error('bad object') end
      end
    elseif c == '[' then
      i = i + 1
      local t = {}
      skip()
      if s:sub(i, i) == ']' then i = i + 1 return t end
      while true do
        t[#t + 1] = value()
        skip()
        local d = s:sub(i, i)
        i = i + 1
        if d == ']' then return t end
        if d ~= ',' then error('bad array') end
      end
    elseif c == '"' then
      return str()
    elseif s:sub(i, i + 3) == 'true'  then i = i + 4 return true
    elseif s:sub(i, i + 4) == 'false' then i = i + 5 return false
    elseif s:sub(i, i + 3) == 'null'  then i = i + 4 return nil
    else
      local n = s:match('^%-?%d+%.?%d*[eE]?[%+%-]?%d*', i)
      if not n or n == '' then error('bad value at ' .. i) end
      i = i + #n
      return tonumber(n)
    end
  end
  return value()
end

-- a decoder that behaves the way the real one does, including its fallback
ENV.jsonDecode = function(v, fallback)
  if type(v) == 'table' then return v end
  if type(v) ~= 'string' or v == '' then return fallback or {} end
  local ok, res = pcall(parse, v, 1)
  if ok and type(res) == 'table' then return res end
  return fallback or {}
end

do
  local a = SV:find('function WorldBoard.loadLayout()', 1, true)
  local b = SV:find('function WorldBoard.on()', a, true)
  assert(a and b, 'could not slice the layout store')
  assert(load(SV:sub(a, b - 1), 'store', 't', ENV))()
end

local WB = ENV.WorldBoard

local function layout(screens, podium)
  local out = { screens = {}, podium = {},
                screensEnabled = true, podiumEnabled = true, podiumDistance = 25.0 }
  for i = 1, screens do
    out.screens[i] = { pos = { x = 100.0 + i, y = 200.0, z = 30.0 }, h = 90.0,
                       pitch = 0.0, width = 6.0, rows = 10, opacity = 255,
                       distance = 35.0, title = 'BOARD' .. i, enabled = true }
  end
  for i = 1, podium do
    out.podium[i] = { pos = { x = 110.0 + i, y = 200.0, z = 29.0 }, h = 90.0 }
  end
  return out
end

-- ==========================================================================
-- 1. what an admin places comes back after a restart
-- ==========================================================================
local ok = WB.saveLayout(7, layout(1, 3))
check('placing a board saves it', ok, true)
check('  and something really went into the table', STORED ~= nil, true)

WB.layout = nil                                   -- the restart
WB.loadLayout()
check('it is there again on the next start', WB.layout ~= nil, true)
check('  with the screen that was placed',  #WB.layout.screens, 1)
check('  and the three podium spots',       #WB.layout.podium, 3)
check('  at the place it was put',          WB.layout.screens[1].pos.x, 101.0)
check('  facing the way it was turned',     WB.layout.screens[1].h, 90.0)
check('  and the console says it loaded',   #LOGS > 0, true)

-- ==========================================================================
-- 2. a row that cannot be read falls back instead of blanking the board
-- ==========================================================================
-- This is the one that made a placed board disappear. An empty table is not a
-- layout, but it is truthy, so it was kept — and a layout with no screens in
-- it draws nothing AND stops the config spots being used. The board was gone
-- and the console had said it loaded.
ERRORS = {}
STORED = 'this is not json'
WB.layout = 'something'
WB.loadLayout()
check('an unreadable row is not treated as a layout', WB.layout, nil)
check('  so the config spots are used again',          WB.layout == nil, true)
check('  and it is said out loud',                     #ERRORS, 1)
check('  naming the table',
      (ERRORS[1] or ''):find('m5_world_board', 1, true) ~= nil, true)

-- a layout with nothing in it is the same case
ERRORS = {}
STORED = '{"screens":[],"podium":[]}'
WB.loadLayout()
check('a layout with nothing in it is no layout', WB.layout, nil)

-- and no row at all is simply "nothing placed yet", which is not an error
ERRORS = {}
STORED = nil
WB.loadLayout()
check('no row at all is not an error', #ERRORS, 0)
check('  and the config stands',       WB.layout, nil)

-- ==========================================================================
-- 3. a save that did not land says so
-- ==========================================================================
-- It used to answer "The board layout was saved." whatever the database did,
-- so an admin placed it, was told it saved, and found it gone after a restart
-- with nothing to go on.
WRITES_LAND = false
STORED = nil
ERRORS = {}
local saved, why = WB.saveLayout(7, layout(1, 0))
check('a save that did not land does not claim it did', saved, false)
check('  and says it will be gone on restart',
      (why or ''):find('restart', 1, true) ~= nil, true)
check('  with the reason in the console',   #ERRORS, 1)

WRITES_LAND = true
check('an empty layout is refused rather than stored',
      select(1, WB.saveLayout(7, { screens = {}, podium = {} })), false)

-- ==========================================================================
-- 4. what the stored layout is allowed to contain
-- ==========================================================================
-- It is read back off a table anyone with database access can edit, so it goes
-- through the same cleaning as what the editor sends.
STORED = ENV.jsonEncode({
  screens = { { pos = { x = 999999.0, y = 0.0, z = 0.0 }, h = 0.0, width = 6.0 } },
  podium = {}
})
WB.loadLayout()
check('a screen somewhere off the map is dropped on load', WB.layout, nil)

STORED = ENV.jsonEncode({
  screens = { { pos = { x = 10.0, y = 10.0, z = 10.0 }, h = 400.0,
                width = 900.0, pitch = 999.0, rows = 4000, opacity = -5 } },
  podium = {}
})
WB.loadLayout()
check('a width nobody could have set is clamped', WB.layout.screens[1].width, 40.0)
check('  the tilt too',                           WB.layout.screens[1].pitch, 60.0)
check('  the row count too',                      WB.layout.screens[1].rows, 25)
check('  and the heading wrapped back round',     WB.layout.screens[1].h, 40.0)

-- ==========================================================================
-- 5. the leaderboard lists the ladder, not the match log
-- ==========================================================================
-- The mode tabs used to be built from m5_match_players, so a player who holds
-- a rank but has not played recently was not on the leaderboard at all — and a
-- server seeded straight into the ladder showed nothing under any tab.
local route = SV:match('elseif mode then.-\n.-\n')
check('a mode tab reads that mode\'s ladder',
      route:find('Board.global(page, showMMR, Player.poolOf(mode))', 1, true) ~= nil, true)

local global = SV:match('function Board%.global.-\nend')
check('the ladder query is on the rank table',
      global:find('FROM m5_player_ranks r', 1, true) ~= nil, true)
check('  for the season and the mode asked for',
      global:find('WHERE r.season_id = ? AND r.mode = ?', 1, true) ~= nil, true)

-- Holding placement back was what emptied a new server's leaderboard: nobody
-- has finished their placement matches on day one, so nobody was listed.
check('  and it does not hide everyone who is mid-placement',
      global:find('placement_done = 1', 1, true), nil)
check('  highest RP first',
      global:find('ORDER BY r.rp DESC', 1, true) ~= nil, true)

-- every row carries the player's picture, like every other list in the menu
local decorate = SV:match('local function decorateRow.-\nend')
check('a listed player carries their picture',
      decorate:find('avatar    = avatarFor', 1, true) ~= nil, true)

print()
print(fails > 0 and ('%d FAILED of %d'):format(fails, checks)
                or ('ALL PASS (%d checks)'):format(checks))
os.exit(fails > 0 and 1 or 0)
