extends Node2D
## Pick a colour and an effect, click to set it off. The cannon fires muzzle flashes, fireballs and
## rockets at the click, and they burst where they land; fire, burning ground, smoke and fuses stay
## where they are put until the oldest makes room. Left alone, the demo sets things off by itself.

const CANNON := Vector2(140, 520)
const GROUND_Y := 560.0
const SHAPES := ["explosion", "blast", "cluster", "ground", "mushroom", "implosion", "firework", "puff", "muzzle",
	"fireball", "rocket", "fire", "burn", "smoke", "fuse"]
const LOOPS := ["fire", "burn", "smoke", "fuse"]
## What a shot bursts into where it lands.
const BURST := {"fireball": "blast", "rocket": "explosion"}
const MAX_LOOPS := 4
const SPEED := 700.0
const IDLE := 3.0

var palette := ""
var shape := ""
var idle := 0.5
var palettes: Array[String] = []
var shapes: Array[String] = []
var palette_row: HFlowContainer
var shape_row: HFlowContainer
var loops: Array[ExplosionFX] = []
var shots: Array[Dictionary] = []   # fireballs and rockets in flight: {fx, to, burst}
var aim := Vector2(700, 400)
var auto := 0


func _ready() -> void:
	var have := ExplosionFX.effects()
	for fx_name in have:
		var p := fx_name.get_slice("_", 0)
		if p not in palettes:
			palettes.append(p)
	for s: String in SHAPES:
		if palettes.any(func(p: String) -> bool: return (p + "_" + s) in have):
			shapes.append(s)
	palette = palettes[0]
	shape = shapes[0]
	var bar := VBoxContainer.new()
	bar.position = Vector2(16, 12)
	add_child(bar)
	palette_row = _choices(palettes, func(v: String) -> void:
		palette = v
		if (palette + "_" + shape) not in ExplosionFX.effects():
			shape = shapes.filter(func(s: String) -> bool: return (palette + "_" + s) in ExplosionFX.effects())[0]
			_show(shape_row, shape))
	shape_row = _choices(shapes, func(v: String) -> void:
		shape = v
		palette = _colour(palette, shape)
		_show(palette_row, palette))
	bar.add_child(palette_row)
	bar.add_child(shape_row)
	var first: Dictionary = ExplosionFX.info(have[0])
	var sets := ["256", "128", "pixel"].filter(func(s: String) -> bool:  # the web build leaves 256 out
		return ResourceLoader.exists(ExplosionFX.sheets_dir.path_join(s).path_join(first.file)))
	ExplosionFX.default_set = sets[0]
	bar.add_child(_choices(sets, func(v: String) -> void: ExplosionFX.default_set = v))
	var hint := Label.new()
	hint.text = "Click to set it off."
	hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.9))
	bar.add_child(hint)


func _choices(values: Array, pick: Callable) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.custom_minimum_size.x = 1248
	var group := ButtonGroup.new()
	for v: String in values:
		var b := Button.new()
		b.text = v
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = v == values[0]
		b.pressed.connect(pick.bind(v))
		row.add_child(b)
	return row


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		idle = IDLE
		set_off(palette, shape, click.position)


## Plays `p`_`what` at `at`, or from the cannon towards it.
## `p` if it comes in `what`, else the first colour that does: a free sampler has each effect in one.
func _colour(p: String, what: String) -> String:
	for q: String in [p] + palettes:
		if (q + "_" + what) in ExplosionFX.effects():
			return q
	return p


func _show(row: HFlowContainer, v: String) -> void:
	for b: Button in row.get_children():
		b.set_pressed_no_signal(b.text == v)


func set_off(p: String, what: String, at: Vector2) -> void:
	p = _colour(p, what)
	var fx_name := p + "_" + what
	if fx_name not in ExplosionFX.effects():
		return
	aim = at
	var muzzle := CANNON + (at - CANNON).normalized() * 60.0
	var angle := (at - CANNON).angle()
	if what == "muzzle":
		_spawn(fx_name, muzzle, angle)
	elif what in BURST:
		shots.append({"fx": _spawn(fx_name, muzzle, angle), "to": at, "burst": p + "_" + BURST[what]})
	elif what in ["ground", "mushroom", "fire", "burn", "smoke", "fuse"]:
		var fx := _spawn(fx_name, Vector2(at.x, GROUND_Y))
		if what in LOOPS:
			loops.append(fx)
			if loops.size() > MAX_LOOPS:
				loops.pop_front().finish()
	else:
		_spawn(fx_name, at)


func _spawn(fx_name: String, at: Vector2, angle := 0.0) -> ExplosionFX:
	var fx := ExplosionFX.spawn(self, fx_name, at, angle)
	var e := ExplosionFX.info(fx_name)
	fx.scale = Vector2.ONE * e.cell["256"][0] / e.cell[fx.sheet_set][0]   # every set at one size
	return fx


func _process(delta: float) -> void:
	for s in shots.duplicate():
		var fx: ExplosionFX = s.fx
		fx.global_position = fx.global_position.move_toward(s.to, SPEED * delta)
		if fx.global_position == s.to:
			fx.queue_free()
			shots.erase(s)
			var burst: String = s.burst
			if burst in ExplosionFX.effects():
				_spawn(burst, s.to)
	queue_redraw()
	idle -= delta
	if idle > 0.0:
		return
	idle = 0.9
	auto += 1
	var at := Vector2(randf_range(420, 1180), randf_range(260, 520))
	set_off(palettes[(auto / 5) % palettes.size()], shapes[auto % shapes.size()], at)


func _draw() -> void:
	draw_rect(get_viewport_rect(), Color(0.07, 0.06, 0.11))
	draw_rect(Rect2(0, GROUND_Y, 1280, 160), Color(0.1, 0.09, 0.15))
	# the cannon, turned to where it last fired
	var dir := (aim - CANNON).normalized()
	draw_line(CANNON, CANNON + dir * 60.0, Color(0.45, 0.47, 0.6), 18)
	draw_circle(CANNON, 26, Color(0.3, 0.32, 0.45))
	draw_rect(Rect2(CANNON + Vector2(-34, 10), Vector2(68, 30)), Color(0.36, 0.26, 0.18))
