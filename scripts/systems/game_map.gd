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
const AI_SURVIVOR_BOT_SCRIPT: Script = preload("res://scripts/characters/ai_survivor_bot_controller.gd")

# Chase music — 4-layer system: Layer1, Layer2, Layer3, Chase
## Settings: configurable folder names for killer + survivor chase themes (auto-searches)
@export var killer_chase_folder: String = "Violentgrass"   # Folder under Killer Chase Themes/ for killer player
@export var survivor_chase_folder: String = "Greengrass"    # Folder under Killer Chase Themes/ for survivor player
const CHASE_BASE_DIR: String = "res://The Darkness Of The Grasslands assets/Music/Killer Chase Themes/"
const CHASE_LAYER_FILES: Array[String] = ["Layer1.wav", "Layer2.wav", "Layer3.wav", "Chase.wav"]
# Killer chase: only Chase layer (no build-up) — distance in pixels
const KILLER_CHASE_ENTER: Array[float] = [0.0, 0.0, 0.0, 250.0]
const KILLER_CHASE_EXIT: Array[float]  = [0.0, 0.0, 0.0, 300.0]
# Survivor chase: all 4 layers with build-up
const SURVIVOR_CHASE_ENTER: Array[float] = [500.0, 300.0, 150.0, 80.0]
const SURVIVOR_CHASE_EXIT: Array[float]  = [600.0, 400.0, 250.0, 150.0]
const CHASE_LAYER_VOLUME: Array[float] = [-6.0, -3.0, -1.0, 0.0]     # Volume per layer (Layer1 audible, Chase loud)
const CHASE_VOL_FADE_MS: float = 0.3  # Crossfade time (seconds)
const CHASE_MAP_DUCK_DB: float = -18.0  # Background music volume when chase is active

var _time_remaining: float = MATCH_DURATION
var _map_manager: MapManager = null
var _player: Node2D = null
var _killer_bot: Node2D = null
var _survivor_bots: Array[Node2D] = []
var _alive_survivor_bot_count: int = 0
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
var _teleport_circles: Array[Node] = []       # Teleport overlay children
var _teleport_markers_active: bool = false     # Whether markers are being shown
var _teleport_marker_targets: Array[Vector2] = []  # World positions of each marker target
var _teleport_marker_buttons: Array[Button] = []   # The UI buttons for each marker

# Match-ending effect
var _ending_vignette: ColorRect = null
var _ending_music_switched: bool = false
var _ending_start_time: float = 0.0

# Match ending screen (timer ≤ 30s — Violentgrass only)
var _ending_screen_bg: TextureRect = null
var _ending_screen_overlay: TextureRect = null
var _ending_screen_created: bool = false
var _ending_bg_alpha: float = 0.0
var _ending_shake_timer: float = 0.0

# Red UI flash elements (appear at 18s remaining, flash left→right at 150+ BPM)
var _ending_red_left: ColorRect = null
var _ending_red_right: ColorRect = null
var _ending_red_active: bool = false
var _ending_red_flash_timer: float = 0.0
var _ending_red_show_left: bool = true

# Match stats
var _total_damage_taken: float = 0.0
var _total_damage_dealt: float = 0.0
var _character_name: String = "Greengrass"

# Damage tracking for VFX (consolidated with _last_hp)
# @deprecated _last_known_hp — now using _last_hp for both paths
var _last_damage_time: float = -10.0  # When last damage was taken (for screen shake cooldown)

# BitmapLabel references
var _bitmap_timer: BitmapLabel = null
var _timer_flash_red: float = 0.0  # Timer turns red when decreasing

# Kill bonus animation state
var _bonus_target: float = 0.0  # Target _time_remaining after bonus animation
var _bonus_tick_timer: float = 0.0  # Accumulator for 1-second ticks

# Multiplayer integration
var _multiplayer_sync: MultiplayerGameSync = null

# AI difficulty controller
var _ai_difficulty: AIDifficultyController = null


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
	
	# Determine if this player should be the killer based on rings
	var gs = get_node("/root/GameState")
	var should_be_killer: bool = false
	if gs != null:
		should_be_killer = _determine_killer_by_rings()
		gs.is_killer = should_be_killer
	
	# Spawn the player character (also spawns killer bot if survivor)
	spawn_player(should_be_killer)
	
	# Setup chat system
	_setup_chat()
	
	# Load saved settings into GameState
	_apply_saved_settings()
	
	# Setup admin panel (for in-game admin controls)
	_setup_admin_panel()
	
	# Replace HUD labels with BitmapLabel versions
	_replace_hud_labels()
	
	# Initialize multiplayer sync if connected to server
	_initialize_multiplayer()
	
	# Play killer intro cutscene after spawns are complete
	call_deferred("_play_killer_cutscene")


func _replace_hud_labels() -> void:
	"""Replace key HUD Label nodes with BitmapLabel versions using Font1."""
	var _fm_node = get_node_or_null("/root/FontManager")
	if not is_instance_valid(_fm_node):
		return
	
	# Replace timer label
	if is_instance_valid(timer_label):
		var parent := timer_label.get_parent()
		if parent:
			var bl := BitmapLabel.new()
			bl.name = "BmpTimer"
			bl.label_text = timer_label.text
			bl.font_scale = 0.22
			bl.char_spacing = 4.0
			bl.horizontal_align = timer_label.horizontal_alignment
			bl.font_color = Color(1, 1, 1, 1)
			bl.position = timer_label.position
			bl.size = timer_label.size
			timer_label.visible = false
			parent.add_child(bl)
			_bitmap_timer = bl

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
		area.body_entered.connect(_on_stairs_entered.bind(area))
		area.body_exited.connect(_on_stairs_exited.bind(area))
		add_child(area)
	
	# Puzzles as interactive Area2D triggers
	# Pre-assign random puzzle types per zone for variety
	var puzzle_type_names: Array[String] = ["Memory", "Wiring", "Rhythm"]
	for i in range(_map_manager.puzzle_positions.size()):
		var pos: Vector2 = _map_manager.puzzle_positions[i]
		# Shift puzzle to be at the left edge of the purple region
		# (where the player naturally walks through) and at player y-height
		var adjusted_pos := Vector2(pos.x - 56.0, pos.y - 45.0)
		var area := Area2D.new()
		area.name = "Puzzle_%d" % i
		# Assign a random puzzle type to this zone (fixed per match)
		var ptype: String = puzzle_type_names[randi() % puzzle_type_names.size()]
		area.set_meta("puzzle_type", ptype)
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
	var gs_sp = get_node("/root/GameState")
	var is_killer_player: bool = spawn_as_killer or (gs_sp != null and gs_sp.is_killer)
	var spawn_pos: Vector2 = _map_manager.get_spawn_point(is_killer_player)
	
	var player_scene: PackedScene = VIOLENTGRASS_SCENE if is_killer_player else GREENGRASS_SCENE
	_player = player_scene.instantiate()
	_player.name = "Player"
	_player.position = spawn_pos
	add_child(_player)
	
	# Enable camera on the player
	# Camera zoom controller — adds scroll-wheel zoom + larger default zoom
	var zoom_ctrl := CameraZoomController.new()
	zoom_ctrl.name = "ZoomController"
	zoom_ctrl.default_zoom = 1.25  # Bigger than default 1.0 for easier viewing
	_player.add_child(zoom_ctrl)
	# Connect zoom to HUD vignette/overlay scaling if needed
	var cam: Camera2D = _player.get_node_or_null("Camera2D") as Camera2D
	
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
	
	# Spawn bot killer if survivor, or survivor bots if killer
	# Set up chase music for both roles
	if not is_killer_player:
		_spawn_bot_killer()
		# Attach dynamic difficulty controller to AI bot
		_attach_ai_difficulty()
		# Survivor player: load all 4 chase layers from survivor's theme folder
		_setup_chase_music(survivor_chase_folder)
	else:
		_spawn_survivor_bots()
		# Killer player: load only Chase layer from killer's theme folder
		_setup_chase_music(killer_chase_folder)
	
	# Track damage dealt via punch signal
	if _player.has_signal("punch_landed") and not _player.punch_landed.is_connected(_on_player_attacked):
		_player.punch_landed.connect(_on_player_attacked)
	
	# Connect teleport scan signal for killer mini-map
	if _player.has_signal("teleport_scan_started") and not _player.teleport_scan_started.is_connected(_on_killer_teleport_scan):
		_player.teleport_scan_started.connect(_on_killer_teleport_scan)
	
	# Connect teleported signal for sound + indicator
	if _player.has_signal("teleported") and not _player.teleported.is_connected(_on_player_teleported):
		_player.teleported.connect(_on_player_teleported)
	
	# Connect teleport cancel to close mini-map
	if _player.has_signal("teleport_cancelled") and not _player.teleport_cancelled.is_connected(_close_teleport_minimap):
		_player.teleport_cancelled.connect(_close_teleport_minimap)
	
	# Re-assert player camera (bots spawned above may have tried to steal it)
	if is_instance_valid(cam):
		cam.enabled = true
		cam.make_current()
	
	print("GameMap: Spawned ", _character_name, " at ", spawn_pos)


