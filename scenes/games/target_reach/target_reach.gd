extends Control

## Center-out reaching task: targets sit evenly on a ring around the center,
## one lights up, and you steer the cursor dot onto it and hold it there.
##
## Which gesture moves the dot which way is picked on the menu (by default
## wrist left/right sideways, open hand up, fist down) and saved to
## SETTINGS_PATH. One gesture can be picked for two directions to move
## diagonally. The harder the gesture, the faster the dot (full speed if the
## model has no force calibration). Arrow keys work too, for testing without
## the band.
##
## Starts on a menu: Start game plays trials_per_game trials, Calibrate opens
## gesture_demo.tscn, whose Play button comes back here. Esc ends a game early.
##
## Versus (opened from versus_lobby.tscn): everyone gets the same targets at
## the same time and sees the others' cursors in their player color. The
## first to hold the target scores; the host decides who was first, and ends
## a trial nobody reached after timeout_seconds. Positions are sent relative
## to the ring, so different screen sizes still line up.
##
## The UI is laid out in target_reach.tscn; the ring, targets and cursor are
## drawn on the Arena node through its draw signal.

const CALIBRATION_SCENE := "res://scenes/calibration/gesture_demo.tscn"
const MAIN_MENU_SCENE := "res://scenes/menus/main_menu.tscn"
const SETTINGS_PATH := "user://target_reach.cfg"
const NO_GESTURE := "(none)"
# Versus: times per second your cursor is sent to the others.
const SYNC_RATE := 30.0

## Number of targets on the ring.
@export_range(2, 16) var target_count := 6
## Trials in one game.
@export_range(1, 100) var trials_per_game := 12
## Ring radius as a fraction of the smaller screen side.
@export_range(0.1, 0.5) var radius := 0.35
@export var target_radius := 40.0
@export var cursor_radius := 14.0
## Cursor speed in pixels per second at 100% force.
@export var max_speed := 400.0
## Seconds the cursor has to stay on the target to hit it.
@export var hold_seconds := 0.5
## Seconds before a trial counts as a miss.
@export var timeout_seconds := 15.0
## Seconds between trials, showing the result.
@export var pause_seconds := 1.0

const DIRECTIONS := {
	"up": Vector2.UP,
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
}
const DEFAULT_CONTROLS := {
	"up": "open_hand",
	"down": "fist",
	"left": "wrist_left",
	"right": "wrist_right",
}

const RING_COLOR := Color(1, 1, 1, 0.25)
const TARGET_COLOR := Color(1.0, 0.85, 0.3)
const HIT_COLOR := Color(0.3, 0.9, 0.4)
const MISS_COLOR := Color(0.95, 0.35, 0.3)
const CURSOR_COLOR := Color(0.35, 0.75, 1.0)

@onready var _arena: Control = %Arena
@onready var _info: Label = %Info
@onready var _menu: Control = %Menu
@onready var _menu_text: Label = %MenuText
@onready var _start_button: Button = %StartButton
# Direction name -> its OptionButton on the menu.
@onready var _pickers := {
	"up": %UpPicker,
	"down": %DownPicker,
	"left": %LeftPicker,
	"right": %RightPicker,
}
# Direction name -> gesture name (or NO_GESTURE), as picked on the menu.
var _controls := DEFAULT_CONTROLS.duplicate()
var _playing := false
# Trials finished in the current game.
var _trial := 0
# Cursor position relative to the screen center.
var _cursor := Vector2.ZERO
var _target := -1
var _trial_time := 0.0
var _hold_time := 0.0
# > 0 while showing the result of the last trial.
var _pause := 0.0
var _last_hit := false
var _hits := 0
var _misses := 0
var _hit_time_sum := 0.0
# Picks the targets; seeded the same on every PC in versus.
var _rng := RandomNumberGenerator.new()

# Versus: peer id -> hits this game.
var _scores := {}
# Versus: peer id -> their cursor, in ring radii from the center.
var _others := {}
# Versus: who won the last trial (0 = nobody), and whether you sent a hit for this one.
var _trial_winner := 0
var _claimed := false
var _sync_timer := 0.0


func _ready() -> void:
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
	for direction in DIRECTIONS:
		# A gesture the current model does not have can never be detected.
		if not choices.has(_controls[direction]):
			_controls[direction] = NO_GESTURE
		var picker: OptionButton = _pickers[direction]
		picker.clear()
		for choice in choices:
			picker.add_item(choice)
		picker.select(choices.find(_controls[direction]))
		picker.item_selected.connect(func(index: int) -> void: _set_control(direction, choices[index]))


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
		# The host starts the game for everyone once all are ready (began).
		_start_button.disabled = true
		Versus.set_ready()
	else:
		_rng.randomize()
		_start_game()


