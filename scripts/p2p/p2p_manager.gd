extends Node
## P2P transport layer — direct ENet peer-to-peer between clients once a match
## is assigned. This is a NEW standalone module; it does not modify any existing
## game code. Wire the lobby/queue UI to it via the signals below.
##
## Roles:
##   - HOST: the peer that called host(). Owns the roster and is authority.
##   - CLIENTS: peers that called join(). Their peer ids are assigned by the host.
##
## The existing dedicated server (dedicated_server.gd) is the *coordination*
## layer (rooms, queue, server browser). This manager is the actual low-latency
## *transport* used once peers are matched.

signal connected_to_host()
signal peer_joined(peer_id: int, player_info: Dictionary)
signal peer_left(peer_id: int)
signal server_disconnected()
signal connection_failed()
signal message_received(sender_id: int, msg_type: String, data: Dictionary)
signal rtt_updated(rtt_ms: float)

const DEFAULT_PORT: int = 7700
const MAX_PLAYERS: int = 12

## Whether the local peer is the host (peer id 1).
var is_host: bool = false
## Whether we currently have an active P2P session.
var is_active: bool = false
## Local peer id assigned by the host (1 on host).
var unique_id: int = 0

## Local player info broadcast to every peer on join.
var player_info: Dictionary = {"name": "Player"}

## Roster: peer_id -> player_info dictionary.
var players: Dictionary = {}

## The reachable "ip:port" address other peers use to join this host. Populated
## automatically by host()/host_auto(); never shown to the user.
var connect_address: String = ""

var _pending_ping_time: float = 0.0
var _last_rtt: float = 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Seed the local display name from GameState (if present).
	var gs: Node = get_node_or_null("/root/GameState")
	if gs and gs.get("logged_in_username") != null:
		var uname: String = str(gs.get("logged_in_username"))
		if not uname.is_empty():
			player_info["name"] = uname


# ── Session control ──────────────────────────────────────────────────────────

