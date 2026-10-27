
extends Control

@onready var level_option: OptionButton = $CenterContainer/VBoxContainer/LevelOption
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

const LEVEL_1 := "res://scenes/root.tscn"
const LEVEL_2 := "res://scenes/levels/level_2.tscn"


func _ready() -> void:
	level_option.clear()
	level_option.add_item("Kenttä 1 - Perustorni")
	level_option.add_item("Kenttä 2 - Haastava torni")
	level_option.select(0)

	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _on_start_pressed() -> void:
	var selected_level: String

	match level_option.selected:
		0:
			selected_level = LEVEL_1
		1:
			selected_level = LEVEL_2
		_:
			return

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
