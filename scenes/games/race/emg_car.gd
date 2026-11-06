extends "res://addons/srcoder_simplecar/assets/scripts/car.gd"

## The srcoder_simplecar car, driven by values set from code (race.gd sets them
## from the EMG gestures) instead of the addon's left/right/up/down actions.
## Steering gets gentler with speed, so holding a full turn does not roll it.

## Speed in m/s at which full steering is halved (lower = calmer at speed).
@export var steer_falloff_speed := 8.0
## Engine power when reversing, 0..1, so holding brake a bit long only creeps back.
@export_range(0.0, 1.0) var reverse_power := 0.3

## 0..1, how much gas.
var gas := 0.0
## 0..1, how much brake. When stopped or rolling backwards it reverses instead.
var brake_amount := 0.0
## -1 (full right) .. 1 (full left).
var steer_amount := 0.0
## Full brake and no gas, whatever the other inputs say.
var parked := true


func get_input(delta: float) -> void:
	var steer_limit := max_steer * steer_falloff_speed / (steer_falloff_speed + linear_velocity.length())
	player_steer = move_toward(player_steer, steer_amount * steer_limit, steer_damping * delta)
	if parked:
		player_acceleration = 0.0
		player_braking = max_brake_force
	elif gas > 0.0:
		player_acceleration = gas
		player_braking = 0.0
	elif brake_amount > 0.0 and going_forward():
		player_acceleration = 0.0
		player_braking = brake_amount * max_brake_force
	else:
		# Negative acceleration reverses, e.g. to back away from a cone.
		player_acceleration = -brake_amount * reverse_power
		player_braking = 0.0
