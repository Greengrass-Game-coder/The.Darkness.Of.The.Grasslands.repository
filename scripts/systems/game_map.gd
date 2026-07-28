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

# Chase music — 4-layer system: Layer1, Layer2, Layer3, Chase
const BOT_CHASE_DIR: String = "res://The Darkness Of The Grasslands assets/Music/Killer Chase Themes/Violentgrass/"
const CHASE_LAYER_FILES: Array[String] = ["Layer1.wav", "Layer2.wav", "Layer3.wav", "Chase.wav"]
const CHASE_ENTER_DIST: Array[float] = [600.0, 350.0, 200.0, 100.0]   # When each layer starts
const CHASE_EXIT_DIST: Array[float]  = [700.0, 450.0, 300.0, 150.0]   # When each layer stops (hysteresis)
const CHASE_LAYER_VOLUME: Array[float] = [-6.0, -3.0, -1.0, 0.0]     # Volume per layer (Layer1 audible, Chase loud)
const CHASE_VOL_FADE_MS: float = 0.3  # Crossfade time (seconds)
const CHASE_MAP_DUCK_DB: float = -18.0  # Background music volume when chase is active

var _time_remaining: float = MATCH_DURATION
var _map_manager: MapManager = null
var _player: Node2D = null
var _killer_bot: Node2D = null
var _chase_layers_enabled: Array[bool] = [false, false, false, false]  # Active state per layer
var _chase_players: Array[AudioStreamPlayer] = []
var _chase_active_layer: int = -1  # Highest active layer index
var _current_interactable: Area2D = null
var _last_hp: float = -1.0
var _solved_puzzles: Array[String] = []
var _e_was_pressed: bool = false
var _puzzle_open: bool = false

# Killer speed scaling (timer < 30s)
var _killer_base_sprint: float = 0.0
var _killer_speed_scaling_active: bool = false

# Death sequence state
var _death_active: bool = false
var _death_overlay: ColorRect = null
var _death_fade_progress: float = 0.0

# Teleport mini-map
var _teleport_minimap: Control = null

# Match-ending effect
var _ending_vignette: ColorRect = null
var _ending_music_switched: bool = false
var _ending_start_time: float = 0.0

# Match stats
var _total_damage_taken: float = 0.0
var _total_damage_dealt: float = 0.0
var _character_name: String = "Greengrass"

# Damage tracking for VFX
var _last_known_hp: float = -1.0
var _last_damage_time: float = -10.0  # When last damage was taken (for screen shake cooldown)


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
	
	# Spawn the player character (also spawns killer bot if survivor)
	spawn_player(GameState.is_killer)
	
	# Setup chat system
	_setup_chat()
	
	# Play killer intro cutscene after spawns are complete
	call_deferred("_play_killer_cutscene")


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
			player.name = "MapMusicPlayer"
			player.stream = stream
			player.autoplay = true
			player.bus = &"Master"
			player.finished.connect(_on_map_music_finished)
			add_child(player)
			print("GameMap: Playing background music")


func _switch_to_ending_music() -> void:
	"""Switch map music to match-ending track at 30s remaining.
	Plays as background music — chase can still play on top."""
	if _ending_music_switched:
		return
	_ending_music_switched = true
	
	# Create a separate ending music player (chase keeps working alongside)
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
	player.volume_db = -2.0
	player.finished.connect(_on_map_music_finished)
	add_child(player)
	
	# Fade out original map music if it's still playing
	var old_player: AudioStreamPlayer = get_node_or_null("MapMusicPlayer")
	if old_player:
		var fade_tween: Tween = create_tween()
		fade_tween.tween_property(old_player, "volume_db", -80.0, 1.0)
		await fade_tween.finished
		old_player.stop()
		old_player.queue_free()
	
	print("GameMap: Switched to MATCH_ENDING music (chase remains on top)")


