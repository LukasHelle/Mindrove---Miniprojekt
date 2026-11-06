extends Node3D

## 3D racing game controlled with EMG gestures. After a countdown you drive
## the car yourself: gas, brake, and steering left/right. The harder the
## gesture, the more gas, brake or steering (full if the model has no force
## calibration). Arrow keys work too, for testing without the band.
##
## The car is the srcoder_simplecar physics car (VehicleBody3D) with
## emg_car.gd on top, so it drives with real wheels and grip; tune it on the
## Car node. The grass slows it down, cones are solid, braking when stopped
## reverses, and a car stuck on its roof or side is put back on the track.
## Laps count distance along the Track, so cutting across the grass or driving
## backwards does not help.
##
## Versus (opened from versus_lobby.tscn): every PC drives its own car and
## sends where it is; the others show up as ghost cars in their player color
## that do not collide, so network lag can not push anyone off. Cars start
## on a grid behind the line and each drives the same distance. The race ends
## when everyone finished, or finish_wait_seconds after the first one did.
##
## Which gesture does what is picked on the menu and saved to SETTINGS_PATH.
## The UI and the car are laid out in race.tscn; reshape the track by editing
## the Track path's points, the road follows it.

const CALIBRATION_SCENE := "res://scenes/calibration/gesture_demo.tscn"
const MAIN_MENU_SCENE := "res://scenes/menus/main_menu.tscn"
const CAR_SCENE := preload("res://addons/srcoder_simplecar/car.tscn")
const SETTINGS_PATH := "user://race.cfg"
const NO_GESTURE := "(none)"
const DEFAULT_CONTROLS := {
	"gas": "fist",
	"brake": "open_hand",
	"left": "wrist_left",
	"right": "wrist_right",
}
const MS_TO_KMH := 3.6
# The car counts as off the road once its center is this close to the edge.
const CAR_HALF_WIDTH := 0.65
# The car counts as flipped when its up axis points less upwards than this.
const FLIPPED_UP := 0.3
# Metres above the road the car is dropped when placed on the track.
const DROP_HEIGHT := 0.5
# Starting grid: metres between rows of two, and from the center to each column.
const GRID_ROW_GAP := 7.0
const GRID_SIDE_OFFSET := 2.5
# Versus: times per second your car's position is sent to the others.
const SYNC_RATE := 30.0
# How quickly ghost cars catch up with their latest position (higher = snappier).
const GHOST_SMOOTHING := 15.0

@export_range(1, 20) var laps_per_race := 3
## Half the road width in metres (match the Road polygon).
@export var road_half_width := 5.0
## Top speed on the grass in m/s; above it the car brakes by itself.
@export var grass_speed := 8.0
## Seconds on its roof or side before the car is put back on the track.
@export var flipped_reset_seconds := 2.0
@export var countdown_seconds := 3.0
## Versus: seconds the others get to finish after the first car finished.
@export var finish_wait_seconds := 30.0

enum State { MENU, COUNTDOWN, RACING, FINISHED }

@onready var _track: Path3D = %Track
@onready var _car: VehicleBody3D = %Car
@onready var _info: Label = %Info
@onready var _message: Label = %Message
@onready var _speed_bar: ProgressBar = %SpeedBar
@onready var _menu: Control = %Menu
@onready var _menu_text: Label = %MenuText
@onready var _start_button: Button = %StartButton
# Action name -> its OptionButton on the menu.
@onready var _pickers := {
	"gas": %GasPicker,
	"brake": %BrakePicker,
	"left": %LeftPicker,
	"right": %RightPicker,
}

# Action name -> gesture name (or NO_GESTURE), as picked on the menu.
var _controls := DEFAULT_CONTROLS.duplicate()
var _state := State.MENU
# Seconds left of the countdown.
var _timer := 0.0
# Seconds the car has been on its roof or side.
var _flipped_time := 0.0
# Distance along the Track driven this race (goes down when driving backwards).
var _distance := 0.0
# Where on the Track the car is closest to, and how far from it in metres.
var _progress := 0.0
var _road_distance := 0.0
var _track_length := 0.0
var _race_time := 0.0
var _lap_start := 0.0
var _lap_times: Array[float] = []

# Versus: peer id -> {"car": ghost VehicleBody3D, "target": Transform3D, "distance": float}
var _ghosts := {}
# Versus: peer id -> race time, for everyone who finished (you too).
var _finish_times := {}
var _sync_timer := 0.0
# Versus, host: seconds left for the others after the first finish, < 0 before.
var _finish_wait := -1.0


