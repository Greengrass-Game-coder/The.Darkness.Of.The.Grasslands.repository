class_name GameMap
extends Node2D

signal match_ended()

const MATCH_DURATION: float = 240.0  # 4 minutes

@export var blueprint_name: String = "Map_Test"

# HUD layout positions — editable in inspector
@export var health_bar_pos: Vector2 = Vector2(440, 555)
@export var health_bar_size: Vector2 = Vector2(400, 30)
@export var stamina_bar_pos: Vector2 = Vector2(440, 590)
@export var stamina_bar_size: Vector2 = Vector2(400, 36)
@export var ability_icons_pos: Vector2 = Vector2(490, 652)
@export var ability_slot_start_x: float = 52.0
@export var ability_slot_spacing: float = 66.0

@onready var match_timer: Timer = $MatchTimer
@onready var map_visual: Sprite2D = $MapVisual
@onready var timer_label: Label = $HUD/TimerLabel
const GREENGRASS_SCENE: PackedScene = preload("res://scenes/greengrass.tscn")
const VIOLENTGRASS_SCENE: PackedScene = preload("res://scenes/violentgrass.tscn")
const AI_BOT_SCRIPT: Script = preload("res://scripts/characters/ai_bot_controller.gd")

# Chase music defaults (overridden by bot's @export settings when spawned)
# Chase music radii (pixels) — defaults, overridden from bot @export at spawn
var _chase_in_layer1: float = 500.0
var _chase_in_layer2: float = 250.0
var _chase_in_layer3: float = 125.0
var _chase_in_chase: float = 50.0
var _chase_out_none: float = 600.0
var _chase_out_layer1: float = 400.0
var _chase_out_layer2: float = 200.0
var _chase_out_layer3: float = 100.0
var _chase_fade_in: float = 0.5
var _chase_fade_out: float = 0.5

const BOT_CHASE_DIR: String = "res://The Darkness Of The Grasslands assets/Music/Killer Chase Themes/Violentgrass/"
const BOT_CHASE_L1: String = BOT_CHASE_DIR + "Layer1.wav"
const BOT_CHASE_L2: String = BOT_CHASE_DIR + "Layer2.wav"
const BOT_CHASE_L3: String = BOT_CHASE_DIR + "Layer3.wav"
const BOT_CHASE_CHASE: String = BOT_CHASE_DIR + "Chase.wav"

enum ChaseState { NONE, LAYER_1, LAYER_2, LAYER_3, CHASE }

var _time_remaining: float = MATCH_DURATION
var _map_manager: MapManager = null
var _player: Node2D = null
var _killer_bot: Node2D = null
var _chase_state: ChaseState = ChaseState.NONE
var _chase_l1: AudioStreamPlayer = null
var _chase_l2: AudioStreamPlayer = null
var _chase_l3: AudioStreamPlayer = null
var _chase_chase: AudioStreamPlayer = null
var _current_interactable: Area2D = null
var _last_hp: float = -1.0
var _solved_puzzles: Array[String] = []
var _e_was_pressed: bool = false
var _puzzle_open: bool = false

# Match-ending effect
var _ending_vignette: ColorRect = null
var _ending_music_switched: bool = false
var _ending_start_time: float = 0.0

# Match stats
var _total_damage_taken: float = 0.0
var _total_damage_dealt: float = 0.0
var _character_name: String = "Greengrass"


func _ready() -> void:
	# Ensure input actions are registered
	_setup_input_actions()
	
	# Set up background music
	_setup_music()
	
	# Load and set up the map
	_map_manager = MapManager.new()
	add_child(_map_manager)
	
	if not _map_manager.load_blueprint(blueprint_name):
		push_error("GameMap: Failed to load blueprint")
		return
	
	# Set the visual map
	var visual_path: String = _map_manager.get_map_visual_path(blueprint_name)
	var map_texture: Texture2D = load(visual_path)
	if map_texture:
		map_visual.texture = map_texture
	else:
		push_error("GameMap: Could not load map visual: ", visual_path)
	
	# Build wall collision
	_map_manager.build_collision(self)
	
	# Add map border walls
	_add_map_border_walls()
	
	# Place marker nodes for debugging/visualization
	_place_markers()
	
	# Start match timer
	match_timer.start(1.0)
	_time_remaining = MATCH_DURATION
	_update_timer_label()
	
	# Spawn the player character
	spawn_player(GameState.is_killer)


