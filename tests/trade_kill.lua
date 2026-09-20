-- Two players kill each other, and they are the last two alive.
--
--   lua5.4 tests/trade_kill.lua
--
-- Nothing in a shooter arrives at the same instant. Both bullets leave, both
-- land, but the two death reports reach the server milliseconds apart — and
-- the gap is the two players' ping, not their aim. So the question this asks
-- is: does the round go to whoever's report arrived first?
--
-- It used to. Match.evaluateRound ended the round the moment one side hit
-- zero alive, Match.endRound moved the state off LIVE, and the second death
-- was then thrown away by the guard at the top of registerKill — no death on
-- their record, no kill for the player who fired it, and the round to the
-- player with the better connection.
--
-- The real registerKill, evaluateRound and the LIVE branch of the tick are
-- sliced out of Server.lua and fed a 1v1 where both players die 40ms apart.

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

-- ==========================================================================
-- just enough server for the round to resolve in
-- ==========================================================================
local CLOCK = 0
function ms()  return CLOCK end
function now() return math.floor(CLOCK / 1000) end
local function advance(n) CLOCK = CLOCK + n end

function srcOf() return nil end
function log() end
function err() end
function dbg() end
function TriggerClientEvent() end

-- SetTimeout is the precise path; the tick is the backstop. The test drives
-- the clock itself, so timers are collected and fired by hand.
local TIMERS = {}
function SetTimeout(delay, fn) TIMERS[#TIMERS + 1] = { at = CLOCK + delay, fn = fn } end
local function runTimers()
  local due = {}
  for i = #TIMERS, 1, -1 do
    if TIMERS[i].at <= CLOCK then due[#due + 1] = TIMERS[i]; table.remove(TIMERS, i) end
  end
  for i = #due, 1, -1 do due[i].fn() end
end

Matches, Players = {}, {}

Config = {
  Match = {
    tradeWindow = 300, roundEndTime = 6, spawnProtection = 3,
    tickInterval = 250, maxMatchDuration = 3600,
    surrender = { cooldown = 60 }, overtime = { enabled = false }
  },
  CombatEvents = {
    ace = { enabled = false }, killStreak = { enabled = false },
    doubleKill = { window = 5000 }, nemesis = { enabled = false, threshold = 3 }
  },
  Database = { maxKillRowsPerMatch = 800 },
  SpectatorRules = { deathDelay = 2 },
  Loadouts = { standard = { weapons = {} } }
}

local ROUNDS = {}
Match = {}

local FEED = {}
local ENV = setmetatable({
  Match = Match,
  combatEvent = function() end,
  addKillFeed = function(_, killer, victim) FEED[#FEED + 1] = (killer or '-') .. '>' .. victim end,
  presetWeapons = function() return {} end,
  spawnPointFor = function() return { x = 0, y = 0, z = 0 } end,
  loadoutFor = function() return {} end,
  DB = { insert = function() end }
}, { __index = _G })

-- the real aliveCount, so "alive" means what the server means by it
do
  local a = SV:find('local function aliveCount(m, team)', 1, true)
  local b = SV:find('local AvatarCache', a, true)
  assert(a and b, 'could not slice aliveCount')
  ENV.aliveCount = assert(load(SV:sub(a, b - 1) .. '\nreturn aliveCount', 'ac', 't', ENV))()
end

-- the real registerKill, evaluateRound, resolveElimination and checkMatchOver
do
  local a = SV:find('function Match.registerKill(m, killerId, victimId', 1, true)
  local b = SV:find('function Match.checkAce(m, winnerTeam)', a, true)
  assert(a and b, 'could not slice the kill and round resolution')
  assert(load(SV:sub(a, b - 1), 'kill', 't', ENV))()
end

-- the parts of the round that the resolution leans on, as stubs that record
Match.pushHud   = function() end
Match.checkAce  = function() end
Match.broadcast = function() end
Match.endMatch  = function(m, winner) m.state = 'MATCH_END'; m.winner = winner end
Match.endRound  = function(m, winner, reason)
  if m.state ~= 'LIVE' then return end
  if winner == 1 or winner == 2 then m.scores[winner] = m.scores[winner] + 1 end
  ROUNDS[#ROUNDS + 1] = { round = m.round, winner = winner, reason = reason,
                          a = m.scores[1], b = m.scores[2] }
  m.state = 'ROUND_END'
end

-- the LIVE branch's trade check, lifted out so the tick path is covered too
local function tick(m)
  if m.state ~= 'LIVE' then return end
  if m.tradeUntil and ms() >= m.tradeUntil then Match.resolveElimination(m) end
end

local function player(userId, team)
  return { userId = userId, name = 'P' .. userId, team = team, alive = true,
           connected = true, kills = 0, deaths = 0, assists = 0, score = 0,
           headshots = 0, killStreak = 0, bestKillStreak = 0, deadAt = 0,
           weapons = {}, nemesis = {}, damageTaken = {}, multiKill = { n = 0, ts = 0 },
           roundsWon = 0, clutches = 0, firstBloods = 0 }
end

local function match()
  ROUNDS, TIMERS = {}, {}
  local m = {
    id = 'M-1', state = 'LIVE', round = 1, scores = { 0, 0 }, ffa = false,
    cfg = { type = 'elimination' },
    settings = { respawn = false, respawnTime = 5, rounds = 5, roundsToWin = 3,
                 matchType = 'standard', friendlyFire = false, weapons = {} },
    players = { [1] = player(1, 1), [2] = player(2, 2) },
    killLog = {}, roundLog = {}, feed = {}, lastHudPush = 0, roundStartMs = 0
  }
  Matches[m.id] = m
  return m
end

-- ==========================================================================
-- 1. the old behaviour: first report home wins
-- ==========================================================================
-- Switching the window off is the behaviour this started from, so the test
-- states plainly what it was.
Config.Match.tradeWindow = 0
local m = match()

Match.registerKill(m, 1, 2, 'WEAPON_PISTOL', false, 8.0)
check('with no window, one death ends the round on the spot', m.state, 'ROUND_END')
check('  and it goes to the player who was still standing', ROUNDS[1].winner, 1)

advance(40)
check('  the other death is refused, because the round is over',
      Match.registerKill(m, 2, 1, 'WEAPON_PISTOL', false, 8.0), false)
check('  so nobody records it as a death', m.players[1].deaths, 0)
check('  and the player who fired it gets no kill', m.players[2].kills, 0)

-- ==========================================================================
-- 2. with the window: the second bullet still counts
-- ==========================================================================
Config.Match.tradeWindow = 300
m = match()

Match.registerKill(m, 1, 2, 'WEAPON_PISTOL', false, 8.0)
check('the round is held open while the bullets land', m.state, 'LIVE')
check('  nothing has been awarded yet',                 #ROUNDS, 0)
check('  and the window is armed for exactly as long as the config says',
      m.tradeUntil - ms(), 300)

advance(40)
check('the trade kill is taken',
      Match.registerKill(m, 2, 1, 'WEAPON_PISTOL', false, 8.0), true)
check('  it is a death on their record',   m.players[1].deaths, 1)
check('  a kill for the one who fired it', m.players[2].kills, 1)
check('  and both sides are down',         ENV.aliveCount(m, 1) + ENV.aliveCount(m, 2), 0)

check('the round is a draw',            ROUNDS[1].winner, 0)
check('  and says why',                 ROUNDS[1].reason, 'TRADE')
check('  neither side scores from it',  ROUNDS[1].a .. '-' .. ROUNDS[1].b, '0-0')
check('  the round is over now',        m.state, 'ROUND_END')
check('  with both sides at the same score', m.scores[1] == m.scores[2], true)

-- ==========================================================================
-- 3. a clean kill is still a clean kill
-- ==========================================================================
-- The window must not turn every round into a draw: if nobody trades, it runs
-- out and the round goes to whoever is left.
m = match()
Match.registerKill(m, 1, 2, 'WEAPON_PISTOL', false, 8.0)
check('a kill with nothing coming back holds for the window', m.state, 'LIVE')

advance(299)
tick(m)
check('  and is still held one millisecond short of it', m.state, 'LIVE')

advance(1)
tick(m)
check('the round goes to the survivor once the window passes', m.state, 'ROUND_END')
check('  by elimination, not a draw', ROUNDS[1].reason, 'ELIMINATION')
check('  to the team still standing', ROUNDS[1].winner, 1)
check('  which scores',               m.scores[1], 1)

-- ==========================================================================
-- 4. the timer path, for a server whose tick is busy
-- ==========================================================================
m = match()
Match.registerKill(m, 1, 2, 'WEAPON_PISTOL', false, 8.0)
advance(300)
runTimers()
check('the timer resolves it without waiting for a tick', m.state, 'ROUND_END')
check('  to the survivor',                                 ROUNDS[1].winner, 1)

-- a timer that fires into a round that already moved on must do nothing
m = match()
Match.registerKill(m, 1, 2, 'WEAPON_PISTOL', false, 8.0)
m.state, m.round = 'LIVE', 2          -- the round was restarted under it
advance(300)
runTimers()
check('a timer from a round that has been and gone is ignored', #ROUNDS, 0)
check('  and it does not leave the window armed', m.tradeUntil, nil)

-- ==========================================================================
-- 5. three a side: the window opens only when a side is actually wiped
-- ==========================================================================
m = match()
m.players[3] = player(3, 1)
m.players[4] = player(4, 2)
m.players[5] = player(5, 2)

Match.registerKill(m, 1, 4, 'WEAPON_PISTOL', false, 8.0)
check('killing one of three arms nothing', m.tradeUntil, nil)
check('  and the round carries on',        m.state, 'LIVE')

Match.registerKill(m, 1, 5, 'WEAPON_PISTOL', false, 8.0)
check('killing the second still arms nothing', m.tradeUntil, nil)

Match.registerKill(m, 1, 2, 'WEAPON_PISTOL', false, 8.0)
check('wiping the side arms the window',   m.tradeUntil ~= nil, true)
check('  with the round still open',       m.state, 'LIVE')

-- and the last two of the losing side's killers can still be traded
advance(50)
Match.registerKill(m, 2, 1, 'WEAPON_PISTOL', false, 8.0)
check('one of two survivors dying is not a wipe', m.state, 'LIVE')
Match.registerKill(m, 2, 3, 'WEAPON_PISTOL', false, 8.0)
check('the last one dying inside the window makes it a draw', ROUNDS[1].reason, 'TRADE')

print(fails > 0 and ('\n%d FAILED of %d'):format(fails, checks)
                or ('\nALL PASS (%d checks)'):format(checks))
os.exit(fails > 0 and 1 or 0)
