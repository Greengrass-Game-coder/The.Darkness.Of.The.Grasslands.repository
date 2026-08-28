extends Node
# Unified dedicated game server — TCPServer + WebSocketPeer (one per connection).
# Absorbed server_main.gd: this is the single server implementation.
# The game-state sync handlers (position/hp/elimination/ability/puzzle) were
# merged in from the former server_main.gd.

## Run: godot --headless res://scenes/server.tscn
## Port: 8080 (overridable via PORT env var)

var server_port: int = 8080
const MAX_PLAYERS: int = 12  # Increased for public testing (was 9)
const MATCH_DURATION_ROUND: float = 240.0
const MATCH_DURATION_LMS: float = 195.0
const LOBBY_ANALYSIS_DURATION: float = 60.0

# ---- Account storage ----
const ACCOUNTS_FILE: String = "user://server_accounts.dat"
const SALT_LEN: int = 16
var _accounts: Dictionary = {}  # username_lower -> {hash, salt, username}

# ---- Save data storage ----
var _player_saves: Dictionary = {}  # username -> {money, rings, ...}

# ---- Server state ----
var _tcp_server: TCPServer = null
var _peers: Dictionary = {}  # peer_id -> WebSocketPeer
var _peer_info: Dictionary = {}  # peer_id -> {username, role, is_admin, hp, ...}
var _next_peer_id: int = 1

enum MatchPhase {
	WAITING_FOR_PLAYERS,
	LOBBY_ANALYSIS,
	ROUND_ACTIVE,
	LAST_MAN_STANDING,
	MATCH_END
}

var _phase: MatchPhase = MatchPhase.WAITING_FOR_PLAYERS
var _phase_timer: float = 0.0
var _queued_players: Array[int] = []  # peer_ids in queue
var _private_rooms: Dictionary = {}  # code -> {host_peer_id, players: []}
var _force_ai_killer: bool = false  # Set by "G force AI" command
var _admin_password: String = "Moon996633"
var _current_match_id: int = 0


# ═══════════════ LIFECYCLE ═══════════════

func _ready() -> void:
	if OS.has_environment("PORT"):
		server_port = int(OS.get_environment("PORT"))
	_load_accounts()
	_start_server()


func _start_server() -> void:
	_tcp_server = TCPServer.new()
	var err: int = _tcp_server.listen(server_port)
	if err != OK:
		push_error("DedicatedServer: Failed to listen on port ", server_port, ": ", error_string(err))
		get_tree().quit(1)
		return
	print("DedicatedServer: Listening on port ", server_port, " (accounts: ", _accounts.size(), ")")


func _process(_delta: float) -> void:
	_accept_new_connections()
	_poll_peers()
	_advance_phase(_delta)


func _accept_new_connections() -> void:
	while _tcp_server and _tcp_server.is_connection_available():
		var stream: StreamPeerTCP = _tcp_server.take_connection()
		if not stream:
			continue
		var ws: WebSocketPeer = WebSocketPeer.new()
		var err: int = ws.accept_stream(stream)
		if err != OK:
			continue
		var pid: int = _next_peer_id
		_next_peer_id += 1
		_peers[pid] = ws
		_peer_info[pid] = {
			"username": "Player_%d" % pid,
			"role": "survivor",
			"is_admin": false,
			"hp": 100.0,
			"max_hp": 100.0,
			"alive": true,
			"in_queue": false,
			"room_code": "",
			"avatar_type": "Lobby Person",
			"x": 0.0,
			"y": 0.0
		}
		_send_to(pid, "connected", {"player_id": pid, "players": _get_player_summaries()})
		_broadcast_player_list()
		print("DedicatedServer: Peer connected: ", pid)


func _poll_peers() -> void:
	var disconnected: Array[int] = []
	for pid: int in _peers:
		var ws: WebSocketPeer = _peers[pid]
		if not ws:
			disconnected.append(pid)
			continue
		
		ws.poll()
		var state: int = ws.get_ready_state()
		
		if state == WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0:
				var raw: PackedByteArray = ws.get_packet()
				var text: String = raw.get_string_from_utf8()
				var data: Dictionary = JSON.parse_string(text) as Dictionary
				if data and data.has("type"):
					_handle_client_message(pid, data)
		
		elif state == WebSocketPeer.STATE_CLOSED:
			disconnected.append(pid)
	
	for pid: int in disconnected:
		_on_peer_disconnected(pid)


