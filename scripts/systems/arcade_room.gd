class_name ArcadeRoom
extends Node2D
## The Darkness Of The Grasslands — Arcade Room
## A pitch-black room with a single interactable arcade machine. Interacting
## boots it up like a retro console (VHS flicker → boot text → quick loading
## bar) and then shows the "Tetrino" title/menu screen with its thumbnail and
## a looping tetrino.wav track. Built programmatically for reliability.

# ── Scene / asset paths ──
const ARCADE_MACHINE_TEX: String = "res://The Darkness Of The Grasslands assets/objects/arcade machine.png"
const TETRINO_MUSIC: String = "res://The Darkness Of The Grasslands assets/Music/Minigames/tetrino.wav"
const CARTRIDGE_START: String = "res://The Darkness Of The Grasslands assets/Sound/Minigames/Cartridge_START_140BPM.wav"
const TETRINO_THUMB: String = "res://The Darkness Of The Grasslands assets/Thumbnails/Minigame_TETRINO.thumnail.png"
# 140 BPM → one beat every 60/140 seconds (pulse the game to the music).
const BEAT_SECONDS: float = 60.0 / 140.0
# Solid fill colors taken from each piece sprite (the sprites are flat-color
# blocks with a black outline), so the game blocks match the artwork exactly.
const PIECE_COLORS: Dictionary = {
	"I": Color(0.0, 0.635, 0.91),
	"J": Color(1.0, 0.537, 0.729),
	"L": Color(1.0, 0.498, 0.153),
	"O": Color(1.0, 0.949, 0.0),
	"S": Color(0.929, 0.11, 0.141),
	"T": Color(0.639, 0.286, 0.643),
	"Z": Color(0.133, 0.694, 0.298),
}
# Base orientation of each piece as a 0/1 matrix, matching the sprite's natural
# orientation (I is vertical, O is 2x2, etc.).
const PIECE_SHAPES: Dictionary = {
	"I": [[1], [1], [1], [1]],
	"J": [[1, 0], [1, 0], [1, 1]],
	"L": [[0, 1], [0, 1], [1, 1]],
	"O": [[1, 1], [1, 1]],
	"S": [[0, 1, 1], [1, 1, 0]],
	"T": [[1, 1, 1], [0, 1, 0]],
	"Z": [[1, 1, 0], [0, 1, 1]],
}
const TETRIS_COLS: int = 10
const TETRIS_ROWS: int = 20
const CELL: float = 24.0
# White "base" block tile (solid white square with a black outline) that gets
# tinted to each piece's colour, so every block looks like a classic Tetris tile.
const BASE_BLOCK_TEX: String = "res://The Darkness Of The Grasslands assets/objects/Minigame_TETRINO_base_piece.png"
# Win condition: first to happen of reaching this score or clearing this many lines.
const WIN_SCORE: int = 1000
const WIN_LINES: int = 10
# Win fanfare and the reward coin artwork.
const TETRINO_COMPLETE: String = "res://The Darkness Of The Grasslands assets/Music/Minigames/MINIGAME-COMPLETED.wav"
const SAVE_MGR_SCRIPT = preload("res://scripts/systems/save_manager.gd")
const COIN_TEX: String = "res://The Darkness Of The Grasslands assets/UI/Lobby/Grassconatication coin.png"
# Time-tamper punishment: if the clock is rolled back to reset the daily coin
# limit, add this much (seconds) to the wait before coins are available again.
const TAMPER_PENALTY_SECONDS: int = 5 * 60 * 60
# Tiny 5x7 dot-matrix pixel font used for the "pixelated numbers" on the coin.
# Each glyph is 7 rows of 5 chars; '#' is a lit pixel.
const PIX_FONT: Dictionary = {
	"0": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": [".###.", "#...#", "....#", "..##.", "....#", "#...#", ".###."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
	"+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
	"x": [".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "....."],
	"c": [".....", ".....", ".###.", "#...#", "#....", "#...#", ".###."],
}
const LOBBY_SCENE: String = "res://scenes/lobby.tscn"
const WALK_DIR: String = "res://The Darkness Of The Grasslands assets/Sprites/Lobby person (Player(s))/Walk directions/Lobby person ---- Lobby -AKA- spectator/"
const FRONT_DIR: String = WALK_DIR + "Front (from human prespective - DOWN)/"
const BACK_DIR: String = WALK_DIR + "Back (from human prespective - UP)/"
const LEFT_DIR: String = WALK_DIR + "Left (from human prespective - LEFT)/"
const RIGHT_DIR: String = WALK_DIR + "Right (from human prespective - RIGHT)/"

# ── Room layout (fixed 1280x768 viewport, no camera) ──
const ROOM_W: float = 1280.0
const ROOM_H: float = 768.0
const MACHINE_POS: Vector2 = Vector2(940, 430)
const PLAYER_START: Vector2 = Vector2(220, 430)

# ── Boot sequence timing ──
const FLICKER_DURATION: float = 0.7
const BOOT_TEXT: String = "COMPUTERING CONSOLE BOOT V0.5P.R.O.T.O.T.Y.P.E."
const LOAD_DURATION: float = 1.0

# ── Theme persistence (console-only; never touched by normal settings) ──
const THEME_CFG: String = "user://console_theme.cfg"
const THEME_CYCLE: Array[String] = ["system", "light", "dark"]

# ── State ──
var _player: CharacterBody2D = null
var _sprite: AnimatedSprite2D = null
var _machine_area: Area2D = null
var _machine_prompt: Label = null
var _ui: CanvasLayer = null
var _boot_active: bool = false
var _browser_active: bool = false   # Minigame browser (list of cartridges)
var _menu_active: bool = false      # A specific minigame's title/menu is showing
var _game_active: bool = false      # The actual Tetris minigame is running
var _browser_msg: Label = null      # The "only this in the demo" nag text
var _browser_msg_visible: bool = false
var _music: AudioStreamPlayer = null
var _idle_anim: String = "idle_down"
var _e_was_down: bool = false
var _esc_was_down: bool = false
var _enter_was_down: bool = false
var _nav_was_down: bool = false
var _t_was_down: bool = false
var _theme_label: Label = null

# ── Tetris game state ──
var _board: Array = []             # 2D grid: "" or piece key for settled cells (single source of truth)
var _cur_type: String = "T"
var _cur_rot: int = 0
var _cur_row: int = 0
var _cur_col: int = 0
var _game_over: bool = false
var _game_lost: bool = false
var _score: int = 0
var _level: int = 1
var _drop_accum: float = 0.0
var _drop_interval: float = 1.0
var _board_origin: Vector2 = Vector2.ZERO
var _board_layer: Control = null
var _board_texs: Array = []        # TextureRects currently shown on the board
var _next_queue: Array = []        # Upcoming piece types (7-bag)
var _next_layer: Control = null    # Layer showing the upcoming pieces
var _next_texs: Array = []         # TextureRects currently shown in NEXT
var _score_lbl: Label = null
var _intro_active: bool = false    # cartridge-start zoom intro is playing
var _beat_accum: float = 0.0       # accumulator for the 140 BPM pulse
var _pulse_overlay: ColorRect = null
var _title_thumb: TextureRect = null  # title art used for the start zoom
var _cart: AudioStreamPlayer = null
var _intro_zoom_tween: Tween = null  # zoom-in tween during the intro (killed on cancel)
var _left_was_down: bool = false
var _right_was_down: bool = false
var _up_was_down: bool = false
var _down_was_down: bool = false
var _space_was_down: bool = false
var _clearing: bool = false        # a line-clear flash is in progress (pause the game)
var _lines_cleared: int = 0        # total lines cleared this run (win condition)
var _won: bool = false             # the player won the minigame (not a loss)
var _hard_mode: bool = false       # this run is the "gamble" hard mode
var _win_coin: TextureRect = null  # coin shown on the win screen (for shine anim)
var _g_was_down: bool = false      # edge-detect for the G (gamble) key on the win screen


func _ready() -> void:
	_load_theme()
	_build_room()
	_build_player()
	_build_machine()
	_build_ui()
	# Reveal from black (right-to-left wipe continues from the lobby).
	_reveal_from_black()


# ═══════════════ CONSOLE THEME (console-only) ═══════════════

func _load_theme() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(THEME_CFG) == OK:
		var t: String = str(cfg.get_value("console", "theme", "system"))
		if t in THEME_CYCLE:
			GameState.console_theme = t


func _save_theme() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("console", "theme", GameState.console_theme)
	cfg.save(THEME_CFG)


func _cycle_theme() -> void:
	var idx: int = THEME_CYCLE.find(GameState.console_theme)
	GameState.console_theme = THEME_CYCLE[(idx + 1) % THEME_CYCLE.size()]
	_save_theme()
	# Rebuild the current screen (browser or menu) with the new palette.
	if _menu_active:
		_rebuild_tetrino()
	elif _browser_active:
		_rebuild_browser()
	_update_theme_label()


func _resolved_theme() -> String:
	# "system" follows the OS light/dark preference.
	if GameState.console_theme == "system":
		var dark: bool = DisplayServer.is_dark_mode_supported() and DisplayServer.is_dark_mode()
		return "dark" if dark else "light"
	return GameState.console_theme


func _palette() -> Dictionary:
	var light: bool = _resolved_theme() == "light"
	if light:
		return {
			"bg": Color(0.93, 0.91, 0.86, 1),       # old-computer beige
			"panel": Color(0.84, 0.80, 0.72, 1),    # darker beige panel
			"panel_edge": Color(0.45, 0.42, 0.38, 1),
			"text": Color(0.08, 0.08, 0.10, 1),     # near-black text
			"text_dim": Color(0.25, 0.25, 0.27, 1),
			"accent": Color(0.0, 0.25, 0.6, 1),     # classic blue
			"gloss": Color(1, 1, 1, 0.55),
		}
	return {
		"bg": Color(0, 0, 0, 1),
		"panel": Color(0.10, 0.11, 0.14, 1),
		"panel_edge": Color(0.28, 0.32, 0.4, 1),
		"text": Color(0.85, 0.95, 1.0, 1),
		"text_dim": Color(0.7, 0.75, 0.8, 1),
		"accent": Color(0.3, 1.0, 1.0, 1),
		"gloss": Color(1, 1, 1, 0.18),
	}


func _update_theme_label() -> void:
	if is_instance_valid(_theme_label):
		_theme_label.text = "DISPLAY: %s" % GameState.console_theme.to_upper()


func _make_glossy_screen(size: Vector2) -> ColorRect:
	"""A glossy glass highlight over a thumbnail/screen. Uses a ColorRect with
	a shader-based diagonal shine so it looks like a reflective CRT screen."""
	var gloss := ColorRect.new()
	gloss.position = Vector2.ZERO
	gloss.size = size
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/systems/arcade_gloss.gdshader")
	gloss.material = mat
	return gloss


# ═══════════════ ROOM CONSTRUCTION ═══════════════

func _build_room() -> void:
	# Pitch black backdrop — "no lighting whatsoever".
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.position = Vector2(0, 0)
	bg.size = Vector2(ROOM_W, ROOM_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# A faint floor line so the player isn't totally lost (still black room).
	var floor_line := ColorRect.new()
	floor_line.color = Color(0.12, 0.12, 0.12, 1)
	floor_line.position = Vector2(0, ROOM_H - 150)
	floor_line.size = Vector2(ROOM_W, 2)
	floor_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floor_line)

	_build_room_walls()


func _build_room_walls() -> void:
	var walls := StaticBody2D.new()
	walls.name = "RoomWalls"
	add_child(walls)
	var bounds: Array[Rect2] = [
		Rect2(-100, -100, ROOM_W + 200, 40),        # top
		Rect2(-100, ROOM_H, ROOM_W + 200, 100),     # bottom
		Rect2(-100, -100, 40, ROOM_H + 200),        # left
		Rect2(ROOM_W, -100, 100, ROOM_H + 200),     # right
	]
	for i in bounds.size():
		var sb := StaticBody2D.new()
		sb.name = "Wall%d" % i
		var shape := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = Vector2(bounds[i].size.x, bounds[i].size.y)
		shape.shape = r
		shape.position = bounds[i].position + bounds[i].size / 2.0
		sb.add_child(shape)
		walls.add_child(sb)


func _build_player() -> void:
	_player = CharacterBody2D.new()
	_player.name = "Player"
	_player.position = PLAYER_START

	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(26, 24)
	col.shape = rect
	_player.add_child(col)

	_sprite = AnimatedSprite2D.new()
	_sprite.name = "ArcadePerson"
	_sprite.scale = Vector2(0.5, 0.5)
	_sprite.sprite_frames = _make_sprite_frames()
	_sprite.animation = "idle_down"
	_player.add_child(_sprite)

	add_child(_player)


func _make_sprite_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var anims := {
		"idle_down": [FRONT_DIR + "Walk_DOWN_frame-1.png"],
		"idle_up": [BACK_DIR + "Walk_UP_frame-1.png"],
		"idle_left": [LEFT_DIR + "Walk_LEFT_frame-1.png"],
		"idle_right": [RIGHT_DIR + "Walk_RIGHT_frame-1.png"],
		"walk_down": [FRONT_DIR + "Walk_DOWN_frame-1.png", FRONT_DIR + "Walk_DOWN_frame-2.png"],
		"walk_up": [BACK_DIR + "Walk_UP_frame-1.png", BACK_DIR + "Walk_UP_frame-2.png"],
		"walk_left": [LEFT_DIR + "Walk_LEFT_frame-1.png", LEFT_DIR + "Walk_LEFT_frame-2.png"],
		"walk_right": [RIGHT_DIR + "Walk_RIGHT_frame-1.png", RIGHT_DIR + "Walk_RIGHT_frame-2.png"],
	}
	for anim_name: String in anims:
		sf.add_animation(anim_name)
		for path: String in anims[anim_name]:
			sf.add_frame(anim_name, load(path))
		sf.set_animation_speed(anim_name, 4.0)
		sf.set_animation_loop(anim_name, anim_name.begins_with("walk"))
	return sf


func _build_machine() -> void:
	_machine_area = Area2D.new()
	_machine_area.name = "ArcadeMachine"
	_machine_area.position = MACHINE_POS

	var sprite := Sprite2D.new()
	sprite.name = "Visual"
	sprite.texture = load(ARCADE_MACHINE_TEX)
	_machine_area.add_child(sprite)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(90, 90)
	shape.shape = rect
	_machine_area.add_child(shape)

	_machine_prompt = Label.new()
	_machine_prompt.name = "InteractPrompt"
	_machine_prompt.text = "Press [E] to play TETRINO"
	_machine_prompt.position = Vector2(-110, -80)
	_machine_prompt.size = Vector2(220, 30)
	_machine_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_machine_prompt.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_machine_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_machine_prompt.add_theme_constant_override("shadow_offset_x", 2)
	_machine_prompt.add_theme_constant_override("shadow_offset_y", 2)
	_machine_prompt.add_theme_font_size_override("font_size", 18)
	_machine_prompt.visible = false
	_machine_area.add_child(_machine_prompt)

	_machine_area.body_entered.connect(_on_machine_body_entered)
	_machine_area.body_exited.connect(_on_machine_body_exited)
	add_child(_machine_area)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "ArcadeUI"
	_ui.layer = 50
	add_child(_ui)


# ═══════════════ PLAYER CONTROL ═══════════════

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	# Edge-detected key handling (E to interact / ESC to back out).
	var e_down := Input.is_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_E)
	if e_down and not _e_was_down:
		_on_e_pressed()
	var esc_down := Input.is_key_pressed(KEY_ESCAPE) or Input.is_physical_key_pressed(KEY_ESCAPE)
	if esc_down and not _esc_was_down:
		_on_esc_pressed()
	_e_was_down = e_down
	_esc_was_down = esc_down

	# Minigame browser: WASD tries to navigate, Enter launches the highlighted
	# game, Esc leaves. In the demo there is only Tetrino, so WASD just shows a
	# friendly "this is all we have" nag.
	# Enter: in the browser it launches Tetrino; on the Tetrino title screen it
	# starts the actual minigame (which is when the music plays).
	var enter_down := Input.is_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_ENTER)
	if enter_down and not _enter_was_down:
		_on_enter_pressed()
	_enter_was_down = enter_down

	if _browser_active and not _menu_active and not _boot_active:
		var nav_down := (
			Input.is_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_W)
			or Input.is_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_A)
			or Input.is_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_S)
			or Input.is_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_D)
		)
		if nav_down and not _nav_was_down:
			_on_browser_navigate()
		var t_down := Input.is_key_pressed(KEY_T) or Input.is_physical_key_pressed(KEY_T)
		if t_down and not _t_was_down:
			_cycle_theme()
		_nav_was_down = nav_down
		_t_was_down = t_down
	else:
		_nav_was_down = false
		_t_was_down = false

	# While the Tetris minigame is actually running, arrow keys / space control
	# the falling piece and gravity advances on a timer.
	if _game_active:
		_player.velocity = Vector2.ZERO
		if is_instance_valid(_sprite):
			_sprite.animation = _idle_anim
		if _won:
			_handle_win_input()
			return
		_tetris_handle_input()
		_tetris_step(delta)
		_tetris_pulse(delta)
		return

	if _boot_active or _menu_active:
		_player.velocity = Vector2.ZERO
		if is_instance_valid(_sprite):
			_sprite.animation = _idle_anim
		return

	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1
	input_dir = input_dir.normalized()
	var speed := 160.0
	if Input.is_key_pressed(KEY_SHIFT):
		speed = 250.0
	if input_dir != Vector2.ZERO:
		_player.velocity = input_dir * speed
		_update_walk_anim(input_dir)
	else:
		_player.velocity = Vector2.ZERO
		if is_instance_valid(_sprite):
			_sprite.animation = _idle_anim
	_player.move_and_slide()


