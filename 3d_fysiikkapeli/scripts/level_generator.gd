class_name LevelGenerator
extends Node

## Satunnaisen kentän tornigeneraattori.
## Torni rakennetaan kerroksittain ruudukkoon: leveä pohja, ylöspäin kapeneva runko ja
## siemenestä riippuvat aukot. Palikka sijoitetaan vain toisen palikan päälle, joten
## tornissa ei ole tukemattomia ulokkeita.
##
## Kaikki satunnaisuus tulee yhdestä siemennetystä RandomNumberGenerator-oliosta, joten
## sama siemen ja samat asetukset tuottavat aina saman alkuasettelun.
## Globaaleja satunnaisfunktioita (randi, Array.shuffle) ei käytetä generoinnissa.

## Kasvata, jos generoinnin tulos muuttuu samalla siemenellä.
const GENERATOR_VERSION := 1

const BOX_SCENE := preload("res://scenes/box.tscn")

## Palikkatyypit box.gd:n BlockType-enumista.
const TYPE_NORMAL := 0
const TYPE_BONUS := 1
const TYPE_EXPLOSIVE := 2

## Kerrosvyöhykkeet erikoispalikoiden jakamiseen (ala-, keski- ja yläosa).
const BAND_COUNT := 3

@export_group("Tornin koko")
@export var min_width: int = 3
@export var max_width: int = 5
@export var min_depth: int = 2
@export var max_depth: int = 4
@export var min_layers: int = 3
@export var max_layers: int = 5
## Todennäköisyys, että kerros kapenee yhdellä ruudulla kummallakin akselilla.
@export_range(0.0, 1.0) var taper_chance: float = 0.45
## Todennäköisyys, että tuettu ruutu jätetään tyhjäksi (ei koske pohjakerrosta).
@export_range(0.0, 1.0) var gap_chance: float = 0.12
@export var min_blocks: int = 14
@export var max_blocks: int = 40
## Yritykset sopivan kokoisen tornin löytämiseksi ennen varamallia.
@export var max_attempts: int = 64

@export_group("Erikoispalikat")
## Tavoiteosuus erikoispalikoille (räjähtävät + bonus) kaikista palikoista.
@export_range(0.0, 1.0) var special_ratio: float = 0.30
## Räjähtävien osuus erikoispalikoista ennen rajojen soveltamista.
@export_range(0.0, 1.0) var explosive_share: float = 0.55
@export var min_explosive: int = 2
@export var max_explosive: int = 8
@export var min_bonus: int = 2
@export var max_bonus: int = 5
## Uudelleenvalinnat, jos kaikki erikoispalikat osuvat samaan neljännekseen.
@export var special_spread_attempts: int = 8

@export_group("Sijoittelu")
## Tornin pohjan keskipiste maailmassa (y luetaan maasta).
@export var tower_center: Vector3 = Vector3(-5.3, 0.0, -0.2)
## Tornin kierto pystyakselin ympäri, sama kuin käsin tehdyissä kentissä.
@export var tower_yaw_degrees: float = -13.16
## Vaakaväli palikoiden välillä törmäys- ja näkyvän koon suuremman lisäksi.
@export var cell_gap: float = 0.04
## Pystyväli kerrosten välillä, jotta törmäysmuodot eivät ala sisäkkäin.
@export var layer_gap: float = 0.01
## Alimman kerroksen etäisyys maasta.
@export var ground_clearance: float = 0.01
## Pelialueen reunan ja tornin väliin jätettävä vähimmäistila.
@export var area_margin: float = 1.0

@export_group("Kohtaus")
@export var boxes_parent: NodePath = ^"../Boxes"
@export var ground_shape: NodePath = ^"../WorldEdge/CollisionShape3D"


