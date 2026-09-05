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
const TEST_KILLER_SCENE: PackedScene = preload("res://scenes/test_killer.tscn")
const AI_BOT_SCRIPT: Script = preload("res://scripts/characters/ai_bot_controller.gd")
const AI_SURVIVOR_BOT_SCRIPT: Script = preload("res://scripts/characters/ai_survivor_bot_controller.gd")
const AI_TEST_KILLER_SCRIPT: Script = preload("res://scripts/characters/ai_test_killer_controller.gd")
const LMS_AURA_SHADER: Shader = preload("res://shaders/player_aura.gdshader")

# Chase music — 4-layer system: Layer1, Layer2, Layer3, Chase
## Settings: configurable folder names for killer + survivor chase themes (auto-searches)
@export var killer_chase_folder: String = "Violentgrass"   # Folder under Killer Chase Themes/ for killer player
@export var survivor_chase_folder: String = "Violentgrass"  # Folder under Killer Chase Themes/ for survivor player (Monster Greengrass theme is unused)
const CHASE_BASE_DIR: String = "res://The Darkness Of The Grasslands assets/Music/Killer Chase Themes/"
const CHASE_LAYER_FILES: Array[String] = ["Layer1.wav", "Layer2.wav", "Layer3.wav", "Chase.wav"]
# Killer chase: only Chase layer (no build-up) — distance in pixels
# EXIT must exceed the survivor bots' flee_range (500px) so an active chase
# doesn't cut off mid-chase when the (fleeing) survivor drifts past the enter
# distance. Chase stays on until the killer is genuinely far (~700px).
const KILLER_CHASE_ENTER: Array[float] = [0.0, 0.0, 0.0, 250.0]
const KILLER_CHASE_EXIT: Array[float]  = [0.0, 0.0, 0.0, 700.0]
# Survivor chase: all 4 layers with build-up
const SURVIVOR_CHASE_ENTER: Array[float] = [500.0, 300.0, 150.0, 80.0]
# Exit is just past each enter step so the chase MUTES as soon as the killer
# moves away (no endless lingering build-up once the threat is far).
const SURVIVOR_CHASE_EXIT: Array[float]  = [520.0, 330.0, 180.0, 110.0]
const CHASE_LAYER_VOLUME: Array[float] = [-6.0, -3.0, -1.0, 0.0]     # Volume per layer (Layer1 audible, Chase loud)
const CHASE_VOL_FADE_MS: float = 0.3  # Crossfade time (seconds)
const CHASE_MAP_DUCK_DB: float = -80.0  # Background music FULLY muted while chase is active (restore only when killer is far)
# Killer (Violentgrass) build-up: each build-up layer plays for this many seconds
# before advancing to the next (Layer1 → Layer2 → Layer3 → Chase). Matches the
# ~9.6s duration of the Layer1/2/3 WAV files.
const CHASE_BUILD_STEP_DURATION: float = 9.6

# ── LMS (Last Man Standing) finale ──
# When it's down to 1 killer + 1 survivor, play the special LMS music and glue
# the 2-frame ViolentBells VFX to the camera screen.
const LMS_MUSIC_PATH: String = "res://The Darkness Of The Grasslands assets/Music/Match/SPECIAL LMSES/Greengrass_VS_Violentgrass_Violent_bells_LMS.wav"
const LMS_VFX_FRAME_1: String = "res://The Darkness Of The Grasslands assets/VFX/ViolentbellsVFX-[ANIM]/FRAME1.png"
const LMS_VFX_FRAME_2: String = "res://The Darkness Of The Grasslands assets/VFX/ViolentbellsVFX-[ANIM]/FRAME2.png"
const LMS_VFX_FPS: float = 4.0      # 2-frame alternation speed (slower, less distracting)
const LMS_VFX_ALPHA: float = 0.55   # Max opacity of the VFX overlay (more transparent = easier to see through)
const LMS_VFX_FADE_DISTANCE: float = 300.0  # Killer within this many px of the survivor → VFX fades out so the final fight is visible
const LMS_VFX_FADE_SPEED: float = 3.0       # How fast the VFX alpha adjusts (higher = snappier fade)
const LMS_KILL_ZOOM_IN: float = 0.5  # Tight zoom during kill punch-in (smaller = closer)
const LMS_KILL_ZOOM_HOLD: float = 0.6  # Seconds spent tight before pulling back out
const LMS_REVEAL_DURATION: float = 4.0  # Seconds the survivor-reveal arrow stays on screen
const LMS_MUSIC_DURATION: float = 100.0  # Fallback countdown length (actual WAV is ~99.7s)
# LMS timer-transition: when LMS starts the match clock animates (up or down) to
# the LMS song length with a dark-red screen while it runs.
const LMS_TRANSITION_TICK_RATE: float = 0.03   # seconds between each 1s timer step (~33s/sec)
const LMS_TRANSITION_ALPHA: float = 0.6        # dark-red overlay strength during the animation
const LMS_TRANSITION_FADE_OUT: float = 1.2     # seconds to fade the red away after the animation
const ROUND_END_GIFT_RING: int = 1    # +1 gift ring added to persistent player_rings each round
# ── LMS end-of-song camera heartbeat (keyed to MUSIC playback, not match clock) ──
# While the LMS song still has LMS_HEARTBEAT_FROM seconds left to play, the camera
# does a gentle screen zoom in/out pulse at a constant 200 BPM. Amplitude is
# small on purpose so players don't get motion sick.
const LMS_HEARTBEAT_FROM: float = 93.0  # Song has 1m33s left → heartbeat begins
const LMS_HEARTBEAT_BPM_START: float = 200.0
const LMS_HEARTBEAT_BPM_END: float = 200.0  # Constant 200 BPM (user requested 200, not 150-175)
const LMS_HEARTBEAT_AMOUNT: float = 0.06  # Zoom difference per heartbeat beat (subtle)
# ── LMS heartbeat circular red pulse overlay ──
# A red vignette that throbs in sync with the camera heartbeat (same beat phase).
const LMS_HEARTBEAT_PULSE_SHADER: String = "res://shaders/lms_heartbeat_pulse.gdshader"
const LMS_HEARTBEAT_PULSE_MAX: float = 0.55   # Peak red fade opacity during a beat
const LMS_HEARTBEAT_PULSE_FADE: float = 8.0   # How fast the red lerps toward the current beat level
# ── LMS music pinch (zoomin at 26.5s, zoomout at 27s of the MUSIC) ──
const LMS_PINCH_IN_AT: float = 26.5   # Music play position (s) → zoom in a little
const LMS_PINCH_OUT_AT: float = 27.0  # Music play position (s) → zoom back out
const LMS_PINCH_ZOOM_IN_MULT: float = 1.12  # default_zoom / mult = zoom-in level ("a little")

var _time_remaining: float = MATCH_DURATION
var _map_manager: MapManager = null
var _player: Node2D = null
var _killer_bot: Node2D = null
var _killer_character_name: String = "Violentgrass"  # Which killer the AI bot is
var _aura_nodes: Dictionary = {}  # character Node → aura AnimatedSprite2D (for cleanup)
# True once the killer intro finishes and the fight is live. Guards the per-frame
# "everyone dead" round-end check from firing before anyone has even spawned.
var _match_live: bool = false
# True once the AI killer bot is eliminated (survivor mode). Lets the per-frame
# check end the round even if the bot's hp_changed signal is somehow missed.
var _killer_bot_eliminated: bool = false
var _killer_sweep_timer: float = 0.0  # Cooldown for single-killer enforcement sweep
var _survivor_bots: Array[Node2D] = []
var _alive_survivor_bot_count: int = 0
# Cached list of all nodes in the "survivors" group (human + bots).
# Refreshed on spawn/elimination to avoid a group query every frame in _update_chase_music.
var _cached_survivors: Array[Node] = []
var _chase_layers_enabled: Array[bool] = [false, false, false, false]  # Active state per layer
var _chase_players: Array[AudioStreamPlayer] = []
var _chase_active_layer: int = -1  # Highest active layer index
# Killer (Violentgrass) time-based build-up state
var _chase_build_step: int = 0     # 0=Layer1, 1=Layer2, 2=Layer3, 3=Chase
var _chase_build_elapsed: float = 0.0  # Seconds spent on the current build-up layer
# One volume-crossfade tween per chase player. Killing the previous tween before
# starting a new one prevents old ramps from fighting — which was making the
# layers stack (multiple layers audible at once).
var _chase_volume_tweens: Array[Tween] = []
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

# Teleport red-glitch FX state (full-screen red glitch + zoom-in, slow zoom-out)
var _teleport_fx_layer: CanvasLayer = null
var _teleport_fx_rect: TextureRect = null
var _teleport_fx_mat: ShaderMaterial = null
var _teleport_fx_timer: float = 0.0
var _teleport_fx_active: bool = false
var _teleport_fx_zoom_out_started: bool = false
var _teleport_fx_zoom_out_started_at: float = 0.0
const TELEPORT_FX_INTENSITY_IN: float = 0.9    # Fully red/glitchy peak at start
const TELEPORT_FX_DURATION: float = 1.8        # Total overlay lifetime (seconds)
const TELEPORT_FX_ZOOM_IN: float = 2.2         # Zoom level during teleport (dramatic close-up)
const TELEPORT_FX_ZOOM_OUT_MS: float = 1800.0  # Slow zoom-out duration after landing (ms)
const TELEPORT_FX_ZOOM_IN_HOLD_S: float = 0.35 # Hold the zoomed-in red state before slow reveal

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

# Guard to prevent double lobby redirect
var _round_ended: bool = false

# LMS (Last Man Standing) finale state
var _lms_active: bool = false          # True once 1 killer + 1 survivor remain
# LMS timer-transition state: while _lms_transition_active the match clock
# animates toward _lms_transition_target with a dark-red screen.
var _lms_transition_active: bool = false
var _lms_transition_target: float = 0.0
var _lms_transition_timer: float = 0.0
var _lms_transition_overlay: ColorRect = null
# True when the whole match is a 1v1 (1 killer + 1 survivor, i.e. 2 combatants).
# In that case the map music never plays — the intro cutscene is the "loading"
# beat and the LMS finale takes over as the sole score.
var _is_1v1: bool = false
# True when the round ended with the KILLER winning (all survivors eliminated).
# When true, the match-end shows Violentgrass's killer outro frozen on its last
# frame with the analysis overlaid before returning to the lobby.
var _killer_won: bool = false
# Analysis overlay shown over the frozen killer-outro frame (continue → lobby).
var _killer_win_analysis_layer: CanvasLayer = null
var _lms_music_player: AudioStreamPlayer = null
var _lms_vfx_layer: CanvasLayer = null
var _lms_vfx_rect: TextureRect = null
var _lms_vfx_timer: float = 0.0        # Frame-alternation accumulator
var _lms_vfx_show_frame2: bool = false
var _lms_alpha_current: float = 0.0    # Current VFX overlay opacity (lerped)
var _lms_alpha_target: float = 0.0     # Desired VFX opacity this frame
# ── LMS end-of-song camera heartbeat / pinch state ──
var _lms_heartbeat_phase: float = 0.0  # Accumulator for BPM-synced zoom pulse
var _lms_heartbeat_active: bool = false  # True once 93s-remaining heartbeat enters
var _lms_pinch_done: bool = false      # One-shot 27s→26.5s zoom pinch already fired
# ── LMS heartbeat circular red pulse overlay ──
var _lms_pulse_layer: CanvasLayer = null  # Full-screen overlay for the red throb
var _lms_pulse_rect: ColorRect = null     # The rect whose shader draws the red fade
var _lms_pulse_mat: ShaderMaterial = null # Shared material (so intensity is updated live)
var _lms_pulse_current: float = 0.0       # Current red intensity (lerped toward target)

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

# Timer pause state (puzzle-complete / kill events): when > 0 the match timer is
# paused while a time adjustment is applied, then resumes counting down.
var _timer_pause_remaining: float = 0.0

# Multiplayer integration
var _multiplayer_sync: Node = null

# AI difficulty controller
var _ai_difficulty: AIDifficultyController = null
# The AI killer starts at "Normal" difficulty (0.28 floor), not Easy.
const AI_DIFFICULTY_START: float = 0.28


func _ready() -> void:
	# Ensure input actions are registered
	_setup_input_actions()
	
	# Background music is set up AFTER spawn (we need to know the combatant
	# count to decide whether a 1v1 should skip the map music entirely).
	
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
	
	# Build navigation mesh for AI pathfinding
	_map_manager.build_navigation(self)
	
	# Add map border walls
	_add_map_border_walls()
	
	# Place Flower pickups (heal 90 HP)
	_spawn_flower_items()
	
	# Place marker nodes for debugging/visualization
	_place_markers()
	
	# Start match timer
	match_timer.start(1.0)
	_time_remaining = MATCH_DURATION
	_round_ended = false
	_killer_won = false
	_update_timer_label()

	# Let the lobby know a match is now in progress (spectate sync).
	GameState.match_in_progress = true
	GameState.game_phase = "ROUND_ACTIVE"
	
	# Determine if this player should be the killer based on rings
	var gs = get_node("/root/GameState")
	var should_be_killer: bool = false
	if gs != null:
		should_be_killer = _determine_killer_by_rings()
		gs.is_killer = should_be_killer
	
	# Spawn the player character (also spawns killer bot if survivor)
	spawn_player(should_be_killer)
	
	# Figure out how many combatants are in this match. A 1v1 (exactly a killer
	# + one survivor = 2 people) NEVER plays the map music — the killer intro
	# cutscene acts as the "loading" beat, then the LMS finale starts straight
	# away so the LMS track is the sole score. Bigger matches keep the map music.
	_is_1v1 = _character_name == "Greengrass" or _alive_survivor_bot_count <= 1
	if _is_1v1:
		print("GameMap: 1v1 (2 combatants) — skipping map music, LMS starts after intro")
	else:
		_setup_music()
	
	# Setup chat system
	_setup_chat()
	
	# Load saved settings into GameState
	_apply_saved_settings()
	
	# Setup admin panel (for in-game admin controls)
	_setup_admin_panel()
	
	# Show role-switch hint (F2 / admin panel) — always visible & discoverable
	_create_role_hint()
	
	# Replace HUD labels with BitmapLabel versions
	_replace_hud_labels()
	
	# Initialize multiplayer sync if connected to server
	_initialize_multiplayer()
	
	# Play killer intro cutscene after spawns are complete
	_setup_vignette()
	call_deferred("_play_killer_cutscene")


func _setup_vignette() -> void:
	"""Add the circular faded-center HUD vignette (persists through LMS)."""
	var scene: PackedScene = load("res://scenes/vignette_overlay.tscn")
	if scene == null:
		return
	if not is_instance_valid($HUD):
		return
	var v: ColorRect = scene.instantiate()
	$HUD.add_child(v)
	print("GameMap: vignette overlay added")


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
				ev.keycode = keycode as Key
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
			player.bus = &"Music"
			player.volume_db = -12.0  # Lowered so rhythm-puzzle BPM audio stays audible
			player.finished.connect(_on_map_music_finished)
			add_child(player)
			print("GameMap: Playing background music")