func _on_map_music_finished() -> void:
	"""Loop map music by restarting playback."""
	var player: AudioStreamPlayer = get_node_or_null("MusicPlayer")
	if not player:
		player = get_node_or_null("MapMusicPlayer")
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
	
	# Set character name for analysis screen
	_character_name = "Violentgrass" if is_killer_player else "Greengrass"
	
	# Create ability icons
	_create_ability_icons(_player, is_killer_player)
	
	# Connect survivor ability icon signals (flash/lock)
	_connect_ability_icon_signals(_player)
	
	# Create health bar UI
	_create_health_bar(_player)
	
	# Create stamina bar UI
	_create_stamina_bar(_player)
	
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
	
	# Connect teleport scan signal for killer mini-map
	if _player.has_signal("teleport_scan_started") and not _player.teleport_scan_started.is_connected(_on_killer_teleport_scan):
		_player.teleport_scan_started.connect(_on_killer_teleport_scan)
	
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
	_update_killer_speed(delta)
	
	# Match-ending effects (last 31 seconds)
	if _time_remaining <= 31.0:
		_ending_start_time += delta
		_update_ending_vignette()
		_switch_to_ending_music()
	
	# +30s timer bonus when killer eliminates a survivor (local mode)
	_check_kill_timer_bonus()
	
	# Death sequence fade
	if _death_active:
		_update_death_fade(delta)


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
		
		# Lock overlay — only for Grass Punch (slot index 1 = E)
		if i == 1:
			var lock_overlay := ColorRect.new()
			lock_overlay.name = "LockOverlay"
			lock_overlay.size = Vector2(56, 56)
			lock_overlay.color = Color(0.3, 0.3, 0.3, 0.7)
			lock_overlay.visible = true  # Start locked
			slot.add_child(lock_overlay)
		
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
		
		# Cooldown overlay (dark + countdown text)
		var cd_overlay := ColorRect.new()
		cd_overlay.name = "CooldownOverlay"
		cd_overlay.size = Vector2(56, 56)
		cd_overlay.color = Color(0.0, 0.0, 0.0, 0.6)
		cd_overlay.visible = false
		slot.add_child(cd_overlay)
		
		var cd_label := Label.new()
		cd_label.name = "CooldownLabel"
		cd_label.size = Vector2(56, 56)
		cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		cd_label.add_theme_font_size_override("font_size", 20)
		cd_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		cd_label.add_theme_constant_override("shadow_offset_x", 1)
		cd_label.add_theme_constant_override("shadow_offset_y", 1)
		cd_overlay.add_child(cd_label)
		
		# Store reference for cooldown tracking
		slot.set_meta("cooldown_var", data["cooldown_var"])


func _update_ability_cooldowns() -> void:
	"""Update cooldown overlays with countdown numbers."""
	var icons: Node = $HUD.get_node_or_null("AbilityIcons")
	if not icons or not is_instance_valid(_player):
		return
	
	for i in range(icons.get_child_count()):
		var slot: Node = icons.get_child(i)
		var data_abilities: Array[Dictionary] = _get_ability_data()
		if i >= data_abilities.size():
			continue
		var cooldown_var_name: String = data_abilities[i]["cooldown_var"]
		var overlay: ColorRect = slot.get_node_or_null("CooldownOverlay")
		if not overlay:
			continue
		
		var is_on_cd: bool = cooldown_var_name in _player and _player.get(cooldown_var_name)
		overlay.visible = is_on_cd
		
		# Update countdown label
		if is_on_cd:
			var cd_label: Label = overlay.get_node_or_null("CooldownLabel")
			if cd_label:
				# Try to get the actual cooldown timer variable
				var timer_var: String = "_" + cooldown_var_name.trim_suffix("_on_cooldown") + "_cd_timer"
				if timer_var in _player:
					var remaining: float = _player.get(timer_var)
					cd_label.text = str(ceili(remaining))
				else:
					cd_label.text = ""
		else:
			var cd_label: Label = overlay.get_node_or_null("CooldownLabel")
			if cd_label:
				cd_label.text = ""


func _get_ability_data() -> Array[Dictionary]:
	"""Return ability data for the current player character."""
	var is_killer: bool = _character_name == "Violentgrass"
	if is_killer:
		return [
			{"icon": "", "key": "Q", "cooldown_var": "hit_on_cooldown"},
			{"icon": "", "key": "R", "cooldown_var": "teleport_on_cooldown"},
		]
	else:
		return [
			{"icon": "", "key": "Q", "cooldown_var": "block_on_cooldown"},
			{"icon": "", "key": "E", "cooldown_var": "punch_on_cooldown"},
			{"icon": "", "key": "R", "cooldown_var": "flower_on_cooldown"},
		]


