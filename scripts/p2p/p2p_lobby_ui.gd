extends Control
## Host/join lobby UI for the self-hosted P2P layer. This is a TEST/launch UI —
## it is not inserted into the main menu flow and it does not touch game code.
##
## Controls:
##   Host:       name + "List in public browser" -> Create (auto address)
##   Find Match: auto-join the best/friend server (no IPs)
##   Browse:     Refresh -> list public servers -> Join Selected

@onready var status_label: Label = %StatusLabel
@onready var host_name_input: LineEdit = %HostNameInput
@onready var register_public: CheckBox = %RegisterPublic
@onready var create_button: Button = %CreateButton
@onready var leave_button: Button = %LeaveButton
@onready var refresh_button: Button = %RefreshButton
@onready var server_list: ItemList = %ServerList
@onready var join_selected_button: Button = %JoinSelectedButton
@onready var find_match_button: Button = %FindMatchButton
@onready var peers_label: Label = %PeersLabel

var _browser: P2PServerBrowser

const DEFAULT_PORT: int = 7700
const MAX_PLAYERS: int = 12

var _hosting: bool = false
var _connect_address: String = ""


func _ready() -> void:
	register_public.button_pressed = true

	# Browser node (not an autoload) — queries the dedicated server for rooms.
	_browser = P2PServerBrowser.new()
	add_child(_browser)
	_browser.servers_updated.connect(_on_servers_updated)
	_browser.browse_failed.connect(func(msg: String): _log("Browse failed: " + msg))
	_browser.queue_routed.connect(_on_queue_routed)

	var p2p: Node = get_node("/root/P2PManager")
	p2p.connected_to_host.connect(_on_connected)
	p2p.peer_joined.connect(_on_peer_joined)
	p2p.peer_left.connect(_on_peer_left)
	p2p.server_disconnected.connect(func(): _log("Host disconnected."))
	p2p.connection_failed.connect(func(): _log("Connection failed."))
	p2p.message_received.connect(_on_message)

	create_button.pressed.connect(_on_create_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	join_selected_button.pressed.connect(_on_join_selected_pressed)
	find_match_button.pressed.connect(_on_find_match_pressed)

	_log("P2P lobby ready. Host a room or click Find Match to auto-join.")
	# Try the public browser against the configured server, then fall back to a
	# local server (ws://localhost:8080) so the full browse->join flow works on
	# this machine without needing to edit any URL.
	_browse_with_local_fallback()


# ── Host ─────────────────────────────────────────────────────────────────────

func _on_create_pressed() -> void:
	var server_name: String = host_name_input.text.strip_edges()
	if server_name.is_empty():
		server_name = "Host"
	var p2p: Node = get_node("/root/P2PManager")
	var err: Error = p2p.host_auto(MAX_PLAYERS, server_name)
	if err != OK:
		_log("Host failed: " + error_string(err))
		return
	_hosting = true
	_connect_address = str(p2p.connect_address)
	_log("Room ready. %s in the public browser." % ("Listed" if register_public.button_pressed else "Private (not listed)"))

	# Register with the coordination server so the browser/queue can find us.
	if register_public.button_pressed:
		_register_with_server(server_name)


func _register_with_server(server_name: String) -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if not nm or not nm.connected:
		_log("Not connected to matchmaking server - public broadcast skipped.")
		return
	var code: String = "p2p_%d" % Time.get_unix_time_from_system()
	nm.send_json({
		"type": "register_server",
		"code": code,
		"name": server_name,
		"mode": "round",
		"max_players": MAX_PLAYERS,
		"connect_address": _connect_address,
	})
	_log("Room registered in the public browser.")


# ── Find Match / Join (automatic — no IPs) ───────────────────────────────────

func _on_join_selected_pressed() -> void:
	var selected: PackedInt32Array = server_list.get_selected_items()
	if selected.is_empty():
		_log("Select a server first.")
		return
	_join_server(server_list.get_item_metadata(int(selected[0])))


func _on_find_match_pressed() -> void:
	_log("Finding the best match for you...")
	var p2p: Node = get_node("/root/P2PManager")
	if p2p.is_active:
		_log("Already in a P2P session.")
		return
	# Ensure the browser can reach a server (falls back to localhost if needed).
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if not nm or nm.get("connected") != true:
		_connect_local_server()
		await get_tree().create_timer(1.0).timeout
	_browser.browse()
	await get_tree().create_timer(0.6).timeout
	if _browser.queue_for_match():
		_join_server(_browser.last_routed_server)
		return
	# queue_for_match() fell back and already sent join_queue to the dedicated
	# server. That is the free, always-online path (works over the Internet
	# through the existing server — no port-forwarding, no payment). Enter the
	# game scene so it receives the server-driven match start.
	_log("No direct P2P room reachable — joining the free online match queue instead.")
	await get_tree().create_timer(0.4).timeout
	var err: int = get_tree().change_scene_to_file("res://scenes/game_map.tscn")
	if err != OK:
		_log("Could not enter the online match: " + error_string(err))


func _join_server(entry: Dictionary) -> void:
	var server_name: String = str(entry.get("name", "?"))
	var addr: String = str(entry.get("connect_address", ""))
	if addr.is_empty():
		_log("No join address available for '%s'." % server_name)
		return
	# Addresses from the public browser are encrypted (AddressCrypto) — decrypt
	# only at connect time so the raw IP is never shown in the UI/log.
	addr = AddressCrypto.decrypt(addr)
	var err: Error = get_node("/root/P2PManager").join_address(addr)
	if err != OK:
		_log("Could not join '%s': %s" % [server_name, error_string(err)])


func _on_queue_routed(server: Dictionary) -> void:
	_log("Queue routed to: " + str(server.get("name", "?")))


func _on_leave_pressed() -> void:
	get_node("/root/P2PManager").leave()
	_hosting = false
	_log("Left session.")


# ── Browse ───────────────────────────────────────────────────────────────────

func browse() -> void:
	_browser.browse()


## Try browsing via the currently-configured server; if NetworkManager isn't
## connected (e.g. dead pinggy tunnel), fall back to a local server at
## ws://localhost:8080 so the browser works on this machine.
func _browse_with_local_fallback() -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm and nm.get("connected") == true:
		browse()
		return
	_log("Configured server unreachable — trying local server (ws://localhost:8080)...")
	_connect_local_server()


func _connect_local_server() -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if not nm:
		browse()  # No network manager — let the browser report its own error
		return
	if nm.get("connected") == true:
		browse()
		return
	# Auto-start the coordination server via the Python waker if it's not up.
	_launch_server_waker()
	await get_tree().create_timer(2.0).timeout
	if nm.has_method("apply_custom_url"):
		nm.apply_custom_url("ws://localhost:8080")
	if nm.has_method("connect_to_server"):
		nm.connect_to_server()
	await get_tree().create_timer(1.0).timeout
	if nm.get("connected") == true:
		_log("Connected to local server. Browsing public servers...")
	else:
		_log("Local server not reachable — try running tools/server_waker.py, then refresh.")
	browse()


## Launch tools/server_waker.py in the background. It starts the coordination
## server (port 8080) if it isn't already running. Uses --once so it exits
## right after the server is up (no leftover monitor process).
func _launch_server_waker() -> void:
	var project_dir: String = ProjectSettings.globalize_path("res://")
	var waker: String = project_dir.path_join("tools").path_join("server_waker.py")
	if not FileAccess.file_exists(waker):
		_log("server_waker.py not found at " + waker)
		return
	var godot_bin: String = OS.get_executable_path()
	var err: int = OS.create_process("python", ["-u", waker, "--once"])
	if err != OK:
		_log("Could not launch server_waker.py (error %d)." % err)
	else:
		_log("Launched server_waker.py to auto-start the local server.")


func _on_refresh_pressed() -> void:
	_log("Refreshing public servers...")
	_browse_with_local_fallback()


func _on_servers_updated(_list: Array) -> void:
	server_list.clear()
	for s: Dictionary in _browser.rank_servers():
		var server_name: String = str(s.get("name", "?"))
		var mode: String = str(s.get("mode", "round"))
		var count: String = "%s/%s" % [s.get("player_count", 0), s.get("max_players", 0)]
		var host: String = str(s.get("host_username", "?"))
		server_list.add_item("  %s  [%s]  %s  host: %s" % [server_name, mode, count, host])
		var i: int = server_list.get_item_count() - 1
		server_list.set_item_metadata(i, s)


# ── Peer/event handling ──────────────────────────────────────────────────────

func _on_connected() -> void:
	_log("Connected to host. My id: %d" % get_node("/root/P2PManager").unique_id)


func _on_peer_joined(peer_id: int, info: Dictionary) -> void:
	_log("Peer joined: %d (%s)" % [peer_id, str(info.get("name", "?"))])
	_update_peers()


func _on_peer_left(peer_id: int) -> void:
	_log("Peer left: %d" % peer_id)
	_update_peers()


func _on_message(sender_id: int, msg_type: String, data: Dictionary) -> void:
	if msg_type == "chat":
		_log("P2P chat from %d: %s" % [sender_id, str(data.get("text", ""))])


func _update_peers() -> void:
	var p2p: Node = get_node("/root/P2PManager")
	var lines: PackedStringArray = []
	for pid: int in p2p.players:
		lines.append("%d: %s" % [pid, str(p2p.players[pid].get("name", "?"))])
	peers_label.text = "Peers (%d):\n%s" % [p2p.players.size(), "\n".join(lines)]


# ── Helpers ──────────────────────────────────────────────────────────────────

func _log(msg: String) -> void:
	status_label.text += "\n" + msg
	print("[P2PLobby] ", msg)