func _switch_to_ending_music() -> void:
	"""Switch map music to match-ending track at 30s remaining.
	Plays as background music — chase can still play on top."""
	if _lms_active or _round_ended:
		# During the LMS finale the LMS track is the sole score; don't layer the
		# generic MATCH_ENDING song on top of it. Also never start it once the
		# round has ended (the killer-win outro must play ONLY the LMS tail).
		return
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
	player.bus = &"Music"
	player.volume_db = -12.0  # Lowered so rhythm-puzzle BPM audio stays audible
	player.finished.connect(_on_map_music_finished)
	add_child(player)
	
	# Fade out original map music if it's still playing
	var old_player: AudioStreamPlayer = get_node_or_null("MapMusicPlayer")
	if old_player:
		var fade_tween: Tween = create_tween()
		fade_tween.tween_property(old_player, "volume_db", -80.0, 1.0)
		await fade_tween.finished
		# The round may have ended (killer outro / lobby transition) while we were
		# waiting for the fade, freeing the player — guard before touching it.
		if is_instance_valid(old_player):
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
		area.add_to_group("puzzles")  # For ability gating near puzzle/generator zones
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


func _survivor_scene_for(survivor_name: String) -> PackedScene:
	# Map an equipped survivor name to its scene. Only Greengrass exists today —
	# extend this map (and add the entry to GameState.CHARACTER_CATALOG) as more
	# survivors are added.
	return GREENGRASS_SCENE


func _killer_scene_for(killer_name: String) -> PackedScene:
	match killer_name:
		"Test Killer": return TEST_KILLER_SCENE
		_: return VIOLENTGRASS_SCENE


func spawn_player(spawn_as_killer: bool = false) -> void:
	"""Spawn the player character at the appropriate spawn point."""
	var gs_sp = get_node("/root/GameState")
	var is_killer_player: bool = spawn_as_killer or (gs_sp != null and gs_sp.is_killer)
	var spawn_pos: Vector2 = _map_manager.get_spawn_point(is_killer_player)
	
	var player_scene: PackedScene
	var character_name: String = "Violentgrass"
	if is_killer_player:
		character_name = "Violentgrass"
		if gs_sp != null and gs_sp.selected_killer != "":
			character_name = gs_sp.selected_killer
		player_scene = _killer_scene_for(character_name)
	else:
		# Spawn the player's equipped survivor (Greengrass by default).
		character_name = "Greengrass"
		if gs_sp != null and gs_sp.selected_survivor != "":
			character_name = gs_sp.selected_survivor
		player_scene = _survivor_scene_for(character_name)
	_player = player_scene.instantiate()
	_player.name = "Player"
	_player.position = spawn_pos
	
	# Create health bar BEFORE adding to tree (catches initial hp_changed emit from _ready)
	_create_health_bar(_player)
	# Create stamina bar UI
	_create_stamina_bar(_player)
	
	add_child(_player)
	if is_killer_player:
		_player.add_to_group("killers")  # For single-killer enforcement sweep
	else:
		_player.add_to_group("survivors")
	# Camera zoom controller — adds scroll-wheel zoom + larger default zoom
	var zoom_ctrl := CameraZoomController.new()
	zoom_ctrl.name = "ZoomController"
	zoom_ctrl.default_zoom = 1.25  # Bigger than default 1.0 for easier viewing
	_player.add_child(zoom_ctrl)
	# Connect zoom to HUD vignette/overlay scaling if needed
	var cam: Camera2D = _player.get_node_or_null("Camera2D") as Camera2D
	
	# Set character name for analysis screen
	_character_name = character_name
	
	# Create ability icons
	_create_ability_icons(_player, is_killer_player)
	
	# Connect survivor ability icon signals (flash/lock)
	_connect_ability_icon_signals(_player)
	
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
		_refresh_survivor_cache()
		# Survivor player: load all 4 chase layers from survivor's theme folder
		_setup_chase_music(_chase_theme_folder())
	else:
		_spawn_survivor_bots()
		_refresh_survivor_cache()
		# Killer player: load only Chase layer from killer's theme folder
		_setup_chase_music(_chase_theme_folder())
	
	# Track damage dealt via punch signal
	if _player.has_signal("punch_landed") and not _player.punch_landed.is_connected(_on_player_attacked):
		_player.punch_landed.connect(_on_player_attacked)
	
	# Connect teleport zoom signal for killer map-view
	if _player.has_signal("teleport_zoom_started") and not _player.teleport_zoom_started.is_connected(_on_teleport_zoom_started):
		_player.teleport_zoom_started.connect(_on_teleport_zoom_started)
	
	# Connect teleported signal for sound + indicator
	if _player.has_signal("teleported") and not _player.teleported.is_connected(_on_player_teleported):
		_player.teleported.connect(_on_player_teleported)
	
	# Connect teleport FX start (red-glitch + zoom-in) for the human killer player
	if _player.has_signal("teleport_fx_started") and not _player.teleport_fx_started.is_connected(_on_teleport_fx_started):
		_player.teleport_fx_started.connect(_on_teleport_fx_started)
	
	# Connect teleport cancel to close mini-map
	if _player.has_signal("teleport_cancelled") and not _player.teleport_cancelled.is_connected(_close_teleport_minimap):
		_player.teleport_cancelled.connect(_close_teleport_minimap)
	
	# Connect teleport zoom signals for camera map-view
	if _player.has_signal("teleport_zoom_started") and not _player.teleport_zoom_started.is_connected(_on_teleport_zoom_started):
		_player.teleport_zoom_started.connect(_on_teleport_zoom_started)
	if _player.has_signal("teleport_zoom_ended") and not _player.teleport_zoom_ended.is_connected(_on_teleport_zoom_ended):
		_player.teleport_zoom_ended.connect(_on_teleport_zoom_ended)
	
	# Re-assert player camera (bots spawned above may have tried to steal it)
	if is_instance_valid(cam):
		cam.enabled = true
		cam.make_current()
	
	print("GameMap: Spawned ", _character_name, " at ", spawn_pos)


# ═══════════════ ROLE SWITCHER (debug/testing) ═══════════════

func _clear_role_entities() -> void:
	"""Free all role-specific entities (player, bots, chase players, HUD bars)."""
	# Player
	if is_instance_valid(_player):
		_player.queue_free()
		_player = null
	# Killer bot
	if is_instance_valid(_killer_bot):
		_killer_bot.queue_free()
		_killer_bot = null
	# Survivor bots
	for bot: Node2D in _survivor_bots:
		if is_instance_valid(bot):
			bot.queue_free()
	_survivor_bots.clear()
	_alive_survivor_bot_count = 0
	# AI difficulty controller (attached to killer bot)
	if is_instance_valid(_ai_difficulty):
		_ai_difficulty.queue_free()
		_ai_difficulty = null
	# Chase players
	for p: AudioStreamPlayer in _chase_players:
		if is_instance_valid(p):
			p.queue_free()
	_chase_players.clear()
	_chase_active_layer = -1
	_chase_layers_enabled = [false, false, false, false]
	# HUD bars (health + stamina)
	var hud_node: CanvasLayer = $HUD
	if hud_node:
		var hb: Node = hud_node.get_node_or_null("HealthBar")
		if hb:
			hb.queue_free()
		var sb: Node = hud_node.get_node_or_null("StaminaBar")
		if sb:
			sb.queue_free()
	# Fullscreen overlays (epilepsy + vignette + ending) — free them so they don't
	# stack/get progressively greyer on repeated role switches.
	if is_instance_valid(_epilepsy_overlay):
		_epilepsy_overlay.queue_free()
		_epilepsy_overlay = null
	if is_instance_valid(_vignette_overlay):
		_vignette_overlay.queue_free()
		_vignette_overlay = null
	if is_instance_valid(_ending_vignette):
		_ending_vignette.queue_free()
		_ending_vignette = null
	# Match-ending screen nodes (Violentgrass-branded bg + overlay + red flash)
	if is_instance_valid(_ending_screen_bg):
		_ending_screen_bg.queue_free()
		_ending_screen_bg = null
	if is_instance_valid(_ending_screen_overlay):
		_ending_screen_overlay.queue_free()
		_ending_screen_overlay = null
	if is_instance_valid(_ending_red_left):
		_ending_red_left.queue_free()
		_ending_red_left = null
	if is_instance_valid(_ending_red_right):
		_ending_red_right.queue_free()
		_ending_red_right = null
	_ending_screen_created = false
	# LMS timer-transition overlay — free it so it can't linger on a role switch.
	if is_instance_valid(_lms_transition_overlay):
		_lms_transition_overlay.queue_free()
		_lms_transition_overlay = null
	_lms_transition_active = false
	_lms_transition_target = 0.0


func _switch_role(role: String) -> void:
	"""Debug/testing helper: switch the player between killer and survivor roles.
	Called via F2 hotkey or the role buttons in the admin panel."""
	var is_killer: bool = role.to_lower() == "killer"
	if is_killer == GameState.is_killer:
		return  # Already that role
	_clear_role_entities()
	GameState.is_killer = is_killer
	spawn_player(is_killer)
	print("GameMap: [RoleSwitcher] switched to %s" % ("KILLER (Violentgrass)" if is_killer else "SURVIVOR (Greengrass)"))


func _toggle_role() -> void:
	"""Toggle between killer and survivor roles (F2 hotkey)."""
	_switch_role("survivor" if GameState.is_killer else "killer")


func _unhandled_input(event: InputEvent) -> void:
	# F2 toggles killer/survivor role for easy testing
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		_toggle_role()
		get_viewport().set_input_as_handled()
	# F3 toggles the admin GUI panel (reliable key shortcut, no chat needed)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		var a_panel: AdminPanel = get_node_or_null("AdminPanel")
		if a_panel:
			a_panel.toggle_gui()
		get_viewport().set_input_as_handled()


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
	var is_killer_player: bool = GameState.is_killer if GameState else false
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
	if is_killer_player:
		bg.color = Color(0.4, 0.0, 0.0, 0.7)  # Dark red bg
	else:
		bg.color = Color(0.4, 0.4, 0.4, 0.6)
	container.add_child(bg)
	
	# Fill bar (inside the border)
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.size = Vector2(400, 28)
	if is_killer_player:
		fill.color = Color(0.0, 0.0, 0.0, 0.95)  # Black fill — reveals red bg when depleted
	else:
		fill.color = Color(0.15, 0.9, 0.15, 0.9)  # Green
	container.add_child(fill)
	
	# Label (HP text)
	var label := Label.new()
	label.name = "Label"
	label.text = "100 / 100"
	label.position = Vector2(0, 4)
	label.size = Vector2(400, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_killer_player:
		label.add_theme_color_override("font_color", Color(0.9, 0.1, 0.1, 1))  # Red text
		label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1))
	else:
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 18)
	container.add_child(label)
	
	# Connect to player's hp_changed signal
	if player.has_signal("hp_changed"):
		player.hp_changed.connect(_on_player_hp_changed.bind(fill, label, is_killer_player))


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
	# HARD GUARANTEE: the round ends the instant the timer hits 0. Checked first
	# every frame so nothing (paused timer, bonus count-up, dying player) can
	# keep the round going past 00:00.
	if _time_remaining <= 0.0 and not _round_ended:
		_time_remaining = 0.0
		if match_timer:
			match_timer.stop()
		_update_timer_label()
		_killer_won = false  # timer-out, not a killer win by elimination
		_end_match()
		return
	
	if not is_instance_valid(_player):
		return
	
	# ── Single-killer enforcement: sweep every 2 seconds ──
	_killer_sweep_timer += delta
	if _killer_sweep_timer >= 2.0:
		_killer_sweep_timer = 0.0
		_enforce_single_killer()
	
	# Multiplayer position sync
	if _multiplayer_sync and is_instance_valid(_player):
		_sync_multiplayer_position(_player.global_position)
	
	# Animated timer bonus count-up (red, tick-by-tick)
	if _bonus_target > 0.0:
		# Track if timer crosses ending threshold during bonus animation
		var was_in_ending: bool = _time_remaining <= 31.0
		
		_bonus_tick_timer += delta
		var tick_speed: float = 0.15  # ~6.7 ticks per second
		while _bonus_tick_timer >= tick_speed and _time_remaining < _bonus_target:
			_bonus_tick_timer -= tick_speed
			_time_remaining = min(_time_remaining + 1.0, _bonus_target)
			_timer_flash_red = 0.3  # Keep red while counting up
			_update_timer_label()
		
		# If timer crossed from ≤31 to >31 during animation → restore map music
		if was_in_ending and _time_remaining > 31.0 and _ending_music_switched:
			_restore_map_music()
		
		if _time_remaining >= _bonus_target:
			_bonus_target = 0.0
			_bonus_tick_timer = 0.0
	
	# LMS timer-transition: animate the match clock up/down to the LMS song
	# length with a dark-red screen while it runs.
	_update_lms_timer_transition(delta)
	
	# Pause the match timer while a time adjustment is being applied (puzzle
	# completion or kill +30s bonus), then resume once the pause duration elapses
	# AND the bonus count-up animation has finished.
	if _timer_pause_remaining > 0.0:
		_timer_pause_remaining -= delta
		if match_timer:
			match_timer.paused = true
		if _timer_pause_remaining <= 0.0 and _bonus_target <= 0.0:
			_timer_pause_remaining = 0.0
			if match_timer:
				match_timer.paused = false
	elif _bonus_target > 0.0 and match_timer:
		# Pause while the kill +30s bonus is still counting up.
		match_timer.paused = true
	
	_update_ability_cooldowns()
	_check_interact_input(delta)
	_check_settings_updates()
	_check_damage_vignette()
	_update_chase_music(delta)
	_update_lms_vfx(delta)
	_update_lms_heartbeat(delta)
	_update_lms_pulse(delta)
	_update_killer_speed(delta)
	_check_everyone_dead()
	
	# Match-ending effects (last 31 seconds) — skip during bonus animation.
	# These only play when a match ENDS with survivors still in play. Once the
	# LMS finale starts (1 survivor left) the LMS track/VFX own the ending, so
	# the generic ending music, vignette and Violentgrass ending screen are all
	# disabled here.
	if not _lms_active and not _round_ended and _time_remaining <= 31.0 and _bonus_target <= 0.0:
		_ending_start_time += delta
		_update_ending_vignette()
		_switch_to_ending_music()
		# Match ending screen (Violentgrass) — ONLY for the killer (Violentgrass)
		# player. Survivors do NOT see the killer's branded ending screen or overlay.
		if _character_name == "Violentgrass":
			if not _ending_screen_created:
				_create_match_ending_screen()
			_update_match_ending_screen(delta)
	
	# HARD FALLBACK: force lobby redirect when timer hits 0 for both killer and survivor
	if _time_remaining <= 0.0 and not _round_ended:
		_killer_won = false  # timer-out, not a killer win by elimination
		_end_match()
		return
	
	# Update AI difficulty scaling
	_update_ai_difficulty()
	
	# Update screen-edge teleport markers (reposition as camera moves)
	_update_teleport_markers()
	
	# Update teleport red-glitch overlay (time + fade while teleporting)
	_update_teleport_fx(delta)
	
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
	
	# Define ability icon data based on character type (single source of truth)
	var abilities: Array[Dictionary] = _get_abilities_for(is_killer)
	
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
		
		# Lock overlay — only for survivors' Spare Flower (slot index 1), never the killer
		if i == 1 and not is_killer:
			var lock_overlay := ColorRect.new()
			lock_overlay.name = "LockOverlay"
			lock_overlay.size = Vector2(56, 56)
			lock_overlay.color = Color(0.3, 0.3, 0.3, 0.7)
			lock_overlay.visible = true  # Start locked
			slot.add_child(lock_overlay)
		
		# Key cap background
		var key_bg := ColorRect.new()
		key_bg.name = "KeyBg"
		key_bg.position = Vector2(2, 34)
		key_bg.size = Vector2(22, 18)
		key_bg.color = Color(0, 0, 0, 0.55)
		slot.add_child(key_bg)

		# Key label
		var key_label := Label.new()
		key_label.name = "KeyLabel"
		key_label.text = data["key"]
		key_label.position = Vector2(2, 34)
		key_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		key_label.add_theme_font_size_override("font_size", 14)
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
	
	var data_abilities: Array[Dictionary] = _get_ability_data()
	for i in range(icons.get_child_count()):
		var slot: Node = icons.get_child(i)
		if i >= data_abilities.size():
			continue
		var data: Dictionary = data_abilities[i]
		var cd_var: String = data.get("cooldown_var", "")
		var overlay: ColorRect = slot.get_node_or_null("CooldownOverlay")
		if not overlay:
			continue
		
		var is_on_cd: bool = cd_var in _player and bool(_player.get(cd_var))
		overlay.visible = is_on_cd
		
		# Update countdown label using each ability's own timer variable
		var cd_label: Label = overlay.get_node_or_null("CooldownLabel")
		if cd_label:
			if is_on_cd:
				var timer_var: String = data.get("cooldown_timer_var", "")
				if timer_var in _player:
					var remaining: float = float(_player.get(timer_var))
					cd_label.text = str(ceili(maxf(remaining, 0.0)))
				else:
					cd_label.text = ""
			else:
				cd_label.text = ""


