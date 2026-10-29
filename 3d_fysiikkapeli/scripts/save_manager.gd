extends Node

## Pelaajan edistyminen: kenttien parhaat tulokset, tähdet ja läpäisyt sekä
## satunnaisen pelimuodon paras putki (random_mode), joka pidetään erillään kenttien tuloksista.
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

## Tallennuspolut muuttujina, jotta testit voivat ohjata tallennuksen väliaikaiseen tiedostoon.
var save_path: String = SAVE_PATH
var temp_path: String = TEMP_PATH
var corrupt_path: String = CORRUPT_PATH

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

	if not FileAccess.file_exists(save_path):
		return

	var file := FileAccess.open(save_path, FileAccess.READ)

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

	# Vanhoissa tallennuksissa random_mode puuttuu, jolloin käytetään oletusarvoja.
	var random_mode: Variant = parsed.get("random_mode", {})

	if typeof(random_mode) == TYPE_DICTIONARY:
		_data["random_mode"] = _sanitize_random_mode(random_mode)

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
	var file := FileAccess.open(temp_path, FileAccess.WRITE)

	if file == null:
		push_error("SaveManager: tallennus epäonnistui, virhekoodi: %d" % FileAccess.get_open_error())
		return false

	var written := file.store_string(JSON.stringify(_data, "\t"))
	file.close()

	if not written:
		push_error("SaveManager: tallennustiedoston kirjoittaminen epäonnistui.")
		return false

	var error := DirAccess.rename_absolute(temp_path, save_path)

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


## Päivittää satunnaisen pelimuodon parhaan putken. Huonompi putki ei koskaan korvaa parempaa.
## Palauttaa true, jos putki on uusi ennätys.
func update_best_streak(streak: int) -> bool:
	if streak <= get_best_streak():
		return false

	_data["random_mode"]["best_streak"] = streak
	save_game()
	return true


func get_best_streak() -> int:
	return _data["random_mode"]["best_streak"]


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
		"random_mode": _default_random_mode(),
	}


func _default_random_mode() -> Dictionary:
	return {
		"best_streak": 0,
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


func _sanitize_random_mode(raw: Dictionary) -> Dictionary:
	var best: Variant = raw.get("best_streak")

	return {
		"best_streak": maxi(int(best), 0) if _is_number(best) else 0,
	}


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


# Rikkinäinen tiedosto kopioidaan talteen ennen kuin uusi tallennus voi korvata sen.
func _backup_corrupt_file() -> void:
	var error := DirAccess.copy_absolute(save_path, corrupt_path)

	if error != OK:
		_read_only = true
		_warn("Tallennus on vioittunut, eikä sitä voitu varmuuskopioida. Edistymistä ei tallenneta tällä kertaa.")
		return

	_warn("Tallennus oli vioittunut, joten aloitetaan alusta. Vanha tiedosto: %s" % corrupt_path)


func _warn(message: String) -> void:
	load_warning = message
	push_warning("SaveManager: " + message)
