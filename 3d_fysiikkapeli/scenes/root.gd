
extends Node3D

@export var projectile_scene: PackedScene
@export var force: float = 20.0
@export var mouse_sensitivity: float = 0.002

@onready var camera: Camera3D = $Camera3D
@onready var ammo_label: Label = $CanvasLayer/AmmoLabel
@onready var victory_label: Label = $CanvasLayer/Message

var ammo_left := 3
var game_over := false

var camera_pitch: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED




func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not game_over:
			camera.rotation.y -= event.relative.x * mouse_sensitivity
			camera_pitch -= event.relative.y * mouse_sensitivity
			camera_pitch = clamp(camera_pitch, deg_to_rad(-80), deg_to_rad(80))
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
		game_over = true
		victory_label.text = "Peli päättyi! Paina R pelataksesi uudelleen."
		victory_label.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