func _get_ability_data() -> Array[Dictionary]:
	"""Return ability data for the current player character."""
	return _get_abilities_for(_is_killer_character(_character_name))


func _is_killer_character(char_name: String) -> bool:
	"""True if the character name is a killer (Violentgrass or Test Killer)."""
	if char_name == "Test Killer" or char_name == "Violentgrass":
		return true
	return false


func _get_abilities_for(is_killer_player: bool) -> Array[Dictionary]:
	"""Return ability data (icon, key, cooldown bool var, cooldown timer var)."""
	if is_killer_player:
		if _character_name == "Test Killer":
			# Test Killer: M1 hit + E tentacle snatch + R The Rage
			return [
				{"icon": "res://assets/generated/icon_ability_hit.png", "key": "M1", "cooldown_var": "hit_on_cooldown", "cooldown_timer_var": "hit_cooldown_timer"},
				{"icon": "", "key": "E", "cooldown_var": "tentacle_on_cooldown", "cooldown_timer_var": "tentacle_cooldown_timer"},
				{"icon": "", "key": "R", "cooldown_var": "rage_on_cooldown", "cooldown_timer_var": "rage_cooldown_timer"},
			]
		# Violentgrass: M1 hit + E teleport
		return [
			{"icon": "res://assets/generated/icon_ability_hit.png", "key": "M1", "cooldown_var": "hit_on_cooldown", "cooldown_timer_var": "_hit_cd_timer"},
			{"icon": "res://assets/generated/icon_ability_teleport.png", "key": "E", "cooldown_var": "teleport_on_cooldown", "cooldown_timer_var": "_teleport_cd_timer"},
		]
	else:
		return [
			{"icon": "res://assets/generated/icon_ability_block.png", "key": "Q", "cooldown_var": "block_on_cooldown", "cooldown_timer_var": "_block_cd_timer"},
			{"icon": "res://assets/generated/icon_ability_grass_punch.png", "key": "E", "cooldown_var": "punch_on_cooldown", "cooldown_timer_var": "_punch_cd_timer"},
			{"icon": "res://assets/generated/icon_ability_spare_flower.png", "key": "R", "cooldown_var": "flower_on_cooldown", "cooldown_timer_var": "_flower_cd_timer"},
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


func _on_player_hp_changed(current_hp: float, max_hp: float, fill: ColorRect, label: Label, is_killer: bool = false) -> void:
	"""Update the health bar when player HP changes."""
	var ratio: float = current_hp / max_hp if max_hp > 0 else 0.0
	fill.size.x = 400.0 * clampf(ratio, 0.0, 1.0)
	label.text = "%d / %d" % [current_hp, max_hp]
	
	# Save previous HP BEFORE updating _last_hp (used for death check below)
	var prev_hp: float = _last_hp
	
	# Damage VFX: screen shake + red flash when HP drops
	if _last_hp >= 0 and current_hp < _last_hp:
		var dmg: float = _last_hp - current_hp
		_total_damage_taken += dmg
		_trigger_screen_shake(clampf(dmg * 0.2, 2.0, 8.0), 0.25)
		_trigger_vignette()
		_last_damage_time = _time_remaining
	_last_hp = current_hp
	
	if not is_killer:
		# Color shifts from green to red as HP drops (survivor)
		if ratio < 0.3:
			fill.color = Color(0.9, 0.15, 0.15, 0.9)
		elif ratio < 0.6:
			fill.color = Color(0.9, 0.7, 0.1, 0.9)
		else:
			fill.color = Color(0.15, 0.9, 0.15, 0.9)
	# Killer: fill stays black (red bg shows through as fill shrinks), text stays red
	
	# Death / round end when HP reaches 0
	# NOTE: uses prev_hp (saved before _last_hp update) to detect the transition to 0
	if current_hp <= 0.0 and prev_hp > 0.0:
		if is_killer:
			# Killer eliminated (tanky — 6666 HP, 25 dmg per punch = ~267 hits)
			print("GameMap: Killer eliminated — ending match")
			match_timer.stop()
			# Survivors win — no killer outro.
			_killer_won = false
			if not _round_ended:
				match_ended.emit()
				_end_match()
		else:
			# Survivor eliminated — +30s timer bonus if bot killer exists
			if is_instance_valid(_killer_bot):
				_on_survivor_eliminated("Player")
			# The killer (AI bot or human) won here.
			_killer_won = true
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
		bot_cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		bot_cam.enabled = false
	add_child(bot)
	if bot.has_signal("bot_solved_puzzle"):
		bot.bot_solved_puzzle.connect(_on_bot_solved_puzzle)
	# Track bot HP to detect elimination
	if bot.has_signal("hp_changed"):
		bot.hp_changed.connect(_on_bot_hp_changed.bind(bot))
	bot.add_to_group("survivor_bots")
	_survivor_bots.append(bot)
	_alive_survivor_bot_count += 1


func _enforce_single_killer() -> void:
	"""Safety sweep: if more than one killer exists in the scene, eliminate extras.
	- If the player is a killer and there's also a bot killer → kill the bot.
	- If the player is a survivor and there are 2+ bot killers → kill all but one.
	- If somehow 2 player-killers exist → kill both (should never happen offline)."""
	var all_killers: Array[Node] = get_tree().get_nodes_in_group("killers")
	# Filter out any queued-for-deletion nodes.
	var valid_killers: Array[Node] = []
	for k: Node in all_killers:
		if is_instance_valid(k):
			valid_killers.append(k)
	if valid_killers.size() <= 1:
		return  # Normal: exactly 0 or 1 killer.
	
	var player_is_killer: bool = GameState.is_killer if GameState else false
	var bot_killers: Array[Node] = []
	var player_killers: Array[Node] = []
	for k: Node in valid_killers:
		if k == _player or (is_instance_valid(_player) and k.name == _player.name):
			player_killers.append(k)
		else:
			bot_killers.append(k)
	
	if player_killers.size() > 1:
		# Multiple player-killers — kill all of them (unrecoverable).
		print("GameMap: ENFORCE — ", player_killers.size(), " player-killers detected! Killing all.")
		for pk: Node in player_killers:
			if is_instance_valid(pk):
				pk.queue_free()
	elif player_killers.size() == 1 and bot_killers.size() >= 1:
		# Player is killer + bot killer exists → kill ALL bot killers.
		print("GameMap: ENFORCE — player is killer, removing ", bot_killers.size(), " extra bot killer(s)")
		for bk: Node in bot_killers:
			if is_instance_valid(bk):
				bk.queue_free()
				if bk == _killer_bot:
					_killer_bot = null
	elif bot_killers.size() > 1:
		# No player-killer, but multiple bot killers → keep one, kill the rest.
		print("GameMap: ENFORCE — ", bot_killers.size(), " bot killers, keeping one")
		for i: int in range(1, bot_killers.size()):
			if is_instance_valid(bot_killers[i]):
				bot_killers[i].queue_free()
				if bot_killers[i] == _killer_bot:
					_killer_bot = null


func _chase_theme_folder() -> String:
	"""Pick the chase-music theme folder matching whichever killer is in the match."""
	var killer_name: String = "Violentgrass"
	if is_instance_valid(_killer_bot) and _killer_character_name != "":
		killer_name = _killer_character_name
	elif _character_name == "Test Killer" or _character_name == "Violentgrass":
		killer_name = _character_name
	if killer_name == "Test Killer":
		return "Test Killer (Originally Monster Greengrass, but used for tests for now.)"
	return "Violentgrass"


func _spawn_flower_items() -> void:
	"""Place a couple of Flower pickups (heal 90 HP) randomly across the map."""
	var flower_script: Script = load("res://scripts/items/flower_item.gd")
	if flower_script == null:
		return
	var map_size: Vector2 = _map_manager.blueprint_size if _map_manager and _map_manager.blueprint_size else Vector2(2000, 1500)
	for i in range(2):
		var item := Area2D.new()
		item.set_script(flower_script)
		item.name = "FlowerItem%d" % i
		item.position = Vector2(
			randf_range(120.0, map_size.x - 120.0),
			randf_range(120.0, map_size.y - 120.0)
		)
		add_child(item)
	print("GameMap: spawned 2 Flower pickups")


func _spawn_bot_killer() -> void:
	"""Spawn an AI-controlled killer bot at a killer spawn point.
	ENFORCES single-killer: if a killer bot already exists, this is a no-op."""
	if is_instance_valid(_killer_bot):
		print("GameMap: _spawn_bot_killer BLOCKED — killer bot already exists")
		return
	var spawn_pos: Vector2 = _map_manager.get_spawn_point(true)
	
	# Killer AI randomly picks Violentgrass or Test Killer.
	var use_test: bool = randi() % 2 == 0
	_killer_character_name = "Test Killer" if use_test else "Violentgrass"
	var bot_scene: PackedScene = TEST_KILLER_SCENE if use_test else VIOLENTGRASS_SCENE
	var bot: Node2D = bot_scene.instantiate()
	bot.set_script(AI_TEST_KILLER_SCRIPT if use_test else AI_BOT_SCRIPT)
	bot.name = "KillerBot"
	bot.position = spawn_pos
	add_child(bot)
	_killer_bot = bot
	bot.add_to_group("killers")  # For single-killer enforcement sweep
	if bot.has_signal("hit_landed") and not bot.hit_landed.is_connected(_on_killer_hit_landed):
		bot.hit_landed.connect(_on_killer_hit_landed)
	# GUARANTEED round-end: track the AI killer's HP so the round ends the moment
	# the survivor eliminates it. Without this, killing the bot never ends the match.
	if bot.has_signal("hp_changed") and not bot.hp_changed.is_connected(_on_killer_bot_hp_changed):
		bot.hp_changed.connect(_on_killer_bot_hp_changed)
	# Connect teleported signal for sound + indicator
	if bot.has_signal("teleported") and not bot.teleported.is_connected(_on_player_teleported):
		bot.teleported.connect(_on_player_teleported)
	# Store killer's base sprint speed for scaling
	if "sprint_speed" in bot:
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


func _refresh_survivor_cache() -> void:
	"""Rebuild the cached list of nodes in the 'survivors' group.
	Call after spawning or eliminating survivors instead of querying every frame."""
	_cached_survivors = get_tree().get_nodes_in_group("survivors")


func _setup_chase_music(folder_name: String) -> void:
	"""Create chase layer players from the specified theme folder, all muted until triggered.
	Auto-searches in CHASE_BASE_DIR + folder_name/ for Layer1-3.wav and Chase.wav."""
	_chase_players.clear()
	_chase_layers_enabled = [false, false, false, false]
	_chase_active_layer = -1
	_chase_volume_tweens.clear()
	
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
		# Force-disable stream looping; we restart via _on_chase_loop instead.
		# Chase.wav's baked-in LOOP_FORWARD causes rapid finished signals in this
		# scene context, so we override it to 0 (disabled) here.
		var sdata := p.stream
		if sdata is AudioStreamWAV:
			sdata.loop_mode = 0
		p.bus = &"Music"
		p.volume_db = -80.0  # Muted until triggered
		p.autoplay = true
		add_child(p)
		# Restart playback on finish (matches the working background-music pattern).
		p.finished.connect(_on_chase_loop.bind(p))
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
	cutscene.fade_in_duration = 1.0  # Fade the killer intro in from black
	add_child(cutscene)
	
	var folder_path: String = "res://The Darkness Of The Grasslands assets/Cutscenes/Killer intros/Violentgrass killer intro"
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
	_match_live = true
	# LMS from match start when the entire match is a 1v1 (only a killer + one
	# survivor). Survivor mode is always 1v1 vs the AI killer bot; killer mode
	# counts as 1v1 when only a single survivor bot was spawned. Bigger matches
	# (e.g. 6 survivors vs 1 killer) do NOT start LMS until the killer whittles
	# them down — see _on_bot_hp_changed.
	if _character_name == "Greengrass" or _alive_survivor_bot_count <= 1:
		_start_lms()


func _on_chase_loop(player: AudioStreamPlayer) -> void:
	"""Loop a chase layer by replaying it on finish (matches the background music pattern)."""
	if is_instance_valid(player):
		player.play()


func _update_chase_music(_delta: float) -> void:
	"""Update chase music based on player role.
	
	- If player IS the killer → play ONLY the single Chase.wav track (no build-up
	  layers) when the human killer is close to survivors; stop only when
	  genuinely far away.
	- If player IS a survivor → play survivor's chase theme that starts its build
	  (Layer1 → Layer2 → Layer3, one at a time, each for
	  CHASE_BUILD_STEP_DURATION) while the killer bot is close to the HUMAN
	  player. The chase only reflects YOUR threat: it never plays just because
	  the killer is near another survivor bot, and it fades out once the killer
	  is far from Layer 1's range.
	
	Only ONE layer plays at a time (no stacking)."""

	if _chase_players.is_empty():
		return

	# During the LMS finale the LMS track is the sole score — chase themes are
	# muted and cannot play at all until the round is over.
	if _lms_active:
		if _chase_active_layer >= 0:
			_silence_all_chase()
		return
	
	var is_killer: bool = _character_name == "Violentgrass"
	var chase_source: Node2D = null
	var dist: float = INF
	
	if is_killer:
		# Player IS the killer — the chase is driven by the human killer's
		# proximity to the nearest surviving bot ("hunt them").
		chase_source = _player if is_instance_valid(_player) else null
		if is_instance_valid(chase_source):
			for s in _cached_survivors:
				if is_instance_valid(s):
					var d: float = chase_source.global_position.distance_to(s.global_position)
					if d < dist:
						dist = d
	else:
		# Player IS a survivor — the chase reflects the threat to the HUMAN
		# player ONLY. It plays when the killer bot is close to YOU and never
		# because the killer happens to be near some other survivor bot.
		chase_source = _killer_bot if is_instance_valid(_killer_bot) else null
		if is_instance_valid(chase_source) and is_instance_valid(_player):
			dist = chase_source.global_position.distance_to(_player.global_position)
	
	if not is_instance_valid(chase_source) or dist == INF:
		_silence_all_chase()
		return
	
	var target_layer: int = -1
	
	if is_killer:
		# ── KILLER (Violentgrass): ONLY the Chase.wav track (no build-up layers) ──
		# Within chase-enter range → play the single Chase layer loud.
		# The chase only stops when the killer is genuinely far beyond the exit.
		if _chase_active_layer >= 3:
			# Chase already playing → keep it until truly far away.
			if dist > KILLER_CHASE_EXIT[3]:
				_silence_all_chase()
				return
			target_layer = 3
		elif dist <= KILLER_CHASE_ENTER[3]:
			# Close enough to the nearest survivor → full Chase music.
			target_layer = 3
		# else: not near any survivor and no active chase → stays silent.
	else:
		# ── SURVIVOR: DISTANCE-BASED build-up (one layer at a time, NOT stacked) ──
		# Only ONE layer is audible at any moment. Which layer depends on how close
		# the killer (bot) is to the survivor:
		#   dist <= 500 → Layer1 (ENTER[0])
		#   dist <= 300 → Layer2 (ENTER[1])
		#   dist <= 150 → Layer3 (ENTER[2])
		#   dist <=  80 → Chase  (ENTER[3])
		# Higher = more intense. When the survivor gets closer it climbs toward
		# Chase; when they get farther it drops back down. The switch between
		# layers is a smooth crossfade (see the transition block below).
		target_layer = -1
		for i: int in range(3, -1, -1):
			if dist <= SURVIVOR_CHASE_ENTER[i]:
				target_layer = i
				break
		
		if target_layer < 0:
			if _chase_active_layer >= 0:
				# Already in a chase but the killer drifted past the outer enter.
				# Keep the current layer (hysteresis) unless genuinely far away.
				if dist > SURVIVOR_CHASE_EXIT[0]:
					_silence_all_chase()
					return
				target_layer = _chase_active_layer
			else:
				# Not near the killer and no chase → stays silent.
				_silence_all_chase()
				return
	
	# Handle layer transitions (smooth: no restart gap; one layer audible at a time)
	if target_layer != _chase_active_layer:
		var was_silent: bool = _chase_active_layer < 0
		
		if target_layer < 0:
			# Leaving the chase → full stop + reset so the next entry rebuilds fresh ("rework").
			_silence_all_chase()
		else:
			_chase_active_layer = target_layer
			
			if was_silent:
				# Fresh chase entry → (re)start ALL layers together so they run
				# synced/armed, only the active layer audible. Starts from Layer1
				# (or the depth matching current distance) and layers up from there.
				_kill_all_chase_tweens()
				for i: int in _chase_players.size():
					if is_instance_valid(_chase_players[i]):
						_chase_layers_enabled[i] = false
						_chase_players[i].volume_db = -80.0
						_chase_players[i].play(0.0)
			
			# Smooth swap: crossfade the incoming layer up, all others down (no restart).
			# Kill each player's previous ramp first so an old tween can't keep a layer
			# loud that should now be silent — that race was making the layers STACK
			# (several audible at once). Only the target layer is audible.
			for i: int in _chase_players.size():
				if not is_instance_valid(_chase_players[i]):
					continue
				_chase_layers_enabled[i] = i == target_layer
				var vol: float = CHASE_LAYER_VOLUME[i] if i == target_layer else -80.0
				_kill_chase_tween(i)
				_start_chase_tween(i, vol)
		
		# Mute/restore background map music based on whether a chase is active.
		# A chase layer playing → map music is FULLY muted (CHASE_MAP_DUCK_DB).
		# No chase → map music is restored (unless the ending music is active).
		_set_map_music_chase_state(target_layer >= 0)


func _silence_all_chase() -> void:
	"""Silence AND fully stop all chase layers, then reset the build so the next
	chase entry rebuilds fresh from Layer1 (the 'rework')."""
	_kill_all_chase_tweens()
	for i in range(_chase_players.size()):
		var player: AudioStreamPlayer = _chase_players[i]
		if is_instance_valid(player):
			player.volume_db = -80.0
			player.stop()
	_chase_active_layer = -1
	# Reset the build-up sequence so the next chase restarts from Layer1.
	_chase_build_step = 0
	_chase_build_elapsed = 0.0
	# Chase stopped → restore the map music (reached even on the early-return
	# paths that skip the normal transition restore).
	_set_map_music_chase_state(false)


func _set_map_music_chase_state(chasing: bool) -> void:
	"""Mute the background map music while a chase is active, restore it when no
	chase is playing (i.e. the killer is far). The ending/LMS music is never
	touched here — it has its own flow."""
	if _lms_active or _ending_music_switched:
		# During LMS/ending the finale track is the sole score — leave map music
		# as-is (it is stopped/absent anyway in those states).
		return
	var bg_player: AudioStreamPlayer = get_node_or_null("MusicPlayer")
	if not bg_player:
		bg_player = get_node_or_null("MapMusicPlayer")
	if bg_player:
		var target_bg_db: float = CHASE_MAP_DUCK_DB if chasing else 0.0
		var mtween := create_tween()
		mtween.tween_property(bg_player, "volume_db", target_bg_db, CHASE_VOL_FADE_MS)


func _kill_chase_tween(i: int) -> void:
	"""Kill the crossfade tween currently driving chase player i (if any)."""
	if _chase_volume_tweens.size() > i and _chase_volume_tweens[i] != null:
		var t: Tween = _chase_volume_tweens[i]
		if t.is_valid():
			t.kill()
		_chase_volume_tweens[i] = null


func _kill_all_chase_tweens() -> void:
	for i in _chase_volume_tweens.size():
		var t: Tween = _chase_volume_tweens[i]
		if t != null and t.is_valid():
			t.kill()
	_chase_volume_tweens.clear()


func _start_chase_tween(i: int, vol: float) -> void:
	"""Start a crossfade tween that moves chase player i's volume to vol."""
	while _chase_volume_tweens.size() <= i:
		_chase_volume_tweens.append(null)
	var ctween := create_tween()
	ctween.tween_property(_chase_players[i], "volume_db", vol, CHASE_VOL_FADE_MS)
	_chase_volume_tweens[i] = ctween


# ---------- TELEPORT ZOOM (map-view circles) ----------
# Variables for survivor visibility management
var _survivors_hidden: Array[Node] = []  # Survivors hidden during teleport scan

func _on_teleport_zoom_started() -> void:
	"""Zoom camera to full-map view, hide survivors, and show teleport circles."""
	# Only works for the human killer (not AI bot)
	var gs_t = get_node_or_null("/root/GameState")
	if gs_t != null and gs_t.is_killer:
		_zoom_to_map_view()
		_hide_survivors_for_teleport()
		_show_teleport_circles()


func _on_teleport_zoom_ended() -> void:
	"""Restore camera, show survivors, and close teleport overlay.
	When a human-killer teleport FX is playing, the red-glitch tween drives the
	camera (zoom-in → slow zoom-out) instead of the instant restore, so we skip
	_restore_camera_view here and let the FX finish the job."""
	if not _teleport_fx_zoom_out_started and not _teleport_fx_active:
		_restore_camera_view()
	_show_survivors_after_teleport()
	_close_teleport_minimap()


func _zoom_to_map_view() -> void:
	"""Zoom the camera out to show the entire map on screen."""
	var zoom_ctrl: Node = _player.get_node_or_null("ZoomController")
	if is_instance_valid(zoom_ctrl) and zoom_ctrl.has_method("zoom_to_map_view"):
		zoom_ctrl.zoom_to_map_view()


func _restore_camera_view() -> void:
	"""Restore the camera to normal zoom and follow mode."""
	var zoom_ctrl: Node = _player.get_node_or_null("ZoomController")
	if is_instance_valid(zoom_ctrl) and zoom_ctrl.has_method("restore_normal_zoom"):
		zoom_ctrl.restore_normal_zoom()


func _hide_survivors_for_teleport() -> void:
	"""Hide all survivors from the killer's view during teleport scan."""
	_survivors_hidden.clear()
	var survivors: Array[Node] = get_tree().get_nodes_in_group("survivors")
	for s: Node in survivors:
		if is_instance_valid(s) and s.visible:
			s.visible = false
			_survivors_hidden.append(s)


func _show_survivors_after_teleport() -> void:
	"""Restore visibility of all survivors hidden during teleport scan."""
	for s: Node in _survivors_hidden:
		if is_instance_valid(s):
			s.visible = true
	_survivors_hidden.clear()


func _show_teleport_circles() -> void:
	"""Show clickable circles on the zoomed-out map at world positions.
	3 targets per survivor: near (200-400px offset), direct (on survivor), and decoy."""
	_close_teleport_minimap()
	_teleport_circles.clear()
	_teleport_marker_buttons.clear()
	_teleport_marker_targets.clear()
	
	# Generate a red circle texture for all markers
	var marker_tex: Texture2D = _make_teleport_marker_texture(48, 20)
	
	# Gather target positions: 3 per survivor (near + direct + decoy)
	var survivors: Array[Node] = get_tree().get_nodes_in_group("survivors")
	for s: Node in survivors:
		if not is_instance_valid(s):
			continue
		var real_pos: Vector2 = s.global_position
		
		# Target 1: near survivor (200-400px offset)
		var offset1: Vector2 = Vector2(randf_range(-400, 400), randf_range(-400, 400))
		if offset1.length() < 200.0:
			offset1 = offset1.normalized() * 200.0
		_teleport_marker_targets.append(real_pos + offset1)
		
		# Target 2: directly on the survivor
		_teleport_marker_targets.append(real_pos)
		
		# Target 3: decoy at a random map position
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
	"""Generate a red circle texture for teleport markers."""
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
				var t: float = dist / radius
				var alpha: float = 1.0 - t * 0.3
				img.set_pixel(x, y, Color(1, 0.2, 0.2, alpha))
			if abs(dist - radius) < 2.0 and dist > 0:
				img.set_pixel(x, y, Color(1, 0.5, 0.5, 1.0))
	return ImageTexture.create_from_image(img)


func _update_teleport_markers() -> void:
	"""Position each marker at the screen position of its world target.
	Called every frame from _process while markers are active."""
	if not _teleport_markers_active:
		return
	
	var camera: Camera2D = get_viewport().get_camera_2d()
	if not is_instance_valid(camera):
		return
	
	for i in range(_teleport_marker_buttons.size()):
		var btn: Button = _teleport_marker_buttons[i]
		if not is_instance_valid(btn):
			continue
		if i >= _teleport_marker_targets.size():
			continue
		
		var target_pos: Vector2 = _teleport_marker_targets[i]
		# Convert world position to screen position using camera canvas transform
		var screen_pos: Vector2 = camera.get_canvas_transform() * target_pos
		btn.position = screen_pos - btn.size * 0.5
		btn.visible = true


func _on_teleport_marker_pressed(index: int) -> void:
	"""Handle click on a teleport marker — teleport killer to that target."""
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
	on survivor HUDs pointing toward the teleport location. If the HUMAN played
	this teleport, the red-glitch overlay fades away and the camera slowly zooms
	out to reveal the destination."""
	if _character_name == "Violentgrass":
		_start_teleport_zoom_out()
	_play_teleport_sound_at(new_pos)
	_close_teleport_minimap()
	_show_teleport_indicator(new_pos)


# ---------- TELEPORT RED-GLITCH FX (human killer) ----------

func _on_teleport_fx_started() -> void:
	"""The human killer is executing a teleport: flash the screen red + glitchy
	and zoom IN dramatically, hiding the position jump. CameraZoomController then
	slow-zooms OUT once the teleport completes (_on_player_teleported)."""
	if _character_name != "Violentgrass":
		return
	_show_teleport_fx()
	_teleport_fx_zoom_out_started = false
	var zoom_ctrl: Node = _player.get_node_or_null("ZoomController")
	if is_instance_valid(zoom_ctrl) and zoom_ctrl.has_method("tween_zoom_to"):
		zoom_ctrl.tween_zoom_to(TELEPORT_FX_ZOOM_IN, 0.35)  # Quick zoom-in as we jump


func _show_teleport_fx() -> void:
	"""Create/re-show the full-screen red-glitch overlay. When zooming out on
	arrival, _update_teleport_fx flattens the intensity down so it fades out."""
	if _teleport_fx_layer and is_instance_valid(_teleport_fx_layer):
		_teleport_fx_layer.visible = true
		_teleport_fx_rect.material = _teleport_fx_mat
		_teleport_fx_timer = 0.0
		_teleport_fx_active = true
		_teleport_fx_mat.set_shader_parameter("intensity", TELEPORT_FX_INTENSITY_IN)
		_teleport_fx_mat.set_shader_parameter("time", 0.0)
		return
	if not ResourceLoader.exists("res://shaders/teleport_glitch.gdshader"):
		push_error("GameMap: teleport_glitch shader missing.")
		return

	_teleport_fx_layer = CanvasLayer.new()
	_teleport_fx_layer.name = "TeleportFxLayer"
	_teleport_fx_layer.layer = 65  # Above gameplay/markers, below HUD (120+)
	add_child(_teleport_fx_layer)

	_teleport_fx_rect = TextureRect.new()
	_teleport_fx_rect.name = "TeleportFx"
	_teleport_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_teleport_fx_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 1x1 white texture so the rect issues a draw call; the shader only samples
	# SCREEN_TEXTURE so the rect's own texture content is irrelevant.
	var fx_img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	fx_img.set_pixel(0, 0, Color.WHITE)
	_teleport_fx_rect.texture = ImageTexture.create_from_image(fx_img)

	_teleport_fx_mat = ShaderMaterial.new()
	_teleport_fx_mat.shader = load("res://shaders/teleport_glitch.gdshader")
	_teleport_fx_mat.set_shader_parameter("intensity", TELEPORT_FX_INTENSITY_IN)
	_teleport_fx_mat.set_shader_parameter("time", 0.0)
	_teleport_fx_rect.material = _teleport_fx_mat

	_teleport_fx_layer.add_child(_teleport_fx_rect)
	_teleport_fx_timer = 0.0
	_teleport_fx_active = true


func _update_teleport_fx(delta: float) -> void:
	"""Advance the red-glitch overlay's time + fade it out after the slow
	zoom-out begins. When intensity hits 0 the overlay hides."""
	if not _teleport_fx_active or not is_instance_valid(_teleport_fx_mat):
		return
	_teleport_fx_timer += delta
	_teleport_fx_mat.set_shader_parameter("time", _teleport_fx_timer)

	# Once the slow zoom-out is playing, fade the red down over ~0.7s.
	if _teleport_fx_zoom_out_started:
		var fade_progress: float = (_teleport_fx_timer - _teleport_fx_zoom_out_started_at) / 0.7
		var intensity: float = clampf(1.0 - fade_progress, 0.0, 1.0)
		_teleport_fx_mat.set_shader_parameter("intensity", intensity)
		if intensity <= 0.01:
			_teleport_fx_active = false
			if is_instance_valid(_teleport_fx_layer):
				_teleport_fx_layer.visible = false


func _start_teleport_zoom_out() -> void:
	"""After the human killer arrives, hold the red close-up for a moment, then
	slowly zoom the camera back out and fade the red-glitch overlay. Only
	triggers once per teleport."""
	if _teleport_fx_zoom_out_started:
		return
	_teleport_fx_zoom_out_started = true

	# Let the zoom-IN (and red flash) read for a beat before the slow reveal.
	await get_tree().create_timer(TELEPORT_FX_ZOOM_IN_HOLD_S).timeout
	if not _teleport_fx_zoom_out_started:
		return
	if not is_instance_valid(self):
		return

	_teleport_fx_zoom_out_started_at = _teleport_fx_timer

	var zoom_ctrl: Node = _player.get_node_or_null("ZoomController")
	if is_instance_valid(zoom_ctrl) and zoom_ctrl.has_method("tween_zoom_to"):
		zoom_ctrl.tween_zoom_to(1.25, TELEPORT_FX_ZOOM_OUT_MS / 1000.0)  # Slow reveal
		# When the slow zoom-out finishes, re-enable camera smoothing (map-view
		# disabled it) so follow behavior is fully normal again.
		await get_tree().create_timer(TELEPORT_FX_ZOOM_OUT_MS / 1000.0).timeout
		if is_instance_valid(zoom_ctrl) and zoom_ctrl.has_method("restore_normal_zoom_silent"):
			zoom_ctrl.restore_normal_zoom_silent()


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

func add_timer_bonus(seconds: float) -> void:
	"""Add time to the match timer with animated red count-up. No cap — timer can grow past 4 minutes."""
	_bonus_target = _time_remaining + seconds
	_force_timer_pause(seconds * 0.15)  # Keep the countdown paused while the bonus plays out
	print("GameMap: Timer +", seconds, "s (target ", _bonus_target, "s)")


func _force_timer_pause(duration: float) -> void:
	"""Pause the match countdown for 'duration' seconds (e.g. while applying a
	time adjustment for a puzzle completion or kill). The pause is lifted after
	the duration AND once any bonus count-up animation has finished."""
	_timer_pause_remaining = max(_timer_pause_remaining, duration)
	if match_timer:
		match_timer.paused = true


# ---------- KILLER ELIMINATION TRACKING ----------

func _on_survivor_eliminated(player_name: String) -> void:
	"""Called when a survivor is eliminated (killed by the killer). +30s timer bonus + ending music handling."""
	# Multiplayer: report the elimination to the server (broadcast to all players)
	if _multiplayer_sync:
		_multiplayer_sync.send_player_eliminated(player_name)
	add_timer_bonus(30.0)
	
	# Handle music transitions when kill happens during ending countdown
	if _ending_music_switched:
		var final_target: float = min(_time_remaining + 30.0, MATCH_DURATION)
		if final_target > 31.0:
			# Kill pushes timer back past 31s → restore normal map music
			_restore_map_music()
		else:
			# Kill within ending period → rewind ending music from beginning
			_rewind_ending_music()


# ---------- ENDING MUSIC HELPERS ----------

func _rewind_ending_music() -> void:
	"""Restart the ending music from the beginning (after a kill during countdown)."""
	var player: AudioStreamPlayer = get_node_or_null("MusicPlayer")
	if is_instance_valid(player):
		player.stop()
		player.play(0.0)
		print("GameMap: Rewound ending music (kill during countdown)")


func _restore_map_music() -> void:
	"""Stop ending music and restore normal map music (kill pushed past 31s)."""
	if _lms_active:
		# During the LMS finale the LMS track stays; don't restore map music.
		return
	var ending_player: AudioStreamPlayer = get_node_or_null("MusicPlayer")
	if is_instance_valid(ending_player):
		ending_player.stop()
		ending_player.queue_free()
	
	_ending_music_switched = false
	
	var music_path: String = "res://The Darkness Of The Grasslands assets/Music/Maps/The Test/Test_map_music.wav"
	if not ResourceLoader.exists(music_path):
		return
	var stream: AudioStream = load(music_path)
	if not stream:
		return
	
	var player := AudioStreamPlayer.new()
	player.name = "MapMusicPlayer"
	player.stream = stream
	player.autoplay = true
	player.bus = &"Music"
	player.volume_db = -12.0  # Lowered so rhythm-puzzle BPM audio stays audible
	player.finished.connect(_on_map_music_finished)
	add_child(player)
	print("GameMap: Restored map music (kill pushed timer past 31s)")


# ═══════════════ LMS (LAST MAN STANDING) FINALE ═══════════════

func _start_lms() -> void:
	"""Begin the Last-Man-Standing finale: special LMS music + VFX glued to screen.
	Only triggers once, when 1 killer + 1 survivor remain."""
	if _lms_active or _round_ended:
		return
	_lms_active = true
	print("GameMap: LMS — 1 killer + 1 survivor remain. Starting finale.")

	# Mute any chase theme immediately — the LMS track is now the sole score.
	_silence_all_chase()

	# Change the match clock to the length of the LMS music: the countdown restarts
	# from the LMS track's duration so the finale (and round) fits the song.
	var lms_duration: float = LMS_MUSIC_DURATION
	var lms_stream: AudioStream = null
	if ResourceLoader.exists(LMS_MUSIC_PATH):
		lms_stream = load(LMS_MUSIC_PATH)
		if is_instance_valid(lms_stream) and lms_stream.get_length() > 0.0:
			lms_duration = lms_stream.get_length()
	if lms_duration > 0.0:
		# Animate the match clock up or down to the LMS song length with a
		# dark-red screen while it runs, instead of instantly jumping the timer.
		_bonus_target = 0.0
		_timer_pause_remaining = 0.0
		_lms_transition_active = true
		_lms_transition_target = lms_duration
		_lms_transition_timer = 0.0
		if match_timer:
			match_timer.paused = true  # hold the countdown while the clock animates
		_show_lms_transition_overlay()
		print("GameMap: LMS — animating match clock to ", lms_duration, "s (LMS music length)")

	# Stop background map music + ending music so the LMS track is the sole score.
	for n: String in ["MapMusicPlayer", "MusicPlayer"]:
		var mp: AudioStreamPlayer = get_node_or_null(n)
		if is_instance_valid(mp):
			# Fade quickly rather than cut.
			var fade := create_tween()
			fade.tween_property(mp, "volume_db", -80.0, 0.4)
			fade.tween_callback(mp.stop)

	# If the LMS kick-in happened while the generic match-ending effects were
	# already showing (kill during the final 30s), hide them — the LMS finale
	# owns the ending now, so no ending vignette / Violentgrass ending screen may
	# linger beneath the LMS VFX or pop back in.
	for overlay: Node in [_ending_vignette, _ending_screen_bg, _ending_screen_overlay,
			_ending_red_left, _ending_red_right]:
		if is_instance_valid(overlay):
			overlay.visible = false
	_ending_red_active = false
	_ending_screen_created = false
	_ending_music_switched = false

	# Play the special Greengrass/Violentgrass LMS track.
	if not ResourceLoader.exists(LMS_MUSIC_PATH):
		push_error("GameMap: LMS music not found: ", LMS_MUSIC_PATH)
	else:
		_lms_music_player = AudioStreamPlayer.new()
		_lms_music_player.name = "LmsMusicPlayer"
		_lms_music_player.stream = lms_stream
		_lms_music_player.bus = &"Music"
		_lms_music_player.volume_db = -8.0
		_lms_music_player.autoplay = true
		_lms_music_player.finished.connect(_on_lms_music_loop)
		add_child(_lms_music_player)

	# Glue the ViolentBells VFX to the camera (full-screen overlay, resized to cover).
	_show_lms_vfx()

	# Create the circular red heart-pulse overlay (starts transparent; it throbs
	# in sync with the camera heartbeat via _update_lms_heartbeat).
	_show_lms_heartbeat_pulse()

	# Give each remaining duelist their signature LMS aura: red/black for the
	# Violentgrass killer, green/black for the Greengrass survivor.
	_apply_lms_auras()


func _update_lms_timer_transition(delta: float) -> void:
	"""Animate the match clock up or down toward the LMS song length, keeping the
	screen dark red while it runs, then resume the countdown when it arrives."""
	if not _lms_transition_active:
		return

	# Keep the dark-red overlay at full strength during the animation.
	if is_instance_valid(_lms_transition_overlay):
		var a: float = _lms_transition_overlay.modulate.a
		a = minf(a + delta * 4.0, LMS_TRANSITION_ALPHA)
		_lms_transition_overlay.modulate = Color(1, 1, 1, a)

	_lms_transition_timer += delta
	while _lms_transition_timer >= LMS_TRANSITION_TICK_RATE and _time_remaining != _lms_transition_target:
		_lms_transition_timer -= LMS_TRANSITION_TICK_RATE
		if _time_remaining < _lms_transition_target:
			_time_remaining = min(_time_remaining + 1.0, _lms_transition_target)
		else:
			_time_remaining = max(_time_remaining - 1.0, _lms_transition_target)
		_timer_flash_red = 0.3
		_update_timer_label()

	if _time_remaining == _lms_transition_target:
		_finish_lms_timer_transition()


func _show_lms_transition_overlay() -> void:
	"""Create the full-screen dark-red overlay shown while the LMS clock animates
	to the LMS song length."""
	if is_instance_valid(_lms_transition_overlay):
		return
	var overlay := ColorRect.new()
	overlay.name = "LmsTransitionOverlay"
	overlay.position = Vector2(0, 0)
	overlay.size = Vector2(1280, 720)
	overlay.color = Color(0.35, 0.0, 0.0, 1.0)  # dark red
	overlay.modulate = Color(1, 1, 1, 0.0)       # starts transparent, ramps in
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(overlay)
	_lms_transition_overlay = overlay


func _finish_lms_timer_transition() -> void:
	"""End the LMS clock transition: resume the countdown and fade the red out."""
	_lms_transition_active = false
	_lms_transition_target = 0.0
	_lms_transition_timer = 0.0
	if match_timer:
		match_timer.paused = false
	if is_instance_valid(_lms_transition_overlay):
		var tween := create_tween()
		tween.tween_property(_lms_transition_overlay, "modulate:a", 0.0, LMS_TRANSITION_FADE_OUT)
		tween.tween_callback(_lms_transition_overlay.queue_free)
		_lms_transition_overlay = null


func _apply_lms_auras() -> void:
	"""Apply the red/black aura to the Violentgrass killer and the green/black
	aura to the Greengrass survivor(s) once LMS begins."""
	var violent: Node2D = null
	var green_list: Array[Node2D] = []
	# The human player carries one of the two roles.
	if is_instance_valid(_player):
		if _character_name == "Violentgrass":
			violent = _player
		else:
			green_list.append(_player)
	# The killer bot is always Violentgrass.
	if is_instance_valid(_killer_bot):
		violent = _killer_bot
	# Survivor bots are always Greengrass.
	for bot: Node2D in _survivor_bots:
		if is_instance_valid(bot):
			green_list.append(bot)

	if violent:
		_apply_aura_to(violent, Color(0.85, 0.05, 0.05, 1.0), "Violentgrass aura (red/black)")
	for g: Node2D in green_list:
		_apply_aura_to(g, Color(0.05, 0.8, 0.25, 1.0), "Greengrass aura (green/black)")


func _apply_aura_to(character: Node2D, color: Color, label: String) -> void:
	"""Attach the aura rim-glow shader to a character's AnimatedSprite2D."""
	var spr: AnimatedSprite2D = character.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if not is_instance_valid(spr):
		return
	var shade := ShaderMaterial.new()
	shade.shader = LMS_AURA_SHADER
	shade.set_shader_parameter("aura_color", color)
	shade.set_shader_parameter("aura_strength", 1.0)
	shade.set_shader_parameter("enabled", true)
	spr.material = shade
	# Track for cleanup (so freeing characters doesn't leave dangling refs).
	_aura_nodes[character] = spr
	print("GameMap: Applied ", label)


func _clear_lms_auras() -> void:
	"""Remove every LMS aura shader so no character keeps a colored glow outside
	the finale (and so characters freed on scene-change aren't left hanging)."""
	for character: Node in _aura_nodes.keys():
		# The character node may already be freed when the round ends mid-
		# elimination (e.g. the timer runs out right as a survivor dies). Using a
		# freed node as a dict key crashes, so skip it before the lookup.
		if not is_instance_valid(character):
			continue
		var spr: AnimatedSprite2D = _aura_nodes[character]
		if is_instance_valid(spr):
			spr.material = null
	_aura_nodes.clear()


func _on_lms_music_loop() -> void:
	"""Loop the LMS track until the match ends."""
	if is_instance_valid(_lms_music_player):
		_lms_music_player.play()


func _show_lms_vfx() -> void:
	"""Create a full-screen CanvasLayer with the 2-frame ViolentBells VFX.
	Uses STRETCH_KEEP_ASPECT_COVERED so the frames 'glue' to the camera/backing
	regardless of window size (resized to cover the whole viewport)."""
	if _lms_vfx_layer and is_instance_valid(_lms_vfx_layer):
		return
	if not ResourceLoader.exists(LMS_VFX_FRAME_1) or not ResourceLoader.exists(LMS_VFX_FRAME_2):
		push_error("GameMap: LMS VFX frames not found.")
		return

	_lms_vfx_layer = CanvasLayer.new()
	_lms_vfx_layer.name = "LmsVfxLayer"
	_lms_vfx_layer.layer = 60  # Above chase/gameplay, below HUD (120+)
	add_child(_lms_vfx_layer)

	_lms_vfx_rect = TextureRect.new()
	_lms_vfx_rect.name = "LmsVfx"
	_lms_vfx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lms_vfx_rect.texture = load(LMS_VFX_FRAME_1)
	_lms_vfx_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lms_vfx_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_lms_vfx_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Start fully transparent on purpose — the fade-in-to-visible is driven every
	# frame by _update_lms_vfx (lerped alpha), so it fades in smoothly FIRST, and
	# later fades back OUT when the killer gets near the survivor.
	_lms_vfx_rect.modulate.a = 0.0
	_lms_vfx_layer.add_child(_lms_vfx_rect)

	_lms_alpha_current = 0.0
	_lms_alpha_target = LMS_VFX_ALPHA

	_lms_vfx_timer = 0.0
	_lms_vfx_show_frame2 = false


func _update_lms_vfx(delta: float) -> void:
	"""Alternate the 2 VFX frames on a timer while LMS is active, and drive the
	overlay alpha: it fades IN when LMS starts (so it never pops in), and fades
	OUT when the killer is near the survivor (so the final fight is visible)."""
	if not _lms_active or not is_instance_valid(_lms_vfx_rect):
		return

	# Proximity-based alpha: fade out when the killer closes in on the survivor.
	_lms_alpha_target = LMS_VFX_ALPHA
	var killer_pos: Vector2 = _get_lms_killer_position()
	var survivor_pos: Vector2 = _get_lms_survivor_position()
	if killer_pos != Vector2.INF and survivor_pos != Vector2.INF:
		if killer_pos.distance_to(survivor_pos) <= LMS_VFX_FADE_DISTANCE:
			_lms_alpha_target = 0.0

	# Smoothly lerp the actual alpha toward the target (covers both the initial
	# fade-in and the near-killer fade-out).
	_lms_alpha_current = lerpf(_lms_alpha_current, _lms_alpha_target,
			minf(delta * LMS_VFX_FADE_SPEED, 1.0))
	_lms_vfx_rect.modulate.a = _lms_alpha_current

	# Frame alternation (2-frame animation).
	_lms_vfx_timer += delta
	if _lms_vfx_timer < 1.0 / LMS_VFX_FPS:
		return
	_lms_vfx_timer -= 1.0 / LMS_VFX_FPS
	_lms_vfx_show_frame2 = not _lms_vfx_show_frame2
	_lms_vfx_rect.texture = load(LMS_VFX_FRAME_2 if _lms_vfx_show_frame2 else LMS_VFX_FRAME_1)


func _show_lms_heartbeat_pulse() -> void:
	"""Create the full-screen circular red fade that throbs with the LMS camera
	heartbeat. Transparent by default; _update_lms_heartbeat drives its shader
	intensity every frame so it pulses in sync with the zoom pulse."""
	if _lms_pulse_layer and is_instance_valid(_lms_pulse_layer):
		return
	if not ResourceLoader.exists(LMS_HEARTBEAT_PULSE_SHADER):
		push_error("GameMap: heartbeat pulse shader not found.")
		return

	_lms_pulse_layer = CanvasLayer.new()
	_lms_pulse_layer.name = "LmsHeartbeatPulseLayer"
	_lms_pulse_layer.layer = 61  # Just above the VFX layer (60), below HUD (120+)
	add_child(_lms_pulse_layer)

	_lms_pulse_mat = ShaderMaterial.new()
	_lms_pulse_mat.shader = load(LMS_HEARTBEAT_PULSE_SHADER)
	_lms_pulse_mat.set_shader_parameter("intensity", 0.0)
	# Match the viewport aspect so the circular fade stays a true circle.
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.y > 0.0:
		_lms_pulse_mat.set_shader_parameter("aspect", vp_size.x / vp_size.y)

	_lms_pulse_rect = ColorRect.new()
	_lms_pulse_rect.name = "LmsHeartbeatPulse"
	_lms_pulse_rect.material = _lms_pulse_mat
	_lms_pulse_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lms_pulse_rect.color = Color(1, 1, 1, 1)
	_lms_pulse_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lms_pulse_layer.add_child(_lms_pulse_rect)

	_lms_pulse_current = 0.0


func _get_lms_killer_position() -> Vector2:
	"""World position of the LMS killer: the human player if they're the killer,
	otherwise the killer bot. Returns Vector2.INF if unavailable."""
	if _character_name == "Violentgrass" or (GameState != null and GameState.is_killer):
		if is_instance_valid(_player):
			return _player.global_position
		return Vector2.INF
	if is_instance_valid(_killer_bot):
		return _killer_bot.global_position
	return Vector2.INF


func _get_lms_survivor_position() -> Vector2:
	"""World position of the LMS survivor: the human player if they're the
	survivor, otherwise the first alive survivor bot. Returns Vector2.INF if
	unavailable."""
	if _character_name != "Violentgrass" and not (GameState != null and GameState.is_killer):
		if is_instance_valid(_player):
			return _player.global_position
		return Vector2.INF
	for bot: Node2D in _survivor_bots:
		if is_instance_valid(bot) and bot.has_method("is_alive"):
			if bot.is_alive():
				return bot.global_position
		elif is_instance_valid(bot):
			return bot.global_position
	return Vector2.INF


func _update_lms_heartbeat(delta: float) -> void:
	"""LMS end-of-song camera drama, driven by the MUSIC'S OWN PLAYBACK position
	(never the match countdown):
	- At 26.5s of music played: zoom in a little; at 27s of music: zoom back out
	  (a quick pinch near the 26.5s mark of the song).
	- While the song still has LMS_HEARTBEAT_FROM (1m33s) left: gentle screen
	  zoom in/out at a constant 200 BPM, with a small amplitude so players
	  don't get motion sick.
	"""
	if not _lms_active or _round_ended:
		return
	if not is_instance_valid(_player):
		return
	var zoom_ctrl: Node = _player.get_node_or_null("ZoomController")
	if not is_instance_valid(zoom_ctrl) or not zoom_ctrl.has_method("set_zoom_silent"):
		return

	# Read the LMS track's playback position (this is the timeline we follow,
	# NOT the match clock). If the player is missing, bail out and leave zoom.
	if not is_instance_valid(_lms_music_player):
		return
	var pos: float = _lms_music_player.get_playback_position()
	var song_len: float = LMS_MUSIC_DURATION
	if is_instance_valid(_lms_music_player.stream) and _lms_music_player.stream.get_length() > 0.0:
		song_len = _lms_music_player.stream.get_length()

	# One-shot music pinch: zoom in a little at 26.5s, zoom back out at 27s.
	if not _lms_pinch_done:
		if pos >= LMS_PINCH_OUT_AT:
			# At 27s of music → zoom back out (and never run again).
			_lms_pinch_done = true
			zoom_ctrl.set_zoom_silent(zoom_ctrl.default_zoom, true)
		elif pos >= LMS_PINCH_IN_AT:
			# Between 26.5s and 27s of music → zoom in a little.
			zoom_ctrl.set_zoom_silent(zoom_ctrl.default_zoom / LMS_PINCH_ZOOM_IN_MULT, true)

	# Heartbeat WINDOW: it must NEVER start before the 26.5/27s pinch, so we use
	# whichever is later — the song reaching the 1m33s-remaining point (93s left)
	# OR the 27s-in pinch already having happened. For our ~99.7s track the pinch
	# comes first, so the heartbeat only begins at ~27s of music and runs to the
	# end. For a longer track, "1m33s till it ends" would take over automatically.
	var heartbeat_start: float = maxf(LMS_PINCH_OUT_AT, song_len - LMS_HEARTBEAT_FROM)
	var remaining: float = song_len - pos
	if pos < heartbeat_start or remaining <= 0.5:
		_lms_heartbeat_active = false
		return
	_lms_heartbeat_active = true

	# Constant 200 BPM from the moment the heartbeat starts (27s) until the song
	# ends (user requested 200 BPM).
	var total_span: float = maxf(song_len - heartbeat_start, 0.001)
	var progress: float = clampf((pos - heartbeat_start) / total_span, 0.0, 1.0)
	var bpm: float = lerpf(LMS_HEARTBEAT_BPM_START, LMS_HEARTBEAT_BPM_END, progress)
	var beat_seconds: float = 60.0 / bpm  # one full in+out cycle per beat

	_lms_heartbeat_phase += delta
	# One full cycle per beat: zoom in for the first half, out for the second.
	var cycle: float = fmod(_lms_heartbeat_phase, beat_seconds)
	var half: float = beat_seconds * 0.5
	if cycle < half:
		var t0: float = cycle / half
		zoom_ctrl.set_zoom_silent(zoom_ctrl.default_zoom / (1.0 + LMS_HEARTBEAT_AMOUNT * (1.0 - t0)), true)
	else:
		var t1: float = (cycle - half) / half
		zoom_ctrl.set_zoom_silent(zoom_ctrl.default_zoom / (1.0 - LMS_HEARTBEAT_AMOUNT * t1), true)


func _update_lms_pulse(delta: float) -> void:
	"""Drive the circular red heart-pulse overlay to throb in sync with the LMS
	camera heartbeat. Uses the same beat phase (same BPM) as _update_lms_heartbeat,
	so the red fades in and out with the zoom pulse. When the heartbeat is off
	(round over, not yet entered, song ending) it smoothly fades the red out."""
	if not is_instance_valid(_lms_pulse_layer) or not is_instance_valid(_lms_pulse_rect):
		return

	var target: float = 0.0
	if _lms_active and _lms_heartbeat_active and not _round_ended:
		# Same constant 200 BPM used by the camera heartbeat.
		var beat_seconds: float = 60.0 / LMS_HEARTBEAT_BPM_START
		var cycle: float = fmod(_lms_heartbeat_phase, beat_seconds)
		# Thump hardest at the beat boundary (aligned with the zoom-in peak),
		# then decay through the rest of the beat — a heartbeat.
		var decay: float = 1.0 - (cycle / beat_seconds)
		target = LMS_HEARTBEAT_PULSE_MAX * pow(maxf(decay, 0.0), 1.5)

	_lms_pulse_current = lerpf(_lms_pulse_current, target,
			minf(delta * LMS_HEARTBEAT_PULSE_FADE, 1.0))
	if is_instance_valid(_lms_pulse_mat):
		_lms_pulse_mat.set_shader_parameter("intensity", _lms_pulse_current)


func _trigger_lms_kill_zoom() -> void:
	"""Corrected 2→1 finale sequence, in order:
	1) While the killer is killing a survivor → zoom in VERY tight on the kill.
	2) Hold tight briefly.
	3) Zoom back out.
	4) Once the zoom-out completes → reveal the survivor's location to both sides
	   and start the LMS finale (VFX + LMS music + match clock set to the song).
	"""
	if not is_instance_valid(_player):
		_start_lms()
		return
	var zoom_ctrl: Node = _player.get_node_or_null("ZoomController")
	if not is_instance_valid(zoom_ctrl) or not zoom_ctrl.has_method("set_zoom"):
		_start_lms()
		return
	# 1) Zoom in VERY tight on the kill.
	zoom_ctrl.set_zoom(LMS_KILL_ZOOM_IN, true)
	# 2) Hold tight.
	await get_tree().create_timer(LMS_KILL_ZOOM_HOLD).timeout
	if _round_ended:
		return
	# 3) Zoom back out.
	if is_instance_valid(zoom_ctrl) and zoom_ctrl.has_method("restore_normal_zoom"):
		zoom_ctrl.restore_normal_zoom()
	# 4) Wait for the zoom-out animation to finish, then reveal + start LMS.
	await get_tree().create_timer(0.7).timeout
	if _round_ended:
		return
	_show_lms_reveal()
	_start_lms()


func _show_lms_reveal() -> void:
	"""After the kill-zoom zooms back out, reveal positions so BOTH sides know
	where the survivor is: the killer sees an arrow to the last surviving survivor,
	and the surviving survivor sees an arrow to the killer."""
	if not is_instance_valid(_player):
		return
	var is_killer_role: bool = _character_name == "Violentgrass" or (GameState.is_killer if GameState else false)
	var target_pos: Vector2 = Vector2.ZERO
	if is_killer_role:
		# Killer: point to the last surviving survivor bot.
		for bot: Node2D in _survivor_bots:
			if is_instance_valid(bot):
				target_pos = bot.global_position
				break
	else:
		# Survivor: point to the killer (AI killer bot or human killer).
		if is_instance_valid(_killer_bot):
			target_pos = _killer_bot.global_position
		elif _character_name == "Violentgrass":
			target_pos = _player.global_position
	if target_pos == Vector2.ZERO:
		return
	_show_lms_reveal_arrow(target_pos)


func _show_lms_reveal_arrow(target_pos: Vector2) -> void:
	"""Draw a temporary edge-of-screen arrow pointing to target_pos on the HUD,
	shown for BOTH roles (unlike the survivor-only teleport indicator)."""
	if not is_instance_valid(_player):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var dir: Vector2 = (target_pos - _player.global_position).normalized() if is_instance_valid(_player) else Vector2.RIGHT

	var arrow_label := Label.new()
	arrow_label.name = "LmsRevealArrow"
	arrow_label.text = "▶"
	arrow_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2, 0.95))
	arrow_label.add_theme_font_size_override("font_size", 40)
	arrow_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	arrow_label.add_theme_constant_override("outline_size", 4)
	arrow_label.size = Vector2(44, 44)
	arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var margin: float = 60.0
	var edge_x: float = viewport_size.x * 0.5 + dir.x * (viewport_size.x * 0.5 - margin)
	var edge_y: float = viewport_size.y * 0.5 + dir.y * (viewport_size.y * 0.5 - margin)
	edge_x = clampf(edge_x, margin, viewport_size.x - margin)
	edge_y = clampf(edge_y, margin, viewport_size.y - margin)
	arrow_label.position = Vector2(edge_x - 22, edge_y - 22)
	var angle: float = atan2(dir.y, dir.x)
	arrow_label.pivot_offset = Vector2(22, 22)
	arrow_label.rotation = angle

	$HUD.add_child(arrow_label)

	# Fade out then remove.
	var tween := create_tween()
	tween.tween_interval(LMS_REVEAL_DURATION - 0.5)
	tween.tween_property(arrow_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void:
		if is_instance_valid(arrow_label):
			arrow_label.queue_free()
	)