func _connect_ability_icon_signals(player: Node2D) -> void:
	"""Connect signals for ability icon visual feedback (flash/lock)."""
	if not is_instance_valid(player):
		return
	if player.has_signal("block_unlocked_punch") and not player.block_unlocked_punch.is_connected(_on_punch_unlocked):
		player.block_unlocked_punch.connect(_on_punch_unlocked)
	if player.has_signal("punch_locked_changed") and not player.punch_locked_changed.is_connected(_on_punch_locked_changed):
		player.punch_locked_changed.connect(_on_punch_locked_changed)


func _on_punch_unlocked() -> void:
	"""Flash the Grass Punch icon yellow when unlocked via block."""
	var icons: Node = $HUD.get_node_or_null("AbilityIcons")
	if not icons:
		return
	var punch_slot: Node = icons.get_child(1) if icons.get_child_count() > 1 else null  # Slot index 1 = Grass Punch
	if not punch_slot:
		return
	var icon: TextureRect = punch_slot.get_node_or_null("Icon")
	if not icon:
		return
	# Flash yellow
	var orig_mod: Color = icon.modulate
	icon.modulate = Color(3.0, 3.0, 0.2, 1.0)
	var tween: Tween = create_tween()
	tween.tween_property(icon, "modulate", orig_mod, 0.5).set_ease(Tween.EASE_OUT)


func _on_punch_locked_changed(locked: bool) -> void:
	"""Show/hide lock overlay on Grass Punch icon."""
	var icons: Node = $HUD.get_node_or_null("AbilityIcons")
	if not icons:
		return
	var punch_slot: Node = icons.get_child(1) if icons.get_child_count() > 1 else null
	if not punch_slot:
		return
	var lock_overlay: ColorRect = punch_slot.get_node_or_null("LockOverlay")
	if lock_overlay:
		lock_overlay.visible = locked


func _on_player_hp_changed(current_hp: float, max_hp: float, fill: ColorRect, label: Label) -> void:
	"""Update the health bar when player HP changes."""
	var ratio: float = current_hp / max_hp if max_hp > 0 else 0.0
	fill.size.x = 400.0 * clampf(ratio, 0.0, 1.0)
	label.text = "%d / %d" % [current_hp, max_hp]
	
	# Damage VFX: screen shake + red flash when HP drops
	if _last_known_hp >= 0 and current_hp < _last_known_hp:
		var dmg: float = _last_known_hp - current_hp
		_total_damage_taken += dmg
		_trigger_screen_shake(clampf(dmg * 0.2, 2.0, 8.0), 0.25)
		_trigger_vignette()
		_last_damage_time = _time_remaining
	
	_last_known_hp = current_hp
	
	# Color shifts from green to red as HP drops
	if ratio < 0.3:
		fill.color = Color(0.9, 0.15, 0.15, 0.9)
	elif ratio < 0.6:
		fill.color = Color(0.9, 0.7, 0.1, 0.9)
	else:
		fill.color = Color(0.15, 0.9, 0.15, 0.9)
	
	# Death sequence: when survivor HP reaches 0
	if current_hp <= 0.0 and _last_hp > 0.0:
		# +30s timer bonus if bot killer exists
		if is_instance_valid(_killer_bot):
			_on_killer_eliminated("Player")
		# Start death sequence
		_start_death_sequence()
	_last_hp = current_hp


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
	add_child(bot)
	_killer_bot = bot
	_setup_chase_music()
	# Connect killer hit signal for damage tracking
	if bot.has_signal("hit_landed") and not bot.hit_landed.is_connected(_on_killer_hit_landed):
		bot.hit_landed.connect(_on_killer_hit_landed)
	# Store killer's base sprint speed for scaling
	if bot.has_method("get_sprint_speed"):
		_killer_base_sprint = bot.sprint_speed
	else:
		_killer_base_sprint = 350.0
	print("GameMap: Spawned KillerBot at ", spawn_pos)


func _add_map_border_walls() -> void:
	"""Add 4 invisible wall rectangles around the map perimeter."""
	var map_w: float = _map_manager.blueprint_size.x
	var map_h: float = _map_manager.blueprint_size.y
	var t: float = 32.0  # thickness
	
	var body := StaticBody2D.new()
	body.name = "MapBorderWalls"
	# Map borders on collision layer 3
	body.collision_layer = 4
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


