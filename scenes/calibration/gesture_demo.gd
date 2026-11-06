extends Control

## Calibrates the Emg autoload's GestureRecognizer and then shows the live
## prediction and force. Saves to Emg.model_path, which is what Emg loads on
## the next start.
##
## Pick which gestures to calibrate with the checkboxes (rest is always
## included, add new ones with the text box), then Calibrate. The model is
## trained on just those, and the game uses whatever the model has.
##
## Calibration steps:
##   1. Hold each gesture normally, a few reps (trains the classifier).
##   2. Hold each gesture as hard as you can (sets 100% force).
##   3. Hold each gesture on the 50% target line shown on the force graph.
##
## The UI is laid out in gesture_demo.tscn; only the gesture checkboxes and
## the per-gesture rows are added in code, since they follow the gesture list.

const ForceGraph := preload("res://scenes/calibration/force_graph.gd")
const HudginsPlot := preload("res://scenes/calibration/hudgins_plot.gd")
## Where the Play button goes, unless a game set Emg's "return_scene" meta
## before opening this screen. The model stays loaded in Emg across scenes.
const GAME_SCENE := "res://scenes/menus/main_menu.tscn"
## Ready-made gestures offered in the "Add a gesture" dropdown.
const PRESET_GESTURES := [
	"fist", "open_hand", "wrist_left", "wrist_right", "wrist_up", "wrist_down",
	"pinch", "point", "thumbs_up", "peace", "rock_on", "turn_palm_up", "turn_palm_down",
]
const PRESET_PROMPT := "Add a gesture..."

## Seconds to hold each gesture while recording.
@export var hold_seconds := 4.0
## Seconds to get into position before each recording starts.
@export var prepare_seconds := 2.0
## How many times to go through all gestures.
@export var repetitions := 3
## Seconds of each max-effort hold.
@export var max_seconds := 3.0
## Seconds of each hold on the 50% target line.
@export var target_seconds := 5.0
## Target force for step 3 (0.5 = 50% of max).
@export_range(0.1, 0.9) var target_force := 0.5
@export var csv_path := "user://gesture_samples.csv"

@onready var _recognizer: GestureRecognizer = Emg.recognizer

@onready var _status: Label = %Status
@onready var _phase_bar: ProgressBar = %PhaseBar
@onready var _detected: Label = %Detected
@onready var _gesture_picks: HFlowContainer = %GesturePicks
@onready var _new_gesture: LineEdit = %NewGesture
@onready var _preset_picker: OptionButton = %PresetPicker
@onready var _grid: GridContainer = %Rows
@onready var _graph: ForceGraph = %ForceGraph
# Shown in place of the force graph while it has nothing to show.
@onready var _hudgins: HudginsPlot = %HudginsPlot

# Everything disabled while calibrating.
var _buttons: Array[Button] = []
# Checkbox per gesture that can be calibrated, rest excluded.
var _gesture_boxes: Array[CheckBox] = []
# One row per gesture: sample count label and live probability bar.
var _count_labels: Array[Label] = []
var _proba_bars: Array[ProgressBar] = []
# False during calibration steps 1 and 2, where force is not used yet.
var _force_step := true
# Which gesture's force the graph shows; "" = the currently detected gesture.
var _graph_gesture := ""
# Target-line score for the hold in progress: frames counted / on target / force sum.
var _score := Vector3.ZERO
var _scoring := false

var _phase_text := ""
var _phase_end := 0.0
var _phase_length := 0.0


func _ready() -> void:
	_buttons.append(_preset_picker)
	_buttons.append(%AddButton)
	_buttons.append_array(%Buttons.get_children())
	# Emg.gestures is the default set; the loaded model may have others.
	for gesture in Emg.gestures + _recognizer.gestures:
		_add_gesture_option(gesture, _recognizer.gestures.has(gesture))
	_refresh_presets()
	_rebuild_rows()
	_recognizer.sample_recorded.connect(_on_sample_recorded)
	_recognizer.gesture_detected.connect(_on_gesture_detected)
	# Opened from the main menu there is no game to play yet, so go back instead.
	if Emg.get_meta("return_scene", GAME_SCENE) == GAME_SCENE:
		$Margin/VBox/Buttons/PlayButton.text = "Main menu"