## Become the host and listen for inbound peers. Returns OK or an error code.
func host(port: int = DEFAULT_PORT, max_players: int = 0, server_name: String = "") -> Error:
	if max_players <= 0:
		max_players = MAX_PLAYERS
	if not server_name.is_empty():
		player_info["name"] = server_name
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, max_players)
	if err != OK:
		push_error("P2PManager: Failed to host on port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	_clear_session()
	is_host = true
	is_active = true
	unique_id = multiplayer.get_unique_id()  # 1 on host
	players[unique_id] = player_info.duplicate()
	connect_address = "%s:%d" % [detect_local_address(), port]
	print("P2PManager: Hosting on port %d (id %d)" % [port, unique_id])
	return OK


## Carefully pick a free port and host, then auto-detect the reachable local
## address. No manual port/IP entry needed.
func host_auto(max_players: int = 0, server_name: String = "") -> Error:
	if max_players <= 0:
		max_players = MAX_PLAYERS
	if not server_name.is_empty():
		player_info["name"] = server_name
	for port: int in range(DEFAULT_PORT, DEFAULT_PORT + 24):
		var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		var err: Error = peer.create_server(port, max_players)
		if err != OK:
			continue
		multiplayer.multiplayer_peer = peer
		_clear_session()
		is_host = true
		is_active = true
		unique_id = multiplayer.get_unique_id()  # 1 on host
		players[unique_id] = player_info.duplicate()
		connect_address = "%s:%d" % [detect_local_address(), port]
		print("P2PManager: Hosting on port %d (id %d)" % [port, unique_id])
		return OK
	return ERR_UNAVAILABLE


## Connect to a host given as an "ip:port" (or bare "ip") address string.
func join_address(address: String) -> Error:
	var ip: String = address.strip_edges()
	var port: int = DEFAULT_PORT
	if ip.contains(":"):
		var parts: PackedStringArray = ip.split(":")
		ip = parts[0].strip_edges()
		port = int(parts[1]) if parts.size() > 1 else DEFAULT_PORT
	return join(ip, port)


## Connect to a host at the given IP/port. Returns OK or an error code.
func join(ip: String, port: int = DEFAULT_PORT) -> Error:
	if ip.is_empty():
		ip = "127.0.0.1"
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		push_error("P2PManager: Failed to join %s:%d: %s" % [ip, port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	_clear_session()
	is_host = false
	is_active = true
	print("P2PManager: Joining %s:%d" % [ip, port])
	return OK


## Best-effort local address (LAN IP when present, else loopback). Used only to
## advertise the host; never surfaced in the UI.
func detect_local_address() -> String:
	for ip: String in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"


## Tear down the current P2P session.
func leave() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_session()
	is_active = false
	is_host = false


# ── Messaging ────────────────────────────────────────────────────────────────

## Send a message to every peer (including the host). Reliable.
func broadcast(msg_type: String, data: Dictionary = {}) -> void:
	relay_message.rpc(msg_type, data, player_info.get("name", "Player"))


## Send a message to every peer, unreliable (for high-frequency position sync).
func broadcast_unreliable(msg_type: String, data: Dictionary = {}) -> void:
	relay_message_unreliable.rpc(msg_type, data)


## Send a message to one specific peer. Reliable.
func send_to(peer_id: int, msg_type: String, data: Dictionary = {}) -> void:
	relay_message.rpc_id(peer_id, msg_type, data, player_info.get("name", "Player"))


## Measure round-trip time to the host. Emits rtt_updated when the echo returns.
func measure_rtt() -> void:
	if not is_active or is_host:
		return
	_pending_ping_time = Time.get_ticks_msec()
	ping_pong.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func relay_message(msg_type: String, data: Dictionary, _origin: String = "") -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0 and is_host:
		sender = unique_id
	message_received.emit(sender, msg_type, data)


@rpc("any_peer", "call_local", "unreliable")
func relay_message_unreliable(msg_type: String, data: Dictionary) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0 and is_host:
		sender = unique_id
	message_received.emit(sender, msg_type, data)


@rpc("any_peer", "call_local", "reliable")
func ping_pong() -> void:
	if is_host:
		ping_pong_back.rpc_id(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func ping_pong_back() -> void:
	if _pending_ping_time > 0.0:
		_last_rtt = Time.get_ticks_msec() - _pending_ping_time
		_pending_ping_time = 0.0
		rtt_updated.emit(_last_rtt)


# ── Roster management ────────────────────────────────────────────────────────

## Host: register a freshly-connected peer's info and tell it the roster.
func _on_peer_connected(peer_id: int) -> void:
	if not is_host:
		return
	_register_player.rpc_id(peer_id, player_info)
	# Send the full known roster to the new peer.
	for pid: int in players:
		if pid != peer_id:
			_register_player.rpc_id(peer_id, players[pid], pid)


## Host: run when a peer asks to register. Client: run when the host tells it
## about a peer (including itself).
@rpc("any_peer", "call_local", "reliable")
func _register_player(new_player_info: Dictionary, known_peer_id: int = -1) -> void:
	var peer_id: int = known_peer_id
	if peer_id < 0:
		peer_id = multiplayer.get_remote_sender_id()
		if peer_id == 0 and is_host:
			peer_id = unique_id
	players[peer_id] = new_player_info.duplicate()
	peer_joined.emit(peer_id, new_player_info.duplicate())


func _on_connected_to_server() -> void:
	unique_id = multiplayer.get_unique_id()
	players[unique_id] = player_info.duplicate()
	peer_joined.emit(unique_id, player_info.duplicate())
	connected_to_host.emit()
	print("P2PManager: Connected to host, assigned id %d" % unique_id)


func _on_peer_disconnected(peer_id: int) -> void:
	players.erase(peer_id)
	peer_left.emit(peer_id)


func _on_connection_failed() -> void:
	print("P2PManager: Connection failed")
	_clear_session()
	is_active = false
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("P2PManager: Host disconnected")
	_clear_session()
	is_active = false
	server_disconnected.emit()


func _clear_session() -> void:
	players.clear()
	unique_id = 0
	_last_rtt = 0.0
	_pending_ping_time = 0.0