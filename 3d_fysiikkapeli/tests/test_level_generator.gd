extends SceneTree

## Generaattorin testit ilman fysiikkaa: toistettavuus, erikoispalikoiden määrät,
## päällekkäisyydet, tuenta ja pelialue usealla siemenellä.
## Ajo: godot --headless --path . -s res://tests/test_level_generator.gd

const SEED_COUNT := 5000
const EPSILON := 0.0001
## Sama kuin RandomRun.MAX_SEED (autoloadia ei voi käyttää -s-ajossa käännösvaiheessa).
const MAX_SEED := 4294967295

var failures: Array[String] = []


func _initialize() -> void:
	var generator := LevelGenerator.new()
	var metrics := LevelGenerator.measure_block()
	var area := _ground_area_from_scene()

	print("Palikan mitat: ", metrics)
	print("Pelialue: ", area)

	var signatures := {}
	var ratio_min := 1.0
	var ratio_max := 0.0
	var ratio_sum := 0.0
	var off_target := 0
	var fallbacks := 0
	var max_attempts := 0
	var count_min := 1000
	var count_max := 0
	var explosive_hist := {}
	var bonus_hist := {}
	var layer_hist := {}
	var quadrant_single := 0

	var seeds: Array[int] = []

	for i in SEED_COUNT:
		seeds.append(i)

	# Myös suuria siemeniä lähellä 32-bittistä ylärajaa.
	for i in 50:
		seeds.append(MAX_SEED - i)

	for seed_value in seeds:
		var layout := generator.generate_layout(seed_value)

		# Globaalin satunnaisgeneraattorin tila ei saa vaikuttaa tulokseen.
		seed(seed_value + 99)
		randi()
		var again := generator.generate_layout(seed_value)

		if layout != again:
			_fail("Siemen %d ei tuota samaa asettelua" % seed_value)

		var transforms := generator.compute_transforms(layout, metrics, area["top"])

		if transforms != generator.compute_transforms(again, metrics, area["top"]):
			_fail("Siemen %d ei tuota samoja sijainteja" % seed_value)

		var blocks: Array = layout["blocks"]
		var total := blocks.size()
		var explosive := _count_type(blocks, LevelGenerator.TYPE_EXPLOSIVE)
		var bonus := _count_type(blocks, LevelGenerator.TYPE_BONUS)

		if explosive != layout["explosive_count"] or bonus != layout["bonus_count"]:
			_fail("Siemen %d: tyyppimäärät eivät vastaa laskettuja" % seed_value)

		if explosive < 2 or explosive > 8:
			_fail("Siemen %d: räjähtäviä %d" % [seed_value, explosive])

		if bonus < 2 or bonus > 5:
			_fail("Siemen %d: bonuksia %d" % [seed_value, bonus])

		if total < generator.min_blocks or total > generator.max_blocks:
			_fail("Siemen %d: palikoita %d" % [seed_value, total])

		var ratio := float(explosive + bonus) / total
		ratio_min = minf(ratio_min, ratio)
		ratio_max = maxf(ratio_max, ratio)
		ratio_sum += ratio

		if explosive + bonus != roundi(total * generator.special_ratio):
			off_target += 1

		if layout["used_fallback"]:
			fallbacks += 1

		max_attempts = maxi(max_attempts, layout["attempts"])
		count_min = mini(count_min, total)
		count_max = maxi(count_max, total)
		explosive_hist[explosive] = explosive_hist.get(explosive, 0) + 1
		bonus_hist[bonus] = bonus_hist.get(bonus, 0) + 1
		layer_hist[layout["layers"]] = layer_hist.get(layout["layers"], 0) + 1

		_check_support(seed_value, blocks)
		_check_spread(seed_value, layout)

		if not _specials_in_multiple_quadrants(layout):
			quadrant_single += 1

		_check_geometry(seed_value, generator, layout, transforms, metrics, area)

		signatures[str(blocks)] = true

	var tested := seeds.size()

	print("Siemeniä testattu: %d" % tested)
	print("Erilaisia asetteluja: %d" % signatures.size())
	print("Palikoita: %d-%d" % [count_min, count_max])
	print("Kerroksia (määrä: siemenet): ", layer_hist)
	print("Räjähtäviä (määrä: siemenet): ", explosive_hist)
	print("Bonuksia (määrä: siemenet): ", bonus_hist)
	print("Erikoisosuus: min %.3f, max %.3f, ka %.3f" % [ratio_min, ratio_max, ratio_sum / tested])
	print("Erikoismäärä poikkesi pyöristetystä 30 %%:sta: %d siemenellä" % off_target)
	print("Varamalli käytössä: %d, yrityksiä enintään: %d" % [fallbacks, max_attempts])
	print("Erikoispalikat yhdessä neljänneksessä: %d" % quadrant_single)

	if signatures.size() < tested * 0.9:
		_fail("Liian vähän erilaisia asetteluja: %d" % signatures.size())

	_check_special_counts(generator)

	generator.free()
	_finish()


