extends Node

## Per-player save data system with persistence, atomic writes, and backup recovery.
## Every player's progress (money, rings, inventory, settings) is saved
## under user://saves/<username>/ so each user keeps their own stuff.
##
## Features:
##   - Atomic writes: writes to .tmp then renames to save.dat (no corruption on crash)
##   - Backup recovery: keeps save.dat.bak for fallback on corrupt files
##   - Schema versioning: saves a version field for future migration
##   - Validation on load: checks for required keys before returning
##
## Usage:
##   SaveManager.save_player_data("PlayerName", data_dict)
##   var data = SaveManager.load_player_data("PlayerName")
##   SaveManager.autosave("PlayerName")      # quick save of GameState fields
##   SaveManager.autoload("PlayerName")      # quick restore to GameState

const SAVE_DIR: String = "user://saves"
const SAVE_VERSION: int = 1  # Increment when schema changes

## Key structure for a player save file.
static func save_path(username: String) -> String:
	return "%s/%s/save.dat" % [SAVE_DIR, _sanitize_username(username)]

## Backup path for corruption recovery.
static func backup_path(username: String) -> String:
	return "%s/%s/save.dat.bak" % [SAVE_DIR, _sanitize_username(username)]

## Temp file path for atomic writes.
static func temp_path(username: String) -> String:
	return "%s/%s/save.tmp" % [SAVE_DIR, _sanitize_username(username)]


## Save data for the given username with atomic write + backup.
## Creates the directory if it doesn't exist.
static func save_player_data(username: String, data: Dictionary) -> bool:
	var clean_username: String = _sanitize_username(username)
	var path: String = save_path(clean_username)
	var tmp_path: String = temp_path(clean_username)
	var backup: String = backup_path(clean_username)
	var dir: String = path.get_base_dir()

	# Ensure directory exists
	if not _ensure_dir(dir):
		return false

	# Add schema version to save data
	data["_save_version"] = SAVE_VERSION

	# Step 1: Write to .tmp file (atomic)
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: Cannot write temp file %s" % tmp_path)
		return false

	var json_str: String = JSON.stringify(data, "\t")
	file.store_string(json_str)
	file.close()

	# Step 2: Rename existing save.dat to .bak (backup)
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, backup)

	# Step 3: Rename .tmp to save.dat (atomic commit)
	var rename_err: int = DirAccess.rename_absolute(tmp_path, path)
	if rename_err != OK:
		push_error("SaveManager: Failed to rename temp file (err=%d)" % rename_err)
		# Try direct write as fallback
		file = FileAccess.open(path, FileAccess.WRITE)
		if not file:
			push_error("SaveManager: Cannot write %s" % path)
			return false
		file.store_string(json_str)
		file.close()

	print("SaveManager: Saved data for '%s' (%d bytes)" % [clean_username, json_str.length()])
	return true


## Load data for the given username with automatic backup recovery.
## Returns an empty Dictionary if no save exists or all recovery attempts fail.
static func load_player_data(username: String) -> Dictionary:
	var clean_username: String = _sanitize_username(username)
	var path: String = save_path(clean_username)
	var backup: String = backup_path(clean_username)

	# Try primary save file first
	if FileAccess.file_exists(path):
		var data: Dictionary = _read_json_file(path)
		if not data.is_empty():
			# Validate schema version
			if _validate_save(data):
				return data
			else:
				push_warning("SaveManager: Save file has incompatible schema version, trying backup...")

	# Try backup file
	if FileAccess.file_exists(backup):
		push_warning("SaveManager: Attempting recovery from backup...")
		var backup_data: Dictionary = _read_json_file(backup)
		if not backup_data.is_empty() and _validate_save(backup_data):
			# Restore backup to primary location
			DirAccess.copy_absolute(backup, path)
			print("SaveManager: Recovered save from backup for '%s'" % clean_username)
			return backup_data
		else:
			push_error("SaveManager: Backup file also corrupt for '%s'" % clean_username)

	return {}


## Delete save data for a username (including backup).
static func delete_player_data(username: String) -> bool:
	var clean_username: String = _sanitize_username(username)
	var path: String = save_path(clean_username)
	var backup: String = backup_path(clean_username)
	var tmp: String = temp_path(clean_username)
	var deleted: bool = false

	if FileAccess.file_exists(path):
		if DirAccess.remove_absolute(path) == OK:
			deleted = true
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)

	return deleted


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
		"player_rounds": GameState.player_rounds.duplicate(true),
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
	if data.has("player_rounds") and data.player_rounds is Dictionary:
		GameState.player_rounds = data.player_rounds.duplicate(true)
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


# ── Private helpers ──

static func _sanitize_username(username: String) -> String:
	"""Sanitize username for filesystem safety: lowercase, no path separators."""
	var safe: String = username.to_lower().strip_edges()
	# Remove any path separators or special chars that could escape the directory
	safe = safe.replace("/", "_").replace("\\", "_").replace("..", "_")
	return safe


static func _ensure_dir(dir_path: String) -> bool:
	"""Create directory chain if it doesn't exist."""
	var dir_access := DirAccess.open("user://")
	if not dir_access:
		push_error("SaveManager: Cannot open user://")
		return false

	if dir_access.dir_exists(dir_path):
		return true

	var err: int = dir_access.make_dir_recursive(dir_path)
	if err != OK:
		push_error("SaveManager: Failed to create dir %s (err=%d)" % [dir_path, err])
		return false
	return true


static func _read_json_file(path: String) -> Dictionary:
	"""Read and parse a JSON file. Returns empty dict on failure."""
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}

	var json_str: String = file.get_as_text()
	file.close()

	if json_str.is_empty():
		return {}

	var result: Variant = JSON.parse_string(json_str)
	if result is Dictionary:
		return result

	push_error("SaveManager: Corrupt save file at %s" % path)
	return {}


static func _validate_save(data: Dictionary) -> bool:
	"""Validate that the save data has a compatible schema version."""
	if not data.has("_save_version"):
		# Legacy saves (before versioning) — accept them
		return true
	var version: int = data["_save_version"] as int
	if version > SAVE_VERSION:
		# Save was written by a newer version — incompatible
		push_warning("SaveManager: Save version %d is newer than current %d" % [version, SAVE_VERSION])
		return false
	return true
