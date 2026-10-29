extends Control

## Aloitusvalikko ja kenttävalinta. Kenttälista ja edistyminen tulevat SaveManagerista.

@onready var main_panel: Control = %MainPanel
@onready var level_panel: Control = %LevelPanel
@onready var level_list: VBoxContainer = %LevelList
@onready var notice_label: Label = %NoticeLabel
@onready var play_button: Button = %PlayButton
@onready var levels_button: Button = %LevelsButton
@onready var quit_button: Button = %QuitButton
@onready var back_button: Button = %BackButton
@onready var random_button: Button = %RandomButton
@onready var random_panel: Control = %RandomPanel
@onready var best_streak_label: Label = %BestStreakLabel
@onready var seed_edit: LineEdit = %SeedEdit
@onready var seed_error_label: Label = %SeedErrorLabel
@onready var start_random_button: Button = %StartRandomButton
@onready var random_back_button: Button = %RandomBackButton

const RANDOM_LEVEL_SCENE := "res://scenes/levels/random_level.tscn"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	play_button.pressed.connect(_on_play_pressed)
	levels_button.pressed.connect(_show_level_select)
	quit_button.pressed.connect(_on_quit_pressed)
	back_button.pressed.connect(_show_main)
	random_button.pressed.connect(_show_random_mode)
	start_random_button.pressed.connect(_on_start_random_pressed)
	random_back_button.pressed.connect(_show_main)
	seed_edit.text_submitted.connect(func(_text: String) -> void: _on_start_random_pressed())

	notice_label.text = SaveManager.load_warning
	notice_label.visible = not SaveManager.load_warning.is_empty()

	_build_level_cards()
	_show_main()


func _show_main() -> void:
	level_panel.hide()
	random_panel.hide()
	main_panel.show()
	play_button.grab_focus()


func _show_level_select() -> void:
	main_panel.hide()
	level_panel.show()
	back_button.grab_focus()


func _show_random_mode() -> void:
	main_panel.hide()
	best_streak_label.text = "Ennätys: %d kenttää" % SaveManager.get_best_streak()
	seed_error_label.hide()
	random_panel.show()
	start_random_button.grab_focus()


## Tyhjä siemenkenttä arpoo uuden siemenen. Jokainen aloitus on uusi juoksu putkesta nolla.
func _on_start_random_pressed() -> void:
	var seed_text := seed_edit.text.strip_edges()
	var seed_value := -1

	if not seed_text.is_empty():
		seed_value = RandomRun.parse_seed(seed_text)

		if seed_value < 0:
			seed_error_label.show()
			return

	RandomRun.start_run(seed_value)

	var error := get_tree().change_scene_to_file(RANDOM_LEVEL_SCENE)

	if error != OK:
		RandomRun.end_run()
		push_error("Satunnaisen kentän latauksen käynnistäminen epäonnistui, virhekoodi: %s" % error)


func _build_level_cards() -> void:
	for child in level_list.get_children():
		child.queue_free()

	for level in SaveManager.LEVELS:
		level_list.add_child(_create_level_card(level))


func _create_level_card(level: Dictionary) -> Button:
	var level_id: String = level["id"]
	var unlocked := SaveManager.is_level_unlocked(level_id)
	var record := SaveManager.get_level_data(level_id)

	var card := Button.new()
	card.custom_minimum_size = Vector2(460, 76)
	card.disabled = not unlocked
	card.pressed.connect(_start_level.bind(level_id))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 20
	row.offset_right = -20
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	var name_label := Label.new()
	name_label.text = level["name"]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)

	var stars_label := Label.new()
	stars_label.theme_type_variation = &"StarsLabel"
	stars_label.add_theme_font_size_override("font_size", 24)
	stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stars_label.text = SaveManager.format_stars(record["best_stars"])
	info.add_child(stars_label)

	var status_label := Label.new()
	status_label.theme_type_variation = &"HintLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.add_child(status_label)

	if not unlocked:
		status_label.text = "Lukittu"
		row.modulate = Color(1, 1, 1, 0.45)
	elif record["completed"]:
		status_label.text = "Paras: %d %%" % record["best_score"]
	else:
		status_label.text = "Ei läpäisty"

	return card


func _on_play_pressed() -> void:
	_start_level(SaveManager.get_first_open_level_id())


func _start_level(level_id: String) -> void:
	if not SaveManager.is_level_unlocked(level_id):
		return

	var selected_level := SaveManager.get_level_path(level_id)

	if not ResourceLoader.exists(selected_level):
		push_error("Kenttää ei löydy: " + selected_level)
		return

	var error := get_tree().change_scene_to_file(selected_level)

	if error != OK:
		push_error(
			"Kentän latauksen käynnistäminen epäonnistui: %s, virhekoodi: %s"
			% [selected_level, error]
		)


func _on_quit_pressed() -> void:
	get_tree().quit()
