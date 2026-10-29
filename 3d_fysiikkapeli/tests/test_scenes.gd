extends SceneTree

## Kohtaustestit: tavalliset kentät, satunnainen kenttä, fysiikan vakaus, ajastin ja
## putken kulku tulosruudun painikkeiden kautta. Väliaikainen tallennustiedosto.
## Ajo: godot --headless --fixed-fps 60 --path . -s res://tests/test_scenes.gd

const TEST_SAVE := "user://test_scenes_save.json"
const TEST_TEMP := "user://test_scenes_save.tmp"
const TEST_CORRUPT := "user://test_scenes_save.corrupt.json"
const REAL_SAVE := "user://save_data.json"

const RANDOM_SCENE := "res://scenes/levels/random_level.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const ORDINARY_LEVELS := ["res://scenes/root.tscn", "res://scenes/levels/level_2.tscn"]

const STABILITY_SEEDS := 40
const STABILITY_FRAMES := 180

var failures: Array[String] = []
var save_manager: Node
var random_run: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	save_manager = root.get_node("SaveManager")
	random_run = root.get_node("RandomRun")

	var real_hash := _real_save_hash()

	save_manager.save_path = TEST_SAVE
	save_manager.temp_path = TEST_TEMP
	save_manager.corrupt_path = TEST_CORRUPT
	_remove_test_files()
	save_manager.load_game()

	for path in ORDINARY_LEVELS:
		await _test_ordinary_level(path)

	await _test_random_scene_basics()
	await _test_stability()
	await _test_streak_flow()
	await _test_menu()

	_check(not save_manager.is_level_completed("level_1"), "kenttätulokset koskemattomat satunnaistilan jälkeen")
	_check(save_manager.get_level_data("level_2")["best_stars"] == 0, "kentälle 2 ei tullut tähtiä")

	change_scene_to_file(MENU_SCENE)
	await _frames(2)
	_remove_test_files()
	_check(real_hash == _real_save_hash(), "oikea tallennus ei muuttunut")

	_finish()


func _test_ordinary_level(path: String) -> void:
	print("--- ", path)
	change_scene_to_file(path)
	await _frames(2)

	var scene := current_scene
	var expected := scene.get_node("Boxes").get_child_count()
	var boxes := get_nodes_in_group("tower_boxes")

	_check(not scene.is_random_mode(), "tavallinen kenttä ei ole satunnaistilassa")
	_check(not scene.level_id.is_empty(), "kentän tunniste löytyy (%s)" % scene.level_id)
	_check(boxes.size() == expected, "palikoita ryhmässä %d / %d" % [boxes.size(), expected])
	_check(_all_connected_once(boxes, scene), "toppled kytketty kerran jokaiseen palikkaan")
	_check(not scene.hud.streak_label.visible and not scene.hud.random_info_panel.visible, "satunnaistilan HUD piilossa")

	await _check_timer(scene)

	await _frames(STABILITY_FRAMES)
	print("  tieto: kaatuneet 3 s jälkeen %d %%" % scene.get_fallen_percentage())

	scene.end_game()
	_check(scene.hud.result_overlay.visible and scene.hud.result_stars.visible, "tulosruutu tähtineen")
	_check(not scene.hud.result_streak.visible, "putkea ei näytetä tavallisessa kentässä")
	_check(scene.hud.next_button.text == "Seuraava kenttä", "seuraava-painikkeen teksti ennallaan")
	_check(not random_run.active, "tavallinen kenttä ei käynnistä satunnaisjuoksua")


## Ajastin vähenee täsmälleen kuluneen ajan verran (ennen korjausta kaksinkertaisesti).
func _check_timer(scene: Node) -> void:
	var before: float = scene.time_left
	await _frames(60)
	var elapsed: float = before - scene.time_left
	_check(absf(elapsed - 1.0) < 0.02, "ajastin: 60 ruutua (1,0 s) vähensi %.3f s" % elapsed)


