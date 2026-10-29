class_name ExplosionFX
extends AnimatedSprite2D
## One Explosion FX sheet as an AnimatedSprite2D, read from sheets/effects.json.
##
##     ExplosionFX.spawn(self, "fire_explosion", enemy.global_position)          # plays once, frees itself
##     ExplosionFX.spawn(gun, "fire_muzzle", gun.global_position, gun.global_rotation)
##     var flames := ExplosionFX.spawn(self, "fire_burn", spot)                  # loops
##     flames.finish()                                                           # fades out and frees
##
## Loops (fireball, fire, burn, smoke) play until finish(); the rest free themselves. Muzzle
## flashes and fireballs point right at angle 0. The anchor in effects.json (the barrel, a
## fireball's head, the base of a fire or smoke, where a ground blast hit, the centre of the rest)
## sits on the node's position. `sheet_set` is "256", "128" or "pixel" (drawn with nearest
## filtering); ExplosionFX.default_set picks it for every spawn.

## Where sheets/ is: found in this folder, or at res://sheets/ as the zip has it. Set it if the
## sheets are elsewhere.
static var sheets_dir := ""
static var default_set := "256"
static var _data: Dictionary = {}
static var _frames: Dictionary = {}

var effect := ""
var sheet_set := ""


## The effect names in the installed sheets, e.g. "fire_explosion".
static func effects() -> PackedStringArray:
	return PackedStringArray(_effects().keys())


static func info(fx_name: String) -> Dictionary:
	return _effects()[fx_name]


## Adds `fx_name` to `parent` at the global position `at`, turned by `angle`, and plays it.
static func spawn(parent: Node, fx_name: String, at: Vector2, angle := 0.0, set_name := "") -> ExplosionFX:
	var fx := ExplosionFX.new()
	fx.setup(fx_name, set_name)
	parent.add_child(fx)
	fx.global_position = at
	fx.global_rotation = angle
	fx.play()
	return fx


## The effect's frames, made once per sheet set and shared.
static func frames_for(fx_name: String, set_name := "") -> SpriteFrames:
	set_name = set_name if set_name else default_set
	var key := set_name + "/" + fx_name
	if key in _frames:
		return _frames[key]
	var e: Dictionary = _effects()[fx_name]
	var sheet: Texture2D = load(sheets_dir.path_join(set_name).path_join(e.file))
	var cell := Vector2(e.cell[set_name][0], e.cell[set_name][1])
	var cols: int = e.columns
	var sf := SpriteFrames.new()
	sf.set_animation_loop(&"default", e.loop)
	sf.set_animation_speed(&"default", e.fps)
	for i in int(e.frames):
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(Vector2(i % cols, floorf(i / float(cols))) * cell, cell)
		sf.add_frame(&"default", atlas)
	_frames[key] = sf
	return sf


static func _effects() -> Dictionary:
	if _data.is_empty():
		if sheets_dir.is_empty():
			var here := "res://addons/explosion_fx/sheets/"
			sheets_dir = here if ResourceLoader.exists(here + "effects.json") else "res://sheets/"
		var json: JSON = load(sheets_dir.path_join("effects.json"))
		for e: Dictionary in json.data.effects:
			_data[e.name] = e
	return _data


func setup(fx_name: String, set_name := "") -> void:
	if fx_name not in _effects():
		push_error("ExplosionFX: no effect %s in %s" % [fx_name, sheets_dir])
		return
	effect = fx_name
	sheet_set = set_name if set_name else default_set
	sprite_frames = frames_for(fx_name, sheet_set)
	var e: Dictionary = _effects()[fx_name]
	var cell := Vector2(e.cell[sheet_set][0], e.cell[sheet_set][1])
	centered = true
	offset = (Vector2(0.5, 0.5) - Vector2(e.anchor[0], e.anchor[1])) * cell
	texture_filter = TEXTURE_FILTER_NEAREST if sheet_set == "pixel" else TEXTURE_FILTER_LINEAR
	if not animation_finished.is_connected(queue_free):
		animation_finished.connect(queue_free)


## Fades the effect out over `fade` seconds and frees it: how a loop ends.
func finish(fade := 0.3) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, fade)
	tw.tween_callback(queue_free)