func _add_gesture_option(gesture: String, checked: bool) -> void:
	if gesture == _recognizer.rest_gesture:
		return
	for existing in _gesture_boxes:
		if existing.text == gesture:
			existing.button_pressed = existing.button_pressed or checked
			return
	var check := CheckBox.new()
	check.text = gesture
	check.button_pressed = checked
	_gesture_picks.add_child(check)
	_gesture_boxes.append(check)
	_buttons.append(check)
	_refresh_presets()


# Fills the dropdown with the presets that are not in the checkbox row yet.
func _refresh_presets() -> void:
	_preset_picker.clear()
	_preset_picker.add_item(PRESET_PROMPT)
	for gesture in PRESET_GESTURES:
		if not _gesture_boxes.any(func(check: CheckBox) -> bool: return check.text == gesture):
			_preset_picker.add_item(gesture)
	_preset_picker.select(0)


func _on_preset_selected(index: int) -> void:
	if index > 0:
		_add_gesture_option(_preset_picker.get_item_text(index), true)


func _on_new_gesture_submitted(_text: String) -> void:
	_add_new_gesture()


func _add_new_gesture() -> void:
	var gesture := _new_gesture.text.strip_edges().to_lower().replace(" ", "_")
	if gesture != "":
		_add_gesture_option(gesture, true)
	_new_gesture.clear()


# Rest first, then the checked gestures in the order shown.
func _selected_gestures() -> PackedStringArray:
	var selected := PackedStringArray([_recognizer.rest_gesture])
	for check in _gesture_boxes:
		if check.button_pressed:
			selected.append(check.text)
	return selected


# One row per gesture of the recognizer: name, sample count, live probability.
func _rebuild_rows() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_count_labels.clear()
	_proba_bars.clear()
	for gesture in _recognizer.gestures:
		var name_label := Label.new()
		name_label.text = gesture
		_grid.add_child(name_label)

		var count_label := Label.new()
		count_label.text = "0 samples"
		_grid.add_child(count_label)
		_count_labels.append(count_label)

		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(bar)
		_proba_bars.append(bar)


func _process(_delta: float) -> void:
	if _phase_length > 0.0:
		var left := maxf(0.0, _phase_end - _now())
		_status.text = "%s  %.1f s" % [_phase_text, left]
		_phase_bar.value = 100.0 * (1.0 - left / _phase_length)

	var proba := _recognizer.get_probabilities()
	for i in _proba_bars.size():
		_proba_bars[i].value = proba[i] if i < proba.size() else 0.0

	var show_force := _force_step and _recognizer.has_force_calibration()
	_graph.visible = show_force
	_hudgins.visible = not show_force
	if show_force:
		var force := _recognizer.get_gesture_force(_graph_gesture) if _graph_gesture != "" else _recognizer.get_force()
		_graph.push(force)
		if _scoring:
			_score += Vector3(1.0, 1.0 if _graph.is_on_target(force) else 0.0, force)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# Shows text with a countdown for the given number of seconds, then returns.
func _phase(text: String, seconds: float) -> void:
	_phase_text = text
	_phase_length = seconds
	_phase_end = _now() + seconds
	await get_tree().create_timer(seconds).timeout
	_phase_length = 0.0