# ═══════════════ STAIRS SYSTEM ═══════════════

func _on_stairs_entered(body: Node2D, area: Area2D) -> void:
	"""When a player enters a stair zone, check front/behind."""
	if not _is_player_or_bot(body):
		return
	# Player is BEHIND stairs (Y < center) → climb (scale up)
	# Player is IN FRONT of stairs (Y > center) → blocked (collision stays)
	var behind: bool = body.global_position.y < area.global_position.y
	if behind:
		body.set("stair_climbing", true)
		# Scale up to create depth illusion
		var tween := create_tween()
		tween.tween_property(body, "scale", body.scale * 1.5, 0.2)
		# Disable collision with the stair segment so player can walk through
		body.set_collision_mask_value(4, false)  # Temporarily disable wall collision


func _on_stairs_exited(body: Node2D, _area: Area2D) -> void:
	"""When a player exits a stair zone, restore normal scale and collision."""
	if not _is_player_or_bot(body):
		return
	body.set("stair_climbing", false)
	# Restore normal scale
	var tween := create_tween()
	tween.tween_property(body, "scale", body.scale / 1.5, 0.2)
	# Restore wall collision
	body.set_collision_mask_value(4, true)


func _is_player_or_bot(body: Node2D) -> bool:
	"""Check if the body is the player or an AI bot."""
	if body == _player:
		return true
	if _survivor_bots.has(body):
		return true
	if _killer_bot == body:
		return true
	return false


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
	
	# Multiplayer position sync
	if _multiplayer_sync and is_instance_valid(_player):
		_sync_multiplayer_position(_player.global_position)
	
	# Animated timer bonus count-up (red, tick-by-tick)
	if _bonus_target > 0.0:
		_bonus_tick_timer += delta
		var tick_speed: float = 0.15  # ~6.7 ticks per second
		while _bonus_tick_timer >= tick_speed and _time_remaining < _bonus_target:
			_bonus_tick_timer -= tick_speed
			_time_remaining = min(_time_remaining + 1.0, _bonus_target)
			_timer_flash_red = 0.3  # Keep red while counting up
			_update_timer_label()
		if _time_remaining >= _bonus_target:
			_bonus_target = 0.0
			_bonus_tick_timer = 0.0
	
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
		# Match ending screen (Violentgrass) — create once, update each frame
		if not _ending_screen_created:
			_create_match_ending_screen()
		_update_match_ending_screen(delta)
	
	# Update AI difficulty scaling
	_update_ai_difficulty()
	
	# Update screen-edge teleport markers (reposition as camera moves)
	_update_teleport_markers()
	
	# +30s timer bonus when killer eliminates a survivor (local mode)
	_check_kill_timer_bonus()
	
	# Decrease timer flash (puzzle reward red flash)
	if _timer_flash_red > 0.0:
		_timer_flash_red -= delta
	
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
	if _last_hp >= 0 and current_hp < _last_hp:
		var dmg: float = _last_hp - current_hp
		_total_damage_taken += dmg
		_trigger_screen_shake(clampf(dmg * 0.2, 2.0, 8.0), 0.25)
		_trigger_vignette()
		_last_damage_time = _time_remaining
	_last_hp = current_hp
	
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


func _on_player_stamina_changed(current: float, max_stamina: float, fill: ColorRect) -> void:
	"""Update the stamina fill bar width based on remaining stamina."""
	var ratio: float = current / max_stamina if max_stamina > 0 else 0.0
	fill.size.x = 400.0 * clampf(ratio, 0.0, 1.0)
	fill.color.a = 0.5 if ratio < 0.2 else 0.9  # Dim when low


func _spawn_survivor_bots() -> void:
	"""Spawn AI-controlled survivor bots that do puzzles."""
	var survivor_spawns: Array[Vector2] = _map_manager.survivor_spawns if _map_manager else []
	if survivor_spawns.is_empty():
		var mid: Vector2 = Vector2(512, 384)
		var offsets: Array[Vector2] = [Vector2(-200, -200), Vector2(200, -200), Vector2(-200, 200), Vector2(200, 200)]
		for i in range(min(4, offsets.size())):
			_bots_create_survivor(mid + offsets[i], "SurvivorBot_%d" % i)
	else:
		var count: int = min(4, survivor_spawns.size())
		for i in range(count):
			_bots_create_survivor(survivor_spawns[i], "SurvivorBot_%d" % i)
	print("GameMap: Spawned %d survivor bots" % _survivor_bots.size())


func _bots_create_survivor(spawn_pos: Vector2, name_str: String) -> void:
	"""Create and configure a single survivor bot."""
	var bot: Node2D = GREENGRASS_SCENE.instantiate()
	bot.set_script(AI_SURVIVOR_BOT_SCRIPT)
	bot.name = name_str
	bot.position = spawn_pos
	# Disable bot camera so it doesn't steal focus from the player
	var bot_cam: Camera2D = bot.get_node_or_null("Camera2D") as Camera2D
	if bot_cam:
		bot_cam.enabled = false
	add_child(bot)
	if bot.has_signal("bot_solved_puzzle"):
		bot.bot_solved_puzzle.connect(_on_bot_solved_puzzle)
	# Track bot HP to detect elimination
	if bot.has_signal("hp_changed"):
		bot.hp_changed.connect(_on_bot_hp_changed.bind(bot))
	_survivor_bots.append(bot)
	_alive_survivor_bot_count += 1


