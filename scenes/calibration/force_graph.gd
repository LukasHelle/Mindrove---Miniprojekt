extends Control

## Scrolling line graph of force (0..1) with an optional target line and a
## tolerance band around it. Call push() once per frame.

## Seconds of history across the full width.
@export var seconds := 5.0
## Target force, or a negative value to hide the target line.
@export var target := -1.0
## Half-height of the "on target" band around the target line.
@export var tolerance := 0.1

const LINE_COLOR := Color(0.35, 0.75, 1.0)
const TARGET_COLOR := Color(1.0, 0.85, 0.3)
const BAND_COLOR := Color(0.3, 0.9, 0.4, 0.18)
const GRID_COLOR := Color(1, 1, 1, 0.15)
const LABEL_COLOR := Color(1, 1, 1, 0.5)

var _values: Array[float] = []
var _times: Array[float] = []


func _init() -> void:
	custom_minimum_size = Vector2(0, 160)


func push(value: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_values.append(value)
	_times.append(now)
	while not _times.is_empty() and _times[0] < now - seconds:
		_times.pop_front()
		_values.pop_front()
	queue_redraw()


func clear() -> void:
	_values.clear()
	_times.clear()
	queue_redraw()


func is_on_target(value: float) -> bool:
	return target >= 0.0 and absf(value - target) <= tolerance


func _y(value: float) -> float:
	return size.y * (1.0 - clampf(value, 0.0, 1.0))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	var font := get_theme_default_font()
	for level in [0.0, 0.5, 1.0]:
		draw_line(Vector2(0, _y(level)), Vector2(size.x, _y(level)), GRID_COLOR)
		draw_string(font, Vector2(4, clampf(_y(level) - 4, 14, size.y - 4)), "%d%%" % roundi(level * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LABEL_COLOR)

	if target >= 0.0:
		var top := _y(target + tolerance)
		draw_rect(Rect2(0, top, size.x, _y(target - tolerance) - top), BAND_COLOR)
		draw_dashed_line(Vector2(0, _y(target)), Vector2(size.x, _y(target)), TARGET_COLOR, 2.0, 10.0)

	if _values.size() < 2:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var points := PackedVector2Array()
	for i in _values.size():
		var x := size.x * (1.0 - (now - _times[i]) / seconds)
		points.append(Vector2(x, _y(_values[i])))
	draw_polyline(points, LINE_COLOR, 3.0, true)
	# Current value as a dot at the right edge, green when on target.
	var dot_color := Color(0.3, 0.9, 0.4) if is_on_target(_values[-1]) else LINE_COLOR
	draw_circle(points[-1], 6.0, dot_color)
