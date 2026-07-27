extends Node

## Whether the local player is playing as the killer
var is_killer: bool = false

## Which character scene to spawn for the player
var selected_survivor: String = "Greengrass"
var selected_killer: String = "Violentgrass"

## User settings (persisted across scenes, not yet saved to disk)
var hide_leaderboard: bool = false
var epilepsy_safe_mode: bool = true

## Match-end analysis state (passed from game_map to lobby)
var show_analysis: bool = false
var match_character_name: String = "Greengrass"
var match_damage_taken: float = 0.0
var match_damage_dealt: float = 0.0