func _setup_input_actions() -> void:
	"""Register missing input actions at runtime."""
	var actions: Dictionary = {
		"move_left": [KEY_A],
		"move_right": [KEY_D],
		"move_up": [KEY_W],
		"move_down": [KEY_S],
		"sprint": [KEY_SHIFT],
		"ability_1": [KEY_Q],
		"ability_2": [KEY_E],
		"ability_3": [KEY_R],
		"ability_4": [KEY_T],
	}
	for action_name: String in actions:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			var keys: Array = actions[action_name] as Array
			for keycode: int in keys:
				var ev := InputEventKey.new()
				ev.keycode = keycode
				InputMap.action_add_event(action_name, ev)


func _setup_music() -> void:
	"""Add and play looping background music (non-positional)."""
	var music_path: String = "res://The Darkness Of The Grasslands assets/Music/Maps/The Test/Test_map_music.wav"
	if ResourceLoader.exists(music_path):
		var stream: AudioStream = load(music_path)
		if stream:
			var player := AudioStreamPlayer.new()
			player.name = "MusicPlayer"
			player.stream = stream
			player.autoplay = true
			player.bus = &"Master"
			player.finished.connect(_on_map_music_finished)
			add_child(player)
			print("GameMap: Playing background music")


func _switch_to_ending_music() -> void:
	"""Switch from map music to the tense match-ending track at 30s remaining.
	Fades map music out over 0.5 seconds first."""
	if _ending_music_switched:
		return
	_ending_music_switched = true
	
	# Fade out existing music player
	var old_player: AudioStreamPlayer = get_node_or_null("MusicPlayer")
	if old_player:
		var fade_tween: Tween = create_tween()
		fade_tween.tween_property(old_player, "volume_db", -80.0, 0.5)
		await fade_tween.finished
		old_player.stop()
		old_player.queue_free()
	
	# Create new player for ending music (if file exists)
	var ending_path: String = "res://The Darkness Of The Grasslands assets/Music/Match/Match_ENDING.wav"
	if not ResourceLoader.exists(ending_path):
		return
	
	var ending_stream: AudioStream = load(ending_path)
	if not ending_stream:
		return
	
	var player := AudioStreamPlayer.new()
	player.name = "MusicPlayer"
	player.stream = ending_stream
	player.autoplay = true
	player.bus = &"Master"
	player.volume_db = -2.0  # Slightly louder for tension
	player.finished.connect(_on_map_music_finished)
	add_child(player)
	print("GameMap: Switched to MATCH_ENDING music")


func _on_map_music_finished() -> void:
	"""Loop map music by restarting playback."""
	var player: AudioStreamPlayer = $MusicPlayer
	if player:
		player.play()


func _place_markers() -> void:
	"""Create Marker2D nodes for spawns, stairs, puzzles, doors."""
	
	# Survivor spawns
	for i in range(_map_manager.survivor_spawns.size()):
		var pos: Vector2 = _map_manager.survivor_spawns[i]
		var marker := Marker2D.new()
		marker.name = "SurvivorSpawn_%d" % i
		marker.position = pos
		add_child(marker)
	
	# Killer spawns
	for i in range(_map_manager.killer_spawns.size()):
		var pos: Vector2 = _map_manager.killer_spawns[i]
		var marker := Marker2D.new()
		marker.name = "KillerSpawn_%d" % i
		marker.position = pos
		add_child(marker)
	
	# Stairs as Area2D triggers
	for i in range(_map_manager.stairs_positions.size()):
		var pos: Vector2 = _map_manager.stairs_positions[i]
		var area := Area2D.new()
		area.name = "Stairs_%d" % i
		area.position = pos
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(64, 64)
		col.shape = shape
		area.add_child(col)
		add_child(area)
	
	# Puzzles as interactive Area2D triggers
	for i in range(_map_manager.puzzle_positions.size()):
		var pos: Vector2 = _map_manager.puzzle_positions[i]
		# Shift puzzle to be at the left edge of the purple region
		# (where the player naturally walks through) and at player y-height
		var adjusted_pos := Vector2(pos.x - 56.0, pos.y - 45.0)
		var area := Area2D.new()
		area.name = "Puzzle_%d" % i
		area.position = adjusted_pos
		area.collision_mask = 1  # Detect player (layer 1)
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(128, 128)  # Bigger catch area
		col.shape = shape
		area.add_child(col)
		
		# Visual indicator (purple rectangle on the ground)
		var rect := ColorRect.new()
		rect.name = "ColorRect"
		rect.size = Vector2(64, 64)
		rect.color = Color(0.64, 0.29, 0.64, 0.4)  # Purple matching blueprint
		rect.position = Vector2(-32, -32)
		area.add_child(rect)
		
		# Interact prompt label
		var prompt := Label.new()
		prompt.name = "InteractPrompt"
		prompt.text = "[E] Activate"
		prompt.position = Vector2(-50, -40)
		prompt.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		prompt.add_theme_constant_override("shadow_offset_x", 1)
		prompt.add_theme_constant_override("shadow_offset_y", 1)
		prompt.visible = false
		area.add_child(prompt)
		
		area.body_entered.connect(_on_puzzle_area_entered.bind(area))
		area.body_exited.connect(_on_puzzle_area_exited.bind(area))
		add_child(area)
	
	# Doors as Area2D triggers
	for i in range(_map_manager.door_positions.size()):
		var pos: Vector2 = _map_manager.door_positions[i]
		var area := Area2D.new()
		area.name = "Door_%d" % i
		area.position = pos
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(64, 64)
		col.shape = shape
		area.add_child(col)
		add_child(area)
	
	print("GameMap: Placed marker nodes")