## Laskee palikan mitat box.tscn:stä: törmäysmuodon koon ja paikallisen siirron sekä
## näkyvän mallin rajat palikan omassa koordinaatistossa.
static func measure_block() -> Dictionary:
	var template := BOX_SCENE.instantiate() as Node3D
	var collision := template.get_node("CollisionShape3D") as CollisionShape3D
	var box_shape := collision.shape as BoxShape3D

	var visual := AABB()
	var has_visual := false

	for mesh_node in template.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D

		if mesh_instance.mesh == null:
			continue

		var aabb := _transform_to(template, mesh_instance) * mesh_instance.mesh.get_aabb()
		visual = aabb if not has_visual else visual.merge(aabb)
		has_visual = true

	var metrics := {
		"collision_size": box_shape.size,
		"collision_offset": collision.position,
		"visual_size": visual.size if has_visual else box_shape.size,
	}

	template.free()
	return metrics


## Kertoo solmun muunnoksen esivanhemman koordinaatistossa ilman, että solmu on puussa.
static func _transform_to(ancestor: Node, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node

	while current != ancestor and current is Node3D:
		result = (current as Node3D).transform * result
		current = current.get_parent()

	return result


## Generoi tornin, lisää palikat kohtaukseen ja palauttaa asettelun tiedot.
## Kutsutaan ennen kuin pisteytys, ajastin ja syöte käsittelevät kenttää.
func generate(seed_value: int) -> Dictionary:
	var parent := get_node(boxes_parent)
	var ground := get_node(ground_shape) as CollisionShape3D
	var area := get_ground_area(ground)

	var layout := generate_layout(seed_value)
	var transforms := compute_transforms(layout, measure_block(), area["top"])
	layout["transforms"] = transforms
	layout["area"] = area

	var blocks: Array = layout["blocks"]

	for i in blocks.size():
		var box := BOX_SCENE.instantiate() as RigidBody3D
		box.name = "GeneratedBox%d" % i
		box.set("block_type", blocks[i]["type"])
		# Muunnos asetetaan ennen puuhun lisäämistä, jotta fysiikka alkaa oikeasta kohdasta.
		box.transform = transforms[i]
		parent.add_child(box)

	return layout


## Maan yläpinnan korkeus ja vaakarajat maailmassa (maa on akselien suuntainen laatikko).
static func get_ground_area(ground: CollisionShape3D) -> Dictionary:
	var size := (ground.shape as BoxShape3D).size
	var center := ground.global_position

	return {
		"top": center.y + size.y * 0.5,
		"min": Vector2(center.x - size.x * 0.5, center.z - size.z * 0.5),
		"max": Vector2(center.x + size.x * 0.5, center.z + size.z * 0.5),
	}


## Puhdas asettelu ilman solmuja: kerrosruudukko ja palikkatyypit.
## Palauttaa {seed, version, width, depth, layers, attempts, used_fallback,
## blocks: [{layer, x, z, type}], explosive_count, bonus_count}.
func generate_layout(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var shape := _generate_shape(rng)
	var cells: Array = shape["cells"]
	var counts := calculate_special_counts(cells.size())

	var types := _assign_types(rng, cells, shape["layers"], shape["width"], shape["depth"], counts)

	var blocks: Array = []

	for i in cells.size():
		var cell: Vector3i = cells[i]
		blocks.append({"layer": cell.y, "x": cell.x, "z": cell.z, "type": types[i]})

	return {
		"seed": seed_value,
		"version": GENERATOR_VERSION,
		"width": shape["width"],
		"depth": shape["depth"],
		"layers": shape["layers"],
		"attempts": shape["attempts"],
		"used_fallback": shape["used_fallback"],
		"blocks": blocks,
		"explosive_count": counts["explosive"],
		"bonus_count": counts["bonus"],
	}


## Erikoispalikoiden määrät palikkamäärän mukaan:
## tavoite = special_ratio * kaikki, räjähtävät ja bonukset rajataan vaadittuihin väleihin.
func calculate_special_counts(total: int) -> Dictionary:
	var target := roundi(total * special_ratio)

	var explosive := clampi(roundi(target * explosive_share), min_explosive, max_explosive)
	var bonus := clampi(target - explosive, min_bonus, max_bonus)

	# Jos bonusten yläraja tuli vastaan, vajaus täytetään räjähtävillä.
	if explosive + bonus < target:
		explosive = mini(max_explosive, target - bonus)

	# Erikoispalikoita ei voi olla enemmän kuin palikoita.
	while explosive + bonus > total and explosive > 0:
		if explosive >= bonus:
			explosive -= 1
		else:
			bonus -= 1

	return {
		"explosive": explosive,
		"bonus": bonus,
		"normal": total - explosive - bonus,
	}


## Kerroksittainen muoto. Solut ovat Vector3i(x, kerros, z) ruudukon koordinaateissa.
func _generate_shape(rng: RandomNumberGenerator) -> Dictionary:
	for attempt in max_attempts:
		var width := rng.randi_range(min_width, max_width)
		var depth := rng.randi_range(min_depth, max_depth)
		var layer_count := rng.randi_range(min_layers, max_layers)

		var cells: Array = []
		var below := {}

		# Kerroksen alue [x0, x1) x [z0, z1). Ylempi alue on aina alemman sisällä.
		var x0 := 0
		var x1 := width
		var z0 := 0
		var z1 := depth
		var built_layers := 0

		for layer in layer_count:
			if layer > 0:
				if x1 - x0 > 1 and rng.randf() < taper_chance:
					if rng.randf() < 0.5:
						x0 += 1
					else:
						x1 -= 1

				if z1 - z0 > 1 and rng.randf() < taper_chance:
					if rng.randf() < 0.5:
						z0 += 1
					else:
						z1 -= 1

			var current := {}

			for x in range(x0, x1):
				for z in range(z0, z1):
					var key := Vector2i(x, z)

					# Ylemmissä kerroksissa palikka tarvitsee alleen palikan.
					if layer > 0 and not below.has(key):
						continue

					if layer > 0 and rng.randf() < gap_chance:
						continue

					current[key] = true
					cells.append(Vector3i(x, layer, z))

			if current.is_empty():
				break

			below = current
			built_layers = layer + 1

		if cells.size() >= min_blocks and cells.size() <= max_blocks:
			return {
				"cells": cells,
				"width": width,
				"depth": depth,
				"layers": built_layers,
				"attempts": attempt + 1,
				"used_fallback": false,
			}

	return _fallback_shape()


## Varamalli: säännöllinen ruudukko, joka täyttää kokorajat. Ei käytä satunnaisuutta.
func _fallback_shape() -> Dictionary:
	var width := clampi(4, min_width, max_width)
	var depth := clampi(3, min_depth, max_depth)
	var per_layer := width * depth
	var layer_count := clampi(ceili(float(min_blocks) / per_layer), 1, maxi(1, floori(float(max_blocks) / per_layer)))

	var cells: Array = []

	for layer in layer_count:
		for x in width:
			for z in depth:
				cells.append(Vector3i(x, layer, z))

	return {
		"cells": cells,
		"width": width,
		"depth": depth,
		"layers": layer_count,
		"attempts": max_attempts,
		"used_fallback": true,
	}


## Jakaa erikoispalikat kerrosvyöhykkeisiin vyöhykkeen koon suhteessa, jotta ne eivät
## kasaannu pelkästään huipulle. Vyöhykkeen sisällä paikka arvotaan.
func _assign_types(
	rng: RandomNumberGenerator,
	cells: Array,
	layer_count: int,
	width: int,
	depth: int,
	counts: Dictionary
) -> Array:
	var total := cells.size()
	var special_total: int = counts["explosive"] + counts["bonus"]

	var bands: Array = []

	for band in BAND_COUNT:
		bands.append([])

	for i in total:
		var cell: Vector3i = cells[i]
		bands[get_band(cell.y, layer_count)].append(i)

	var quotas := _band_quotas(bands, special_total, total)

	var chosen: Array = []

	for attempt in maxi(special_spread_attempts, 1):
		chosen.clear()

		for band in BAND_COUNT:
			var indices: Array = bands[band].duplicate()
			shuffle(rng, indices)
			chosen.append_array(indices.slice(0, quotas[band]))

		if _quadrant_count(chosen, cells, width, depth) > 1:
			break

	var special_types: Array = []

	for i in counts["explosive"]:
		special_types.append(TYPE_EXPLOSIVE)

	for i in counts["bonus"]:
		special_types.append(TYPE_BONUS)

	shuffle(rng, special_types)

	var types: Array = []
	types.resize(total)
	types.fill(TYPE_NORMAL)

	for i in chosen.size():
		types[chosen[i]] = special_types[i]

	return types


## Jokainen ei-tyhjä vyöhyke saa ensin yhden erikoispalikan (jos niitä riittää), loput
## jaetaan vyöhykkeiden koon suhteessa suurimman jakojäännöksen menetelmällä.
## Kiintiöiden summa on aina special_total.
func _band_quotas(bands: Array, special_total: int, total: int) -> Array:
	var quotas: Array = []
	var remainders: Array = []
	var non_empty := 0

	for band in BAND_COUNT:
		if not bands[band].is_empty():
			non_empty += 1

	var guaranteed := 1 if special_total >= non_empty else 0
	var assigned := 0

	for band in BAND_COUNT:
		var band_size: int = bands[band].size()
		var base := mini(guaranteed, band_size)
		assigned += base

	var remaining := special_total - assigned

	for band in BAND_COUNT:
		var band_size: int = bands[band].size()
		var base := mini(guaranteed, band_size)
		var exact := base + float(remaining) * band_size / maxf(total, 1)
		var quota := mini(floori(exact), band_size)
		quotas.append(quota)
		remainders.append([exact - quota, band])

	assigned = 0

	for quota in quotas:
		assigned += quota

	# Isoin jäännös ensin, tasatilanteessa alempi vyöhyke ensin.
	remainders.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))

	var index := 0

	while assigned < special_total:
		var band: int = remainders[index % BAND_COUNT][1]

		if quotas[band] < bands[band].size():
			quotas[band] += 1
			assigned += 1

		index += 1

	return quotas


