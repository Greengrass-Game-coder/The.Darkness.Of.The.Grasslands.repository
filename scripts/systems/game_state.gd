extends Node

## Whether the local player is playing as the killer
var is_killer: bool = false

## Player avatar type for cosmetic selection in lobby
var avatar_type: String = "Lobby Person"

## Display name — shown in chat & leaderboard instead of username
var display_name: String = ""

## Authentication and network state
var logged_in_username: String = ""
var is_admin: bool = false
var is_limited_admin: bool = false  # Reserved testers with limited admin panel access
var connected_to_server: bool = false
var player_id: int = 0
var player_role: String = ""
var game_phase: String = ""
var match_in_progress: bool = false
var in_private_server: bool = false
var private_server_code: String = ""
var double_trouble: bool = false
var force_killer: bool = false
var lms_enabled: bool = false
var pending_join_code: String = ""

## Which character scene to spawn for the player
var selected_survivor: String = "Greengrass"  # Will be set from CharacterData
var selected_killer: String = "Violentgrass"  # Will be set from CharacterData

## User settings (persisted across scenes, not yet saved to disk)
var hide_leaderboard: bool = false
var epilepsy_safe_mode: bool = true

## Money tracking per player
var player_money: int = 0

## Rings (Killer chance) tracking per player
var player_rings: Dictionary = {}

## Rounds played tracking per player (persisted for profile popup display)
var player_rounds: Dictionary = {}

func add_money(amount: int) -> void:
	"""Add to the player's money."""
	player_money += amount

func spend_money(amount: int) -> bool:
	"""Spend money if available. Returns true if successful."""
	if player_money >= amount:
		player_money -= amount
		return true
	return false

func set_player_rings(player_name: String, rings: int) -> void:
	player_rings[player_name] = rings

func get_player_rings(player_name: String) -> int:
	return player_rings.get(player_name, 0)

func set_player_rounds(player_name: String, rounds: int) -> void:
	player_rounds[player_name] = rounds

func get_player_rounds(player_name: String) -> int:
	return player_rounds.get(player_name, 0)

func add_player_round(player_name: String) -> void:
	player_rounds[player_name] = player_rounds.get(player_name, 0) + 1

func get_players_sorted_by_rings() -> Array[String]:
	"""Return player names sorted by rings (descending)."""
	var names: Array[String] = []
	for pname: String in player_rings:
		names.append(pname)
	names.sort_custom(func(a: String, b: String) -> bool:
		return player_rings.get(a, 0) > player_rings.get(b, 0)
	)
	return names

## Match-end analysis state (passed from game_map to lobby)
var show_analysis: bool = false
var match_character_name: String = "Greengrass"
var match_damage_taken: float = 0.0
var match_damage_dealt: float = 0.0

## Carry-over flag: set when a match ends while the LMS finale was playing, so
## the lobby plays the LMS track (intermission carry-over) instead of its tune.
var returning_from_lms: bool = false