func spawn_player(spawn_as_killer: bool = false) -> void:
	"""Spawn the player character at the appropriate spawn point."""
	var is_killer_player: bool = spawn_as_killer or GameState.is_killer
	var spawn_pos: Vector2 = _map_manager.get_spawn_point(is_killer_player)
	
	var player_scene: PackedScene = VIOLENTGRASS_SCENE if is_killer_player else GREENGRASS_SCENE
	_player = player_scene.instantiate()
	_player.name = "Player"
	_player.position = spawn_pos
	add_child(_player)
	
	# Enable camera on the player
	var cam := _player.get_node("Camera2D") as Camera2D
	if cam:
		cam.enabled = true
		cam.make_current()
		cam.reset_smoothing()
	
	# Set character name for analysis screen
	_character_name = "Violentgrass" if is_killer_player else "Greengrass"
	
	# Create health bar UI
	_create_health_bar(_player)
	
	# Create stamina bar UI
	_create_stamina_bar(_player)
	
	# Create ability icons
	_create_ability_icons(_player, is_killer_player)
	
	# Create epilepsy-safe overlay
	_create_epilepsy_overlay(_player)
	
	# Create match-ending vignette
	_create_ending_vignette()
	
	# Spawn bot killer if player is survivor
	if not is_killer_player:
		_spawn_bot_killer()
	
	# Track damage dealt via punch signal
	if _player.has_signal("punch_landed") and not _player.punch_landed.is_connected(_on_player_attacked):
		_player.punch_landed.connect(_on_player_attacked)
	
	print("GameMap: Spawned ", _character_name, " at ", spawn_pos)


func _create_health_bar(player: Node2D) -> void:
	"""Create a health bar in the center-bottom of the HUD."""
	var container := Control.new()
	container.name = "HealthBar"
	container.position = health_bar_pos
	container.size = health_bar_size
	$HUD.add_child(container)
	
	# Background (acts as border frame due to 2px gap)
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.size = Vector2(404, 32)
	bg.position = Vector2(-2, -2)
	bg.color = Color(0.4, 0.4, 0.4, 0.6)
	container.add_child(bg)
	
	# Fill bar (inside the border)
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.size = Vector2(400, 28)
	fill.color = Color(0.15, 0.9, 0.15, 0.9)  # Green
	container.add_child(fill)
	
	# Label (HP text)
	var label := Label.new()
	label.name = "Label"
	label.text = "100 / 100"
	label.position = Vector2(0, 4)
	label.size = Vector2(400, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 18)
	container.add_child(label)
	
	# Connect to player's hp_changed signal
	if player.has_signal("hp_changed"):
		player.hp_changed.connect(_on_player_hp_changed.bind(fill, label))


func _create_stamina_bar(player: Node2D) -> void:
	"""Create a stamina bar under the health bar in the HUD."""
	var stamina_container := Control.new()
	stamina_container.name = "StaminaBar"
	stamina_container.position = stamina_bar_pos  # Below health bar
	stamina_container.size = stamina_bar_size
	$HUD.add_child(stamina_container)
	
	# Background (dark)
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.size = Vector2(400, 14)
	bg.color = Color(0.15, 0.15, 0.15, 0.8)
	stamina_container.add_child(bg)
	
	# Fill bar
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.size = Vector2(400, 14)
	fill.color = Color(0.2, 0.8, 0.2, 0.9)
	stamina_container.add_child(fill)
	
	# Label (below the fill bar, inside the container)
	var label := Label.new()
	label.name = "Label"
	label.text = "SPRINT LIMIT"
	label.position = Vector2(0, 16)
	label.size = Vector2(400, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 10)
	stamina_container.add_child(label)
	
	# Connect to player's stamina signal
	if player.has_signal("stamina_changed"):
		player.stamina_changed.connect(_on_player_stamina_changed.bind(fill))