func _update_walk_anim(dir: Vector2) -> void:
	var anim: String = "walk_down"
	if absf(dir.x) > absf(dir.y):
		anim = "walk_right" if dir.x > 0 else "walk_left"
		_idle_anim = "idle_right" if dir.x > 0 else "idle_left"
	else:
		anim = "walk_down" if dir.y > 0 else "walk_up"
		_idle_anim = "idle_down" if dir.y > 0 else "idle_up"
	if is_instance_valid(_sprite):
		_sprite.animation = anim


func _on_e_pressed() -> void:
	if _boot_active or _menu_active:
		return
	if not is_instance_valid(_player) or not is_instance_valid(_machine_area):
		return
	# Allow interaction if within a comfortable range of the machine, even if
	# the prompt isn't currently visible (avoids timing edge cases).
	var in_range: bool = _player.global_position.distance_to(_machine_area.global_position) < 140.0
	if _machine_prompt and _machine_prompt.visible:
		in_range = true
	if in_range:
		_start_boot_sequence()


func _on_enter_pressed() -> void:
	if _game_active and (_game_over or _won):
		# Game over / win screen: Enter retries (normal mode).
		_hard_mode = false
		_start_tetrino_game()
		return
	if _intro_active:
		return
	if _browser_active and not _menu_active and not _boot_active:
		_launch_tetrino()
	elif _menu_active and not _game_active:
		# On the Tetrino title screen, Enter plays the cartridge-start sound,
		# zooms into the game, and then begins the actual minigame (which is
		# when the music starts).
		_start_tetrino_intro()


