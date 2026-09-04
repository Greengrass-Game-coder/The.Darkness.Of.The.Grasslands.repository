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

## Character catalog — the single source of truth for selectable characters.
## Add a new survivor/killer here and it automatically appears in the lobby
## Shop (BUY) and Inventory (EQUIP). `cost` 0 means it's a free starter.
const CHARACTER_CATALOG: Dictionary = {
	"Greengrass": {"kind": "survivor", "cost": 0, "icon": "res://The Darkness Of The Grasslands assets/UI/Lobby/Greengrass - survivor icon.png"},
	"Violentgrass": {"kind": "killer", "cost": 0, "icon": "res://The Darkness Of The Grasslands assets/UI/Lobby/Violentgrass - Killer icon.png"},
}

## Ownership: which characters the player has bought. Starters are owned by
## default. Keyed by character name -> true.
var owned_survivors: Dictionary = {"Greengrass": true}
var owned_killers: Dictionary = {"Violentgrass": true}

## Character helper methods ------------------------------------------------

func is_character_owned(kind: String, name: String) -> bool:
	if kind == "survivor":
		return owned_survivors.get(name, false)
	return owned_killers.get(name, false)


func own_character(kind: String, name: String) -> void:
	if kind == "survivor":
		owned_survivors[name] = true
	else:
		owned_killers[name] = true


func get_equipped_character(kind: String) -> String:
	return selected_survivor if kind == "survivor" else selected_killer


## Equip a character (sets it as selected for its kind). Returns false if the
## player doesn't own it yet.
func equip_character(kind: String, name: String) -> bool:
	if not is_character_owned(kind, name):
		return false
	if kind == "survivor":
		selected_survivor = name
	else:
		selected_killer = name
	return true

## User settings (persisted across scenes, not yet saved to disk)
var hide_leaderboard: bool = false
var epilepsy_safe_mode: bool = true
var vibration_enabled: bool = true
## "Ragdoll" (funny) setting: makes survivor death-flings exactly 100% stronger
## (double launch strength, no more than that). Off by default.
var ragdoll: bool = false

## Console (arcade room) theme: "system", "light", or "dark". Console-only —
## only changeable inside the arcade console, never in normal settings.
var console_theme: String = "system"

## Money tracking per player
var player_money: int = 0

## Tetrivo minigame coin-reward state (persisted via SaveManager):
## - tetrivo_coins_earned: total coins earned from Tetrivo (0..3; 3 = gamble win)
## - tetrivo_last_coin_time: unix time of the most recent coin earned (daily limit)
## - tetrivo_gambled: whether the player took the hard-mode gamble (permanent)
## - tetrivo_time_penalty_until: if the clock was tampered with, coins unlock only after this
## - tetrivo_last_seen_time: last recorded wall-clock time, used to detect roll-backs
var tetrivo_coins_earned: int = 0
var tetrivo_last_coin_time: int = 0
var tetrivo_gambled: bool = false
var tetrivo_time_penalty_until: int = 0
var tetrivo_last_seen_time: int = 0
## tetrivo_coins_spent: coins the player has spent on paid cartridges (so the
## spendable "Grass coin" balance = tetrivo_coins_earned - tetrivo_coins_spent)
var tetrivo_coins_spent: int = 0
## tetrivo_owns_paid: permanent ownership of the paid "TETRIVO 2" cartridge.
## Once bought (spending coins through the game profile) it stays owned forever.
var tetrivo_owns_paid: bool = false
## tetrivo_owns_paid3: permanent ownership of the paid "TETRIVO 3" cartridge
## (the 3-coin copy). Once bought it stays owned forever, like TETRIVO 2.
var tetrivo_owns_paid3: bool = false
## tetrivo_gift_given: whether the one-time anti-softlock apology gift (2 Grass
## coins + 1,000 gold) has already been granted to this profile.
var tetrivo_gift_given: bool = false
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