func _ready() -> void:
	_track_length = _track.curve.get_baked_length()
	# Top speed: the addon caps the driving wheels' rpm.
	var wheel: VehicleWheel3D = _car.driving_wheels[0]
	_speed_bar.max_value = _car.max_wheel_rpm / 60.0 * TAU * wheel.wheel_radius
	_place_car(0.0)
	_load_controls()
	_fill_pickers()
	if Versus.active:
		_setup_versus()
	_show_menu("")


func _fill_pickers() -> void:
	var choices := [NO_GESTURE]
	for gesture in Emg.recognizer.gestures:
		if gesture != Emg.recognizer.rest_gesture:
			choices.append(gesture)
	for action in _pickers:
		# A gesture the current model does not have can never be detected.
		if not choices.has(_controls[action]):
			_controls[action] = NO_GESTURE
		var picker: OptionButton = _pickers[action]
		picker.clear()
		for choice in choices:
			picker.add_item(choice)
		picker.select(choices.find(_controls[action]))
		picker.item_selected.connect(func(index: int) -> void: _set_control(action, choices[index]))


func _load_controls() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for action in _controls:
		_controls[action] = config.get_value("controls", action, _controls[action])


func _set_control(action: String, gesture: String) -> void:
	_controls[action] = gesture
	var config := ConfigFile.new()
	for a in _controls:
		config.set_value("controls", a, _controls[a])
	config.save(SETTINGS_PATH)


func _on_calibrate_pressed() -> void:
	# The calibration screen's Play button comes back here.
	Emg.set_meta("return_scene", scene_file_path)
	get_tree().change_scene_to_file(CALIBRATION_SCENE)


func _on_main_menu_pressed() -> void:
	if Versus.active:
		_leave_versus()
	else:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_start_pressed() -> void:
	if Versus.active:
		# The host starts the race for everyone once all are ready (began).
		_start_button.disabled = true
		Versus.set_ready()
	else:
		_start_race()


func _show_menu(result: String) -> void:
	_state = State.MENU
	var model := "Model ready." if Emg.has_model() else "No gesture model yet: press Calibrate first\n(arrow keys still work)."
	_menu_text.text = (result + "\n\n" if result != "" else "") + model
	_start_button.disabled = false
	_menu.show()


func _start_race() -> void:
	_menu.hide()
	_distance = 0.0
	_progress = 0.0
	_road_distance = 0.0
	_place_car(0.0)
	_race_time = 0.0
	_lap_start = 0.0
	_lap_times.clear()
	_state = State.COUNTDOWN
	_timer = countdown_seconds
	if Versus.active:
		_finish_times.clear()
		_finish_wait = -1.0
		var ids := Versus.player_ids()
		for id in ids:
			if _ghosts.has(id):
				_ghosts[id].distance = 0.0
				_ghosts[id].target = _grid_transform(ids.find(id))
				_ghosts[id].car.global_transform = _ghosts[id].target
		# Same distance for everyone: progress starts at the grid slot, distance at 0.
		_progress = _grid_progress(ids.find(multiplayer.get_unique_id()))
		_car.global_transform = _grid_transform(ids.find(multiplayer.get_unique_id()))


func _finish_race(title: String) -> void:
	var lines: Array[String] = [title]
	for i in _lap_times.size():
		lines.append("Lap %d: %.2f s" % [i + 1, _lap_times[i]])
	if _lap_times.size() == laps_per_race:
		lines.append("Total: %.2f s   Best lap: %.2f s" % [_race_time, _lap_times.min()])
	_show_menu("\n".join(lines))


func _unhandled_input(event: InputEvent) -> void:
	if _state != State.MENU and event.is_action_pressed("ui_cancel"):
		if Versus.active:
			_leave_versus()
		else:
			_finish_race("Race stopped")


# 0..1 for an action: the arrow key, or the picked gesture scaled by its force.
func _amount(action: String, key: String) -> float:
	if Input.is_action_pressed(key):
		return 1.0
	var gesture: String = _controls[action]
	if gesture == NO_GESTURE or not Emg.is_gesture(gesture):
		return 0.0
	return Emg.get_force() if Emg.recognizer.has_force_calibration() else 1.0


# Puts the car on the track at the given progress, facing along it, at rest.
func _place_car(progress: float) -> void:
	_car.global_transform = _track_transform(progress, 0.0)
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
	_flipped_time = 0.0


