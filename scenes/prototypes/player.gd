extends CharacterBody2D

## Moves with EMG gestures from the Emg autoload (arrow keys work too, for
## testing without the band). Wrist left/right moves sideways; the harder you
## make a fist, the higher the player floats (max effort = max_height).

@export var speed := 300.0
## Pixels above the start position at 100% fist force.
@export var max_height := 250.0
## How quickly the player follows the force (higher = snappier).
@export var height_follow := 10.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _ground_y := position.y


func _ready() -> void:
	Emg.gesture_changed.connect(_on_gesture_changed)
	if not Emg.has_model():
		push_warning("No gesture model yet: run gesture_demo.tscn, calibrate and press Save model")


func _physics_process(_delta: float) -> void:
	var direction := Input.get_axis("ui_left", "ui_right")
	if Emg.is_gesture("wrist_left"):
		direction = -1.0
	elif Emg.is_gesture("wrist_right"):
		direction = 1.0
	var force := Emg.get_force() if Emg.get_gesture() == "fist" else 0.0
	var target_y := _ground_y - force * max_height
	velocity = Vector2(direction * speed, (target_y - position.y) * height_follow)
	move_and_slide()


func _on_gesture_changed(gesture: String, confidence: float) -> void:
	print("Gesture: %s (%d%%)" % [gesture, roundi(confidence * 100.0)])
	# Red while making a fist, to see it working.
	_sprite.modulate = Color.RED if gesture == "fist" else Color.WHITE
