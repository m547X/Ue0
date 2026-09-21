-- The ten made-up players, checked against the ranks they claim to be.
--
--   lua5.4 tests/board_demo_sql.lua
--
-- m5_rankedpvp_board_demo.sql writes rank_id and division straight into the
-- database, which means it carries a copy of Config.Ranks written out as a SQL
-- CASE. Two copies of the same thresholds is exactly the kind of pair that
-- drifts apart quietly: the file keeps working, the badges just go wrong.
--
-- So this reads the real Config.Ranks and the real SQL, works out what each
-- seeded player's rank would be from the config, and checks the CASE agrees.
-- It also checks the three INSERTs are talking about the same ten players and
-- that the cleanup at the bottom covers all of them.

local SQL = io.open('M5_RankedPvP/m5_rankedpvp_board_demo.sql'):read('a')

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
-- the config, as the resource reads it
-- ==========================================================================
local Config
do
  local env = {
    Config = {},
    vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
    vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
  }
  setmetatable(env, { __index = _G })
  local src = io.open('M5_RankedPvP/الاعدادات/Config_Server.lua'):read('a')
  assert(load(src, 'cfg', 't', env))()
  Config = env.Config
end
assert(Config.Ranks and #Config.Ranks > 0, 'Config.Ranks did not load')

--- The rank the resource would put a player on for this many RP: the highest
--- one they have paid for. Unranked (id 0) is not something you climb into.
local function rankFromConfig(rp)
  local best
  for i = 1, #Config.Ranks do
    local r = Config.Ranks[i]
    if r.id ~= 0 and rp >= r.rpRequired then
      if not best or r.rpRequired >= best.rpRequired then best = r end
    end
  end
  return best
end

-- ==========================================================================
-- the SQL, read the way MySQL would read it
-- ==========================================================================
--- Pull the nth `CASE WHEN ... END` out of the file and turn it into a
--- function of rp, branch order kept, because that is what decides the answer.
local function caseAt(n)
  local seen, body = 0, nil
  for block in SQL:gmatch('CASE(.-)END') do
    seen = seen + 1
    if seen == n then body = block break end
  end
  assert(body, 'no CASE number ' .. n .. ' in the file')

  local branches = {}
  for at, value in body:gmatch('WHEN%s+f%.`rp`%s*>=%s*(%d+)%s+THEN%s+(%d+)') do
    branches[#branches + 1] = { at = tonumber(at), value = tonumber(value) }
  end
  local fallback = tonumber(body:match('ELSE%s+(%d+)'))
  assert(#branches > 0 and fallback, 'CASE ' .. n .. ' did not parse')

  return function(rp)
    for i = 1, #branches do
      if rp >= branches[i].at then return branches[i].value end
    end
    return fallback
  end
end

local sqlRankId  = caseAt(1)
local sqlDivision = caseAt(2)
local sqlHighest  = caseAt(3)

--- The ten players the file seeds, as (user_id, rp).
local seeded = {}
for id, rp in SQL:gmatch('SELECT%s+(%d%d%d%d%d%d)[^,]*,%s*(%d+)') do
  seeded[#seeded + 1] = { id = tonumber(id), rp = tonumber(rp) }
end

check('the file seeds ten players', #seeded, 10)

-- ==========================================================================
-- 1. every branch of the CASE agrees with the config
-- ==========================================================================
-- Not just the ten values that happen to be in the file: every RP from nothing
-- to past the top rank, so editing an rp in the file cannot land on a wrong
-- badge either.
local wrongRank, wrongDiv, firstWrong = 0, 0, nil
for rp = 0, 3000, 10 do
  local want = rankFromConfig(rp)
  if sqlRankId(rp) ~= want.id then
    wrongRank = wrongRank + 1
    firstWrong = firstWrong or ('%d RP: sql says %d, config says %d (%s)')
      :format(rp, sqlRankId(rp), want.id, want.name)
  end
  if sqlDivision(rp) ~= want.division then wrongDiv = wrongDiv + 1 end
end
check('the SQL puts every RP on the rank the config would', wrongRank, 0)
if firstWrong then print('       first disagreement — ' .. firstWrong) end
check('  and on the right division inside it',              wrongDiv, 0)

-- highest_rank_id is written from the same thresholds, so it has to be the
-- same expression — a player's best rank cannot be below their current one.
local sameAsRank = true
for rp = 0, 3000, 10 do
  if sqlHighest(rp) ~= sqlRankId(rp) then sameAsRank = false break end
end
check('the best-ever rank is written as the current one', sameAsRank, true)

-- ==========================================================================
-- 2. the ten players land where the file says they do
-- ==========================================================================
local tiers = {}
for i = 1, #seeded do
  local r = rankFromConfig(seeded[i].rp)
  tiers[#tiers + 1] = r.name
end
print()
print('--- what the board will show ---')
for i = 1, #seeded do
  print(('  %2d. %-8d %5d RP   %s'):format(i, seeded[i].id, seeded[i].rp, tiers[i]))
end
print()

check('the top of the board is the top rank', tiers[1], Config.Ranks[#Config.Ranks].name)
check('they are listed highest RP first', (function()
  for i = 2, #seeded do
    if seeded[i].rp >= seeded[i - 1].rp then return false end
  end
  return true
end)(), true)

-- The point of ten of them is that the board shows its whole range: podium
-- medals at the top, ordinary rows below, and enough different colours to see
-- that the rank tinting works at all.
local distinct = {}
local n = 0
for i = 1, #seeded do
  local tier = rankFromConfig(seeded[i].rp).tier
  if not distinct[tier] then distinct[tier] = true n = n + 1 end
end
check('they are spread over enough ranks to see the colours', n >= 5, true)

-- ==========================================================================
-- 3. the three inserts and the cleanup are about the same ten people
-- ==========================================================================
local function idsIn(fromPattern)
  local at = SQL:find(fromPattern)
  assert(at, 'could not find ' .. fromPattern)
  local stop = SQL:find('ON DUPLICATE KEY UPDATE', at, true) or #SQL
  local out = {}
  for id in SQL:sub(at, stop):gmatch('(9000%d%d)') do out[tonumber(id)] = true end
  return out
end

local inPlayers = idsIn('INSERT INTO `m5_players`')
local inRanks   = idsIn('INSERT INTO `m5_player_ranks`')
local inStats   = idsIn('INSERT INTO `m5_player_stats`')

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
check('ten rows go into the player table', count(inPlayers), 10)
check('ten rows go onto the ladder',        count(inRanks),   10)
check('ten rows of statistics',             count(inStats),   10)

local matched = true
for id in pairs(inPlayers) do
  if not inRanks[id] or not inStats[id] then matched = false break end
end
check('and it is the same ten in all three', matched, true)

-- A player on the ladder with no row in m5_players shows as "Unknown" on the
-- board, which is the one way this file could half-work.
local orphan = false
for id in pairs(inRanks) do if not inPlayers[id] then orphan = true break end end
check('nobody is on the ladder without a name', orphan, false)

-- The cleanup has to reach all of them, or the server opens with invented
-- players still on the board.
local lo, hi = SQL:match('DELETE FROM `m5_players`%s+WHERE `user_id` BETWEEN (%d+) AND (%d+)')
check('the cleanup names a range', lo ~= nil, true)
local covered = true
for id in pairs(inPlayers) do
  if id < tonumber(lo) or id > tonumber(hi) then covered = false break end
end
check('  that covers every one of them', covered, true)

local deletes = 0
for _ in SQL:gmatch('DELETE FROM `m5_[%w_]+`') do deletes = deletes + 1 end
check('  from all three tables', deletes, 3)

-- ==========================================================================
-- 4. the podium peds are real models
-- ==========================================================================
-- Each ped_model in the file has the model name next to it in a comment. The
-- number is that name hashed, and a number that is not stops the top three
-- wearing what the file says they wear — they quietly fall back instead.
local function joaat(s)
  local h = 0
  for i = 1, #s do
    h = (h + s:byte(i)) & 0xFFFFFFFF
    h = (h + (h << 10)) & 0xFFFFFFFF
    h = h ~ (h >> 6)
  end
  h = (h + (h << 3)) & 0xFFFFFFFF
  h = h ~ (h >> 11)
  return (h + (h << 15)) & 0xFFFFFFFF
end

local pedRows, pedBad = 0, nil
for num, name in SQL:gmatch('(%d+)%),?%s*%-%-%s*([%w_]+)\n') do
  local hash = tonumber(num)
  if hash and hash > 1000 then
    pedRows = pedRows + 1
    if joaat(name) ~= hash then
      pedBad = pedBad or ('%s should be %d, file says %d'):format(name, joaat(name), hash)
    end
  end
end
check('every podium ped is named next to its number', pedRows, 10)
check('  and the number is that name hashed', pedBad, nil)

print()
print(fails > 0 and ('%d FAILED of %d'):format(fails, checks)
                or ('ALL PASS (%d checks)'):format(checks))
os.exit(fails > 0 and 1 or 0)
