-- The training drills are described entirely in Config_Server.lua and the
-- client is handed a finished spec, because the client must never read the
-- server config — that is what crashed every headshot once already. These
-- checks run the real resolvers against the real config file, so a drill added
-- there arrives at the client whole, and a pace nobody offers cannot be asked
-- for from the interface.
--
--   lua5.4 tests/training.lua
local SV = io.open('M5_RankedPvP/Files/Server.lua'):read('a')
local CS = io.open('M5_RankedPvP/الاعدادات/Config_Server.lua'):read('a')
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

-- ==========================================================================
-- the real Config.Training, out of the real config file
-- ==========================================================================
Config = {}
do
  local a = CS:find('Config.Training%s*=%s*{')
  assert(a, 'could not find Config.Training')
  -- read to the closing brace of the assignment by counting depth
  local depth, i, started = 0, a, false
  while i <= #CS do
    local c = CS:sub(i, i)
    if c == '{' then depth = depth + 1; started = true
    elseif c == '}' then depth = depth - 1; if started and depth == 0 then break end end
    i = i + 1
  end
  local chunk = CS:sub(a, i)
  assert(load(chunk, 'training-config', 't',
         setmetatable({ Config = Config, vector4 = function(x, y, z, w)
           return { x = x, y = y, z = z, w = w } end },
           { __index = _G })))()
end

Training = {}
do
  local a = SV:find('function Training.paceList(mode)', 1, true)
  local b = SV:find('function Training.start(userId, kind, pace)', a, true)
  assert(a and b, 'could not slice the training resolvers')
  assert(load(SV:sub(a, b - 1), 'training', 't',
         setmetatable({ Training = Training, Config = Config }, { __index = _G })))()
end

-- ==========================================================================
-- 1. the card list the interface is built from
-- ==========================================================================
local list = Training.modeList()
check('every drill in the config is offered', #list >= 5, true)

local byKind, order = {}, {}
for i = 1, #list do byKind[list[i].kind] = list[i]; order[i] = list[i].kind end

check('the drills come back in the order the config asks for',
      table.concat(order, ','), 'aim,headshot,moving,reflex,range')
check('each one carries its name',   byKind.moving.label, 'MOVING TARGETS')
check('  and its description',       type(byKind.moving.desc), 'string')
check('the reflex drill offers paces', #byKind.reflex.paces, 3)
check('  named for the player',      byKind.reflex.paces[1].label, 'SLOW')
check('  by id',                     byKind.reflex.paces[3].id, 'fast')
check('a drill with no paces says so', byKind.aim.paces, nil)
check('  and neither does the open range', byKind.range.paces, nil)

-- ==========================================================================
-- 2. the pace the player asked for, and the one they get when they ask for
--    something that is not on offer
-- ==========================================================================
local reflexMode = Config.Training.modes.reflex
check('the asked-for pace is the one resolved',
      Training.paceOf(reflexMode, 'fast').id, 'fast')
check('an unknown pace falls back to the default',
      Training.paceOf(reflexMode, 'ludicrous').id, 'normal')
check('no pace at all falls back to the default',
      Training.paceOf(reflexMode, nil).id, 'normal')
check('a drill with no paces resolves to nothing',
      Training.paceOf(Config.Training.modes.aim, 'fast'), nil)

-- ==========================================================================
-- 3. the spec the client is handed
-- ==========================================================================
local reflex = Training.spec('reflex', reflexMode, 'fast')
check('a reflex drill sends a reflex spec', type(reflex), 'table')
check('  with the chosen pace',       reflex.pace, 'fast')
check('  its target lifetime',        reflex.live > 0, true)
check('  the gap between targets',    reflex.gap >= 0, true)
check('  how many are up at once',    reflex.up >= 1, true)
check('  the arc they appear in',     reflex.arc > 0, true)
check('  and the near and far range', reflex.far > reflex.near, true)

local _, moving = Training.spec('moving', Config.Training.modes.moving, nil)
check('a moving drill sends a moving spec', type(moving), 'table')
check('  with the arena size',        moving.area > 0, true)
check('  a closest spawn distance',   moving.minDist > 0, true)
check('  and a respawn delay',        moving.respawn >= 0, true)

-- the speed mix is flattened by weight, so the client only has to pick at
-- random and still gets the spread the config asked for
local seen = {}
for i = 1, #moving.speeds do
  seen[moving.speeds[i].id] = (seen[moving.speeds[i].id] or 0) + 1
end
check('the speed mix is flattened for the client', #moving.speeds, 4)
check('  walk appears once',   seen.walk, 1)
check('  jog twice, as weighted', seen.jog, 2)
check('  sprint once',         seen.sprint, 1)
check('  and every speed carries a number', moving.speeds[1].speed > 0, true)

local r2, m2 = Training.spec('aim', Config.Training.modes.aim, nil)
check('a plain drill sends neither spec', r2 == nil and m2 == nil, true)

-- ==========================================================================
-- 4. a broken config is refused rather than sent half-built
-- ==========================================================================
local noPaces = { reflex = { default = 'x', paces = {} } }
check('a reflex drill with no paces resolves to nothing',
      Training.spec('reflex', noPaces, 'slow'), nil)
check('  and offers none to the interface', Training.paceList(noPaces), nil)

local noSpeeds = { moving = { area = 10.0, speeds = {} } }
local _, m3 = Training.spec('moving', noSpeeds, nil)
check('a moving drill with no speeds still gets one', #m3.speeds, 1)

-- ==========================================================================
-- 5. the client reads none of this out of the config itself
-- ==========================================================================
-- Config.Training.exit is the one part that lives in Config_Client.lua; every
-- other field has to arrive in the event payload.
local reads = {}
for field in CL:gmatch('Config%.Training%.([%a_]+)') do reads[field] = true end
local extra = {}
for field in pairs(reads) do
  if field ~= 'exit' then extra[#extra + 1] = field end
end
table.sort(extra)
check('the client reads nothing but the exit settings from Config.Training',
      table.concat(extra, ','), '')

-- and the spec fields it does read all come off the payload
check('the client takes the pace spec off the event',
      CL:find('data.reflex', 1, true) ~= nil, true)
check('  and the movement spec too',
      CL:find('data.moving', 1, true) ~= nil, true)

print(fails > 0 and ('\n%d FAILED of %d'):format(fails, checks)
                or ('\nALL PASS (%d checks)'):format(checks))
os.exit(fails > 0 and 1 or 0)