func _spawn_bot_killer() -> void:
	"""Spawn an AI-controlled killer bot at a killer spawn point."""
	var spawn_pos: Vector2 = _map_manager.get_spawn_point(true)
	
	var bot: Node2D = VIOLENTGRASS_SCENE.instantiate()
	bot.set_script(AI_BOT_SCRIPT)
	bot.name = "KillerBot"
	bot.position = spawn_pos
	add_child(bot)
	_killer_bot = bot
	# Connect killer hit signal for damage tracking
	if bot.has_signal("hit_landed") and not bot.hit_landed.is_connected(_on_killer_hit_landed):
		bot.hit_landed.connect(_on_killer_hit_landed)
	# Connect teleported signal for sound + indicator
	if bot.has_signal("teleported") and not bot.teleported.is_connected(_on_player_teleported):
		bot.teleported.connect(_on_player_teleported)
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


func _setup_chase_music(folder_name: String) -> void:
	"""Create chase layer players from the specified theme folder, all muted until triggered.
	Auto-searches in CHASE_BASE_DIR + folder_name/ for Layer1-3.wav and Chase.wav."""
	_chase_players.clear()
	_chase_layers_enabled = [false, false, false, false]
	_chase_active_layer = -1
	
	var dir: String = CHASE_BASE_DIR + folder_name + "/"
	
	for i: int in CHASE_LAYER_FILES.size():
		var file_name: String = CHASE_LAYER_FILES[i]
		var file_path: String = dir + file_name
		if not ResourceLoader.exists(file_path):
			push_error("GameMap: Chase layer file not found: ", file_path)
			continue
		
		var p := AudioStreamPlayer.new()
		p.name = "ChaseLayer_%d" % i
		p.stream = load(file_path)
		# Enable seamless looping on short WAV layers
		var sdata = p.stream
		if sdata is AudioStreamWAV:
			sdata.loop_mode = AudioStreamWAV.LOOP_FORWARD
		p.autoplay = true
		p.volume_db = -80.0  # Muted until triggered
		add_child(p)
		_chase_players.append(p)
	
	var loaded: int = _chase_players.size()
	print("GameMap: Chase music ready — %d layers loaded from '%s'" % [loaded, folder_name])


func _play_killer_cutscene() -> void:
	"""Play the Violentgrass killer intro cutscene from PNG frames.
	Also shows animated text overlay: 'THE NEXT KILLER IS:' fades in,
	then killer name + player username appear 2.5s later with zoom effect."""
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
	
	# ── Build text overlay (on top of cutscene frames) ──
	var overlay := CanvasLayer.new()
	overlay.name = "KillerIntroTextOverlay"
	overlay.layer = 5  # Above cutscene (layer 0/1), below HUD (layer 10)
	add_child(overlay)
	
	var container := Control.new()
	container.name = "IntroTextContainer"
	container.anchors_preset = Control.PRESET_FULL_RECT
	overlay.add_child(container)
	
	# "THE NEXT KILLER IS:" — appears immediately with fade + zoom
	var line1 := Label.new()
	line1.name = "Line1_TheNextKiller"
	line1.text = "THE NEXT KILLER IS:"
	line1.anchors_preset = Control.PRESET_TOP_WIDE
	line1.offset_left = 0
	line1.offset_right = 0
	line1.offset_top = 220
	line1.offset_bottom = 300
	line1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line1.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	line1.add_theme_font_size_override("font_size", 46)
	line1.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	line1.add_theme_constant_override("outline_size", 5)
	line1.modulate = Color(1, 1, 1, 0)
	line1.pivot_offset = Vector2(512, 50)  # center of label for scale-from-center
	line1.scale = Vector2(0.5, 0.5)
	container.add_child(line1)
	
	# Killer name — appears 2.5s later with fade + zoom
	# Show "Killer_AI" when no human killer (AI bot is the killer)
	var gs_k = get_node_or_null("/root/GameState")
	var is_human_killer: bool = gs_k != null and gs_k.is_killer
	var killer_name: String = "Violentgrass" if is_human_killer else "Killer_AI"
	var line2 := Label.new()
	line2.name = "Line2_KillerName"
	line2.text = killer_name
	line2.anchors_preset = Control.PRESET_TOP_WIDE
	line2.offset_left = 0
	line2.offset_right = 0
	line2.offset_top = 310
	line2.offset_bottom = 410
	line2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line2.add_theme_color_override("font_color", Color(1, 0.15, 0.15, 1))
	line2.add_theme_font_size_override("font_size", 68)
	line2.add_theme_color_override("font_outline_color", Color(0.3, 0, 0, 1))
	line2.add_theme_constant_override("outline_size", 8)
	line2.modulate = Color(1, 1, 1, 0)
	line2.pivot_offset = Vector2(512, 60)  # center of label for scale-from-center
	line2.scale = Vector2(0.4, 0.4)
	container.add_child(line2)
	
	# Player username — same timing as killer name, positioned below
	var player_name: String = ""
	var gs = get_node("/root/GameState")
	if gs != null:
		player_name = gs.logged_in_username
	var line3 := Label.new()
	line3.name = "Line3_PlayerName"
	line3.text = player_name
	line3.anchors_preset = Control.PRESET_TOP_WIDE
	line3.offset_left = 0
	line3.offset_right = 0
	line3.offset_top = 420
	line3.offset_bottom = 470
	line3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line3.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line3.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	line3.add_theme_font_size_override("font_size", 26)
	line3.modulate = Color(1, 1, 1, 0)
	line3.pivot_offset = Vector2(512, 25)  # center of label for scale-from-center
	line3.scale = Vector2(0.4, 0.4)
	container.add_child(line3)
	
	# ── Animate ──
	# Line 1: fade in + zoom immediately (0.8s)
	var t1: Tween = create_tween().set_parallel(true)
	t1.tween_property(line1, "modulate", Color(1, 1, 1, 1), 0.8).set_ease(Tween.EASE_OUT)
	t1.tween_property(line1, "scale", Vector2(1.0, 1.0), 0.8).set_ease(Tween.EASE_OUT)
	
	# Wait 2.5s, then lines 2 and 3: fade in + zoom (1.0s)
	var t2_start: float = 2.5
	await get_tree().create_timer(t2_start).timeout
	
	if is_instance_valid(overlay):
		var t2: Tween = create_tween().set_parallel(true)
		t2.tween_property(line2, "modulate", Color(1, 0.15, 0.15, 1), 1.0).set_ease(Tween.EASE_OUT)
		t2.tween_property(line2, "scale", Vector2(1.0, 1.0), 1.0).set_ease(Tween.EASE_OUT)
		t2.tween_property(line3, "modulate", Color(0.6, 0.6, 0.6, 0.6), 1.0).set_ease(Tween.EASE_OUT)
		t2.tween_property(line3, "scale", Vector2(1.0, 1.0), 1.0).set_ease(Tween.EASE_OUT)
	
	# Wait for cutscene to finish (has auto-fade in last 1s)
	await cutscene.finished
	cutscene.queue_free()
	
	# Clean up the text overlay
	if is_instance_valid(overlay):
		overlay.queue_free()
	
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
	"""Update chase music based on player role.
	
	- If player IS the killer → play killer's chase theme (only Chase layer) when close to survivors
	- If player IS a survivor → play survivor's chase theme (all 4 build-up layers) when killer is close
	
	Only ONE layer plays at a time (no stacking)."""
	if _chase_players.is_empty():
		return
	
	var is_killer: bool = _character_name == "Violentgrass"
	var chase_source: Node2D = null
	var enter_dist: Array[float]
	var exit_dist: Array[float]
	
	if is_killer:
		# Player is the killer — measure distance from player to nearest survivor
		chase_source = _player if is_instance_valid(_player) else null
		enter_dist = KILLER_CHASE_ENTER
		exit_dist = KILLER_CHASE_EXIT
	else:
		# Player is a survivor — measure distance from killer bot to nearest survivor
		chase_source = _killer_bot if is_instance_valid(_killer_bot) else null
		enter_dist = SURVIVOR_CHASE_ENTER
		exit_dist = SURVIVOR_CHASE_EXIT
	
	if not is_instance_valid(chase_source):
		_silence_all_chase()
		return
	
	# Measure distance from chase source to nearest survivor
	var survivors: Array[Node] = get_tree().get_nodes_in_group("survivors")
	var closest_dist: float = INF
	for s in survivors:
		if is_instance_valid(s):
			var d: float = chase_source.global_position.distance_to(s.global_position)
			if d < closest_dist:
				closest_dist = d
	
	if closest_dist == INF:
		_silence_all_chase()
		return
	
	var dist: float = closest_dist
	
	# Determine which layer should be active based on distance
	var target_layer: int = -1
	for i: int in range(enter_dist.size() - 1, -1, -1):
		if dist <= enter_dist[i]:
			target_layer = i
			break
	
	# Apply hysteresis: use EXIT distance to leave current layer
	if _chase_active_layer >= 0 and target_layer < _chase_active_layer:
		if dist > exit_dist[_chase_active_layer]:
			target_layer = -1  # Go straight to silence
	
	if target_layer < -1:
		target_layer = -1
	
	# Handle layer transitions
	if target_layer != _chase_active_layer:
		var _old_layer: int = _chase_active_layer
		_chase_active_layer = target_layer
		
		# INSTANTLY mute all players
		for i: int in _chase_players.size():
			if is_instance_valid(_chase_players[i]):
				_chase_layers_enabled[i] = false
				_chase_players[i].volume_db = -80.0
		
		# Fade-IN only the target layer
		if target_layer >= 0 and target_layer < _chase_players.size():
			_chase_layers_enabled[target_layer] = true
			if is_instance_valid(_chase_players[target_layer]):
				var tween := create_tween()
				tween.tween_property(_chase_players[target_layer], "volume_db", CHASE_LAYER_VOLUME[target_layer], CHASE_VOL_FADE_MS)
		
		# Duck background music when chase active
		var bg_player: AudioStreamPlayer = get_node_or_null("MusicPlayer")
		if not bg_player:
			bg_player = get_node_or_null("MapMusicPlayer")
		if bg_player:
			var is_chasing: bool = target_layer >= 0
			var target_bg_db: float = CHASE_MAP_DUCK_DB if is_chasing else (-2.0 if _ending_music_switched else 0.0)
			var mtween := create_tween()
			mtween.tween_property(bg_player, "volume_db", target_bg_db, CHASE_VOL_FADE_MS)