func _read_bot_chase_settings(_bot: Node2D) -> void:
	"""(Reading from bot chase settings is now unused — game_map uses its own CHASE_ENTER/EXIT_DIST constants.)"""
	pass


func _setup_chase_music() -> void:
	"""Create 4 chase layer players (Layer1-3 + Chase), all muted until triggered."""
	_chase_players.clear()
	_chase_layers_enabled = [false, false, false, false]
	_chase_active_layer = -1
	
	for i: int in CHASE_LAYER_FILES.size():
		var file_name: String = CHASE_LAYER_FILES[i]
		var file_path: String = BOT_CHASE_DIR + file_name
		if not ResourceLoader.exists(file_path):
			push_error("GameMap: Chase layer file not found: ", file_path)
			continue
		
		var p := AudioStreamPlayer.new()
		p.name = "ChaseLayer_%d" % i
		p.stream = load(file_path)
		p.autoplay = true
		p.volume_db = -80.0  # Muted until triggered
		p.finished.connect(_on_chase_loop.bind(p))
		add_child(p)
		_chase_players.append(p)
	
	var loaded: int = _chase_players.size()
	print("GameMap: Chase music ready — %d layers loaded" % loaded)


func _play_killer_cutscene() -> void:
	"""Play the Violentgrass killer intro cutscene from PNG frames."""
	# Hide everything except the cutscene
	var hud: CanvasLayer = $HUD
	if hud:
		hud.visible = false
	if map_visual:
		map_visual.visible = false
	
	# Disable player movement
	if is_instance_valid(_player) and _player.has_method("set_physics_process"):
		_player.set_physics_process(false)
	
	var cutscene := CutscenePlayer.new()
	cutscene.name = "KillerCutscene"
	cutscene.fps = 8.0  # 43 frames at 8fps ≈ 5.4 seconds
	add_child(cutscene)
	
	var folder_path: String = "res://The Darkness Of The Grasslands assets/Cutscenes/Killer intros/Violentgrass+killer+intro"
	var audio_path: String = ""  # No audio yet — user can add later
	
	# Pause the match timer while cutscene plays
	if match_timer:
		match_timer.paused = true
	
	cutscene.play_cutscene(folder_path, audio_path)
	
	# Wait for cutscene to finish (has auto-fade in last 1s)
	await cutscene.finished
	cutscene.queue_free()
	
	# Restore everything
	if hud:
		hud.visible = true
	if map_visual:
		map_visual.visible = true
	if is_instance_valid(_player) and _player.has_method("set_physics_process"):
		_player.set_physics_process(true)
	if match_timer:
		match_timer.paused = false
	print("GameMap: Killer intro finished, match started")


func _on_chase_loop(player: AudioStreamPlayer) -> void:
	"""Loop the chase track by replaying on finish."""
	if is_instance_valid(player):
		player.play()


func _update_chase_music(_delta: float) -> void:
	"""4-layer chase: Layer1 (distant) → Layer2 → Layer3 → Chase (intense)."""
	if not is_instance_valid(_killer_bot) or not is_instance_valid(_player):
		return
	if _chase_players.is_empty():
		return
	
	var dist: float = _player.global_position.distance_to(_killer_bot.global_position)
	
	# Determine which layer should be active based on distance
	var target_layer: int = -1  # -1 = no chase (too far)
	for i: int in range(CHASE_ENTER_DIST.size() - 1, -1, -1):
		if dist <= CHASE_ENTER_DIST[i]:
			target_layer = i
	
	# Apply hysteresis: if currently at a layer, use EXIT distance to leave
	if _chase_active_layer >= 0 and target_layer < _chase_active_layer:
		# Check if we've exceeded the exit distance for the current layer
		if dist > CHASE_EXIT_DIST[_chase_active_layer]:
			target_layer = _chase_active_layer - 1
	
	# Clamp target_layer: if no layers match, set to -1
	if target_layer < -1:
		target_layer = -1
	
	# Handle layer transitions
	if target_layer != _chase_active_layer:
		var old_layer: int = _chase_active_layer
		_chase_active_layer = target_layer
		
		# Mute all players first
		for i: int in _chase_players.size():
			if is_instance_valid(_chase_players[i]):
				_chase_layers_enabled[i] = false
				var tween := create_tween()
				tween.tween_property(_chase_players[i], "volume_db", -80.0, CHASE_VOL_FADE_MS)
		
		# Unmute the target layer if any
		if target_layer >= 0 and target_layer < _chase_players.size():
			_chase_layers_enabled[target_layer] = true
			if is_instance_valid(_chase_players[target_layer]):
				var tween := create_tween()
				tween.tween_property(_chase_players[target_layer], "volume_db", CHASE_LAYER_VOLUME[target_layer], CHASE_VOL_FADE_MS)
		
		# Duck background music deeply when chase active (-18dB instead of just -10dB)
		var bg_player: AudioStreamPlayer = get_node_or_null("MusicPlayer")
		if not bg_player:
			bg_player = get_node_or_null("MapMusicPlayer")
		if bg_player:
			var is_chasing: bool = target_layer >= 0
			var target_bg_db: float = CHASE_MAP_DUCK_DB if is_chasing else (-2.0 if _ending_music_switched else 0.0)
			var mtween := create_tween()
			mtween.tween_property(bg_player, "volume_db", target_bg_db, CHASE_VOL_FADE_MS)


