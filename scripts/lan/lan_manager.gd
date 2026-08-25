extends Node
## LAN cross-play over a local network using Godot's built-in ENet networking.
##
## One device (the laptop) HOSTS the game on its LAN IP; the other device (the
## phone) JOINS by entering that IP. Everything happens directly over the local
## WiFi — no Ziva relay, no server, no subscription.
##
## The host is peer 1 (the high-level multiplayer "server"). Every joiner is a
## client (peer id > 1) and talks to the host directly.

signal host_started(ip_list: Array)
signal join_started
signal connected_to_host
signal connection_failed
signal host_disconnected
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

const PORT: int = 2456
const MAX_PEERS: int = 2

var is_host: bool = false
var connected: bool = false
var my_peer_id: int = 0

var _local_ips: Array = []


func _ready() -> void:
	_local_ips = _compute_local_ips()


func _compute_local_ips() -> Array:
	# Filter out loopback and APIPA/link-local noise; keep the private LAN IPv4s
	# (192.168.x, 10.x, 172.16-31.x) the phone can actually reach.
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.begins_with("127.") or a.begins_with("169.254"):
			continue
		if ":" in a:
			continue  # skip IPv6 for simplicity
		out.append(a)
	return out


func display_ips() -> String:
	if _local_ips.is_empty():
		return "No LAN IP found — check WiFi"
	return ", ".join(_local_ips)


func primary_ip() -> String:
	if _local_ips.is_empty():
		return ""
	return str(_local_ips[0])


## The laptop calls this to become the host. Binds to all interfaces so the
## phone can reach it over the local network.
func host() -> Error:
	if connected:
		return OK
	stop()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(PORT, MAX_PEERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	connected = true
	my_peer_id = multiplayer.get_unique_id()
	_connect_signals()
	host_started.emit(_local_ips)
	return OK


## The phone calls this to join the laptop's game by its LAN IP.
func join(ip: String) -> Error:
	if connected:
		return OK
	stop()
	var target: String = ip.strip_edges()
	if target.is_empty():
		target = "127.0.0.1"
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(target, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	_connect_signals()
	join_started.emit()
	return OK


func _connect_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(peer_id: int) -> void:
	if is_host:
		peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if is_host:
		peer_left.emit(peer_id)


func _on_connected_to_server() -> void:
	connected = true
	my_peer_id = multiplayer.get_unique_id()
	connected_to_host.emit()


func _on_connection_failed() -> void:
	stop()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	stop()
	host_disconnected.emit()


## Cleanly tear down the network peer (back to a normal single-player game).
func stop() -> void:
	if not connected and multiplayer.multiplayer_peer == null:
		return
	multiplayer.multiplayer_peer = null
	is_host = false
	connected = false
	my_peer_id = 0


func peer_count() -> int:
	var n: int = 0
	for p in multiplayer.get_peers():
		if int(p) > 0:
			n += 1
	return n
