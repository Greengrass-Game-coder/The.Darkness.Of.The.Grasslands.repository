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
	"Greengrass": {
		"kind": "survivor", "cost": 0,
		"icon": "res://The Darkness Of The Grasslands assets/UI/Lobby/Greengrass - survivor icon.png",
		"description": "A gentle grass spirit who heals allies with Spare Flower and blocks attacks with a sturdy punch.",
		"stats": {"HP": "100", "Speed": "160", "Sprint": "250", "Stamina": "100"},
		"abilities": [
			{"name": "Punch (M1)", "desc": "Block incoming attacks and push back enemies"},
			{"name": "Spare Flower (M2)", "desc": "Heal 70 HP — 45s cooldown"}
		]
	},
	"Violentgrass": {
		"kind": "killer", "cost": 0,
		"icon": "res://The Darkness Of The Grasslands assets/UI/Lobby/Violentgrass - Killer icon.png",
		"description": "A ruthless grass killer who teleports through shadows and strikes from unexpected angles.",
		"stats": {"HP": "6666", "Speed": "240", "Sprint": "350", "Stamina": "110", "M1 Damage": "25", "M1 Range": "120px"},
		"abilities": [
			{"name": "Scythe Strike (M1)", "desc": "25 dmg, 120px range — 2.5s cooldown"},
			{"name": "Shadow Teleport (M2)", "desc": "Teleport up to 350px — 45s cooldown"}
		]
	},
	"Test Killer": {
		"kind": "killer", "cost": 1500,
		"icon": "",
		"description": "An experimental monster that ensnares survivors with a long-range tentacle, dragging them through walls.",
		"stats": {"HP": "6666", "Speed": "240", "Sprint": "350", "Stamina": "110", "M1 Damage": "25", "M1 Range": "120px"},
		"abilities": [
			{"name": "Scythe Strike (M1)", "desc": "25 dmg, 120px range — 2.5s cooldown (10 dmg follow-up after snatch)"},
			{"name": "Tentacle Snatch (M2)", "desc": "Remote tentacle — 500px range, 15 catch dmg, wall-hit 2 dmg, 1s stun. 28s/18s/12s cooldown"}
		]
	},
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


## ── Sound Packs: buyable audio layers that play on top of an OST ──────────
## Catalog of buyable sound packs. One entry = one purchasable pack, which can
## hold MULTIPLE audio layers that all play on top of the base OST when equipped.
## `cost` = one-time gold price for the whole bundle. `version` is bumped whenever
## the pack is updated (new sounds / remixes); owners can re-buy the latest version
## for `update_cost` gold. `ost` = which OST the layers sit on ("lobby" for now;
## maps come later), so it only starts on a matching tune.
const SOUND_PACK_CATALOG: Dictionary = {
	"Chiptunic Layer": {
		"description": "A chiptune remix layer that sits on top of the lobby OST.",
		"cost": 150,
		"version": 1,
		"update_cost": 15,
		"ost": "lobby",
		"layers": [
			"res://The Darkness Of The Grasslands assets/Music/Lobby/Lobby remix layers/Chiptunic layer.wav",
		],
	},
	"Chiptunic Layer #2": {
		"description": "A second chiptune remix layer for the lobby OST.",
		"cost": 150,
		"version": 1,
		"update_cost": 15,
		"ost": "lobby",
		"layers": [
			"res://The Darkness Of The Grasslands assets/Music/Lobby/Lobby remix layers/Chiptunic layer #2.wav",
		],
	},
}

## Owned sound packs: id -> version owned (int). A pack is "owned" once bought.
var owned_sound_packs: Dictionary = {}
var equipped_sound_packs: Array = []

func is_sound_pack_owned(id: String) -> bool:
	return owned_sound_packs.has(id)


func get_owned_sound_pack_version(id: String) -> int:
	return int(owned_sound_packs.get(id, 0))


func own_sound_pack(id: String) -> void:
	var def: Dictionary = SOUND_PACK_CATALOG.get(id, {})
	owned_sound_packs[id] = int(def.get("version", 1))


## True when the player owns the pack but a newer version is available.
func can_update_sound_pack(id: String) -> bool:
	if not is_sound_pack_owned(id):
		return false
	var def: Dictionary = SOUND_PACK_CATALOG.get(id, {})
	if def.is_empty():
		return false
	return get_owned_sound_pack_version(id) < int(def.get("version", 1))


func update_sound_pack(id: String) -> void:
	var def: Dictionary = SOUND_PACK_CATALOG.get(id, {})
	owned_sound_packs[id] = int(def.get("version", 1))


func is_sound_pack_equipped(id: String) -> bool:
	return equipped_sound_packs.has(id)


func _sound_pack_layer_count(id: String) -> int:
	return int(SOUND_PACK_CATALOG.get(id, {}).get("layers", []).size())


func equip_sound_pack(id: String) -> bool:
	# Toggle. If already equipped, unequip it. Otherwise add it only when the
	# total equipped layers stays within the 2-layer cap.
	if not is_sound_pack_owned(id):
		return false
	if is_sound_pack_equipped(id):
		unequip_sound_pack(id)
		return true
	var total: int = 0
	for eid in equipped_sound_packs:
		total += _sound_pack_layer_count(eid)
	if total + _sound_pack_layer_count(id) <= 2:
		equipped_sound_packs.append(id)
		return true
	return false


func unequip_sound_pack(id: String) -> void:
	equipped_sound_packs.erase(id)


func get_equipped_sound_packs() -> Array:
	return equipped_sound_packs

## User settings (persisted across scenes, not yet saved to disk)
var hide_leaderboard: bool = false
var epilepsy_safe_mode: bool = true
var vibration_enabled: bool = true
## "Ragdoll" (funny) setting: makes survivor death-flings exactly 100% stronger
## (double launch strength, no more than that). Off by default.
var ragdoll: bool = false
## Global subtle-motion intensity (0..1): how strong idle animations are.
## 0 turns all subtle motion off; 1 is full intensity.
var motion_intensity: float = 1.0
## Debug: show only the local player's own hitbox (green outline).
var show_hitboxes: bool = false
## Debug: show all players' (survivors + killers + bots) collision boxes — not walls.
var show_collision_hitboxes: bool = false

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

## Character EXP — tracks EXP per character per player (username -> {character_name -> exp})
var player_character_exp: Dictionary = {}

func add_character_exp(character_name: String, amount: int) -> void:
	"""Add EXP to the currently logged-in player's character."""
	if logged_in_username.is_empty():
		return
	if not player_character_exp.has(logged_in_username):
		player_character_exp[logged_in_username] = {}
	var char_exp: Dictionary = player_character_exp[logged_in_username] as Dictionary
	var current: int = char_exp.get(character_name, 0)
	char_exp[character_name] = current + amount

func get_character_exp(character_name: String) -> int:
	"""Get EXP for the logged-in player's character."""
	if logged_in_username.is_empty():
		return 0
	if not player_character_exp.has(logged_in_username):
		return 0
	var char_exp: Dictionary = player_character_exp[logged_in_username] as Dictionary
	return char_exp.get(character_name, 0)

func get_total_exp() -> int:
	"""Get total EXP across all characters for the logged-in player."""
	if logged_in_username.is_empty():
		return 0
	if not player_character_exp.has(logged_in_username):
		return 0
	var char_exp: Dictionary = player_character_exp[logged_in_username] as Dictionary
	var total: int = 0
	for exp: int in char_exp.values():
		total += exp
	return total

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