func _process(delta: float) -> void:
	"""Update HUD, interact detection, cooldowns, and settings each frame."""
	if not is_instance_valid(_player):
		return
	_update_ability_cooldowns()
	_check_interact_input(delta)
	_check_settings_updates()
	_check_damage_vignette()
	_update_chase_music(delta)
	
	# Match-ending effects (last 31 seconds)
	if _time_remaining <= 31.0:
		_ending_start_time += delta
		_update_ending_vignette()
		_switch_to_ending_music()


func _create_ability_icons(_player_node: Node2D, is_killer: bool) -> void:
	"""Create ability icon slots in the HUD below the sprint bar, centered."""
	var container := Control.new()
	container.name = "AbilityIcons"
	container.position = ability_icons_pos  # Centered below sprint bar
	container.size = Vector2(300, 60)
	$HUD.add_child(container)
	
	# Define ability icon data based on character type
	var abilities: Array[Dictionary] = []
	if is_killer:
		abilities = [
			{"icon": "res://assets/generated/icon_ability_hit.png", "key": "Q", "cooldown_var": "hit_on_cooldown"},
			{"icon": "res://assets/generated/icon_ability_teleport.png", "key": "R", "cooldown_var": "teleport_on_cooldown"},
		]
	else:
		abilities = [
			{"icon": "res://assets/generated/icon_ability_block.png", "key": "Q", "cooldown_var": "block_on_cooldown"},
			{"icon": "res://assets/generated/icon_ability_grass_punch.png", "key": "E", "cooldown_var": "punch_on_cooldown"},
			{"icon": "res://assets/generated/icon_ability_spare_flower.png", "key": "R", "cooldown_var": "flower_on_cooldown"},
		]
	
	for i: int in range(abilities.size()):
		var data: Dictionary = abilities[i]
		var slot := Control.new()
		slot.name = "Ability%d" % i
		slot.position = Vector2(ability_slot_start_x + i * ability_slot_spacing, 0)
		slot.size = Vector2(56, 56)
		container.add_child(slot)
		
		# Icon
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = load(data["icon"])
		icon.size = Vector2(56, 56)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.add_child(icon)
		
		# Cooldown overlay (dark)
		var overlay := ColorRect.new()
		overlay.name = "CooldownOverlay"
		overlay.size = Vector2(56, 56)
		overlay.color = Color(0, 0, 0, 0.6)
		overlay.visible = false
		slot.add_child(overlay)
		
		# Key label
		var key_label := Label.new()
		key_label.name = "KeyLabel"
		key_label.text = data["key"]
		key_label.position = Vector2(2, 36)
		key_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		key_label.add_theme_constant_override("shadow_offset_x", 1)
		key_label.add_theme_constant_override("shadow_offset_y", 1)
		slot.add_child(key_label)
		
		# Store reference for cooldown tracking
		slot.set_meta("cooldown_var", data["cooldown_var"])


func _update_ability_cooldowns() -> void:
	"""Update cooldown overlays by checking player variables."""
	var icons: Node = $HUD.get_node_or_null("AbilityIcons")
	if not icons or not is_instance_valid(_player):
		return
	
	for slot: Node in icons.get_children():
		var var_name: String = slot.get_meta("cooldown_var", "")
		if var_name.is_empty():
			continue
		var overlay: ColorRect = slot.get_node_or_null("CooldownOverlay")
		if not overlay:
			continue
		# Use 'in' operator to check if property exists on the player
		if var_name in _player and _player.get(var_name):
			overlay.visible = true
		else:
			overlay.visible = false


func _on_player_hp_changed(current_hp: float, max_hp: float, fill: ColorRect, label: Label) -> void:
	"""Update the health bar when player HP changes."""
	var ratio: float = current_hp / max_hp if max_hp > 0 else 0.0
	fill.size.x = 400.0 * clampf(ratio, 0.0, 1.0)
	label.text = "%d / %d" % [current_hp, max_hp]
	# Color shifts from green to red as HP drops
	if ratio < 0.3:
		fill.color = Color(0.9, 0.15, 0.15, 0.9)
	elif ratio < 0.6:
		fill.color = Color(0.9, 0.7, 0.1, 0.9)
	else:
		fill.color = Color(0.15, 0.9, 0.15, 0.9)


func _on_player_stamina_changed(current: float, max_stamina: float, fill: ColorRect) -> void:
	"""Update the stamina fill bar width based on remaining stamina."""
	var ratio: float = current / max_stamina if max_stamina > 0 else 0.0
	fill.size.x = 400.0 * clampf(ratio, 0.0, 1.0)
	fill.color.a = 0.5 if ratio < 0.2 else 0.9  # Dim when low


