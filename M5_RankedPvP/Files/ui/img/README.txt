Artwork folder — every file here is optional.

  Map previews   Config.Maps[].image = 'harbor'   ->  harbor.png
  Store cards    Config.Store.cards[].image
  Weapon renders Config.HUD.weapon.images['WEAPON_PISTOL_MK2']
  Decorations    Config.Store.avatars[].art = 'img/deco.png'

A bare name resolves to img/<name>.png. A value containing a slash or a
scheme (https://, nui://) is used exactly as written.

`art` is the one field that reads a bare name as a drawing rather than a file:
'vines' is one of the built-in drawings, 'img/vines.png' is this folder. Give
an avatar decoration a picture and it is drawn around the portrait at its own
size and colours, so an animated PNG lifted from a decoration pack lands the
way it was made. Square artwork with a transparent middle works best — the
portrait shows through it. A frame's `art` is a corner spray, drawn once and
flipped into all four corners, so it only takes the built-in drawings.

Nothing here is required: a missing file falls back to the drawn placeholder,
so the map vote, the store and the weapon card all render without it.
