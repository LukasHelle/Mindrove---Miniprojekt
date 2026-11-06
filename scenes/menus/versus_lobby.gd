extends Control

## Versus lobby: host a match or join one by the host's IP, see who is in,
## and (as host) pick a game and start it on every PC. The connection stays
## up between games, which come back here when the host ends them.
##
## Every player needs their own PC and band, and the PCs need to reach each
## other (with the band on WiFi, connect the PCs by Ethernet). The host's
## firewall has to let in UDP port Online.LOCAL_SERVER_PORT.
##
## The UI is laid out in versus_lobby.tscn; only the player rows are added in
## code, since they follow Online.players.

const MAIN_MENU_SCENE := "res://scenes/menus/main_menu.tscn"
const SETTINGS_PATH := "user://versus.cfg"

@onready var _name_edit: LineEdit = %NameEdit
@onready var _connect_box: Control = %ConnectBox
@onready var _match_box: Control = %MatchBox
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _address_label: Label = %AddressLabel
@onready var _players: VBoxContainer = %Players
@onready var _host_controls: Control = %HostControls
@onready var _game_picker: OptionButton = %GamePicker
@onready var _waiting_label: Label = %WaitingLabel
@onready var _status: Label = %Status


func _ready() -> void:
	_load_settings()
	for scene in Versus.GAMES:
		_game_picker.add_item(Versus.GAMES[scene])
	Online.player_connected.connect(func(_data: PlayerData) -> void: _refresh())
	Online.player_disconnected.connect(func(_data: PlayerData) -> void: _refresh())
	_status.text = Versus.message
	Versus.message = ""
	_refresh()


func _load_settings() -> void:
	var data := Online.personal_player_data
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	data.display_name = config.get_value("player", "name", data.display_name)
	# PlayerData starts white; everyone gets their own color for cars and cursors.
	if data.color == Color.WHITE:
		data.color = config.get_value("player", "color", Color.from_hsv(randf(), 0.7, 0.95))
	_address_edit.text = config.get_value("player", "last_host", "")
	_name_edit.text = data.display_name
	_name_edit.add_theme_color_override("font_color", data.color)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "name", Online.personal_player_data.display_name)
	config.set_value("player", "color", Online.personal_player_data.color)
	config.set_value("player", "last_host", _address_edit.text.strip_edges())
	config.save(SETTINGS_PATH)


# Shows the host/join buttons or the match, whichever applies.
func _refresh() -> void:
	var connected := Versus.is_connected_to_match()
	_connect_box.visible = not connected
	_match_box.visible = connected
	_name_edit.editable = not connected
	if not connected:
		return
	# A PC on two networks (e.g. band WiFi + cable) has several; the right one is on the others' network.
	_address_label.text = "Others join with: %s" % " or ".join(Online.get_lan_addresses()) if Versus.is_host() else "Connected to the host."
	_host_controls.visible = Versus.is_host()
	_waiting_label.visible = not Versus.is_host()
	for child in _players.get_children():
		child.queue_free()
	for id in Versus.player_ids():
		var row := Label.new()
		var host := " (host)" if id == 1 else ""
		var you := " (you)" if id == multiplayer.get_unique_id() else ""
		row.text = "● %s%s%s" % [Versus.player_name(id), host, you]
		row.add_theme_color_override("font_color", Versus.player_color(id))
		_players.add_child(row)


func _on_name_changed(new_name: String) -> void:
	Online.personal_player_data.display_name = new_name.strip_edges() if new_name.strip_edges() else "Player"


func _on_host_pressed() -> void:
	_save_settings()
	if Online.host_local_lobby() == Online.ErrorCodes.SUCCESS:
		_status.text = ""
	else:
		_status.text = "Could not host: is port %d already in use?" % Online.LOCAL_SERVER_PORT
	_refresh()


func _on_join_pressed() -> void:
	var address := _address_edit.text.strip_edges()
	if address == "":
		address = Online.LOCAL_SERVER_ADDRESS
	if not address.is_valid_ip_address():
		_status.text = "Type the IP the host's lobby shows, e.g. 192.168.1.20"
		return
	_save_settings()
	_status.text = "Connecting to %s..." % address
	_connect_box.propagate_call("set_disabled", [true])
	var result: Online.ErrorCodes = await Online.join_local_lobby(address)
	_connect_box.propagate_call("set_disabled", [false])
	_status.text = "" if result == Online.ErrorCodes.SUCCESS else "No match found at %s." % address
	_refresh()


func _on_start_pressed() -> void:
	Versus.start_game(Versus.GAMES.keys()[_game_picker.selected])


func _on_leave_pressed() -> void:
	Versus.leave()


func _on_main_menu_pressed() -> void:
	if Versus.is_connected_to_match():
		Online.leave_lobby()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