# ---------- TELEPORT MINI-MAP ----------

func _on_killer_teleport_scan() -> void:
	"""Show mini-map overlay when killer activates teleport scan."""
	if not is_instance_valid(_killer_bot):
		return
	_show_teleport_minimap()


func _show_teleport_minimap() -> void:
	"""Create a mini-map overlay showing all survivor positions as dots."""
	if is_instance_valid(_teleport_minimap):
		_teleport_minimap.queue_free()
	
	var minimap := Control.new()
	minimap.name = "TeleportMiniMap"
	minimap.size = get_viewport().get_visible_rect().size
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	$HUD.add_child(minimap)
	_teleport_minimap = minimap
	
	# Dark background
	var bg := ColorRect.new()
	bg.size = minimap.size
	bg.color = Color(0, 0, 0, 0.7)
	minimap.add_child(bg)
	
	# Determine map bounds from map manager
	var map_size: Vector2 = _map_manager.blueprint_size if _map_manager else Vector2(1024, 768)
	# Display area for the mini-map (centered, 300x225)
	var mm_w: float = 300.0
	var mm_h: float = 225.0
	var mm_x: float = (minimap.size.x - mm_w) * 0.5
	var mm_y: float = (minimap.size.y - mm_h) * 0.5
	
	# Mini-map background
	var mm_bg := ColorRect.new()
	mm_bg.position = Vector2(mm_x, mm_y)
	mm_bg.size = Vector2(mm_w, mm_h)
	mm_bg.color = Color(0.08, 0.08, 0.08, 0.9)
	minimap.add_child(mm_bg)
	
	# Title
	var title := Label.new()
	title.text = "TELEPORT TARGET"
	title.position = Vector2(mm_x, mm_y - 28)
	title.size = Vector2(mm_w, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1, 1, 0.7, 1))
	title.add_theme_font_size_override("font_size", 18)
	minimap.add_child(title)
	
	# Find all survivors
	var survivors: Array[Node] = get_tree().get_nodes_in_group("survivors")
	
	for s: Node in survivors:
		if not is_instance_valid(s):
			continue
		# Map survivor world position to mini-map position
		var world_pos: Vector2 = s.global_position
		var mm_pos: Vector2 = Vector2(
			mm_x + (world_pos.x / map_size.x) * mm_w,
			mm_y + (world_pos.y / map_size.y) * mm_h
		)
		
		# Create clickable dot for this survivor
		var dot := Button.new()
		dot.name = "Dot_%s" % s.name
		dot.position = mm_pos - Vector2(8, 8)
		dot.size = Vector2(16, 16)
		dot.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
		dot.add_theme_font_size_override("font_size", 14)
		dot.text = "●"
		dot.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		dot.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		dot.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		dot.pressed.connect(_on_minimap_dot_pressed.bind(world_pos))
		minimap.add_child(dot)
	
	# Close button
	var close_btn := Button.new()
	close_btn.text = "X CANCEL"
	close_btn.position = Vector2(mm_x + mm_w - 80, mm_y + mm_h + 8)
	close_btn.size = Vector2(80, 28)
	close_btn.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
	close_btn.pressed.connect(_close_teleport_minimap)
	minimap.add_child(close_btn)


