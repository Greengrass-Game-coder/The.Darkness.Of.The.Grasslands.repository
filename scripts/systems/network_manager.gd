extends Node
# Autoload — accessible via get_node("/root/NetworkManager")

## Network manager — plain WebSocket client.
## Connects to the dedicated server via playit.gg tunnel (or localhost).
## Maintains the same signal interface for backward compatibility.

signal connected_to_server()
signal disconnected_from_server()
signal connection_failed(error_msg: String)
signal player_joined(player_id: String, username: String)
signal player_left(player_id: String)
signal player_list_updated(players: Array)
signal chat_message_received(sender: String, text: String)
signal match_found(match_data: Dictionary)
signal game_started(role: String, player_list: Array)
signal phase_changed(phase: String, time_remaining: float)
signal admin_command_result(success: bool, message: String)

# Auth & save signals
signal auth_result(success: bool, username: String, error_msg: String)
signal save_data_loaded(data: Dictionary)

# Server → client signals (nothing the server sends is dropped)
signal queue_status_updated(position: int, total: int)
signal save_data_confirmed()
signal avatar_updated(avatar_type: String)
signal private_room_created(code: String)
signal private_room_joined(code: String, player_count: int)
signal server_error(message: String)
signal server_list_received(servers: Array)

const DEFAULT_WS_URL: String = "ws://localhost:8080"
const CONNECT_TIMEOUT: float = 10.0  # seconds before giving up

## Whether we're connected to the server
var connected: bool = false

## Local player ID assigned by server
var player_id: String = "0"

var _ws: WebSocketPeer = null
var _ws_url: String = DEFAULT_WS_URL
var _player_names: Dictionary = {}  # pid -> username
var _connect_elapsed: float = 0.0  # For connection timeout


func _ready() -> void:
	# Get URL from EnvironmentConfig if available
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if env_config and env_config.has_method("get_ws_url"):
		_ws_url = env_config.get_ws_url()
	print("NetworkManager: Starting, WS URL = %s" % _ws_url)


func _process(_delta: float) -> void:
	if _ws:
		_ws.poll()
		var state: int = _ws.get_ready_state()
		
		if state == WebSocketPeer.STATE_OPEN:
			while _ws.get_available_packet_count() > 0:
				var raw: PackedByteArray = _ws.get_packet()
				var text: String = raw.get_string_from_utf8()
				_handle_message(text)
		
		elif state == WebSocketPeer.STATE_CONNECTING:
			_connect_elapsed += _delta
			if _connect_elapsed >= CONNECT_TIMEOUT:
				_ws.close()
				_ws = null
				connection_failed.emit("Connection timed out")
		
		elif state == WebSocketPeer.STATE_CLOSED:
			_disconnected()


func apply_custom_url(url: String) -> void:
	"""Override the WebSocket URL with a user-provided one (e.g. from login screen)."""
	if url.is_empty():
		return
	# Only override if different from default
	if url != _ws_url:
		_ws_url = url
		print("NetworkManager: Custom URL set to %s" % _ws_url)
		# If already connected to a different URL, disconnect first
		if connected or (_ws and _ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING):
			disconnect_from_server()


func connect_to_server() -> void:
	"""Connect to the WebSocket server."""
	if connected:
		return
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		return  # Already connecting
	
	_ws = WebSocketPeer.new()
	var err: Error = _ws.connect_to_url(_ws_url)
	if err != OK:
		connection_failed.emit("Failed to connect: %s" % error_string(err))
		_ws = null
		return
	
	print("NetworkManager: Connecting to %s..." % _ws_url)
	_connect_elapsed = 0.0


func disconnect_from_server() -> void:
	"""Disconnect from the server."""
	if _ws:
		_ws.close()
		_ws = null
	_disconnected()


func _disconnected() -> void:
	if connected:
		connected = false
		GameState.connected_to_server = false
		_player_names.clear()
		disconnected_from_server.emit()
		print("NetworkManager: Disconnected")


