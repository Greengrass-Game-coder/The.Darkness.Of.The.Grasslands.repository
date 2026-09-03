class_name ArcadeRoom
extends Node2D
## The Darkness Of The Grasslands — Arcade Room
## A pitch-black room with a single interactable arcade machine. Interacting
## boots it up like a retro console (VHS flicker → boot text → quick loading
## bar) and then shows the "Tetrivo" title/menu screen with its thumbnail and
## a looping tetrino.wav track. Built programmatically for reliability.

# ── Scene / asset paths ──
const ARCADE_MACHINE_TEX: String = "res://The Darkness Of The Grasslands assets/objects/arcade machine.png"
const TETRIVO_MUSIC: String = "res://The Darkness Of The Grasslands assets/Music/Minigames/tetrino.wav"
const CARTRIDGE_START: String = "res://The Darkness Of The Grasslands assets/Sound/Minigames/Cartridge_START_140BPM.wav"
# Console background music (plays while the console navigator is on) + its
# navigation feedback sounds.
const CONSOLE_MUSIC: String = "res://The Darkness Of The Grasslands assets/Music/Minigames/Console-navigation-music.wav"
# Boot-up sound played while the console turns on, before the navigator music.
const CONSOLE_BOOTUP: String = "res://The Darkness Of The Grasslands assets/Sound/Minigames/Console-bootup.wav"
const CONSOLE_CONFIRM: String = "res://The Darkness Of The Grasslands assets/Sound/Minigames/Console-confirm-sound.wav"
const CONSOLE_ERROR: String = "res://The Darkness Of The Grasslands assets/Sound/Minigames/Navigation-error-cant-navigate.wav"
const TETRIVO_CHOICE: String = "res://The Darkness Of The Grasslands assets/Sound/Minigames/tetrino-minigame-choice.wav"
# Subtle old-console CRT post-process overlay (pixelation, faint scanlines,
# gentle curvature, static only while loading).
const CONSOLE_CRT_SHADER: String = "res://shaders/console_crt.gdshader"
const TETRIVO_THUMB: String = "res://The Darkness Of The Grasslands assets/Thumbnails/Minigame_TETRINO.thumnail.png"
# Dirtysweeper cartridge: its own thumbnail. It now plays EMBEDDED inside this
# arcade scene (no separate scene) — exactly like Tetrivo does.
const DIRTSWEEPER_THUMB: String = "res://The Darkness Of The Grasslands assets/Thumbnails/Minigame_dirtysweeper.thumbnail.png"
# Dirtysweeper (minesweeper) constants + face artwork.
const DS_CELL: float = 46.0
const DS_GRID: int = 9
const DS_MINES: int = 10
const DS_MINES_HARD: int = 16
const DS_FACE_NEUTRAL: String = "res://The Darkness Of The Grasslands assets/UI/minigames/Minigame_minesweeper_neutral_face.png"
const DS_FACE_WARNING: String = "res://The Darkness Of The Grasslands assets/UI/minigames/Minigame_minesweeper_warning_face.png"
const DS_FACE_DEAD: String = "res://The Darkness Of The Grasslands assets/UI/minigames/Minigame_minesweeper_dead_face.png"
const DS_FACE_NEUTRAL_G: String = "res://The Darkness Of The Grasslands assets/UI/minigames/Minigame_minesweeper_neutral_face_gambling.png"
const DS_FACE_WARNING_G: String = "res://The Darkness Of The Grasslands assets/UI/minigames/Minigame_minesweeper_warning_face_gambling.png"
const DS_FACE_DEAD_G: String = "res://The Darkness Of The Grasslands assets/UI/minigames/Minigame_minesweeper_dead_face_gambling.png"
# Classic minesweeper number colours.
const DS_NUM_COLORS: Array = [Color.BLACK, Color(0.2,0.35,0.9), Color(0.1,0.6,0.2), Color(0.85,0.15,0.15),
	Color(0.3,0.1,0.6), Color(0.5,0.15,0.4), Color(0.1,0.6,0.65), Color.BLACK, Color(0.4,0.4,0.4)]
# 140 BPM → one beat every 60/140 seconds (pulse the game to the music).
const BEAT_SECONDS: float = 60.0 / 140.0
const SOFT_DROP_INTERVAL: float = 0.06  # rows/second pace while holding Down (fast fall)
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
const TETRIVO_COMPLETE: String = "res://The Darkness Of The Grasslands assets/Music/Minigames/MINIGAME-COMPLETED.wav"
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
const GAME_MAP_SCENE: String = "res://scenes/game_map.tscn"
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
# Walk past this X (left edge of the room) to leave back to the lobby.
const LEFT_EXIT_X: float = -20.0

# ── Boot sequence timing ──
const FLICKER_DURATION: float = 0.7
const BOOT_TEXT: String = "COMPUTERING CONSOLE — THE MAGIC ENTERTAINER — BOOT V0.5P.R.O.T.O.T.Y.P.E."
const MAGIC_ICON: String = "res://The Darkness Of The Grasslands assets/UI/minigames/The-Magic-Entertainer-icon.png"
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
var _intermission_label: Label = null
var _intermission_prompt: Control = null
var _intermission_prompt_active: bool = false
var _boot_active: bool = false
var _browser_active: bool = false   # Minigame browser (list of cartridges)
var _menu_active: bool = false      # A specific minigame's title/menu is showing
var _game_active: bool = false      # The actual Tetris minigame is running
# ── Dirtysweeper (minesweeper) embedded minigame state ──
var _dirty_active: bool = false        # Dirtysweeper minigame is running
var _dirty_hard: bool = false          # hard (16-mine) gamble mode
var _dirty_board: Array = []           # _dirty_board[r][c] = {mine, revealed, flagged, count}
var _dirty_cursor: Vector2i = Vector2i(0, 0)
var _dirty_game_over: bool = false
var _dirty_won: bool = false
var _dirty_flag_mode: bool = false
var _dirty_move_timer: float = 0.0
var _dirty_press_armed: bool = false   # holding a cell (worried-face state)
var _dirty_press_cell: Vector2i = Vector2i(-1, -1)
var _dirty_buttons: Array = []         # _dirty_buttons[r][c] = Button
var _dirty_cursor_rect: ColorRect = null
var _dirty_face_btn: Button = null
var _dirty_face_tex: TextureRect = null
var _dirty_status: Label = null
var _dirty_counts: Label = null
var _dirty_win_awarded: bool = false   # prevents double-award on the same win
var _dirty_root: Control = null        # root Control holding the DS UI (child of _ui)
var _browser_cartridge: Control = null  # the Tetrivo cartridge (nudged/shaken on nav)
var _browser_index: int = 0                 # which browser cartridge is selected
var _browser_entries: Array = []            # each: {name, thumb, cost} in Grass coins
var _browser_cartridges: Array = []         # built cartridge Control nodes
var _browser_grid: Array = []               # grid coords (Vector2) per cartridge, for 2D nav + scaling
var _browser_row: Control = null            # row container that pans like a camera
var _browser_highlight: ColorRect = null    # gold selection frame around the chosen cartridge
var _cant_afford_label: Label = null        # transient "not enough coins" note
var _purchase_confirm: bool = false         # purchase confirmation overlay open
var _gift_active: bool = false              # gift recipient picker open
var _gift_friends: Array = []               # candidate recipients ({name,source,peer})
var _gift_index: int = 0                    # highlighted recipient
var _gift_overlay: Control = null           # recipient picker overlay
var _gift_rows: Array = []                  # picker row labels
var _gift_nav_was_down: bool = false
var _gift_inbox_active: bool = false        # accept/deny prompt open
var _inbox_gift: Dictionary = {}            # the gift being decided
var _inbox_overlay: Control = null          # accept/deny prompt overlay
var _cart_shaking: bool = false          # true while the cartridge shake plays
var _music: AudioStreamPlayer = null
var _idle_anim: String = "idle_down"
var _e_was_down: bool = false
var _esc_was_down: bool = false
var _enter_was_down: bool = false
var _nav_was_down: bool = false
var _t_was_down: bool = false
var _theme_label: Label = null

# ── Console rhythm / beat-sync state ──
var _console_music: AudioStreamPlayer = null  # background music while console is on
var _last_beat_index: int = -1                # last detected beat (for edge detection)
var _pending_action: Callable = Callable()    # action fired on the next detected beat
var _last_beat_time_msec: int = 0             # when _on_beat last fired (for SFX beat-sync)
var _esc_lock_until: float = 0.0              # debounce ESC so it can't spam/glitch

# ── Console CRT overlay state ──
var _crt_layer: CanvasLayer = null     # top canvas layer holding the CRT overlay
var _crt_rect: ColorRect = null        # full-screen ColorRect with the CRT shader
var _crt_mat: ShaderMaterial = null    # the CRT shader material (noise/scanline) 

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
var _soft_drop: bool = false              # holding Down → fast fall (real-Tetris soft drop)
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
var _leaving: bool = false         # a leave/black-block transition is in progress


func _ready() -> void:
	_load_theme()
	_build_room()
	_build_player()
	_build_machine()
	# Keep the machine's interact prompt in sync with the assigned input binding
	# and the device currently in use (keyboard / gamepad / touch).
	if not InputSystem.device_changed.is_connected(_refresh_machine_prompt):
		InputSystem.device_changed.connect(_refresh_machine_prompt)
	_build_ui()
	# Reveal from black (right-to-left wipe continues from the lobby).
	_reveal_from_black()
	# Phone/tablet: connect the touch-controls drag/tap navigation signals and
	# start in the room-walking layout (the browser switches it to "browser").
	if not TouchControls.swipe.is_connected(_on_touch_swipe):
		TouchControls.swipe.connect(_on_touch_swipe)
	if not TouchControls.tap.is_connected(_on_touch_tap):
		TouchControls.tap.connect(_on_touch_tap)
	TouchControls.set_mode(TouchControls.OVERWORLD)


## Lets the global PauseManager know whether the console UI is on-screen, so
## pressing Pause here opens Settings (the console pause) instead of the full
## in-game pause menu (where ESC already means cancel/back).
func console_ui_active() -> bool:
	return _boot_active or _browser_active or _menu_active or _game_active or _gift_active or _gift_inbox_active


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
		_rebuild_tetrivo()
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
	_machine_prompt.text = _machine_prompt_text()
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
	_build_intermission_notification()


# ═══════════════ INTERMISSION NOTIFICATION ═══════════════
#
# A small top-left notice that mirrors the lobby's intermission countdown. It
# reads from the IntermissionTimer autoload so it stays in sync with the lobby
# (the timer keeps running across the scene change) instead of resetting.

func _build_intermission_notification() -> void:
	_intermission_label = Label.new()
	_intermission_label.name = "IntermissionLabel"
	_intermission_label.position = Vector2(24, 20)
	_intermission_label.size = Vector2(420, 32)
	_intermission_label.add_theme_font_size_override("font_size", 20)
	_intermission_label.add_theme_color_override("font_color", Color(0.6, 1.0, 1.0))
	_intermission_label.add_theme_constant_override("outline_size", 4)
	_intermission_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_ui.add_child(_intermission_label)
	if not IntermissionTimer.ticked.is_connected(_on_intermission_ticked):
		IntermissionTimer.ticked.connect(_on_intermission_ticked)
	if not IntermissionTimer.finished.is_connected(_on_intermission_finished):
		IntermissionTimer.finished.connect(_on_intermission_finished)
	_update_intermission_label()