func _on_bot_hp_changed(current_hp: float, _max_hp: float, bot: Node2D) -> void:
	"""Track AI survivor bot HP and trigger elimination when HP reaches 0."""
	if current_hp > 0.0:
		return
	if not is_instance_valid(bot):
		return
	if not _survivor_bots.has(bot):
		return
	
	# Captured BEFORE decrement to detect the 2→1 kill (zoom punch moment).
	var was_two_left: bool = _alive_survivor_bot_count == 2
	
	# Mark bot as eliminated
	_alive_survivor_bot_count -= 1
	_survivor_bots.erase(bot)
	_refresh_survivor_cache()
	
	# Fling the dead body around the map (away from whoever killed it), then fade
	# it out and remove it after a few seconds. The controller handles the physics.
	var killer_pos: Vector2 = bot.global_position
	if is_instance_valid(_player) and _character_name == "Violentgrass":
		killer_pos = _player.global_position
	elif is_instance_valid(_killer_bot):
		killer_pos = _killer_bot.global_position
	var fling_dir: Vector2 = (bot.global_position - killer_pos).normalized()
	if fling_dir == Vector2.ZERO:
		fling_dir = Vector2.RIGHT.rotated(randf() * TAU)
	fling_dir = fling_dir.rotated(randf_range(-0.6, 0.6))
	# Funny Ragdoll setting doubles the fling strength (exactly 100% stronger).
	var fling_mult: float = 2.0 if (GameState != null and GameState.ragdoll) else 1.0
	if bot.has_method("play_death_fling"):
		bot.play_death_fling(fling_dir, fling_mult)
		print("GameMap: FLING triggered for ", bot.name, " dir=", fling_dir, " mult=", fling_mult)
	
	print("GameMap: Survivor bot eliminated — %d bot(s) remaining" % _alive_survivor_bot_count)
	_on_survivor_eliminated("SurvivorBot")
	
	# LMS trigger: when it drops to exactly 1 survivor (1 killer + 1 survivor left).
	# If this kill took it from 2 → 1, run the corrected kill-zoom sequence:
	# zoom in tight on the kill → zoom out → THEN reveal + VFX + LMS music + clock.
	# (kill-zoom now calls _start_lms() itself after the zoom-out completes.)
	if _alive_survivor_bot_count == 1 and not _lms_active:
		if was_two_left:
			_trigger_lms_kill_zoom()
		else:
			_start_lms()
	
	# Check if all survivors (human + bots) are eliminated
	_check_all_survivors_eliminated()