func _silence_all_chase() -> void:
	"""Silence all chase layers."""
	for i in range(_chase_players.size()):
		var player: AudioStreamPlayer = _chase_players[i]
		if is_instance_valid(player):
			player.volume_db = -80.0
	_chase_active_layer = -1


# ---------- TELEPORT CIRCLES (screen-edge indicators) ----------

func _on_killer_teleport_scan() -> void:
	"""Show screen-edge teleport indicators.
	Works for both human killers (GameState.is_killer) and AI bot killers."""
	var gs_t = get_node_or_null("/root/GameState")
	if (gs_t != null and gs_t.is_killer) or is_instance_valid(_killer_bot):
		_show_teleport_circles()


func _show_teleport_circles() -> void:
	"""Show clickable screen-edge circles — 2 per survivor (real + decoy).
	Circles are positioned at the edge of the killer's camera viewport,
	pointing toward each target position. Killer clicks to teleport."""
	_close_teleport_minimap()
	_teleport_circles.clear()
	_teleport_marker_buttons.clear()
	_teleport_marker_targets.clear()
	
	# Generate a red circle texture for all markers
	var marker_tex: Texture2D = _make_teleport_marker_texture(48, 20)
	
	# Gather target positions: 2 per survivor (real-area + decoy)
	var survivors: Array[Node] = get_tree().get_nodes_in_group("survivors")
	for s: Node in survivors:
		if not is_instance_valid(s):
			continue
		var real_pos: Vector2 = s.global_position
		
		# Target 1: far from survivor (200-400px offset — full-distance teleport)
		var offset1: Vector2 = Vector2(randf_range(-400, 400), randf_range(-400, 400))
		if offset1.length() < 200.0:
			offset1 = offset1.normalized() * 200.0
		_teleport_marker_targets.append(real_pos + offset1)
		
		# Target 2: decoy at a random map position
		_teleport_marker_targets.append(_get_random_map_position())
	
	# Create a CanvasLayer overlay for the screen-space markers
	var overlay := CanvasLayer.new()
	overlay.name = "TeleportOverlay"
	overlay.layer = 128
	add_child(overlay)
	_teleport_circles.append(overlay)
	
	# Create a clickable button for each target
	for i in range(_teleport_marker_targets.size()):
		var btn := Button.new()
		btn.name = "TeleportMarker_%d" % i
		btn.icon = marker_tex
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.size = Vector2(48, 48)
		# Flat invisible style (just the icon shows)
		btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		# Connect click to teleport
		btn.pressed.connect(_on_teleport_marker_pressed.bind(i))
		overlay.add_child(btn)
		_teleport_marker_buttons.append(btn)
		_teleport_circles.append(btn)
		
		# Pulsing animation via tween on the button scale
		var pulse := create_tween().set_loops()
		pulse.tween_property(btn, "scale", Vector2(1.3, 1.3), 0.8)
		pulse.tween_property(btn, "scale", Vector2(0.9, 0.9), 0.8)
	
	# Cancel hint at top of screen
	var hint := Label.new()
	hint.name = "TeleportCancelHint"
	hint.text = "[E] to cancel"
	hint.add_theme_color_override("font_color", Color(1, 0.6, 0.6, 0.9))
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	hint.add_theme_constant_override("outline_size", 2)
	hint.size = Vector2(160, 24)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - 80, 12)
	overlay.add_child(hint)
	_teleport_circles.append(hint)
	
	_teleport_markers_active = true