func _test_random_scene_basics() -> void:
	print("--- satunnainen kenttä, siemen 12345")
	random_run.start_run(12345)
	change_scene_to_file(RANDOM_SCENE)
	await _frames(2)

	var scene := current_scene
	var layout: Dictionary = scene.random_layout
	var blocks: Array = layout["blocks"]
	var boxes := get_nodes_in_group("tower_boxes")

	_check(scene.is_random_mode(), "satunnaistila päällä")
	_check(layout["seed"] == 12345, "asettelu käyttää juoksun siementä")
	_check(boxes.size() == blocks.size(), "ryhmässä %d palikkaa, asettelussa %d" % [boxes.size(), blocks.size()])
	_check(scene.get_node("Boxes").get_child_count() == blocks.size(), "Boxes-solmussa kaikki palikat")
	_check(_all_connected_once(boxes, scene), "toppled kytketty kerran jokaiseen palikkaan")
	_check(scene.level_id.is_empty(), "satunnaiskentällä ei ole kenttätunnistetta")

	var types_ok := true
	var positions_ok := true
	var children := scene.get_node("Boxes").get_children()

	for i in blocks.size():
		types_ok = types_ok and children[i].get_block_type() == blocks[i]["type"]
		positions_ok = positions_ok and children[i].global_position.distance_to(layout["transforms"][i].origin) < 0.05

	_check(types_ok, "palikkatyypit vastaavat asettelua")
	_check(positions_ok, "alkusijainnit vastaavat asettelua")
	_check(scene.hud.streak_label.visible and scene.hud.streak_label.text == "Putki: 0 kenttää", "HUD: putki 0")
	_check(scene.hud.random_info_label.text == "Siemen: 12345 · %d palikkaa" % blocks.size(), "HUD: %s" % scene.hud.random_info_label.text)

	var camera := scene.get_node("Camera3D") as Camera3D
	var visible := 0

	for box in boxes:
		if camera.is_position_in_frustum(box.get_node("CollisionShape3D").global_position):
			visible += 1

	print("  tieto: kameran näkymässä %d / %d palikkaa alkuasennossa" % [visible, boxes.size()])

	await _check_timer(scene)


## Torni pysyy pystyssä, kun fysiikka käynnistyy.
func _test_stability() -> void:
	print("--- vakaus %d siemenellä, %d fysiikkaruutua" % [STABILITY_SEEDS, STABILITY_FRAMES])
	var worst_move := 0.0
	var worst_tilt := 0.0
	var fallen_levels := 0
	var min_in_view := 1.0

	for i in STABILITY_SEEDS:
		var seed_value := 1000 + i * 7919
		random_run.start_run(seed_value)
		change_scene_to_file(RANDOM_SCENE)
		await _frames(2)

		var scene := current_scene
		var start: Array = []
		var camera := scene.get_node("Camera3D") as Camera3D
		var in_view := 0

		for box in scene.get_node("Boxes").get_children():
			start.append(box.global_position)

			if camera.is_position_in_frustum(box.get_node("CollisionShape3D").global_position):
				in_view += 1

		min_in_view = minf(min_in_view, float(in_view) / start.size())

		await _physics_frames(STABILITY_FRAMES)

		var children := scene.get_node("Boxes").get_children()

		for j in children.size():
			worst_move = maxf(worst_move, children[j].global_position.distance_to(start[j]))
			worst_tilt = maxf(worst_tilt, rad_to_deg(children[j].global_transform.basis.y.angle_to(Vector3.UP)))

		if scene.get_fallen_percentage() > 0:
			fallen_levels += 1
			printerr("  siemen %d: kaatuneita %d %%" % [seed_value, scene.get_fallen_percentage()])

	print("  tieto: suurin siirtymä %.4f, suurin kallistus %.3f astetta" % [worst_move, worst_tilt])
	print("  tieto: pienin kameran alkunäkymässä oleva osuus %.0f %%" % (min_in_view * 100.0))
	_check(fallen_levels == 0, "yksikään torni ei kaatunut itsestään (%d / %d)" % [fallen_levels, STABILITY_SEEDS])
	_check(worst_move < 0.1, "palikat pysyvät paikallaan (suurin siirtymä %.4f)" % worst_move)