func _check_all_survivors_eliminated() -> void:
	"""End the match when all survivors (human + AI bots) are eliminated."""
	var is_killer: bool = _character_name == "Violentgrass"
	if is_killer:
		# The human IS the killer — survivors are only the bots.
		# The killer wins as soon as all bot survivors are eliminated.
		if _alive_survivor_bot_count <= 0:
			print("GameMap: All survivors eliminated — ending match")
			match_timer.stop()
			_killer_won = true
			if not _round_ended:
				match_ended.emit()
				_end_match()
		return
	# Human is a survivor — all survivors gone only when bots AND human are dead.
	if _alive_survivor_bot_count > 0:
		return
	var player_hp: float = _player.get("current_hp") if is_instance_valid(_player) and "current_hp" in _player else 0.0
	if player_hp <= 0.0:
		print("GameMap: All survivors eliminated — ending match")
		match_timer.stop()
		_killer_won = true
		if not _round_ended:
			match_ended.emit()
			_end_match()


# ---------- EVERYONE-DEAD ROUND-END GUARANTEE ----------

func _on_killer_bot_hp_changed(current_hp: float, _max_hp: float) -> void:
	"""Survivor mode: when the AI killer bot's HP hits 0, the survivor wins —
	end the round immediately (not just when the timer runs out)."""
	if current_hp > 0.0:
		return
	if _round_ended:
		return
	_killer_bot_eliminated = true
	print("GameMap: Killer bot eliminated — survivors win. Ending match.")
	match_timer.stop()
	_killer_won = false
	if not _round_ended:
		match_ended.emit()
		_end_match()


