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
var vibration_enabled: bool = true

## Console (arcade room) theme: "system", "light", or "dark". Console-only —
## only changeable inside the arcade console, never in normal settings.
var console_theme: String = "system"

## Money tracking per player
var player_money: int = 0

## Tetrino minigame coin-reward state (persisted via SaveManager):
## - tetrino_coins_earned: total coins earned from Tetrino (0..3; 3 = gamble win)
## - tetrino_last_coin_time: unix time of the most recent coin earned (daily limit)
## - tetrino_gambled: whether the player took the hard-mode gamble (permanent)
## - tetrino_time_penalty_until: if the clock was tampered with, coins unlock only after this
## - tetrino_last_seen_time: last recorded wall-clock time, used to detect roll-backs
var tetrino_coins_earned: int = 0
var tetrino_last_coin_time: int = 0
var tetrino_gambled: bool = false
var tetrino_time_penalty_until: int = 0
var tetrino_last_seen_time: int = 0
## tetrino_coins_spent: coins the player has spent on paid cartridges (so the
## spendable "Grass coin" balance = tetrino_coins_earned - tetrino_coins_spent)
var tetrino_coins_spent: int = 0
## tetrino_owns_paid: permanent ownership of the paid "TETRINO 2" cartridge.
## Once bought (spending coins through the game profile) it stays owned forever.
var tetrino_owns_paid: bool = false
## tetrino_owns_paid3: permanent ownership of the paid "TETRINO 3" cartridge
## (the 3-coin copy). Once bought it stays owned forever, like TETRINO 2.
var tetrino_owns_paid3: bool = false
## tetrino_gift_given: whether the one-time anti-softlock apology gift (2 Grass
## coins + 1,000 gold) has already been granted to this profile.
var tetrino_gift_given: bool = false
## dirtysweeper_owns_paid: permanent ownership of the paid "DIRTYSWEEPER"
## cartridge (2 coins). Once bought it stays owned forever.
var dirtysweeper_owns_paid: bool = false
## dirtysweeper_hard: whether the player last played Dirtysweeper in hard
## (gamble) mode — used to keep the chosen difficulty across sessions.
var dirtysweeper_hard: bool = false

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
