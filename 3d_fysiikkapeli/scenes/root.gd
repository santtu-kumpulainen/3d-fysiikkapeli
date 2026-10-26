
extends Node3D

@export var projectile_scene: PackedScene
@export var force: float = 20.0
@export var mouse_sensitivity: float = 0.002

@onready var camera: Camera3D = $Camera3D
@onready var ammo_label: Label = $CanvasLayer/AmmoLabel
@onready var victory_label: Label = $CanvasLayer/Message
@onready var score_label: Label = $CanvasLayer/ScoreLabel

var ammo_left: int = 3
var game_over: bool = false
var camera_pitch: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ammo_label.text = "Ammuksia: " + str(ammo_left)
	victory_label.visible = false
	update_score()


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

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		elif event.keycode == KEY_R and game_over:
			get_tree().reload_current_scene()


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


func _process(_delta: float) -> void:
	if game_over:
		return

	update_score()

	if get_fallen_percentage() >= 100:
		end_game(true)


func end_game(won: bool) -> void:
	if game_over:
		return

	game_over = true

	if won:
		victory_label.text = "Voitit! Kaikki laatikot kaatuivat. Paina R pelataksesi uudelleen."
	else:
		victory_label.text = "Peli päättyi! Kaatuneet: %d%%. Paina R yrittääksesi uudelleen." % get_fallen_percentage()

	victory_label.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