func _on_peer_disconnected(pid: int) -> void:
	var ws: WebSocketPeer = _peers.get(pid)
	if ws:
		ws.close(1000, "Server close")
	_peers.erase(pid)
	_peer_info.erase(pid)
	_queued_players.erase(pid)
	for code: String in _private_rooms.keys():
		_private_rooms[code]["players"].erase(pid)
	_broadcast_player_list()
	print("DedicatedServer: Peer disconnected: ", pid)


# ═══════════════ PHASES ═══════════════

func _advance_phase(delta: float) -> void:
	match _phase:
		MatchPhase.WAITING_FOR_PLAYERS:
			if _queued_players.size() >= MAX_PLAYERS:
				_start_match()
		
		MatchPhase.LOBBY_ANALYSIS:
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				_broadcast_phase("ROUND_ACTIVE", MATCH_DURATION_ROUND)
				_phase = MatchPhase.ROUND_ACTIVE
				_phase_timer = MATCH_DURATION_ROUND
		
		MatchPhase.ROUND_ACTIVE:
			_phase_timer -= delta
			var alive_survivors: int = _count_alive("survivor")
			var alive_killers: int = _count_alive("killer")
			if alive_survivors <= 0 or alive_killers <= 0:
				_phase_timer = 0.0
			if _phase_timer <= 0.0:
				if alive_survivors <= 1 and alive_killers >= 1:
					_broadcast_phase("LAST_MAN_STANDING", MATCH_DURATION_LMS)
					_phase = MatchPhase.LAST_MAN_STANDING
					_phase_timer = MATCH_DURATION_LMS
				else:
					_end_match()
		
		MatchPhase.LAST_MAN_STANDING:
			_phase_timer -= delta
			var alive_survivors: int = _count_alive("survivor")
			var alive_killers: int = _count_alive("killer")
			if alive_survivors <= 0 or alive_killers <= 0:
				_phase_timer = 0.0
			if _phase_timer <= 0.0:
				_end_match()
		
		MatchPhase.MATCH_END:
			_broadcast_phase("LOBBY_ANALYSIS", LOBBY_ANALYSIS_DURATION)
			_phase = MatchPhase.LOBBY_ANALYSIS
			_phase_timer = LOBBY_ANALYSIS_DURATION


func _count_alive(role: String) -> int:
	var count: int = 0
	for pid: int in _peer_info:
		var p: Dictionary = _peer_info[pid]
		if p["role"] == role and p["alive"]:
			count += 1
	return count


func _start_match() -> void:
	_current_match_id += 1
	var peer_ids: Array[int] = _queued_players.duplicate()
	_queued_players.clear()
	
	for i: int in range(peer_ids.size()):
		var pid: int = peer_ids[i]
		if not _peer_info.has(pid):
			continue
		if i == 0:
			_peer_info[pid]["role"] = "killer"
		else:
			_peer_info[pid]["role"] = "survivor"
		_peer_info[pid]["alive"] = true
	
	# Tell each player their role
	for pid: int in peer_ids:
		if not _peer_info.has(pid):
			continue
		var role: String = _peer_info[pid]["role"]
		_send_to(pid, "game_started", {
			"role": role,
			"player_list": _get_player_summaries(),
			"force_ai_killer": _force_ai_killer
		})
	
	_force_ai_killer = false  # Reset flag after use
	_phase = MatchPhase.ROUND_ACTIVE
	_phase_timer = MATCH_DURATION_ROUND
	_broadcast_phase("ROUND_ACTIVE", MATCH_DURATION_ROUND)
	print("DedicatedServer: Match ", _current_match_id, " started with ", peer_ids.size(), " players")


func _end_match() -> void:
	_broadcast_phase("LOBBY_ANALYSIS", LOBBY_ANALYSIS_DURATION)
	_phase = MatchPhase.LOBBY_ANALYSIS
	_phase_timer = LOBBY_ANALYSIS_DURATION
	print("DedicatedServer: Match ended")


# ═══════════════ BROADCASTING ═══════════════

func _broadcast_player_list() -> void:
	var list: Array[Dictionary] = []
	for pid: int in _peer_info:
		var p: Dictionary = _peer_info[pid]
		list.append({
			"player_id": pid,
			"username": p["username"],
			"role": p["role"],
			"alive": p["alive"]
		})
	_send_to_all("player_list", {"players": list})


func _broadcast_phase(phase: String, time_remaining: float) -> void:
	_send_to_all("phase_changed", {
		"phase": phase,
		"time_remaining": time_remaining
	})