static func get_band(layer: int, layer_count: int) -> int:
	return clampi(floori(float(layer * BAND_COUNT) / maxi(layer_count, 1)), 0, BAND_COUNT - 1)


## Monessako tornin neljänneksessä valitut palikat ovat (keskilinjan solut lasketaan molempiin).
static func _quadrant_count(chosen: Array, cells: Array, width: int, depth: int) -> int:
	var quadrants := {}
	var center_x := (width - 1) * 0.5
	var center_z := (depth - 1) * 0.5

	for i in chosen:
		var cell: Vector3i = cells[i]

		for qx in ([-1, 1] if cell.x == center_x else [int(signf(cell.x - center_x))]):
			for qz in ([-1, 1] if cell.z == center_z else [int(signf(cell.z - center_z))]):
				quadrants[Vector2i(qx, qz)] = true

	return quadrants.size()


## Fisher-Yates-sekoitus annetulla generaattorilla (Array.shuffle käyttäisi globaalia).
static func shuffle(rng: RandomNumberGenerator, array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp: Variant = array[i]
		array[i] = array[j]
		array[j] = temp


## Palikoiden runkojen muunnokset. Törmäysmuodon keskipiste lasketaan ruudukosta ja
## rungon origo siirretään box.tscn:n paikallisen siirron (1, 1, 1) verran.
func compute_transforms(layout: Dictionary, metrics: Dictionary, ground_top: float) -> Array:
	var collision_size: Vector3 = metrics["collision_size"]
	var visual_size: Vector3 = metrics["visual_size"]
	var offset: Vector3 = metrics["collision_offset"]

	var pitch_x := maxf(collision_size.x, visual_size.x) + cell_gap
	var pitch_z := maxf(collision_size.z, visual_size.z) + cell_gap
	var pitch_y := collision_size.y + layer_gap

	var basis := Basis(Vector3.UP, deg_to_rad(tower_yaw_degrees))
	var half_width := (int(layout["width"]) - 1) * 0.5
	var half_depth := (int(layout["depth"]) - 1) * 0.5
	var base_y := ground_top + ground_clearance + collision_size.y * 0.5

	var transforms: Array = []

	for block in layout["blocks"]:
		var local := Vector3(
			(block["x"] - half_width) * pitch_x,
			0.0,
			(block["z"] - half_depth) * pitch_z
		)

		var center := Vector3(tower_center.x, base_y + block["layer"] * pitch_y, tower_center.z) + basis * local
		transforms.append(Transform3D(basis, center - basis * offset))

	return transforms