func _on_minimap_dot_pressed(world_pos: Vector2) -> void:
	"""Teleport killer to the clicked survivor position."""
	if is_instance_valid(_killer_bot) and _killer_bot.has_method("teleport_to_position"):
		_killer_bot.teleport_to_position(world_pos)
	_close_teleport_minimap()


func _close_teleport_minimap() -> void:
	"""Remove the teleport mini-map overlay."""
	if is_instance_valid(_teleport_minimap):
		_teleport_minimap.queue_free()
		_teleport_minimap = null


func get_random_killer_spawn() -> Vector2:
	return _map_manager.get_spawn_point(true)


# ---------- KILLER SPEED SCALING (last 30s) ----------

func _update_killer_speed(_delta: float) -> void:
	"""Scale killer's sprint speed faster as timer approaches 0 (after 30s remaining)."""
	if not is_instance_valid(_killer_bot):
		return
	if _time_remaining > 30.0:
		if _killer_speed_scaling_active:
			_killer_speed_scaling_active = false
			# Reset to original speed
			if "sprint_speed" in _killer_bot:
				_killer_bot.sprint_speed = _killer_base_sprint
		return
	
	_killer_speed_scaling_active = true
	# Speed multiplier: 1.0x at 30s → 2.5x at 0s
	var progress: float = 1.0 - (_time_remaining / 30.0)  # 0→1
	var multiplier: float = 1.0 + progress * 1.5  # 1.0x → 2.5x
	var new_speed: float = _killer_base_sprint * multiplier
	_killer_bot.sprint_speed = new_speed


# ---------- KILL ELIMINATION TIMER BONUS (+30s) ----------

var _last_killer_bot_kills: int = 0

func _check_kill_timer_bonus() -> void:
	"""Detect when the killer bot eliminates a survivor and add 30s to timer."""
	if not is_instance_valid(_killer_bot):
		return
	# Trick: track a count we can observe. In local mode, the bot "kills" by
	# proximity — the player dies when the killer touches them (via _on_player_died).
	# The +30s is actually added there. See _on_player_died() for implementation.

func add_timer_bonus(seconds: float) -> void:
	"""Add time to the match timer (e.g. +30s when killer kills a survivor)."""
	_time_remaining = min(_time_remaining + seconds, MATCH_DURATION)
	_update_timer_label()
	print("GameMap: Timer +", seconds, "s (now ", _time_remaining, "s)")


# ---------- KILLER ELIMINATION TRACKING ----------

func _on_killer_eliminated(_player_name: String) -> void:
	"""Called when killer eliminates a survivor (from network or local)."""
	# +30s timer bonus
	add_timer_bonus(30.0)


# ---------- MATCH TIMER ----------

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


func _on_killer_hit_landed(target: Node2D, damage: float) -> void:
	"""Track when killer lands a hit (for stats and VFX)."""
	print("GameMap: Killer landed hit for %.1f damage on %s" % [damage, target.name])


func _trigger_vignette() -> void:
	"""Flash a subtle dark vignette when taking damage."""
	if not is_instance_valid(_vignette_overlay):
		return
	var enabled: bool = "epilepsy_safe_mode" in GameState and GameState.epilepsy_safe_mode
	var target_alpha: float = 0.25 if enabled else 0.4  # Slightly stronger if epilepsy mode is off
	
	_vignette_overlay.color = Color(0, 0, 0, target_alpha)
	var tween := create_tween()
	tween.tween_property(_vignette_overlay, "color", Color(0, 0, 0, 0), 0.8).set_ease(Tween.EASE_OUT)


func _apply_shake(progress: float, cam: Camera2D, intensity: float) -> void:
	"""Apply a decaying random shake offset to the camera."""
	if not is_instance_valid(cam):
		return
	var orig: Vector2 = cam.get("_shake_orig") if cam.get("_shake_orig") != null else Vector2.ZERO
	var decay: float = 1.0 - progress
	cam.offset = orig + Vector2(
		randf_range(-intensity, intensity) * decay,
		randf_range(-intensity, intensity) * decay
	)