func _update_intermission_label() -> void:
	if not is_instance_valid(_intermission_label):
		return
	_intermission_label.visible = IntermissionTimer.running
	if IntermissionTimer.running:
		_intermission_label.text = "Intermission: %d left." % IntermissionTimer.seconds_left()


func _on_intermission_ticked(_seconds_left: int) -> void:
	_update_intermission_label()


# ── Intermission-finished: JOIN / KEEP PLAYING choice ──────────────────
#
# When the intermission ends while the player is in the console, we don't
# teleport them into the match. Instead we surface a little heads-up and let
# them join the match or keep playing on the console.

func _on_intermission_finished() -> void:
	_update_intermission_label()  # countdown is over, hide the label
	_show_intermission_prompt()


func _show_intermission_prompt() -> void:
	if _intermission_prompt_active:
		return
	_intermission_prompt_active = true

	var panel := Panel.new()
	panel.name = "IntermissionPrompt"
	panel.size = Vector2(560, 200)
	panel.position = Vector2((ROOM_W - 560) / 2.0, (ROOM_H - 200) / 2.0)
	panel.add_theme_stylebox_override("panel", _prompt_panel_style())
	_ui.add_child(panel)
	_intermission_prompt = panel

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 24
	box.offset_right = -24
	box.offset_top = 20
	box.offset_bottom = -20
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "A MATCH JUST STARTED!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 1.0, 0.55))
	box.add_child(title)

	var sub := Label.new()
	sub.text = "The intermission is over. Join the match, or keep playing on the console."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	box.add_child(sub)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	box.add_child(hbox)

	var join_btn := Button.new()
	join_btn.name = "JoinMatchButton"
	join_btn.text = "JOIN MATCH"
	join_btn.custom_minimum_size = Vector2(200, 46)
	join_btn.add_theme_font_size_override("font_size", 20)
	join_btn.pressed.connect(_join_match_from_prompt)
	hbox.add_child(join_btn)

	var keep_btn := Button.new()
	keep_btn.name = "KeepPlayingButton"
	keep_btn.text = "KEEP PLAYING"
	keep_btn.custom_minimum_size = Vector2(200, 46)
	keep_btn.add_theme_font_size_override("font_size", 20)
	keep_btn.pressed.connect(_keep_playing_from_prompt)
	hbox.add_child(keep_btn)

	# Default to JOIN focused; left/right (D-pad / arrows) moves between the
	# two buttons and Enter/A activates the focused one (via Godot's ui_*).
	join_btn.grab_focus()


func _prompt_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.97)
	sb.border_color = Color(0.35, 1.0, 1.0, 0.9)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	return sb


func _join_match_from_prompt() -> void:
	_hide_intermission_prompt()
	get_tree().change_scene_to_file(GAME_MAP_SCENE)


func _keep_playing_from_prompt() -> void:
	_hide_intermission_prompt()


func _hide_intermission_prompt() -> void:
	_intermission_prompt_active = false
	if is_instance_valid(_intermission_prompt):
		_intermission_prompt.queue_free()
	_intermission_prompt = null


# ═══════════════ PLAYER CONTROL ═══════════════

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	# While the "A match just started!" prompt is up, freeze the player and only
	# let Esc/B mean "keep playing" (JOIN is handled by the focused button).
	# Everything else is handled by the prompt's own buttons.
	if _intermission_prompt_active:
		_player.velocity = Vector2.ZERO
		if is_instance_valid(_sprite):
			_sprite.animation = _idle_anim
		var esc_p := InputSystem.is_pressed("cancel")
		if esc_p and not _esc_was_down:
			_keep_playing_from_prompt()
		_esc_was_down = esc_p
		return

	# While the Dirtysweeper minigame is running, it owns all input (movement,
	# confirm/cancel, flag, restart). Freeze the player and return early.
	if _dirty_active:
		_player.velocity = Vector2.ZERO
		if is_instance_valid(_sprite):
			_sprite.animation = _idle_anim
		_dirty_process(delta)
		_dirty_handle_input()
		return

	# Edge-detected input (interact / cancel), driven by the InputSystem so it
	# honours rebinds and works with keyboard + gamepad.
	var e_down := InputSystem.is_pressed("interact")
	if e_down and not _e_was_down:
		_on_e_pressed()
	var esc_down := InputSystem.is_pressed("cancel")
	if esc_down and not _esc_was_down:
		_on_esc_pressed()
	_e_was_down = e_down
	_esc_was_down = esc_down

	# Minigame browser: WASD tries to navigate, Enter launches the highlighted
	# game, Esc leaves. In the demo there is only Tetrivo, so WASD just shows a
	# friendly "this is all we have" nag.
	# Enter: in the browser it launches Tetrivo; on the Tetrivo title screen it
	# starts the actual minigame (which is when the music plays).
	var enter_down := InputSystem.is_pressed("confirm")
	if enter_down and not _enter_was_down:
		_on_enter_pressed()
	_enter_was_down = enter_down

	# G opens the gift picker from the purchase screen, and denies a gift from
	# the inbox prompt. (Reuses the "gamble" action, which is only used on the
	# Tetrivo win screen and is otherwise free.)
	# G also opens the gift picker straight from the browser for any PAID
	# cartridge — so a gifter who already owns the game can still buy it for a
	# friend.
	var g_down := InputSystem.is_pressed("gamble")
	if g_down and not _g_was_down:
		if _purchase_confirm and not _gift_active:
			_open_gift_picker()
		elif _gift_inbox_active:
			_deny_gift()
		elif _browser_active and _selected_is_paid() and not _gift_active:
			_open_gift_picker()
	_g_was_down = g_down

	# Gift recipient picker: up/down moves the highlight, Enter picks (handled
	# in _on_enter_pressed), Esc backs out (handled in _on_esc_pressed).
	if _gift_active:
		var gnav := InputSystem.is_pressed("move_up") or InputSystem.is_pressed("move_down")
		if gnav and not _gift_nav_was_down:
			_gift_nav(InputSystem.is_pressed("move_up"))
		_gift_nav_was_down = gnav
	else:
		_gift_nav_was_down = false

	if _browser_active and not _menu_active and not _boot_active:
		# Sync navigation/confirm actions to the console music's 140 BPM beat.
		_update_beat_clock()
		var nav_down := (
			InputSystem.is_pressed("move_up") or InputSystem.is_pressed("move_down")
			or InputSystem.is_pressed("move_left") or InputSystem.is_pressed("move_right")
		)
		if nav_down and not _nav_was_down:
			_on_browser_navigate()
		var t_down := InputSystem.is_pressed("display_toggle")
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

	if _boot_active or _browser_active or _menu_active or _gift_inbox_active:
		_player.velocity = Vector2.ZERO
		if is_instance_valid(_sprite):
			_sprite.animation = _idle_anim
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed := 160.0
	if InputSystem.is_pressed("sprint"):
		speed = 250.0
	if input_dir != Vector2.ZERO:
		_player.velocity = input_dir * speed
		_update_walk_anim(input_dir)
	else:
		_player.velocity = Vector2.ZERO
		if is_instance_valid(_sprite):
			_sprite.animation = _idle_anim
	_player.move_and_slide()
	# Leave the arcade room by walking left (back to the lobby). Only reachable
	# while idle in the room (the console states return earlier above).
	if _player.global_position.x < LEFT_EXIT_X:
		_leave_arcade_room()


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
	if _gift_inbox_active:
		_accept_gift()
		return
	if _gift_active:
		_confirm_gift()
		return
	if _purchase_confirm:
		_confirm_purchase()
		return
	if _game_active and (_game_over or _won):
		# Game over / win screen: Enter retries (normal mode).
		_hard_mode = false
		_start_tetrivo_game()
		return
	if _intro_active:
		return
	if _browser_active and not _menu_active and not _boot_active:
		# Launching a minigame is beat-synced: play the console confirm blip and
		# actually enter on the next detected beat.
		_pending_action = _confirm_launch_tetrivo
	elif _menu_active and not _game_active:
		# On the Tetrivo title screen, Enter plays the cartridge-start sound,
		# zooms into the game, and then begins the actual minigame (which is
		# when the music starts).
		_start_tetrivo_intro()


func _confirm_launch_tetrivo() -> void:
	"""Play the console confirm sound, then launch the highlighted cartridge.
	For a paid cartridge that isn't owned yet, this first opens the purchase
	screen (which requires your game profile) — once bought it's a permanent,
	profile-linked unlock. Called on a beat so the blip/transition land on
	rhythm."""
	_play_console_sfx(CONSOLE_CONFIRM, 1.0, 1.0)
	var cost: int = _selected_cartridge_cost()
	if cost <= 0:
		# Free, or already owned — launch straight away.
		_play_console_sfx(TETRIVO_CHOICE, 1.0, 1.0)
		_launch_tetrivo()
		return
	# A purchase that isn't owned yet: you must be on your game profile first.
	if AuthManager.current_username.is_empty():
		_play_console_sfx(CONSOLE_ERROR, 0.8, 1.25)
		_show_browser_notice("ACCESS YOUR GAME PROFILE FIRST TO PURCHASE", Color(1.0, 0.5, 0.3))
		return
	_show_purchase_overlay(cost)


func _show_purchase_overlay(cost: int) -> void:
	"""Show the profile/purchase confirmation over the browser. Enter confirms a
	permanent, profile-linked purchase; ESC cancels back to the browser."""
	if _purchase_confirm:
		return
	_purchase_confirm = true
	var p := _palette()
	var entry: Dictionary = _browser_entries[clampi(_browser_index, 0, _browser_entries.size() - 1)]
	var ov := ColorRect.new()
	ov.name = "PurchaseOverlay"
	ov.color = Color(0, 0, 0, 0.82)
	ov.position = Vector2(0, 0)
	ov.size = Vector2(ROOM_W, ROOM_H)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(ov)
	var lbl := Label.new()
	lbl.text = "PURCHASE CONFIRMATION\n\n" \
		+ "%s  —  %d Grass coins\n\n" % [entry["name"], cost] \
		+ "PROFILE: " + AuthManager.current_username + "\n\n" \
		+ "This purchase is PERMANENT and linked to your profile.\n" \
		+ "You will own %s forever.\n\n" % entry["name"] \
		+ "[ENTER] buy for self    [G] GIFT to a friend\n" \
		+ "[ESC] cancel"
	lbl.position = Vector2(0, 240)
	lbl.size = Vector2(ROOM_W, 300)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", p["accent"])
	lbl.add_theme_font_size_override("font_size", 26)
	_ui.add_child(lbl)


