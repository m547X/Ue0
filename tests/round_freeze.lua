-- Who can move, and when.
--
--   lua5.4 tests/round_freeze.lua
--
-- A round that has already been decided is not a round any more, so nobody
-- should be running or shooting through the break. The freeze is easy to get
-- wrong in the other direction though — a player left frozen with nothing
-- coming to release them is stuck for the rest of the match — so the real
-- round handler is sliced out of Client.lua and driven through a whole match's
-- worth of phases against stubbed natives, checking both ends of it.
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
-- the world
-- ==========================================================================
local P = { frozen = false, firing = true, driveBy = true, health = 200, armour = 0 }
local ENV = setmetatable({}, { __index = _G })

ENV.State = {
  matchId = 'm1', team = 1, alive = true, roundLive = false, frozen = false,
  reportedDeath = false, spawnProtectUntil = 0, lastHealth = 200, lastArmor = 0,
  settings = {}, spectating = false
}
ENV.Config = { Effects = { countdownEffect = 'fx' } }

local NUI = {}
ENV.nui  = function(msg) NUI[#NUI + 1] = msg end
ENV.hook = function() end
ENV.clearBoundary = function() end
ENV.stopSpectate  = function() end
ENV.screenEffect  = function() end
ENV.applyLoadout  = function() end
ENV.ms = function() return 1000 end
ENV.playerPed = function() return 1 end
ENV.PlayerId  = function() return 0 end

ENV.teleport = function(_, freeze)
  if freeze then P.frozen = true; ENV.State.frozen = true end
end

ENV.FreezeEntityPosition   = function(_, v) P.frozen  = v == true end
ENV.DisablePlayerFiring    = function(_, v) P.firing  = v ~= true end
ENV.SetPlayerCanDoDriveBy  = function(_, v) P.driveBy = v == true end
ENV.GetEntityHealth        = function() return P.health end
ENV.GetPedArmour           = function() return P.armour end
ENV.SetEntityHealth        = function(_, v) P.health = v end
ENV.SetEntityMaxHealth     = function(_, v) P.maxHealth = v end
ENV.SetPedArmour           = function(_, v) P.armour = v end
ENV.ClearPedBloodDamage    = function() P.bloodCleared = true end
ENV.IsPedRagdoll           = function() return false end
ENV.IsPedFalling           = function() return false end
ENV.IsPedDeadOrDying       = function() return false end
ENV.ClearPedTasksImmediately = function() end
ENV.SetPedCanRagdoll       = function() end

ENV.RegisterNetEvent = function(_, fn) ENV.__round = fn end

do
  local a = CL:find("RegisterNetEvent('m5rp:cl:round', function(data)", 1, true)
  local b = CL:find("RegisterNetEvent('m5rp:cl:hud'", a, true)
  assert(a and b, 'could not slice the round handler')
  assert(load(CL:sub(a, b - 1), 'round', 't', ENV))()
end
assert(ENV.__round, 'the round event never registered')

local function send(data)
  data.matchId = data.matchId or 'm1'
  ENV.__round(data)
end
-- what the player can do right now: the flags the match thread would also be
-- holding down every frame while State.frozen is set
local function canMove() return not P.frozen and not ENV.State.frozen end
local function canShoot() return P.firing and not ENV.State.frozen end

-- ==========================================================================
-- 1. a round that has been won is over for everyone on the map
-- ==========================================================================
send({ phase = 'spawn', spawn = {}, freeze = true, protection = 3 })
send({ phase = 'countdown', round = 1, seconds = 3 })
send({ phase = 'live', round = 1, time = 120 })

check('the round goes live and the player is let go', canMove(), true)
check('  and can shoot',                              canShoot(), true)

send({ phase = 'end', round = 1, winner = 1, scores = { a = 1, b = 0 } })
check('the round is won: the player is frozen', canMove(), false)
check('  and cannot shoot',                     canShoot(), false)
check('  no drive-by either',                   P.driveBy, false)
check('  the round is no longer live',          ENV.State.roundLive, false)
check('  and the result still reaches the interface',
      (function()
        for i = #NUI, 1, -1 do
          if NUI[i].action == 'round' and NUI[i].data.phase == 'end' then return true end
        end
        return false
      end)(), true)

-- losing it freezes just the same — the round is over either way
send({ phase = 'live', round = 2, time = 120 })
send({ phase = 'end', round = 2, winner = 2, scores = { a = 1, b = 1 } })
check('losing a round freezes too', canMove(), false)

-- ==========================================================================
-- 2. and the freeze is always lifted again
-- ==========================================================================
send({ phase = 'spawn', spawn = {}, freeze = true, protection = 3 })
check('the next round spawns you still frozen', canMove(), false)
send({ phase = 'countdown', round = 3, seconds = 3 })
check('  the countdown keeps you there',        canMove(), false)
send({ phase = 'live', round = 3, time = 120 })
check('  and going live releases you',          canMove(), true)
check('  with your weapon back',                canShoot(), true)
check('  and drive-by allowed again',           P.driveBy, true)

-- a respawn inside a live round must never leave the player standing still:
-- it arrives with no freeze flag at all
send({ phase = 'end', round = 3, winner = 1, scores = { a = 2, b = 1 } })
send({ phase = 'respawn', spawn = {}, protection = 3 })
check('a respawn in a live round is not frozen', canMove(), true)
check('  and can shoot straight away',           canShoot(), true)

-- the whole cycle again, twice, to be sure nothing latches
for round = 4, 6 do
  send({ phase = 'end', round = round, winner = 1, scores = { a = round, b = 1 } })
  send({ phase = 'spawn', spawn = {}, freeze = true, protection = 3 })
  send({ phase = 'countdown', round = round + 1, seconds = 3 })
  send({ phase = 'live', round = round + 1, time = 120 })
end
check('after three more rounds the player still moves', canMove(), true)
check('  and still shoots',                             canShoot(), true)

-- ==========================================================================
-- 3. the phases that are not about movement leave it alone
-- ==========================================================================
send({ phase = 'end', round = 7, winner = 1, scores = { a = 5, b = 1 } })
send({ phase = 'loadout', gunLevel = 2 })
check('a loadout change does not unfreeze the break', canMove(), false)
send({ phase = 'rearm' })
check('nor does a rearm',                             canMove(), false)
send({ phase = 'revive', health = 100 })
check('nor a revive',                                 canMove(), false)
send({ phase = 'live', round = 8, time = 120 })
check('and the next round still releases after them', canMove(), true)

-- ==========================================================================
-- 4. a message for a different match is not ours to act on
-- ==========================================================================
send({ phase = 'live', round = 8, time = 120 })
ENV.__round({ matchId = 'other', phase = 'end', round = 1, winner = 1 })
check('a round ending in another match does not freeze us', canMove(), true)

-- ==========================================================================
-- 5. a round starts at full health, whatever the countdown did to you
-- ==========================================================================
-- Between the spawn and the round going live the player is standing on a map
-- that may only just have streamed in, and a short drop onto it is a few
-- points of fall damage. Starting a round on 93 of 100 because the ground
-- arrived late is not a fight anybody agreed to.
ENV.State.loadout = { health = 100, armor = 50 }
ENV.State.settings = { health = 100, armor = 50 }

P.health, P.armour, P.bloodCleared = 193, 12, false
send({ phase = 'live', round = 2, time = 120 })
check('the round starts on full health', P.health, 200)
check('  and the armour it was given',   P.armour, 50)
check('  with the blood wiped off',      P.bloodCleared, true)

-- but it tops up, it does not hand out more than the loadout said
P.health, P.armour = 200, 50
send({ phase = 'live', round = 3, time = 120 })
check('a player already on full is left alone', P.health, 200)
check('  and so is their armour',               P.armour, 50)

-- and what the damage check compares against is reset with it, so the top-up
-- is not read as somebody having hit you for the difference
check('the damage watch starts from there too', ENV.State.lastHealth, 200)

print(fails > 0 and ('\n%d FAILED of %d'):format(fails, checks)
                or ('\nALL PASS (%d checks)'):format(checks))
os.exit(fails > 0 and 1 or 0)