func _end_shake(cam: Camera2D) -> void:
	"""Restore camera offset after shake ends."""
	if is_instance_valid(cam):
		var orig: Vector2 = cam.get("_shake_orig") if cam.get("_shake_orig") != null else Vector2.ZERO
		cam.offset = orig


func _trigger_screen_shake(intensity: float = 5.0, duration: float = 0.2) -> void:
	"""Apply a brief screen shake by offsetting the player's Camera2D."""
	if not is_instance_valid(_player):
		return
	var cam: Camera2D = _player.get_node_or_null("Camera2D")
	if not cam:
		return
	# Use tween_method to apply decaying random shake over duration
	cam.set("_shake_elapsed", 0.0)
	cam.set("_shake_orig", cam.offset)
	var tween: Tween = create_tween()
	tween.tween_method(_apply_shake.bind(cam, intensity), 0.0, 1.0, duration).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_end_shake.bind(cam))


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

# ---------- CHAT SYSTEM ----------

func _setup_chat() -> void:
	"""Create ChatLayer instance and connect its signals."""
	var chat := ChatLayer.new()
	chat.name = "ChatLayer"
	chat.chat_sent.connect(_on_map_chat_sent)
	add_child(chat)


func _on_map_chat_sent(text: String, is_admin: bool) -> void:
	"""Handle a chat message sent from ChatLayer in game map."""
	var trimmed: String = text.strip_edges().to_lower()
	if trimmed == "g" or trimmed == "g help":
		_show_map_admin_help()
		return
	
	if is_admin and GameState.connected_to_server:
		var nm: Node = Engine.get_singleton("NetworkManager")
		if is_instance_valid(nm) and nm.has_method("send_admin_command"):
			nm.send_admin_command(text.trim_prefix("G "))
		return
	
	if GameState.connected_to_server:
		var nm: Node = Engine.get_singleton("NetworkManager")
		if is_instance_valid(nm) and nm.has_method("send_chat"):
			nm.send_chat(text)
	else:
		var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
		if chat_layer:
			chat_layer.add_system_message("Chat sent (offline): %s" % text)


func _show_map_admin_help() -> void:
	"""Display all available admin commands in chat."""
	var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
	if not chat_layer:
		return
	chat_layer.add_system_message("=== ADMIN COMMANDS ===")
	chat_layer.add_system_message("G end / G round - End current round")
	chat_layer.add_system_message("G kill <name> - Eliminate player")
	chat_layer.add_system_message("G force / G next - Force next killer")
	chat_layer.add_system_message("G gamemode select double trouble - Toggle double trouble")
	chat_layer.add_system_message("G AUTH <pw> - Authenticate as admin")
	chat_layer.add_system_message("=====================")


func _on_player_attacked(_stunned: bool) -> void:
	"""Track attacks when player lands a punch."""
	_total_damage_dealt += 1.0


# ---------- DEATH SEQUENCE ----------

func _start_death_sequence() -> void:
	"""Start the 5-second death fade-out sequence."""
	if _death_active:
		return
	_death_active = true
	_death_fade_progress = 0.0
	
	# Disable player physics (can't move)
	if is_instance_valid(_player):
		_player.set_physics_process(false)
		# Greying out the player
		_player.modulate = Color(0.6, 0.6, 0.6, 1.0)
	
	# Create fade overlay on top of everything
	_death_overlay = ColorRect.new()
	_death_overlay.name = "DeathOverlay"
	_death_overlay.color = Color(0.15, 0.15, 0.15, 0.0)  # Start transparent
	_death_overlay.size = get_viewport().get_visible_rect().size
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(_death_overlay)
	
	print("GameMap: Death sequence started — fading out over 5 seconds")


func _update_death_fade(delta: float) -> void:
	"""Advance the death fade progress."""
	_death_fade_progress += delta / 5.0  # Complete over 5 seconds
	var alpha: float = clampf(_death_fade_progress, 0.0, 1.0)
	# Fade from transparent to 85% grey
	if is_instance_valid(_death_overlay):
		_death_overlay.color = Color(0.15, 0.15, 0.15, alpha * 0.85)
	
	# After 5 seconds, end match
	if _death_fade_progress >= 1.0:
		_death_active = false
		if is_instance_valid(_death_overlay):
			_death_overlay.queue_free()
		_end_match()


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
