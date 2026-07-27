extends Node

## Dedicated game server for The Darkness of the Grasslands.
## Runs headless on Railway using WebSocketPeer (matches client protocol).
## Manages match phases, player queues, and private servers.
##
## To run: godot --headless --server server.gd
## Default port: 8080
##
## For Railway: select this scene as main, export as Linux headless server.

const SERVER_PORT: int = int(OS.get_environment("PORT")) if OS.has_environment("PORT") else 8080
const MAX_PLAYERS: int = 9  # 1 killer + 8 survivors
const MATCH_DURATION_ROUND: float = 240.0  # 4 minutes
const MATCH_DURATION_LMS: float = 195.0  # 3.25 minutes
const LOBBY_ANALYSIS_DURATION: float = 60.0
const QUEUE_TIMEOUT: float = 120.0

enum MatchPhase {
	WAITING_FOR_PLAYERS,
	LOBBY_ANALYSIS,
	ROUND_ACTIVE,
	LAST_MAN_STANDING,
	MATCH_END
}

# Server state
var _server: WebSocketMultiplayerPeer = null
var _phase: MatchPhase = MatchPhase.WAITING_FOR_PLAYERS
var _phase_timer: float = 0.0
var _players: Dictionary = {}  # peer_id -> {username, role, is_admin, hp, ...}
var _queued_players: Array[int] = []  # peer_ids in queue
var _private_rooms: Dictionary = {}  # code -> {host_peer_id, players: []}
var _admin_password: String = "Moon996633"
var _current_match_id: int = 0


func _ready() -> void:
	print("DedicatedServer: Starting on port ", SERVER_PORT)
	_start_server()


func _start_server() -> void:
	_server = WebSocketMultiplayerPeer.new()
	var err: int = _server.create_server(SERVER_PORT, "*")
	if err != OK:
		push_error("DedicatedServer: Failed to create server: ", error_string(err))
		get_tree().quit(1)
		return
	
	multiplayer.multiplayer_peer = _server
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	print("DedicatedServer: Server running on port ", SERVER_PORT, " (max ", MAX_PLAYERS, " players)")


func _process(delta: float) -> void:
	# Poll for incoming WebSocket messages
	_poll_incoming()
	
	match _phase:
		MatchPhase.WAITING_FOR_PLAYERS:
			_process_waiting(delta)
		MatchPhase.LOBBY_ANALYSIS:
			_process_lobby_analysis(delta)
		MatchPhase.ROUND_ACTIVE:
			_process_round_active(delta)
		MatchPhase.LAST_MAN_STANDING:
			_process_lms(delta)
		MatchPhase.MATCH_END:
			_process_match_end(delta)


func _process_waiting(_delta: float) -> void:
	# Check if enough players are queued to start
	if _queued_players.size() >= MAX_PLAYERS:
		_start_match()
	elif _queued_players.size() >= 2:
		# Could start with minimum players
		pass


func _process_lobby_analysis(delta: float) -> void:
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		_broadcast_phase_change("ROUND_ACTIVE", MATCH_DURATION_ROUND)
		_phase = MatchPhase.ROUND_ACTIVE
		_phase_timer = MATCH_DURATION_ROUND


func _process_round_active(delta: float) -> void:
	_phase_timer -= delta
	var alive_survivors: int = _count_alive_players("survivor")
	var alive_killers: int = _count_alive_players("killer")
	
	# Check end conditions
	if alive_survivors <= 0 or alive_killers <= 0:
		_phase_timer = 0.0
	
	if _phase_timer <= 0.0:
		# Check if we should enter LMS
		if alive_survivors <= 1 and alive_killers >= 1:
			_broadcast_phase_change("LAST_MAN_STANDING", MATCH_DURATION_LMS)
			_phase = MatchPhase.LAST_MAN_STANDING
			_phase_timer = MATCH_DURATION_LMS
		else:
			_end_match()


func _process_lms(delta: float) -> void:
	_phase_timer -= delta
	var alive_survivors: int = _count_alive_players("survivor")
	var alive_killers: int = _count_alive_players("killer")
	
	if alive_survivors <= 0 or alive_killers <= 0:
		_phase_timer = 0.0
	
	if _phase_timer <= 0.0:
		_end_match()


func _process_match_end(_delta: float) -> void:
	# After match ends, go to lobby analysis phase
	_broadcast_phase_change("LOBBY_ANALYSIS", LOBBY_ANALYSIS_DURATION)
	_phase = MatchPhase.LOBBY_ANALYSIS
	_phase_timer = LOBBY_ANALYSIS_DURATION


# ---------- Player Management ----------

