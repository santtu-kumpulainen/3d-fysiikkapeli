The full pack: Explosion FX has 15 effects: clusters, ground blasts, mushroom clouds,
implosions, fireworks, fireballs, rocket trails, burning ground and fuses on top of these, and
every effect in fire, red, blue, green, purple and white. Same sheets, same player.
https://heyheythere.itch.io/explosion-fx

sheets/256/    every effect at 256 px (muzzle flashes, fireballs, rockets and burning ground
               256x128, fires and smoke 128x256, fuses 128x128)
sheets/128/    the same at half size
sheets/pixel/  pixel-art versions, drawn at 64 px (scale them up with nearest filtering)
previews/      an animated GIF of each effect
sheets/effects.json  for each sheet: frame size per set, frame count, columns, fps, whether it
               loops, and the anchor (0..1 across and down the frame: the barrel of a muzzle
               flash, a fireball's head, a rocket's nozzle, the base of a fire, burning ground or
               smoke, where a ground blast or a mushroom cloud went off, the centre of the rest)

Each sheet is a grid of frames, left to right then top to bottom, 8 to a row, on a transparent
background (straight alpha). Fireballs, rockets, fires, burning ground, smoke and fuses loop
seamlessly; the rest play once. Muzzle flashes, fireballs and rockets point right: rotate them to
the shot.

Godot 4.3+
    Copy addons/explosion_fx/ into your project and sheets/ into addons/explosion_fx/, then
        ExplosionFX.spawn(self, "fire_explosion", enemy.global_position)
        ExplosionFX.spawn(self, "fire_muzzle", barrel.global_position, barrel.global_rotation)
        var flames := ExplosionFX.spawn(self, "fire_burn", spot)
        flames.finish()   # fades a loop out
    One-shots free themselves when done. ExplosionFX.default_set = "pixel" (or "128") switches
    every spawn to that set; set ExplosionFX.sheets_dir if sheets/ is elsewhere. Open
    addons/explosion_fx/demo/demo.tscn to try them all.

Unity
    Import a sheet, set Texture Type to Sprite (2D and UI), Sprite Mode to Multiple, then in the
    Sprite Editor: Slice > Grid By Cell Size with the frame size from effects.json. Select the
    sprites in order and drag them into the scene to make the animation; set its sample rate to
    the fps, and Loop Time to match "loop". For the pixel set: Filter Mode Point, no compression.

GameMaker
    Create Sprite > Import > the sheet, then Convert to Frames with the frame size, 8 frames per
    row and the frame count from effects.json. Set the sprite's speed to the fps and its origin
    to the anchor.

Anything else
    Any engine or framework that cuts a grid sheet: use the frame size and count from
    effects.json.
