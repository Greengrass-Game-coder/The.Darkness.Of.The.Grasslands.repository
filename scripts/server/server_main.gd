extends Node
# Standalone dedicated server scene script replacement.
# This is a simpler, more robust version of dedicated_server.gd
# that handles the server-side of multiplayer game sync.
#
# Run with: godot --headless res://scenes/server.tscn

var server_port: int = 8080
const MAX_PLAYERS: int = 12  # Increased for public testing (was 9)
const MATCH_DURATION: float = 240.0

var _tcp_server: TCPServer = null
var _peers: Dictionary = {}  # peer_id -> WebSocketPeer
var _peer_info: Dictionary = {}  # peer_id -> {username, role, alive, hp, x, y, ...}
var _next_peer_id: int = 1

enum Phase { LOBBY, QUEUE, MATCH, LMS, END }
var _phase: Phase = Phase.LOBBY
var _phase_timer: float = 0.0
var _queued: Array[int] = []

# Account system
var _accounts: Dictionary = {}
var _saves: Dictionary = {}
const ACCOUNTS_FILE: String = "user://accounts.dat"
const SAVES_DIR: String = "user://server_saves/"
const ADMIN_PASSWORD: String = "Moon996633"


func _ready() -> void:
	if OS.has_environment("PORT"):
		server_port = int(OS.get_environment("PORT"))
	_load_accounts()
	_start_server()
	print("══ SERVER READY ══")
	print("Port: ", server_port)
	print("Players: 0/", MAX_PLAYERS)
	print("Phase: LOBBY")
	print("═════════════════")


func _start_server() -> void:
	_tcp_server = TCPServer.new()
	var err: int = _tcp_server.listen(server_port)
	if err != OK:
		push_error("FAILED to listen on port ", server_port)
		get_tree().quit(1)


func _process(_delta: float) -> void:
	_accept_peers()
	_poll_all()
	_update_phase(_delta)


# ── Connections ──

func _accept_peers() -> void:
	while _tcp_server.is_connection_available():
		var stream: StreamPeerTCP = _tcp_server.take_connection()
		if not stream: continue
		var ws := WebSocketPeer.new()
		if ws.accept_stream(stream) != OK: continue
		var pid := _next_peer_id
		_next_peer_id += 1
		_peers[pid] = ws
		_peer_info[pid] = _fresh_player(pid)
		_send(pid, "connected", {"player_id": pid})
		_broadcast_list()
		print("[+] Player ", pid, " connected | Total: ", _peers.size())


func _fresh_player(pid: int) -> Dictionary:
	return {
		"username": "Player_%d" % pid,
		"role": "survivor",
		"alive": true,
		"is_admin": false,
		"hp": 100.0, "max_hp": 100.0,
		"x": 0.0, "y": 0.0,
	}


func _poll_all() -> void:
	var dropped: Array[int] = []
	for pid: int in _peers.keys():
		var ws: WebSocketPeer = _peers[pid]
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					var raw := ws.get_packet()
					_handle(pid, raw.get_string_from_utf8())
			WebSocketPeer.STATE_CLOSED:
				dropped.append(pid)
	for pid in dropped:
		_remove_peer(pid)


func _remove_peer(pid: int) -> void:
	_peers.erase(pid)
	_peer_info.erase(pid)
	_queued.erase(pid)
	_broadcast_list()
	print("[-] Player ", pid, " left | Total: ", _peers.size())


# ── Phases ──

func _update_phase(delta: float) -> void:
	match _phase:
		Phase.LOBBY:
			if _queued.size() >= 2:  # Min 2 to start
				_start_match()
		Phase.MATCH:
			_phase_timer -= delta
			if _phase_timer <= 0 or _count_alive("survivor") == 0:
				_end_match()
		Phase.LMS:
			_phase_timer -= delta
			if _phase_timer <= 0 or _count_alive("survivor") == 0:
				_end_match()
		Phase.END:
			_phase = Phase.LOBBY
			_bc_phase("LOBBY", 0)


func _start_match() -> void:
	var players: Array[int] = _queued.duplicate()
	_queued.clear()
	# Assign killer: first player or highest-ring player
	var killer_idx: int = 0
	for i: int in range(players.size()):
		var pid := players[i]
		_peer_info[pid]["role"] = "killer" if i == killer_idx else "survivor"
		_peer_info[pid]["alive"] = true
		_peer_info[pid]["hp"] = 6666.0 if i == killer_idx else 100.0
		_peer_info[pid]["max_hp"] = 6666.0 if i == killer_idx else 100.0
	
	for pid in players:
		_send(pid, "game_started", {
			"role": _peer_info[pid]["role"],
			"player_list": _get_summaries(),
		})
	
	_phase = Phase.MATCH
	_phase_timer = MATCH_DURATION
	_bc_phase("ROUND_ACTIVE", MATCH_DURATION)
	print("► MATCH STARTED — ", players.size(), " players")


func _end_match() -> void:
	_bc_phase("LOBBY_ANALYSIS", 60)
	_phase = Phase.END
	print("► MATCH ENDED")


func _count_alive(role: String) -> int:
	var c := 0
	for p: Dictionary in _peer_info.values():
		if p["role"] == role and p["alive"]:
			c += 1
	return c


# ── Broadcasting ──

func _bc_phase(phase: String, time_remaining: float) -> void:
	_send_all("phase_changed", {"phase": phase, "time_remaining": time_remaining})


func _broadcast_list() -> void:
	var list: Array[Dictionary] = []
	for pid: int in _peer_info:
		var p: Dictionary = _peer_info[pid]
		list.append({"id": pid, "username": p["username"], "role": p["role"]})
	_send_all("player_list", {"players": list})


