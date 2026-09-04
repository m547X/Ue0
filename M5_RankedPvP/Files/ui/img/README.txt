Artwork folder — every file here is optional.

  Map previews   Config.Maps[].image = 'harbor'   ->  harbor.png
  Store cards    Config.Store.cards[].image
  Weapon renders Config.HUD.weapon.images['WEAPON_PISTOL_MK2']

A bare name resolves to img/<name>.png. A value containing a slash or a
scheme (https://, nui://) is used exactly as written.

Nothing here is required: a missing file falls back to the drawn placeholder,
so the map vote, the store and the weapon card all render without it.
