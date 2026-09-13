-- An invite takes the cursor without opening the interface. Getting that wrong
-- in either direction is bad: no focus and the card cannot be clicked, focus
-- never released and the player is stuck holding a pointer in a firefight.
--
-- Run on the real focus helpers out of Client.lua.
--
--   lua5.4 tests/prompt_focus.lua
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

-- ------------------------------------------------------------------ engine
-- what the game was last told
local FOCUS, KEEP = nil, nil
function SetNuiFocus(a) FOCUS = a end
function SetNuiFocusKeepInput(a) KEEP = a end

State  = { menuOpen = false, promptFocus = false }
Config = { Prompt = { keepInput = true, sound = true } }

local setFocus, setPromptFocus, applyPromptFocus
do
  local a = CL:find('local function setFocus(on)', 1, true)
  local b = CL:find('local function openMenu(page)', a, true)
  assert(a and b, 'could not slice the focus helpers')
  setFocus, setPromptFocus, applyPromptFocus = assert(load(
    CL:sub(a, b - 1) ..
    '\nreturn setFocus, setPromptFocus, applyPromptFocus', 'focus'))()
end

-- ==========================================================================
-- 1. the invite takes the cursor without freezing the player
-- ==========================================================================
-- keepInput is the whole difference between a prompt and a menu: the card can
-- arrive mid-fight, so the player keeps moving and shooting.
setPromptFocus(true)
check('an invite turns the cursor on',   FOCUS, true)
check('  without taking the controls',   KEEP, true)
check('  and the state records it',      State.promptFocus, true)

setPromptFocus(false)
check('answering it gives the cursor back', FOCUS, false)
check('  and the controls with it',         KEEP, false)

-- a server that wants the old freezing behaviour says so
Config.Prompt.keepInput = false
setPromptFocus(true)
check('keepInput false does freeze the player', KEEP, false)
check('  and still shows the cursor',           FOCUS, true)
setPromptFocus(false)
Config.Prompt.keepInput = true

-- no Prompt config at all is the safe default, not a crash
Config.Prompt = nil
setPromptFocus(true)
check('no Prompt config keeps the controls', KEEP, true)
setPromptFocus(false)
Config.Prompt = { keepInput = true, sound = true }

-- ==========================================================================
-- 2. the menu and the card do not fight over the cursor
-- ==========================================================================
-- The menu owns the focus while it is open. An invite arriving behind it must
-- not quietly hand the controls back to the game underneath.
State.menuOpen = true
setFocus(true)
check('the open menu takes the controls', KEEP, false)

setPromptFocus(true)
check('an invite behind the open menu changes nothing', KEEP, false)
check('  and the cursor stays on',                      FOCUS, true)
check('  but it is remembered',                         State.promptFocus, true)

-- and when the menu closes, the card still wants a cursor
State.menuOpen = false
applyPromptFocus()
check('closing the menu leaves the cursor for the card', FOCUS, true)
check('  with the controls back',                        KEEP, true)

-- and once the card is answered, everything goes
setPromptFocus(false)
check('answering it finally releases the cursor', FOCUS, false)

-- the other order: no card, menu closes, nothing is held
State.menuOpen = true
setFocus(true)
State.menuOpen = false
setFocus(false)
applyPromptFocus()
check('a menu closing with no card holds nothing', FOCUS, false)
check('  and does not keep input on either',       KEEP, false)

-- ==========================================================================
-- 3. it is the client that releases it, not only the page
-- ==========================================================================
-- The interface posts back when the card is answered, but a page that reloads
-- or a resource that restarts never does. The client arms its own timer.
check('the client releases the cursor itself on a timer',
      CL:find('Citizen.SetTimeout', 1, true) ~= nil, true)
check('  keyed to the invite it belongs to',
      CL:find('if promptToken == mine then setPromptFocus(false) end', 1, true) ~= nil, true)
check('  and the page can release it early',
      CL:find("RegisterNUICallback('promptDone'", 1, true) ~= nil, true)

-- ==========================================================================
-- 4. an invite does not open the interface
-- ==========================================================================
-- This is what was asked for: the card, the cursor, and nothing else.
local handler = CL:match("RegisterNetEvent%('m5rp:cl:party'.-\nend%)")
assert(handler, 'could not find the party handler')
check('the invite handler never opens the menu',
      handler:find("action = 'open'", 1, true) ~= nil, false)
check('  and never claims the menu is open',
      handler:find('State.menuOpen = true', 1, true) ~= nil, false)
check('  it primes the page instead',
      handler:find("action = 'prime'", 1, true) ~= nil, true)
check('  and takes prompt focus',
      handler:find('setPromptFocus(true)', 1, true) ~= nil, true)

-- a match being found is the other case, and that one does still open it
local found = CL:match("RegisterNetEvent%('m5rp:cl:matchFound'.-\nend%)")
check('a found match still opens the interface',
      found and found:find("action = 'open'", 1, true) ~= nil, true)

print()
print(fails == 0 and ('ALL PASS (%d checks)'):format(checks)
                 or ('%d FAILED'):format(fails))
os.exit(fails == 0 and 0 or 1)