func _on_esc_pressed() -> void:
	if _intro_active:
		# ESC during the cartridge-start intro cancels the entering (pitches the
		# sound down, purple flash, back to the title menu) instead of exiting.
		_cancel_tetrino_intro()
	elif _game_active:
		_exit_tetrino_game()
	elif _menu_active:
		_close_tetrino()
	elif _browser_active:
		_leave_arcade_room()
	elif _boot_active:
		# Skip boot and go straight to the browser.
		_show_minigame_browser()
	else:
		_leave_arcade_room()


# ═══════════════ MACHINE INTERACTION ═══════════════

func _on_machine_body_entered(body: Node) -> void:
	if body == _player and not _boot_active and not _menu_active:
		_machine_prompt.visible = true


func _on_machine_body_exited(body: Node) -> void:
	if body == _player:
		_machine_prompt.visible = false


# ═══════════════ CONSOLE BOOT SEQUENCE ═══════════════

func _start_boot_sequence() -> void:
	if _boot_active or _menu_active:
		return
	_boot_active = true
	_machine_prompt.visible = false
	_run_boot()


func _run_boot() -> void:
	# 1) VHS-style flicker: the screen goes black and stays black (the flicker
	#    is expressed as a barely-visible shimmer, never white).
	var flick := ColorRect.new()
	flick.name = "BootBlack"
	flick.color = Color(0, 0, 0, 1)
	flick.position = Vector2(0, 0)
	flick.size = Vector2(ROOM_W, ROOM_H)
	flick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(flick)

	# Black-only flicker: nudge opacity a touch for a CRT shimmer feel.
	var t_end := Time.get_ticks_msec() + int(FLICKER_DURATION * 1000.0)
	while Time.get_ticks_msec() < t_end:
		flick.color = Color(0, 0, 0, randf_range(0.85, 1.0))
		await get_tree().create_timer(randf_range(0.02, 0.06)).timeout
	flick.color = Color(0, 0, 0, 1)
	await get_tree().create_timer(0.1).timeout

	# 2) Boot text (monospace-style, centered).
	var boot_lbl := Label.new()
	boot_lbl.text = BOOT_TEXT
	boot_lbl.position = Vector2(0, ROOM_H * 0.4)
	boot_lbl.size = Vector2(ROOM_W, 40)
	boot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boot_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5, 1))
	boot_lbl.add_theme_font_size_override("font_size", 26)
	_ui.add_child(boot_lbl)
	await get_tree().create_timer(0.8).timeout
	boot_lbl.queue_free()
	# Screen stays black (flick overlay still up) through boot text + loading.

	# 3) Quick fake loading bar: 10% → 78% → 100% in ~1s.
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.2, 0.2, 0.2, 0.9)
	bar_bg.position = Vector2((ROOM_W - 400) / 2.0, ROOM_H * 0.6)
	bar_bg.size = Vector2(404, 28)
	_ui.add_child(bar_bg)

	var bar_fill := ColorRect.new()
	bar_fill.color = Color(0.2, 1.0, 0.2, 1)
	bar_fill.position = bar_bg.position + Vector2(2, 2)
	bar_fill.size = Vector2(0, 24)
	_ui.add_child(bar_fill)

	var pct_lbl := Label.new()
	pct_lbl.position = Vector2(0, bar_bg.position.y + 32)
	pct_lbl.size = Vector2(ROOM_W, 30)
	pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pct_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	pct_lbl.add_theme_font_size_override("font_size", 20)
	_ui.add_child(pct_lbl)

	# Jump 10% → 78% → 100% over the load duration.
	var marks: Array[Vector2] = [
		Vector2(0.0, 0.10),
		Vector2(0.35, 0.78),
		Vector2(0.9, 1.0),
	]
	for m in marks:
		var tween := create_tween()
		tween.tween_property(bar_fill, "size:x", 400.0 * m.y, LOAD_DURATION * 0.35)
		tween.parallel().tween_property(pct_lbl, "text", "%d%%" % int(m.y * 100.0), 0.01)
		await tween.finished
	bar_fill.size.x = 400.0
	pct_lbl.text = "100%"
	await get_tree().create_timer(0.2).timeout

	bar_bg.queue_free()
	bar_fill.queue_free()
	pct_lbl.queue_free()

	# Boot is done — lift the black overlay and reveal the console navigator.
	flick.queue_free()

	_boot_active = false
	_show_minigame_browser()