func _spawn_bot_killer() -> void:
	"""Spawn an AI-controlled killer bot at a killer spawn point."""
	var spawn_pos: Vector2 = _map_manager.get_spawn_point(true)
	
	var bot: Node2D = VIOLENTGRASS_SCENE.instantiate()
	bot.set_script(AI_BOT_SCRIPT)
	bot.name = "KillerBot"
	bot.position = spawn_pos
	add_child(bot)  # add_child triggers AI bot's _ready() once
	_killer_bot = bot
	_read_bot_chase_settings(bot)
	_setup_chase_music()
	print("GameMap: Spawned KillerBot at ", spawn_pos)


func _add_map_border_walls() -> void:
	"""Add 4 invisible wall rectangles around the map perimeter."""
	var map_w: float = _map_manager.blueprint_size.x
	var map_h: float = _map_manager.blueprint_size.y
	var t: float = 32.0  # thickness
	
	var body := StaticBody2D.new()
	body.name = "MapBorderWalls"
	add_child(body)
	
	# Top
	var top := CollisionShape2D.new()
	top.shape = RectangleShape2D.new()
	top.shape.size = Vector2(map_w + t * 2, t)
	top.position = Vector2(map_w * 0.5, -t * 0.5)
	body.add_child(top)
	
	# Bottom
	var bot := CollisionShape2D.new()
	bot.shape = RectangleShape2D.new()
	bot.shape.size = Vector2(map_w + t * 2, t)
	bot.position = Vector2(map_w * 0.5, map_h + t * 0.5)
	body.add_child(bot)
	
	# Left
	var left := CollisionShape2D.new()
	left.shape = RectangleShape2D.new()
	left.shape.size = Vector2(t, map_h)
	left.position = Vector2(-t * 0.5, map_h * 0.5)
	body.add_child(left)
	
	# Right
	var right := CollisionShape2D.new()
	right.shape = RectangleShape2D.new()
	right.shape.size = Vector2(t, map_h)
	right.position = Vector2(map_w + t * 0.5, map_h * 0.5)
	body.add_child(right)
	
	print("GameMap: Added map border walls (", map_w, "x", map_h, ")")


func _read_bot_chase_settings(bot: Node2D) -> void:
	"""Read @export chase settings from the bot instance (if they exist)."""
	if not is_instance_valid(bot):
		return
	if "chase_in_layer1" in bot:
		_chase_in_layer1 = bot.chase_in_layer1
	if "chase_in_layer2" in bot:
		_chase_in_layer2 = bot.chase_in_layer2
	if "chase_in_layer3" in bot:
		_chase_in_layer3 = bot.chase_in_layer3
	if "chase_in_chase" in bot:
		_chase_in_chase = bot.chase_in_chase
	if "chase_out_none" in bot:
		_chase_out_none = bot.chase_out_none
	if "chase_out_layer1" in bot:
		_chase_out_layer1 = bot.chase_out_layer1
	if "chase_out_layer2" in bot:
		_chase_out_layer2 = bot.chase_out_layer2
	if "chase_out_layer3" in bot:
		_chase_out_layer3 = bot.chase_out_layer3
	if "chase_fade_in_duration" in bot:
		_chase_fade_in = bot.chase_fade_in_duration
	if "chase_fade_out_duration" in bot:
		_chase_fade_out = bot.chase_fade_out_duration


func _setup_chase_music() -> void:
	"""Create 4 looping chase music players (start muted, volume controlled by distance)."""
	var tracks: Array[Dictionary] = [
		{"name": "ChaseL1", "path": BOT_CHASE_L1, "var_ref": "_chase_l1"},
		{"name": "ChaseL2", "path": BOT_CHASE_L2, "var_ref": "_chase_l2"},
		{"name": "ChaseL3", "path": BOT_CHASE_L3, "var_ref": "_chase_l3"},
		{"name": "ChaseFinal", "path": BOT_CHASE_CHASE, "var_ref": "_chase_chase"},
	]
	for t: Dictionary in tracks:
		if not ResourceLoader.exists(t["path"]):
			continue
		var p := AudioStreamPlayer.new()
		p.name = t["name"]
		p.stream = load(t["path"])
		p.autoplay = true
		p.volume_db = -80.0  # Start muted
		p.finished.connect(_on_chase_loop.bind(p))
		add_child(p)
		set(t["var_ref"], p)
	_chase_state = ChaseState.NONE
	print("GameMap: Chase music players ready")


func _on_chase_loop(player: AudioStreamPlayer) -> void:
	"""Loop a chase music track by replaying on finish."""
	if is_instance_valid(player):
		player.play()