func _check_everyone_dead() -> void:
	"""GUARANTEED "everyone is dead" round-end, checked every frame from _process.
	Ends the round the moment every combatant is eliminated, in BOTH roles:
	- Killer (Violentgrass): all survivor bots dead → killer wins.
	- Survivor (Greengrass): AI killer bot dead → survivors win, OR human survivor
	  dead → round ends (also handled by the death sequence)."""
	if _round_ended or not _match_live:
		return
	var is_killer: bool = _character_name == "Violentgrass"
	if is_killer:
		if _alive_survivor_bot_count <= 0:
			print("GameMap: (guaranteed) All survivors eliminated — ending match")
			match_timer.stop()
			_killer_won = true
			if not _round_ended:
				match_ended.emit()
				_end_match()
		return
	# Survivor mode: killer bot gone means the survivor won.
	if _killer_bot_eliminated or (_killer_bot != null and not is_instance_valid(_killer_bot)):
		print("GameMap: (guaranteed) Killer bot eliminated — survivors win. Ending match.")
		match_timer.stop()
		_killer_won = false
		if not _round_ended:
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
		# Timer-out is NOT a killer-win-by-elimination — no killer outro here.
		_killer_won = false
		if not _round_ended:
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
	
	if InputSystem.is_pressed("interact") and not _e_was_pressed and not _puzzle_open:
		_e_was_pressed = true
		_open_puzzle_for_area(_current_interactable)
	elif not InputSystem.is_pressed("interact"):
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
	
	# Rewards: +$5, +1 ring, and +10 EXP per puzzle level completed
	var gs = get_node("/root/GameState")
	var rings_per_level: int = 1
	var money_per_level: int = 5
	var exp_per_level: int = 10
	if gs != null:
		gs.add_money(money_per_level)
		var username: String = gs.logged_in_username
		if username != "":
			var current_rings: int = gs.get_player_rings(username)
			gs.set_player_rings(username, current_rings + rings_per_level)
		# Award EXP to the character being played
		var char_name: String = gs.selected_survivor if not gs.is_killer else gs.selected_killer
		gs.add_character_exp(char_name, exp_per_level)
		print("GameMap: Puzzle reward — +$", money_per_level, ", +", rings_per_level, " ring, +", exp_per_level, " EXP for ", char_name, " (level ", puzzle_level, ")")
		# Show floating notification
		_show_reward_popup("+" + str(exp_per_level) + " EXP (" + char_name + ")\n+$" + str(money_per_level) + " Gold")
	
	# Decrease match timer by 3.25 seconds per puzzle level (flash red) — UNLESS
	# this is an LMS finale or a straight 1v1 (survivor vs killer), where taking
	# time away for solving a puzzle is considered cheating, so no penalty applies.
	if not _lms_active and not _is_1v1:
		var deduction: float = 3.25 * puzzle_level
		_time_remaining = max(0.0, _time_remaining - deduction)
		_timer_flash_red = 1.0
		_update_timer_label()
		_force_timer_pause(0.6)
	
	# Show success text
	var prompt: Label = area.get_node_or_null("InteractPrompt")
	if prompt:
		prompt.text = "✓ Solved!"
	
	# Visual feedback: tint the area marker green
	if area.has_node("ColorRect"):
		var rect: ColorRect = area.get_node("ColorRect")
		rect.color = Color(0.2, 0.8, 0.2, 0.5)
	
	# Multiplayer: report the puzzle solve to the server
	if _multiplayer_sync:
		_multiplayer_sync.send_puzzle_solved(area_name, puzzle_level)
	
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


