extends Node

## Pelaajan edistyminen: kenttien parhaat tulokset, tähdet ja läpäisyt.
## Tallennetaan versioituna JSON-tiedostona user://-hakemistoon.
## Kentän avautuminen johdetaan edellisen kentän läpäisystä, sitä ei tallenneta erikseen.

const SAVE_PATH := "user://save_data.json"
const TEMP_PATH := "user://save_data.tmp"
const CORRUPT_PATH := "user://save_data.corrupt.json"
const SAVE_VERSION := 1

## Kenttien järjestys määrää avautumisjärjestyksen.
## Tunniste (id) pysyy samana, vaikka scenetiedosto siirrettäisiin.
const LEVELS := [
	{
		"id": "level_1",
		"name": "Kenttä 1 - Perustorni",
		"path": "res://scenes/root.tscn",
	},
	{
		"id": "level_2",
		"name": "Kenttä 2 - Haastava torni",
		"path": "res://scenes/levels/level_2.tscn",
	},
]

## Varoitus viimeisimmästä latauksesta. Tyhjä, jos kaikki meni hyvin.
var load_warning: String = ""

var _data: Dictionary = {}

# Tosi, kun tallennusta ei saa kirjoittaa yli (esim. uudemman version tallennus).
var _read_only: bool = false


func _ready() -> void:
	load_game()


func load_game() -> void:
	_data = _default_data()
	_read_only = false
	load_warning = ""

	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)

	if file == null:
		# Tiedosto on olemassa, mutta sitä ei voi lukea: älä kirjoita sen päälle.
		_read_only = true
		_warn("Tallennusta ei voitu lukea (virhe %d). Edistymistä ei tallenneta tällä kertaa." % FileAccess.get_open_error())
		return

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()

	var parsed: Variant = json.data

	if parse_error != OK or typeof(parsed) != TYPE_DICTIONARY or not _is_number(parsed.get("version")):
		_backup_corrupt_file()
		return

	if int(parsed["version"]) > SAVE_VERSION:
		_read_only = true
		_warn("Tallennus on tehty uudemmalla pelin versiolla. Edistymistä ei tallenneta tällä kertaa.")
		return

	var levels: Variant = parsed.get("levels", {})

	if typeof(levels) != TYPE_DICTIONARY:
		return

	# Tuntemattomat kentät säilytetään, jotta niiden tiedot eivät katoa.
	for level_id in levels:
		if typeof(level_id) == TYPE_STRING and typeof(levels[level_id]) == TYPE_DICTIONARY:
			_data["levels"][level_id] = _sanitize_record(levels[level_id])


func save_game() -> bool:
	if _read_only:
		push_warning("SaveManager: tallennus ohitettu, koska tallennustiedostoa ei saa korvata.")
		return false

	# Kirjoitetaan ensin väliaikaiseen tiedostoon, ettei keskeytynyt kirjoitus riko tallennusta.
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)

	if file == null:
		push_error("SaveManager: tallennus epäonnistui, virhekoodi: %d" % FileAccess.get_open_error())
		return false

	var written := file.store_string(JSON.stringify(_data, "\t"))
	file.close()

	if not written:
		push_error("SaveManager: tallennustiedoston kirjoittaminen epäonnistui.")
		return false

	var error := DirAccess.rename_absolute(TEMP_PATH, SAVE_PATH)

	if error != OK:
		push_error("SaveManager: tallennustiedoston korvaaminen epäonnistui, virhekoodi: %d" % error)
		return false

	return true


## Päivittää kentän ennätykset läpäisyn jälkeen. Huonompi tulos ei koskaan korvaa parempaa.
## Palauttaa tiedon uusista ennätyksistä.
func update_level_record(level_id: String, score: int, stars: int) -> Dictionary:
	var result := {
		"new_best_score": false,
		"new_best_stars": false,
		"saved": false,
	}

	# Vain läpäisy (vähintään yksi tähti) kirjataan.
	if get_level_index(level_id) < 0 or stars <= 0:
		return result

	var record := get_level_data(level_id)

	if score > record["best_score"]:
		record["best_score"] = clampi(score, 0, 100)
		result["new_best_score"] = true

	if stars > record["best_stars"]:
		record["best_stars"] = clampi(stars, 0, 3)
		result["new_best_stars"] = true

	record["completed"] = true
	_data["levels"][level_id] = record
	result["saved"] = save_game()

	return result


func get_level_data(level_id: String) -> Dictionary:
	return _data["levels"].get(level_id, _default_record()).duplicate()


func get_best_score(level_id: String) -> int:
	return get_level_data(level_id)["best_score"]


func get_best_stars(level_id: String) -> int:
	return get_level_data(level_id)["best_stars"]


func is_level_completed(level_id: String) -> bool:
	return get_level_data(level_id)["completed"]


func is_level_unlocked(level_id: String) -> bool:
	var index := get_level_index(level_id)

	if index < 0:
		return false

	if index == 0:
		return true

	return is_level_completed(LEVELS[index - 1]["id"])


func get_level_index(level_id: String) -> int:
	for i in LEVELS.size():
		if LEVELS[i]["id"] == level_id:
			return i

	return -1


func get_level_path(level_id: String) -> String:
	var index := get_level_index(level_id)
	return LEVELS[index]["path"] if index >= 0 else ""


func get_level_id_for_scene(scene_path: String) -> String:
	for level in LEVELS:
		if level["path"] == scene_path:
			return level["id"]

	return ""


## Palauttaa seuraavan kentän tunnisteen tai tyhjän, jos kyseessä on viimeinen kenttä.
func get_next_level_id(level_id: String) -> String:
	var index := get_level_index(level_id)

	if index < 0 or index + 1 >= LEVELS.size():
		return ""

	return LEVELS[index + 1]["id"]


## Ensimmäinen avattu kenttä, jota ei ole vielä läpäisty. Muuten ensimmäinen kenttä.
func get_first_open_level_id() -> String:
	for level in LEVELS:
		if is_level_unlocked(level["id"]) and not is_level_completed(level["id"]):
			return level["id"]

	return LEVELS[0]["id"]


func format_stars(stars: int) -> String:
	var count := clampi(stars, 0, 3)
	return "★".repeat(count) + "☆".repeat(3 - count)


func _default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"levels": {},
	}


func _default_record() -> Dictionary:
	return {
		"completed": false,
		"best_score": 0,
		"best_stars": 0,
	}


func _sanitize_record(raw: Dictionary) -> Dictionary:
	var completed: Variant = raw.get("completed")
	var score: Variant = raw.get("best_score")
	var stars: Variant = raw.get("best_stars")

	return {
		"completed": typeof(completed) == TYPE_BOOL and completed,
		"best_score": clampi(int(score), 0, 100) if _is_number(score) else 0,
		"best_stars": clampi(int(stars), 0, 3) if _is_number(stars) else 0,
	}


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


# Rikkinäinen tiedosto kopioidaan talteen ennen kuin uusi tallennus voi korvata sen.
func _backup_corrupt_file() -> void:
	var error := DirAccess.copy_absolute(SAVE_PATH, CORRUPT_PATH)

	if error != OK:
		_read_only = true
		_warn("Tallennus on vioittunut, eikä sitä voitu varmuuskopioida. Edistymistä ei tallenneta tällä kertaa.")
		return

	_warn("Tallennus oli vioittunut, joten aloitetaan alusta. Vanha tiedosto: %s" % CORRUPT_PATH)


func _warn(message: String) -> void:
	load_warning = message
	push_warning("SaveManager: " + message)