func _calibrate() -> void:
	var selected := _selected_gestures()
	if selected.size() < 2:
		_status.text = "Tick at least one gesture besides rest."
		return
	_set_buttons_enabled(false)
	_recognizer.predicting = false
	# Changing the gestures changes the class labels, so start from scratch.
	_recognizer.gestures = selected
	_recognizer.clear_samples()
	_rebuild_rows()
	_force_step = false
	_detected.text = ""

	# 1. Normal holds.
	var gestures := _recognizer.gestures
	for rep in repetitions:
		for gesture in gestures:
			var step := "(%d/%d)" % [rep + 1, repetitions]
			await _phase("Get ready: %s %s" % [gesture.to_upper(), step], prepare_seconds)
			_recognizer.start_recording(gesture)
			await _phase("Hold %s %s" % [gesture.to_upper(), step], hold_seconds)
			_recognizer.stop_recording()

	# 2. Max effort, for every gesture except rest.
	var force_gestures: Array[String] = []
	for gesture in gestures:
		if gesture != _recognizer.rest_gesture:
			force_gestures.append(gesture)
	for gesture in force_gestures:
		await _phase("Get ready: %s as HARD as you can" % gesture.to_upper(), prepare_seconds)
		_recognizer.start_recording(gesture, true)
		await _phase("MAX %s!" % gesture.to_upper(), max_seconds)
		_recognizer.stop_recording()

	# 3. Follow the target line.
	var results: Array[String] = []
	_force_step = true
	if _recognizer.calibrate_force():
		_graph.target = target_force
		for gesture in force_gestures:
			_graph_gesture = gesture
			_graph.clear()
			await _phase("Get ready: %s at %d%%" % [gesture.to_upper(), roundi(target_force * 100)], prepare_seconds)
			_recognizer.start_recording(gesture)
			# Score like the recording: skip the first settle_ms.
			_score = Vector3.ZERO
			get_tree().create_timer(_recognizer.settle_ms / 1000.0).timeout.connect(func() -> void: _scoring = true)
			await _phase("Hold %s on the line" % gesture.to_upper(), target_seconds)
			_scoring = false
			_recognizer.stop_recording()
			if _score.x > 0:
				results.append("%s %d%% (on line %d%% of the time)" % [gesture, roundi(100 * _score.z / _score.x), roundi(100 * _score.y / _score.x)])
		_graph.target = -1.0
		_graph_gesture = ""
	else:
		results.append("force calibration failed, see the output")

	if _recognizer.train():
		# Save right away so the model is there on the next start too.
		var saved := "Saved." if _recognizer.save_model(Emg.model_path) == OK else "Save failed, use Save model."
		_status.text = "Trained. %s Try the gestures, or press Play!\nTarget hold: %s" % [saved, ", ".join(results)]
		_recognizer.predicting = true
	else:
		_status.text = "Training failed, see the errors in the output."
	_set_buttons_enabled(true)


func _set_buttons_enabled(enabled: bool) -> void:
	for button in _buttons:
		button.disabled = not enabled


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(Emg.get_meta("return_scene", GAME_SCENE))


func _save_model() -> void:
	var err := _recognizer.save_model(Emg.model_path)
	_status.text = "Saved to " + ProjectSettings.globalize_path(Emg.model_path) if err == OK else "Save failed: " + error_string(err)


func _load_model() -> void:
	var err := _recognizer.load_model(Emg.model_path)
	if err != OK:
		_status.text = "Load failed: " + error_string(err)
		return
	for check in _gesture_boxes:
		check.button_pressed = _recognizer.gestures.has(check.text)
	for gesture in _recognizer.gestures:
		_add_gesture_option(gesture, true)
	_rebuild_rows()
	_recognizer.predicting = true
	_status.text = "Model loaded. Try the gestures!"


func _export_csv() -> void:
	var err := _recognizer.export_csv(csv_path)
	_status.text = "Exported to " + ProjectSettings.globalize_path(csv_path) if err == OK else "Export failed: " + error_string(err)


func _on_sample_recorded(gesture: String, sample_count: int) -> void:
	var index := _recognizer.gestures.find(gesture)
	if index >= 0 and index < _count_labels.size():
		_count_labels[index].text = "%d samples" % sample_count


func _on_gesture_detected(gesture: String, confidence: float) -> void:
	_detected.text = "%s  (%d%%)" % [gesture, roundi(confidence * 100.0)]