func _show_reward_popup(text: String) -> void:
	"""Show a floating reward notification in the HUD that drifts up and fades."""
	var hud: CanvasLayer = $HUD
	if not hud:
		return
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 1))
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.size = Vector2(300, 50)
	label.position = Vector2(490, 480)
	hud.add_child(label)
	
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 60, 2.0).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 2.0).set_delay(0.8)
	tween.chain().tween_callback(label.queue_free)


# ---------- EPILEPSY SAFE OVERLAY ----------

var _epilepsy_overlay: ColorRect = null
var _vignette_overlay: ColorRect = null

func _create_epilepsy_overlay(player: Node2D) -> void:
	"""Create epilepsy-safe desaturation overlay and damage vignette."""
	# Guard: don't create duplicates if one already exists (e.g. on role switch).
	if is_instance_valid(_epilepsy_overlay) or is_instance_valid(_vignette_overlay):
		return
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
	# Guard: don't create duplicates (e.g. on role switch).
	if is_instance_valid(_ending_vignette):
		return
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
	if _lms_active:
		# During the LMS finale the LMS track/VFX own the ending — never show
		# the generic match-ending vignette on top of it.
		return
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
	if _lms_active:
		# During the LMS finale the Violentgrass branded ending screen must not
		# appear — the LMS VFX + music own the ending instead.
		return
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
	red_left.color = Color(1, 0, 0, 0.5)
	red_left.position = Vector2(0, 0)
	red_left.size = Vector2(view_size.x * 0.5, view_size.y)
	red_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	red_left.visible = false
	hud.add_child(red_left)
	_ending_red_left = red_left
	
	var red_right := ColorRect.new()
	red_right.name = "EndingRedRight"
	red_right.color = Color(1, 0, 0, 0.5)
	red_right.position = Vector2(view_size.x * 0.5, 0)
	red_right.size = Vector2(view_size.x * 0.5, view_size.y)
	red_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	red_right.visible = false
	hud.add_child(red_right)
	_ending_red_right = red_right


func _update_match_ending_screen(delta: float) -> void:
	"""Update the ending screen: fade-in, shake intensity scales with time left, red UI flash at 18s."""
	if _lms_active:
		# During the LMS finale the Violentgrass ending screen is disabled.
		return
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
	"""Detect player HP changes to trigger the visual vignette only.
	Damage/SFX stats are owned by _on_player_hp_changed(); this must NOT
	touch _total_damage_taken or _last_hp (which would double-count)."""
	if not is_instance_valid(_player):
		return
	if not "current_hp" in _player:
		return
	var hp: float = _player.get("current_hp")
	if _last_hp >= 0 and hp < _last_hp:
		_trigger_vignette()


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
	if not panel.role_switch_requested.is_connected(_switch_role):
		panel.role_switch_requested.connect(_switch_role)
	panel.hide()  # Start hidden — toggled via "G Gui"


func _create_role_hint() -> void:
	"""Add an always-visible hint showing how to switch roles (F2) and open the
	admin panel (G Gui / F3). Makes the killer/survivor role switch discoverable."""
	var hud: CanvasLayer = $HUD
	if not hud or hud.get_node_or_null("RoleHint"):
		return
	var hint := Label.new()
	hint.name = "RoleHint"
	hint.text = "F2: Switch Killer / Survivor    |    F3 / Chat 'G Gui': Admin Panel"
	hint.position = Vector2(8, 8)
	hint.size = Vector2(660, 20)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	hint.add_theme_constant_override("shadow_offset_x", 1)
	hint.add_theme_constant_override("shadow_offset_y", 1)
	hud.add_child(hint)


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
	# "G coingive [user] <amount>" — give gold to the local player
	if trimmed.begins_with("g coingive"):
		var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
		if not chat_layer:
			return
		var parts: PackedStringArray = text.strip_edges().split(" ")
		if parts.size() < 3:
			chat_layer.add_system_message("Usage: G coingive [user] <amount>")
			return
		var amount_str: String = parts[parts.size() - 1]
		var amount: int = amount_str.to_int()
		if amount <= 0:
			chat_layer.add_system_message("Usage: G coingive [user] <amount>")
			return
		var target_user: String = ""
		if parts.size() >= 4:
			target_user = parts[2]
		var gs := GameState
		var is_self: bool = true
		if target_user != "":
			var tu: String = target_user.to_lower()
			var uname: String = gs.logged_in_username.to_lower()
			var dname: String = gs.display_name.to_lower()
			is_self = (tu == uname or tu == dname or tu == "me" or tu == "you" or tu == "self")
			if not is_self:
				chat_layer.add_system_message("Player '%s' not found locally — granting to you instead." % target_user)
		gs.add_money(amount)
		if SaveManager and SaveManager.has_method("autosave"):
			SaveManager.autosave(gs.logged_in_username)
		var who: String = gs.display_name if not gs.display_name.is_empty() else gs.logged_in_username
		chat_layer.add_system_message("Gave $%d to %s. New balance: $%d" % [amount, who, gs.player_money])
		return
	
	# "G force AI" / "G next AI" — force next killer to be AI
	if is_admin and (trimmed.begins_with("g force") or trimmed.begins_with("g next")):
		if trimmed.contains("ai"):
			if GameState.connected_to_server:
				# Send to server so it handles the command
				var nm: Node = get_node("/root/NetworkManager")
				if is_instance_valid(nm) and nm.has_method("send_admin_command"):
					var admin_cmd: String = text
					if admin_cmd.begins_with("G "):
						admin_cmd = admin_cmd.trim_prefix("G ")
					elif admin_cmd.begins_with("g "):
						admin_cmd = admin_cmd.trim_prefix("g ")
					nm.send_admin_command(admin_cmd)
				return
			else:
				# Local mode: set flag directly
				GameState.is_killer = false
				var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
				if chat_layer:
					chat_layer.add_system_message("Next killer will be AI.")
				return
	
	if is_admin and GameState.connected_to_server:
		var nm: Node = get_node("/root/NetworkManager")
		if is_instance_valid(nm) and nm.has_method("send_admin_command"):
			var admin_cmd: String = text
			if admin_cmd.begins_with("G "):
				admin_cmd = admin_cmd.trim_prefix("G ")
			elif admin_cmd.begins_with("g "):
				admin_cmd = admin_cmd.trim_prefix("g ")
			nm.send_admin_command(admin_cmd)
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
	chat_layer.add_system_message("G force AI / G next AI - Force next killer to be AI")
	chat_layer.add_system_message("G gamemode select double trouble - Toggle double trouble")
	chat_layer.add_system_message("G AUTH <pw> - Authenticate as admin")
	chat_layer.add_system_message("G Gui - Toggle admin GUI panel")
	chat_layer.add_system_message("G coingive [user] <amount> - Give gold")
	chat_layer.add_system_message("=====================")


func _determine_killer_by_rings() -> bool:
	"""Killer selection no longer depends on rings. Earning rings in a match
	never makes the player the killer. The local player starts as a SURVIVOR
	(against the AI killer bot); they can switch roles with the F2 admin/role
	switcher at any time if they want to play as the killer."""
	return false


func _on_player_attacked(_stunned: bool) -> void:
	"""Track attacks when player lands a punch."""
	_total_damage_dealt += 1.0


# ---------- DEATH SEQUENCE ----------

