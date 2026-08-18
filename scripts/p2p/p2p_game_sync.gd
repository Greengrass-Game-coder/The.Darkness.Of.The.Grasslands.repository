class_name P2PGameSync
extends Node
## Prepared bridge that mirrors the existing MultiplayerGameSync interface but
## transports over P2PManager (ENet) instead of the WebSocket dedicated server.
##
## This is intentionally NOT wired into game_map.gd — it is a drop-in stand-in so
## that wiring it in later requires no other changes. The message types match the
## ones the dedicated server already understands (position_update, hp_update,
## player_eliminated, ability_used, puzzle_solved).

signal match_started(role: String, player_list: Array)
signal player_disconnected(player_name: String)

const SYNC_INTERVAL: float = 0.1

var _role: String = "survivor"
var _player_list: Array[Dictionary] = []


func _ready() -> void:
	var p2p: Node = get_node_or_null("/root/P2PManager")
	if p2p:
		p2p.peer_left.connect(_on_peer_left)
		p2p.server_disconnected.connect(_on_disconnected)


func _on_peer_left(peer_id: int) -> void:
	var peer_name: String = ""
	var p2p: Node = get_node_or_null("/root/P2PManager")
	if p2p and p2p.players.has(peer_id):
		peer_name = str(p2p.players[peer_id].get("name", "Unknown"))
	for p: Dictionary in _player_list:
		if str(p.get("player_id", "")) == str(peer_id) or str(p.get("username", "")) == peer_name:
			player_disconnected.emit(peer_name)
			return


func _on_disconnected() -> void:
	_player_list.clear()


# ── State sync (mirrors MultiplayerGameSync) ────────────────────────────────

func send_position_update(pos: Vector2) -> void:
	var p2p: Node = get_node_or_null("/root/P2PManager")
	if p2p:
		p2p.broadcast_unreliable("position_update", {"x": pos.x, "y": pos.y})


func send_hp_update(current_hp: float, max_hp: float) -> void:
	var p2p: Node = get_node_or_null("/root/P2PManager")
	if p2p:
		p2p.broadcast("hp_update", {"hp": current_hp, "max_hp": max_hp})


func send_player_eliminated(victim_name: String) -> void:
	var p2p: Node = get_node_or_null("/root/P2PManager")
	if p2p:
		p2p.broadcast("player_eliminated", {"victim": victim_name})


func send_ability_used(ability_name: String, target_pos: Vector2 = Vector2.ZERO) -> void:
	var data: Dictionary = {"ability": ability_name}
	if target_pos != Vector2.ZERO:
		data["x"] = target_pos.x
		data["y"] = target_pos.y
	var p2p: Node = get_node_or_null("/root/P2PManager")
	if p2p:
		p2p.broadcast("ability_used", data)


func send_puzzle_solved(area_name: String, level: int) -> void:
	var p2p: Node = get_node_or_null("/root/P2PManager")
	if p2p:
		p2p.broadcast("puzzle_solved", {"area": area_name, "level": level})


# ── Query ────────────────────────────────────────────────────────────────────

func is_multiplayer() -> bool:
	var p2p: Node = get_node_or_null("/root/P2PManager")
	return p2p != null and p2p.is_active


func get_player_role() -> String:
	return _role


func is_killer() -> bool:
	return _role == "killer"


func get_player_count() -> int:
	var p2p: Node = get_node_or_null("/root/P2PManager")
	if p2p:
		return p2p.players.size()
	return 0