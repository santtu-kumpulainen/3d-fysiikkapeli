
extends Node3D

@export var projectile_scene: PackedScene
@export var force: float = 20.0
@export var mouse_sensitivity: float = 0.002

@onready var camera: Camera3D = $Camera3D
@onready var hud: GameHUD = $HUD



const MENU_SCENE := "res://scenes/main_menu.tscn"

## Pienin kaatumisprosentti, jolla kenttä läpäistään (yksi tähti).
const COMPLETION_PERCENT := 65

var time_left: float = 60.0
var ammo_left: int = 5
var game_over: bool = false
var camera_pitch: float = 0.0
var level_id: String = ""

var normal_fov: float = 75.0
var zoom_fov: float = 40.0
var force_step: float = 5.0
var min_force: float = 5.0
var max_force: float = 50.0

# Kameraefektit
var recoil_fov: float = 12.0
var recoil_fov_offset: float = 0.0
var recoil_return_speed: float = 8.0

var shake_strength: float = 0.0
var shake_decay: float = 12.0
var shake_offset: Vector3 = Vector3.ZERO
var camera_base_position: Vector3




func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	level_id = SaveManager.get_level_id_for_scene(scene_file_path)

	if level_id.is_empty():
		push_warning("Kenttää ei löydy SaveManagerin listasta, tulosta ei tallenneta: " + scene_file_path)

	hud.set_ammo(ammo_left)
	update_score()

	for box in get_tree().get_nodes_in_group("tower_boxes"):
		if box.has_signal("toppled"):
			box.toppled.connect(_on_box_toppled)

	hud.set_time(time_left)

	normal_fov = camera.fov
	camera.fov = normal_fov

	# Lopetusvalikon painikkeet
	hud.retry_requested.connect(_on_retry_pressed)
	hud.next_requested.connect(_on_next_pressed)
	hud.menu_requested.connect(_on_menu_pressed)

	update_force_label()

	camera_base_position = camera.position



func update_force_label() -> void:
	hud.set_force(force)


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
						_on_retry_pressed()

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

	if projectile_scene == null:
		push_error("Projectile Scene puuttuu Inspectorin projectile_scene-asetuksesta.")
		return

	ammo_left -= 1
	apply_recoil()
	hud.set_ammo(ammo_left)

	var projectile = projectile_scene.instantiate() as RigidBody3D
	get_tree().current_scene.add_child(projectile)

	var direction = -camera.global_transform.basis.z
	projectile.global_position = camera.global_position + direction * 1.5
	projectile.apply_central_impulse(direction * force)

	# Wait for blocks
	if ammo_left == 0:
		await get_tree().create_timer(5.0).timeout
		if not game_over:
			end_game()


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
	hud.set_score(get_fallen_percentage())

## star rating: 0 tähteä tarkoittaa, ettei kenttää läpäisty.
func get_star_rating(percentage: int) -> int:
	if percentage >= 100:
		return 3
	elif percentage >= 80:
		return 2
	elif percentage >= COMPLETION_PERCENT:
		return 1
	else:
		return 0


func _process(delta: float) -> void:
	if game_over:
		return

	# Palauta FOV normaaliksi pehmeästi.
	recoil_fov_offset = lerpf(
	recoil_fov_offset,
	0.0,
	minf(recoil_return_speed * delta, 1.0)
)

	var target_fov: float = normal_fov + recoil_fov_offset

	camera.fov = lerpf(
		camera.fov,
		target_fov,
		minf(12.0 * delta, 1.0)
	)

	# Kameran kevyt tärähdys.
	shake_strength = move_toward(
		shake_strength,
		0.0,
		shake_decay * delta
	)

	shake_offset = Vector3(
		randf_range(-shake_strength, shake_strength),
		randf_range(-shake_strength, shake_strength),
		0.0
	)

	camera.position = camera_base_position + shake_offset

	# Päivitä pisteet.
	update_score()

	# Voitto, kun kaikki palikat ovat kaatuneet.
	if get_fallen_percentage() >= 100:
		end_game()
		return

	# Päivitä ajastin.
	time_left = maxf(time_left - delta, 0.0)
	hud.set_time(time_left)

	if time_left <= 0.0:
		end_game()



	time_left = maxf(time_left - delta, 0.0)
	hud.set_time(time_left)

	if time_left <= 0.0:
		end_game()



## Kierroksen loppu. Läpäisy ratkeaa tähtien perusteella riippumatta siitä,
## loppuiko kierros aikaan, ammuksiin vai kaikkien palikoiden kaatumiseen.
func end_game() -> void:
	if game_over:
		return

	game_over = true

	var percentage := get_fallen_percentage()
	var stars := get_star_rating(percentage)
	var completed := stars > 0
	var new_record := false

	if completed and not level_id.is_empty():
		var result := SaveManager.update_level_record(level_id, percentage, stars)
		new_record = result["new_best_score"] or result["new_best_stars"]

	var next_id := SaveManager.get_next_level_id(level_id)
	var has_next := not next_id.is_empty() and SaveManager.is_level_unlocked(next_id)

	hud.show_result(
		completed,
		percentage,
		stars,
		COMPLETION_PERCENT,
		SaveManager.get_level_data(level_id),
		new_record,
		has_next
	)

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
			hud.set_ammo(ammo_left)
		2:
			explode(block)

## explode
func explode(block: RigidBody3D) -> void:
	
	apply_camera_shake(0.55)
	
	var particles := block.get_node_or_null("ExplosionParticles") as GPUParticles3D

	# Montako partikkelia piirretään
	if particles != null:
		particles.emitting = false
		particles.restart()
		particles.emitting = true
		print("Partikkeleta: ", particles.amount)
	else:
		print("ExplosionParticles puuttuu: ", block.name)
	
	var explosion_radius: float = 4.0
	var explosion_force: float = 4.0

	# Toimiiko node
	if particles != null:
		particles.restart()
		particles.emitting = true
	else:
		print("Palikasta puuttuu ExplosionParticles: ", block.name)

	# Työnnä lähellä olevia palikoita.
	for other in get_tree().get_nodes_in_group("tower_boxes"):
		if other == block:
			continue

		if not other is RigidBody3D:
			continue

		var distance: float = block.global_position.distance_to(other.global_position)

		if distance <= explosion_radius:
			var direction: Vector3 = (
				other.global_position - block.global_position
			).normalized()

			direction.y += 0.5
			other.apply_central_impulse(
				direction.normalized() * explosion_force
			)



	# Työnnä lähellä olevia palikoita.
	for other in get_tree().get_nodes_in_group("tower_boxes"):
		if other == block:
			continue

		if not other is RigidBody3D:
			continue

		var distance := block.global_position.distance_to(other.global_position)

		if distance <= explosion_radius:
			var direction: Vector3 = (
	other.global_position - block.global_position
).normalized()

			direction.y += 0.5
			other.apply_central_impulse(
				direction.normalized() * explosion_force
			)

func apply_recoil() -> void:
	recoil_fov_offset = recoil_fov


func apply_camera_shake(strength: float = 0.12) -> void:
	shake_strength = maxf(shake_strength, strength)

func _on_retry_pressed() -> void:
	print("Yritä uudelleen painettu")
	get_tree().reload_current_scene()


func _on_next_pressed() -> void:
	var next_id := SaveManager.get_next_level_id(level_id)

	if next_id.is_empty() or not SaveManager.is_level_unlocked(next_id):
		return

	get_tree().change_scene_to_file(SaveManager.get_level_path(next_id))



func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