func _get_player_summaries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for pid: int in _peer_info:
		var p: Dictionary = _peer_info[pid]
		list.append({
			"player_id": pid,
			"username": p["username"],
			"role": p["role"]
		})
	return list


func _send_to_all(msg_type: String, payload: Dictionary) -> void:
	for pid: int in _peers:
		_send_to(pid, msg_type, payload)


func _send_to(pid: int, msg_type: String, payload: Dictionary) -> void:
	var ws: WebSocketPeer = _peers.get(pid)
	if not ws:
		return
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var msg: Dictionary = {"type": msg_type}
	msg.merge(payload)
	ws.send_text(JSON.stringify(msg))


# ═══════════════ GAME STATE SYNC (merged from server_main.gd) ═══════════════

func _handle_position_update(pid: int, data: Dictionary) -> void:
	"""Store a player's latest position for state sync."""
	if not _peer_info.has(pid):
		return
	_peer_info[pid]["x"] = data.get("x", 0.0)
	_peer_info[pid]["y"] = data.get("y", 0.0)


func _handle_hp_update(pid: int, data: Dictionary) -> void:
	"""Store a player's latest HP / max HP."""
	if not _peer_info.has(pid):
		return
	_peer_info[pid]["hp"] = data.get("hp", 100.0)
	_peer_info[pid]["max_hp"] = data.get("max_hp", 100.0)


func _handle_player_eliminated(pid: int, data: Dictionary) -> void:
	"""Mark the victim as eliminated and announce it in chat."""
	var victim: String = data.get("victim", "")
	if victim.is_empty():
		return
	for pid2: int in _peer_info:
		if _peer_info[pid2]["username"] == victim:
			_peer_info[pid2]["alive"] = false
			break
	_send_to_all("chat", {"sender": "SERVER", "text": victim + " was eliminated!"})
	print("DedicatedServer: Eliminated: ", victim)


func _handle_ability_used(pid: int, data: Dictionary) -> void:
	"""Track killer/survivor ability usage (stored for future broadcast)."""
	if not _peer_info.has(pid):
		return
	_peer_info[pid]["last_ability"] = data.get("ability", "")
	_peer_info[pid]["ability_x"] = data.get("x", 0.0)
	_peer_info[pid]["ability_y"] = data.get("y", 0.0)


func _handle_puzzle_solved(pid: int, data: Dictionary) -> void:
	"""Track puzzle completions during a match."""
	if not _peer_info.has(pid):
		return
	_peer_info[pid]["puzzle_area"] = data.get("area", "")
	_peer_info[pid]["puzzle_level"] = data.get("level", 1)
	print("DedicatedServer: Puzzle solved by peer ", pid, ": ", data.get("area", ""), " (level ", data.get("level", 1), ")")


# ═══════════════ MESSAGE HANDLING ═══════════════

func _handle_client_message(pid: int, data: Dictionary) -> void:
	var msg_type: String = data.get("type", "")
	match msg_type:
		"register":
			_handle_register(pid, data.get("username", ""), data.get("password", ""))
		"login":
			_handle_login(pid, data.get("username", ""), data.get("password", ""))
		"join_queue":
			_handle_join_queue(pid)
		"leave_queue":
			_handle_leave_queue(pid)
		"chat":
			_handle_chat(pid, data.get("text", ""), data.get("is_admin", false))
		"request_avatar_change":
			_handle_avatar_change(pid, data.get("avatar_type", "Lobby Person"))
		"create_private_server":
			_handle_create_private(pid, data.get("code", ""))
		"join_private_server":
			_handle_join_private(pid, data.get("code", ""))
		"save_data":
			_handle_save_data(pid, data.get("data", {}))
		"load_data":
			_handle_load_data(pid)
		"position_update":
			_handle_position_update(pid, data)
		"hp_update":
			_handle_hp_update(pid, data)
		"player_eliminated":
			_handle_player_eliminated(pid, data)
		"ability_used":
			_handle_ability_used(pid, data)
		"puzzle_solved":
			_handle_puzzle_solved(pid, data)
		_:
			_send_to(pid, "error", {"message": "Unknown type: " + msg_type})


# ═══════════════ ACCOUNTS ═══════════════

