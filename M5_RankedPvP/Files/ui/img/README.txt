Artwork folder — every file here is optional.

  Map previews   Config.Maps[].image = 'harbor'   ->  harbor.png
  Store cards    Config.Store.cards[].image
  Weapon renders Config.HUD.weapon.images['WEAPON_PISTOL_MK2']
  Decorations    Config.Store.avatars[].art = 'img/deco.png'

Three ways to name the same file, Files/ui/img/harbor.png:

    'harbor'            a bare name, the short form for a .png
    'harbor.png'        a file name, and how you point at a .jpg or a .webp
    'img/harbor.png'    written out

A value containing a slash or a scheme (https://, nui://, data:) is used
exactly as written, so a full URL works anywhere a file does. Subfolders are
fine too — 'img/weapons/ak.png'.

`art` is the one field that reads a bare name as a drawing rather than a file:
'vines' is one of the built-in drawings, 'img/vines.png' is this folder. Give
an avatar decoration a picture and it is drawn around the portrait at its own
size and colours, so an animated PNG lifted from a decoration pack lands the
way it was made. Square artwork with a transparent middle works best — the
portrait shows through it. A frame's `art` is a corner spray, drawn once and
flipped into all four corners, so it only takes the built-in drawings.

Two folders are read by their name alone, with nothing to list anywhere:

  weapons/        weapons/WEAPON_CARBINERIFLE.png
                  Named after the weapon exactly as the game names it. Drop a
                  folder of them in and the weapon card and the kill feed show
                  them; a weapon with no file keeps its drawn silhouette.
                  Config.HUD.weapon.images still wins for any one weapon, so a
                  single odd name can be pointed somewhere else.

  patents/        patents/Gold/Gold_1.png     rank badges
                  patents/Radiant/Radiant.png a tier with no divisions
                  The folder and the file are the tier name in TitleCase, and
                  the number is the division. Or name the file yourself with
                  `img` on the rank in Config.Ranks, which wins and lets the
                  folders be called anything — that is how a set whose folders
                  do not match the tier names is used.

Both are asked about once and the answer kept, so a half-filled folder costs
nothing: a rank or a weapon with no picture keeps the shape that was always
drawn for it, and the badge is laid over that shape rather than replacing it.

Nothing here is required: a missing file falls back to the drawn placeholder,
so the map vote, the store and the weapon card all render without it.
