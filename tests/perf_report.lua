-- The perf report is the one thing that is never exercised until somebody is
-- already looking for a problem, and it is nothing but format strings. A `%d`
-- handed a nil is a crash at exactly the wrong moment, so it is rendered here
-- against real counters.
--
--   lua5.4 tests/perf_report.lua
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
local CLOCK = 600000
function ms() return CLOCK end
function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

Config = {
  Match       = { tickInterval = 250 },
  Matchmaking = { tickInterval = 2000 }
}
Matches, Players, PermCache, UsedBuckets = {}, {}, {}, {}
local ONLINE = {}
function srcOf(id) return ONLINE[id] end
Matchmaker  = { searchingCount = function() return 0 end }
CustomGames = { rooms = {} }
Board       = { cache = {} }
Store       = { cache = {} }
DB          = { txAvailable = true }

Perf = { startedAt = 0, boots = 3, net = { queue = 40, store = 9 },
  vrp  = { calls = 12, wall = 30 },
  loop = { ticks = 340, busy = 12, cpu = 0.42, worst = 0.004,
           causeMatch = 12, causeBots = 0, causeQueue = 0 },
  db   = { calls = 63, wall = 4219, cpu = 0.1,
           kinds = { read = 40, write = 23 }, worst = 924, worstKind = 'write',
           reads = { n = 40, wall = 160 }, writes = { n = 23, wall = 4059 },
           baseline = 2 } }

local perfReport
do
  local a = SV:find('local function perfReport(printer)', 1, true)
  local b = SV:find("RegisterCommand('m5perf'", a, true)
  assert(a and b, 'could not slice perfReport')
  perfReport = assert(load(SV:sub(a, b - 1) .. '\nreturn perfReport', 'perf', 't',
                      setmetatable({}, { __index = _G })))()
end

local function render()
  local out = {}
  local ok, e = pcall(perfReport, function(line) out[#out + 1] = line end)
  if not ok then return nil, e end
  return table.concat(out, '\n')
end

local function has(text, s) return text:find(s, 1, true) ~= nil end

-- ==========================================================================
-- 1. it renders at all, on an idle server
-- ==========================================================================
local text, e = render()
check('an idle report renders without erroring', text ~= nil, true)
if not text then print('  ' .. tostring(e)) os.exit(1) end

check('  no nil leaked into a line', has(text, 'nil'), false)
check('  the tick rates are named',  has(text, '250 ms while busy, 1000 ms idle'), true)

-- ==========================================================================
-- 2. it says whether the usage is high, rather than only printing a number
-- ==========================================================================
-- 0.42s of work in 10 minutes is nothing, and the report should say so instead
-- of leaving it to be read off a percentage.
check('a quiet loop is called out as quiet',
      has(text, 'not what is loading the server'), true)

Perf.loop.cpu = 30          -- 30s of cpu in a 10 minute window
check('a loop doing real work is called out as high',
      has(render(), 'high — the loop is doing real work'), true)

Perf.loop.cpu = 15
check('and the middle is neither', has(render(), 'noticeable, but not a problem'), true)
Perf.loop.cpu = 0.42

-- ==========================================================================
-- 3. slow writes against fast reads name the cause
-- ==========================================================================
-- 176 ms a write against 4 ms a read, on a connection that answers SELECT 1 in
-- 2 ms. Nothing about that is the query or the network.
check('a healthy round trip is reported as healthy',
      has(text, 'SELECT 1 — healthy'), true)
check('  and the slow writes are blamed on the commit, not the query',
      has(text, 'innodb_flush_log_at_trx_commit'), true)

Perf.db.writes = { n = 23, wall = 200 }        -- writes as quick as reads
check('writes in line with reads say nothing about flushing',
      has(render(), 'innodb_flush_log_at_trx_commit'), false)
Perf.db.writes = { n = 23, wall = 4059 }

Perf.db.baseline = 40
check('a slow round trip is blamed on the connection',
      has(render(), 'this is the connection, not the queries'), true)
Perf.db.baseline = 2

DB.txAvailable = false
check('an oxmysql without transactions is called out',
      has(render(), 'NO transaction support'), true)
DB.txAvailable = true

-- ==========================================================================
-- 4. the stuck match, which is the report telling you why it is busy
-- ==========================================================================
Matches.m1 = { id = 'm1', players = { [7] = { connected = true },
                                      [8] = { connected = true } } }
ONLINE[7] = 107                                  -- 8 closed the game
text = render()
check('the seats are counted apart from the profiles',
      has(text, '2 seats, 1 still connected'), true)
check('  and the one who is gone is named',
      has(text, '1 marked connected but gone'), true)
check('  with what it costs spelled out',
      has(text, 'holds the whole loop at the fast'), true)

ONLINE[8] = 108
check('nobody missing, nothing said about ghosts',
      has(render(), 'marked connected but gone'), false)

-- ==========================================================================
-- 5. an empty server, where every counter is zero
-- ==========================================================================
-- Divide by zero and format a nil are both live here, so it is worth its own
-- pass.
Matches, ONLINE = {}, {}
Perf.db = { calls = 0, wall = 0, cpu = 0, kinds = {}, worst = 0, worstKind = '',
            reads = { n = 0, wall = 0 }, writes = { n = 0, wall = 0 } }
Perf.loop = { ticks = 0, busy = 0, cpu = 0, worst = 0,
              causeMatch = 0, causeBots = 0, causeQueue = 0 }
Perf.net, Perf.vrp, Perf.boots = {}, { calls = 0, wall = 0 }, 0
text, e = render()
check('a report with nothing in it still renders', text ~= nil, true)
if text then
  check('  and says so rather than showing a blank', has(text, 'by kind         none'), true)
  check('  no nan or inf anywhere', has(text, 'nan') or has(text, 'inf'), false)
end

print()
print(fails == 0 and ('ALL PASS (%d checks)'):format(checks)
                 or ('%d FAILED'):format(fails))
os.exit(fails == 0 and 0 or 1)