func _make_teleport_marker_texture(size: int, radius: float) -> Texture2D:
	"""Generate a red circle texture for screen-edge teleport markers."""
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: float = size * 0.5
	var cy: float = size * 0.5
	for x in range(size):
		for y in range(size):
			var dx: float = x - cx
			var dy: float = y - cy
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= radius:
				# Red circle with soft gradient
				var t: float = dist / radius
				var alpha: float = 1.0 - t * 0.3
				img.set_pixel(x, y, Color(1, 0.2, 0.2, alpha))
			# Bright ring at edge
			if abs(dist - radius) < 2.0 and dist > 0:
				img.set_pixel(x, y, Color(1, 0.5, 0.5, 1.0))
	return ImageTexture.create_from_image(img)


func _update_teleport_markers() -> void:
	"""Reposition each screen-edge marker to point toward its target.
	Called every frame from _process while markers are active."""
	if not _teleport_markers_active:
		return
	
	var camera: Camera2D = get_viewport().get_camera_2d()
	if not is_instance_valid(camera):
		return
	
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var cam_pos: Vector2 = camera.global_position
	var margin: float = 60.0  # Pixels from viewport edge
	var half: Vector2 = viewport_size * 0.5
	
	for i in range(_teleport_marker_buttons.size()):
		var btn: Button = _teleport_marker_buttons[i]
		if not is_instance_valid(btn):
			continue
		if i >= _teleport_marker_targets.size():
			continue
		
		var target_pos: Vector2 = _teleport_marker_targets[i]
		var dir: Vector2 = (target_pos - cam_pos).normalized()
		
		# Project direction to viewport edge (with margin)
		var safe_rect: Vector2 = half - Vector2(margin, margin)
		var s_x: float = safe_rect.x / abs(dir.x) if dir.x != 0.0 else INF
		var s_y: float = safe_rect.y / abs(dir.y) if dir.y != 0.0 else INF
		var s: float = min(s_x, s_y)
		var edge_pos: Vector2 = half + dir * s
		
		btn.position = edge_pos - btn.size * 0.5
		
		# Show/hide if direction has no meaningful component
		btn.visible = s > 0.0


func _on_teleport_marker_pressed(index: int) -> void:
	"""Handle click on a screen-edge marker — teleport killer to that target."""
	if index < 0 or index >= _teleport_marker_targets.size():
		return
	var target_pos: Vector2 = _teleport_marker_targets[index]
	
	# Teleport the killer (player) to this position
	if is_instance_valid(_player) and _player.has_method("teleport_to_position"):
		_player.teleport_to_position(target_pos)
	elif is_instance_valid(_killer_bot) and _killer_bot.has_method("teleport_to_position"):
		_killer_bot.teleport_to_position(target_pos)
	
	_close_teleport_minimap()


func _get_random_map_position() -> Vector2:
	"""Get a random position on the map (for decoy circles)."""
	var map_size: Vector2 = Vector2(512, 512)
	if _map_manager and _map_manager.blueprint_size:
		map_size = Vector2(_map_manager.blueprint_size)
	# Stay away from edges
	var edge_margin: float = 100.0
	var rx: float = randf_range(edge_margin, map_size.x - edge_margin)
	var ry: float = randf_range(edge_margin, map_size.y - edge_margin)
	# Ensure at least 200px from any survivor so decoy is a genuine choice
	var min_dist_from_survivors: float = 200.0
	var survivors: Array[Node] = get_tree().get_nodes_in_group("survivors")
	for s: Node in survivors:
		if is_instance_valid(s):
			var dist: float = Vector2(rx, ry).distance_to(s.global_position)
			if dist < min_dist_from_survivors:
				var dir: Vector2 = (Vector2(rx, ry) - s.global_position).normalized()
				rx = s.global_position.x + dir.x * min_dist_from_survivors
				ry = s.global_position.y + dir.y * min_dist_from_survivors
	return Vector2(rx, ry)


func _close_teleport_minimap() -> void:
	"""Remove all teleport overlay, markers, and cleanup."""
	_teleport_markers_active = false
	_teleport_marker_buttons.clear()
	_teleport_marker_targets.clear()
	for c: Node in _teleport_circles:
		if is_instance_valid(c):
			c.queue_free()
	_teleport_circles.clear()


# ---------- TELEPORT SOUND + INDICATOR ----------

const TELEPORT_SOUND_PATH: String = "res://The Darkness Of The Grasslands assets/Sound/Sfx/Violentgrass_Teleportation.wav"

func _on_player_teleported(new_pos: Vector2) -> void:
	"""Called when Violentgrass (player or AI bot) completes a teleport.
	Plays a positional sound at the destination and shows an arrow indicator
	on survivor HUDs pointing toward the teleport location."""
	_play_teleport_sound_at(new_pos)
	_close_teleport_minimap()
	_show_teleport_indicator(new_pos)


func _play_teleport_sound_at(pos: Vector2) -> void:
	"""Spawn a temporary positional audio player at the teleport position."""
	var player := AudioStreamPlayer2D.new()
	player.stream = load(TELEPORT_SOUND_PATH)
	player.global_position = pos
	player.max_distance = 800.0  # Audible to nearby survivors
	player.volume_db = 0.0
	add_child(player)
	player.play()
	# Auto-cleanup after sound finishes playing
	get_tree().create_timer(2.5).timeout.connect(func ():
		if is_instance_valid(player):
			player.queue_free()
	)


func _show_teleport_indicator(teleport_pos: Vector2) -> void:
	"""Show a directional arrow on the player's HUD pointing to the teleport location.
	Only shows when the player is a survivor (not the killer who teleported).
	The arrow disappears after 3 seconds."""
	# Don't show if the player IS the killer
	if _character_name == "Violentgrass" or GameState.is_killer:
		return
	
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	
	# Get relative direction from player to teleport position
	var dir: Vector2 = (teleport_pos - _player.global_position).normalized() if is_instance_valid(_player) else Vector2.RIGHT
	
	# Create the indicator — a Label with a transparent arrow character
	var arrow_label := Label.new()
	arrow_label.name = "TeleportIndicator"
	arrow_label.text = "▶"
	arrow_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 0.95))
	arrow_label.add_theme_font_size_override("font_size", 32)
	arrow_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	arrow_label.add_theme_constant_override("outline_size", 3)
	arrow_label.size = Vector2(40, 40)
	arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Place at screen edge
	var margin: float = 40.0
	var edge_x: float = viewport_size.x * 0.5 + dir.x * (viewport_size.x * 0.5 - margin)
	var edge_y: float = viewport_size.y * 0.5 + dir.y * (viewport_size.y * 0.5 - margin)
	edge_x = clamp(edge_x, margin, viewport_size.x - margin)
	edge_y = clamp(edge_y, margin, viewport_size.y - margin)
	
	arrow_label.position = Vector2(edge_x - 20, edge_y - 20)
	
	# Rotate the arrow to point toward the teleport location
	var angle: float = atan2(dir.y, dir.x)
	arrow_label.pivot_offset = Vector2(20, 20)
	arrow_label.rotation = angle
	
	# Add to HUD
	$HUD.add_child(arrow_label)
	
	# Add a secondary ring pulse effect below the arrow
	var ring := ColorRect.new()
	ring.name = "TeleportIndicatorRing"
	ring.size = Vector2(6, 6)
	ring.position = arrow_label.position + Vector2(17, 17)
	ring.color = Color(1, 0.2, 0.2, 0.6)
	$HUD.add_child(ring)
	
	# Animate ring pulse
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "size", Vector2(20, 20), 0.5)
	tween.tween_property(ring, "modulate:a", 0.0, 0.5)
	tween.tween_property(arrow_label, "modulate:a", 0.0, 0.5).set_delay(2.5)
	
	# Remove both after 3 seconds
	get_tree().create_timer(3.0).timeout.connect(func ():
		if is_instance_valid(arrow_label):
			arrow_label.queue_free()
		if is_instance_valid(ring):
			ring.queue_free()
	)


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

