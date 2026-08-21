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

# ── State ──
var _player: CharacterBody2D = null
var _sprite: AnimatedSprite2D = null
var _machine_area: Area2D = null
var _machine_prompt: Label = null
var _ui: CanvasLayer = null
var _boot_active: bool = false
var _browser_active: bool = false   # Minigame browser (list of cartridges)
var _menu_active: bool = false      # A specific minigame's title/menu is showing
var _browser_msg: Label = null      # The "only this in the demo" nag text
var _browser_msg_visible: bool = false
var _music: AudioStreamPlayer = null
var _idle_anim: String = "idle_down"
var _e_was_down: bool = false
var _esc_was_down: bool = false
var _enter_was_down: bool = false
var _nav_was_down: bool = false


func _ready() -> void:
	_build_room()
	_build_player()
	_build_machine()
	_build_ui()
	# Reveal from black (right-to-left wipe continues from the lobby).
	_reveal_from_black()


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
	if _browser_active and not _menu_active and not _boot_active:
		var nav_down := (
			Input.is_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_W)
			or Input.is_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_A)
			or Input.is_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_S)
			or Input.is_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_D)
		)
		if nav_down and not _nav_was_down:
			_on_browser_navigate()
		var enter_down := Input.is_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_ENTER)
		if enter_down and not _enter_was_down:
			_launch_tetrino()
		_nav_was_down = nav_down
		_enter_was_down = enter_down
	else:
		_nav_was_down = false
		_enter_was_down = false

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


func _on_esc_pressed() -> void:
	if _menu_active:
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
	# 1) VHS-style flicker: rapid random black/white flashes.
	var flick := ColorRect.new()
	flick.color = Color(0, 0, 0, 1)
	flick.position = Vector2(0, 0)
	flick.size = Vector2(ROOM_W, ROOM_H)
	flick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(flick)

	var t_end := Time.get_ticks_msec() + int(FLICKER_DURATION * 1000.0)
	while Time.get_ticks_msec() < t_end:
		flick.color = Color(1, 1, 1, 1) if randi() % 2 == 0 else Color(0, 0, 0, 1)
		await get_tree().create_timer(randf_range(0.02, 0.06)).timeout
	flick.color = Color(0, 0, 0, 1)
	await get_tree().create_timer(0.1).timeout
	flick.queue_free()

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

	_boot_active = false
	_show_minigame_browser()


# ═══════════════ MINIGAME BROWSER ═══════════════

func _show_minigame_browser() -> void:
	"""Black-screen cartridge browser. In the demo there is only one minigame:
	Tetrino. WASD navigation just shows a friendly 'this is all we have' nag."""
	if _browser_active:
		return
	_browser_active = true
	_browser_msg_visible = false

	# Looping music for the minigame (starts once the machine is booted).
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.stream = load(TETRINO_MUSIC)
		_music.bus = "Music"
		_music.volume_db = -6.0
		add_child(_music)
	if not _music.playing:
		_music.play()

	# Black backdrop.
	var bg := ColorRect.new()
	bg.name = "BrowserBG"
	bg.color = Color(0, 0, 0, 1)
	bg.position = Vector2(0, 0)
	bg.size = Vector2(ROOM_W, ROOM_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bg)

	var title := Label.new()
	title.text = "MINIGAME BROWSER"
	title.position = Vector2(0, 40)
	title.size = Vector2(ROOM_W, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.5, 1.0, 1.0, 1))
	title.add_theme_font_size_override("font_size", 40)
	_ui.add_child(title)

	# The single cartridge: Tetrino (highlighted/selected).
	var card := ColorRect.new()
	card.name = "TetrinoCard"
	card.color = Color(0.1, 0.12, 0.16, 1)
	card.position = Vector2((ROOM_W - 420) / 2.0, 150)
	card.size = Vector2(420, 300)
	_ui.add_child(card)

	var thumb := TextureRect.new()
	thumb.texture = load(TETRINO_THUMB)
	thumb.position = card.position + Vector2(40, 40)
	thumb.size = Vector2(338, 220)
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ui.add_child(thumb)

	var card_name := Label.new()
	card_name.text = "TETRINO"
	card_name.position = Vector2(0, card.position.y + 230)
	card_name.size = Vector2(ROOM_W, 60)
	card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_name.add_theme_color_override("font_color", Color(0.3, 1.0, 1.0, 1))
	card_name.add_theme_font_size_override("font_size", 44)
	_ui.add_child(card_name)

	var hint := Label.new()
	hint.text = "WASD  navigate   •   ENTER  play   •   ESC  leave"
	hint.position = Vector2(0, ROOM_H - 80)
	hint.size = Vector2(ROOM_W, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
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
	_browser_msg = Label.new()
	_browser_msg.text = "This is the minigame we got in the Demo, so either have fun or just leave the game."
	_browser_msg.position = Vector2(0, ROOM_H - 130)
	_browser_msg.size = Vector2(ROOM_W, 40)
	_browser_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_browser_msg.add_theme_color_override("font_color", Color(1, 1, 0.8, 1))
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


# ═══════════════ TETRINO TITLE / MENU ═══════════════

func _show_tetrino_menu() -> void:
	if _menu_active:
		return
	_menu_active = true

	# Looping music for the minigame.
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.stream = load(TETRINO_MUSIC)
		_music.bus = "Music"
		_music.volume_db = -6.0
		add_child(_music)
	if not _music.playing:
		_music.play()

	# Black backdrop behind the menu.
	var bg := ColorRect.new()
	bg.name = "TetrinoBG"
	bg.color = Color(0, 0, 0, 1)
	bg.position = Vector2(0, 0)
	bg.size = Vector2(ROOM_W, ROOM_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bg)

	# Thumbnail as the title art.
	var thumb := TextureRect.new()
	thumb.texture = load(TETRINO_THUMB)
	thumb.position = Vector2((ROOM_W - 338) / 2.0, 70)
	thumb.size = Vector2(338, 258)
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ui.add_child(thumb)

	var title := Label.new()
	title.text = "TETRINO"
	title.position = Vector2(0, 340)
	title.size = Vector2(ROOM_W, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.3, 1.0, 1.0, 1))
	title.add_theme_font_size_override("font_size", 56)
	_ui.add_child(title)

	# Placeholder play field (menu-first scope).
	var field_border := ColorRect.new()
	field_border.color = Color(0.25, 0.25, 0.3, 1)
	field_border.position = Vector2((ROOM_W - 220) / 2.0, 430)
	field_border.size = Vector2(220, 220)
	_ui.add_child(field_border)

	var field_bg := ColorRect.new()
	field_bg.color = Color(0.05, 0.05, 0.08, 1)
	field_bg.position = Vector2((ROOM_W - 216) / 2.0, 434)
	field_bg.size = Vector2(212, 212)
	_ui.add_child(field_bg)

	var hint := Label.new()
	hint.text = "INSERT COIN TO PLAY\n(coming soon)"
	hint.position = Vector2(0, ROOM_H - 120)
	hint.size = Vector2(ROOM_W, 50)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	hint.add_theme_font_size_override("font_size", 20)
	_ui.add_child(hint)

	var back := Label.new()
	back.text = "Press [ESC] to exit"
	back.position = Vector2(0, ROOM_H - 60)
	back.size = Vector2(ROOM_W, 30)
	back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	back.add_theme_font_size_override("font_size", 14)
	_ui.add_child(back)


func _close_tetrino() -> void:
	_menu_active = false
	for child: Node in _ui.get_children():
		child.queue_free()
	# Back to the cartridge browser (music keeps looping).
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