func _handle_message(text: String) -> void:
	var json: Dictionary = {}
	var json_parse: JSON = JSON.new()
	var parse_err: Error = json_parse.parse(text)
	if parse_err != OK:
		push_error("NetworkManager: Invalid JSON: %s" % text)
		return
	json = json_parse.data as Dictionary
	if json.is_empty():
		return
	
	var msg_type: String = json.get("type", "")
	match msg_type:
		"connected":
			connected = true
			player_id = str(json.get("player_id", "0"))
			GameState.connected_to_server = true
			GameState.player_id = json.get("player_id", 0)
			print("NetworkManager: Connected, ID = %s" % player_id)
			connected_to_server.emit()
		
		"player_joined":
			var pid: String = str(json.get("player_id", "0"))
			var uname: String = json.get("username", "Unknown")
			_player_names[pid] = uname
			player_joined.emit(pid, uname)
			_emit_player_list()
		
		"player_left":
			var pid: String = str(json.get("player_id", "0"))
			_player_names.erase(pid)
			player_left.emit(pid)
			_emit_player_list()
		
		"player_list":
			var players: Array = json.get("players", [])
			for p: Dictionary in players:
				var pid: String = str(p.get("id", "0"))
				_player_names[pid] = p.get("username", "Unknown")
			_emit_player_list()
		
		"chat":
			chat_message_received.emit(
				json.get("sender", "?"),
				json.get("text", "")
			)
		
		"match_found":
			match_found.emit(json.get("data", {}))
		
		"game_started":
			game_started.emit(
				json.get("role", "survivor"),
				json.get("player_list", [])
			)
		
		"phase_changed":
			phase_changed.emit(
				json.get("phase", ""),
				json.get("time_remaining", 0.0)
			)
		
		"auth_result":
			auth_result.emit(
				json.get("success", false),
				json.get("username", ""),
				json.get("error", "")
			)
		
		"load_data":
			save_data_loaded.emit(json.get("data", {}))
		
		"admin_result":
			admin_command_result.emit(
				json.get("success", false),
				json.get("message", "")
			)
		
		"queue_status":
			queue_status_updated.emit(json.get("position", 0), json.get("total", 0))
		
		"save_data_ack":
			save_data_confirmed.emit()
		
		"avatar_updated":
			avatar_updated.emit(json.get("avatar_type", ""))
		
		"private_room_created":
			private_room_created.emit(json.get("code", ""))
		
		"private_room_joined":
			private_room_joined.emit(json.get("code", ""), json.get("players", 0))
		
		"error":
			server_error.emit(json.get("message", ""))

		"server_list":
			server_list_received.emit(json.get("servers", []))


func _emit_player_list() -> void:
	var list: Array = []
	for pid: String in _player_names:
		list.append({
			"id": pid,
			"username": _player_names[pid]
		})
	player_list_updated.emit(list)


func send_json(data: Dictionary) -> void:
	"""Send a JSON message to the server."""
	if not _ws or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var text: String = JSON.stringify(data)
	_ws.send_text(text)


func send_chat(text: String, is_admin_command: bool = false) -> void:
	"""Send a chat message."""
	var sender: String = GameState.logged_in_username
	if sender.is_empty():
		sender = "Anonymous"
	var msg: Dictionary = {
		"type": "chat",
		"sender": sender,
		"text": text,
		"is_admin": is_admin_command
	}
	send_json(msg)


func send_admin_command(command: String) -> void:
	"""Send an admin command (prefixed with 'G ')."""
	send_chat("G " + command, true)


func join_queue() -> void:
	"""Join the matchmaking queue."""
	if not connected:
		return
	send_json({"type": "join_queue"})


func leave_queue() -> void:
	"""Leave the queue."""
	if not connected:
		return
	send_json({"type": "leave_queue"})


func create_private_server(_code: String) -> void:
	"""Create a private server."""
	if not connected:
		connect_to_server()
		await connected_to_server
	send_json({"type": "create_private_server", "code": _code})


func join_private_server(code: String) -> void:
	"""Join a private server by code."""
	if not connected:
		connect_to_server()
		await connected_to_server
	send_json({"type": "join_private_server", "code": code})


# ═══════════════ AUTH ═══════════════

func register(username: String, password: String) -> void:
	"""Register a new account on the server."""
	send_json({"type": "register", "username": username, "password": password})


func login(username: String, password: String) -> void:
	"""Log in to an existing account on the server."""
	send_json({"type": "login", "username": username, "password": password})


# ═══════════════ SAVE DATA ═══════════════

func save_data(data: Dictionary) -> void:
	"""Save player data to the server."""
	send_json({"type": "save_data", "data": data})


func load_data() -> void:
	"""Request player save data from the server."""
	send_json({"type": "load_data"})