func _test_streak_flow() -> void:
	print("--- putken kulku painikkeiden kautta")
	random_run.start_run(12345)
	change_scene_to_file(RANDOM_SCENE)
	await _frames(2)

	var scene := current_scene
	var first_blocks: Array = scene.random_layout["blocks"].duplicate(true)
	var first_transforms: Array = scene.random_layout["transforms"].duplicate()

	# Epäonnistuminen: mitään ei kaadettu.
	scene.end_game()
	_check(random_run.level_state == random_run.LevelState.FAILED, "0 % on epäonnistuminen")
	_check(random_run.streak == 0, "epäonnistuminen ei kasvata putkea")
	_check(scene.hud.retry_button.visible and not scene.hud.next_button.visible, "epäonnistuessa: Yritä uudelleen, ei Seuraava")
	_check(not scene.hud.result_stars.visible, "satunnaistilassa ei tähtiä")
	_check(scene.hud.result_streak.text == "Putki: 0 kenttää", "tulosruutu: %s" % scene.hud.result_streak.text)
	_check(scene.hud.result_best.text == "Ennätys: 0 kenttää", "tulosruutu: %s" % scene.hud.result_best.text)

	scene._on_retry_pressed()
	await _frames(2)
	scene = current_scene
	_check(scene.random_layout["seed"] == 12345, "uusinta samalla siemenellä")
	_check(scene.random_layout["blocks"] == first_blocks, "uusinnassa samat palikkatyypit ja solut")
	_check(scene.random_layout["transforms"] == first_transforms, "uusinnassa samat sijainnit")
	_check(get_nodes_in_group("tower_boxes").size() == first_blocks.size(), "edellisen kierroksen palikat poistuneet")
	_check(not scene.game_over and scene.ammo_left == 5 and scene.time_left > 59.9, "kierroksen tila nollattu")

	# Läpäisy: kaadetaan kaikki palikat. Bonukset ja räjähdykset laukeavat normaalisti.
	var bonus_count := _count_type(scene, 1)
	var explosive_count := _count_type(scene, 2)
	# Kallistus tehdään fysiikkavaiheessa, kuten pelissä: palikan toppled-signaali ehtii
	# ennen Rootin _process-tarkistusta.
	await physics_frame
	_topple_all(scene)
	await _physics_frames(3)
	await _frames(2)

	_check(scene.game_over, "kaikkien kaatuminen päättää kierroksen")
	_check(random_run.streak == 1, "läpäisy nostaa putken yhteen")
	_check(scene.ammo_left == 5 + 2 * bonus_count, "bonuspalikat antoivat ammuksia (%d)" % scene.ammo_left)
	_check(_count_vfx(scene) == explosive_count, "räjähdysefektejä %d / %d" % [_count_vfx(scene), explosive_count])
	_check(_count_dissolving(scene) == explosive_count, "räjähtäneet palikat liukenevat")
	_check(get_nodes_in_group("tower_boxes").size() == first_blocks.size(), "räjähdykset eivät muuta nimittäjää")
	_check(scene.get_fallen_percentage() == 100, "kaatuneita 100 %")
	_check(scene.hud.next_button.visible and scene.hud.next_button.text == "Seuraava satunnaiskenttä", "Seuraava satunnaiskenttä -painike")
	_check(not scene.hud.retry_button.visible, "läpäisyn jälkeen ei uusintaa")
	_check(scene.hud.result_record.visible, "uusi ennätys näytetään")
	_check(save_manager.get_best_streak() == 1, "paras putki tallennettu")

	# R-näppäin / uusinta ei saa toistaa läpäistyä kenttää.
	scene._on_retry_pressed()
	await _frames(2)
	_check(current_scene == scene, "läpäistyn kentän uusinta estetty")
	_check(random_run.streak == 1, "putki ennallaan estetyn uusinnan jälkeen")

	scene._on_next_pressed()
	await _frames(2)
	var next_scene := current_scene
	_check(next_scene != scene, "seuraava kenttä ladattu")
	_check(next_scene.random_layout["seed"] != 12345, "seuraava kenttä uudella siemenellä (%d)" % next_scene.random_layout["seed"])
	_check(next_scene.random_layout["blocks"] != first_blocks, "seuraava kenttä eri asettelulla")
	_check(next_scene.hud.streak_label.text == "Putki: 1 kenttää", "HUD: %s" % next_scene.hud.streak_label.text)
	_check(get_nodes_in_group("tower_boxes").size() == next_scene.random_layout["blocks"].size(), "ryhmässä vain uuden tornin palikat")
	_check(not next_scene.game_over and next_scene.ammo_left == 5, "uusi kierros nollattu")

	next_scene.end_game()
	_check(random_run.streak == 1, "epäonnistuminen jättää putken yhteen")
	_check(next_scene.hud.result_record.visible, "epäonnistuessa näytetään juoksun ennätys")
	_check(next_scene.hud.result_title.text == "Putki päättyi", "otsikko: %s" % next_scene.hud.result_title.text)

	next_scene._on_menu_pressed()
	await _frames(2)
	_check(not random_run.active and random_run.streak == 0, "valikko päättää juoksun")
	_check(save_manager.get_best_streak() == 1, "ennätys säilyy valikossa")


