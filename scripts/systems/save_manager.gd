extends Node

## Per-player save data system.
## Every player's progress (money, rings, inventory, settings) is saved
## under user://saves/<username>/ so each user keeps their own stuff.
##
## Usage:
##   SaveManager.save_player_data("PlayerName", data_dict)
##   var data = SaveManager.load_player_data("PlayerName")

const SAVE_DIR: String = "user://saves"

## Key structure for a player save file.
static func save_path(username: String) -> String:
	return "%s/%s/save.dat" % [SAVE_DIR, username.to_lower().strip_edges()]


## Save data for the given username.
## Creates the directory if it doesn't exist.
static func save_player_data(username: String, data: Dictionary) -> bool:
	var path: String = save_path(username)
	var dir: String = path.get_base_dir()

	var dir_access := DirAccess.open("user://")
	if not dir_access:
		push_error("SaveManager: Cannot open user://")
		return false

	# Create directory chain
	var parts: PackedStringArray = dir.trim_prefix("user://").split("/")
	var current: String = "user://"
	for part in parts:
		if part.is_empty():
			continue
		current = current.path_join(part)
		if not dir_access.dir_exists(current):
			var err: int = dir_access.make_dir_recursive(current)
			if err != OK:
				push_error("SaveManager: Failed to create dir %s (err=%d)" % [current, err])
				return false

	# Write JSON
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: Cannot write %s" % path)
		return false

	var json_str: String = JSON.stringify(data, "\t")
	file.store_string(json_str)
	file.close()
	print("SaveManager: Saved data for '%s' (%d bytes)" % [username, json_str.length()])
	return true


## Load data for the given username.
## Returns an empty Dictionary if no save exists.
static func load_player_data(username: String) -> Dictionary:
	var path: String = save_path(username)

	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}

	var json_str: String = file.get_as_text()
	file.close()

	var result: Variant = JSON.parse_string(json_str)
	if result is Dictionary:
		return result
	return {}


## Delete save data for a username.
static func delete_player_data(username: String) -> bool:
	var path: String = save_path(username)
	if not FileAccess.file_exists(path):
		return false
	var err: int = DirAccess.remove_absolute(path)
	return err == OK


## List all usernames that have save data.
static func list_saved_players() -> Array[String]:
	var dir := DirAccess.open("user://saves")
	if not dir:
		return []

	var names: Array[String] = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and not entry.begins_with("."):
			names.append(entry)
		entry = dir.get_next()
	return names


## Quick autosave ----- saves GameState fields relevant to the player.
static func autosave(username: String) -> bool:
	var data: Dictionary = {
		"player_money": GameState.player_money,
		"player_rings": GameState.player_rings.duplicate(true),
		"avatar_type": GameState.avatar_type,
		"display_name": GameState.display_name,
		"selected_survivor": GameState.selected_survivor,
		"selected_killer": GameState.selected_killer,
		"hide_leaderboard": GameState.hide_leaderboard,
		"epilepsy_safe_mode": GameState.epilepsy_safe_mode,
		"is_admin": GameState.is_admin
	}
	# Also include audio bus volumes
	for bus_name in ["Master", "Music", "SFX"]:
		var bus_idx: int = AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0:
			data["bus_vol_" + bus_name] = AudioServer.get_bus_volume_db(bus_idx)
	return save_player_data(username, data)


## Quick autoload ----- restores GameState fields from save.
static func autoload(username: String) -> bool:
	var data: Dictionary = load_player_data(username)
	if data.is_empty():
		return false

	if data.has("player_money"):
		GameState.player_money = data.player_money
	if data.has("player_rings") and data.player_rings is Dictionary:
		GameState.player_rings = data.player_rings.duplicate(true)
	if data.has("avatar_type"):
		GameState.avatar_type = data.avatar_type
	if data.has("display_name"):
		GameState.display_name = data.display_name
	if data.has("selected_survivor"):
		GameState.selected_survivor = data.selected_survivor
	if data.has("selected_killer"):
		GameState.selected_killer = data.selected_killer
	if data.has("hide_leaderboard"):
		GameState.hide_leaderboard = data.hide_leaderboard
	if data.has("epilepsy_safe_mode"):
		GameState.epilepsy_safe_mode = data.epilepsy_safe_mode
	if data.has("is_admin"):
		GameState.is_admin = data.is_admin
	
	# Restore audio bus volumes
	for bus_name in ["Master", "Music", "SFX"]:
		var key: String = "bus_vol_" + bus_name
		if data.has(key):
			var bus_idx: int = AudioServer.get_bus_index(bus_name)
			if bus_idx >= 0:
				AudioServer.set_bus_volume_db(bus_idx, data[key])

	print("SaveManager: Loaded data for '%s'" % username)
	return true