func _confirm_purchase() -> void:
	"""Enter on the purchase screen: spend the coins, unlock TETRIVO 2
	permanently on this profile, then launch it."""
	if not _purchase_confirm:
		return
	var cost: int = _selected_cartridge_cost()
	if cost <= 0:
		_cancel_purchase()
		return
	if cost > _coin_balance():
		_cancel_purchase()
		_play_console_sfx(CONSOLE_ERROR, 0.8, 1.25)
		_show_cant_afford(cost)
		return
	_play_console_sfx(CONSOLE_CONFIRM, 1.0, 1.0)
	_spend_coins(cost)
	var entry: Dictionary = _browser_entries[clampi(_browser_index, 0, _browser_entries.size() - 1)]
	var owned_key: String = entry.get("owned_key", "tetrivo_owns_paid")
	GameState.set(owned_key, true)
	_save_tetrivo_state()
	_purchase_confirm = false
	for child: Node in _ui.get_children():
		child.queue_free()
	_play_console_sfx(TETRIVO_CHOICE, 1.0, 1.0)
	_launch_tetrivo()


func _cancel_purchase() -> void:
	"""ESC on the purchase screen: back to the browser without buying."""
	if not _purchase_confirm:
		return
	_purchase_confirm = false
	_browser_active = false  # allow the browser to rebuild below
	var keep: int = _browser_index
	for child: Node in _ui.get_children():
		child.queue_free()
	_show_minigame_browser()
	# Return to the same cartridge the player was looking at before buying.
	_browser_index = keep
	_center_browser(false)


# ═══════════════ GIFTING ═══════════════

func _selected_cartridge_name() -> String:
	if _browser_entries.is_empty():
		return "?"
	return str(_browser_entries[clampi(_browser_index, 0, _browser_entries.size() - 1)]["name"])


func _selected_owned_key() -> String:
	if _browser_entries.is_empty():
		return ""
	return str(_browser_entries[clampi(_browser_index, 0, _browser_entries.size() - 1)].get("owned_key", ""))


## True when the currently selected cartridge is a paid one — regardless of
## whether the player already owns it. Lets an owner still gift it to a friend.
func _selected_is_paid() -> bool:
	if _browser_entries.is_empty():
		return false
	return int(_browser_entries[clampi(_browser_index, 0, _browser_entries.size() - 1)].get("cost", 0)) > 0


## Build the list of giftable recipients: local profiles + online peers who
## don't already own the selected cartridge (self excluded).
func _build_gift_friends() -> void:
	_gift_friends.clear()
	var me: String = AuthManager.current_username
	var owned_key: String = _selected_owned_key()
	for name: String in GiftSystem.list_local_profiles():
		if name.to_lower() == me.to_lower():
			continue
		if not owned_key.is_empty() and GiftSystem.local_owns(name, owned_key):
			continue
		_gift_friends.append({"name": name, "source": "local", "peer": 0})


func _open_gift_picker() -> void:
	if _gift_active:
		return
	_build_gift_friends()
	if _gift_friends.is_empty():
		_play_console_sfx(CONSOLE_ERROR, 0.8, 1.25)
		_show_browser_notice("NO FRIENDS AVAILABLE TO GIFT", Color(1.0, 0.5, 0.3))
		return
	_gift_index = 0
	_gift_active = true
	_show_gift_overlay()


func _show_gift_overlay() -> void:
	if _gift_overlay != null and is_instance_valid(_gift_overlay):
		return
	var p := _palette()
	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0.82)
	ov.position = Vector2(0, 0)
	ov.size = Vector2(ROOM_W, ROOM_H)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(ov)
	_gift_overlay = ov

	var title := Label.new()
	title.text = "GIFT %s — CHOOSE A FRIEND" % _selected_cartridge_name()
	title.position = Vector2(0, 120)
	title.size = Vector2(ROOM_W, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", p["accent"])
	title.add_theme_font_size_override("font_size", 30)
	ov.add_child(title)

	var list := VBoxContainer.new()
	list.name = "GiftList"
	list.position = Vector2(ROOM_W / 2.0 - 300, 190)
	list.size = Vector2(600, 0)
	ov.add_child(list)
	_gift_rows.clear()
	_draw_gift_list()


func _draw_gift_list() -> void:
	if _gift_overlay == null or not is_instance_valid(_gift_overlay):
		return
	var list: Node = _gift_overlay.get_node_or_null("GiftList")
	if list == null:
		return
	for c in list.get_children():
		c.queue_free()
	_gift_rows.clear()
	var p := _palette()
	for i in range(_gift_friends.size()):
		var friend: Dictionary = _gift_friends[i]
		var lbl := Label.new()
		var mark: String = "> " if i == _gift_index else "  "
		lbl.text = mark + str(friend["name"]) + ("  (online)" if friend["source"] == "online" else "")
		lbl.size = Vector2(600, 36)
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", p["accent"] if i == _gift_index else p["text"])
		list.add_child(lbl)
		_gift_rows.append(lbl)


func _gift_nav(up: bool) -> void:
	if not _gift_active or _gift_friends.is_empty():
		return
	_play_console_sfx(CONSOLE_CONFIRM, 0.7, 1.0)
	if up:
		_gift_index = (_gift_index - 1 + _gift_friends.size()) % _gift_friends.size()
	else:
		_gift_index = (_gift_index + 1) % _gift_friends.size()
	_draw_gift_list()


func _confirm_gift() -> void:
	if not _gift_active or _gift_friends.is_empty():
		return
	var entry: Dictionary = _browser_entries[clampi(_browser_index, 0, _browser_entries.size() - 1)]
	var cost: int = int(entry["cost"])
	if cost > _coin_balance():
		_play_console_sfx(CONSOLE_ERROR, 0.8, 1.25)
		_show_cant_afford(cost)
		return
	var friend: Dictionary = _gift_friends[_gift_index]
	_play_console_sfx(CONSOLE_CONFIRM, 1.0, 1.0)
	_spend_coins(cost)
	var cart_name: String = str(entry["name"])
	GiftSystem.create_local_gift(AuthManager.current_username, str(friend["name"]), cart_name)
	_gift_active = false
	if _gift_overlay != null and is_instance_valid(_gift_overlay):
		_gift_overlay.queue_free()
	_gift_overlay = null
	if _purchase_confirm:
		_cancel_purchase()  # rebuilds the browser (clears purchase + picker)
	# Gifting an already-owned game stays on the browser — just close the picker.
	_show_browser_notice("GIFTED %s → %s" % [cart_name, friend["name"]], Color(0.4, 1.0, 0.6))


func _cancel_gift() -> void:
	if not _gift_active:
		return
	_gift_active = false
	if _gift_overlay != null and is_instance_valid(_gift_overlay):
		_gift_overlay.queue_free()
	_gift_overlay = null


# ── Gift inbox (accept / deny) ────────────────────────────────────────────

func _show_gift_inbox(gift: Dictionary) -> void:
	if _gift_inbox_active:
		return
	_gift_inbox_active = true
	_inbox_gift = gift
	var p := _palette()
	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0.82)
	ov.position = Vector2(0, 0)
	ov.size = Vector2(ROOM_W, ROOM_H)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(ov)
	_inbox_overlay = ov

	var title := Label.new()
	title.text = "INCOMING GIFT!"
	title.position = Vector2(0, 210)
	title.size = Vector2(ROOM_W, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", p["accent"])
	title.add_theme_font_size_override("font_size", 42)
	ov.add_child(title)

	var body := Label.new()
	body.text = "%s sent you %s!\n\n[ENTER] ACCEPT    [G] DENY (gifter refunded)" \
		% [str(gift.get("gifter", "A friend")), str(gift.get("cartridge", "a game"))]
	body.position = Vector2(0, 290)
	body.size = Vector2(ROOM_W, 140)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_color_override("font_color", p["text"])
	body.add_theme_font_size_override("font_size", 24)
	ov.add_child(body)


func _hide_gift_inbox() -> void:
	_gift_inbox_active = false
	if _inbox_overlay != null and is_instance_valid(_inbox_overlay):
		_inbox_overlay.queue_free()
	_inbox_overlay = null


func _accept_gift() -> void:
	if not _gift_inbox_active:
		return
	GiftSystem.accept_gift(_inbox_gift)
	_hide_gift_inbox()
	_show_browser_notice("GIFT ACCEPTED!", Color(0.4, 1.0, 0.6))


func _deny_gift() -> void:
	if not _gift_inbox_active:
		return
	GiftSystem.deny_gift(_inbox_gift)
	_hide_gift_inbox()
	_show_browser_notice("GIFT DECLINED — GIFTED REFUNDED", Color(1.0, 0.6, 0.4))


## Show the first undecided local gift addressed to the current profile.
func _show_first_pending_gift() -> void:
	if _gift_inbox_active:
		return
	var me: String = AuthManager.current_username
	if me.is_empty():
		return
	var pending: Array = GiftSystem.pending_for(me)
	if not pending.is_empty():
		_show_gift_inbox(pending[0])


func _show_browser_notice(text: String, color: Color) -> void:
	"""A transient one-line notice at the bottom of the browser screen."""
	if _cant_afford_label != null and is_instance_valid(_cant_afford_label):
		_cant_afford_label.queue_free()
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(0, ROOM_H - 190)
	lbl.size = Vector2(ROOM_W, 30)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 22)
	_ui.add_child(lbl)
	_cant_afford_label = lbl
	await get_tree().create_timer(1.6).timeout
	if is_instance_valid(lbl):
		lbl.queue_free()


func _cartridge_owned(entry: Dictionary) -> bool:
	"""Whether a paid cartridge has already been bought (permanent, profile-linked
	unlock). Free cartridges are never 'owned' — they're always free."""
	if not bool(entry.get("paid", false)):
		return false
	var key: String = entry.get("owned_key", "")
	if key == "":
		return false
	return bool(GameState.get(key))


func _selected_cartridge_cost() -> int:
	"""Cost to launch the selected cartridge right now: 0 for free games and for
	a paid cartridge you already own, otherwise its listed coin price."""
	if _browser_entries.is_empty():
		return 0
	var idx: int = clampi(_browser_index, 0, _browser_entries.size() - 1)
	var entry: Dictionary = _browser_entries[idx]
	if _cartridge_owned(entry):
		return 0  # already bought — play for free from now on
	return int(entry["cost"])


func _coin_balance() -> int:
	"""Spendable Grass-coin balance = coins earned minus coins spent."""
	return maxi(GameState.tetrivo_coins_earned - GameState.tetrivo_coins_spent, 0)


func _spend_coins(n: int) -> void:
	GameState.tetrivo_coins_spent += n
	_save_tetrivo_state()


func _is_softlocked() -> bool:
	"""Coins are farmable (every win earns one, no lifetime cap), so a player can
	always earn more by playing — there is no soft-lock. Kept as a method for
	compatibility with the anti-softlock gift call site."""
	return false


func _auto_gift_if_softlocked() -> void:
	"""Anti-softlock: if the player is stuck with 0 Grass coins (harvested then
	wasted them and can't earn more), gift them 2 Grass coins + 1,000 gold once
	as an apology so they're never permanently locked out. Persisted per profile."""
	if AuthManager.current_username.is_empty():
		return
	if GameState.tetrivo_gift_given:
		return
	if not _is_softlocked():
		return
	GameState.tetrivo_gift_given = true
	GameState.tetrivo_coins_earned += 2
	GameState.add_money(1000)
	_save_tetrivo_state()
	_show_browser_notice("SORRY! You were stuck at 0 coins — here's a gift:  +2 Grass coins,  +1,000 gold", Color(0.4, 1.0, 0.6))


