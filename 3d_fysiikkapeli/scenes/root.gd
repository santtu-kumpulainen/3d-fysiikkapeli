
extends Node3D

@export var projectile_scene: PackedScene
@export var force: float = 20.0

@onready var camera: Camera3D = $Camera3D


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			shoot()


func shoot() -> void:
	var projectile = projectile_scene.instantiate() as RigidBody3D
	get_tree().current_scene.add_child(projectile)

	var direction = -camera.global_transform.basis.z
	projectile.global_position = camera.global_position + direction * 1.5

	projectile.apply_central_impulse(direction * force)
