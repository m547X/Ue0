-- The map vote resolving early, the coma probe, and the search that would not
-- stop — all on the real functions out of the shipped files.
--
--   lua5.4 tests/vote_coma_queue.lua
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

local CLOCK = 0
function ms() return CLOCK end
function log() end
function err() end

-- ==========================================================================
-- 1. the map vote: decided is decided, so stop counting down
-- ==========================================================================
local RESOLVED, SENT = 0, {}
Match = {
  resolveMapVote = function() RESOLVED = RESOLVED + 1 end,
  broadcast      = function(_, _, data) SENT[#SENT + 1] = data end
}

do
  local a = SV:find('function Match.vote(m, userId, mapId)', 1, true)
  local b = SV:find('function Match.resolveMapVote', a, true)
  assert(a and b, 'could not slice Match.vote')
  assert(load(SV:sub(a, b - 1), 'vote', 't',
         setmetatable({ Match = Match }, { __index = _G })))()
end

local function voteMatch(players)
  RESOLVED, SENT = 0, {}
  local m = { id = 'm1', state = 'MAP_VOTE', mapVotes = {}, players = {},
              mapOptions = { { id = 'dust' }, { id = 'neon1' }, { id = 'lego' } } }
  for i = 1, players do m.players[i] = { connected = true } end
  return m
end

local m = voteMatch(2)
check('the first of two votes does not decide it', Match.vote(m, 1, 'dust') and RESOLVED, 0)
check('  but the tally goes out',                  #SENT, 1)
check('the second vote ends it there',             Match.vote(m, 2, 'neon1') and RESOLVED, 1)

-- a vote for a map that is not on offer changes nothing
m = voteMatch(2)
check('a map that was not offered is refused', Match.vote(m, 1, 'atlantis'), false)
check('  and nothing is decided',              RESOLVED, 0)

-- somebody who is not in the match cannot vote
m = voteMatch(2)
check('an outsider cannot vote', Match.vote(m, 99, 'dust'), false)

-- voting twice is changing your mind, not a second vote
m = voteMatch(2)
Match.vote(m, 1, 'dust')
Match.vote(m, 1, 'neon1')
check('changing your own vote does not decide it', RESOLVED, 0)
check('  and the change is recorded',              m.mapVotes[1], 'neon1')
Match.vote(m, 2, 'dust')
check('  the other player still ends it',          RESOLVED, 1)

-- a player who left is not waited for
m = voteMatch(3)
m.players[3].connected = false
Match.vote(m, 1, 'dust')
Match.vote(m, 2, 'dust')
check('a disconnected player is not waited for', RESOLVED, 1)

-- and the vote is only open during the vote
m = voteMatch(2)
m.state = 'LIVE'
check('voting after the vote is over is refused', Match.vote(m, 1, 'dust'), false)

-- one player, alone: their vote is the whole vote
m = voteMatch(1)
Match.vote(m, 1, 'lego')
check('a single player decides on their own', RESOLVED, 1)

-- ==========================================================================
-- 2. the coma probe: a vRP without isInComa must not be asked twice
-- ==========================================================================
local ASKS = 0
Config = { ComaWatch = { enabled = true, interval = 2000 } }

-- vRP's Proxy hands back a callable for any name at all, so asking whether the
-- function "exists" always says yes. It is the answer that tells you: a call it
-- does not have returns nothing.
vRP = setmetatable({}, { __index = function()
  return function() ASKS = ASKS + 1 return nil end
end })

local comaWatchOn, inComa
do
  local a = SV:find('local function comaWatchOn()', 1, true)
  local b = SV:find('function Match.checkComa(m)', a, true)
  assert(a and b, 'could not slice the coma helpers')
  comaWatchOn, inComa = assert(load(
    'local comaSupported = nil\n' .. SV:sub(a, b - 1) ..
    '\nreturn comaWatchOn, inComa', 'coma'))()
end

check('the watch starts willing', comaWatchOn(), true)
check('  and the type check alone would have said yes',
      type(vRP.isInComa), 'function')

check('a vRP with no isInComa answers nothing', inComa(1), false)
check('  which turns the watch off',            comaWatchOn(), false)
local after = ASKS
inComa(2)
inComa(3)
check('  and it is never asked again', ASKS, after)

-- a vRP that does have it is believed, both ways
ASKS = 0
local ANSWER = true
vRP = { isInComa = function() ASKS = ASKS + 1 return ANSWER end }
do
  local a = SV:find('local function comaWatchOn()', 1, true)
  local b = SV:find('function Match.checkComa(m)', a, true)
  comaWatchOn, inComa = assert(load(
    'local comaSupported = nil\n' .. SV:sub(a, b - 1) ..
    '\nreturn comaWatchOn, inComa', 'coma'))()
end
check('a real isInComa saying yes is believed', inComa(1), true)
ANSWER = false
check('  and saying no',                        inComa(1), false)
check('  and it keeps being asked',             comaWatchOn(), true)

-- one that throws is also the end of it
vRP = { isInComa = function() error('proxy exploded') end }
do
  local a = SV:find('local function comaWatchOn()', 1, true)
  local b = SV:find('function Match.checkComa(m)', a, true)
  comaWatchOn, inComa = assert(load(
    'local comaSupported = nil\n' .. SV:sub(a, b - 1) ..
    '\nreturn comaWatchOn, inComa', 'coma'))()
end
check('a throwing isInComa is answered false', inComa(1), false)
check('  and turns the watch off',             comaWatchOn(), false)

-- switched off in the config, nothing is asked at all
Config.ComaWatch.enabled = false
check('switched off: the watch is off', comaWatchOn(), false)
Config.ComaWatch.enabled = true

-- ==========================================================================
-- 3. entering a match ends the search
-- ==========================================================================
-- The dock kept counting and the button kept offering to cancel a search that
-- had already found the match the player was standing in.
local addPlayer = SV:match('function Match%.addPlayer.-\nend')
assert(addPlayer, 'could not find Match.addPlayer')
check('joining a match tells the client the search is over',
      addPlayer:find("m5rp:cl:queue", 1, true) ~= nil, true)
check('  and tells it the search is idle',
      addPlayer:find("state = 'IDLE'", 1, true) ~= nil, true)

print()
print(fails == 0 and ('ALL PASS (%d checks)'):format(checks)
                 or ('%d FAILED'):format(fails))
os.exit(fails == 0 and 0 or 1)