func _show_cant_afford(cost: int) -> void:
	"""Briefly flash a 'not enough coins' note on the browser screen."""
	if _cant_afford_label != null and is_instance_valid(_cant_afford_label):
		_cant_afford_label.queue_free()
	var lbl := Label.new()
	lbl.text = "NOT ENOUGH COINS — need %d" % cost
	lbl.position = Vector2(0, ROOM_H - 190)
	lbl.size = Vector2(ROOM_W, 30)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3, 1))
	lbl.add_theme_font_size_override("font_size", 22)
	_ui.add_child(lbl)
	_cant_afford_label = lbl
	await get_tree().create_timer(1.4).timeout
	if is_instance_valid(lbl):
		lbl.queue_free()


func _on_esc_pressed() -> void:
	# Debounce: ignore ESC for a short window after the last accepted press so
	# MASHING it doesn't cascade through several states (cancel intro → close
	# menu → turn off console → leave room), which caused glitches and repeated
	# pitched-down cartridge-eject audio.
	var now := Time.get_ticks_msec() / 1000.0
	if now < _esc_lock_until:
		return
	if _intro_active:
		_cancel_tetrivo_intro()
		# Absorb the rest of a rapid ESC mash: cancelling the intro is the only
		# thing this burst should do, so lock out ESC for a longer window.
		_esc_lock_until = now + 1.2
		return
	_esc_lock_until = now + 0.5
	if _gift_inbox_active:
		# Leave the gift pending (don't decide) — it'll reappear later.
		_hide_gift_inbox()
		return
	if _gift_active:
		_cancel_gift()
		return
	if _purchase_confirm:
		_cancel_purchase()
		return
	if _pending_action.is_valid():
		# A beat-synced action is queued but hasn't fired yet (e.g. a launch that
		# would open the purchase screen). Back out cleanly instead of racing it,
		# so a quick ESC doesn't fall through to turning the console off.
		_pending_action = Callable()
		return
	if _game_active:
		_exit_tetrivo_game()
	elif _menu_active:
		_close_tetrivo()
	elif _browser_active:
		# ESC in the browser turns the console OFF (white vertical-shrink),
		# returning you to the idle room where you can boot it up again with E.
		_turn_off_console()
	elif _boot_active:
		# Skip boot and go straight to the browser.
		_show_minigame_browser()
	else:
		# Idle in the room: leave back to the lobby (black block left→right).
		_leave_arcade_room()


# ═══════════════ MACHINE INTERACTION ═══════════════

func _on_machine_body_entered(body: Node) -> void:
	if body == _player and not _boot_active and not _menu_active:
		_machine_prompt.visible = true


func _on_machine_body_exited(body: Node) -> void:
	if body == _player:
		_machine_prompt.visible = false


func _machine_prompt_text() -> String:
	return "Press [%s] to boot up The Magic Entertainer™" % _interact_key_label()


func _refresh_machine_prompt() -> void:
	if is_instance_valid(_machine_prompt):
		_machine_prompt.text = _machine_prompt_text()


## Display name for the "interact" action on the current input device, so the
## prompt follows the player's assigned binding instead of hard-coding E (which
## confuses people who remapped it).
func _interact_key_label() -> String:
	return InputSystem.prompt_for("interact", "E")


# ═══════════════ CONSOLE BOOT SEQUENCE ═══════════════

func _start_boot_sequence() -> void:
	if _boot_active or _menu_active:
		return
	_boot_active = true
	_machine_prompt.visible = false
	# The console is turning on: add the subtle CRT overlay and bring up static
	# noise, which will disappear the moment loading finishes.
	_create_crt_overlay()
	_set_crt_noise(0.5)
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
		_set_crt_noise(randf_range(0.4, 0.6))  # live static while turning on
		await get_tree().create_timer(randf_range(0.02, 0.06)).timeout
	flick.color = Color(0, 0, 0, 1)
	await get_tree().create_timer(0.1).timeout
	_set_crt_noise(0.42)  # static persists through the boot text + loading bar

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

	# 2b) The Magic Entertainer icon flickers up, then stays until loading ends.
	var icon := TextureRect.new()
	icon.texture = load(MAGIC_ICON)
	var isz := 340.0
	icon.size = Vector2(isz, isz)
	icon.position = Vector2((ROOM_W - isz) / 2.0, ROOM_H * 0.3 - isz / 2.0)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(icon)
	# CRT-style flicker-up: rapid, random opacity so it shimmers into view.
	var ft_end := Time.get_ticks_msec() + 550
	while Time.get_ticks_msec() < ft_end:
		icon.modulate = Color(1, 1, 1, randf_range(0.2, 1.0))
		await get_tree().create_timer(randf_range(0.02, 0.05)).timeout
	icon.modulate = Color(1, 1, 1, 1)  # locked on — stays through loading

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

	# Play the boot-up sound now, and drive the loading bar so it reaches 100%
	# at the exact moment the boot-up ends. Then hand straight into the
	# navigator music for a perfectly-synced boot-up → music transition.
	var boot_p := AudioStreamPlayer.new()
	boot_p.stream = load(CONSOLE_BOOTUP)
	boot_p.bus = "SFX"
	add_child(boot_p)
	boot_p.play()
	var boot_len: float = boot_p.stream.get_length()

	# Jump 10% → 78% → 100% over the boot-up's duration.
	var marks: Array[Vector2] = [
		Vector2(0.0, 0.10),
		Vector2(0.35, 0.78),
		Vector2(0.9, 1.0),
	]
	for m in marks:
		var tween := create_tween()
		tween.tween_property(bar_fill, "size:x", 400.0 * m.y, boot_len / marks.size())
		tween.parallel().tween_property(pct_lbl, "text", "%d%%" % int(m.y * 100.0), 0.01)
		await tween.finished
	bar_fill.size.x = 400.0
	pct_lbl.text = "100%"

	# Let the boot-up fully finish (right as the bar hits 100%), then free it.
	while boot_p.playing:
		await get_tree().process_frame
	boot_p.queue_free()

	bar_bg.queue_free()
	bar_fill.queue_free()
	pct_lbl.queue_free()

	# Loading is complete — fade the Magic Entertainer icon out, then lift the
	# black overlay and reveal the console navigator, which starts the 140 BPM
	# music exactly as the boot-up ends.
	var icon_fade := create_tween()
	icon_fade.tween_property(icon, "modulate:a", 0.0, 0.4)
	await icon_fade.finished
	icon.queue_free()

	flick.queue_free()

	_boot_active = false
	_show_minigame_browser()


# ═══════════════ MINIGAME BROWSER ═══════════════