# ═══════════════ MINIGAME BROWSER ═══════════════

func _show_minigame_browser() -> void:
	"""Cartridge browser. In the demo there is only one minigame: Tetrino.
	WASD navigation just shows a friendly 'this is all we have' nag. Themed like
	an authentic old computer (light beige / dark CRT), with glossy screens."""
	if _browser_active:
		return
	_browser_active = true
	_browser_msg_visible = false
	# Music is NOT played here — tetrino.wav only plays inside the Tetris game.

	var p := _palette()

	# Backdrop (themed).
	var bg := ColorRect.new()
	bg.name = "BrowserBG"
	bg.color = p["bg"]
	bg.position = Vector2(0, 0)
	bg.size = Vector2(ROOM_W, ROOM_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bg)

	# Authentic CRT bezel frame around the display area.
	var bezel := ColorRect.new()
	bezel.name = "BrowserBezel"
	bezel.color = Color(0.12, 0.12, 0.14, 1)
	bezel.position = Vector2(60, 40)
	bezel.size = Vector2(ROOM_W - 120, ROOM_H - 110)
	_ui.add_child(bezel)

	# Inner screen (themed panel).
	var screen := ColorRect.new()
	screen.name = "BrowserScreen"
	screen.color = p["bg"]
	screen.position = bezel.position + Vector2(14, 14)
	screen.size = bezel.size - Vector2(28, 28)
	_ui.add_child(screen)

	var title := Label.new()
	title.text = "MINIGAME BROWSER"
	title.position = Vector2(screen.position.x, screen.position.y + 24)
	title.size = Vector2(screen.size.x, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", p["accent"])
	title.add_theme_font_size_override("font_size", 40)
	_ui.add_child(title)

	# The single cartridge: Tetrino (highlighted/selected) as a glossy screen.
	var card := ColorRect.new()
	card.name = "TetrinoCard"
	card.color = p["panel"]
	card.position = Vector2((ROOM_W - 420) / 2.0, 150)
	card.size = Vector2(420, 300)
	_ui.add_child(card)

	var thumb := TextureRect.new()
	thumb.texture = load(TETRINO_THUMB)
	thumb.position = card.position + Vector2(40, 40)
	thumb.size = Vector2(338, 220)
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ui.add_child(thumb)

	# Glossy screen reflection on top of the thumbnail.
	var gloss := _make_glossy_screen(thumb.size)
	gloss.position = thumb.position
	_ui.add_child(gloss)

	var card_name := Label.new()
	card_name.text = "TETRINO"
	card_name.position = Vector2(0, card.position.y + 230)
	card_name.size = Vector2(ROOM_W, 60)
	card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_name.add_theme_color_override("font_color", p["accent"])
	card_name.add_theme_font_size_override("font_size", 44)
	_ui.add_child(card_name)

	# Shiny Grassconatication coin + pixelated count earned from Tetrino.
	var coin_badge := TextureRect.new()
	coin_badge.texture = load(COIN_TEX)
	coin_badge.position = Vector2(ROOM_W / 2.0 - 220, ROOM_H - 150)
	coin_badge.size = Vector2(36, 36)
	coin_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(coin_badge)
	_add_pixel_text(_ui, "x" + str(GameState.tetrino_coins_earned),
		Vector2(ROOM_W / 2.0 - 176, ROOM_H - 142), 3.0, p["accent"])

	# Theme indicator (console-only setting).
	_theme_label = Label.new()
	_theme_label.position = Vector2(0, ROOM_H - 108)
	_theme_label.size = Vector2(ROOM_W, 28)
	_theme_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_theme_label.add_theme_color_override("font_color", p["text_dim"])
	_theme_label.add_theme_font_size_override("font_size", 16)
	_ui.add_child(_theme_label)
	_update_theme_label()

	var hint := Label.new()
	hint.text = "WASD  navigate   •   T  display   •   ENTER  play   •   ESC  leave"
	hint.position = Vector2(0, ROOM_H - 80)
	hint.size = Vector2(ROOM_W, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", p["text_dim"])
	hint.add_theme_font_size_override("font_size", 18)
	_ui.add_child(hint)


func _on_browser_navigate() -> void:
	"""WASD in the browser: in the demo there's only Tetrino, so show a friendly
	notice that this is all we've got — have fun or leave."""
	if not _browser_active or _menu_active or _boot_active:
		return
	if _browser_msg_visible:
		return
	_browser_msg_visible = true
	var p := _palette()
	_browser_msg = Label.new()
	_browser_msg.text = "This is the minigame we got in the Demo, so either have fun or just leave the game."
	_browser_msg.position = Vector2(0, ROOM_H - 130)
	_browser_msg.size = Vector2(ROOM_W, 40)
	_browser_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_browser_msg.add_theme_color_override("font_color", p["text"])
	_browser_msg.add_theme_font_size_override("font_size", 20)
	_ui.add_child(_browser_msg)
	# Auto-hide after a moment so it doesn't permanently clutter the screen.
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(_browser_msg):
		_browser_msg.queue_free()
		_browser_msg = null
		_browser_msg_visible = false


func _launch_tetrino() -> void:
	if not _browser_active or _menu_active or _boot_active:
		return
	_clear_browser()
	_show_tetrino_menu()


func _clear_browser() -> void:
	_browser_active = false
	for child: Node in _ui.get_children():
		child.queue_free()
	_browser_msg = null
	_browser_msg_visible = false


func _rebuild_browser() -> void:
	_clear_browser()
	_show_minigame_browser()


# ═══════════════ TETRINO TITLE / MENU ═══════════════

func _show_tetrino_menu() -> void:
	if _menu_active:
		return
	_menu_active = true
	_game_active = false
	# Music is NOT started here — it only plays once the player actually
	# enters the minigame (see _start_tetrino_game).

	var p := _palette()

	# Backdrop behind the menu (themed).
	var bg := ColorRect.new()
	bg.name = "TetrinoBG"
	bg.color = p["bg"]
	bg.position = Vector2(0, 0)
	bg.size = Vector2(ROOM_W, ROOM_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bg)

	# CRT bezel frame.
	var bezel := ColorRect.new()
	bezel.name = "TetrinoBezel"
	bezel.color = Color(0.12, 0.12, 0.14, 1)
	bezel.position = Vector2(60, 40)
	bezel.size = Vector2(ROOM_W - 120, ROOM_H - 110)
	_ui.add_child(bezel)

	# Thumbnail as the title art (glossy screen).
	var thumb := TextureRect.new()
	thumb.texture = load(TETRINO_THUMB)
	thumb.position = Vector2((ROOM_W - 338) / 2.0, 70)
	thumb.size = Vector2(338, 258)
	thumb.pivot_offset = thumb.size / 2.0
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title_thumb = thumb
	_ui.add_child(thumb)

	var gloss := _make_glossy_screen(thumb.size)
	gloss.position = thumb.position
	_ui.add_child(gloss)

	var title := Label.new()
	title.text = "TETRINO"
	title.position = Vector2(0, 340)
	title.size = Vector2(ROOM_W, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", p["accent"])
	title.add_theme_font_size_override("font_size", 56)
	_ui.add_child(title)

	# Placeholder play field (menu-first scope).
	var field_border := ColorRect.new()
	field_border.color = p["panel_edge"]
	field_border.position = Vector2((ROOM_W - 220) / 2.0, 430)
	field_border.size = Vector2(220, 220)
	_ui.add_child(field_border)

	var field_bg := ColorRect.new()
	field_bg.color = p["panel"]
	field_bg.position = Vector2((ROOM_W - 216) / 2.0, 434)
	field_bg.size = Vector2(212, 212)
	_ui.add_child(field_bg)

	var hint := Label.new()
	hint.text = "INSERT COIN TO PLAY"
	hint.position = Vector2(0, ROOM_H - 120)
	hint.size = Vector2(ROOM_W, 50)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", p["accent"])
	hint.add_theme_font_size_override("font_size", 24)
	_ui.add_child(hint)

	var back := Label.new()
	back.text = "Press [ENTER] to play   •   [ESC] to exit"
	back.position = Vector2(0, ROOM_H - 60)
	back.size = Vector2(ROOM_W, 30)
	back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.add_theme_color_override("font_color", p["text_dim"])
	back.add_theme_font_size_override("font_size", 14)
	_ui.add_child(back)


func _rebuild_tetrino() -> void:
	_menu_active = false
	for child: Node in _ui.get_children():
		child.queue_free()
	_show_tetrino_menu()


func _play_music() -> void:
	"""Start tetrino.wav looping seamlessly (full track, no fade-in). If the
	audio is imported as uncompressed 16-bit PCM we loop at the stream level so
	there's no gap; if it's a compressed import (QOA/ADPCM) we fall back to
	restarting on the `finished` signal so the track always plays fully and
	repeats."""
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.stream = load(TETRINO_MUSIC)
		_music.bus = "Music"
		add_child(_music)
		var wav: AudioStreamWAV = _music.stream as AudioStreamWAV
		if wav:
			if wav.format == AudioStreamWAV.FORMAT_16_BITS:
				# Uncompressed PCM: loop the WHOLE track at the stream level for
				# a truly seamless repeat. Loop fields are in sample frames (not
				# bytes), so derive the full frame count from the raw PCM size.
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				var bytes_per_frame: int = 2 * (2 if wav.stereo else 1)
				if bytes_per_frame > 0:
					wav.loop_end = int(wav.data.size() / bytes_per_frame)
			else:
				# Compressed import: loop points aren't reliable, so restart on
				# finish to keep the track repeating.
				wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
				_music.finished.connect(_on_music_finished)
	if not _music.playing:
		# Start at full volume immediately (no fade-in).
		_music.volume_db = -6.0
		_music.play()


func _on_music_finished() -> void:
	"""Restart the looped track (used only when the import is compressed and
	stream-level looping isn't available)."""
	if is_instance_valid(_music):
		_music.play()


func _start_tetrino_intro() -> void:
	"""Play the cartridge-start sound and zoom into the title art, then begin
	the actual Tetris minigame."""
	if _intro_active or _game_active:
		return
	_intro_active = true

	# Play the cartridge-start jingle on the SFX bus.
	_cart = AudioStreamPlayer.new()
	_cart.stream = load(CARTRIDGE_START)
	_cart.bus = "SFX"
	add_child(_cart)
	_cart.finished.connect(_on_cart_finished)
	_cart.play()

	# Zoom into the title art to "enter" the game.
	if is_instance_valid(_title_thumb):
		_intro_zoom_tween = create_tween()
		_intro_zoom_tween.tween_property(_title_thumb, "scale", Vector2(3.2, 3.2), 1.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# The game music waits for the cartridge jingle to finish fully before
	# starting (see _on_cart_finished), so the two never overlap.


func _cancel_tetrino_intro() -> void:
	"""ESC during the cartridge-start intro: cancel the entering. The cartridge
	sound pitches down like a disc being slowed/ejected, the screen flashes
	purple and fades away over 0.5s, and the title art un-zooms back to the
	menu (the game is NOT started)."""
	if not _intro_active:
		return
	_intro_active = false  # stops _on_cart_finished from starting the game

	# Stop the zoom-in and glide the title art back to normal.
	if is_instance_valid(_intro_zoom_tween):
		_intro_zoom_tween.kill()
		_intro_zoom_tween = null
	if is_instance_valid(_title_thumb):
		var zt := create_tween()
		zt.tween_property(_title_thumb, "scale", Vector2.ONE, 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Pitch the cartridge sound down like a disc winding down.
	if is_instance_valid(_cart):
		var pt := create_tween()
		pt.tween_property(_cart, "pitch_scale", 0.12, 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		pt.tween_callback(_cleanup_cart)

	# Purple flash that fades away over 0.5s.
	var flash := ColorRect.new()
	flash.name = "CancelFlash"
	flash.color = Color(0.6, 0.0, 1.0, 1.0)
	flash.position = Vector2(0, 0)
	flash.size = Vector2(ROOM_W, ROOM_H)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(flash)
	var ft := create_tween()
	ft.tween_property(flash, "modulate:a", 0.0, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ft.tween_callback(flash.queue_free)


func _cleanup_cart() -> void:
	if is_instance_valid(_cart):
		_cart.stop()
		_cart.queue_free()
	_cart = null


func _on_cart_finished() -> void:
	"""The cartridge-start jingle has played to the end — now begin the actual
	game (which starts the tetrino music). Guards so a back-out during the
	intro cancels it."""
	if not _intro_active:
		return
	_intro_active = false
	_start_tetrino_game()


func _start_tetrino_game() -> void:
	"""Player pressed ENTER on the title screen — the actual Tetris minigame
	now begins, which is when the music starts. Also used to retry after a
	game over."""
	if not _menu_active:
		return
	if _game_active and not _game_over:
		return
	_game_active = true
	_game_over = false
	_game_lost = false
	_won = false
	_clearing = false
	_lines_cleared = 0
	_score = 0
	_level = 1
	# Hard mode ("gamble") starts faster for a tougher challenge.
	_drop_interval = 0.5 if _hard_mode else 1.0
	_drop_accum = 0.0
	_space_was_down = false
	_left_was_down = false
	_right_was_down = false
	_up_was_down = false
	_down_was_down = false
	_beat_accum = 0.0

	_play_music()
	var p := _palette()

	# Clear the title menu and draw the live game screen.
	for child: Node in _ui.get_children():
		child.queue_free()

	var bg := ColorRect.new()
	bg.color = p["bg"]
	bg.position = Vector2(0, 0)
	bg.size = Vector2(ROOM_W, ROOM_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bg)

	var bezel := ColorRect.new()
	bezel.color = Color(0.12, 0.12, 0.14, 1)
	bezel.position = Vector2(60, 40)
	bezel.size = Vector2(ROOM_W - 120, ROOM_H - 110)
	_ui.add_child(bezel)

	# Board: 10 cols x 20 rows of CELL-sized cells, placed on the left-centre.
	_board_origin = Vector2(140, 120)
	var board_w: float = TETRIS_COLS * CELL
	var board_h: float = TETRIS_ROWS * CELL

	var field_border := ColorRect.new()
	field_border.color = p["panel_edge"]
	field_border.position = _board_origin - Vector2(6, 6)
	field_border.size = Vector2(board_w + 12, board_h + 12)
	_ui.add_child(field_border)

	var field_bg := ColorRect.new()
	field_bg.color = p["panel"]
	field_bg.position = _board_origin
	field_bg.size = Vector2(board_w, board_h)
	_ui.add_child(field_bg)

	# Layer that holds the rendered pieces (TextureRects).
	_board_layer = Control.new()
	_board_layer.position = _board_origin
	_board_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_board_layer)

	# Subtle overlay used to pulse the board to the 140 BPM beat.
	_pulse_overlay = ColorRect.new()
	_pulse_overlay.color = Color(1, 1, 1, 1)
	_pulse_overlay.modulate.a = 0.0
	_pulse_overlay.position = _board_origin
	_pulse_overlay.size = Vector2(board_w, board_h)
	_pulse_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_pulse_overlay)

	var playing := Label.new()
	playing.text = "TETRINO — PLAYING"
	playing.position = Vector2(0, 64)
	playing.size = Vector2(ROOM_W, 40)
	playing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	playing.add_theme_color_override("font_color", p["accent"])
	playing.add_theme_font_size_override("font_size", 28)
	_ui.add_child(playing)

	# Side panel: score / level / controls.
	var side_x: float = _board_origin.x + board_w + 40
	var lbl := Label.new()
	lbl.text = "SCORE"
	lbl.position = Vector2(side_x, 130)
	lbl.size = Vector2(360, 30)
	lbl.add_theme_color_override("font_color", p["text_dim"])
	lbl.add_theme_font_size_override("font_size", 18)
	_ui.add_child(lbl)

	_score_lbl = Label.new()
	_score_lbl.text = "0"
	_score_lbl.position = Vector2(side_x, 160)
	_score_lbl.size = Vector2(360, 40)
	_score_lbl.add_theme_color_override("font_color", p["accent"])
	_score_lbl.add_theme_font_size_override("font_size", 34)
	_ui.add_child(_score_lbl)

	# NEXT: the upcoming pieces on the empty right side.
	var next_lbl := Label.new()
	next_lbl.text = "NEXT"
	next_lbl.position = Vector2(side_x, 250)
	next_lbl.size = Vector2(360, 30)
	next_lbl.add_theme_color_override("font_color", p["text_dim"])
	next_lbl.add_theme_font_size_override("font_size", 18)
	_ui.add_child(next_lbl)

	_next_layer = Control.new()
	_next_layer.position = Vector2(side_x, 290)
	_next_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_next_layer)

	var ctrl := Label.new()
	ctrl.text = "← → move\n↑ rotate\n↓ soft drop\nspace hard drop"
	ctrl.position = Vector2(side_x, 580)
	ctrl.size = Vector2(360, 120)
	ctrl.add_theme_color_override("font_color", p["text_dim"])
	ctrl.add_theme_font_size_override("font_size", 18)
	_ui.add_child(ctrl)

	var back := Label.new()
	back.text = "Press [ESC] to exit"
	back.position = Vector2(0, ROOM_H - 60)
	back.size = Vector2(ROOM_W, 30)
	back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.add_theme_color_override("font_color", p["text_dim"])
	back.add_theme_font_size_override("font_size", 14)
	_ui.add_child(back)

	# Initialise the board and spawn the first piece.
	_board = []
	for _r in range(TETRIS_ROWS):
		var row: Array = []
		row.resize(TETRIS_COLS)
		row.fill("")
		_board.append(row)
	_spawn_piece()
	_render_board()


# ═══════════════ TETRIS GAMEPLAY ═══════════════

func _rot_shape(shape: Array, rot: int) -> Array:
	"""Return the 0/1 matrix of `shape` rotated `rot` times 90° clockwise."""
	var m: Array = shape
	for _i in range(((rot % 4) + 4) % 4):
		var h: int = m.size()
		var w: int = m[0].size()
		var out: Array = []
		for x in range(w):
			var nr: Array = []
			for y in range(h - 1, -1, -1):
				nr.append(m[y][x])
			out.append(nr)
		m = out
	return m


func _refill_queue() -> void:
	"""Add a shuffled 7-bag of every piece to the upcoming queue."""
	var keys: Array = PIECE_SHAPES.keys()
	keys.shuffle()
	for k: String in keys:
		_next_queue.append(k)


func _spawn_piece() -> void:
	"""Create a new falling piece from the queue at the top centre; flag game
	over if blocked."""
	if _next_queue.is_empty():
		_refill_queue()
	_cur_type = _next_queue.pop_front()
	_cur_rot = 0
	var shape: Array = PIECE_SHAPES[_cur_type]
	var w: int = shape[0].size()
	_cur_row = 0
	_cur_col = (TETRIS_COLS - w) / 2
	if _collides(_cur_type, _cur_rot, _cur_row, _cur_col):
		_game_lost = true
	_render_next()


func _matrix(type: String, rot: int) -> Array:
	return _rot_shape(PIECE_SHAPES[type], rot)


func _collides(type: String, rot: int, row: int, col: int) -> bool:
	var m := _matrix(type, rot)
	for r in range(m.size()):
		for c in range(m[r].size()):
			if m[r][c] == 0:
				continue
			var rr: int = row + r
			var cc: int = col + c
			if rr < 0 or cc < 0 or cc >= TETRIS_COLS or rr >= TETRIS_ROWS:
				return true
			if _board[rr][cc] != "":
				return true
	return false


func _try_move(dr: int, dc: int) -> void:
	if _game_lost or _game_over:
		return
	if not _collides(_cur_type, _cur_rot, _cur_row + dr, _cur_col + dc):
		_cur_row += dr
		_cur_col += dc
		_render_board()


func _try_rotate() -> void:
	if _game_lost or _game_over:
		return
	var nrot: int = (_cur_rot + 1) % 4
	if not _collides(_cur_type, nrot, _cur_row, _cur_col):
		_cur_rot = nrot
		_render_board()
	elif not _collides(_cur_type, nrot, _cur_row, _cur_col - 1):
		# Wall kick one cell left.
		_cur_rot = nrot
		_cur_col -= 1
		_render_board()
	elif not _collides(_cur_type, nrot, _cur_row, _cur_col + 1):
		# Wall kick one cell right.
		_cur_rot = nrot
		_cur_col += 1
		_render_board()


func _hard_drop() -> void:
	if _game_lost or _game_over or _won or _clearing:
		return
	var m := _matrix(_cur_type, _cur_rot)
	while not _collides(_cur_type, _cur_rot, _cur_row + 1, _cur_col):
		_cur_row += 1
	_score += 2 * m.size() * m[0].size()
	_lock_piece()
	_update_score()


func _lock_piece() -> void:
	"""Freeze the current piece into the board, flash+clear complete lines, then
	spawn the next piece (or end the game if the win condition was reached)."""
	var m := _matrix(_cur_type, _cur_rot)
	for r in range(m.size()):
		for c in range(m[r].size()):
			if m[r][c] == 0:
				continue
			var rr: int = _cur_row + r
			var cc: int = _cur_col + c
			if rr >= 0 and rr < TETRIS_ROWS and cc >= 0 and cc < TETRIS_COLS:
				_board[rr][cc] = _cur_type

	_render_board()

	# Find complete rows.
	var full_rows: Array = []
	for r in range(TETRIS_ROWS):
		var full: bool = true
		for c in range(TETRIS_COLS):
			if _board[r][c] == "":
				full = false
				break
		if full:
			full_rows.append(r)

	if full_rows.is_empty():
		_after_lock()
		return

	# Flash the completed rows white, then collapse them.
	_clearing = true
	await _animate_line_clear(full_rows)

	var cleared: int = 0
	for r in range(TETRIS_ROWS - 1, -1, -1):
		var full: bool = true
		for c in range(TETRIS_COLS):
			if _board[r][c] == "":
				full = false
				break
		if full:
			_board.remove_at(r)
			var new_row: Array = []
			new_row.resize(TETRIS_COLS)
			new_row.fill("")
			_board.insert(0, new_row)
			cleared += 1
			r += 1  # re-check the same index after removal

	if cleared > 0:
		_lines_cleared += cleared
		_score += [0, 100, 300, 500, 800][min(cleared, 4)]
		# Speed up as the level rises.
		_level = 1 + int(_score / 500.0)
		_drop_interval = max(0.15, 1.0 - (0.05 * (_level - 1)))
		_update_score()

	_clearing = false
	_after_lock()


func _after_lock() -> void:
	"""Common tail of _lock_piece: check the win condition, else spawn the next."""
	if _score >= WIN_SCORE or _lines_cleared >= WIN_LINES:
		_show_win()
		return
	_render_board()
	_spawn_piece()


func _animate_line_clear(full_rows: Array) -> void:
	"""Flash the completed rows pure white for a moment (classic Tetris line
	clear), then let _lock_piece collapse them."""
	for t in _board_texs:
		if not is_instance_valid(t):
			continue
		var row: int = int(round(t.position.y / CELL))
		if full_rows.has(row):
			t.self_modulate = Color(1, 1, 1, 1)
	await get_tree().create_timer(0.28).timeout


func _render_board() -> void:
	"""Rebuild all piece blocks on the board layer from the _board grid (the
	single source of truth) plus the currently falling piece."""
	for t in _board_texs:
		if is_instance_valid(t):
			t.queue_free()
	_board_texs.clear()
	if not is_instance_valid(_board_layer):
		return
	for r in range(TETRIS_ROWS):
		for c in range(TETRIS_COLS):
			if _board[r][c] != "":
				var block: Control = _make_block(_board[r][c], CELL)
				block.position = Vector2(c * CELL, r * CELL)
				_board_layer.add_child(block)
				_board_texs.append(block)
	if not _game_lost and not _won:
		_add_piece_tex(_cur_type, _cur_rot, _cur_row, _cur_col)


func _make_block(type: String, cell: float) -> Control:
	"""Build one clean, square Tetris block using the white 'base' tile tinted to
	the piece's colour. The base is a solid white square with a black outline, so
	self_modulate recolours the fill while the black border stays black — exactly
	like a classic Tetris tile, with no sprite-slicing glitches."""
	var block := TextureRect.new()
	block.texture = load(BASE_BLOCK_TEX)
	block.self_modulate = PIECE_COLORS[type]
	block.size = Vector2(cell, cell)
	block.stretch_mode = TextureRect.STRETCH_SCALE
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return block


func _add_piece_tex(type: String, rot: int, row: int, col: int) -> void:
	# Render the piece block-by-block: every block is a clean, square, solid
	# colour with a black outline — no squish, no missing blocks.
	var m := _matrix(type, rot)
	for r in range(m.size()):
		for c in range(m[r].size()):
			if m[r][c] == 0:
				continue
			var block: Control = _make_block(type, CELL)
			block.position = Vector2((col + c) * CELL, (row + r) * CELL)
			_board_layer.add_child(block)
			_board_texs.append(block)


func _update_score() -> void:
	if is_instance_valid(_score_lbl):
		_score_lbl.text = str(_score)


func _render_next() -> void:
	"""Show the next 3 upcoming pieces in the side panel."""
	for t in _next_texs:
		if is_instance_valid(t):
			t.queue_free()
	_next_texs.clear()
	if not is_instance_valid(_next_layer):
		return
	for i in range(min(3, _next_queue.size())):
		_add_next_tex(_next_queue[i], i)


func _add_next_tex(type: String, slot: int) -> void:
	var preview_cell: float = 22.0
	var base: Array = PIECE_SHAPES[type]
	for r in range(base.size()):
		for c in range(base[r].size()):
			if base[r][c] == 0:
				continue
			var block: Control = _make_block(type, preview_cell)
			block.position = Vector2(30 + c * preview_cell, slot * 90.0 + r * preview_cell)
			_next_layer.add_child(block)
			_next_texs.append(block)


func _tetris_pulse(delta: float) -> void:
	"""Pulse the board once per beat (140 BPM) to the tetrino track."""
	if _game_over or _game_lost:
		return
	_beat_accum += delta
	if _beat_accum >= BEAT_SECONDS:
		_beat_accum -= BEAT_SECONDS
		_do_pulse()


func _do_pulse() -> void:
	if not is_instance_valid(_pulse_overlay):
		return
	var up: float = 0.12
	var tw := create_tween()
	tw.tween_property(_pulse_overlay, "modulate:a", up, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_pulse_overlay, "modulate:a", 0.0, BEAT_SECONDS - 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _tetris_step(delta: float) -> void:
	"""Per-frame gravity + game-over check."""
	if _game_lost:
		_show_game_over()
		return
	if _game_over or _won or _clearing:
		return
	_drop_accum += delta
	if _drop_accum >= _drop_interval:
		_drop_accum = 0.0
		if not _collides(_cur_type, _cur_rot, _cur_row + 1, _cur_col):
			_cur_row += 1
			_render_board()
		else:
			_lock_piece()


func _tetris_handle_input() -> void:
	if _game_lost or _game_over or _won or _clearing:
		return
	var left := Input.is_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_LEFT)
	var right := Input.is_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_RIGHT)
	var up := Input.is_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_UP)
	var down := Input.is_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_DOWN)
	var space := Input.is_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SPACE)

	if left and not _left_was_down:
		_try_move(0, -1)
	if right and not _right_was_down:
		_try_move(0, 1)
	if up and not _up_was_down:
		_try_rotate()
	# Hold down to keep soft-dropping at a fast rate.
	if down:
		_drop_accum = max(_drop_accum, _drop_interval - 0.05)
	if space and not _space_was_down:
		_hard_drop()

	_left_was_down = left
	_right_was_down = right
	_up_was_down = up
	_down_was_down = down
	_space_was_down = space


