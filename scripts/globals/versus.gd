extends Node

## Head-to-head matches over the local network, on top of the Online
## autoload's connection (each player on their own PC with their own band).
##
## In versus_lobby.tscn the host picks a game and start_game() loads it on
## every PC. Games check `active` to switch to their versus rules: their menu's
## Start button calls set_ready() instead, and once every player is ready the
## host starts the round for everyone at once (began, with a shared seed).
## Rounds can be replayed the same way until the host goes back_to_lobby().

## Every player is ready: start the round. game_seed is set just before.
signal began
## Someone pressed ready (ready_ids changed).
signal ready_changed

const LOBBY_SCENE := "res://scenes/menus/versus_lobby.tscn"
## Scene path -> name, the games the host can pick.
const GAMES := {
	"res://scenes/games/race/race.tscn": "EMG Race",
	"res://scenes/games/target_reach/target_reach.tscn": "Target Reach",
}

## True while a versus game scene is loaded.
var active := false
## Same on every PC for the current round, for things like the target order.
var game_seed := 0
## Players that pressed ready for the next round.
var ready_ids: Array[int] = []
## Shown once by the lobby, e.g. why the match ended.
var message := ""


func _ready() -> void:
	Online.server_disconnected.connect(func() -> void: leave("The host left the match."))
	Online.player_disconnected.connect(func(_data: PlayerData) -> void: _start_if_all_ready())


func is_connected_to_match() -> bool:
	# Online closes the peer before it reports that you left, so check the status too.
	var peer := multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and not Online.players.is_empty()


func is_host() -> bool:
	return is_connected_to_match() and multiplayer.is_server()


## Multiplayer ids of everyone in the match, the host (1) first.
func player_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(Online.players.keys())
	ids.sort()
	return ids


func player_name(id: int) -> String:
	return Online.players[id].display_name if Online.players.has(id) else "?"


func player_color(id: int) -> Color:
	return Online.players[id].color if Online.players.has(id) else Color.WHITE


## Host only: loads the game on every PC.
func start_game(scene: String) -> void:
	if is_host():
		_load_game.rpc(scene)


@rpc("authority", "call_local", "reliable")
func _load_game(scene: String) -> void:
	active = true
	ready_ids.clear()
	get_tree().change_scene_to_file(scene)


## Called by a game when this player is ready for the next round.
func set_ready() -> void:
	_player_ready.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _player_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	if not ready_ids.has(id):
		ready_ids.append(id)
	_set_ready_ids.rpc(ready_ids)
	_start_if_all_ready()


# Host only, also when someone leaves while the others wait for them.
func _start_if_all_ready() -> void:
	if not is_host() or ready_ids.is_empty():
		return
	for id in player_ids():
		if not ready_ids.has(id):
			return
	_begin.rpc(randi())


@rpc("authority", "call_local", "reliable")
func _set_ready_ids(ids: Array) -> void:
	ready_ids.assign(ids)
	ready_changed.emit()


@rpc("authority", "call_local", "reliable")
func _begin(new_seed: int) -> void:
	game_seed = new_seed
	ready_ids.clear()
	ready_changed.emit()
	began.emit()


## Names of the players that are not ready yet, for "Waiting for ..." texts.
func waiting_for() -> String:
	var names: Array[String] = []
	for id in player_ids():
		if not ready_ids.has(id):
			names.append(player_name(id))
	return ", ".join(names)


## Host only: everyone goes back to the lobby, still connected.
func back_to_lobby() -> void:
	if is_host():
		_go_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _go_to_lobby() -> void:
	active = false
	get_tree().change_scene_to_file(LOBBY_SCENE)


## Disconnects and goes to the lobby screen, showing why.
func leave(why := "") -> void:
	Online.leave_lobby()
	message = why
	active = false
	get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)