func _show_minigame_browser() -> void:
	"""Cartridge browser. In the demo there is only one minigame: Tetrivo.
	WASD navigation just shows a friendly 'this is all we have' nag. Themed like
	an authentic old computer (light beige / dark CRT), with glossy screens."""
	if _browser_active:
		return
	_browser_active = true
	_purchase_confirm = false
	TouchControls.set_mode(TouchControls.BROWSER)
	# Loading is finished — the static disappears completely; only the subtle
	# pixelation + scanlines remain.
	_set_crt_noise(0.0)
	# Music is NOT played here — tetrino.wav only plays inside the Tetrivo game.

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

	# The cartridges live in a 2D grid laid out like a smart-watch app launcher.
	# TETRIVO (free) and TETRIVO 2 (2 coins) sit side by side; the TETRIVO 3
	# copy (3 coins) sits ABOVE them and is reached ONLY by pressing Up/Down —
	# never Left/Right. The focused cartridge is full size and every other one
	# shrinks the farther its grid-distance is from the focused one (a subtle
	# depth effect, so far-away cartridges look smaller).
	_browser_entries = [
		{"name": "TETRIVO", "thumb": TETRIVO_THUMB, "cost": 0, "paid": false},
		{"name": "DIRTYSWEEPER", "thumb": DIRTSWEEPER_THUMB, "cost": 2, "paid": true, "owned_key": "dirtysweeper_owns_paid"},
		{"name": "TETRIVO 3", "thumb": TETRIVO_THUMB, "cost": 3, "paid": true, "owned_key": "tetrivo_owns_paid3"},
	]
	# Grid coordinates: (0,0) = TETRIVO, (1,0) = DIRTYSWEEPER, (0,-1) = TETRIVO 3.
	_browser_grid = [Vector2(0, 0), Vector2(1, 0), Vector2(0, -1)]
	_browser_index = 0
	_browser_cartridges = []

	var card_w := 340.0
	var card_h := 180.0
	var cell_x := 380.0
	var cell_y := 160.0
	var grid_center := Vector2(ROOM_W / 2.0, 400.0)
	var row := Control.new()
	row.name = "BrowserRow"
	row.position = Vector2(0, 0)
	_ui.add_child(row)
	_browser_row = row

	# Gold highlight frame sits in the row, behind the selected cartridge.
	_browser_highlight = ColorRect.new()
	_browser_highlight.name = "BrowserHighlight"
	_browser_highlight.color = Color(1.0, 0.84, 0.3, 0.9)
	_browser_highlight.size = Vector2(card_w + 12, card_h + 12)
	_browser_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_browser_highlight)

	for i in range(_browser_entries.size()):
		var entry: Dictionary = _browser_entries[i]
		var cartridge := Control.new()
		cartridge.name = "Cartridge%d" % i
		cartridge.pivot_offset = Vector2(card_w, card_h) / 2.0
		var g: Vector2 = _browser_grid[i]
		var center: Vector2 = grid_center + Vector2(g.x * cell_x, g.y * cell_y)
		cartridge.position = center - Vector2(card_w, card_h) / 2.0
		cartridge.size = Vector2(card_w, card_h)
		row.add_child(cartridge)
		_browser_cartridges.append(cartridge)

		var card := ColorRect.new()
		card.color = p["panel"]
		card.position = Vector2.ZERO
		card.size = Vector2(card_w, card_h)
		cartridge.add_child(card)

		var thumb := TextureRect.new()
		thumb.texture = load(entry["thumb"])
		thumb.position = Vector2(45, 8)
		thumb.size = Vector2(250, 115)
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cartridge.add_child(thumb)

		# Glossy screen reflection on top of the thumbnail.
		var gloss := _make_glossy_screen(thumb.size)
		gloss.position = Vector2(45, 8)
		cartridge.add_child(gloss)

		var card_name := Label.new()
		card_name.text = entry["name"]
		card_name.position = Vector2(0, 126)
		card_name.size = Vector2(card_w, 28)
		card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_name.add_theme_color_override("font_color", p["accent"])
		card_name.add_theme_font_size_override("font_size", 26)
		cartridge.add_child(card_name)

		var is_paid: bool = bool(entry.get("paid", false))
		var owned: bool = _cartridge_owned(entry)
		var cost_text: String = "FREE"
		var cost_color: Color = p["accent"]
		if is_paid:
			cost_text = "OWNED" if owned else "%d COINS" % entry["cost"]
			cost_color = Color(0.5, 1.0, 0.5) if owned else Color(1.0, 0.8, 0.2, 1)
		var cost_lbl := Label.new()
		cost_lbl.text = cost_text
		cost_lbl.position = Vector2(0, 152)
		cost_lbl.size = Vector2(card_w, 22)
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_lbl.add_theme_color_override("font_color", cost_color)
		cost_lbl.add_theme_font_size_override("font_size", 18)
		cartridge.add_child(cost_lbl)

	# Snap to cartridge 0 (no pan) on first show.
	_center_browser(false)

	# Anti-softlock apology gift, granted BEFORE the coin badge is drawn so the
	# badge shows the new balance (see _auto_gift_if_softlocked).
	_auto_gift_if_softlocked()

	# Shiny Grassconatication coin + pixelated spendable balance (earned - spent).
	# expand/size set BEFORE the texture so it stays tiny (16x16). Kept in the
	# top-right corner so it never sits under a centered cartridge.
	var coin_badge := TextureRect.new()
	coin_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_badge.position = Vector2(ROOM_W - 220, 150)
	coin_badge.size = Vector2(44, 44)
	coin_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_badge.texture = load(COIN_TEX)
	_ui.add_child(coin_badge)
	_add_pixel_text(_ui, "x" + str(_coin_balance()),
		Vector2(ROOM_W - 172, 170), 2.0, p["accent"])

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
	hint.name = "BrowserHint"
	hint.text = ""
	hint.position = Vector2(0, ROOM_H - 80)
	hint.size = Vector2(ROOM_W, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", p["text_dim"])
	hint.add_theme_font_size_override("font_size", 18)
	_ui.add_child(hint)
	_refresh_browser_hint()

	# The console is now on: start the 140 BPM navigation music and sync actions
	# to its beats.
	_start_console_music()

	# If a friend gifted us a cartridge, offer it now (accept / deny).
	_show_first_pending_gift()


func _on_touch_swipe(dir: Vector2) -> void:
	"""Touch drag in the console browser: move the selection in the drag
	direction (beat-synced, same as WASD)."""
	if not _browser_active or _menu_active or _boot_active \
			or _purchase_confirm or _gift_active or _gift_inbox_active:
		return
	if dir == Vector2.ZERO:
		return
	_pending_action = _select_browser_slot.bind(dir.normalized())


func _on_touch_tap() -> void:
	"""Quick tap in the console browser: launch the highlighted cartridge."""
	if not _browser_active or _menu_active or _boot_active \
			or _purchase_confirm or _gift_active or _gift_inbox_active:
		return
	_on_enter_pressed()


func _on_browser_navigate() -> void:
	"""WASD in the browser moves the selection between the cartridges
	(left/right, with up/down as a fallback)."""
	if not _browser_active or _menu_active or _boot_active:
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	dir = dir.normalized()
	if dir == Vector2.ZERO:
		return
	# Queue the selection change to fire on the next beat (rhythm-synced).
	_pending_action = _select_browser_slot.bind(dir)


## Refresh the one-line control hint at the bottom of the browser. It adds a
## "[G] GIFT to a friend" hint whenever a PAID cartridge (owned or not) is
## selected, so an owner knows they can still gift it.
func _refresh_browser_hint() -> void:
	if not _browser_active or not is_instance_valid(_ui):
		return
	var hint: Label = _ui.get_node_or_null("BrowserHint")
	if hint == null:
		return
	var text: String = "WASD  navigate   •   T  display   •   ENTER  play   •   ESC  leave"
	if _selected_is_paid():
		text += "   •   G  GIFT to a friend"
	hint.text = text


func _select_browser_slot(dir: Vector2) -> void:
	"""Move the selection to the nearest cartridge in the given direction and
	re-scale the grid so the newly selected one pops to full size while the
	others shrink by grid-distance. Only moves to a real cartridge: if nothing
	exists that way it does NOT wrap — it plays the navigation-error sound and
	shakes the grid instead of going somewhere that doesn't exist."""
	if _browser_cartridges.is_empty():
		return
	var new_idx: int = _neighbor_in_direction(_browser_index, dir)
	if new_idx < 0 or new_idx == _browser_index:
		# No cartridge exists that way — nav error: error sound + shake/rebound.
		_play_console_sfx(CONSOLE_ERROR, 0.8, 1.25)
		_shake_browser_row(dir)
		return
	_browser_index = new_idx
	_play_console_sfx(CONSOLE_CONFIRM, 1.0, 1.0)
	_center_browser(true)
	_refresh_browser_hint()


func _neighbor_in_direction(idx: int, dir: Vector2) -> int:
	"""Smart-watch-app style: among the other cartridges, return the one most in
	the pressed direction, or -1 if none exists that way. Up/Down grabs whatever
	is generally above/below (so the TETRIVO 3 copy is reached by Up from either
	bottom cartridge), while Left/Right requires a clean horizontal neighbor so
	the copy is never reached by pressing Left or Right."""
	if _browser_grid.is_empty():
		return -1
	var from: Vector2 = _browser_grid[idx]
	var best := -1
	var best_score := -INF
	for j in _browser_entries.size():
		if j == idx:
			continue
		var offset: Vector2 = _browser_grid[j] - from
		var proj: float = offset.dot(dir)
		if proj <= 0.001:
			continue
		var perp: float = absf(offset.x * dir.y - offset.y * dir.x)
		if absf(dir.x) > absf(dir.y):
			# Horizontal press: the neighbor must be mostly horizontal.
			if proj <= perp:
				continue
		var score: float = proj - perp * 0.4
		if score > best_score:
			best_score = score
			best = j
	return best


func _browser_grid_dist(a: int, b: int) -> float:
	"""Euclidean grid distance between two cartridges (drives the shrink scale)."""
	if _browser_grid.is_empty():
		return 0.0
	return _browser_grid[a].distance_to(_browser_grid[b])


func _shake_browser_row(dir: Vector2) -> void:
	"""Shake the whole grid opposite the pressed direction, then rebound it back
	to center — the navigation-error shake when nothing exists that way."""
	if _browser_row == null or not is_instance_valid(_browser_row):
		return
	var base: Vector2 = _browser_row.position
	var nudge: Vector2 = -dir * 16.0
	if dir == Vector2.ZERO:
		nudge = Vector2(16, 0)
	var tw := create_tween()
	tw.tween_property(_browser_row, "position", base + nudge, 0.12)
	for i in 4:
		var amp: float = 6.0 * (1.0 - float(i) / 5.0)
		var sgn := 1.0 if i % 2 == 0 else -1.0
		tw.tween_property(_browser_row, "position", base + nudge + sgn * amp * dir.abs(), 0.05)
	tw.tween_property(_browser_row, "position", base, 0.16)


func _center_browser(animate: bool) -> void:
	"""The camera (the row) pans in 2D so the cartridge the player is about to
	choose is centered on screen, while every other cartridge is scaled down by
	its grid-distance from the focused one (so the farther you navigate away, the
	smaller it looks). When animate is true the pan + resize tween smoothly."""
	if _browser_row == null or _browser_cartridges.is_empty():
		return
	var idx: int = clampi(_browser_index, 0, _browser_cartridges.size() - 1)
	var cart: Control = _browser_cartridges[idx]
	# Center the focused cartridge on screen (its pivot is at its center, so its
	# visual center stays at position + size/2 regardless of scale).
	var target: Vector2 = Vector2(ROOM_W / 2.0, 400.0) - (cart.position + cart.size / 2.0)
	if animate and is_instance_valid(_browser_row):
		var tw := create_tween()
		tw.tween_property(_browser_row, "position", target, 0.2) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_browser_row.position = target
	for i in _browser_cartridges.size():
		var c: Control = _browser_cartridges[i]
		if not is_instance_valid(c):
			continue
		var dist: float = _browser_grid_dist(_browser_index, i)
		var target_scale: float = 1.0 / (1.0 + 0.6 * dist)
		if animate and is_instance_valid(c):
			var tw2 := create_tween()
			tw2.tween_property(c, "scale", Vector2(target_scale, target_scale), 0.16) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			c.scale = Vector2(target_scale, target_scale)
	_place_browser_highlight()


func _place_browser_highlight() -> void:
	"""Position the gold selection frame over the currently selected cartridge
	inside the panning row."""
	if not is_instance_valid(_browser_highlight) or _browser_cartridges.is_empty():
		return
	var idx: int = clampi(_browser_index, 0, _browser_cartridges.size() - 1)
	var cart: Control = _browser_cartridges[idx]
	_browser_highlight.position = cart.position - Vector2(6, 6)


func _launch_tetrivo() -> void:
	if not _browser_active or _menu_active or _boot_active:
		return
	# Dirtysweeper now plays EMBEDDED inside this arcade scene (no separate
	# scene) — exactly like Tetrivo.
	if _selected_cartridge_name() == "DIRTYSWEEPER":
		_start_dirtysweeper()
		return
	_clear_browser()
	_show_tetrivo_menu()


func _clear_browser() -> void:
	_browser_active = false
	TouchControls.set_mode(TouchControls.OVERWORLD)
	for child: Node in _ui.get_children():
		child.queue_free()
	_browser_cartridge = null
	_browser_cartridges = []
	_browser_entries = []
	_browser_grid = []
	_browser_row = null
	_browser_highlight = null
	_cart_shaking = false
	_purchase_confirm = false
	# A minigame was chosen: keep the console music playing in the background
	# but muted (it resumes audible when we come back to the browser).
	_mute_console_music()


func _rebuild_browser() -> void:
	# Preserve which cartridge is selected so toggling the display (T) doesn't
	# send the player back to the first minigame — they keep their spot.
	var keep: int = _browser_index
	_clear_browser()
	_show_minigame_browser()
	_browser_index = keep
	_center_browser(false)


# ═══════════════ TETRIVO TITLE / MENU ═══════════════

func _show_tetrivo_menu() -> void:
	if _menu_active:
		return
	_menu_active = true
	_game_active = false
	TouchControls.set_mode(TouchControls.TETRIS)
	# Music is NOT started here — it only plays once the player actually
	# enters the minigame (see _start_tetrivo_game).

	var p := _palette()

	# Backdrop behind the menu (themed).
	var bg := ColorRect.new()
	bg.name = "TetrivoBG"
	bg.color = p["bg"]
	bg.position = Vector2(0, 0)
	bg.size = Vector2(ROOM_W, ROOM_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bg)

	# CRT bezel frame.
	var bezel := ColorRect.new()
	bezel.name = "TetrivoBezel"
	bezel.color = Color(0.12, 0.12, 0.14, 1)
	bezel.position = Vector2(60, 40)
	bezel.size = Vector2(ROOM_W - 120, ROOM_H - 110)
	_ui.add_child(bezel)

	# Thumbnail as the title art (glossy screen).
	var thumb := TextureRect.new()
	thumb.texture = load(TETRIVO_THUMB)
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
	title.text = "TETRIVO"
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


func _rebuild_tetrivo() -> void:
	_menu_active = false
	for child: Node in _ui.get_children():
		child.queue_free()
	_show_tetrivo_menu()


func _play_music() -> void:
	"""Start tetrino.wav looping seamlessly (full track, no fade-in). If the
	audio is imported as uncompressed 16-bit PCM we loop at the stream level so
	there's no gap; if it's a compressed import (QOA/ADPCM) we fall back to
	restarting on the `finished` signal so the track always plays fully and
	repeats."""
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.stream = load(TETRIVO_MUSIC)
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


# ── Console background music + beat-sync clock ──

func _start_console_music() -> void:
	"""Start the console navigation music (140 BPM) that plays while the
	console navigator is on. Loops seamlessly like tetrino.wav. Resets the
	beat clock so the next beat boundary is detected fresh."""
	if _console_music == null:
		_console_music = AudioStreamPlayer.new()
		# Load the 140 BPM navigation chiptune through the resource system
		# (pck-safe, works on Android/iOS) — the same way the boot sound and
		# tetrino.wav load. The imported WAV keeps its raw PCM so the seamless
		# stream-level loop below still works.
		_console_music.stream = load(CONSOLE_MUSIC)
		_console_music.bus = "Music"
		add_child(_console_music)
		var wav: AudioStreamWAV = _console_music.stream as AudioStreamWAV
		if wav:
			if wav.format == AudioStreamWAV.FORMAT_16_BITS:
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				var bpf: int = 2 * (2 if wav.stereo else 1)
				if bpf > 0:
					wav.loop_end = int(wav.data.size() / bpf)
			else:
				wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
				_console_music.finished.connect(_on_console_music_finished)
	if not _console_music.playing:
		_console_music.volume_db = -6.0
		_console_music.play()
	# Always bring the volume back up (in case it was muted while a minigame
	# was chosen) and align the beat clock to where the music is right now.
	_console_music.volume_db = -6.0
	_last_beat_index = _beat_index()


func _mute_console_music() -> void:
	"""Keep the console music playing in the background but muted, so the chosen
	minigame's own audio is what you hear. Beat clock + queued actions pause."""
	if is_instance_valid(_console_music):
		_console_music.volume_db = -80.0
	_last_beat_index = -1
	_pending_action = Callable()


func _on_console_music_finished() -> void:
	"""Restart the looped console track (only used if the import is compressed)."""
	if is_instance_valid(_console_music):
		_console_music.play()


func _stop_console_music() -> void:
	"""Stop the console background music and clear any queued beat action."""
	if is_instance_valid(_console_music):
		_console_music.stop()
	_last_beat_index = -1
	_pending_action = Callable()


func _beat_index() -> int:
	"""Which 140 BPM beat the console music playhead is currently on, or -1."""
	if is_instance_valid(_console_music) and _console_music.playing:
		return int(_console_music.get_playback_position() / BEAT_SECONDS)
	return -1


func _update_beat_clock() -> void:
	"""Detect a beat boundary in the console music and fire the queued action."""
	if not is_instance_valid(_console_music) or not _console_music.playing:
		return
	var bi := _beat_index()
	if bi >= 0 and bi != _last_beat_index:
		_last_beat_index = bi
		_on_beat()


func _on_beat() -> void:
	"""A beat was detected — execute the action the player queued."""
	_last_beat_time_msec = Time.get_ticks_msec()
	if _pending_action.is_valid():
		var a: Callable = _pending_action
		_pending_action = Callable()
		a.call()


# ── One-shot console SFX ──

func _beat_align_delay() -> float:
	"""Seconds until the next beat of the 140 BPM console music, so a sound can
	be started exactly in rhythm. Returns 0.0 if the music isn't playing (in
	which case the caller should just play immediately)."""
	if not is_instance_valid(_console_music) or not _console_music.playing:
		return 0.0
	var pos: float = _console_music.get_playback_position()
	var next_beat: float = (floori(pos / BEAT_SECONDS) + 1) * BEAT_SECONDS
	return maxf(next_beat - pos, 0.0)


func _play_console_sfx(path: String, min_pitch: float, max_pitch: float) -> void:
	"""Play a short one-shot sound on the SFX bus, aligned to the console
	music's 140 BPM beat so every console blip lands in rhythm. If the music
	isn't playing, or the call happens right on a beat (an action fired from
	_on_beat), it plays immediately; otherwise it waits for the next beat."""
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.bus = "SFX"
	p.pitch_scale = randf_range(min_pitch, max_pitch)
	add_child(p)
	var wait: float = _beat_align_delay()
	var on_beat_now: bool = Time.get_ticks_msec() - _last_beat_time_msec <= 80
	if wait > 0.03 and not on_beat_now:
		get_tree().create_timer(wait).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.play()
		)
	else:
		p.play()
	p.finished.connect(p.queue_free)


