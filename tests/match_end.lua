-- Four fixes from the round of reports, checked on the real functions.
--
-- These live in the repository rather than in a scratch directory, because the
-- last set did not survive the machine being rebuilt.
--
--   lua5.4 tests/match_end.lua
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
local CLOCK = 0
function ms()  return CLOCK end
function now() return math.floor(CLOCK / 1000) end
function log() end
function err() end
function dbg() end

Matches, Players, Reconnects = {}, {}, {}
-- who the server can actually still see. checkForfeit trusts this over the
-- `connected` flag, because the flag is bookkeeping and bookkeeping drifts.
local ONLINE = {}
function srcOf(userId) return ONLINE[userId] end
Config = {
  Match = { minPlayersToContinue = 1, abandonForfeitDelay = 60 },
  ComaWatch = { enabled = true, interval = 2000 }
}

local ENDED, ABORTED, BROADCASTS = {}, {}, {}
Match = {
  endMatch  = function(m, winner, reason)
                ENDED[#ENDED + 1] = { id = m.id, winner = winner, reason = reason }
                m.state = 'MATCH_END'
              end,
  abort     = function(m, reason)
                ABORTED[#ABORTED + 1] = { id = m.id, reason = reason }
                Matches[m.id] = nil
                m.state = 'CLEANUP'
              end,
  broadcast = function(_, _, data) BROADCASTS[#BROADCASTS + 1] = data end
}

-- the real checkForfeit and its helper
do
  local a = SV:find('function Match.checkForfeit(m)', 1, true)
  local b = SV:find('function Match.tryReconnect', a, true)
  assert(a and b, 'could not slice checkForfeit')
  assert(load(SV:sub(a, b - 1), 'forfeit', 't',
         setmetatable({ Match = Match }, { __index = _G })))()
end

local function match(teams, state)
  local m = { id = 'm1', state = state or 'LIVE', ffa = false,
              forfeitTimer = {}, players = {} }
  local n = 0
  ONLINE = {}
  for team, count in pairs(teams) do
    for _ = 1, count do
      n = n + 1
      m.players[n] = { team = team, connected = true }
      ONLINE[n] = 100 + n            -- everybody is on the server to begin with
    end
  end
  Matches[m.id] = m
  ENDED, ABORTED, BROADCASTS = {}, {}, {}
  return m
end

--- the player leaves the way the code expects: flag cleared and gone
local function leaves(m, id)
  m.players[id].connected = false
  ONLINE[id] = nil
end

--- and the way that caused the stuck match: gone, but still marked connected
local function vanishes(m, id)
  ONLINE[id] = nil
end

-- ==========================================================================
-- 1. a match whose opponent walked out has to end
-- ==========================================================================
local m = match({ [1] = 1, [2] = 1 })
Match.checkForfeit(m)
check('both sides present: nothing happens', #ENDED, 0)

-- the opponent leaves a 1v1
leaves(m, 2)
Match.checkForfeit(m)
check('the opponent leaves: the match ends at once', #ENDED, 1)
check('  and the player who stayed wins',            ENDED[1] and ENDED[1].winner, 1)
check('  recorded as a forfeit',                     ENDED[1] and ENDED[1].reason, 'FORFEIT')

-- the other way round, so the winner is not simply always team 1
m = match({ [1] = 1, [2] = 1 })
leaves(m, 1)
Match.checkForfeit(m)
check('whichever side empties, the other wins', ENDED[1] and ENDED[1].winner, 2)

-- ==========================================================================
-- 2. unless somebody is coming back
-- ==========================================================================
m = match({ [1] = 1, [2] = 1 })
leaves(m, 2)
Reconnects[2] = { matchId = 'm1', expires = now() + 120 }
Match.checkForfeit(m)
check('a pending reconnect holds the match open', #ENDED, 0)
check('  and the short-handed warning goes out',   #BROADCASTS, 1)

-- and when that window closes, it ends
CLOCK = CLOCK + 121000
Match.checkForfeit(m)
check('the reconnect window lapses: the match ends', #ENDED, 1)
Reconnects[2] = nil

-- ==========================================================================
-- 3. a team that is short but not empty still gets its grace period
-- ==========================================================================
m = match({ [1] = 3, [2] = 3 })
Config.Match.minPlayersToContinue = 2
leaves(m, 4)
leaves(m, 5)                            -- team 2 is down to one, not empty
Match.checkForfeit(m)
check('short handed but not empty: a timer, not an end', #ENDED, 0)
check('  and the players are told',                      #BROADCASTS, 1)

Match.checkForfeit(m)
check('the timer is not restarted on the next tick', #BROADCASTS, 1)
check('  and it has not fired yet',                  #ENDED, 0)

CLOCK = CLOCK + 61000
Match.checkForfeit(m)
check('once it expires the match ends', #ENDED, 1)
Config.Match.minPlayersToContinue = 1

-- and a team that fills back up clears its timer
m = match({ [1] = 3, [2] = 3 })
Config.Match.minPlayersToContinue = 2
leaves(m, 4)
leaves(m, 5)
Match.checkForfeit(m)
m.players[4].connected = true           -- somebody reconnected
ONLINE[4] = 104
Match.checkForfeit(m)
check('a team that fills back up is not on a timer', m.forfeitTimer[2], nil)
CLOCK = CLOCK + 61000
Match.checkForfeit(m)
check('  and does not forfeit later', #ENDED, 0)
Config.Match.minPlayersToContinue = 1

-- ==========================================================================
-- 4. nobody left at all: the match goes, rather than sitting in memory
-- ==========================================================================
m = match({ [1] = 1, [2] = 1 })
leaves(m, 1)
leaves(m, 2)
Match.checkForfeit(m)
check('an empty match is aborted',      #ABORTED, 1)
check('  and taken out of the table',   Matches['m1'], nil)
check('  without being counted as a win', #ENDED, 0)

-- a free for all with one player left standing
m = match({ [1] = 1, [2] = 1, [3] = 1 })
m.ffa = true
leaves(m, 2)
Match.checkForfeit(m)
check('a free for all with two left runs on', #ENDED, 0)
leaves(m, 3)
Match.checkForfeit(m)
check('  and ends when one is left',          #ENDED, 1)

-- a match already over is never ended twice
m = match({ [1] = 1, [2] = 1 }, 'MATCH_END')
leaves(m, 2)
Match.checkForfeit(m)
check('a finished match is left alone', #ENDED, 0)

-- ==========================================================================
-- 5. the stuck match: gone, but the seat still says connected
-- ==========================================================================
-- This is what "0 players, 1 matches" with two people in it actually was. A
-- drop that did not reach the match left the seat marked as taken, and the
-- match then waited forever on somebody who had closed the game.
m = match({ [1] = 1, [2] = 1 })
vanishes(m, 2)
check('a seat marked connected but gone is not believed', m.players[2].connected, true)
Match.checkForfeit(m)
check('  the flag is corrected',       m.players[2].connected, false)
check('  and the match ends',          #ENDED, 1)
check('  for the player who stayed',   ENDED[1] and ENDED[1].winner, 1)

-- both of them vanish that way
m = match({ [1] = 1, [2] = 1 })
vanishes(m, 1)
vanishes(m, 2)
Match.checkForfeit(m)
check('both vanish: the match is dropped', #ABORTED, 1)
check('  and nothing is left behind',      Matches['m1'], nil)

-- a player who is genuinely there is never mistaken for a ghost
m = match({ [1] = 1, [2] = 1 })
Match.checkForfeit(m)
check('everyone present: nobody is corrected', m.players[1].connected, true)
check('  and the match runs on',               #ENDED, 0)

print()
print(fails == 0 and ('ALL PASS (%d checks)'):format(checks)
                 or ('%d FAILED'):format(fails))
os.exit(fails == 0 and 0 or 1)