func _handle_register(pid: int, username: String, password: String) -> void:
	if username.is_empty() or password.is_empty():
		_send_to(pid, "auth_result", {"success": false, "error": "Username and password required."})
		return
	var key: String = username.to_lower()
	if _accounts.has(key):
		_send_to(pid, "auth_result", {"success": false, "error": "Username already taken."})
		return
	var salt: String = _generate_salt()
	var hash_val: String = _hash_password(password, salt)
	_accounts[key] = {"hash": hash_val, "salt": salt, "username": username}
	_save_accounts()
	if _peer_info.has(pid):
		_peer_info[pid]["username"] = username
	_send_to(pid, "auth_result", {"success": true, "username": username})
	print("DedicatedServer: Registered: ", username)


func _handle_login(pid: int, username: String, password: String) -> void:
	if username.is_empty():
		_send_to(pid, "auth_result", {"success": false, "error": "Username required."})
		return
	var key: String = username.to_lower()
	if not _accounts.has(key):
		# Auto-register if not exists
		_handle_register(pid, username, password)
		return
	var acct: Dictionary = _accounts[key]
	var hash_val: String = _hash_password(password, acct["salt"])
	if hash_val != acct["hash"]:
		_send_to(pid, "auth_result", {"success": false, "error": "Invalid password."})
		return
	var original_username: String = acct.get("username", username)
	if _peer_info.has(pid):
		_peer_info[pid]["username"] = original_username
	_load_player_data(original_username)
	_send_to(pid, "auth_result", {"success": true, "username": original_username})
	print("DedicatedServer: Logged in: ", original_username)


func _hash_password(password: String, salt: String) -> String:
	return (salt + password + salt).sha256_text()


func _generate_salt() -> String:
	var chars: String = "abcdefghijklmnopqrstuvwxyz0123456789"
	var result: String = ""
	for i in range(SALT_LEN):
		result += chars[randi() % chars.length()]
	return result


func _load_accounts() -> void:
	if not FileAccess.file_exists(ACCOUNTS_FILE):
		_accounts = {}
		return
	var file: FileAccess = FileAccess.open(ACCOUNTS_FILE, FileAccess.READ)
	if not file:
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Dictionary = JSON.parse_string(text) as Dictionary
	if parsed:
		_accounts = parsed


func _save_accounts() -> void:
	var file: FileAccess = FileAccess.open(ACCOUNTS_FILE, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify(_accounts))
	file.close()


# ═══════════════ SAVE DATA ═══════════════

func _handle_save_data(pid: int, data: Dictionary) -> void:
	var username: String = _peer_info.get(pid, {}).get("username", "")
	if username.is_empty():
		return
	_player_saves[username] = data.duplicate()
	_save_player_data(username)
	_send_to(pid, "save_data_ack", {})


func _handle_load_data(pid: int) -> void:
	var username: String = _peer_info.get(pid, {}).get("username", "")
	if username.is_empty():
		_send_to(pid, "load_data", {"data": {}})
		return
	var data: Dictionary = _player_saves.get(username, {})
	_send_to(pid, "load_data", {"data": data})


func _save_player_data(username: String) -> void:
	var dir_path: String = "user://server_saves/" + username
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file: FileAccess = FileAccess.open(dir_path + "/save.dat", FileAccess.WRITE)
	if not file:
		return
	var data: Dictionary = _player_saves.get(username, {})
	file.store_string(JSON.stringify(data))
	file.close()


func _load_player_data(username: String) -> void:
	var path: String = "user://server_saves/" + username + "/save.dat"
	if not FileAccess.file_exists(path):
		_player_saves[username] = {}
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Dictionary = JSON.parse_string(text) as Dictionary
	if parsed:
		_player_saves[username] = parsed


# ═══════════════ CHAT / ADMIN / QUEUE / ROOMS ═══════════════

func _handle_join_queue(pid: int) -> void:
	if not _peer_info.has(pid):
		return
	if pid not in _queued_players:
		_queued_players.append(pid)
	_peer_info[pid]["in_queue"] = true
	var pos: int = _queued_players.find(pid) + 1
	_send_to(pid, "queue_status", {"position": pos, "total": _queued_players.size()})
	print("DedicatedServer: Player ", pid, " joined queue (", _queued_players.size(), "/", MAX_PLAYERS, ")")


func _handle_leave_queue(pid: int) -> void:
	_queued_players.erase(pid)
	if _peer_info.has(pid):
		_peer_info[pid]["in_queue"] = false
	_send_to(pid, "queue_status", {"position": 0, "total": _queued_players.size()})