func _on_peer_connected(peer_id: int) -> void:
	print("DedicatedServer: Peer connected: ", peer_id)
	_players[peer_id] = {
		"username": "Player_%d" % peer_id,
		"role": "survivor",
		"is_admin": false,
		"hp": 100.0,
		"max_hp": 100.0,
		"alive": true,
		"in_queue": false,
		"room_code": ""
	}
	_broadcast_player_list()


func _on_peer_disconnected(peer_id: int) -> void:
	print("DedicatedServer: Peer disconnected: ", peer_id)
	_players.erase(peer_id)
	_queued_players.erase(peer_id)
	# Remove from private rooms
	for code: String in _private_rooms.keys():
		_private_rooms[code]["players"].erase(peer_id)
	_broadcast_player_list()


func _count_alive_players(role: String) -> int:
	var count: int = 0
	for pid: int in _players:
		var p: Dictionary = _players[pid]
		if p["role"] == role and p["alive"]:
			count += 1
	return count


# ---------- Queue / Match Start ----------

func _start_match() -> void:
	_current_match_id += 1
	# Assign roles: first peer is killer, rest are survivors
	var peer_ids: Array[int] = _queued_players.duplicate()
	_queued_players.clear()
	
	for i: int in range(peer_ids.size()):
		var pid: int = peer_ids[i]
		if not _players.has(pid):
			continue
		if i == 0:
			_players[pid]["role"] = "killer"
		else:
			_players[pid]["role"] = "survivor"
		_players[pid]["alive"] = true
	
	_broadcast_game_start(peer_ids)
	_phase = MatchPhase.ROUND_ACTIVE
	_phase_timer = MATCH_DURATION_ROUND
	_broadcast_phase_change("ROUND_ACTIVE", MATCH_DURATION_ROUND)
	print("DedicatedServer: Match ", _current_match_id, " started with ", peer_ids.size(), " players")


func _end_match() -> void:
	_broadcast_phase_change("LOBBY_ANALYSIS", LOBBY_ANALYSIS_DURATION)
	_phase = MatchPhase.LOBBY_ANALYSIS
	_phase_timer = LOBBY_ANALYSIS_DURATION
	print("DedicatedServer: Match ended")


# ---------- Broadcasting ----------

func _broadcast_player_list() -> void:
	var list: Array[Dictionary] = []
	for pid: int in _players:
		var p: Dictionary = _players[pid]
		list.append({
			"player_id": pid,
			"username": p["username"],
			"role": p["role"],
			"alive": p["alive"]
		})
	_send_to_all("player_list", {"players": list})


func _broadcast_game_start(peer_ids: Array) -> void:
	for pid: int in peer_ids:
		if not _players.has(pid):
			continue
		var role: String = _players[pid]["role"]
		_send_to_peer(pid, "game_start", {
			"role": role,
			"players": _get_player_summaries()
		})


func _broadcast_phase_change(phase: String, time_remaining: float) -> void:
	_send_to_all("phase_change", {
		"phase": phase,
		"time_remaining": time_remaining
	})


func _get_player_summaries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for pid: int in _players:
		var p: Dictionary = _players[pid]
		list.append({
			"player_id": pid,
			"username": p["username"],
			"role": p["role"]
		})
	return list


func _send_to_all(type: String, payload: Dictionary) -> void:
	for pid: int in _players:
		_send_to_peer(pid, type, payload)


func _poll_incoming() -> void:
	"""Poll for incoming JSON messages from WebSocket clients."""
	if not _server:
		return
	_server.poll()
	while _server.get_available_packet_count() > 0:
		var peer_id: int = _server.get_packet_peer()
		var raw: PackedByteArray = _server.get_packet()
		var json_str: String = raw.get_string_from_utf8()
		var data: Dictionary = JSON.parse_string(json_str) as Dictionary
		if data and data.has("type"):
			_handle_client_message(peer_id, data)


func _handle_client_message(peer_id: int, data: Dictionary) -> void:
	"""Route an incoming client message to the right handler."""
	var msg_type: String = data.get("type", "")
	match msg_type:
		"join_queue":
			_handle_join_queue(peer_id)
		"leave_queue":
			_handle_leave_queue(peer_id)
		"chat":
			_handle_chat(peer_id, data.get("text", ""), data.get("admin", false))
		"create_private":
			_handle_create_private(peer_id, data.get("code", ""))
		"join_private":
			_handle_join_private(peer_id, data.get("code", ""))


func _send_to_peer(peer_id: int, type: String, payload: Dictionary) -> void:
	if not _server:
		return
	var msg: Dictionary = {"type": type}
	msg.merge(payload)
	var json_str: String = JSON.stringify(msg)
	_server.set_target_peer(peer_id)
	_server.put_packet(json_str.to_utf8_buffer())