## Kaikki palikkamäärät generaattorin rajoissa, ei vain arvotut.
func _check_special_counts(generator: LevelGenerator) -> void:
	for total in range(generator.min_blocks, generator.max_blocks + 1):
		var counts := generator.calculate_special_counts(total)
		var special: int = counts["explosive"] + counts["bonus"]

		if counts["explosive"] < 2 or counts["explosive"] > 8 or counts["bonus"] < 2 or counts["bonus"] > 5:
			_fail("Palikkamäärä %d: rajat ylittyvät %s" % [total, counts])

		if absf(float(special) / total - generator.special_ratio) > 0.5 / total + EPSILON:
			_fail("Palikkamäärä %d: osuus %.3f liian kaukana tavoitteesta" % [total, float(special) / total])

	print("Erikoismäärät tarkistettu palikkamäärille %d-%d" % [generator.min_blocks, generator.max_blocks])


func _check_support(seed_value: int, blocks: Array) -> void:
	var occupied := {}

	for block in blocks:
		var key := Vector3i(block["x"], block["layer"], block["z"])

		if occupied.has(key):
			_fail("Siemen %d: sama solu kahdesti %s" % [seed_value, key])

		occupied[key] = true

	for block in blocks:
		if block["layer"] > 0 and not occupied.has(Vector3i(block["x"], block["layer"] - 1, block["z"])):
			_fail("Siemen %d: tukematon palikka %s" % [seed_value, block])


## Erikoispalikat eivät saa olla pelkästään tornin yläosassa.
func _check_spread(seed_value: int, layout: Dictionary) -> void:
	var bands := {}

	for block in layout["blocks"]:
		if block["type"] != LevelGenerator.TYPE_NORMAL:
			bands[LevelGenerator.get_band(block["layer"], layout["layers"])] = true

	if layout["layers"] >= 2 and bands.size() < 2:
		_fail("Siemen %d: erikoispalikat vain yhdellä vyöhykkeellä" % seed_value)


func _specials_in_multiple_quadrants(layout: Dictionary) -> bool:
	var blocks: Array = layout["blocks"]
	var chosen: Array = []

	for i in blocks.size():
		if blocks[i]["type"] != LevelGenerator.TYPE_NORMAL:
			chosen.append(i)

	var cells: Array = []

	for block in blocks:
		cells.append(Vector3i(block["x"], block["layer"], block["z"]))

	return LevelGenerator._quadrant_count(chosen, cells, layout["width"], layout["depth"]) > 1


