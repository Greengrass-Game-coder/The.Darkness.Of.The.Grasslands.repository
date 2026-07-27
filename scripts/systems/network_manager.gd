extends Node

## WebSocket client that connects to the Railway-hosted game server.
## Autoload — accessible globally as NetworkManager.

signal connected_to_server()
signal disconnected_from_server()
signal connection_failed(error_msg: String)
signal player_joined(player_id: int, username: String)
signal player_left(player_id: int)
signal player_list_updated(players: Array)
signal chat_message_received(sender: String, text: String)
signal match_found(match_data: Dictionary)
signal game_started(role: String, player_list: Array)
signal phase_changed(phase: String, time_remaining: float)
signal admin_command_result(success: bool, mesconst RAILWAY_URL: String = "wss://the-darkness-server.onrender.com"6.up.railway.app"
const RECONNECT_DELAY: float = 3.0
const MAX_RECONNECT_ATTEMPTS: int = 5

var socket: WebSocketMultiplayerPeer = null
var connected: bool = false
var player_id: int = 0
var reconnect_attempts: int = 0
var _reconnect_timer: float = 0.0
var _in_queue: bool = false
var _handlers: Dictionary = {}


func _ready() -> void:
	_register_handlers()


func _register_handlers() -> void:
	_handlers["connected"] = _on_server_connected
	_handlers["disconnected"] = _on_server_disconnected
	_handlers["player_joined"] = _on_player_joined
	_handlers["player_left"] = _on_player_left
	_handlers["player_list"] = _on_player_list
	_handlers["chat"] = _on_chat_message
	_handlers["match_found"] = _on_match_found
	_handlers["game_start"] = _on_game_start
	_handlers["phase_change"] = _on_phase_change
	_handlers["admin_result"] = _on_admin_result
	_handlers["error"] = _on_server_error


func connect_to_server() -> void:
	"""Connect to the Railway WebSocket server."""
	if connected:
		return
	
	socket = WebSocketMultiplayerPeer.new()
	var player_name: String = GameState.logged_in_username if GameState.logged_in_username.is_empty() == false else "Player"
	var url: String = RAILWAY_URL + "?player_name=" + player_name.uri_encode()
	var err: int = socket.create_client(url)
	
	if err != OK:
		connection_failed.emit("Failed to create WebSocket client: " + error_string(err))
		return
	
	multiplayer.multiplayer_peer = socket
	_connect_signals()
	reconnect_attempts = 0
	print("NetworkManager: Connecting to ", RAILWAY_URL)


func _connect_signals() -> void:
	if not socket:
		return
	if not socket.connection_succeeded.is_connected(_on_socket_connected):
		socket.connection_succeeded.connect(_on_socket_connected)
	if not socket.connection_failed.is_connected(_on_socket_connect_failed):
		socket.connection_failed.connect(_on_socket_connect_failed)
	if not socket.server_disconnected.is_connected(_on_socket_disconnected):
		socket.server_disconnected.connect(_on_socket_disconnected)


func _on_socket_connected() -> void:
	connected = true
	reconnect_attempts = 0
	connected_to_server.emit()
	print("NetworkManager: Connected to Railway server")


func _on_socket_connect_failed() -> void:
	connected = false
	connection_failed.emit("Connection refused by server")
	_try_reconnect()


func _on_socket_disconnected() -> void:
	connected = false
	GameState.connected_to_server = false
	disconnected_from_server.emit()
	print("NetworkManager: Disconnected from server")
	_try_reconnect()


func _try_reconnect() -> void:
	if reconnect_attempts < MAX_RECONNECT_ATTEMPTS:
		reconnect_attempts += 1
		print("NetworkManager: Reconnect attempt %d/%d in %.1fs..." % [reconnect_attempts, MAX_RECONNECT_ATTEMPTS, RECONNECT_DELAY])
		_reconnect_timer = RECONNECT_DELAY


func _process(delta: float) -> void:
	# Handle reconnect timer
	if _reconnect_timer > 0:
		_reconnect_timer -= delta
		if _reconnect_timer <= 0:
			connect_to_server()
	
	# Poll for incoming packets
	if not connected or not socket:
		return
	
	socket.poll()
	if socket.get_available_packet_count() > 0:
		var raw: PackedByteArray = socket.get_packet()
		var json_str: String = raw.get_string_from_utf8()
		var data: Dictionary = JSON.parse_string(json_str) as Dictionary
		if data and data.has("type"):
			var handler: Callable = _handlers.get(data["type"], Callable())
			if handler.is_valid():
				handler.call(data)


func send_message(type: String, payload: Dictionary = {}) -> void:
	"""Send a JSON message to the server."""
	if not connected or not socket:
		return
	var msg: Dictionary = {"type": type}
	msg.merge(payload)
	var json_str: String = JSON.stringify(msg)
	socket.put_packet(json_str.to_utf8_buffer())


# ---------- High-level API ----------

func join_queue() -> void:
	"""Join the matchmaking queue."""
	_in_queue = true
	send_message("join_queue", {"role_preference": "survivor"})


func leave_queue() -> void:
	"""Leave the matchmaking queue."""
	_in_queue = false
	send_message("leave_queue")


func create_private_server(code: String) -> void:
	"""Create a private server with a join code."""
	send_message("create_private", {"code": code})
	GameState.in_private_server = true
	GameState.private_server_code = code


func join_private_server(code: String) -> void:
	"""Join a private server using a code."""
	send_message("join_private", {"code": code})
	GameState.in_private_server = true
	GameState.private_server_code = code


func send_chat(text: String, is_admin_command: bool = false) -> void:
	"""Send a chat message or admin command."""
	send_message("chat", {"text": text, "admin": is_admin_command})


func send_admin_command(command: String) -> void:
	"""Send a G-prefix admin command."""
	send_chat("G " + command, true)


# ---------- Message Handlers ----------

func _on_server_connected(data: Dictionary) -> void:
	player_id = data.get("player_id", 0)
	GameState.connected_to_server = true
	GameState.player_id = player_id


func _on_server_disconnected(_data: Dictionary) -> void:
	GameState.connected_to_server = false
	_in_queue = false


func _on_player_joined(data: Dictionary) -> void:
	var pid: int = data.get("player_id", 0)
	var pname: String = data.get("username", "Unknown")
	player_joined.emit(pid, pname)


func _on_player_left(data: Dictionary) -> void:
	var pid: int = data.get("player_id", 0)
	player_left.emit(pid)


func _on_player_list(data: Dictionary) -> void:
	var players: Array = data.get("players", [])
	player_list_updated.emit(players)


func _on_chat_message(data: Dictionary) -> void:
	var sender: String = data.get("sender", "System")
	var text: String = data.get("text", "")
	chat_message_received.emit(sender, text)


func _on_match_found(data: Dictionary) -> void:
	_in_queue = false
	match_found.emit(data)


func _on_game_start(data: Dictionary) -> void:
	var role: String = data.get("role", "survivor")
	var players: Array = data.get("players", [])
	GameState.player_role = role
	GameState.is_killer = (role == "killer")
	game_started.emit(role, players)


func _on_phase_change(data: Dictionary) -> void:
	var phase: String = data.get("phase", "")
	var time_remaining: float = data.get("time_remaining", 0.0)
	phase_changed.emit(phase, time_remaining)


func _on_admin_result(data: Dictionary) -> void:
	var success: bool = data.get("success", false)
	var msg: String = data.get("message", "")
	admin_command_result.emit(success, msg)


func _on_server_error(data: Dictionary) -> void:
	var msg: String = data.get("message", "Unknown error")
	print("NetworkManager: Server error - ", msg)


func disconnect_from_server() -> void:
	"""Cleanly disconnect from the server."""
	if socket:
		socket.close()
	connected = false
	_in_queue = false
	GameState.connected_to_server = false
	if multiplayer.multiplayer_peer == socket:
		multiplayer.multiplayer_peer = null
	socket = null