# Where a car sits at the given progress, side_offset metres right of the center.
func _track_transform(progress: float, side_offset: float) -> Transform3D:
	var xf := _track.global_transform * _track.curve.sample_baked_with_rotation(progress)
	# The addon's car drives towards +Z, the curve's forward is -Z.
	var origin := xf.origin + xf.basis.x * side_offset + Vector3.UP * DROP_HEIGHT
	return Transform3D(Basis.looking_at(-xf.basis.z, Vector3.UP, true), origin)


func _process(delta: float) -> void:
	match _state:
		State.COUNTDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.RACING
		State.RACING:
			_race_time += delta
			_update_track_position()
			_check_flipped(delta)
			if int(_distance / _track_length) > _lap_times.size():
				_lap_times.append(_race_time - _lap_start)
				_lap_start = _race_time
				if _lap_times.size() >= laps_per_race:
					if Versus.active:
						_state = State.FINISHED
						_car_finished.rpc(_race_time)
					else:
						_finish_race("Finished!")
	if Versus.active:
		_update_versus(delta)
	_update_car_input()
	_update_hud()


func _update_car_input() -> void:
	_car.gas = _amount("gas", "ui_up")
	_car.brake_amount = _amount("brake", "ui_down")
	_car.steer_amount = _amount("left", "ui_left") - _amount("right", "ui_right")
	# Parked outside the race, and the grass holds the car back.
	_car.parked = _state != State.RACING or (_is_off_road() and _speed() > grass_speed)


func _speed() -> float:
	return _car.linear_velocity.length()


func _update_track_position() -> void:
	var local := _track.to_local(_car.global_position)
	var progress := _track.curve.get_closest_offset(local)
	# Shortest way round between the old and new progress, so the lap line
	# does not count as a whole lap.
	_distance += fposmod(progress - _progress + _track_length / 2.0, _track_length) - _track_length / 2.0
	_progress = progress
	var center := _track.curve.sample_baked(progress)
	_road_distance = Vector2(local.x - center.x, local.z - center.z).length()


func _is_off_road() -> bool:
	return _road_distance > road_half_width - CAR_HALF_WIDTH


func _check_flipped(delta: float) -> void:
	if _car.global_basis.y.y < FLIPPED_UP:
		_flipped_time += delta
		if _flipped_time >= flipped_reset_seconds:
			_place_car(_progress)
	else:
		_flipped_time = 0.0


func _update_hud() -> void:
	_speed_bar.value = _speed()
	var best := "%.2f s" % _lap_times.min() if not _lap_times.is_empty() else "-"
	var time: float = _race_time if not _finish_times.has(multiplayer.get_unique_id()) else _finish_times[multiplayer.get_unique_id()]
	_info.text = "Lap %d / %d   Time %.1f s   Best lap %s\nSpeed %d km/h\nGas: %s   Brake: %s   Left: %s   Right: %s   (Esc = %s)" % [
		mini(_lap_times.size() + 1, laps_per_race), laps_per_race, time, best,
		roundi(_speed() * MS_TO_KMH), _controls["gas"], _controls["brake"], _controls["left"], _controls["right"],
		"leave" if Versus.active else "stop",
	]
	if Versus.active and _state != State.MENU:
		_info.text += "\n\n" + _standings_text()

	# Only the countdown is shown in the middle of the screen.
	_message.text = str(ceili(_timer)) if _state == State.COUNTDOWN else ""
	if _state == State.FINISHED:
		_message.text = "Finished! Waiting for the others"


#region Versus

func _setup_versus() -> void:
	Versus.began.connect(_start_race)
	Versus.ready_changed.connect(_on_ready_changed)
	Online.player_disconnected.connect(_on_player_left)
	%CalibrateButton.hide()
	_start_button.text = "Ready"
	%MainMenuButton.text = "Back to lobby" if Versus.is_host() else "Leave match"
	var ids := Versus.player_ids()
	for id in ids:
		if id != multiplayer.get_unique_id():
			_add_ghost(id, _grid_transform(ids.find(id)))
	_paint_car(_car, Versus.player_color(multiplayer.get_unique_id()))
	_car.global_transform = _grid_transform(ids.find(multiplayer.get_unique_id()))


func _leave_versus() -> void:
	if Versus.is_host():
		Versus.back_to_lobby()
	else:
		Versus.leave()


func _on_ready_changed() -> void:
	if _state == State.MENU and _start_button.disabled:
		_menu_text.text = "Waiting for: " + Versus.waiting_for()