## Törmäysmuodot ja näkyvät mallit eivät mene päällekkäin, torni on maassa ja alueella.
func _check_geometry(
	seed_value: int,
	generator: LevelGenerator,
	layout: Dictionary,
	transforms: Array,
	metrics: Dictionary,
	area: Dictionary
) -> void:
	var collision_size: Vector3 = metrics["collision_size"]
	var visual_size: Vector3 = metrics["visual_size"]
	var offset: Vector3 = metrics["collision_offset"]
	var basis := Basis(Vector3.UP, deg_to_rad(generator.tower_yaw_degrees))
	var inverse := basis.inverse()

	var collision_boxes: Array = []
	var visual_boxes: Array = []
	var lowest := INF

	for i in transforms.size():
		var body: Transform3D = transforms[i]

		if not body.basis.is_equal_approx(basis):
			_fail("Siemen %d: palikan %d kierto väärä" % [seed_value, i])

		var center := body * offset
		lowest = minf(lowest, center.y - collision_size.y * 0.5)

		# Kaikilla palikoilla on sama kierto, joten vertailu tehdään tornin koordinaatistossa.
		var local := inverse * center
		collision_boxes.append(AABB(local - collision_size * 0.5, collision_size))
		visual_boxes.append(AABB(local - visual_size * 0.5, visual_size))

		for corner_index in 8:
			var corner := basis * (collision_boxes[i] as AABB).get_endpoint(corner_index)
			var margin := generator.area_margin

			if corner.x < area["min"].x + margin or corner.x > area["max"].x - margin \
					or corner.z < area["min"].y + margin or corner.z > area["max"].y - margin:
				_fail("Siemen %d: palikka %d pelialueen ulkopuolella" % [seed_value, i])
				break

	for i in collision_boxes.size():
		for j in range(i + 1, collision_boxes.size()):
			if _overlaps(collision_boxes[i], collision_boxes[j]):
				_fail("Siemen %d: törmäysmuodot %d ja %d päällekkäin" % [seed_value, i, j])

			# Näkyvä malli on törmäysmuotoa vähän korkeampi, joten pystysuunnassa sallitaan
			# sama pieni limitys kuin pinotuissa palikoissa yleensä; vaakasuunnassa ei.
			var a: AABB = visual_boxes[i]
			var b: AABB = visual_boxes[j]

			if _same_layer(layout, i, j) and _overlaps(a, b):
				_fail("Siemen %d: mallit %d ja %d päällekkäin" % [seed_value, i, j])

	var expected_bottom: float = area["top"] + generator.ground_clearance

	if absf(lowest - expected_bottom) > EPSILON:
		_fail("Siemen %d: alin palikka korkeudella %.4f, odotettiin %.4f" % [seed_value, lowest, expected_bottom])


func _same_layer(layout: Dictionary, i: int, j: int) -> bool:
	return layout["blocks"][i]["layer"] == layout["blocks"][j]["layer"]


func _overlaps(a: AABB, b: AABB) -> bool:
	return a.position.x < b.end.x - EPSILON and b.position.x < a.end.x - EPSILON \
		and a.position.y < b.end.y - EPSILON and b.position.y < a.end.y - EPSILON \
		and a.position.z < b.end.z - EPSILON and b.position.z < a.end.z - EPSILON


func _count_type(blocks: Array, type: int) -> int:
	var count := 0

	for block in blocks:
		if block["type"] == type:
			count += 1

	return count


## Maan mitat luetaan random_level.tscn:stä ilman kohtauksen käynnistämistä.
func _ground_area_from_scene() -> Dictionary:
	var scene := (load("res://scenes/levels/random_level.tscn") as PackedScene).instantiate()
	var edge := scene.get_node("WorldEdge") as Node3D
	var ground := edge.get_node("CollisionShape3D") as CollisionShape3D
	var size := (ground.shape as BoxShape3D).size
	var center := (edge.transform * ground.transform).origin
	scene.free()

	return {
		"top": center.y + size.y * 0.5,
		"min": Vector2(center.x - size.x * 0.5, center.z - size.z * 0.5),
		"max": Vector2(center.x + size.x * 0.5, center.z + size.z * 0.5),
	}


func _fail(message: String) -> void:
	if failures.size() < 50:
		printerr("VIRHE: " + message)

	failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("GENERAATTORITESTIT: OK")
		quit(0)
	else:
		print("GENERAATTORITESTIT: %d virhettä" % failures.size())
		quit(1)
