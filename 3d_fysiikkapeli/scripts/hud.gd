class_name GameHUD
extends CanvasLayer

## Pelinäkymän käyttöliittymä: yläpalkki, tähtäin, voima, ohjeet ja tulosruutu.
## Ei sisällä pelilogiikkaa, vaan näyttää Rootin antamat arvot.

signal retry_requested
signal next_requested
signal menu_requested

@onready var ammo_label: Label = %AmmoLabel
@onready var timer_label: Label = %TimerLabel
@onready var score_label: Label = %ScoreLabel
@onready var streak_label: Label = %StreakLabel
@onready var random_info_panel: Control = %RandomInfoPanel
@onready var random_info_label: Label = %RandomInfoLabel
@onready var force_label: Label = %ForceLabel
@onready var crosshair: Label = %Crosshair
@onready var result_overlay: Control = %ResultOverlay
@onready var result_title: Label = %ResultTitle
@onready var result_score: Label = %ResultScore
@onready var result_stars: Label = %ResultStars
@onready var result_streak: Label = %ResultStreak
@onready var result_best: Label = %ResultBest
@onready var result_record: Label = %ResultRecord
@onready var result_hint: Label = %ResultHint
@onready var retry_button: Button = %RetryButton
@onready var next_button: Button = %NextButton
@onready var menu_button: Button = %MenuButton


func _ready() -> void:
	result_overlay.hide()

	retry_button.pressed.connect(retry_requested.emit)
	next_button.pressed.connect(next_requested.emit)
	menu_button.pressed.connect(menu_requested.emit)


func set_ammo(ammo: int) -> void:
	ammo_label.text = "Ammuksia: %d" % ammo


func set_time(seconds: float) -> void:
	timer_label.text = "Aikaa: %d" % ceili(seconds)


func set_score(percentage: int) -> void:
	score_label.text = "Kaatuneet: %d %%" % percentage


func set_force(force: float) -> void:
	force_label.text = "Voima: %d" % int(force)


## Satunnaisen pelimuodon tiedot: putki yläpalkkiin, siemen ja palikkamäärä sen alle.
func set_random_info(seed_value: int, block_count: int, streak: int) -> void:
	streak_label.text = "Putki: %d kenttää" % streak
	streak_label.show()
	random_info_label.text = "Siemen: %d · %d palikkaa" % [seed_value, block_count]
	random_info_panel.show()


## Satunnaisen pelimuodon tulosruutu: tähtien sijaan putki ja ennätys.
func show_random_result(
	completed: bool,
	percentage: int,
	required_percentage: int,
	streak: int,
	best_streak: int,
	new_record: bool,
	seed_value: int
) -> void:
	crosshair.hide()

	result_title.text = "Kenttä läpäisty!" if completed else "Putki päättyi"
	result_score.text = "Kaatuneet: %d %%" % percentage
	result_stars.hide()

	result_streak.text = "Putki: %d kenttää" % streak
	result_streak.show()
	result_record.visible = new_record
	result_best.text = "Ennätys: %d kenttää" % best_streak

	if completed:
		result_hint.text = "Siemen: %d" % seed_value
	else:
		result_hint.text = "Läpäisyyn tarvitaan vähintään %d %%.\nSiemen: %d\nR - Yritä uudelleen" % [
			required_percentage,
			seed_value
		]

	# Läpäistyä kenttää ei voi pelata uudelleen, jotta putkea ei voi kasvattaa toistamalla.
	retry_button.visible = not completed
	next_button.text = "Seuraava satunnaiskenttä"
	next_button.visible = completed

	result_overlay.show()


## Näyttää tulosruudun. record on SaveManager.get_level_data()-muotoinen sanakirja.
func show_result(
	completed: bool,
	percentage: int,
	stars: int,
	required_percentage: int,
	record: Dictionary,
	new_record: bool,
	has_next: bool
) -> void:
	crosshair.hide()

	result_title.text = "Kenttä läpäisty!" if completed else "Peli päättyi"
	result_score.text = "Kaatuneet: %d %%" % percentage
	result_stars.text = SaveManager.format_stars(stars)

	result_record.visible = new_record

	if record["completed"]:
		result_best.text = "Paras tulos: %d %%  %s" % [
			record["best_score"],
			SaveManager.format_stars(record["best_stars"])
		]
	else:
		result_best.text = "Ei vielä läpäisyä"

	if completed:
		result_hint.text = "R - Yritä uudelleen"
	else:
		result_hint.text = "Läpäisyyn tarvitaan vähintään %d %%.\nR - Yritä uudelleen" % required_percentage

	next_button.visible = has_next

	# Painikkeille ei anneta fokusta, koska välilyönti (zoomaus) painaisi fokusoitua painiketta.
	result_overlay.show()
