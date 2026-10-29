
extends RigidBody3D

signal toppled(block: RigidBody3D)

enum BlockType {
	NORMAL,
	BONUS_AMMO,
	EXPLOSIVE
}

@export var block_type: BlockType = BlockType.NORMAL

const EXPLOSIVE_MATERIAL := preload("res://assets/shaders/explosive_block_material.tres")
const DISSOLVE_TIME: float = 0.9

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var effect_triggered := false
var dissolve_material: ShaderMaterial
var dissolving := false


func _ready() -> void:
	var material := StandardMaterial3D.new()

	match block_type:
		BlockType.NORMAL:
			material.albedo_color = Color.BLUE
		BlockType.BONUS_AMMO:
			material.albedo_color = Color.GOLD
		BlockType.EXPLOSIVE:
			apply_explosive_material()
			return

	mesh_instance.material_override = material


## Jokainen räjähtävä palikka saa oman kopion, jotta liukeneminen ei vaikuta muihin.
func apply_explosive_material() -> void:
	dissolve_material = EXPLOSIVE_MATERIAL.duplicate()
	mesh_instance.material_override = dissolve_material

	for child in mesh_instance.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_override = dissolve_material


## Liuottaa palikan pois räjähdyksen jälkeen. Palikka jää tower_boxes-ryhmään,
## jotta kaatuneiden prosenttiosuus ei muutu.
func start_dissolve() -> void:
	if dissolving or dissolve_material == null:
		return

	dissolving = true
	set_deferred("freeze", true)
	collision_shape.set_deferred("disabled", true)

	var tween := create_tween()
	tween.tween_property(dissolve_material, "shader_parameter/dissolve_amount", 1.0, DISSOLVE_TIME)
	tween.tween_callback(mesh_instance.hide)


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