func _start_death_sequence() -> void:
	"""Start the death fling + fade-out sequence."""
	if _death_active:
		return
	_death_active = true
	_death_fade_progress = 0.0
	
	# ── Death fling: launch the player away from the killer ──
	if is_instance_valid(_player):
		# Find the killer to fling away from
		var killer_pos: Vector2 = _player.global_position
		if is_instance_valid(_killer_bot):
			killer_pos = _killer_bot.global_position
		var fling_dir: Vector2 = (_player.global_position - killer_pos).normalized()
		if fling_dir.length_squared() < 0.01:
			fling_dir = Vector2(randf() - 0.5, -1.0).normalized()
		# Add random wobble
		fling_dir = fling_dir.rotated(randf_range(-0.6, 0.6))
		
		# Use a Tween for the fling (bypasses physics, always works)
		var speed: float = randf_range(300.0, 500.0)
		var fling_vel: Vector2 = fling_dir * speed
		var ragdoll_mult: float = 2.0 if GameState.ragdoll else 1.0
		fling_vel *= ragdoll_mult
		
		_player.modulate = Color(0.5, 0.5, 0.5, 1.0)
		var target_pos: Vector2 = _player.global_position + fling_vel * 1.5
		var spin: float = randf_range(-4.0, 4.0)
		
		var t := _player.create_tween()
		t.set_parallel(true)
		t.tween_property(_player, "global_position", target_pos, 1.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_property(_player, "rotation", _player.rotation + spin * 3.0, 1.5)
		
		# Fade out and free after 10s
		var ft := _player.create_tween()
		ft.tween_interval(9.4)
		ft.tween_property(_player, "modulate:a", 0.0, 0.6)
		ft.tween_callback(_player.queue_free)
		_player = null
	
	# Create fade overlay on top of everything
	_death_overlay = ColorRect.new()
	_death_overlay.name = "DeathOverlay"
	_death_overlay.color = Color(0.15, 0.15, 0.15, 0.0)  # Start transparent
	_death_overlay.size = get_viewport().get_visible_rect().size
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(_death_overlay)
	
	print("GameMap: Death sequence started — player flung, fading over 5 seconds")


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
	# Guard: only end the round once.
	if _round_ended:
		return
	_round_ended = true

	# The match is over — lobby can no longer count this as an in-progress game
	# (analysis phase still shows briefly as "just ended" via the server).
	GameState.match_in_progress = false
	GameState.game_phase = "LOBBY_ANALYSIS"
	
	# Round-end reward: +1 gift ring (persistent) for every round played, plus
	# increment the player's "rounds played" counter. Applied BEFORE the killer-won
	# branch so it fires on every match end (killer-win and generic).
	var gs_gift = get_node_or_null("/root/GameState")
	if gs_gift != null:
		var uname: String = gs_gift.logged_in_username
		if not uname.is_empty():
			gs_gift.set_player_rings(uname, gs_gift.get_player_rings(uname) + ROUND_END_GIFT_RING)
			gs_gift.add_player_round(uname)
			print("GameMap: Round end — +%d gift ring, rounds played now %d" % [
				ROUND_END_GIFT_RING, gs_gift.get_player_rounds(uname)])
	
	# Store stats in GameState for the lobby to display
	GameState.show_analysis = true
	GameState.match_character_name = _character_name
	GameState.match_damage_taken = _total_damage_taken
	GameState.match_damage_dealt = _total_damage_dealt
	# Do NOT carry the LMS track into the lobby intermission. The killer-win
	# drama already plays its LMS tail inside the match (outro), and on ANY
	# match end (win or lose) the lobby should return to its normal intermission
	# tune rather than keep the LMS music playing.
	GameState.returning_from_lms = false
	
	# If the KILLER won (the last survivor died), we don't just cut to the lobby:
	# cut to black, let the LMS song's ~1:33 tail keep playing, then play
	# Violentgrass's killer OUTRO on top of it, freeze on its last frame and show
	# the match analysis over that frozen frame before returning to the lobby.
	# The LMS music must survive until the outro finishes, so defer the full
	# cleanup until the very end of the killer-win flow.
	if _killer_won:
		get_tree().paused = false
		_play_killer_win_outro()
		return

	# Generic match-end: nothing special — full cleanup, then straight to the lobby.
	_cleanup_for_lobby()
	
	# Generic match-end → lobby (no loading bar).
	get_tree().paused = false
	SceneFader.go("res://scenes/lobby.tscn", "")
	print("GameMap: Match ended — transitioning to lobby for analysis")


func _freeze_match_for_analysis() -> void:
	"""Disable ALL match gameplay so nothing (player movement, abilities,
	camera follow, bots, chase music updates) continues while the killer-win
	outro and its analysis overlay are being shown. The match stays frozen
	until the user continues to the lobby."""
	# Stop the match clock (belts-and-suspenders; clean-up already stops it).
	if match_timer:
		match_timer.stop()
	_timer_pause_remaining = 0.0
	_bonus_target = 0.0
	_bonus_tick_timer = 0.0
	# Block the human player entirely (movement + abilities + input).
	if is_instance_valid(_player):
		_player.set_physics_process(false)
		_player.set_process_unhandled_input(false)
		_player.set_process_input(false)
		_player.process_mode = Node.PROCESS_MODE_DISABLED
	# Freeze every bot too.
	if is_instance_valid(_killer_bot):
		_killer_bot.set_physics_process(false)
		_killer_bot.process_mode = Node.PROCESS_MODE_DISABLED
	for bot: Node2D in _survivor_bots:
		if is_instance_valid(bot):
			bot.set_physics_process(false)
			bot.process_mode = Node.PROCESS_MODE_DISABLED
	# Freeze chase-music / LMS updates by clearing active state.
	_chase_active_layer = -1
	_chase_layers_enabled = [false, false, false, false]
	_lms_active = false
	print("GameMap: Match frozen for killer-win outro + analysis")


func _play_killer_win_outro() -> void:
	"""Killer won (Violentgrass killed Greengrass in LMS): go BLACK instantly,
	let the final ~1:33 of the LMS song keep playing as the dramatic tail, then
	fade in the FIRST FRAME of the killer OUTRO, play it over the still-playing
	tail, freeze on its last frame, overlay the match analysis, then return to
	the lobby. The LMS music is NOT stopped here on purpose — it plays under the
	outro and is only stopped once the outro is done."""
	print("GameMap: Killer wins — black, LMS music tail, then killer OUTRO")
	# FREEZE THE WHOLE MATCH: the killer has ended the round, so no gameplay
	# (movement, abilities, camera) may continue while the outro AND the match
	# analysis are shown. It stays frozen until the analysis is dismissed.
	_freeze_match_for_analysis()

	# The LMS VFX (layer 60) and red-pulse (layer 61) overlays sit ABOVE the
	# cutscene (layer 1), so hide them so only the outro + analysis show.
	if is_instance_valid(_lms_vfx_layer):
		_lms_vfx_layer.visible = false
	if is_instance_valid(_lms_pulse_layer):
		_lms_pulse_layer.visible = false

	var hud: CanvasLayer = $HUD
	if hud:
		hud.visible = false
	if map_visual:
		map_visual.visible = false

	# Silence the regular music players but KEEP the LMS song — it's the audio
	# bed for the whole outro. (Cleanup is deferred on this path, so stop any
	# map/ending music manually; the LMS player is handled below.)
	for player_name in ["MapMusicPlayer", "MusicPlayer"]:
		var mp: AudioStreamPlayer = get_node_or_null(player_name)
		if is_instance_valid(mp):
			mp.stop()

	# The chase layers used to keep playing over the outro because
	# _freeze_match_for_analysis clears their flags but not the players
	# themselves. Stop every chase player explicitly.
	for cp: AudioStreamPlayer in _chase_players:
		if is_instance_valid(cp):
			cp.stop()
	# Also mark ending music as switched so the last-31s generic MATCH_ENDING
	# track can never start during the frozen outro (it would layer on top of the
	# LMS tail — only the LMS tail should play here).
	_ending_music_switched = true

	# Keep the LMS song playing through the outro. If more than the final ~1:33
	# (LMS_HEARTBEAT_FROM) still remains, jump to the start of that dramatic tail
	# so the outro always lands on the best part of the track.
	if is_instance_valid(_lms_music_player):
		var song_len: float = LMS_MUSIC_DURATION
		if is_instance_valid(_lms_music_player.stream) and _lms_music_player.stream.get_length() > 0.0:
			song_len = _lms_music_player.stream.get_length()
		var remaining: float = song_len - _lms_music_player.get_playback_position()
		if remaining > LMS_HEARTBEAT_FROM + 0.5:
			_lms_music_player.seek(maxf(song_len - LMS_HEARTBEAT_FROM, 0.0))
		if not _lms_music_player.playing:
			_lms_music_player.play()

	# Phase 1 — GO BLACK INSTANTLY, then FADE IN THE FIRST FRAME OF THE OUTRO.
	# The CutscenePlayer builds a full-screen black background immediately (so the
	# screen goes black the moment it's added) and its fade overlay starts opaque
	# black, revealing the FIRST FRAME over fade_in_duration — then the outro plays.
	var outro_folder: String = "res://The Darkness Of The Grasslands assets/Cutscenes/Killer outros/Violentgrass+Killer+Outro"
	var cutscene := CutscenePlayer.new()
	cutscene.name = "KillerWinOutroCutscene"
	cutscene.fps = 8.0  # 38 frames at 8fps ≈ 4.75s
	cutscene.fade_in_duration = 1.0  # first frame fades in from the instant black
	cutscene.hold_on_last_frame = true  # freeze so analysis can overlay it
	add_child(cutscene)
	cutscene.play_cutscene(outro_folder, "")

	await cutscene.finished

	# Outro done and frozen on its last frame — the LMS tail has played out, so
	# stop the music now (the analysis is shown silent, then we leave for lobby).
	if is_instance_valid(_lms_music_player):
		_lms_music_player.stop()

	# Cutscene is now frozen on its last frame — lay the analysis over it.
	_show_killer_win_analysis()


func _show_killer_win_analysis() -> void:
	"""Build a compact ROUND-SUMMARY analysis over the frozen killer-outro frame,
	then continue to the lobby when dismissed."""
	var layer := CanvasLayer.new()
	layer.name = "KillerWinAnalysis"
	layer.layer = 15
	add_child(layer)
	
	# Dim behind the panel (keeps the frozen outro frame partially visible)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchors_preset = Control.PRESET_FULL_RECT
	layer.add_child(dim)
	
	# Panel
	var panel := Control.new()
	panel.name = "Panel"
	panel.position = Vector2(390, 130)
	panel.size = Vector2(500, 460)
	layer.add_child(panel)
	
	var bg := TextureRect.new()
	bg.name = "Bg"
	bg.size = Vector2(500, 460)
	bg.texture = load("res://The Darkness Of The Grasslands assets/UI/Lobby/Shop and inventory background UI.png")
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(1, 1, 1, 0.9)
	panel.add_child(bg)
	
	var inner := ColorRect.new()
	inner.name = "Inner"
	inner.size = Vector2(480, 300)
	inner.position = Vector2(10, 80)
	inner.color = Color(0.05, 0.05, 0.1, 0.8)
	panel.add_child(inner)
	
	var title := Label.new()
	title.name = "Title"
	title.text = "KILLER WINS — ROUND SUMMARY"
	title.position = Vector2(20, 20)
	title.size = Vector2(460, 40)
	title.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	
	var sep := ColorRect.new()
	sep.position = Vector2(50, 65)
	sep.size = Vector2(400, 2)
	sep.color = Color(1, 1, 1, 0.3)
	panel.add_child(sep)
	
	# Character name
	var name_lbl := Label.new()
	name_lbl.name = "NameLabel"
	name_lbl.text = GameState.match_character_name
	name_lbl.position = Vector2(20, 100)
	name_lbl.size = Vector2(460, 34)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(name_lbl)
	
	# Stats
	var stats_data: Array[Dictionary] = [
		{"label": "Damage Taken", "value": "%d" % GameState.match_damage_taken},
		{"label": "Punches Landed", "value": "%d" % GameState.match_damage_dealt},
	]
	var stat_y: float = 165.0
	for s in stats_data:
		var lbl := Label.new()
		lbl.text = s["label"]
		lbl.position = Vector2(70, stat_y)
		lbl.size = Vector2(250, 28)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		lbl.add_theme_font_size_override("font_size", 16)
		panel.add_child(lbl)
		var val := Label.new()
		val.text = s["value"]
		val.position = Vector2(320, stat_y)
		val.size = Vector2(100, 28)
		val.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		val.add_theme_font_size_override("font_size", 16)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(val)
		stat_y += 36.0
	
	var footer := Label.new()
	footer.text = "MATCH COMPLETE"
	footer.position = Vector2(20, 250)
	footer.size = Vector2(460, 30)
	footer.add_theme_color_override("font_color", Color(0.5, 1, 0.5, 1))
	footer.add_theme_font_size_override("font_size", 18)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(footer)
	
	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.position = Vector2(150, 330)
	continue_btn.size = Vector2(200, 44)
	continue_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	continue_btn.add_theme_font_size_override("font_size", 20)
	continue_btn.pressed.connect(_continue_after_killer_win)
	panel.add_child(continue_btn)
	
	# Zoom-in animation (like the lobby's analysis overlay)
	panel.scale = Vector2(0.8, 0.8)
	panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "scale", Vector2(1, 1), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.2)
	# Keep a reference so the layer can be cleaned up on continue
	_killer_win_analysis_layer = layer


func _continue_after_killer_win() -> void:
	"""Dismiss the killer-win analysis and return to the lobby (no loading bar,
	since the analysis was already shown over the outro frame)."""
	if is_instance_valid(_killer_win_analysis_layer):
		_killer_win_analysis_layer.queue_free()
	_killer_win_analysis_layer = null
	# Analysis already shown here — don't re-show it inside the lobby.
	GameState.show_analysis = false
	get_tree().paused = false
	SceneFader.go("res://scenes/lobby.tscn", "")
	print("GameMap: Killer-win analysis done — transitioning to lobby")


func _cleanup_for_lobby() -> void:
	"""Stop the timer, silence all music, free overlays/bots so the round fully ends."""
	# Stop the match clock
	if match_timer:
		match_timer.stop()
	_timer_pause_remaining = 0.0
	_bonus_target = 0.0
	_bonus_tick_timer = 0.0

	# Strip the LMS auras off any characters so they don't linger into the lobby.
	_clear_lms_auras()
	
	# Silence and free all chase layer players
	for p: AudioStreamPlayer in _chase_players:
		if is_instance_valid(p):
			p.stop()
			p.queue_free()
	_chase_players.clear()
	_chase_active_layer = -1
	_chase_layers_enabled = [false, false, false, false]
	
	# Silence/free map music + ending music players
	for player_name in ["MapMusicPlayer", "MusicPlayer", "LmsMusicPlayer"]:
		var mp: AudioStreamPlayer = get_node_or_null(player_name)
		if is_instance_valid(mp):
			mp.stop()
			mp.queue_free()
	_ending_music_switched = false
	# Free the LMS VFX overlay
	if is_instance_valid(_lms_vfx_layer):
		_lms_vfx_layer.queue_free()
	_lms_vfx_layer = null
	_lms_vfx_rect = null
	_lms_active = false
	_lms_vfx_timer = 0.0
	_lms_vfx_show_frame2 = false
	_lms_alpha_current = 0.0
	_lms_alpha_target = 0.0
	_lms_heartbeat_phase = 0.0
	_lms_heartbeat_active = false
	_lms_pinch_done = false
	# Free the LMS heartbeat circular red pulse overlay
	if is_instance_valid(_lms_pulse_layer):
		_lms_pulse_layer.queue_free()
	_lms_pulse_layer = null
	_lms_pulse_rect = null
	_lms_pulse_mat = null
	_lms_pulse_current = 0.0

	# Free the teleport red-glitch FX overlay
	if is_instance_valid(_teleport_fx_layer):
		_teleport_fx_layer.queue_free()
	_teleport_fx_layer = null
	_teleport_fx_rect = null
	_teleport_fx_mat = null
	_teleport_fx_active = false
	_teleport_fx_zoom_out_started = false
	_teleport_fx_timer = 0.0
	
	# Free overlays
	for overlay in [_death_overlay, _ending_screen_bg, _ending_screen_overlay,
			_ending_red_left, _ending_red_right, _epilepsy_overlay, _vignette_overlay,
			_ending_vignette]:
		if is_instance_valid(overlay):
			overlay.queue_free()
	_death_overlay = null
	_ending_screen_bg = null
	_ending_screen_overlay = null
	_ending_red_left = null
	_ending_red_right = null
	_epilepsy_overlay = null
	_vignette_overlay = null
	_ending_vignette = null
	_ending_screen_created = false
	_death_active = false
	
	# Free bots
	if is_instance_valid(_killer_bot):
		_killer_bot.queue_free()
		_killer_bot = null
	for bot: Node2D in _survivor_bots:
		if is_instance_valid(bot):
			bot.queue_free()
	_survivor_bots.clear()
	_alive_survivor_bot_count = 0
	
	# Free any open puzzle overlay
	var puzz := get_node_or_null("PuzzleOverlay")
	if is_instance_valid(puzz):
		puzz.queue_free()
	var puzz_mgr := get_node_or_null("PuzzleManager")
	if is_instance_valid(puzz_mgr):
		puzz_mgr.queue_free()
	_puzzle_open = false


# ═══════════════ MULTIPLAYER INTEGRATION ═══════════════

func _initialize_multiplayer() -> void:
	"""Set up multiplayer sync with the dedicated server if connected. When not
	connected, the game runs fully locally and AI bots handle gameplay."""
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


func _on_multiplayer_player_left(player_name: String) -> void:
	"""Handle player disconnection during match."""
	var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
	if chat_layer:
		chat_layer.add_system_message(player_name + " disconnected.")
	print("GameMap: Player left during match — ", player_name)


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
	# Start the AI killer at "Normal" difficulty, not Easy.
	_ai_difficulty.start_difficulty = AI_DIFFICULTY_START
	print("GameMap: AI difficulty controller attached (start=%.2f)" % [_ai_difficulty.start_difficulty])


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
