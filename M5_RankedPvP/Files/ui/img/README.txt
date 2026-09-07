Artwork folder — every file here is optional.

  Map previews   Config.Maps[].image = 'harbor'   ->  harbor.png
  Store cards    Config.Store.cards[].image
  Weapon renders Config.HUD.weapon.images['WEAPON_PISTOL_MK2']
  Decorations    Config.Store.frames[].art = 'img/deco.png'

A bare name resolves to img/<name>.png. A value containing a slash or a
scheme (https://, nui://) is used exactly as written.

A frame's `art` is the one field that reads a bare name as a drawing rather
than a file: 'vines' is one of the built-in drawings, 'img/vines.png' is this
folder. Give it a picture and it is drawn around the portrait at its own
size and colours, so an animated PNG lifted from a decoration pack lands the
way it was made. Square artwork with a transparent middle works best — the
portrait shows through it.

Nothing here is required: a missing file falls back to the drawn placeholder,
so the map vote, the store and the weapon card all render without it.
