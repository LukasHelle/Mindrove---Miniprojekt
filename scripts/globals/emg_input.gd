class_name EmgInput
extends Node

## Drop-in EMG gesture input. Creates the EmgBand -> HudginsFeatures ->
## GestureRecognizer chain in code and loads the model saved by gesture_demo.tscn.
##
## Add it to a scene (Add Child Node -> EmgInput), then:
##     $EmgInput.gesture_changed.connect(_on_gesture)
##     if $EmgInput.is_gesture("fist"): ...
##
## Only one EmgInput (or EmgBand) can talk to the band at a time.

## Fires when the smoothed gesture changes.
signal gesture_changed(gesture: String, confidence: float)

## Synthetic: -1 (fake data for testing), MindRove WiFi: 0.
@export_enum("Synthetic:-1", "MindRove WiFi:0", "MindRove SyncBox:1") var board_id := 0
@export var ip_address := ""
## Gestures offered by default on the calibration screen. A loaded model
## brings its own list (recognizer.gestures), which is what is detected.
@export var gestures := PackedStringArray(["rest", "fist", "open_hand", "wrist_left", "wrist_right"])
## Model saved by the calibration demo.
@export var model_path := "user://gesture_model.json"
## is_gesture() only returns true at or above this confidence.
@export_range(0.0, 1.0) var min_confidence := 0.6
## Bigger = steadier but slower to react (each step is 50 ms).
@export_range(1, 50) var smoothing_window := 5

var band: EmgBand
var features: HudginsFeatures
var recognizer: GestureRecognizer


func _ready() -> void:
	# Each node connects to the previous one in its _ready, so the paths have to
	# be set before add_child, and the nodes added in this order.
	band = EmgBand.new()
	band.name = "EmgBand"
	band.board_id = board_id
	band.ip_address = ip_address
	add_child(band)

	features = HudginsFeatures.new()
	features.name = "HudginsFeatures"
	features.band = NodePath("../EmgBand")
	add_child(features)

	recognizer = GestureRecognizer.new()
	recognizer.name = "GestureRecognizer"
	recognizer.features = NodePath("../HudginsFeatures")
	recognizer.gestures = gestures
	recognizer.smoothing_window = smoothing_window
	add_child(recognizer)
	recognizer.gesture_detected.connect(func(g: String, c: float) -> void: gesture_changed.emit(g, c))

	if FileAccess.file_exists(model_path):
		load_model()
	else:
		push_warning("EmgInput: no model at %s, run gesture_demo.tscn to calibrate" % model_path)


## Loads the model and starts predicting. Returns false if it could not be loaded.
func load_model(path := model_path) -> bool:
	if recognizer.load_model(path) != OK:
		return false
	recognizer.predicting = true
	return true


func save_model(path := model_path) -> bool:
	return recognizer.save_model(path) == OK


func has_model() -> bool:
	return recognizer.is_trained()


## The current gesture, or "" before the first prediction.
func get_gesture() -> String:
	return recognizer.get_current_gesture()


func get_confidence() -> float:
	return recognizer.get_current_confidence()


## Force of the current gesture, 0 (rest) to 1 (max effort). Always 0 if the
## model was calibrated without the force steps.
func get_force() -> float:
	return recognizer.get_force()


## Force of a specific gesture, even if the classifier currently sees another one.
func get_gesture_force(gesture: String) -> float:
	return recognizer.get_gesture_force(gesture)


## True while the given gesture is held with at least min_confidence.
func is_gesture(gesture: String) -> bool:
	return get_gesture() == gesture and get_confidence() >= min_confidence