# ── Console CRT / old-prototype overlay ──

func _create_crt_overlay() -> void:
	"""Add a full-screen post-process overlay (pixelation, faint scanlines,
	gentle curvature) on a canvas layer above the console UI. The static noise
	uniform starts off and is only raised while the console is loading."""
	if _crt_layer != null:
		return
	_crt_layer = CanvasLayer.new()
	_crt_layer.name = "ConsoleCRT"
	_crt_layer.layer = 51  # above _ui (layer 50)
	add_child(_crt_layer)
	_crt_rect = ColorRect.new()
	_crt_rect.name = "CRTOverlay"
	_crt_rect.position = Vector2(0, 0)
	_crt_rect.size = Vector2(ROOM_W, ROOM_H)
	_crt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crt_mat = ShaderMaterial.new()
	_crt_mat.shader = load(CONSOLE_CRT_SHADER)
	_crt_rect.material = _crt_mat
	_crt_layer.add_child(_crt_rect)
	_set_crt_noise(0.0)


func _remove_crt_overlay() -> void:
	"""Remove the CRT overlay (console powered off)."""
	if is_instance_valid(_crt_layer):
		_crt_layer.queue_free()
	_crt_layer = null
	_crt_rect = null
	_crt_mat = null


func _set_crt_noise(v: float) -> void:
	"""Raise/lower the static noise shown on the CRT overlay. Only > 0 while the
	console is loading; it must drop back to 0 the moment loading finishes."""
	if _crt_mat != null:
		_crt_mat.set_shader_parameter("noise_amount", clampf(v, 0.0, 1.0))