func _update_chase_music(_delta: float) -> void:
	"""Check distance to killer bot and transition chase music layers."""
	if not is_instance_valid(_killer_bot) or not is_instance_valid(_player):
		return
	
	var dist: float = _player.global_position.distance_to(_killer_bot.global_position)
	var new_state: ChaseState = _determine_chase_state(dist)
	
	if new_state == _chase_state:
		return
	
	var prev_state: ChaseState = _chase_state
	_chase_state = new_state
	
	# Mute/unmute players based on state
	var map_player: AudioStreamPlayer = get_node_or_null("MusicPlayer")
	
	match new_state:
		ChaseState.NONE:
			# Reactivate map music (fade in)
			if map_player:
				var tween := create_tween()
				tween.tween_property(map_player, "volume_db", 0.0, 0.5)
			_set_chase_volumes(-80.0, -80.0, -80.0, -80.0)
		
		ChaseState.LAYER_1:
			# Fade out map music on first activation
			if map_player and prev_state == ChaseState.NONE:
				var tween := create_tween()
				tween.tween_property(map_player, "volume_db", -80.0, 0.5)
			_set_chase_volumes(0.0, -80.0, -80.0, -80.0)
		
		ChaseState.LAYER_2:
			_set_chase_volumes(-80.0, 0.0, -80.0, -80.0)
		
		ChaseState.LAYER_3:
			_set_chase_volumes(-80.0, -80.0, 0.0, -80.0)
		
		ChaseState.CHASE:
			_set_chase_volumes(-80.0, -80.0, -80.0, 0.0)


func _determine_chase_state(dist: float) -> ChaseState:
	"""Determine chase music state from distance with hysteresis."""
	if _chase_state == ChaseState.NONE:
		if dist <= _chase_in_layer1:
			return ChaseState.LAYER_1
		return ChaseState.NONE
	
	elif _chase_state == ChaseState.LAYER_1:
		if dist <= _chase_in_layer2:
			return ChaseState.LAYER_2
		if dist > _chase_out_layer1:
			return ChaseState.NONE
		return ChaseState.LAYER_1
	
	elif _chase_state == ChaseState.LAYER_2:
		if dist <= _chase_in_layer3:
			return ChaseState.LAYER_3
		if dist > _chase_out_layer2:
			return ChaseState.LAYER_1
		return ChaseState.LAYER_2
	
	elif _chase_state == ChaseState.LAYER_3:
		if dist <= _chase_in_chase:
			return ChaseState.CHASE
		if dist > _chase_out_layer3:
			return ChaseState.LAYER_2
		return ChaseState.LAYER_3
	
	elif _chase_state == ChaseState.CHASE:
		if dist > _chase_out_layer3:
			return ChaseState.LAYER_3
		return ChaseState.CHASE
	
	return ChaseState.NONE


func _set_chase_volumes(l1: float, l2: float, l3: float, chase: float) -> void:
	"""Set volume for all 4 chase players (tweened for smooth crossfade)."""
	_tween_chase_vol(_chase_l1, l1)
	_tween_chase_vol(_chase_l2, l2)
	_tween_chase_vol(_chase_l3, l3)
	_tween_chase_vol(_chase_chase, chase)


func _tween_chase_vol(player: AudioStreamPlayer, target_db: float) -> void:
	"""Smoothly tween a chase player's volume."""
	if not is_instance_valid(player):
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", target_db, _chase_fade_in)


func get_random_killer_spawn() -> Vector2:
	return _map_manager.get_spawn_point(true)


func _on_match_timer_timeout() -> void:
	_time_remaining -= 1.0
	_update_timer_label()
	
	if _time_remaining <= 0.0:
		_time_remaining = 0.0
		_update_timer_label()
		match_timer.stop()
		match_ended.emit()
		print("GameMap: Match ended!")
		_end_match()


# ---------- PUZZLE INTERACTION ----------

func _on_puzzle_area_entered(_body: Node2D, area: Area2D) -> void:
	"""Show interact prompt when player enters a puzzle zone."""
	_current_interactable = area
	var prompt: Label = area.get_node_or_null("InteractPrompt")
	if prompt:
		prompt.visible = true


func _on_puzzle_area_exited(_body: Node2D, area: Area2D) -> void:
	"""Hide interact prompt when player leaves a puzzle zone."""
	if _current_interactable == area:
		_current_interactable = null
	var prompt: Label = area.get_node_or_null("InteractPrompt")
	if prompt:
		prompt.visible = false


