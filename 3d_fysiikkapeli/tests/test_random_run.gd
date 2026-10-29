extends SceneTree

## Putken ja tallennuksen testit. Käyttää väliaikaista tallennustiedostoa, joten
## pelaajan oikeaa tallennusta ei kirjoiteta.
## Ajo: godot --headless --path . -s res://tests/test_random_run.gd

const TEST_SAVE := "user://test_random_run_save.json"
const TEST_TEMP := "user://test_random_run_save.tmp"
const TEST_CORRUPT := "user://test_random_run_save.corrupt.json"
const REAL_SAVE := "user://save_data.json"

var failures: Array[String] = []
var save_manager: Node
var random_run: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Autoloadit haetaan ajon aikana, koska -s-skripti käännetään ennen niiden rekisteröintiä.
	save_manager = root.get_node("SaveManager")
	random_run = root.get_node("RandomRun")

	var real_hash := FileAccess.get_md5(REAL_SAVE) if FileAccess.file_exists(REAL_SAVE) else "(ei tiedostoa)"

	save_manager.save_path = TEST_SAVE
	save_manager.temp_path = TEST_TEMP
	save_manager.corrupt_path = TEST_CORRUPT
	_remove_test_files()
	save_manager.load_game()

	_test_streak_flow()
	_test_persistence()
	_test_backward_compatibility()
	_test_parse_seed()

	_remove_test_files()

	var real_hash_after := FileAccess.get_md5(REAL_SAVE) if FileAccess.file_exists(REAL_SAVE) else "(ei tiedostoa)"
	_check(real_hash == real_hash_after, "oikea tallennus ei muuttunut")
	print("Oikean tallennuksen tarkiste: ", real_hash)

	_finish()


func _test_streak_flow() -> void:
	random_run.start_run(1234)
	_check(random_run.streak == 0, "uusi juoksu alkaa putkesta 0")
	_check(random_run.current_seed == 1234, "syötetty siemen käytössä")
	_check(not random_run.advance(), "kesken olevasta kentästä ei voi siirtyä seuraavaan")
	_check(not random_run.retry(), "kesken olevaa kenttää ei voi uusia")

	_check(random_run.record_success(), "ensimmäinen läpäisy on uusi ennätys")
	_check(random_run.streak == 1, "läpäisy nostaa putken yhteen")
	_check(save_manager.get_best_streak() == 1, "paras putki 1 tallessa")

	_check(not random_run.record_success(), "samaa kenttää ei voi kirjata kahdesti")
	_check(random_run.streak == 1, "putki ei kasva toistolla")
	_check(not random_run.retry(), "läpäistyä kenttää ei voi uusia")
	_check(random_run.streak == 1, "putki säilyy, kun uusinta estetään")

	var first_seed: int = random_run.current_seed
	_check(random_run.advance(), "läpäisyn jälkeen voi jatkaa")
	_check(random_run.current_seed != first_seed, "seuraava kenttä saa uuden siemenen")

	random_run.record_success()
	random_run.advance()
	random_run.record_success()
	_check(random_run.streak == 3, "kolme läpäisyä peräkkäin = putki 3")
	_check(save_manager.get_best_streak() == 3, "paras putki 3")

	random_run.advance()
	var failed_seed: int = random_run.current_seed
	random_run.record_failure()
	_check(random_run.streak == 3, "epäonnistuminen ei kasvata putkea")
	_check(not random_run.record_success(), "epäonnistunutta kenttää ei voi kirjata läpäistyksi")
	_check(not random_run.advance(), "epäonnistumisen jälkeen ei voi jatkaa")
	_check(random_run.run_new_record, "juoksu teki ennätyksen")

	_check(random_run.retry(), "epäonnistumisen jälkeen voi yrittää uudelleen")
	_check(random_run.streak == 0, "uusinta aloittaa uuden juoksun")
	_check(random_run.current_seed == failed_seed, "uusinta käyttää samaa siementä")
	_check(not random_run.run_new_record, "uuden juoksun ennätyslippu nollattu")

	random_run.record_success()
	random_run.advance()
	random_run.record_failure()
	_check(save_manager.get_best_streak() == 3, "huonompi juoksu ei korvaa ennätystä")
	_check(not random_run.run_new_record, "huonompi juoksu ei ole ennätys")

	random_run.end_run()
	_check(random_run.streak == 0 and not random_run.active, "valikkoon palaaminen nollaa putken")
	_check(save_manager.get_best_streak() == 3, "valikkoon palaaminen säilyttää ennätyksen")

	random_run.start_run()
	_check(random_run.streak == 0, "uusi juoksu valikosta alkaa nollasta")
	random_run.end_run()

	_check(save_manager.get_level_data("level_1")["best_stars"] == 0, "satunnaistila ei anna tähtiä kentälle 1")
	_check(not save_manager.is_level_completed("level_1"), "satunnaistila ei merkitse kenttää läpäistyksi")
	_check(not save_manager.is_level_unlocked("level_2"), "satunnaistila ei avaa kenttää 2")