func _show_game_over() -> void:
	if _game_over:
		return
	_game_over = true
	# If this was a hard-mode gamble run, apply the fair punishment: you lose the
	# chance at the 2nd coin and are left with only the 1st.
	if _hard_mode:
		_on_gamble_lost()
	var p := _palette()
	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0.75)
	ov.position = Vector2(0, 0)
	ov.size = Vector2(ROOM_W, ROOM_H)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(ov)
	var title: String = "GAME OVER"
	if _hard_mode:
		title = "GAMBLE LOST\n(kept " + str(GameState.tetrino_coins_earned) + " coin)"
	var lbl := Label.new()
	lbl.text = title + "\nScore: " + str(_score) + "\nPress [ENTER] to retry"
	lbl.position = Vector2(0, 260)
	lbl.size = Vector2(ROOM_W, 200)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", p["accent"])
	lbl.add_theme_font_size_override("font_size", 34)
	_ui.add_child(lbl)


# ═══════════════ WIN / COIN REWARD ═══════════════

func _now_sec() -> int:
	return int(Time.get_unix_time_from_system())


func _same_day(a: int, b: int) -> bool:
	var da := Time.get_datetime_dict_from_unix_time(a)
	var db := Time.get_datetime_dict_from_unix_time(b)
	return da["year"] == db["year"] and da["month"] == db["month"] and da["day"] == db["day"]