func _check_interact_input(_delta: float) -> void:
	"""Check for E key press to open a puzzle minigame."""
	if _current_interactable == null:
		return
	
	var area_name: String = _current_interactable.name
	if area_name in _solved_puzzles:
		return  # Already solved
	
	if Input.is_key_pressed(KEY_E) and not _e_was_pressed and not _puzzle_open:
		_e_was_pressed = true
		_open_puzzle_for_area(_current_interactable)
	elif not Input.is_key_pressed(KEY_E):
		_e_was_pressed = false


func _open_puzzle_for_area(area: Area2D) -> void:
	"""Open a random puzzle minigame for this area."""
	if not is_instance_valid(_player) or _puzzle_open:
		return
	
	_puzzle_open = true
	
	# Hide interact prompt while puzzle is open
	var prompt: Label = area.get_node_or_null("InteractPrompt")
	if prompt:
		prompt.visible = false
	
	# Create puzzle manager and open a puzzle
	var puz_scene: PuzzleManager = PuzzleManager.new()
	add_child(puz_scene)
	puz_scene.open_puzzle(area, _player)
	puz_scene.puzzle_completed.connect(_on_puzzle_solved)
	puz_scene.puzzle_closed.connect(_on_puzzle_closed.bind(puz_scene))


func _on_puzzle_solved(area: Area2D) -> void:
	"""Handle puzzle solved — mark complete, change appearance."""
	var area_name: String = area.name
	_solved_puzzles.append(area_name)
	
	# Show success text
	var prompt: Label = area.get_node_or_null("InteractPrompt")
	if prompt:
		prompt.text = "✓ Solved!"
	
	# Visual feedback: tint the area marker green
	if area.has_node("ColorRect"):
		var rect: ColorRect = area.get_node("ColorRect")
		rect.color = Color(0.2, 0.8, 0.2, 0.5)
	
	print("GameMap: Puzzle solved at ", area.position)


func _on_puzzle_closed(puz_scene: PuzzleManager) -> void:
	"""Clean up puzzle manager when closed."""
	_puzzle_open = false
	if is_instance_valid(puz_scene):
		puz_scene.queue_free()


# ---------- LEADERBOARD ----------

# Leaderboard moved to lobby.gd


# ---------- EPILEPSY SAFE OVERLAY ----------

var _epilepsy_overlay: ColorRect = null
var _vignette_overlay: ColorRect = null

func _create_epilepsy_overlay(player: Node2D) -> void:
	"""Create epilepsy-safe desaturation overlay and damage vignette."""
	var hud: CanvasLayer = $HUD
	
	# Full-screen desaturation overlay
	var overlay := ColorRect.new()
	overlay.name = "EpilepsyOverlay"
	overlay.position = Vector2(0, 0)
	overlay.size = Vector2(1280, 720)
	overlay.color = Color(0.5, 0.5, 0.5, 0.0)  # Starts off
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(overlay)
	_epilepsy_overlay = overlay
	
	# Vignette overlay (shown briefly on damage)
	var vignette := ColorRect.new()
	vignette.name = "Vignette"
	vignette.position = Vector2(0, 0)
	vignette.size = Vector2(1280, 720)
	vignette.color = Color(0, 0, 0, 0.0)  # Starts transparent
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(vignette)
	_vignette_overlay = vignette
	
	# Apply epilepsy mode on spawn
	_apply_epilepsy_mode()
	
	# Connect to player damage signals if they exist
	if player.has_signal("healed"):
		# Use healing signal with negative direction to detect damage
		pass  # Damage detection handled via polling in _process
	
	# Listen for GameState changes by polling (process is already active)


func _apply_epilepsy_mode() -> void:
	"""Apply or remove the epilepsy-safe desaturation overlay."""
	var enabled: bool = "epilepsy_safe_mode" in GameState and GameState.epilepsy_safe_mode
	if is_instance_valid(_epilepsy_overlay):
		_epilepsy_overlay.color = Color(0.5, 0.5, 0.5, 0.2) if enabled else Color(0.5, 0.5, 0.5, 0.0)


func _trigger_vignette() -> void:
	"""Flash a subtle dark vignette when taking damage."""
	if not is_instance_valid(_vignette_overlay):
		return
	var enabled: bool = "epilepsy_safe_mode" in GameState and GameState.epilepsy_safe_mode
	var target_alpha: float = 0.25 if enabled else 0.4  # Slightly stronger if epilepsy mode is off
	
	_vignette_overlay.color = Color(0, 0, 0, target_alpha)
	var tween := create_tween()
	tween.tween_property(_vignette_overlay, "color", Color(0, 0, 0, 0), 0.8).set_ease(Tween.EASE_OUT)


func _check_settings_updates() -> void:
	"""Poll GameState for setting changes and apply them."""
	_apply_epilepsy_mode()


