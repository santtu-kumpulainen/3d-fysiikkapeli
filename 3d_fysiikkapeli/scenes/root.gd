
extends Node3D

@export var projectile_scene: PackedScene
@export var force: float = 20.0
@export var mouse_sensitivity: float = 0.002

@onready var camera: Camera3D = $Camera3D
@onready var ammo_label: Label = $CanvasLayer/AmmoLabel
@onready var victory_label: Label = $CanvasLayer/Message
@onready var score_label: Label = $CanvasLayer/ScoreLabel
@onready var timer_label: Label = $CanvasLayer/TimerLabel
@onready var crosshair: Label = $CanvasLayer/Crosshair
@onready var force_label: Label = $CanvasLayer/ForceLabel
@onready var controls_label: Label = $CanvasLayer/ControlsLabel

var time_left: float = 20.0

var ammo_left: int = 5
var game_over: bool = false
var camera_pitch: float = 0.0

var normal_fov: float = 75.0
var zoom_fov: float = 40.0
var force_step: float = 5.0
var min_force: float = 5.0
var max_force: float = 50.0





func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	ammo_label.text = "Ammuksia: " + str(ammo_left)
	victory_label.visible = false
	update_score()

	for box in get_tree().get_nodes_in_group("tower_boxes"):
		if box.has_signal("toppled"):
			box.toppled.connect(_on_box_toppled)

	timer_label.text = "Aikaa: %d" % ceili(time_left)

	normal_fov = camera.fov
	camera.fov = normal_fov

	# Tähtäin keskelle näyttöä
	crosshair.visible = true
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -15
	crosshair.offset_top = -20
	crosshair.offset_right = 15
	crosshair.offset_bottom = 20
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.z_index = 10

	# Voimanäyttö vasempaan alakulmaan
	force_label.visible = true
	force_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	force_label.offset_left = 20
	force_label.offset_top = -45
	force_label.offset_right = 220
	force_label.offset_bottom = -15
	force_label.z_index = 10
	update_force_label()

	# Ohjeet oikeaan alakulmaan
	controls_label.visible = true
	controls_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	controls_label.offset_left = -240
	controls_label.offset_top = -100
	controls_label.offset_right = -20
	controls_label.offset_bottom = -20
	controls_label.text = "SPACE - Zoomaus\n- - Vähennä voimaa\n+ - Lisää voimaa"
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls_label.z_index = 10



func update_force_label() -> void:
	force_label.text = "Voima: " + str(int(force))



func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not game_over:
			camera.rotation.y -= event.relative.x * mouse_sensitivity
			camera_pitch -= event.relative.y * mouse_sensitivity
			camera_pitch = clamp(
				camera_pitch,
				deg_to_rad(-80),
				deg_to_rad(80)
			)
			camera.rotation.x = camera_pitch

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not game_over:
				shoot()

	if event is InputEventKey:
		if event.pressed and not event.echo:
			match event.keycode:
				KEY_ESCAPE:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

				KEY_R:
					if game_over:
						get_tree().reload_current_scene()

				KEY_SPACE:
					if not game_over:
						camera.fov = zoom_fov

				KEY_MINUS, KEY_KP_SUBTRACT:
					if not game_over:
						force = maxf(force - force_step, min_force)
						update_force_label()

				KEY_EQUAL, KEY_KP_ADD:
					if not game_over:
						force = minf(force + force_step, max_force)
						update_force_label()

		elif not event.pressed and event.keycode == KEY_SPACE:
			camera.fov = normal_fov



func shoot() -> void:
	if game_over or ammo_left <= 0:
		return

	ammo_left -= 1
	ammo_label.text = "Ammuksia: " + str(ammo_left)

	var projectile = projectile_scene.instantiate() as RigidBody3D
	get_tree().current_scene.add_child(projectile)

	var direction = -camera.global_transform.basis.z
	projectile.global_position = camera.global_position + direction * 1.5
	projectile.apply_central_impulse(direction * force)

	if ammo_left == 0:
		await get_tree().create_timer(3.0).timeout

		if not game_over:
			end_game(false)


func count_fallen_boxes() -> int:
	var boxes = get_tree().get_nodes_in_group("tower_boxes")
	var fallen: int = 0

	for box in boxes:
		var up_direction = box.global_transform.basis.y.normalized()
		var angle = up_direction.angle_to(Vector3.UP)

		if angle >= deg_to_rad(45.0):
			fallen += 1

	return fallen


func get_fallen_percentage() -> int:
	var boxes = get_tree().get_nodes_in_group("tower_boxes")

	if boxes.is_empty():
		return 0

	return int(round(
		float(count_fallen_boxes()) / float(boxes.size()) * 100.0
	))


func update_score() -> void:
	var percentage = get_fallen_percentage()
	score_label.text = "Kaatuneet: %d%% / 100%%" % percentage


func get_star_rating(percentage: int) -> String:
	if percentage >= 100:
		return "★★★"
	elif percentage >= 90:
		return "★★"
	elif percentage >= 80:
		return "★"
	else:
		return "Ei tähtiä"



func _process(delta: float) -> void:
	if game_over:
		return

	update_score()

	# 100 % kaatuneita laatikoita tarkoittaa voittoa
	if get_fallen_percentage() >= 100:
		end_game(true)
		return

	# Vähennä aikaa
	time_left -= delta
	time_left = maxf(time_left, 0.0)

	timer_label.text = "Aikaa: %d" % ceili(time_left)

	# Ajan loppuminen tarkoittaa häviötä
	if time_left <= 0.0:
		game_over = true
		victory_label.text = "Aika loppui! Kaatuneet: %d%%. Paina R yrittääksesi uudelleen." % get_fallen_percentage()
		victory_label.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE




func end_game(won: bool) -> void:
	if game_over:
		return

	game_over = true

	var percentage := get_fallen_percentage()
	var stars := get_star_rating(percentage)

	if won:
		victory_label.text = "Voitit!\nKaatuneet: %d%%\nTähdet: %s\nPaina R pelataksesi uudelleen." % [
			percentage,
			stars
		]
	else:
		victory_label.text = "Peli päättyi!\nKaatuneet: %d%%\nTähdet: %s\nPaina R yrittääksesi uudelleen." % [
			percentage,
			stars
		]

	victory_label.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	
	
func _on_box_toppled(block: RigidBody3D) -> void:
	if game_over:
		return

	if not block.has_method("get_block_type"):
		return

	match block.get_block_type():
		0:
			pass
		1:
			ammo_left += 2
			ammo_label.text = "Ammuksia: " + str(ammo_left)
		2:
			explode(block)

	match block.block_type:
		0:
			pass
		1:
			ammo_left += 2
			ammo_label.text = "Ammuksia: " + str(ammo_left)
		2:
			explode(block)


func explode(block: RigidBody3D) -> void:
	var explosion_radius := 4.0
	var explosion_force := 8.0

	for other in get_tree().get_nodes_in_group("tower_boxes"):
		if other == block:
			continue

		if not other is RigidBody3D:
			continue

		var distance = block.global_position.distance_to(other.global_position)

		if distance <= explosion_radius:
			var direction = (other.global_position - block.global_position).normalized()
			direction.y += 0.5
			other.apply_central_impulse(direction.normalized() * explosion_force)