func _test_menu() -> void:
	print("--- valikko")
	change_scene_to_file(MENU_SCENE)
	await _frames(2)

	var menu := current_scene
	_check(menu.random_button.text == "Satunnainen pelimuoto", "valikossa satunnaistilan painike")

	menu._show_random_mode()
	_check(menu.random_panel.visible and not menu.main_panel.visible, "satunnaistilan paneeli auki")
	_check(menu.best_streak_label.text == "Ennätys: 1 kenttää", "valikko: %s" % menu.best_streak_label.text)

	menu.seed_edit.text = "abc"
	menu._on_start_random_pressed()
	await _frames(2)
	_check(current_scene == menu and menu.seed_error_label.visible, "virheellinen siemen hylätään")

	menu.seed_edit.text = "777"
	menu._on_start_random_pressed()
	await _frames(2)
	_check(current_scene.scene_file_path == RANDOM_SCENE, "aloita avaa satunnaisen kentän")
	_check(current_scene.random_layout["seed"] == 777 and random_run.streak == 0, "syötetty siemen 777, putki 0")

	current_scene._on_menu_pressed()
	await _frames(2)
	current_scene._show_random_mode()
	current_scene.seed_edit.text = ""
	current_scene._on_start_random_pressed()
	await _frames(2)
	_check(current_scene.scene_file_path == RANDOM_SCENE, "tyhjä siemen arpoo uuden (%d)" % random_run.current_seed)


func _topple_all(scene: Node) -> void:
	for box in scene.get_node("Boxes").get_children():
		box.freeze = true
		var tilted: Transform3D = box.global_transform
		tilted.basis = tilted.basis * Basis(Vector3.RIGHT, deg_to_rad(90))
		box.global_transform = tilted


func _count_type(scene: Node, type: int) -> int:
	var count := 0

	for box in scene.get_node("Boxes").get_children():
		if box.get_block_type() == type:
			count += 1

	return count


func _count_vfx(scene: Node) -> int:
	var count := 0

	for child in scene.get_children():
		if child.scene_file_path == "res://scenes/effects/explosion_vfx.tscn":
			count += 1

	return count


func _count_dissolving(scene: Node) -> int:
	var count := 0

	for box in scene.get_node("Boxes").get_children():
		if box.dissolving:
			count += 1

	return count


func _all_connected_once(boxes: Array, scene: Node) -> bool:
	for box in boxes:
		var count := 0

		for connection in box.toppled.get_connections():
			if connection["callable"].get_object() == scene:
				count += 1

		if count != 1:
			return false

	return true


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for i in count:
		await physics_frame


func _real_save_hash() -> String:
	return FileAccess.get_md5(REAL_SAVE) if FileAccess.file_exists(REAL_SAVE) else "(ei tiedostoa)"


func _remove_test_files() -> void:
	for path in [TEST_SAVE, TEST_TEMP, TEST_CORRUPT]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok  " + message)
	else:
		printerr("VIRHE: " + message)
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("KOHTAUSTESTIT: OK")
		quit(0)
	else:
		print("KOHTAUSTESTIT: %d virhettä" % failures.size())
		quit(1)