func _check_kill_timer_bonus() -> void:
	"""Detect when the killer bot eliminates a survivor and add 30s to timer."""
	if not is_instance_valid(_killer_bot):
		return
	# Trick: track a count we can observe. In local mode, the bot "kills" by
	# proximity — the player dies when the killer touches them (via _on_player_died).
	# The +30s is actually added there. See _on_player_died() for implementation.

func add_timer_bonus(seconds: float) -> void:
	"""Add time to the match timer with animated red count-up."""
	_bonus_target = min(_time_remaining + seconds, MATCH_DURATION)
	print("GameMap: Timer +", seconds, "s (target ", _bonus_target, "s)")


# ---------- KILLER ELIMINATION TRACKING ----------

func _on_killer_eliminated(_player_name: String) -> void:
	"""Called when killer eliminates a survivor (from network or local)."""
	# +5s timer bonus (animated count-up) — was 30.0 originally
	add_timer_bonus(5.0)


func _on_bot_hp_changed(current_hp: float, _max_hp: float, bot: Node2D) -> void:
	"""Track AI survivor bot HP and trigger elimination when HP reaches 0."""
	if current_hp > 0.0:
		return
	if not is_instance_valid(bot):
		return
	if not _survivor_bots.has(bot):
		return
	
	# Mark bot as eliminated
	_alive_survivor_bot_count -= 1
	_survivor_bots.erase(bot)
	
	# Grey out the bot
	bot.modulate = Color(0.4, 0.4, 0.4, 0.5)
	bot.set_physics_process(false)
	
	print("GameMap: Survivor bot eliminated — %d bot(s) remaining" % _alive_survivor_bot_count)
	_on_killer_eliminated("SurvivorBot")
	
	# Check if all survivors (human + bots) are eliminated
	_check_all_survivors_eliminated()


func _check_all_survivors_eliminated() -> void:
	"""End the match when all survivors (human + AI bots) are eliminated."""
	if _alive_survivor_bot_count > 0:
		return
	# Also check if human player is dead
	var player_hp: float = _player.get("current_hp") if is_instance_valid(_player) and "current_hp" in _player else 0.0
	if player_hp <= 0.0:
		print("GameMap: All survivors eliminated — ending match")
		match_timer.stop()
		match_ended.emit()
		_end_match()


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
	"""Open this zone's pre-assigned puzzle minigame."""
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
	# Use the pre-assigned puzzle type stored on this zone
	var forced_type: int = PuzzleManager.PuzzleType.RHYTHM
	var zone_type: String = area.get_meta("puzzle_type", "Rhythm")
	match zone_type:
		"Memory": forced_type = PuzzleManager.PuzzleType.MEMORY
		"Wiring": forced_type = PuzzleManager.PuzzleType.WIRING
		"Rhythm": forced_type = PuzzleManager.PuzzleType.RHYTHM
	puz_scene.open_puzzle(area, _player, 1, forced_type)
	puz_scene.puzzle_completed.connect(_on_puzzle_solved)
	puz_scene.puzzle_closed.connect(_on_puzzle_closed.bind(puz_scene))


func _on_puzzle_solved(area: Area2D, puzzle_level: int = 1) -> void:
	"""Handle puzzle solved — rewards + timer deduction (3.25s per puzzle level)."""
	var area_name: String = area.name
	if not area_name in _solved_puzzles:
		_solved_puzzles.append(area_name)
	
	# Rewards: +$5 and +1 ring per puzzle level completed
	var gs = get_node("/root/GameState")
	var rings_per_level: int = 1
	var money_per_level: int = 5
	if gs != null:
		gs.add_money(money_per_level)
		var username: String = gs.logged_in_username
		if username != "":
			var current_rings: int = gs.get_player_rings(username)
			gs.set_player_rings(username, current_rings + rings_per_level)
		print("GameMap: Puzzle reward — +$", money_per_level, ", +", rings_per_level, " ring (level ", puzzle_level, ")")
	
	# Decrease match timer by 3.25 seconds per puzzle level (flash red)
	var deduction: float = 3.25 * puzzle_level
	_time_remaining = max(0.0, _time_remaining - deduction)
	_timer_flash_red = 1.0
	_update_timer_label()
	
	# Show success text
	var prompt: Label = area.get_node_or_null("InteractPrompt")
	if prompt:
		prompt.text = "✓ Solved!"
	
	# Visual feedback: tint the area marker green
	if area.has_node("ColorRect"):
		var rect: ColorRect = area.get_node("ColorRect")
		rect.color = Color(0.2, 0.8, 0.2, 0.5)
	
	print("GameMap: Puzzle solved at ", area.position)


func _on_bot_solved_puzzle(_area_name: String, area_ref: Area2D) -> void:
	"""Handle a survivor bot solving a puzzle (default level 1 deduction)."""
	if not is_instance_valid(area_ref):
		return
	# Bot solves at level 1 by default; level tracking could be enhanced later
	_on_puzzle_solved(area_ref, 1)


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


# ---------- MATCH ENDING SCREEN (timer ≤ 30s) ----------

func _create_match_ending_screen() -> void:
	"""Create the full-screen ending image + top overlay when timer ≤ 30s."""
	if _ending_screen_created:
		return
	_ending_screen_created = true
	_ending_bg_alpha = 0.0
	_ending_shake_timer = 0.0
	
	var hud: CanvasLayer = $HUD
	
	# Load textures
	var bg_tex: Texture2D = load("res://The Darkness Of The Grasslands assets/UI/Match/Violentgrass_MATCH_ENDING_SCREEN.png")
	var overlay_tex: Texture2D = load("res://The Darkness Of The Grasslands assets/UI/Match/Violentgrass_MATCH_ENDING_SCREEN_TOP_OVERLAY.png")
	
	# Background image — full screen, fades in slowly
	var bg := TextureRect.new()
	bg.name = "EndingScreenBg"
	bg.texture = bg_tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.position = Vector2(0, 0)
	bg.size = get_viewport().get_visible_rect().size
	bg.modulate = Color(1, 1, 1, 0.0)  # Start transparent
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bg)
	_ending_screen_bg = bg
	
	# Top overlay — shakes aggressively each second
	var top := TextureRect.new()
	top.name = "EndingScreenOverlay"
	top.texture = overlay_tex
	top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	top.position = Vector2(0, 0)
	top.size = get_viewport().get_visible_rect().size
	top.modulate = Color(1, 1, 1, 0.0)  # Start transparent
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top)
	_ending_screen_overlay = top
	
	# Two red UI flash elements — created now but hidden until 18s
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	
	var red_left := ColorRect.new()
	red_left.name = "EndingRedLeft"
	red_left.color = Color(1, 0, 0, 0.85)
	red_left.position = Vector2(0, 0)
	red_left.size = Vector2(view_size.x * 0.5, view_size.y)
	red_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	red_left.visible = false
	hud.add_child(red_left)
	_ending_red_left = red_left
	
	var red_right := ColorRect.new()
	red_right.name = "EndingRedRight"
	red_right.color = Color(1, 0, 0, 0.85)
	red_right.position = Vector2(view_size.x * 0.5, 0)
	red_right.size = Vector2(view_size.x * 0.5, view_size.y)
	red_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	red_right.visible = false
	hud.add_child(red_right)
	_ending_red_right = red_right