func _handle_chat(pid: int, text: String, is_admin: bool) -> void:
	if not _peer_info.has(pid):
		return
	var username: String = _peer_info[pid]["username"]
	if is_admin:
		_handle_admin_command(pid, text.trim_prefix("G "))
	else:
		_send_to_all("chat", {"sender": username, "text": text})


func _handle_admin_command(pid: int, command: String) -> void:
	var parts: PackedStringArray = command.split(" ", false)
	if parts.is_empty():
		return
	var is_admin_user: bool = _peer_info.get(pid, {}).get("is_admin", false)
	if not is_admin_user:
		if parts[0].to_lower() == "auth" and parts.size() >= 2:
			if parts[1] == _admin_password:
				if _peer_info.has(pid):
					_peer_info[pid]["is_admin"] = true
				_send_to(pid, "admin_result", {"success": true, "message": "Authenticated as admin."})
				return
			else:
				_send_to(pid, "admin_result", {"success": false, "message": "Invalid admin password."})
				return
		_send_to(pid, "admin_result", {"success": false, "message": "Not authenticated as admin."})
		return
	match parts[0].to_lower():
		"end", "round":
			_phase_timer = 0.0
			_send_to_all("admin_result", {"success": true, "message": "Round ended by admin."})
		"kill":
			if parts.size() >= 2:
				var target_name: String = parts[1]
				for pid2: int in _peer_info:
					if _peer_info[pid2]["username"] == target_name:
						_peer_info[pid2]["alive"] = false
						_send_to_all("admin_result", {"success": true, "message": "Player %s eliminated." % target_name})
						return
				_send_to(pid, "admin_result", {"success": false, "message": "Player not found: " + target_name})
		"force", "next":
			# Check if "AI" is mentioned in remaining parts
			var wants_ai: bool = false
			for i in range(1, parts.size()):
				if parts[i].to_lower() == "ai":
					wants_ai = true
					break
			if wants_ai:
				_force_ai_killer = true
				_send_to_all("admin_result", {"success": true, "message": "Next killer forced to AI."})
			else:
				_rotate_killer_role()
				_send_to_all("admin_result", {"success": true, "message": "Next killer forced."})
		"gamemode":
			if parts.size() >= 3 and parts[1].to_lower() == "select" and parts[2].to_lower() == "double" and parts.size() >= 4:
				if parts[3].to_lower() == "trouble":
					_send_to_all("admin_result", {"success": true, "message": "Double Trouble mode enabled."})
		_:
			_send_to(pid, "admin_result", {"success": false, "message": "Unknown command: " + parts[0]})


func _handle_avatar_change(pid: int, avatar_type: String) -> void:
	if not _peer_info.has(pid):
		return
	if avatar_type.is_empty():
		avatar_type = "Lobby Person"
	_peer_info[pid]["avatar_type"] = avatar_type
	_send_to(pid, "avatar_updated", {"avatar_type": avatar_type})
	_broadcast_player_list()


func _handle_create_private(pid: int, code: String) -> void:
	if code.is_empty() or _private_rooms.has(code):
		_send_to(pid, "error", {"message": "Code invalid or already taken."})
		return
	_private_rooms[code] = {"host_peer_id": pid, "players": [pid]}
	if _peer_info.has(pid):
		_peer_info[pid]["room_code"] = code
	_send_to(pid, "private_room_created", {"code": code})


func _handle_join_private(pid: int, code: String) -> void:
	if not _private_rooms.has(code):
		_send_to(pid, "error", {"message": "Room not found: " + code})
		return
	var room: Dictionary = _private_rooms[code]
	if room["players"].size() >= MAX_PLAYERS:
		_send_to(pid, "error", {"message": "Room is full."})
		return
	room["players"].append(pid)
	if _peer_info.has(pid):
		_peer_info[pid]["room_code"] = code
	_send_to(pid, "private_room_joined", {"code": code, "players": room["players"].size()})


func _rotate_killer_role() -> void:
	var current_killer: int = -1
	var survivors: Array[int] = []
	for pid: int in _peer_info:
		if _peer_info[pid]["role"] == "killer":
			current_killer = pid
		elif _peer_info[pid]["role"] == "survivor" and _peer_info[pid]["alive"]:
			survivors.append(pid)
	if current_killer >= 0:
		_peer_info[current_killer]["role"] = "survivor"
	if not survivors.is_empty():
		_peer_info[survivors[0]]["role"] = "killer"
