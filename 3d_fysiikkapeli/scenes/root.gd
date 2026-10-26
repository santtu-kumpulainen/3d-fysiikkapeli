
extends Node3D

@export var projectile_scene: PackedScene
@export var force: float = 20.0
@export var mouse_sensitivity: float = 0.002

@onready var camera: Camera3D = $Camera3D

var camera_pitch: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED



func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		camera.rotation.y -= event.relative.x * mouse_sensitivity
		camera_pitch -= event.relative.y * mouse_sensitivity
		camera_pitch = clamp(camera_pitch, deg_to_rad(-80), deg_to_rad(80))
		camera.rotation.x = camera_pitch

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			shoot()

	if event is InputEventKey:
		if event.keycode == KEY_ESCAPE and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_ESCAPE and not event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED



func shoot() -> void:
	var projectile = projectile_scene.instantiate() as RigidBody3D
	get_tree().current_scene.add_child(projectile)

	var direction = -camera.global_transform.basis.z
	projectile.global_position = camera.global_position + direction * 1.5
	projectile.apply_central_impulse(direction * force)