func _update_match_ending_screen(delta: float) -> void:
	"""Update the ending screen: fade-in, shake intensity scales with time left, red UI flash at 18s."""
	if not _ending_screen_created:
		return
	if not is_instance_valid(_ending_screen_bg) or not is_instance_valid(_ending_screen_overlay):
		return
	
	# Slowly fade in the background (alpha 0 → 0.6 over 10 seconds)
	_ending_bg_alpha = min(_ending_bg_alpha + delta * 0.06, 0.6)
	_ending_screen_bg.modulate = Color(1, 1, 1, _ending_bg_alpha)
	
	# Top overlay fades in slightly faster
	var overlay_alpha: float = min(_ending_bg_alpha * 1.5, 0.85)
	_ending_screen_overlay.modulate = Color(1, 1, 1, overlay_alpha)
	
	# Shake intensity scales with time remaining
	# 31s → mild (±8px, 1.0s interval), 18s → violent (±35px, 0.25s), 0s → extreme (±50px, 0.15s)
	var time_progress: float = 1.0 - (_time_remaining / 31.0)  # 0 at 31s, 1 at 0s
	time_progress = clamp(time_progress, 0.0, 1.0)
	
	var shake_amplitude: float = 8.0 + time_progress * 42.0  # 8px at 31s, 50px at 0s
	var shake_interval: float = 1.0 - time_progress * 0.85  # 1.0s at 31s, 0.15s at 0s
	shake_interval = max(shake_interval, 0.15)
	
	_ending_shake_timer += delta
	if _ending_shake_timer >= shake_interval:
		_ending_shake_timer -= shake_interval
		var shake_x: float = randf_range(-shake_amplitude, shake_amplitude)
		var shake_y: float = randf_range(-shake_amplitude * 0.75, shake_amplitude * 0.75)
		if is_instance_valid(_ending_screen_overlay):
			_ending_screen_overlay.position = Vector2(shake_x, shake_y)
	
	# Red UI flash — activate at 18 seconds remaining
	if _time_remaining <= 18.0 and not _ending_red_active:
		_ending_red_active = true
		_ending_red_flash_timer = 0.0
		_ending_red_show_left = true
	
	if _ending_red_active:
		# 150 BPM = 400ms per beat = 200ms alternating left→right
		# Speed up slightly as time decreases (max 180 BPM = 333ms cycle)
		var bpm: float = 150.0 + (18.0 - _time_remaining) * (30.0 / 18.0)  # 150 at 18s, 180 at 0s
		bpm = clamp(bpm, 150.0, 180.0)
		var half_cycle: float = 60.0 / bpm / 2.0  # Time per side (200ms at 150 BPM)
		
		_ending_red_flash_timer += delta
		if _ending_red_flash_timer >= half_cycle:
			_ending_red_flash_timer -= half_cycle
			_ending_red_show_left = not _ending_red_show_left
			if is_instance_valid(_ending_red_left):
				_ending_red_left.visible = _ending_red_show_left
			if is_instance_valid(_ending_red_right):
				_ending_red_right.visible = not _ending_red_show_left


# ---------- DAMAGE VIGNETTE ----------

func _check_damage_vignette() -> void:
	"""Detect player HP changes to trigger vignette and track damage.
	Uses _last_damage_time to avoid duplicating _on_player_hp_changed()."""
	if not is_instance_valid(_player):
		return
	if not "current_hp" in _player:
		return
	var hp: float = _player.get("current_hp")
	# Don't track _last_hp here — that's owned by _on_player_hp_changed().
	# Only trigger the visual vignette effect.
	if _last_hp >= 0 and hp < _last_hp:
		var dmg: float = _last_hp - hp
		_total_damage_taken += dmg
		_trigger_vignette()
	_last_hp = hp


func _update_timer_label() -> void:
	var total_seconds: int = int(_time_remaining)
	var minutes: int = int(total_seconds / 60.0)
	var seconds: int = total_seconds % 60
	var txt: String = "%02d:%02d" % [minutes, seconds]
	timer_label.text = txt
	if is_instance_valid(_bitmap_timer):
		_bitmap_timer.label_text = txt
	
	# Flash red when timer is being decreased (puzzle deduction)
	if _timer_flash_red > 0.0:
		var red_alpha: float = min(_timer_flash_red * 2.0, 1.0)
		timer_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, red_alpha))
		if is_instance_valid(_bitmap_timer):
			_bitmap_timer.font_color = Color(1.0, 0.2, 0.2, red_alpha)
	else:
		timer_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		if is_instance_valid(_bitmap_timer):
			_bitmap_timer.font_color = Color(1, 1, 1, 1)


# ---------- MATCH STATS ----------

# ---------- CHAT SYSTEM ----------

func _setup_chat() -> void:
	"""Create ChatLayer instance and connect its signals."""
	var chat := ChatLayer.new()
	chat.name = "ChatLayer"
	chat.chat_sent.connect(_on_map_chat_sent)
	chat.chat_opened.connect(_on_chat_opened)
	chat.chat_closed.connect(_on_chat_closed)
	add_child(chat)
	
	# Listen for incoming chat messages from the server
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if is_instance_valid(nm) and nm.has_signal("chat_message_received"):
		if not nm.chat_message_received.is_connected(_on_server_chat):
			nm.chat_message_received.connect(_on_server_chat)


func _setup_admin_panel() -> void:
	"""Create AdminPanel instance for in-game admin controls."""
	var panel := AdminPanel.new()
	panel.name = "AdminPanel"
	add_child(panel)
	panel.hide()  # Start hidden — toggled via "G Gui"


func _apply_saved_settings() -> void:
	"""Apply loaded settings from GameState to the game map."""
	# Load audio bus volumes from save (already applied by SaveManager.autoload at login)
	# This ensures proper audio setup in the game map
	var sm = get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("load_player_data") and GameState.logged_in_username != "":
		var data: Dictionary = sm.load_player_data(GameState.logged_in_username)
		if not data.is_empty():
			# Restore audio bus volumes
			for bus_name in ["Master", "Music", "SFX"]:
				var key: String = "bus_vol_" + bus_name
				if data.has(key):
					var bus_idx: int = AudioServer.get_bus_index(bus_name)
					if bus_idx >= 0:
						AudioServer.set_bus_volume_db(bus_idx, data[key])
	
	# Apply epilepsy safe mode (reduce flash effects)
	if GameState.epilepsy_safe_mode:
		# Red flash intensity is already controlled by _timer_flash_red
		# Just ensure the flash alpha is reduced
		pass
	
	print("GameMap: Applied saved settings")