# ---------- MATCH-ENDING OVERLAY ----------

func _create_ending_vignette() -> void:
	"""Create a dark-red overlay that pulses in the final 30 seconds."""
	var hud: CanvasLayer = $HUD
	var vignette := ColorRect.new()
	vignette.name = "EndingVignette"
	vignette.position = Vector2(0, 0)
	vignette.size = Vector2(1280, 720)
	vignette.color = Color(0.4, 0.0, 0.0, 0.0)  # Dark red, starts transparent
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(vignette)
	_ending_vignette = vignette


func _update_ending_vignette() -> void:
	"""Animate the ending vignette from 30s to 0s.
	Epilepsy mode ON  → dark red screen gets darker.
	Epilepsy mode OFF → 10 crazy cycling colors based on seconds remaining.
	"""
	if not is_instance_valid(_ending_vignette):
		return
	if _time_remaining > 30.0:
		_ending_vignette.color = Color(0.4, 0.0, 0.0, 0.0)
		return
	
	var epilepsy_on: bool = "epilepsy_safe_mode" in GameState and GameState.epilepsy_safe_mode
	var seconds_left: int = int(_time_remaining)
	var progress: float = 1.0 - (_time_remaining / 30.0)  # 0→1
	
	if epilepsy_on:
		# Dark red, gets darker as time runs out — steady, no crazy colors
		var alpha: float = clampf(progress * 0.75, 0.0, 0.75)
		_ending_vignette.color = Color(0.35, 0.0, 0.0, alpha)
	else:
		# 10 vibrant cycling colors, one per 3-second bucket
		var color_index: int = int(seconds_left / 3.0)  # 30→0 maps to 10→0
		color_index = clampi(color_index, 0, 9)
		var colors: Array[Color] = [
			Color(1.0, 0.0, 0.0, 0.7),   # 0-2s:  Red
			Color(1.0, 0.5, 0.0, 0.7),   # 3-5s:  Orange
			Color(1.0, 1.0, 0.0, 0.7),   # 6-8s:  Yellow
			Color(0.5, 1.0, 0.0, 0.7),   # 9-11s: Lime
			Color(0.0, 1.0, 0.5, 0.7),   # 12-14s:Teal-green
			Color(0.0, 0.8, 1.0, 0.7),   # 15-17s:Cyan
			Color(0.0, 0.3, 1.0, 0.7),   # 18-20s:Blue
			Color(0.5, 0.0, 1.0, 0.7),   # 21-23s:Purple
			Color(1.0, 0.0, 1.0, 0.7),   # 24-26s:Magenta
			Color(1.0, 0.3, 0.6, 0.7),   # 27-29s:Hot pink
		]
		var base_color: Color = colors[color_index]
		
		# Aggressive pulse on top for extra chaos
		var pulse_speed: float = 4.0 + progress * 8.0  # 4→12 Hz
		var pulse: float = sin(_ending_start_time * pulse_speed) * 0.5 + 0.5
		var flicker_alpha: float = 0.5 + pulse * 0.4
		var flicker_bright: float = 0.7 + pulse * 0.3
		
		_ending_vignette.color = Color(
			base_color.r * flicker_bright,
			base_color.g * flicker_bright,
			base_color.b * flicker_bright,
			clampf(flicker_alpha, 0.3, 0.85)
		)


# ---------- DAMAGE VIGNETTE ----------

func _check_damage_vignette() -> void:
	"""Detect player HP changes to trigger vignette and track damage."""
	if not is_instance_valid(_player):
		return
	if not "current_hp" in _player:
		return
	var hp: float = _player.get("current_hp")
	if _last_hp < 0.0:
		_last_hp = hp
		return
	if hp < _last_hp:
		# Player took damage
		var dmg: float = _last_hp - hp
		_total_damage_taken += dmg
		_trigger_vignette()
	_last_hp = hp


func _update_timer_label() -> void:
	var total_seconds: int = int(_time_remaining)
	var minutes: int = int(total_seconds / 60.0)
	var seconds: int = total_seconds % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]


# ---------- MATCH STATS ----------

func _on_player_attacked(_stunned: bool) -> void:
	"""Track attacks when player lands a punch."""
	_total_damage_dealt += 1.0


func _end_match() -> void:
	"""Store match stats in GameState and transition to lobby for analysis."""
	# Store stats in GameState for the lobby to display
	GameState.show_analysis = true
	GameState.match_character_name = _character_name
	GameState.match_damage_taken = _total_damage_taken
	GameState.match_damage_dealt = _total_damage_dealt
	
	# Transition to lobby
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	print("GameMap: Match ended — transitioning to lobby for analysis")