# ---------- Message Handling ----------

func _handle_join_queue(peer_id: int) -> void:
	if not _players.has(peer_id):
		return
	if peer_id not in _queued_players:
		_queued_players.append(peer_id)
	_players[peer_id]["in_queue"] = true
	_send_to_peer(peer_id, "queue_status", {"position": _queued_players.find(peer_id) + 1, "total": _queued_players.size()})
	print("DedicatedServer: Player ", peer_id, " joined queue (", _queued_players.size(), "/", MAX_PLAYERS, ")")


func _handle_leave_queue(peer_id: int) -> void:
	_queued_players.erase(peer_id)
	if _players.has(peer_id):
		_players[peer_id]["in_queue"] = false
	_send_to_peer(peer_id, "queue_status", {"position": 0, "total": _queued_players.size()})


func _handle_chat(peer_id: int, text: String, is_admin: bool) -> void:
	if not _players.has(peer_id):
		return
	var username: String = _players[peer_id]["username"]
	
	if is_admin:
		_handle_admin_command(peer_id, text)
	else:
		_send_to_all("chat", {"sender": username, "text": text})


func _handle_admin_command(peer_id: int, command: String) -> void:
	var parts: PackedStringArray = command.split(" ", false)
	if parts.is_empty():
		return
	
	var is_admin_user: bool = _players.get(peer_id, {}).get("is_admin", false)
	if not is_admin_user:
		# Allow admin password validation
		if parts[0] == "AUTH" and parts.size() >= 2:
			if parts[1] == _admin_password:
				_players[peer_id]["is_admin"] = true
				_send_to_peer(peer_id, "admin_result", {"success": true, "message": "Authenticated as admin."})
				return
			else:
				_send_to_peer(peer_id, "admin_result", {"success": false, "message": "Invalid admin password."})
				return
		_send_to_peer(peer_id, "admin_result", {"success": false, "message": "Not authenticated as admin."})
		return
	
	match parts[0].to_lower():
		"end", "round":
			_phase_timer = 0.0
			_send_to_all("admin_result", {"success": true, "message": "Round ended by admin."})
		
		"kill":
			if parts.size() >= 2:
				var target_name: String = parts[1]
				for pid: int in _players:
					if _players[pid]["username"] == target_name:
						_players[pid]["alive"] = false
						_send_to_all("admin_result", {"success": true, "message": "Player %s eliminated." % target_name})
						return
				_send_to_peer(peer_id, "admin_result", {"success": false, "message": "Player not found: " + target_name})
		
		"force", "next":
			# Force next killer — rotate roles
			_rotate_killer_role()
			_send_to_all("admin_result", {"success": true, "message": "Next killer forced."})
		
		"gamemode":
			if parts.size() >= 3 and parts[1].to_lower() == "select" and parts[2].to_lower() == "double" and parts.size() >= 4:
				if parts[3].to_lower() == "trouble":
					_send_to_all("admin_result", {"success": true, "message": "Double Trouble mode enabled."})
					# Double Trouble = 2 killers next match
		
		_:
			_send_to_peer(peer_id, "admin_result", {"success": false, "message": "Unknown command: " + parts[0]})


func _handle_create_private(peer_id: int, code: String) -> void:
	if code.is_empty() or _private_rooms.has(code):
		_send_to_peer(peer_id, "error", {"message": "Code invalid or already taken."})
		return
	_private_rooms[code] = {"host_peer_id": peer_id, "players": [peer_id]}
	_players[peer_id]["room_code"] = code
	_send_to_peer(peer_id, "private_room_created", {"code": code})


func _handle_join_private(peer_id: int, code: String) -> void:
	if not _private_rooms.has(code):
		_send_to_peer(peer_id, "error", {"message": "Room not found: " + code})
		return
	var room: Dictionary = _private_rooms[code]
	if room["players"].size() >= MAX_PLAYERS:
		_send_to_peer(peer_id, "error", {"message": "Room is full."})
		return
	room["players"].append(peer_id)
	_players[peer_id]["room_code"] = code
	_send_to_peer(peer_id, "private_room_joined", {"code": code, "players": room["players"].size()})


func _rotate_killer_role() -> void:
	"""Rotate killer role to the next alive survivor."""
	var current_killer: int = -1
	var survivors: Array[int] = []
	for pid: int in _players:
		if _players[pid]["role"] == "killer":
			current_killer = pid
		elif _players[pid]["role"] == "survivor" and _players[pid]["alive"]:
			survivors.append(pid)
	
	if current_killer >= 0:
		_players[current_killer]["role"] = "survivor"
	
	if not survivors.is_empty():
		var next_killer: int = survivors[0]
		_players[next_killer]["role"] = "killer"
