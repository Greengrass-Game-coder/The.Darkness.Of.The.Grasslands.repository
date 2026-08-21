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
const TETRINO_THUMB: String = "res://The Darkness Of The Grasslands assets/Thumbnails/Minigame_TETRINO.thumnail.png"
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

func _physics_process(_delta: float) -> void:
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
	if _browser_active and not _menu_active and not _boot_active:
		_launch_tetrino()
	elif _menu_active and not _game_active:
		# On the Tetrino title screen, Enter starts the actual minigame — this
		# is when the music begins to play.
		_start_tetrino_game()


func _on_esc_pressed() -> void:
	if _game_active:
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
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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
	"""Start tetrino.wav looping with a one-time fade-in. The track loops
	seamlessly at the stream level, so the fade only ever runs once — never on
	subsequent loop iterations."""
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.stream = load(TETRINO_MUSIC)
		_music.bus = "Music"
		# Force forward looping so the track repeats (even if the .wav lacks
		# embedded loop points).
		if _music.stream is AudioStreamWAV:
			var wav: AudioStreamWAV = _music.stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			if wav.loop_end <= 0:
				wav.loop_end = int(wav.data.size() / 2.0)
		add_child(_music)
	if not _music.playing:
		_music.volume_db = -60.0
		_music.play()
		var tween := create_tween()
		tween.tween_property(_music, "volume_db", -6.0, 1.5).set_trans(Tween.TRANS_SINE)


func _start_tetrino_game() -> void:
	"""Player pressed ENTER on the title screen — the actual Tetris minigame
	now begins, which is when the music fades in."""
	if not _menu_active or _game_active:
		return
	_game_active = true

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

	var field_border := ColorRect.new()
	field_border.color = p["panel_edge"]
	field_border.position = Vector2((ROOM_W - 220) / 2.0, 120)
	field_border.size = Vector2(440, 500)
	_ui.add_child(field_border)

	var field_bg := ColorRect.new()
	field_bg.color = p["panel"]
	field_bg.position = Vector2((ROOM_W - 216) / 2.0, 124)
	field_bg.size = Vector2(432, 492)
	_ui.add_child(field_bg)

	var playing := Label.new()
	playing.text = "TETRINO — PLAYING"
	playing.position = Vector2(0, 80)
	playing.size = Vector2(ROOM_W, 40)
	playing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	playing.add_theme_color_override("font_color", p["accent"])
	playing.add_theme_font_size_override("font_size", 28)
	_ui.add_child(playing)

	var back := Label.new()
	back.text = "Press [ESC] to exit"
	back.position = Vector2(0, ROOM_H - 60)
	back.size = Vector2(ROOM_W, 30)
	back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.add_theme_color_override("font_color", p["text_dim"])
	back.add_theme_font_size_override("font_size", 14)
	_ui.add_child(back)


func _exit_tetrino_game() -> void:
	"""ESC from inside the game goes back to the Tetrino title screen and stops
	the music (it only plays while actually in the minigame)."""
	if not _game_active:
		return
	if _music:
		_music.stop()
	_menu_active = false
	_game_active = false
	for child: Node in _ui.get_children():
		child.queue_free()
	_show_tetrino_menu()


func _close_tetrino() -> void:
	_menu_active = false
	_game_active = false
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
