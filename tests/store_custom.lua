-- The custom card and the custom portrait: the staff open the slot, the player
-- fills it in.
--
--   lua5.4 tests/store_custom.lua
--
-- Three things are worth pinning down. That the slot is really that one
-- player's, and appears in their store owned and equippable without leaking
-- into anyone else's list. That a player cannot set a picture in a slot nobody
-- opened for them — the address arrives over the network from the interface,
-- so being unlocked is checked on the server, not in the page. And the address
-- itself, which ends up inside a CSS url(): anything that is not a plain
-- http(s) link or a file under ui/img is refused before it is stored.
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
-- a database and a config to run the real Store against
-- ==========================================================================
local ROWS, WRITES = {}, {}

local ENV = setmetatable({}, { __index = _G })

ENV.Config = {
  Store = {
    enabled = true,
    currency = { label = 'COINS', starting = 0, max = 1000 },
    rarities = {
      common    = { label = 'COMMON', color = '#8B93A3' },
      legendary = { label = 'LEGENDARY', color = '#F5C542' }
    },
    custom = { name = 'CUSTOM', rarity = 'legendary', cooldown = 0, playerNames = true },
    cards = {
      { id = 'default', name = 'Default', rarity = 'common', price = 0, image = '', default = true },
      { id = 'thorn',   name = 'Thorn',   rarity = 'common', price = 200, image = 'https://x/t.png' }
    },
    titles = {}, effects = {}, frames = {}, avatars = {},
    portraits = { { id = 'default', name = 'Default', rarity = 'common', price = 0, default = true } }
  },
  Avatars = { enabled = true, default = 'https://cdn/default.png', source = 'none' }
}