func _detect_time_tamper(now: int) -> void:
	"""Best-effort anti-farming: if the wall clock has been rolled back since we
	last recorded a time (the classic daily-limit bypass), add a +5h penalty."""
	if GameState.tetrino_last_seen_time > 0 and now < GameState.tetrino_last_seen_time:
		GameState.tetrino_time_penalty_until = max(GameState.tetrino_time_penalty_until, now + TAMPER_PENALTY_SECONDS)
	if GameState.tetrino_last_coin_time > 0 and now < GameState.tetrino_last_coin_time:
		GameState.tetrino_time_penalty_until = max(GameState.tetrino_time_penalty_until, now + TAMPER_PENALTY_SECONDS)
	GameState.tetrino_last_seen_time = max(GameState.tetrino_last_seen_time, now)


func _daily_available(now: int) -> bool:
	"""Can this player earn a coin from Tetrino right now? Admins are unlimited;
	everyone else gets one coin-earning opportunity per calendar day."""
	if GameState.is_admin:
		return true
	if GameState.tetrino_time_penalty_until > 0 and now < GameState.tetrino_time_penalty_until:
		return false
	if GameState.tetrino_last_coin_time <= 0:
		return true
	return not _same_day(GameState.tetrino_last_coin_time, now)


func _save_tetrino_state() -> void:
	var uname: String = AuthManager.current_username
	if uname.is_empty():
		return
	SAVE_MGR_SCRIPT.autosave(uname)