func _show_menu(result: String) -> void:
	_playing = false
	_target = -1
	_cursor = Vector2.ZERO
	var model := "Model ready." if Emg.has_model() else "No gesture model yet: press Calibrate first\n(arrow keys still work)."
	_menu_text.text = (result + "\n\n" if result != "" else "") + model
	_start_button.disabled = false
	_menu.show()


func _load_controls() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for direction in DIRECTIONS:
		_controls[direction] = config.get_value("controls", direction, _controls[direction])


func _set_control(direction: String, gesture: String) -> void:
	_controls[direction] = gesture
	var config := ConfigFile.new()
	for d in DIRECTIONS:
		config.set_value("controls", d, _controls[d])
	config.save(SETTINGS_PATH)


func _controls_text() -> String:
	var parts: Array[String] = []
	for direction in DIRECTIONS:
		if _controls[direction] != NO_GESTURE:
			parts.append("%s = %s" % [_controls[direction], direction])
	return ", ".join(parts)


func _start_game() -> void:
	_menu.hide()
	_hits = 0
	_misses = 0
	_hit_time_sum = 0.0
	_trial = 0
	_pause = 0.0
	_playing = true
	_scores.clear()
	for id in Versus.player_ids():
		_scores[id] = 0
	_next_trial()


func _finish_game() -> void:
	var average := "  Avg time %.1f s" % (_hit_time_sum / _hits) if _hits > 0 else ""
	var result := "Hits %d / %d%s" % [_hits, _trial, average]
	if Versus.active:
		result = "Game over!\n" + _scores_text("\n")
		_start_button.text = "Ready for a rematch"
	_show_menu(result)


func _unhandled_input(event: InputEvent) -> void:
	if _playing and event.is_action_pressed("ui_cancel"):
		if Versus.active:
			_leave_versus()
		else:
			_finish_game()


func _next_trial() -> void:
	var previous := _target
	while _target == previous:
		_target = _rng.randi() % target_count
	_cursor = Vector2.ZERO
	_trial_time = 0.0
	_hold_time = 0.0
	_claimed = false
	for id in _others:
		_others[id] = Vector2.ZERO


func _end_trial(hit: bool) -> void:
	_last_hit = hit
	if hit:
		_hits += 1
		_hit_time_sum += _trial_time
	else:
		_misses += 1
	_trial += 1
	_pause = pause_seconds


func _target_position(index: int) -> Vector2:
	# First target straight up, the rest clockwise.
	var angle := -PI / 2.0 + TAU * index / target_count
	return Vector2.from_angle(angle) * _ring_radius()


func _ring_radius() -> float:
	return radius * minf(_arena.size.x, _arena.size.y)


func _velocity() -> Vector2:
	var keys := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if keys != Vector2.ZERO:
		return keys * max_speed
	var gesture := Emg.get_gesture()
	if not Emg.is_gesture(gesture):
		return Vector2.ZERO
	# Sum of every direction this gesture is picked for, so it can go diagonal.
	var direction := Vector2.ZERO
	for d in DIRECTIONS:
		if _controls[d] == gesture:
			direction += DIRECTIONS[d]
	var force := Emg.get_force() if Emg.recognizer.has_force_calibration() else 1.0
	return direction.normalized() * force * max_speed


func _process(delta: float) -> void:
	if _playing:
		_update_game(delta)
	var average := "%.1f s" % (_hit_time_sum / _hits) if _hits > 0 else "-"
	_info.text = "Trial %d / %d   Hits %d   Misses %d   Avg time %s\nGesture: %s (%d%%)   Force %d%%\n%s   (Esc = %s)" % [
		mini(_trial + 1, trials_per_game), trials_per_game, _hits, _misses, average,
		Emg.get_gesture(), roundi(Emg.get_confidence() * 100.0), roundi(Emg.get_force() * 100.0),
		_controls_text(), "leave" if Versus.active else "stop",
	]
	if Versus.active and _playing:
		_info.text += "\n\n" + _scores_text("   ")
	_arena.queue_redraw()


func _update_game(delta: float) -> void:
	if _pause > 0.0:
		_pause -= delta
		if _pause <= 0.0:
			if _trial >= trials_per_game:
				_finish_game()
			else:
				_next_trial()
		return

	_trial_time += delta
	var limit := _arena.size / 2.0 - Vector2.ONE * cursor_radius
	_cursor = (_cursor + _velocity() * delta).clamp(-limit, limit)
	if Versus.active:
		_update_versus(delta)
		return
	if _cursor.distance_to(_target_position(_target)) <= target_radius:
		_hold_time += delta
		if _hold_time >= hold_seconds:
			_end_trial(true)
			return
	else:
		_hold_time = 0.0
	if _trial_time >= timeout_seconds:
		_end_trial(false)


