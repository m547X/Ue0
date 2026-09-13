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
-- 1. the vote: three questions, one timer, and decided is decided
-- ==========================================================================
local RESOLVED, SENT = 0, {}
Match = {
  resolveMapVote = function() RESOLVED = RESOLVED + 1 end,
  broadcast      = function(_, _, data) SENT[#SENT + 1] = data end
}

function inList(list, value)
  for i = 1, #list do if list[i] == value then return true end end
  return false
end

do
  local a = SV:find('local function voteGroups(m)', 1, true)
  local b = SV:find('function Match.resolveMapVote', a, true)
  assert(a and b, 'could not slice Match.vote')
  assert(load(SV:sub(a, b - 1), 'vote', 't',
         setmetatable({ Match = Match }, { __index = _G })))()
end

--- A match mid-vote. `groups` says which questions are being asked, so the
--- same helper covers a map-only vote and the full three.
local function voteMatch(players, groups)
  groups = groups or { map = true }
  RESOLVED, SENT = 0, {}
  local m = {
    id = 'm1', state = 'MAP_VOTE', players = {},
    mapVotes = {}, weaponVotes = {}, ruleVotes = {},
    mapOptions    = groups.map and { { id = 'dust' }, { id = 'neon1' }, { id = 'lego' } } or {},
    weaponOptions = groups.weapon and { 'sniper', 'smg', 'knife' } or {},
    ruleVote      = groups.rule == true
  }
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
-- 1b. the weapon and the kill rule, on the same screen and the same timer
-- ==========================================================================
-- One answer each is owed, and the vote runs until every player has answered
-- every question. A map picked but no weapon picked is not a finished vote.
m = voteMatch(1, { map = true, weapon = true, rule = true })
check('the map alone does not finish a three part vote',
      Match.vote(m, 1, 'map', 'dust') and RESOLVED, 0)
check('  nor the weapon on top of it',
      Match.vote(m, 1, 'weapon', 'smg') and RESOLVED, 0)
check('the last answer finishes it',
      Match.vote(m, 1, 'rule', 'head') and RESOLVED, 1)
check('  and each answer went to its own group', m.weaponVotes[1], 'smg')
check('  including the rule',                    m.ruleVotes[1], 'head')

-- two players, and neither is finished until both are
m = voteMatch(2, { map = true, weapon = true })
Match.vote(m, 1, 'map', 'dust')
Match.vote(m, 1, 'weapon', 'sniper')
check('one player answering everything is not the whole vote', RESOLVED, 0)
Match.vote(m, 2, 'map', 'dust')
check('  nor the other answering half of it',                  RESOLVED, 0)
Match.vote(m, 2, 'weapon', 'knife')
check('  both, on everything, ends it',                        RESOLVED, 1)

-- a weapon that was not offered, and a rule that is not one of the two
m = voteMatch(2, { map = true, weapon = true, rule = true })
check('a weapon that was not offered is refused', Match.vote(m, 1, 'weapon', 'minigun'), false)
check('a rule that is neither is refused',        Match.vote(m, 1, 'rule', 'maybe'), false)
check('  full body is one of them',               Match.vote(m, 1, 'rule', 'full'), true)
check('  headshot only is the other',             Match.vote(m, 1, 'rule', 'head'), true)

-- a group that is switched off is not asked about and not waited for
m = voteMatch(1, { map = true })
check('voting on a weapon nobody offered is refused',
      Match.vote(m, 1, 'weapon', 'smg'), false)
check('  and the map alone still finishes the vote',
      Match.vote(m, 1, 'map', 'dust') and RESOLVED, 1)

-- a vote with no map in it at all, which is what a one-map mode sends
m = voteMatch(1, { weapon = true })
check('a weapon-only vote is finished by the weapon',
      Match.vote(m, 1, 'weapon', 'smg') and RESOLVED, 1)

-- the old two-argument call still means a map vote
m = voteMatch(1)
check('the old vote(m, id, mapId) shape still works', Match.vote(m, 1, 'dust'), true)
check('  and lands in the map group',                 m.mapVotes[1], 'dust')

-- every group's tally goes out on every vote, so each counter can be painted
m = voteMatch(2, { map = true, weapon = true, rule = true })
Match.vote(m, 1, 'map', 'dust')
Match.vote(m, 2, 'weapon', 'smg')
local last = SENT[#SENT]
check('the broadcast carries a tally per group',
      last.tallies and last.tallies.map and last.tallies.weapon
      and last.tallies.rule ~= nil, true)
check('  the map count is right',    last.tallies.map.dust, 1)
check('  and the weapon count',      last.tallies.weapon.smg, 1)
check('  and the old votes field still carries the map',
      last.votes and last.votes.dust, 1)

-- ==========================================================================
-- 1c. picking the winner
-- ==========================================================================
local winnerOf
do
  local a = SV:find('local function tallyOf(votes)', 1, true)
  local b = SV:find('function Match.vote(m, userId, kind, choice)', a, true)
  winnerOf = assert(load(SV:sub(a, b - 1) .. '\nreturn winnerOf', 'win'))()
end

check('the most votes wins', winnerOf({ [1] = 'a', [2] = 'b', [3] = 'b' }), 'b')
check('one vote wins on its own', winnerOf({ [1] = 'a' }), 'a')
check('nobody voting has no winner', winnerOf({}), nil)

-- a tie is broken at random, so what is checked is that it picks one of them
-- and does not favour whichever the table happened to hand back first
local seen = {}
for _ = 1, 200 do seen[winnerOf({ [1] = 'a', [2] = 'b' })] = true end
check('a tie picks one of the tied options',
      (seen.a or seen.b) and not seen.c, true)
check('  and over 200 draws it picks both at least once',
      seen.a == true and seen.b == true, true)

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
