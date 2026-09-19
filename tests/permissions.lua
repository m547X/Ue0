-- The master key, and the ordinary keys.
--
--   lua5.4 tests/permissions.lua
--
-- `pvp.all` is documented as "this person can do everything". It was only
-- wired into the admin panel's own check, so the board editor — which asks
-- hasPerm directly — turned the owner away from a tool the config said they
-- had. Anything checked with hasPerm has to honour the master key, or the
-- config is lying.
--
-- The real hasPerm is sliced out of Server.lua and asked.

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
-- a vRP that answers from a table, and counts how often it is asked
-- ==========================================================================
local GRANTS, ASKS = {}, 0

local ENV = setmetatable({}, { __index = _G })
ENV.Config = {
  Permissions = {
    superAdmin     = 'pvp.all',
    adminGrantsAll = true,
    admin          = 'pvp.admin',
    moderator      = 'pvp.moderator',
    openMenu       = 'pvp.menu',
    spectate       = 'pvp.spectate',
    viewMMR        = 'pvp.mmr',
    editBoard      = 'pvp.board',
    manageBans     = 'pvp.bans'
  }
}
ENV.vRP = { hasPermission = function(a)
  ASKS = ASKS + 1
  local who, perm = a[1], a[2]
  return (GRANTS[who] or {})[perm] == true
end }

local CLOCK = 0
ENV.ms = function() return CLOCK end
ENV.Perf = { vrp = { calls = 0, wall = 0 } }

local M
do
  local a = SV:find('local PERM_TTL', 1, true)
  local b = SV:find('local function playerName', a, true)
  assert(a and b, 'could not slice the permission check')
  local chunk = SV:sub(a, b - 1) .. '\nreturn { has = hasPerm, all = permAll, forget = forgetPerms }'
  M = assert(load(chunk, 'perm', 't', ENV))()
end

local P = ENV.Config.Permissions
local function reset() M.forget(); ASKS = 0 end

-- ==========================================================================
-- 1. an ordinary staff member has exactly what they were given
-- ==========================================================================
GRANTS = { [7] = { ['pvp.bans'] = true } }
reset()
check('a permission that was granted passes', M.has(7, P.manageBans), true)
check('  one that was not does not',          M.has(7, P.editBoard), false)
check('  and they are not treated as staff',  M.all(7), false)

-- ==========================================================================
-- 2. pvp.all is a master key, not one more permission in the list
-- ==========================================================================
GRANTS = { [1] = { ['pvp.all'] = true } }
reset()
check('the master key opens the board editor', M.has(1, P.editBoard), true)
check('  the admin panel',                     M.has(1, P.manageBans), true)
check('  the menu',                            M.has(1, P.openMenu), true)
check('  spectating',                          M.has(1, P.spectate), true)
check('  the hidden MMR',                      M.has(1, P.viewMMR), true)
check('  and something nobody ever named',     M.has(1, 'pvp.made.up.later'), true)
check('  it counts as full staff',             M.all(1), true)

-- it must not claim they literally hold the admin or moderator role, or the
-- panel would read the owner as a moderator and lock half of it
check('but it does not forge the admin role',     M.has(1, P.admin), false)
check('  nor the moderator role',                 M.has(1, P.moderator), false)
check('  nor answer yes to being itself by luck', M.has(1, P.superAdmin), true)

-- ==========================================================================
-- 3. the admin role does the same while adminGrantsAll is on
-- ==========================================================================
GRANTS = { [2] = { ['pvp.admin'] = true } }
reset()
check('an admin gets the board editor too', M.has(2, P.editBoard), true)
check('  and counts as full staff',         M.all(2), true)

ENV.Config.Permissions.adminGrantsAll = false
reset()
check('turning that off puts them back on their own grants',
      M.has(2, P.editBoard), false)
check('  while the master key is unaffected',
      (function() GRANTS[2] = { ['pvp.all'] = true }; reset()
         return M.has(2, P.editBoard) end)(), true)
ENV.Config.Permissions.adminGrantsAll = true

-- ==========================================================================
-- 4. asking vRP is the expensive part, so it is asked once
-- ==========================================================================
GRANTS = { [3] = { ['pvp.bans'] = true } }
reset()
for _ = 1, 50 do M.has(3, P.manageBans) end
check('fifty checks are not fifty calls into vRP', ASKS <= 3, true)

local before = ASKS
M.forget(3)
M.has(3, P.manageBans)
check('  but forgetting a player asks again', ASKS > before, true)

-- a permission that was given after the answer was cached is picked up once
-- the cache expires, so a staff promotion does not need a reconnect
CLOCK = CLOCK + 600000
GRANTS[3]['pvp.board'] = true
check('a permission granted later is seen after the cache ages out',
      M.has(3, P.editBoard), true)

print(fails > 0 and ('\n%d FAILED of %d'):format(fails, checks)
                or ('\nALL PASS (%d checks)'):format(checks))
os.exit(fails > 0 and 1 or 0)
