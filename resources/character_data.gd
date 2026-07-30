class_name CharacterData
extends Resource
## Data resource for a playable character (killer or survivor).
##
## To add a new character:
## 1. Create their scene (extends CharacterBody2D)
## 2. Create a CharacterData resource (.tres) with their stats
## 3. Add to killer_scenes[] or survivor_scenes[] in game_map inspector
## 4. Register in the character catalog below

# ── Identity ──
@export var display_name: String = ""            # "Violentgrass"
@export var character_type: String = "killer"    # "killer" or "survivor"
@export var icon_path: String = ""               # "res://...icon.png"

# ── Stats ──
@export var max_hp: float = 100.0
@export var move_speed: float = 120.0
@export var sprint_speed: float = 250.0
@export var max_stamina: float = 100.0

# ── Ability Configuration ──
@export var abilities: Array[Dictionary] = []    # {name, key, icon_path, cooldown_var}

# ── Scene ──
@export var scene_path: String = ""              # "res://scenes/violentgrass.tscn"

# ── AI defaults (when used as bot) ──
@export var ai_script_path: String = ""          # Optional override AI script

# ── Sound ──
@export var hit_sound_path: String = ""
@export var ability_sound_path: String = ""
@export var teleport_sound_path: String = ""


## Register all available characters here
static func get_catalog() -> Array[CharacterData]:
	var catalog: Array[CharacterData] = []
	
	var vg := CharacterData.new()
	vg.display_name = "Violentgrass"
	vg.character_type = "killer"
	vg.icon_path = "res://The Darkness Of The Grasslands assets/UI/Lobby/Violentgrass - Killer icon.png"
	vg.max_hp = 6666.0
	vg.move_speed = 120.0
	vg.sprint_speed = 350.0
	vg.max_stamina = 100.0
	vg.abilities = [
		{"name": "Hit", "key": "Q", "icon_path": "res://assets/generated/icon_ability_hit.png", "cooldown_var": "hit_on_cooldown"},
		{"name": "Teleport", "key": "E", "icon_path": "res://assets/generated/icon_ability_teleport.png", "cooldown_var": "teleport_on_cooldown"},
	]
	catalog.append(vg)
	
	var gg := CharacterData.new()
	gg.display_name = "Greengrass"
	gg.character_type = "survivor"
	gg.icon_path = "res://The Darkness Of The Grasslands assets/UI/Lobby/Greengrass - survivor icon.png"
	gg.max_hp = 100.0
	gg.move_speed = 120.0
	gg.sprint_speed = 250.0
	gg.max_stamina = 100.0
	gg.abilities = [
		{"name": "Block", "key": "Q", "icon_path": "res://assets/generated/icon_ability_block.png", "cooldown_var": "block_on_cooldown"},
		{"name": "Grass Punch", "key": "E", "icon_path": "res://assets/generated/icon_ability_grass_punch.png", "cooldown_var": "punch_on_cooldown"},
		{"name": "Spare Flower", "key": "R", "icon_path": "res://assets/generated/icon_ability_spare_flower.png", "cooldown_var": "flower_on_cooldown"},
	]
	catalog.append(gg)
	
	return catalog


## Get character data by name (or return null)
static func get_by_name(name: String) -> CharacterData:
	for c: CharacterData in get_catalog():
		if c.display_name == name:
			return c
	return null
