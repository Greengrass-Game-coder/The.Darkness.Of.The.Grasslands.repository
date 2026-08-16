class_name P2PServerBrowser
extends Node
## Client-side server browser + friend-aware matchmaking queue.
##
## Talks to the existing dedicated server (a *coordination* layer) to list public
## P2P rooms, then ranks them so the queue can pick the best server — favouring
## rooms that contain the player's friends (FriendsManager), then lowest ping,
## then most open slots. The actual data transport after a room is picked is
## P2PManager (ENet), not this node.

signal servers_updated(servers: Array)
signal browse_failed(message: String)
signal queue_routed(server: Dictionary)

## Most recent server list from the server: [{code,name,mode,player_count,max_players,host_username,connect_address,players}]
var servers: Array = []

## The last server we routed the queue into (empty until a successful route).
var last_routed_server: Dictionary = {}

var _browse_pending: bool = false


func _ready() -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm:
		nm.server_error.connect(_on_server_error)
		nm.server_list_received.connect(on_server_list)


# ── Browse ───────────────────────────────────────────────────────────────────

## Ask the dedicated server for the current public P2P server list.
func browse() -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if not nm or not nm.connected:
		browse_failed.emit("Not connected to the matchmaking server.")
		return
	_browse_pending = true
	nm.send_json({"type": "browse_servers"})


## Handle an incoming server_list message (connected by NetworkManager listener).
func on_server_list(list: Array) -> void:
	servers = list
	_browse_pending = false
	servers_updated.emit(servers)


func _on_server_error(message: String) -> void:
	if _browse_pending:
		_browse_pending = false
	browse_failed.emit(message)


# ── Ranking ──────────────────────────────────────────────────────────────────

## Rank servers best-first. Friends present outrank everything; then lower ping
## (by connect_order when known is not available, we use open slots as a proxy);
## then more open slots so rooms fill up rather than playing 1v1.
func rank_servers(friend_names: Array = []) -> Array:
	var ranked: Array = servers.duplicate()
	var friend_set: Dictionary = {}
	for f: String in friend_names:
		if not f.is_empty():
			friend_set[f.to_lower()] = true
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_friend: int = _friend_count(a, friend_set)
		var b_friend: int = _friend_count(b, friend_set)
		if a_friend != b_friend:
			return a_friend > b_friend
		var a_open: int = int(a.get("max_players", 0)) - int(a.get("player_count", 0))
		var b_open: int = int(b.get("max_players", 0)) - int(b.get("player_count", 0))
		if a_open != b_open:
			return a_open > b_open
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)
	return ranked


## The first server that contains at least one of the given friends, or {} if none.
func find_friend_server(friend_names: Array = []) -> Dictionary:
	var friend_set: Dictionary = {}
	for f: String in friend_names:
		if not f.is_empty():
			friend_set[f.to_lower()] = true
	for s: Dictionary in servers:
		if _friend_count(s, friend_set) > 0:
			return s
	return {}


## The single best server to route into, or {} if none.
func best_server() -> Dictionary:
	if servers.is_empty():
		return {}
	return rank_servers(_local_friend_names())[0]


# ── Queue ────────────────────────────────────────────────────────────────────

## Route the queue: prefer a server that contains a friend, else the best-ranked
## server, else fall back to the dedicated server's public queue. Returns true if
## a P2P room was chosen (join it via P2PManager afterwards).
func queue_for_match() -> bool:
	var friends: Array = _local_friend_names()
	# 1) Friend server
	var friend_srv: Dictionary = find_friend_server(friends)
	if not friend_srv.is_empty():
		last_routed_server = friend_srv
		queue_routed.emit(friend_srv)
		return true
	# 2) Best-ranked server
	if not servers.is_empty():
		var best: Dictionary = best_server()
		if not best.is_empty():
			last_routed_server = best
			queue_routed.emit(best)
			return true
	# 3) Fall back to the server's standard public queue
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm and nm.connected:
		nm.send_json({"type": "join_queue"})
	return false


# ── Helpers ──────────────────────────────────────────────────────────────────

func _local_friend_names() -> Array:
	var fm: Node = get_node_or_null("/root/FriendsManager")
	if not fm:
		return []
	var out: Array = []
	for f: Dictionary in fm.cached_friends:
		out.append(str(f.get("name", "")))
	return out


func _friend_count(srv: Dictionary, friend_set: Dictionary) -> int:
	var players_list: Array = srv.get("players", [])
	if players_list.is_empty():
		return 0
	var count: int = 0
	for player_entry: Variant in players_list:
		if friend_set.has(str(player_entry).to_lower()):
			count += 1
	return count