func _on_chat_opened() -> void:
	"""Disable ALL player processing (movement + abilities) when chat is open."""
	if is_instance_valid(_player):
		_player.set_physics_process(false)
		_player.process_mode = Node.PROCESS_MODE_DISABLED


func _on_server_chat(sender: String, text: String) -> void:
	"""Display a chat message received from the server relay."""
	var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
	if chat_layer:
		if sender == "SERVER":
			chat_layer.add_system_message(text)
		else:
			chat_layer.add_message(sender, text)


func _on_chat_closed() -> void:
	"""Re-enable ALL player processing when chat is closed."""
	if is_instance_valid(_player):
		_player.set_physics_process(true)
		_player.process_mode = Node.PROCESS_MODE_INHERIT


func _on_map_chat_sent(text: String, is_admin: bool) -> void:
	"""Handle a chat message sent from ChatLayer in game map."""
	var trimmed: String = text.strip_edges().to_lower()
	if trimmed == "g" or trimmed == "g help":
		_show_map_admin_help()
		return
	
	# "G Gui" — toggle admin GUI panel (works regardless of server status)
	if trimmed == "g gui":
		var panel: AdminPanel = get_node_or_null("AdminPanel")
		if panel:
			panel.toggle_gui()
		return
	
	if is_admin and GameState.connected_to_server:
		var nm: Node = get_node("/root/NetworkManager")
		if is_instance_valid(nm) and nm.has_method("send_admin_command"):
			nm.send_admin_command(text.trim_prefix("G "))
		return
	
	if GameState.connected_to_server:
		var nm: Node = get_node("/root/NetworkManager")
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
	chat_layer.add_system_message("G Gui - Toggle admin GUI panel")
	chat_layer.add_system_message("=====================")


func _determine_killer_by_rings() -> bool:
	"""Ring-based killer selection: highest ring count gets to be killer.
	If multiple players tied or local player isn't top, picks based on next-in-line.
	If nobody has rings, picks randomly."""
	var gs = get_node("/root/GameState")
	if gs == null:
		return false
	
	# Get players sorted by rings descending
	var sorted_players: Array[String] = gs.get_players_sorted_by_rings()
	
	# If no other players have ring data, check for tied/highest
	var local_username: String = gs.logged_in_username
	if local_username.is_empty():
		return false
	
	var local_rings: int = gs.get_player_rings(local_username)
	
	# If this player has the most rings, they're the killer
	if sorted_players.is_empty() or sorted_players[0] == local_username:
		# Check if ANY other player has equal rings (tie)
		var tied_players: Array[String] = []
		for pname: String in sorted_players:
			if gs.get_player_rings(pname) >= local_rings:
				tied_players.append(pname)
		
		if tied_players.size() <= 1:
			# This player is uniquely at the top
			print("GameMap: Ring-based killer selection — %s (%d rings)" % [local_username, local_rings])
			return true
		else:
			# Tie — pick next person in line
			var my_index: int = tied_players.find(local_username)
			if my_index >= 0 and my_index + 1 < tied_players.size():
				# Next tied player is chosen instead
				print("GameMap: Ring tie — %s passed to %s" % [local_username, tied_players[my_index + 1]])
				return false
			# Default to this player
			return true
	
	# Someone else has more rings
	print("GameMap: Ring-based killer selection — %s is not top ring holder" % local_username)
	return false


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
	
	# Clean up multiplayer sync
	if _multiplayer_sync:
		_multiplayer_sync.queue_free()
		_multiplayer_sync = null
	
	# Transition to lobby with fade effect
	get_tree().paused = false
	SceneFader.go("res://scenes/lobby.tscn", "Match Complete — Loading Results...")
	print("GameMap: Match ended — transitioning to lobby for analysis")


# ═══════════════ MULTIPLAYER INTEGRATION ═══════════════

func _initialize_multiplayer() -> void:
	"""Set up MultiplayerGameSync if connected to the dedicated server."""
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if not nm or not nm.connected:
		return  # Offline mode — bots handle gameplay
	
	_multiplayer_sync = MultiplayerGameSync.new()
	_multiplayer_sync.name = "MultiplayerSync"
	add_child(_multiplayer_sync)
	_multiplayer_sync.match_started.connect(_on_multiplayer_match_started)
	_multiplayer_sync.player_disconnected.connect(_on_multiplayer_player_left)
	
	# Override role from server
	if _multiplayer_sync.is_killer():
		GameState.is_killer = true
		_character_name = "Violentgrass"
	
	print("GameMap: Multiplayer mode active — role: ", _multiplayer_sync.get_player_role())


func _on_multiplayer_match_started(role: String, player_list: Array) -> void:
	"""Handle match start from server."""
	print("GameMap: Multiplayer match started — Role: ", role, " | Players: ", player_list.size())


func _on_multiplayer_player_left(name: String) -> void:
	"""Handle player disconnection during match."""
	var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
	if chat_layer:
		chat_layer.add_system_message(name + " disconnected.")
	print("GameMap: Player left during match — ", name)


func _sync_multiplayer_position(pos: Vector2) -> void:
	"""Send position update to server for multiplayer sync."""
	if _multiplayer_sync:
		_multiplayer_sync.send_position_update(pos)


func _sync_multiplayer_hp(hp: float, max_hp: float) -> void:
	"""Send HP update to server for multiplayer sync."""
	if _multiplayer_sync:
		_multiplayer_sync.send_hp_update(hp, max_hp)


func _sync_multiplayer_ability(ability: String, pos: Vector2 = Vector2.ZERO) -> void:
	"""Send ability usage to server for multiplayer sync."""
	if _multiplayer_sync:
		_multiplayer_sync.send_ability_used(ability, pos)


# ═══════════════ AI DIFFICULTY SCALING ═══════════════

func _attach_ai_difficulty() -> void:
	"""Attach dynamic difficulty to the AI killer bot."""
	if not is_instance_valid(_killer_bot):
		return
	_ai_difficulty = AIDifficultyController.new()
	_ai_difficulty.name = "AIDifficulty"
	_killer_bot.add_child(_ai_difficulty)
	_ai_difficulty.initialize(_killer_bot)
	print("GameMap: AI difficulty controller attached")


func _update_ai_difficulty() -> void:
	"""Update AI difficulty based on current match state."""
	if not is_instance_valid(_ai_difficulty) or not is_instance_valid(_killer_bot):
		return
	var target_hp: float = 100.0
	if is_instance_valid(_player) and "current_hp" in _player:
		target_hp = _player.current_hp
	
	var survivor_count: int = 0
	for bot in _survivor_bots:
		if is_instance_valid(bot):
			survivor_count += 1
	if _character_name != "Violentgrass" and is_instance_valid(_player):
		survivor_count += 1
	
	_ai_difficulty.update_difficulty(_time_remaining, survivor_count, target_hp)
