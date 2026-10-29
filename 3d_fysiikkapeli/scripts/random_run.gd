extends Node

## Satunnaisen pelimuodon juoksun tila, joka säilyy kentän uudelleenlatauksen yli.
## Putki kasvaa vain onnistuneesta kentästä ja kerran kenttää kohden. Paras putki
## tallennetaan SaveManageriin erillään tavallisten kenttien tuloksista.

const MAX_SEED := 4294967295

enum LevelState {
	PLAYING,
	COMPLETED,
	FAILED,
}

## Nykyisen kentän siemen.
var current_seed: int = 0
## Peräkkäin läpäistyt kentät tässä juoksussa.
var streak: int = 0
## Tosi, kun tämä juoksu on nostanut parhaan putken.
var run_new_record: bool = false
var active: bool = false
var level_state: LevelState = LevelState.PLAYING

var _seed_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_seed_rng.randomize()


## Uusi juoksu putkesta nolla. Negatiivinen siemen tarkoittaa uutta satunnaista siementä.
func start_run(seed_value: int = -1) -> void:
	active = true
	streak = 0
	run_new_record = false
	current_seed = seed_value if seed_value >= 0 else new_seed()
	level_state = LevelState.PLAYING


func new_seed() -> int:
	return _seed_rng.randi()


## Kirjaa kentän läpäisyn. Palauttaa true, jos putki on uusi ennätys.
## Samaa kenttää ei voi kirjata kahdesti.
func record_success() -> bool:
	if level_state != LevelState.PLAYING:
		return false

	level_state = LevelState.COMPLETED
	streak += 1

	var new_record := SaveManager.update_best_streak(streak)
	run_new_record = run_new_record or new_record
	return new_record


## Kirjaa epäonnistumisen. Putki päättyy, mutta sen pituus näytetään tulosruudussa.
func record_failure() -> void:
	if level_state != LevelState.PLAYING:
		return

	level_state = LevelState.FAILED


## Siirtyy seuraavaan kenttään uudella siemenellä. Sallittu vain läpäisyn jälkeen.
func advance() -> bool:
	if level_state != LevelState.COMPLETED:
		return false

	current_seed = new_seed()
	level_state = LevelState.PLAYING
	return true


## Epäonnistumisen jälkeen sama siemen alkaa uutena juoksuna. Läpäistyä kenttää ei voi
## pelata uudelleen saman juoksun aikana, joten putkea ei voi kasvattaa toistamalla.
func retry() -> bool:
	if level_state != LevelState.FAILED:
		return false

	start_run(current_seed)
	return true


func end_run() -> void:
	active = false
	streak = 0
	run_new_record = false
	level_state = LevelState.PLAYING


## Muuntaa pelaajan syöttämän siemenen luvuksi. Palauttaa -1, jos syöte ei kelpaa.
static func parse_seed(text: String) -> int:
	var trimmed := text.strip_edges()

	if trimmed.is_empty() or trimmed.length() > 10 or not trimmed.is_valid_int() or trimmed.begins_with("-") or trimmed.begins_with("+"):
		return -1

	var value := trimmed.to_int()
	return value if value >= 0 and value <= MAX_SEED else -1
