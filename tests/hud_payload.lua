-- What the server builds every time it pushes the HUD.
--
--   lua5.4 tests/hud_payload.lua
--
-- The scoreboard goes out roughly once a second, to every player, for as long
-- as the match runs. A five-minute 5v5 is about three hundred pushes, and the
-- payload is a row per player — so the shape of this one function decides
-- whether a busy server spends its afternoon collecting garbage.
--
-- Two things are checked here and they pull against each other:
--
--   the rows must be the same tables every push, not fresh ones;
--   and they must still be *right* — kills that changed, a player who left,
--   the order the board is sorted in.
--
-- A cache that goes stale is worse than no cache, so the second half is the
-- important half.

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
-- a server with two teams on it
-- ==========================================================================
local ENV = setmetatable({}, { __index = _G })

ENV.Players  = {}
ENV.Parties  = {}
ENV.Store    = { cache = {}, customImage = function() return nil end }
ENV.UserToSrc = { [1] = 11, [2] = 12, [3] = 13, [4] = 14 }
ENV.now = function() return 0 end
ENV.ms  = function() return 0 end
ENV.err, ENV.dbg, ENV.log = function() end, function() end, function() end

ENV.srcOf = function(userId) return ENV.UserToSrc[userId] end
ENV.GetPlayerName = function(s) return 'p' .. tostring(s) end
ENV.GetPlayerPing = function(s) return s end
ENV.PerformHttpRequest = function() end
ENV.Citizen = { CreateThread = function() end }

ENV.Config = {
  Avatars = { enabled = false },
  TeamNames = { mode = 'leader', pick = 'rank', pattern = "%s'S TEAM",
                fixed = { [1] = 'TEAM A', [2] = 'TEAM B' } }
}

local M
do
  local a = SV:find('local function teamPlayers(m, team)', 1, true)
  local b = SV:find('function Match.create(opts)', a, true)
  assert(a and b, 'could not slice the payload code')
  M = assert(load(SV:sub(a, b - 1)
    .. '\nreturn { rows = playerListPayload, teamName = teamNameFor }',
    'hud', 't', ENV))()
end

local function player(name, team, rank, kills)
  return { name = name, team = team, rankName = rank, rankId = rank,
           alive = true, connected = true, kills = kills or 0, deaths = 0,
           assists = 0, headshots = 0, damage = 0, score = kills or 0 }
end

local m = {
  id = 'M1',
  players = {
    [1] = player('ALPHA',  1, 5, 3),
    [2] = player('BRAVO',  1, 2, 1),
    [3] = player('CHARLIE', 2, 7, 4),
    [4] = player('DELTA',  2, 1, 0)
  }
}

-- ==========================================================================
-- 1. it says the right thing
-- ==========================================================================
local rows, byUser, aliveA, aliveB = M.rows(m)
check('every player is on the board', #rows, 4)
check('  team A counted alive', aliveA, 2)
check('  team B counted alive', aliveB, 2)
check('team A comes first',     rows[1].team, 1)
check('  best score at the top of their side', rows[1].name, 'ALPHA')
check('  and the same on the other side',      rows[3].name, 'CHARLIE')
check('a row can be found by user id', byUser[2].name, 'BRAVO')
check('  carrying the server id to send it to', byUser[2].serverId, 12)
check('  and their ping',                       byUser[2].ping, 12)

-- ==========================================================================
-- 2. the second push reuses the first one's tables
-- ==========================================================================
-- The list is sorted, so a given player does not keep the same slot and a
-- row table does not belong to a player. What matters is that the second push
-- hands back tables the first push already made, and makes none of its own.
local pool = {}
for i = 1, #rows do pool[rows[i]] = true end

local rows2, byUser2 = M.rows(m)
check('the board is the same table every push', rawequal(rows, rows2), true)
check('  and so is the lookup',                 rawequal(byUser, byUser2), true)

local fresh = 0
for i = 1, #rows2 do if not pool[rows2[i]] then fresh = fresh + 1 end end
check('  and a push builds no new rows at all', fresh, 0)

-- ==========================================================================
-- 3. and it is still right
-- ==========================================================================
-- A reused row that keeps yesterday's kill count is the bug this trades
-- against, so every field that moves is checked after it moved.
m.players[2].kills = 9
m.players[2].score = 9
m.players[1].alive = false
local rows3, byUser3 = M.rows(m)
check('a kill that landed shows up in the reused row', byUser3[2].kills, 9)
check('  and it overtakes on the board',               rows3[1].name, 'BRAVO')
check('a player who died is not counted alive',        select(3, M.rows(m)), 1)

-- A player who leaves keeps their row (the server marks them disconnected
-- rather than dropping them), but a match that genuinely shrinks must not
-- leave a ghost on the end of the list.
m.players[4].connected = false
m.players[4].alive = false
local rows4 = M.rows(m)
check('someone who disconnected is still listed', #rows4, 4)
check('  shown as gone',
      (function() for i = 1, #rows4 do
         if rows4[i].name == 'DELTA' then return rows4[i].connected end
       end end)(), false)

m.players[4] = nil
local rows5 = M.rows(m)
check('a player taken off the match leaves no ghost row', #rows5, 3)
check('  and nothing of theirs is left on the end', rows5[4], nil)

-- ==========================================================================
-- 4. the team name is worked out once, not every push
-- ==========================================================================
-- teamNameFor walks the roster and builds a table to do it. The membership
-- cannot change once the match is running, so the answer cannot either.
local seen = 0
local realPairs = pairs
ENV.pairs = function(t)
  if t == m.players then seen = seen + 1 end
  return realPairs(t)
end

m.teamNames = nil
local nameA = M.teamName(m, 1)
local firstWalk = seen
M.teamName(m, 1); M.teamName(m, 1); M.teamName(m, 1)
ENV.pairs = realPairs

check('the team is named after its best ranked player', nameA, "ALPHA'S TEAM")
check('  and working it out walks the roster once',     firstWalk, 1)
check('  no matter how many times it is asked',         seen, firstWalk)

-- Someone joining is the one thing that can change it, and that throws the
-- answer away.
m.players[5] = player('ECHO', 1, 9, 0)
m.teamNames = nil
check('a new player can take the name over', M.teamName(m, 1), "ECHO'S TEAM")

-- A single player on a side reads as just their name, which is what makes a
-- 1v1 show two names facing each other.
local solo = { id = 'M2', players = { [1] = player('ALPHA', 1, 5, 0) } }
check('one player on a side is just their name', M.teamName(solo, 1), 'ALPHA')

print()
print(fails > 0 and ('%d FAILED of %d'):format(fails, checks)
                or ('ALL PASS (%d checks)'):format(checks))
os.exit(fails > 0 and 1 or 0)