func _get_summaries() -> Array[Dictionary]:
	var a: Array[Dictionary] = []
	for pid: int in _peer_info:
		var p: Dictionary = _peer_info[pid]
		a.append({"player_id": pid, "username": p["username"], "role": p["role"]})
	return a


func _send(pid: int, msg_type: String, payload: Dictionary) -> void:
	var ws: WebSocketPeer = _peers.get(pid)
	if not ws or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var msg := payload.duplicate()
	msg["type"] = msg_type
	ws.send_text(JSON.stringify(msg))


func _send_all(msg_type: String, payload: Dictionary) -> void:
	for pid in _peers:
		_send(pid, msg_type, payload)


# ── Message Handler ──

func _handle(pid: int, raw: String) -> void:
	var data: Dictionary = JSON.parse_string(raw) as Dictionary
	if data.is_empty() or not data.has("type"):
		return
	
	var msg_type: String = data["type"]
	match msg_type:
		"login":
			_auth_login(pid, data.get("username", ""), data.get("password", ""))
		"register":
			_auth_register(pid, data.get("username", ""), data.get("password", ""))
		"join_queue":
			if pid not in _queued: _queued.append(pid)
			_send(pid, "queue_status", {"pos": _queued.find(pid) + 1, "total": _queued.size()})
		"leave_queue":
			_queued.erase(pid)
		"chat":
			_on_chat(pid, data.get("text", ""), data.get("is_admin", false))
		"position_update":
			if _peer_info.has(pid):
				_peer_info[pid]["x"] = data.get("x", 0.0)
				_peer_info[pid]["y"] = data.get("y", 0.0)
		"hp_update":
			if _peer_info.has(pid):
				_peer_info[pid]["hp"] = data.get("hp", 100.0)
		"player_eliminated":
			var victim: String = data.get("victim", "")
			for pid2: int in _peer_info:
				if _peer_info[pid2]["username"] == victim:
					_peer_info[pid2]["alive"] = false
			_send_all("chat", {"sender": "SERVER", "text": victim + " was eliminated!"})
		"save_data":
			if _peer_info.has(pid):
				var uname: String = _peer_info[pid]["username"]
				_saves[uname] = data.get("data", {})
				_save_player(uname)
		"load_data":
			if _peer_info.has(pid):
				var uname: String = _peer_info[pid]["username"]
				_send(pid, "load_data", {"data": _saves.get(uname, {})})


# ── Auth ──

func _auth_register(pid: int, username: String, password: String) -> void:
	if username.is_empty():
		_send(pid, "auth_result", {"success": false, "error": "Username required"})
		return
	var key := username.to_lower()
	if _accounts.has(key):
		_send(pid, "auth_result", {"success": false, "error": "Username taken"})
		return
	var salt := _rand_str(16)
	_accounts[key] = {
		"hash": (salt + password + salt).sha256_text(),
		"salt": salt, "username": username
	}
	_save_accounts()
	_peer_info[pid]["username"] = username
	_send(pid, "auth_result", {"success": true, "username": username})
	print("[AUTH] Registered: ", username)


func _auth_login(pid: int, username: String, password: String) -> void:
	var key := username.to_lower()
	if not _accounts.has(key):
		_auth_register(pid, username, password)
		return
	var acct: Dictionary = _accounts[key]
	var h: String = (acct["salt"] + password + acct["salt"]).sha256_text()
	if h != acct["hash"]:
		_send(pid, "auth_result", {"success": false, "error": "Wrong password"})
		return
	_peer_info[pid]["username"] = acct["username"]
	_send(pid, "auth_result", {"success": true, "username": acct["username"]})
	print("[AUTH] Login: ", acct["username"])


# ── Chat ──

func _on_chat(pid: int, text: String, is_admin: bool) -> void:
	var uname: String = _peer_info.get(pid, {}).get("username", "?")
	if is_admin:
		_handle_admin(pid, text.trim_prefix("G "))
		return
	_send_all("chat", {"sender": uname, "text": text})


func _handle_admin(pid: int, cmd: String) -> void:
	var parts := cmd.split(" ", false)
	if parts.is_empty(): return
	var is_admin: bool = _peer_info.get(pid, {}).get("is_admin", false)
	if parts[0].to_lower() == "auth" and parts.size() >= 2:
		if parts[1] == ADMIN_PASSWORD:
			_peer_info[pid]["is_admin"] = true
			_send(pid, "admin_result", {"success": true, "message": "Admin granted"})
		else:
			_send(pid, "admin_result", {"success": false, "message": "Wrong password"})
		return
	if not is_admin:
		_send(pid, "admin_result", {"success": false, "message": "Not admin"})
		return
	
	match parts[0].to_lower():
		"end", "round": _phase_timer = 0
		"kill": 
			if parts.size() >= 2:
				for pid2 in _peer_info:
					if _peer_info[pid2]["username"] == parts[1]:
						_peer_info[pid2]["alive"] = false


# ── Persistence ──

func _rand_str(n: int) -> String:
	var s := ""
	for _i in n:
		s += "abcdefghijklmnopqrstuvwxyz0123456789"[randi() % 36]
	return s


func _save_accounts() -> void:
	var f := FileAccess.open(ACCOUNTS_FILE, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(_accounts)); f.close()


func _load_accounts() -> void:
	if FileAccess.file_exists(ACCOUNTS_FILE):
		var f := FileAccess.open(ACCOUNTS_FILE, FileAccess.READ)
		if f:
			_accounts = (JSON.parse_string(f.get_as_text()) as Dictionary) if JSON.parse_string(f.get_as_text()) is Dictionary else {}
			f.close()


func _save_player(username: String) -> void:
	DirAccess.make_dir_recursive_absolute(SAVES_DIR + username)
	var f := FileAccess.open(SAVES_DIR + username + "/save.dat", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(_saves.get(username, {}))); f.close()
