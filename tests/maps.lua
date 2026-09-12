-- Every mode offered in the ranked queue has to have somewhere to play it.
-- A mode with no map is a button that searches forever, so this reads the real
-- config rather than a copy of it.
--
--   lua5.4 tests/maps.lua
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

-- the config is written for FiveM, so it needs the vector constructors
local env = { Config = {} }
env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
env.vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
setmetatable(env, { __index = _G })
assert(loadfile('M5_RankedPvP/الاعدادات/Config_Server.lua', 't', env))()
local Config = env.Config

local function has(list, v)
  for i = 1, #list do if list[i] == v then return true end end
  return false
end

-- ==========================================================================
-- 1. every queue mode is a real mode, and it is switched on
-- ==========================================================================
for _, mode in ipairs(Config.RankedQueueModes) do
  local cfg = Config.Modes[mode]
  check(('%s is a defined mode'):format(mode), cfg ~= nil, true)
  if cfg then
    check(('  %s is enabled'):format(mode), cfg.enabled, true)
  end
end

-- ==========================================================================
-- 2. and every one of them has at least one map
-- ==========================================================================
local mapsFor = {}
for _, map in ipairs(Config.Maps) do
  for _, mode in ipairs(map.modes or {}) do
    mapsFor[mode] = (mapsFor[mode] or 0) + 1
  end
end

for _, mode in ipairs(Config.RankedQueueModes) do
  check(('%s has a map to play on'):format(mode), (mapsFor[mode] or 0) > 0, true)
end

-- ==========================================================================
-- 3. the two big-team modes go wherever 5v5 goes
-- ==========================================================================
-- They are the same ten players on the same arena, so a map that can hold a
-- 5v5 can hold them, and one that cannot should not be offering them.
for _, map in ipairs(Config.Maps) do
  local five = has(map.modes, '5v5')
  for _, mode in ipairs({ 'tdm', 'snd' }) do
    if has(Config.RankedQueueModes, mode) then
      check(('%s: %s follows 5v5'):format(map.id, mode), has(map.modes, mode), five)
    end
  end
end

-- ==========================================================================
-- 4. a map has to be able to seat the biggest mode it offers
-- ==========================================================================
-- Spawn points wrap around, so a short list is not fatal — the extra players
-- stack on the same spot. That is survivable in a round mode and miserable in
-- one that respawns, so this reports rather than fails.
local thin = {}
for _, map in ipairs(Config.Maps) do
  local want = 0
  for _, mode in ipairs(map.modes or {}) do
    local cfg = Config.Modes[mode]
    if cfg and cfg.type ~= 'ffa' and cfg.teamSize > want then want = cfg.teamSize end
  end
  local a, b = #(map.teamA or {}), #(map.teamB or {})
  if a < want or b < want then
    thin[#thin + 1] = ('%s: %d/%d spawns for %d a side'):format(map.id, a, b, want)
  end
end

check('every map has a spawn point for both teams', (function()
  for _, map in ipairs(Config.Maps) do
    if #(map.teamA or {}) == 0 or #(map.teamB or {}) == 0 then return false end
  end
  return true
end)(), true)

if #thin > 0 then
  print()
  print(('note: %d maps spawn players on top of each other in their biggest mode')
        :format(#thin))
  for _, s in ipairs(thin) do print('  ' .. s) end
end

print()
print(fails == 0 and ('ALL PASS (%d checks)'):format(checks)
                 or ('%d FAILED'):format(fails))
os.exit(fails == 0 and 0 or 1)