ENV.DB = {
  single = function() return { coins = 500 } end,
  insert = function() end,
  query  = function(sql, args)
    if sql:find('m5_player_items', 1, true) then return {} end
    if sql:find('m5_player_custom', 1, true) then
      return ROWS[args[1]] or {}
    end
    return {}
  end,
  write = function(sql, args) WRITES[#WRITES + 1] = { sql = sql, args = args } end
}

ENV.log = function() end
ENV.dbg = function() end
local CLOCK = 1000
ENV.now = function() return CLOCK end
ENV._Lf = function(fmt, ...) return string.format(fmt, ...) end
ENV.Players = {}
ENV.clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
-- the picture the player already had, which the default portrait tile previews
ENV.avatarFor = function(_, plain) return plain and 'https://cdn/discord.png' or 'x' end

do
  local a = SV:find('Store = { cache = {} }', 1, true)
  local b = SV:find('Rewards = {}', a, true)
  assert(a and b, 'could not slice the store')
  assert(load(SV:sub(a, b - 1), 'store', 't', ENV))()
end
local Store = ENV.Store

-- ==========================================================================
-- 1. the image address, which came out of a text box
-- ==========================================================================
local ok, why = Store.imageAllowed('https://cdn.example.com/a.png')
check('an https link is accepted', ok, 'https://cdn.example.com/a.png')
check('  and http too', (Store.imageAllowed('http://example.com/a.png')), 'http://example.com/a.png')
check('  a file under ui/img is a name, not a link',
      (Store.imageAllowed('img/mine.png')), 'img/mine.png')
check('  and a bare name is one as well', (Store.imageAllowed('mine')), 'mine')
check('  surrounding spaces are trimmed off',
      (Store.imageAllowed('  https://x/a.png  ')), 'https://x/a.png')

check('a script url is refused', (Store.imageAllowed('javascript:alert(1)')), nil)
check('  a data url is refused',  (Store.imageAllowed('data:image/png;base64,AAA')), nil)
check('  a file url is refused',  (Store.imageAllowed('file:///etc/passwd')), nil)
check('  climbing out of the folder is refused',
      (Store.imageAllowed('../../secret.png')), nil)
check('  an absolute path is refused', (Store.imageAllowed('/etc/passwd')), nil)
check('  nothing at all is refused',  (Store.imageAllowed('')), nil)
check('  and so is a run of text with spaces in it',
      (Store.imageAllowed('https://x/a.png onerror=x')), nil)
ok, why = Store.imageAllowed(('https://x/' .. string.rep('a', 600)))
check('  an address too long to store is refused', ok, nil)
check('  and says why',                            type(why), 'string')

-- ==========================================================================
-- 2. granting one, and what the player's store then looks like
-- ==========================================================================
local ME, YOU = 7, 8

check('before anything is granted the card list is the config one',
      #Store.payload(ME).cards, 2)
check('  and the portrait list is just the default', #Store.payload(ME).portraits, 1)
check('  which previews the picture the player already has',
      Store.payload(ME).portraits[1].image, 'https://cdn/discord.png')

-- a player nobody unlocked cannot set one, however well formed the address is
check('a player with no slot cannot set a picture',
      select(2, Store.setCustom(ME, 'card', 'https://cdn/mine.gif')),
      'You do not have a custom slot for that.')

ok, why = Store.allowCustom(ME, 'card')
check('the staff can open a card slot', ok, true)
check('  which is written to the database',
      WRITES[#WRITES].sql:find('m5_player_custom', 1, true) ~= nil, true)
check('  the store tells the interface the slot is open',
      Store.payload(ME).customAllowed.card, true)
check('  but an empty slot puts nothing in the list', #Store.payload(ME).cards, 2)
check('  and the portrait slot is still shut',
      Store.payload(ME).customAllowed.portrait, nil)

ok = Store.setCustom(ME, 'card', 'https://cdn/mine.gif', 'M547')
check('the player fills it in themselves', ok, true)

local mine = Store.payload(ME)
check('the card now appears in that player\'s store', #mine.cards, 3)

local custom
for i = 1, #mine.cards do if mine.cards[i].id == 'custom' then custom = mine.cards[i] end end
check('  it is there by name',        custom ~= nil, true)
check('  already owned',              custom.owned, true)
check('  costing nothing',            custom.price, 0)
check('  marked as a gift',           custom.custom, true)
check('  carrying the picture',       custom.image, 'https://cdn/mine.gif')
check('  and the name the staff gave it', custom.name, 'M547')

check('nobody else gets it', #Store.payload(YOU).cards, 2)

-- a slot opened with a picture already in it, for a staff member who wants to
-- set one rather than leave the choice
Store.allowCustom(YOU, 'card', 'https://cdn/yours.png')
local yours = Store.payload(YOU)
for i = 1, #yours.cards do
  if yours.cards[i].id == 'custom' then
    check('a picture with no name uses the configured word', yours.cards[i].name, 'CUSTOM')
  end
end

-- ==========================================================================
-- 3. wearing it
-- ==========================================================================
ok = Store.equip(ME, 'card', 'custom')
check('the player can equip it', ok, true)
check('  and it is what their card image now is',
      Store.cosmetics(ME).cardImage, 'https://cdn/mine.gif')
check('  the store shows it as worn', (function()
  local p = Store.payload(ME)
  for i = 1, #p.cards do if p.cards[i].id == 'custom' then return p.cards[i].equipped end end
  return nil
end)(), true)

check('buying something they already own is refused',
      select(2, Store.buy(ME, 'card', 'custom')), 'You already own that.')
check('and a player with no grant cannot equip one',
      select(2, Store.equip(9, 'card', 'custom')), 'Unknown item.')

-- ==========================================================================
-- 4. a portrait is a picture of the player, not a card
-- ==========================================================================
Store.allowCustom(ME, 'portrait')
ok = Store.setCustom(ME, 'portrait', 'img/face.png', 'MY FACE')
check('a portrait slot works the same way', ok, true)
local pp = Store.payload(ME)
check('  and joins the portrait list', #pp.portraits, 2)
check('  without touching the cards',  #pp.cards, 3)

check('equipping it is allowed', Store.equip(ME, 'portrait', 'custom'), true)
check('  and the server hands that picture out for the player',
      Store.customImage(ME, 'portrait'), 'img/face.png')

-- ==========================================================================
-- 5. taking it back
-- ==========================================================================
-- the player can empty their own slot without losing it
ok = Store.clearCustom(ME, 'card')
check('the player can clear their own picture', ok, true)
check('  the item leaves the list',   #Store.payload(ME).cards, 2)
check('  but the slot stays open',    Store.payload(ME).customAllowed.card, true)
check('  and they are back on the default card',
      Store.cosmetics(ME).cardImage, '')
Store.setCustom(ME, 'card', 'https://cdn/again.png')
check('  and they can put another one in', #Store.payload(ME).cards, 3)

ok = Store.denyCustom(ME, 'card')
check('the staff can close the slot', ok, true)
check('  it leaves the store',        #Store.payload(ME).cards, 2)
check('  the slot is gone with it',   Store.payload(ME).customAllowed.card, nil)
check('  and the portrait slot is left alone',
      Store.payload(ME).customAllowed.portrait, true)
check('  the player is put back on the default card',
      Store.cosmetics(ME).cardImage, '')
check('  and they cannot set one any more',
      select(2, Store.setCustom(ME, 'card', 'https://cdn/sneak.png')),
      'You do not have a custom slot for that.')
check('  closing one that was never open says so',
      select(2, Store.denyCustom(ME, 'card')),
      'That player does not have that unlocked.')

-- the portrait slot was a separate grant and is untouched by any of that
Store.allowCustom(ME, 'portrait')
Store.setCustom(ME, 'portrait', 'img/face.png')
check('the portrait slot is independent of the card one',
      #Store.payload(ME).portraits, 2)

check('a kind that is not customisable is refused',
      select(2, Store.allowCustom(ME, 'title', 'https://x/a.png')), 'Unknown item.')
check('  and cannot be set by a player either',
      select(2, Store.setCustom(ME, 'title', 'https://x/a.png')), 'Unknown item.')

-- ==========================================================================
-- 6. the address a player sends is checked as hard as the staff's
-- ==========================================================================
check('a player cannot slip a script url through',
      select(2, Store.setCustom(ME, 'portrait', 'javascript:alert(1)')) ~= nil, true)
check('  nor a data url',
      select(2, Store.setCustom(ME, 'portrait', 'data:image/png;base64,AAA')) ~= nil, true)
check('  nor climb out of the image folder',
      select(2, Store.setCustom(ME, 'portrait', '../../secret.png')) ~= nil, true)
check('  and the picture they had is still the one in place',
      Store.customImage(ME, 'portrait'), 'img/face.png')

-- and they cannot change it as fast as they like
ENV.Config.Store.custom.cooldown = 30
Store.customSetAt[ME] = CLOCK
check('a change too soon after the last one is refused',
      select(2, Store.setCustom(ME, 'portrait', 'https://cdn/spam.png')) ~= nil, true)
CLOCK = CLOCK + 31
check('  and allowed once the wait is over',
      Store.setCustom(ME, 'portrait', 'https://cdn/later.png'), true)
ENV.Config.Store.custom.cooldown = 0

print(fails > 0 and ('\n%d FAILED of %d'):format(fails, checks)
                or ('\nALL PASS (%d checks)'):format(checks))
os.exit(fails > 0 and 1 or 0)
