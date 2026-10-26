
extends RigidBody3D

signal toppled(block: RigidBody3D)

enum BlockType {
	NORMAL,
	BONUS_AMMO,
	EXPLOSIVE
}

@export var block_type: BlockType = BlockType.NORMAL

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var effect_triggered := false


func _ready() -> void:
	var material := StandardMaterial3D.new()

	match block_type:
		BlockType.NORMAL:
			material.albedo_color = Color.BLUE
		BlockType.BONUS_AMMO:
			material.albedo_color = Color.GOLD
		BlockType.EXPLOSIVE:
			material.albedo_color = Color.RED

	mesh_instance.material_override = material


func _physics_process(_delta: float) -> void:
	if effect_triggered:
		return

	var up_direction = global_transform.basis.y.normalized()
	var angle = up_direction.angle_to(Vector3.UP)

	if angle >= deg_to_rad(45.0):
		effect_triggered = true
		toppled.emit(self)


func get_block_type() -> int:
	return block_type
