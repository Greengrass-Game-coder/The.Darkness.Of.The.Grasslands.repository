class_name MultiplayerGameSync
extends Node
## Syncs game state between clients during a match via NetworkManager.
## Handles: player positions, HP updates, elimination events,
## killer ability events, and phase transitions.
##
## This bridges the offline-oriented game_map.gd with the 
## DedicatedServer's WebSocket-based multiplayer system.

signal match_started(role: String, player_list: Array)
signal player_disconnected(player_name: String)

# ── References ──
var _is_connected: bool = false
var _player_role: String = "survivor"
var _player_list: Array[Dictionary] = []
var _is_killer: bool = false

# Position sync rate (reserved for throttled updates)
const SYNC_INTERVAL: float = 0.1


func _ready() -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm:
		nm.game_started.connect(_on_game_started)
		nm.player_left.connect(_on_player_left)
		nm.disconnected_from_server.connect(_on_disconnected)
		_is_connected = nm.connected
		(get_node_or_null("/root/GameState") as Node).set("connected_to_server", nm.connected)


func _on_game_started(role: String, player_list: Array) -> void:
	_player_role = role
	_player_list = player_list
	_is_killer = (role == "killer")
	(get_node_or_null("/root/GameState") as Node).set("is_killer", _is_killer)
	print("MultiplayerGameSync: Match started — Role: ", role, " | Players: ", player_list.size())
	match_started.emit(role, player_list)


func _on_player_left(_pid: String) -> void:
	var player_name: String = ""
	for p in _player_list:
		if str(p.get("player_id", "")) == _pid:
			player_name = p.get("username", "Unknown")
			break
	if not player_name.is_empty():
		player_disconnected.emit(player_name)


func _on_disconnected() -> void:
	_is_connected = false
	var gs_c: Node = get_node_or_null("/root/GameState")
	if gs_c:
		gs_c.set("connected_to_server", false)


# ── State Sync ──

func send_position_update(pos: Vector2) -> void:
	if not _is_connected:
		return
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if not nm:
		return
	nm.send_json({
		"type": "position_update",
		"x": pos.x,
		"y": pos.y,
	})


func send_hp_update(current_hp: float, max_hp: float) -> void:
	if not _is_connected:
		return
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if not nm:
		return
	nm.send_json({
		"type": "hp_update",
		"hp": current_hp,
		"max_hp": max_hp,
	})


func send_player_eliminated(victim_name: String) -> void:
	if not _is_connected:
		return
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if not nm:
		return
	nm.send_json({
		"type": "player_eliminated",
		"victim": victim_name,
	})


func send_ability_used(ability_name: String, target_pos: Vector2 = Vector2.ZERO) -> void:
	if not _is_connected:
		return
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if not nm:
		return
	var msg: Dictionary = {
		"type": "ability_used",
		"ability": ability_name,
	}
	if target_pos != Vector2.ZERO:
		msg["x"] = target_pos.x
		msg["y"] = target_pos.y
	nm.send_json(msg)


func send_puzzle_solved(area_name: String, level: int) -> void:
	if not _is_connected:
		return
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if not nm:
		return
	nm.send_json({
		"type": "puzzle_solved",
		"area": area_name,
		"level": level,
	})


# ── Query ──

func is_multiplayer() -> bool:
	return _is_connected


func get_player_role() -> String:
	return _player_role


func is_killer() -> bool:
	return _is_killer


func get_player_count() -> int:
	return _player_list.size()