func _on_arena_draw() -> void:
	var center := _arena.size / 2.0
	_arena.draw_arc(center, radius * minf(_arena.size.x, _arena.size.y), 0.0, TAU, 96, RING_COLOR, 1.0, true)
	_arena.draw_circle(center, 4.0, RING_COLOR)

	for i in target_count:
		var pos := center + _target_position(i)
		if i != _target:
			_arena.draw_arc(pos, target_radius, 0.0, TAU, 48, RING_COLOR, 2.0, true)
		elif _pause > 0.0:
			var color := HIT_COLOR if _last_hit else MISS_COLOR
			if Versus.active:
				color = Versus.player_color(_trial_winner) if _trial_winner != 0 else MISS_COLOR
			_arena.draw_circle(pos, target_radius, color)
		else:
			_arena.draw_circle(pos, target_radius, Color(TARGET_COLOR, 0.35))
			_arena.draw_arc(pos, target_radius, 0.0, TAU, 48, TARGET_COLOR, 3.0, true)
			# Hold progress as an arc filling up around the target.
			if _hold_time > 0.0:
				var progress := _hold_time / hold_seconds
				_arena.draw_arc(pos, target_radius + 6.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 48, HIT_COLOR, 5.0, true)

	if _playing and Versus.active:
		var font := _arena.get_theme_default_font()
		for id in _others:
			var pos: Vector2 = center + _others[id] * _ring_radius()
			_arena.draw_circle(pos, cursor_radius, Color(Versus.player_color(id), 0.8))
			_arena.draw_string(font, pos + Vector2(-40, cursor_radius + 16), Versus.player_name(id), HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Versus.player_color(id))
		# Yours on top, in your color with a white ring.
		_arena.draw_circle(center + _cursor, cursor_radius, Versus.player_color(multiplayer.get_unique_id()))
		_arena.draw_arc(center + _cursor, cursor_radius + 2.0, 0.0, TAU, 32, Color.WHITE, 2.0, true)
	elif _playing:
		_arena.draw_circle(center + _cursor, cursor_radius, CURSOR_COLOR)


#region Versus

func _setup_versus() -> void:
	Versus.began.connect(_on_versus_began)
	Versus.ready_changed.connect(_on_ready_changed)
	Online.player_disconnected.connect(_on_player_left)
	%CalibrateButton.hide()
	_start_button.text = "Ready"
	%MainMenuButton.text = "Back to lobby" if Versus.is_host() else "Leave match"
	for id in Versus.player_ids():
		if id != multiplayer.get_unique_id():
			_others[id] = Vector2.ZERO


func _leave_versus() -> void:
	if Versus.is_host():
		Versus.back_to_lobby()
	else:
		Versus.leave()


func _on_versus_began() -> void:
	# Same seed on every PC, so everyone gets the same targets in the same order.
	_rng.seed = Versus.game_seed
	_target = -1
	_start_game()


func _on_ready_changed() -> void:
	if not _playing and _start_button.disabled:
		_menu_text.text = "Waiting for: " + Versus.waiting_for()


func _on_player_left(data: PlayerData) -> void:
	_others.erase(data.multiplayer_id)
	_scores.erase(data.multiplayer_id)


func _update_versus(delta: float) -> void:
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = 1.0 / SYNC_RATE
		_cursor_state.rpc(_cursor / maxf(_ring_radius(), 1.0))

	if _cursor.distance_to(_target_position(_target)) <= target_radius and not _claimed:
		_hold_time += delta
		if _hold_time >= hold_seconds:
			# The host decides who was first; until then keep waiting here.
			_claimed = true
			_claim_hit.rpc_id(1, _trial)
	elif not _claimed:
		_hold_time = 0.0
	if Versus.is_host() and _trial_time >= timeout_seconds:
		_trial_result.rpc(_trial, 0)


@rpc("any_peer", "unreliable_ordered")
func _cursor_state(cursor: Vector2) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _others.has(id):
		_others[id] = cursor


# Host only: the first hit for the current trial wins it.
@rpc("any_peer", "call_local", "reliable")
func _claim_hit(trial: int) -> void:
	if multiplayer.is_server() and trial == _trial and _pause <= 0.0:
		_trial_result.rpc(trial, multiplayer.get_remote_sender_id())


@rpc("authority", "call_local", "reliable")
func _trial_result(trial: int, winner: int) -> void:
	if trial != _trial or not _playing:
		return
	_trial_winner = winner
	if winner != 0:
		_scores[winner] = _scores.get(winner, 0) + 1
	_end_trial(winner == multiplayer.get_unique_id())


# Players by hits, best first, joined with the separator.
func _scores_text(separator: String) -> String:
	var ids := Versus.player_ids()
	ids.sort_custom(func(a: int, b: int) -> bool: return _scores.get(a, 0) > _scores.get(b, 0))
	var parts: Array[String] = []
	for id in ids:
		var you := " (you)" if id == multiplayer.get_unique_id() else ""
		parts.append("%s%s: %d" % [Versus.player_name(id), you, _scores.get(id, 0)])
	return separator.join(parts)

#endregion