func _test_persistence() -> void:
	save_manager.load_game()
	_check(save_manager.get_best_streak() == 3, "paras putki säilyy latauksen yli")

	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	_check(typeof(data) == TYPE_DICTIONARY, "tallennus on JSON-sanakirja")
	_check(data["version"] == 1.0, "SAVE_VERSION pysyi 1:nä")
	_check(data["random_mode"]["best_streak"] == 3.0, "random_mode.best_streak tallennettu")
	_check((data["levels"] as Dictionary).is_empty(), "satunnaistila ei kirjoita kenttätuloksia")

	_check(not save_manager.update_best_streak(2), "pienempi putki ei päivitä")
	_check(save_manager.update_best_streak(4), "suurempi putki päivittää")
	save_manager.load_game()
	_check(save_manager.get_best_streak() == 4, "uusi ennätys tallessa")


## Vanha tallennus ilman random_mode-avainta latautuu ja säilyttää kenttätulokset.
func _test_backward_compatibility() -> void:
	var old_save := {
		"version": 1,
		"levels": {
			"level_1": {"completed": true, "best_score": 87, "best_stars": 2},
		},
	}

	_write_json(TEST_SAVE, old_save)
	save_manager.load_game()

	_check(save_manager.load_warning.is_empty(), "vanha tallennus latautuu ilman varoitusta")
	_check(save_manager.get_best_streak() == 0, "vanhassa tallennuksessa paras putki 0")
	_check(save_manager.get_best_stars("level_1") == 2, "vanhan tallennuksen tähdet säilyvät")
	_check(save_manager.is_level_unlocked("level_2"), "vanhan tallennuksen eteneminen säilyy")

	save_manager.update_best_streak(5)
	save_manager.load_game()
	_check(save_manager.get_best_score("level_1") == 87, "kenttätulos säilyy putken tallennuksessa")
	_check(save_manager.get_best_streak() == 5, "putki tallentuu vanhan tallennuksen rinnalle")

	_write_json(TEST_SAVE, {"version": 1, "levels": {}, "random_mode": {"best_streak": -7}})
	save_manager.load_game()
	_check(save_manager.get_best_streak() == 0, "negatiivinen putki korjataan nollaksi")

	_write_json(TEST_SAVE, {"version": 1, "levels": {}, "random_mode": {"best_streak": "abc"}})
	save_manager.load_game()
	_check(save_manager.get_best_streak() == 0, "virheellinen putki korjataan nollaksi")

	_write_json(TEST_SAVE, {"version": 1, "levels": {}, "random_mode": "rikki"})
	save_manager.load_game()
	_check(save_manager.get_best_streak() == 0, "virheellinen random_mode ohitetaan")


func _test_parse_seed() -> void:
	var cases := {
		"0": 0,
		"42": 42,
		"  123 ": 123,
		"4294967295": 4294967295,
		"4294967296": -1,
		"-5": -1,
		"+5": -1,
		"abc": -1,
		"12a": -1,
		"": -1,
		"1.5": -1,
	}

	for text in cases:
		var parsed: int = random_run.parse_seed(text)
		_check(parsed == cases[text], "parse_seed(\"%s\") = %d" % [text, cases[text]])


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


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
		print("PUTKITESTIT: OK")
		quit(0)
	else:
		print("PUTKITESTIT: %d virhettä" % failures.size())
		quit(1)