func _resolve_win_reward() -> int:
	"""Apply the confirmed coin rules on a win and return how many coins were
	awarded this run (0..3). Updates GameState and persists."""
	var now := _now_sec()
	_detect_time_tamper(now)
	var awarded := 0
	if _daily_available(now) and not GameState.tetrino_gambled:
		var coins: int = GameState.tetrino_coins_earned
		if _hard_mode:
			# Gamble: a hard-mode win guarantees 3 coins total.
			if coins < 3:
				awarded = 3 - coins
				GameState.tetrino_coins_earned = 3
			GameState.tetrino_gambled = true
			GameState.tetrino_last_coin_time = now
		elif coins < 2:
			# Normal: 1st win → 1 coin, 2nd win → 2 (cap at 2).
			awarded = 1
			GameState.tetrino_coins_earned = coins + 1
			GameState.tetrino_last_coin_time = now
	elif _hard_mode:
		GameState.tetrino_gambled = true
	if awarded > 0:
		GameState.add_money(awarded)
		_save_tetrino_state()
	return awarded


func _on_gamble_lost() -> void:
	"""Lost the hard-mode gamble: drop to just the first coin and lock further
	earning (no 2nd coin) as a fair punishment."""
	if GameState.tetrino_coins_earned > 1:
		GameState.tetrino_coins_earned = 1
	GameState.tetrino_gambled = true
	_save_tetrino_state()