# Grid slot by player order: rows of two behind the start line.
func _grid_progress(slot: int) -> float:
	return fposmod(-GRID_ROW_GAP * (slot / 2), _track_length)


func _grid_transform(slot: int) -> Transform3D:
	return _track_transform(_grid_progress(slot), GRID_SIDE_OFFSET if slot % 2 == 0 else -GRID_SIDE_OFFSET)


# A car that only shows where another player is: frozen, no collisions, no input.
func _add_ghost(id: int, xf: Transform3D) -> void:
	var ghost: VehicleBody3D = CAR_SCENE.instantiate()
	ghost.name = "Ghost%d" % id
	ghost.freeze = true
	ghost.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	ghost.collision_layer = 0
	ghost.collision_mask = 0
	add_child(ghost)
	# The addon car reads its own input actions, which this project does not have.
	ghost.set_physics_process(false)
	ghost.global_transform = xf
	_paint_car(ghost, Versus.player_color(id))
	var label := Label3D.new()
	label.text = Versus.player_name(id)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3.UP * 1.6
	label.font_size = 48
	label.outline_size = 12
	label.modulate = Versus.player_color(id)
	ghost.add_child(label)
	_ghosts[id] = {"car": ghost, "target": xf, "distance": 0.0}


func _paint_car(car: VehicleBody3D, color: Color) -> void:
	var body: MeshInstance3D = car.get_node("body")
	var material := body.get_active_material(0).duplicate() as StandardMaterial3D
	material.albedo_color = color
	body.material_override = material


func _on_player_left(data: PlayerData) -> void:
	var id := data.multiplayer_id
	if _ghosts.has(id):
		_ghosts[id].car.queue_free()
		_ghosts.erase(id)


func _update_versus(delta: float) -> void:
	for id in _ghosts:
		var ghost: Dictionary = _ghosts[id]
		ghost.car.global_transform = ghost.car.global_transform.interpolate_with(ghost.target, minf(1.0, GHOST_SMOOTHING * delta))

	if _state == State.RACING:
		_sync_timer -= delta
		if _sync_timer <= 0.0:
			_sync_timer = 1.0 / SYNC_RATE
			_car_state.rpc(_car.global_transform, _distance)

	# The host decides when the race is over, so everyone sees the same result.
	if Versus.is_host() and _finish_wait >= 0.0 and _state != State.MENU:
		_finish_wait -= delta
		var everyone := Versus.player_ids().all(func(id: int) -> bool: return _finish_times.has(id))
		if everyone or _finish_wait <= 0.0:
			_finish_wait = -1.0
			_race_over.rpc()


@rpc("any_peer", "unreliable_ordered")
func _car_state(xf: Transform3D, distance: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _ghosts.has(id):
		_ghosts[id].target = xf
		_ghosts[id].distance = distance


@rpc("any_peer", "call_local", "reliable")
func _car_finished(time: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	_finish_times[id] = time
	if _ghosts.has(id):
		_ghosts[id].distance = laps_per_race * _track_length
	if _finish_wait < 0.0:
		_finish_wait = finish_wait_seconds


@rpc("authority", "call_local", "reliable")
func _race_over() -> void:
	var lines: Array[String] = ["Race over!"]
	var place := 1
	for id in _ranking():
		var result := "%.2f s" % _finish_times[id] if _finish_times.has(id) else "did not finish"
		lines.append("%d. %s   %s" % [place, Versus.player_name(id), result])
		place += 1
	_start_button.text = "Ready for a rematch"
	_show_menu("\n".join(lines))


# Player ids best first: finishers by time, then the rest by distance driven.
func _ranking() -> Array[int]:
	var ids := Versus.player_ids()
	var own := multiplayer.get_unique_id()
	var distance := func(id: int) -> float: return _distance if id == own else _ghosts[id].distance if _ghosts.has(id) else 0.0
	ids.sort_custom(func(a: int, b: int) -> bool:
		if _finish_times.has(a) or _finish_times.has(b):
			return _finish_times.get(a, INF) < _finish_times.get(b, INF)
		return distance.call(a) > distance.call(b))
	return ids


func _standings_text() -> String:
	var lines: Array[String] = []
	var place := 1
	for id in _ranking():
		var you := "  (you)" if id == multiplayer.get_unique_id() else ""
		lines.append("%d. %s%s" % [place, Versus.player_name(id), you])
		place += 1
	return "\n".join(lines)

#endregion
