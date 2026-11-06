extends Control

## Start screen: pick a game or open the calibration screen. Each game gets a
## button from GAMES, so a new game only needs a line there. The games' own
## menus have a Main menu button that comes back here.
##
## The UI is laid out in main_menu.tscn; only the game buttons are added in
## code, since they follow GAMES.

const CALIBRATION_SCENE := "res://scenes/calibration/gesture_demo.tscn"
const GAMES := [
	{
		"title": "EMG Race",
		"description": "Drive a car around the track with gas, brake and steering gestures.",
		"scene": "res://scenes/games/race/race.tscn",
	},
	{
		"title": "Target Reach",
		"description": "Steer the dot onto the targets on the ring and hold it there.",
		"scene": "res://scenes/games/target_reach/target_reach.tscn",
	},
	{
		"title": "Versus (LAN)",
		"description": "Host or join a match on the local network and play the games against each other.",
		"scene": "res://scenes/menus/versus_lobby.tscn",
	},
]

@onready var _games: VBoxContainer = %Games
@onready var _model_status: Label = %ModelStatus


func _ready() -> void:
	for game in GAMES:
		_add_game_button(game)
	_show_model_status()
	# Keyboard and gamepad navigation start on the first game.
	_games.get_child(0).grab_focus()


func _add_game_button(game: Dictionary) -> void:
	var button := Button.new()
	button.text = "%s\n%s" % [game.title, game.description]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(420, 72)
	button.pressed.connect(func() -> void: get_tree().change_scene_to_file(game.scene))
	_games.add_child(button)


func _show_model_status() -> void:
	if not Emg.has_model():
		_model_status.text = "No gesture model yet: calibrate first\n(arrow keys still work in the games)."
		return
	var gestures := Array(Emg.recognizer.gestures)
	var force := ", with force" if Emg.recognizer.has_force_calibration() else ""
	_model_status.text = "Model ready%s: %s" % [force, ", ".join(gestures)]


func _on_calibrate_pressed() -> void:
	# The calibration screen's Play button comes back here.
	Emg.set_meta("return_scene", scene_file_path)
	get_tree().change_scene_to_file(CALIBRATION_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