func _start_tetrivo_intro() -> void:
	"""Play the cartridge-start sound and zoom into the title art, then begin
	the actual Tetris minigame."""
	if _intro_active or _game_active:
		return
	_intro_active = true

	# Play the cartridge-start jingle on the SFX bus, aligned to the console
	# music's 140 BPM beat so the transition lands on rhythm.
	_cart = AudioStreamPlayer.new()
	_cart.stream = load(CARTRIDGE_START)
	_cart.bus = "SFX"
	add_child(_cart)
	_cart.finished.connect(_on_cart_finished)
	var cart_wait: float = _beat_align_delay()
	if cart_wait > 0.03:
		get_tree().create_timer(cart_wait).timeout.connect(func() -> void:
			if is_instance_valid(_cart):
				_cart.play()
		)
	else:
		_cart.play()

	# Zoom into the title art to "enter" the game.
	if is_instance_valid(_title_thumb):
		_intro_zoom_tween = create_tween()
		_intro_zoom_tween.tween_property(_title_thumb, "scale", Vector2(3.2, 3.2), 1.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# The game music waits for the cartridge jingle to finish fully before
	# starting (see _on_cart_finished), so the two never overlap.


func _cancel_tetrivo_intro() -> void:
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
	game (which starts the tetrivo music). Guards so a back-out during the
	intro cancels it."""
	if not _intro_active:
		return
	_intro_active = false
	_start_tetrivo_game()


func _start_tetrivo_game() -> void:
	"""Player pressed ENTER on the title screen — the actual Tetris minigame
	now begins, which is when the music starts. Also used to retry after a
	game over or a win."""
	# Allowed either from the title menu (fresh start) or as a retry from the
	# game-over / win screen (a running game that has already ended). Without
	# this, pressing Enter on the game-over/win screen did nothing because the
	# title menu isn't active during a run.
	var retrying: bool = _game_active and (_game_over or _won)
	if not _menu_active and not retrying:
		return
	if _game_active and not _game_over and not _won:
		return
	_game_active = true
	TouchControls.set_mode(TouchControls.TETRIS)
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
	_soft_drop = false
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
	playing.text = "TETRIVO — PLAYING"
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
		# Speed up as the level rises (real-Tetris-style gravity acceleration).
		_level = 1 + int(_score / 500.0)
		_drop_interval = max(0.05, 1.0 - (0.09 * (_level - 1)))
		_update_score()

	_clearing = false
	_after_lock()


func _after_lock() -> void:
	"""Common tail of _lock_piece: check the win condition, else spawn the next."""
	# Win condition is now purely line-clear based (10 lineups). Reaching a high
	# score no longer earns a coin — the objective is clearing 10 lines.
	if _lines_cleared >= WIN_LINES:
		_show_win()
		return
	_render_board()
	_spawn_piece()


func _animate_line_clear(full_rows: Array) -> void:
	"""Pause the game to show the cleared rows, then let _lock_piece collapse
	them and award the score. A single line does a quick flash; a double, triple
	or more freezes the minigame for a full second (via the _clearing flag) with
	a brief white flash so the big clear lands with impact before play resumes."""
	var n := full_rows.size()
	# Flash the completed rows pure white (classic Tetris line clear).
	for t in _board_texs:
		if not is_instance_valid(t):
			continue
		var row: int = int(round(t.position.y / CELL))
		if full_rows.has(row):
			t.self_modulate = Color(1, 1, 1, 1)

	# Single line: quick flash and back to business.
	if n <= 1:
		await get_tree().create_timer(0.28).timeout
		return

	# Double / triple / more: stop the minigame for a second to clear all these
	# lines. A brief full-screen white flash sells the impact, then we carry on.
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.55)
	flash.position = Vector2(0, 0)
	flash.size = Vector2(ROOM_W, ROOM_H)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(flash)
	var ft := create_tween()
	ft.tween_property(flash, "modulate:a", 0.0, 0.3)
	ft.tween_callback(flash.queue_free)
	await get_tree().create_timer(1.0).timeout


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
	"""Pulse the board once per beat (140 BPM) to the tetrivo track."""
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
	# Real-Tetris gravity: base pace is _drop_interval (level-based); while
	# holding Down the piece falls at the fixed fast soft-drop rate instead.
	var interval := _drop_interval
	if _soft_drop:
		interval = minf(interval, SOFT_DROP_INTERVAL)
	_drop_accum += delta
	if _drop_accum >= interval:
		_drop_accum = 0.0
		if not _collides(_cur_type, _cur_rot, _cur_row + 1, _cur_col):
			_cur_row += 1
			_render_board()
		else:
			_lock_piece()


func _tetris_handle_input() -> void:
	if _game_lost or _game_over or _won or _clearing:
		return
	var left := InputSystem.is_pressed("tetris_left")
	var right := InputSystem.is_pressed("tetris_right")
	var up := InputSystem.is_pressed("tetris_rotate")
	var down := InputSystem.is_pressed("tetris_down")
	var space := InputSystem.is_pressed("tetris_harddrop")

	if left and not _left_was_down:
		_try_move(0, -1)
	if right and not _right_was_down:
		_try_move(0, 1)
	if up and not _up_was_down:
		_try_rotate()
	# Holding Down is a real soft drop: the piece falls at the fast soft-drop
	# rate (see _tetris_step), just like classic Tetris.
	_soft_drop = down
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
		title = "GAMBLE LOST\n(kept " + str(GameState.tetrivo_coins_earned) + " coin)"
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
	if GameState.tetrivo_last_seen_time > 0 and now < GameState.tetrivo_last_seen_time:
		GameState.tetrivo_time_penalty_until = max(GameState.tetrivo_time_penalty_until, now + TAMPER_PENALTY_SECONDS)
	if GameState.tetrivo_last_coin_time > 0 and now < GameState.tetrivo_last_coin_time:
		GameState.tetrivo_time_penalty_until = max(GameState.tetrivo_time_penalty_until, now + TAMPER_PENALTY_SECONDS)
	GameState.tetrivo_last_seen_time = max(GameState.tetrivo_last_seen_time, now)


func _daily_available(now: int) -> bool:
	"""Is the daily hard-mode gamble available right now? Admins are unlimited;
	everyone else gets one gamble opportunity per calendar day. (Normal win
	farming is NOT gated by this — it's always available.)"""
	if GameState.is_admin:
		return true
	if GameState.tetrivo_time_penalty_until > 0 and now < GameState.tetrivo_time_penalty_until:
		return false
	if GameState.tetrivo_last_coin_time <= 0:
		return true
	return not _same_day(GameState.tetrivo_last_coin_time, now)


func _save_tetrivo_state() -> void:
	var uname: String = AuthManager.current_username
	if uname.is_empty():
		return
	SAVE_MGR_SCRIPT.autosave(uname)


func _resolve_win_reward() -> int:
	"""Farmable coin rules. Every win (objective met) earns 1 Grass coin — no
	lifetime cap and no daily gate, so coins are genuinely farmable. The daily
	hard-mode gamble is a bonus that pays a 2nd coin for that run. Returns coins
	awarded this run (1 or 2). Updates GameState and persists."""
	var now := _now_sec()
	_detect_time_tamper(now)
	# Each new day resets the daily gamble so it's available once per day.
	if _daily_available(now):
		GameState.tetrivo_gambled = false
	var awarded := 0
	if _hard_mode and not GameState.tetrivo_gambled:
		# Gamble: hard-mode win pays the base coin + a bonus = 2 coins this run.
		awarded = 2
		GameState.tetrivo_coins_earned += 2
		GameState.tetrivo_gambled = true
		GameState.tetrivo_last_coin_time = now
	else:
		# Normal farm: every win is 1 coin, repeatable, no cap.
		awarded = 1
		GameState.tetrivo_coins_earned += 1
		GameState.tetrivo_last_coin_time = now
	if awarded > 0:
		GameState.add_money(awarded)
		_save_tetrivo_state()
	return awarded


func _on_gamble_lost() -> void:
	"""Lost the hard-mode gamble: you keep the coins you farmed, but lose the
	day's bonus-coin opportunity (the gamble is used up for today)."""
	GameState.tetrivo_gambled = true
	_save_tetrivo_state()


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

	# Play the win fanfare (replace the tetrivo music).
	if _music:
		_music.stop()
	var complete := AudioStreamPlayer.new()
	complete.stream = load(TETRIVO_COMPLETE)
	complete.bus = "Music"
	add_child(complete)
	complete.play()

	var awarded := _resolve_win_reward()
	var can_gamble: bool = _daily_available(_now_sec()) and not GameState.tetrivo_gambled
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
	sub.text = "YOU WIN — TETRIVO COMPLETE"
	sub.position = Vector2(0, 168)
	sub.size = Vector2(ROOM_W, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", p["text"])
	sub.add_theme_font_size_override("font_size", 24)
	_ui.add_child(sub)

	# The shiny reward coin, centred — 40x40 px. Set expand/size BEFORE the
	# texture so the node doesn't auto-grow to the texture's native size.
	_win_coin = TextureRect.new()
	_win_coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_win_coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_win_coin.position = Vector2(ROOM_W / 2.0 - 30, 264)
	_win_coin.size = Vector2(60, 60)
	_win_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_coin.texture = load(COIN_TEX)
	_ui.add_child(_win_coin)
	_make_coin_shiny()

	# Pixelated "+N" next to the coin.
	if awarded > 0:
		_add_pixel_text(_ui, "+" + str(awarded), Vector2(ROOM_W / 2.0 + 36, 290), 2.5, Color(1.0, 0.85, 0.2))
	else:
		_add_pixel_text(_ui, "+0", Vector2(ROOM_W / 2.0 + 36, 290), 2.5, p["text_dim"])

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
		lines.append("Press [G] to GAMBLE — HARD MODE (2 coins on win)")
	prompt.text = "\n".join(lines)
	prompt.position = Vector2(0, 440)
	prompt.size = Vector2(ROOM_W, 90)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", p["accent"])
	prompt.add_theme_font_size_override("font_size", 22)
	_ui.add_child(prompt)


func _handle_win_input() -> void:
	"""On the win screen: G starts the hard-mode gamble run (when available)."""
	var g := InputSystem.is_pressed("gamble")
	if g and not _g_was_down:
		if _daily_available(_now_sec()) and not GameState.tetrivo_gambled:
			_hard_mode = true
			_start_tetrivo_game()
	_g_was_down = g


func _exit_tetrivo_game() -> void:
	"""ESC from inside the game goes back to the Tetrivo title screen and stops
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
	_show_tetrivo_menu()


func _close_tetrivo() -> void:
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


# ═══════════════ DIRTYSWEEPER (EMBEDDED) ═══════════════

func _start_dirtysweeper() -> void:
	if not _browser_active or _menu_active or _boot_active:
		return
	_clear_browser()
	_dirty_active = true
	_dirty_hard = GameState.dirtysweeper_hard
	TouchControls.set_mode(TouchControls.MINESWEEPER)
	_build_dirtysweeper()


func _close_dirtysweeper() -> void:
	if not _dirty_active:
		return
	GameState.dirtysweeper_hard = _dirty_hard
	_dirty_active = false
	_dirty_win_awarded = false
	for child: Node in _ui.get_children():
		child.queue_free()
	_dirty_root = null
	TouchControls.set_mode(TouchControls.OVERWORLD)
	_show_minigame_browser()


## ── Board generation ───────────────────────────────────────────────

func _dirty_new_board(exclude: Vector2i) -> void:
	var mines: int = DS_MINES_HARD if _dirty_hard else DS_MINES
	_dirty_board = []
	for r in range(DS_GRID):
		var row: Array = []
		for c in range(DS_GRID):
			row.append({"mine": false, "revealed": false, "flagged": false, "count": 0})
		_dirty_board.append(row)
	var placed := 0
	while placed < mines:
		var r: int = randi() % DS_GRID
		var c: int = randi() % DS_GRID
		if Vector2i(r, c) == exclude:
			continue
		if absi(r - exclude.x) <= 1 and absi(c - exclude.y) <= 1:
			continue
		if _dirty_board[r][c]["mine"]:
			continue
		_dirty_board[r][c]["mine"] = true
		placed += 1
	_dirty_compute_counts()
	_dirty_game_over = false
	_dirty_won = false
	_dirty_flag_mode = false
	_dirty_press_armed = false
	_dirty_cursor = exclude
	_dirty_win_awarded = false


func _dirty_compute_counts() -> void:
	for r in range(DS_GRID):
		for c in range(DS_GRID):
			var n := 0
			for dr in [-1, 0, 1]:
				for dc in [-1, 0, 1]:
					if dr == 0 and dc == 0:
						continue
					var rr: int = r + dr
					var cc: int = c + dc
					if rr >= 0 and rr < DS_GRID and cc >= 0 and cc < DS_GRID and _dirty_board[rr][cc]["mine"]:
						n += 1
			_dirty_board[r][c]["count"] = n


func _dirty_mines_flagged() -> int:
	var n := 0
	for r in range(DS_GRID):
		for c in range(DS_GRID):
			if _dirty_board[r][c]["flagged"]:
				n += 1
	return n


func _dirty_unrevealed_safe() -> int:
	var n := 0
	for r in range(DS_GRID):
		for c in range(DS_GRID):
			if not _dirty_board[r][c]["mine"] and not _dirty_board[r][c]["revealed"]:
				n += 1
	return n


## ── UI build ───────────────────────────────────────────────────────

func _build_dirtysweeper() -> void:
	var p := _ds_palette()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	_dirty_root = root

	var bg := ColorRect.new()
	bg.color = p["bg"]
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var title := Label.new()
	title.text = "DIRTYSWEEPER"
	title.position = Vector2(0, 24)
	title.size = Vector2(ROOM_W, 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", p["accent"])
	title.add_theme_font_size_override("font_size", 52)
	root.add_child(title)

	_dirty_face_tex = TextureRect.new()
	_dirty_face_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dirty_face_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dirty_face_tex.size = Vector2(64, 64)
	_dirty_face_tex.position = Vector2(ROOM_W / 2.0 - 32, 92)
	_dirty_face_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dirty_face_tex)
	_dirty_face_btn = Button.new()
	_dirty_face_btn.position = Vector2(ROOM_W / 2.0 - 40, 88)
	_dirty_face_btn.size = Vector2(80, 72)
	_dirty_face_btn.flat = true
	_dirty_face_btn.pressed.connect(_dirty_restart)
	root.add_child(_dirty_face_btn)
	_dirty_refresh_face()

	_dirty_status = Label.new()
	_dirty_status.position = Vector2(0, 158)
	_dirty_status.size = Vector2(ROOM_W, 30)
	_dirty_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dirty_status.add_theme_color_override("font_color", p["text"])
	_dirty_status.add_theme_font_size_override("font_size", 20)
	root.add_child(_dirty_status)
	_dirty_counts = Label.new()
	_dirty_counts.position = Vector2(0, 184)
	_dirty_counts.size = Vector2(ROOM_W, 26)
	_dirty_counts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dirty_counts.add_theme_color_override("font_color", Color(1, 0.8, 0.3, 1))
	_dirty_counts.add_theme_font_size_override("font_size", 20)
	root.add_child(_dirty_counts)

	var grid_w: float = DS_GRID * DS_CELL
	var ox: float = (ROOM_W - grid_w) / 2.0
	var oy: float = 230.0
	for r in range(DS_GRID):
		var row_arr: Array = []
		for c in range(DS_GRID):
			var b := Button.new()
			b.position = Vector2(ox + c * DS_CELL, oy + r * DS_CELL)
			b.size = Vector2(DS_CELL, DS_CELL)
			b.custom_minimum_size = Vector2(DS_CELL, DS_CELL)
			b.add_theme_font_size_override("font_size", 22)
			b.add_theme_stylebox_override("normal", _dirty_cell_style(Color(0.45,0.45,0.5), 2))
			b.add_theme_stylebox_override("hover", _dirty_cell_style(Color(0.55,0.55,0.62), 2))
			b.add_theme_stylebox_override("pressed", _dirty_cell_style(Color(0.3,0.3,0.34), 2))
			b.add_theme_stylebox_override("focus", _dirty_cell_style(Color(1,1,1,0), 2))
			b.focus_mode = Control.FOCUS_NONE
			var cell := Vector2i(r, c)
			b.button_down.connect(_dirty_on_cell_down.bind(cell))
			b.button_up.connect(_dirty_on_cell_up.bind(cell))
			b.mouse_exited.connect(_dirty_on_cell_exited.bind(cell))
			root.add_child(b)
			row_arr.append(b)
		_dirty_buttons.append(row_arr)

	_dirty_cursor_rect = ColorRect.new()
	_dirty_cursor_rect.color = Color(1, 1, 1, 0.28)
	_dirty_cursor_rect.size = Vector2(DS_CELL, DS_CELL)
	_dirty_cursor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dirty_cursor_rect)

	var hint := Label.new()
	hint.text = "ENTER reveal   •   F flag   •   arrows/WASD move   •   ESC quit   •   face restarts"
	hint.position = Vector2(0, oy + grid_w + 14)
	hint.size = Vector2(ROOM_W, 26)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", p["text_dim"])
	hint.add_theme_font_size_override("font_size", 18)
	root.add_child(hint)

	_dirty_new_board(Vector2i(DS_GRID / 2, DS_GRID / 2))
	_dirty_update_all()
	_dirty_update_cursor_rect()


func _dirty_cell_style(color: Color, border: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_border_width_all(border)
	sb.border_color = Color(0.2, 0.2, 0.22, 1)
	return sb


func _ds_palette() -> Dictionary:
	return {
		"bg": Color(0.05, 0.05, 0.08, 1),
		"accent": Color(0.5, 1.0, 0.5, 1),
		"text": Color(0.85, 0.85, 0.85, 1),
		"text_dim": Color(0.5, 0.5, 0.5, 1),
	}


func _dirty_face_path() -> String:
	if _dirty_game_over and not _dirty_won:
		return DS_FACE_DEAD_G if _dirty_hard else DS_FACE_DEAD
	if _dirty_won:
		return DS_FACE_NEUTRAL_G if _dirty_hard else DS_FACE_NEUTRAL
	if _dirty_press_armed and not _dirty_flag_mode and _dirty_press_is_on_mine():
		return DS_FACE_WARNING_G if _dirty_hard else DS_FACE_WARNING
	return DS_FACE_NEUTRAL_G if _dirty_hard else DS_FACE_NEUTRAL


func _dirty_refresh_face() -> void:
	_dirty_face_tex.texture = load(_dirty_face_path())


func _dirty_press_is_on_mine() -> bool:
	if _dirty_press_cell.x < 0 or _dirty_press_cell.y < 0:
		return false
	return bool(_dirty_board[_dirty_press_cell.x][_dirty_press_cell.y]["mine"])


## ── Rendering ──────────────────────────────────────────────────────

func _dirty_update_all() -> void:
	for r in range(DS_GRID):
		for c in range(DS_GRID):
			_dirty_update_cell(r, c)
	_dirty_counts.text = "MINES LEFT: %d" % maxi(DS_MINES_HARD if _dirty_hard else DS_MINES - _dirty_mines_flagged(), 0)
	if _dirty_won:
		_dirty_status.text = "YOU WIN! +%d Grass coin" % (2 if _dirty_hard else 1)
	elif _dirty_game_over:
		_dirty_status.text = "BOOM! GAME OVER"
	else:
		_dirty_status.text = ("FLAG MODE" if _dirty_flag_mode else "SAFE") + ("  [HARD]" if _dirty_hard else "  [NORMAL]")


func _dirty_update_cell(r: int, c: int) -> void:
	var b: Button = _dirty_buttons[r][c]
	var cell: Dictionary = _dirty_board[r][c]
	if cell["revealed"]:
		if cell["mine"]:
			b.text = "💣"
			b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			b.add_theme_stylebox_override("normal", _dirty_cell_style(Color(0.6, 0.2, 0.2), 2))
		else:
			var n: int = cell["count"]
			b.text = "" if n == 0 else str(n)
			b.add_theme_color_override("font_color", DS_NUM_COLORS[n] if n > 0 else Color(0.8, 0.8, 0.8, 1))
			b.add_theme_stylebox_override("normal", _dirty_cell_style(Color(0.72, 0.72, 0.78), 2))
	else:
		if cell["flagged"]:
			b.text = "⚑"
			b.add_theme_color_override("font_color", Color(1, 0.5, 0.2, 1))
		else:
			b.text = ""
		b.add_theme_stylebox_override("normal", _dirty_cell_style(Color(0.45, 0.45, 0.5), 2))


func _dirty_update_cursor_rect() -> void:
	if _dirty_game_over:
		_dirty_cursor_rect.visible = false
		return
	_dirty_cursor_rect.visible = true
	var grid_w: float = DS_GRID * DS_CELL
	var ox: float = (ROOM_W - grid_w) / 2.0
	_dirty_cursor_rect.position = Vector2(ox + _dirty_cursor.y * DS_CELL, 230.0 + _dirty_cursor.x * DS_CELL)


## ── Game logic ─────────────────────────────────────────────────────

func _dirty_reveal(r: int, c: int) -> void:
	if _dirty_game_over or _dirty_won:
		return
	var cell: Dictionary = _dirty_board[r][c]
	if cell["flagged"]:
		return
	if cell["mine"]:
		cell["revealed"] = true
		_dirty_game_over = true
		_dirty_reveal_all_mines()
		_dirty_update_all()
		_dirty_refresh_face()
		return
	_dirty_flood_reveal(r, c)
	_dirty_update_all()
	if _dirty_unrevealed_safe() == 0:
		_dirty_win()


func _dirty_flood_reveal(r: int, c: int) -> void:
	var cell: Dictionary = _dirty_board[r][c]
	if cell["revealed"] or cell["flagged"]:
		return
	cell["revealed"] = true
	if cell["count"] != 0:
		return
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var rr: int = r + dr
			var cc: int = c + dc
			if rr >= 0 and rr < DS_GRID and cc >= 0 and cc < DS_GRID:
				_dirty_flood_reveal(rr, cc)


func _dirty_reveal_all_mines() -> void:
	for r in range(DS_GRID):
		for c in range(DS_GRID):
			if _dirty_board[r][c]["mine"]:
				_dirty_board[r][c]["revealed"] = true


func _dirty_flag(r: int, c: int) -> void:
	if _dirty_game_over or _dirty_won:
		return
	var cell: Dictionary = _dirty_board[r][c]
	if cell["revealed"]:
		return
	cell["flagged"] = not cell["flagged"]
	_dirty_update_all()
	_dirty_refresh_face()


func _dirty_on_cell_down(cell: Vector2i) -> void:
	if _dirty_game_over or _dirty_won:
		return
	var c: Dictionary = _dirty_board[cell.x][cell.y]
	if c["revealed"]:
		return
	_dirty_press_armed = true
	_dirty_press_cell = cell
	_dirty_refresh_face()


func _dirty_on_cell_up(cell: Vector2i) -> void:
	var was_armed: bool = _dirty_press_armed and _dirty_press_cell == cell
	_dirty_press_armed = false
	_dirty_refresh_face()
	if not was_armed:
		return
	if _dirty_flag_mode:
		_dirty_flag(cell.x, cell.y)
	else:
		_dirty_reveal(cell.x, cell.y)


func _dirty_on_cell_exited(cell: Vector2i) -> void:
	if _dirty_press_armed and _dirty_press_cell == cell:
		_dirty_press_armed = false
		_dirty_refresh_face()


func _dirty_restart() -> void:
	_dirty_new_board(Vector2i(DS_GRID / 2, DS_GRID / 2))
	_dirty_update_all()
	_dirty_update_cursor_rect()
	_dirty_refresh_face()


func _dirty_win() -> void:
	_dirty_won = true
	_dirty_award_win()
	_dirty_update_all()
	_dirty_refresh_face()


## ── Coin economy (reuses the shared Tetrivo coin pool) ─────────────

func _dirty_award_win() -> void:
	if _dirty_win_awarded:
		return
	var now: int = _now_sec()
	if _daily_available(now):
		GameState.tetrivo_gambled = false
	var awarded := 0
	if _dirty_hard and not GameState.tetrivo_gambled:
		awarded = 2
		GameState.tetrivo_coins_earned += 2
		GameState.tetrivo_gambled = true
		GameState.tetrivo_last_coin_time = now
	else:
		awarded = 1
		GameState.tetrivo_coins_earned += 1
		GameState.tetrivo_last_coin_time = now
	if awarded > 0:
		GameState.add_money(awarded)
		_save_tetrivo_state()
	_dirty_win_awarded = true


## ── Input ──────────────────────────────────────────────────────────

func _dirty_process(delta: float) -> void:
	if _dirty_game_over or _dirty_won:
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		_dirty_move_timer -= delta
		if _dirty_move_timer <= 0.0:
			_dirty_move_cursor(dir)
			_dirty_move_timer = 0.13
	else:
		_dirty_move_timer = 0.0


func _dirty_move_cursor(dir: Vector2) -> void:
	var nx: int = clampi(_dirty_cursor.x + int(round(dir.y)), 0, DS_GRID - 1)
	var ny: int = clampi(_dirty_cursor.y + int(round(dir.x)), 0, DS_GRID - 1)
	_dirty_cursor = Vector2i(nx, ny)
	_dirty_update_cursor_rect()


func _dirty_handle_input() -> void:
	var enter := InputSystem.is_pressed("confirm")
	if enter and not _enter_was_down:
		_dirty_reveal(_dirty_cursor.x, _dirty_cursor.y)
	_enter_was_down = enter
	var esc := InputSystem.is_pressed("cancel")
	if esc and not _esc_was_down:
		_close_dirtysweeper()
	_esc_was_down = esc
	if InputSystem.just_pressed("flag"):
		_dirty_flag_mode = not _dirty_flag_mode
		_dirty_update_all()
		_dirty_refresh_face()


func _unhandled_input(event: InputEvent) -> void:
	if not _dirty_active:
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_dirty_flag(_dirty_cursor.x, _dirty_cursor.y)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_dirty_restart()
			get_viewport().set_input_as_handled()


# ═══════════════ TRANSITIONS ═══════════════

func _leave_arcade_room() -> void:
	"""Leave the arcade room: a black block sweeps LEFT→RIGHT across the screen
	(covering it), then load the lobby. This is the reverse of the right→left
	wipe that plays when entering from the lobby."""
	if _leaving:
		return
	_leaving = true
	var wipe := ColorRect.new()
	wipe.color = Color(0, 0, 0, 1)
	wipe.position = Vector2(-ROOM_W, 0)  # Start fully off-screen to the left
	wipe.size = Vector2(ROOM_W, ROOM_H)
	wipe.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(wipe)
	var tween := create_tween()
	tween.tween_property(wipe, "position", Vector2(0, 0), 0.45)
	await tween.finished
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _turn_off_console() -> void:
	"""Turn the arcade console OFF (CRT power-off): the screen goes white and
	shrinks down vertically toward the middle until it's gone. Returns you to
	the idle arcade room so you can press E to boot it up again."""
	if _leaving:
		return
	_boot_active = false
	_browser_active = false
	_menu_active = false
	_game_active = false
	if _music:
		_music.stop()
	# Clear any on-screen console UI (browser / menu / overlays).
	for child: Node in _ui.get_children():
		child.queue_free()
	_stop_console_music()
	_remove_crt_overlay()

	# White screen that collapses vertically to the middle (power-off).
	var white := ColorRect.new()
	white.color = Color(1, 1, 1, 1)
	white.position = Vector2(0, 0)
	white.size = Vector2(ROOM_W, ROOM_H)
	white.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(white)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(white, "size:y", 0.0, 0.45)
	tween.tween_property(white, "position:y", ROOM_H / 2.0, 0.45)
	await tween.finished
	white.queue_free()
	if is_instance_valid(_machine_prompt):
		_machine_prompt.visible = false


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
