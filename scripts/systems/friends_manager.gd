extends Node
# Autoload — accessible via get_node("/root/FriendsManager")

## Friend system — local-only friend lists.
## Stores friend names in a file, no online dependencies.

signal friends_loaded(friends: Array)
@warning_ignore("unused_signal")
signal friend_request_received(from_name: String, display_name: String)
signal friend_request_sent(to_name: String)
signal friend_added(name: String, display_name: String)
signal friend_removed(name: String)
@warning_ignore("unused_signal")
signal friend_online_status_changed(name: String, is_online: bool)

const FRIENDS_FILE: String = "user://friends_cache.dat"

## Cached friend list: [{name, display_name}]
var cached_friends: Array[Dictionary] = []
## Pending incoming requests: [{name, display_name}]
var pending_incoming: Array[Dictionary] = []
## Pending outgoing requests: [{name, display_name}]
var pending_outgoing: Array[Dictionary] = []

var _loaded: bool = false


func _ready() -> void:
	_load_cache()


## Query cached friends list.
func query_friends() -> void:
	if not _loaded:
		_load_cache()
	friends_loaded.emit(cached_friends)


## Send a friend request by username.
func send_friend_request(username: String) -> bool:
	if username.is_empty():
		return false
	# Check not already friends
	for f: Dictionary in cached_friends:
		if f.get("name", "").to_lower() == username.to_lower():
			return false  # Already friends
	var request_entry: Dictionary = {"name": username, "display_name": username}
	pending_outgoing.append(request_entry)
	friend_request_sent.emit(username)
	_save_cache()
	return true


## Accept a friend request.
func accept_friend_request(username: String) -> bool:
	var to_remove: Array = []
	var found: bool = false
	for req: Dictionary in pending_incoming:
		if req.get("name", "").to_lower() == username.to_lower():
			cached_friends.append({"name": username, "display_name": username})
			to_remove.append(req)
			found = true
			break
	for r: Dictionary in to_remove:
		pending_incoming.erase(r)
	if found:
		friend_added.emit(username, username)
		_save_cache()
	return found


## Reject a friend request.
func reject_friend_request(username: String) -> bool:
	var to_remove: Array = []
	var found: bool = false
	for req: Dictionary in pending_incoming:
		if req.get("name", "").to_lower() == username.to_lower():
			to_remove.append(req)
			found = true
			break
	for r: Dictionary in to_remove:
		pending_incoming.erase(r)
	if found:
		_save_cache()
	return found


## Remove a friend.
func remove_friend(username: String) -> void:
	var idx: int = -1
	for i: int in cached_friends.size():
		if cached_friends[i].get("name", "").to_lower() == username.to_lower():
			idx = i
			break
	if idx >= 0:
		cached_friends.remove_at(idx)
		friend_removed.emit(username)
		_save_cache()


## Check if a username is a friend.
func is_friend(username: String) -> bool:
	var lower: String = username.to_lower()
	for f: Dictionary in cached_friends:
		if f.get("name", "").to_lower() == lower:
			return true
	return false


## Load friend list from disk.
func _load_cache() -> void:
	_loaded = true
	if not FileAccess.file_exists(FRIENDS_FILE):
		cached_friends = []
		pending_incoming = []
		pending_outgoing = []
		return
	var file: FileAccess = FileAccess.open(FRIENDS_FILE, FileAccess.READ)
	if not file:
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var friends_arr: Array = parsed.get("friends", [])
		cached_friends = []
		for item: Variant in friends_arr:
			if item is Dictionary:
				cached_friends.append(item)
		var incoming_arr: Array = parsed.get("incoming", [])
		pending_incoming = []
		for item: Variant in incoming_arr:
			if item is Dictionary:
				pending_incoming.append(item)
		var outgoing_arr: Array = parsed.get("outgoing", [])
		pending_outgoing = []
		for item: Variant in outgoing_arr:
			if item is Dictionary:
				pending_outgoing.append(item)


## Save friend list to disk.
func _save_cache() -> void:
	var data: Dictionary = {
		"friends": cached_friends,
		"incoming": pending_incoming,
		"outgoing": pending_outgoing,
	}
	var file: FileAccess = FileAccess.open(FRIENDS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