func _add_pixel_text(parent: Node, text: String, pos: Vector2, px_size: float, color: Color) -> void:
	"""Draw a string using the tiny 5x7 pixel font as scaled ColorRect pixels."""
	var x := 0.0
	for ch in text:
		var glyph: Array = PIX_FONT.get(String(ch), [])
		for row in range(glyph.size()):
			var line: String = glyph[row]
			for col in range(line.length()):
				if line[col] == "#":
					var px := ColorRect.new()
					px.color = color
					px.position = pos + Vector2((x + col) * px_size, row * px_size)
					px.size = Vector2(px_size, px_size)
					px.mouse_filter = Control.MOUSE_FILTER_IGNORE
					parent.add_child(px)
		x += 6.0  # glyph advance (5 wide + 1 spacing)


func _make_coin_shiny() -> void:
	"""A soft white sheen that sweeps across the reward coin, clipped to it."""
	if not is_instance_valid(_win_coin):
		return
	var clip := Control.new()
	clip.name = "CoinShine"
	clip.position = _win_coin.position
	clip.size = _win_coin.size
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(clip)
	var band := ColorRect.new()
	band.color = Color(1, 1, 1, 0.32)
	band.position = Vector2(-_win_coin.size.x, 0)
	band.size = Vector2(_win_coin.size.x * 0.6, _win_coin.size.y)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(band)
	var tw := create_tween().set_loops()
	tw.tween_property(band, "position:x", _win_coin.size.x * 1.8, 1.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(0.5)


func _show_win() -> void:
	"""The minigame was won: play the completion fanfare, show the shiny reward
	coin with a pixelated +N, and offer retry / gamble."""
	if _won:
		return
	_won = true

	# Play the win fanfare (replace the tetrino music).
	if _music:
		_music.stop()
	var complete := AudioStreamPlayer.new()
	complete.stream = load(TETRINO_COMPLETE)
	complete.bus = "Music"
	add_child(complete)
	complete.play()

	var awarded := _resolve_win_reward()
	var can_gamble: bool = _daily_available(_now_sec()) \
		and GameState.tetrino_coins_earned == 1 and not GameState.tetrino_gambled
	var p := _palette()

	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0.8)
	ov.position = Vector2(0, 0)
	ov.size = Vector2(ROOM_W, ROOM_H)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(ov)

	var title := Label.new()
	title.text = "CONGRATULATIONS!"
	title.position = Vector2(0, 96)
	title.size = Vector2(ROOM_W, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", p["accent"])
	title.add_theme_font_size_override("font_size", 54)
	_ui.add_child(title)

	var sub := Label.new()
	sub.text = "YOU WIN — TETRINO COMPLETE"
	sub.position = Vector2(0, 168)
	sub.size = Vector2(ROOM_W, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", p["text"])
	sub.add_theme_font_size_override("font_size", 24)
	_ui.add_child(sub)

	# The shiny reward coin, centred.
	_win_coin = TextureRect.new()
	_win_coin.texture = load(COIN_TEX)
	_win_coin.position = Vector2(ROOM_W / 2.0 - 62, 232)
	_win_coin.size = Vector2(124, 124)
	_win_coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_win_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_win_coin)
	_make_coin_shiny()

	# Pixelated "+N" next to the coin.
	if awarded > 0:
		_add_pixel_text(_ui, "+" + str(awarded), Vector2(ROOM_W / 2.0 + 92, 292), 4.0, Color(1.0, 0.85, 0.2))
	else:
		_add_pixel_text(_ui, "+0", Vector2(ROOM_W / 2.0 + 92, 292), 4.0, p["text_dim"])

	var reward := Label.new()
	if awarded > 0:
		reward.text = "Reward: " + str(awarded) + " Grassconatication coin" + ("s" if awarded > 1 else "")
	else:
		reward.text = "No coin today" + ("" if GameState.is_admin else " (daily limit)") + " — play for fun!"
	reward.position = Vector2(0, 380)
	reward.size = Vector2(ROOM_W, 40)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward.add_theme_color_override("font_color", p["text"])
	reward.add_theme_font_size_override("font_size", 22)
	_ui.add_child(reward)

	var prompt := Label.new()
	var lines: Array = ["Press [ENTER] to play again"]
	if can_gamble:
		lines.append("Press [G] to GAMBLE — HARD MODE (3 coins on win)")
	prompt.text = "\n".join(lines)
	prompt.position = Vector2(0, 440)
	prompt.size = Vector2(ROOM_W, 90)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", p["accent"])
	prompt.add_theme_font_size_override("font_size", 22)
	_ui.add_child(prompt)


func _handle_win_input() -> void:
	"""On the win screen: G starts the hard-mode gamble run (when available)."""
	var g := Input.is_key_pressed(KEY_G) or Input.is_physical_key_pressed(KEY_G)
	if g and not _g_was_down:
		if _daily_available(_now_sec()) and GameState.tetrino_coins_earned == 1 \
				and not GameState.tetrino_gambled:
			_hard_mode = true
			_start_tetrino_game()
	_g_was_down = g


func _exit_tetrino_game() -> void:
	"""ESC from inside the game goes back to the Tetrino title screen and stops
	the music (it only plays while actually in the minigame)."""
	if not _game_active:
		return
	_intro_active = false
	if _music:
		_music.stop()
	_menu_active = false
	_game_active = false
	for child: Node in _ui.get_children():
		child.queue_free()
	_show_tetrino_menu()


func _close_tetrino() -> void:
	_intro_active = false
	_menu_active = false
	_game_active = false
	if is_instance_valid(_cart):
		_cart.stop()
		_cart.queue_free()
		_cart = null
	for child: Node in _ui.get_children():
		child.queue_free()
	# Back to the cartridge browser (music stops — it only plays in the game).
	if _music:
		_music.stop()
	_show_minigame_browser()


# ═══════════════ TRANSITIONS ═══════════════

func _leave_arcade_room() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _reveal_from_black() -> void:
	# A black panel slides from covering the screen out to the left, revealing
	# the room (completes the right-to-left wipe started in the lobby).
	var wipe := ColorRect.new()
	wipe.color = Color(0, 0, 0, 1)
	wipe.position = Vector2(0, 0)
	wipe.size = Vector2(ROOM_W, ROOM_H)
	wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(wipe)
	var tween := create_tween()
	tween.tween_property(wipe, "position", Vector2(-ROOM_W, 0), 0.35)
	await tween.finished
	wipe.queue_free()
