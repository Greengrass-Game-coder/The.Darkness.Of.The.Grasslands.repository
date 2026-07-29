class_name Lobby
extends CharacterBody2D

signal countdown_finished()

@export var countdown_duration: float = 60.0
@export var movement_speed: float = 200.0
@export var sprint_multiplier: float = 2.5

# HUD button positions — editable in inspector
@export var shop_button_pos: Vector2 = Vector2(16, 200)
@export var shop_button_size: Vector2 = Vector2(64, 64)
@export var inventory_button_pos: Vector2 = Vector2(16, 270)
@export var inventory_button_size: Vector2 = Vector2(64, 64)
@export var settings_button_pos: Vector2 = Vector2(16, 340)
@export var settings_button_size: Vector2 = Vector2(64, 64)

# Role toggle
@export var role_toggle_pos: Vector2 = Vector2(820, 660)

@onready var lobby_music: AudioStreamPlayer2D = $"../LobbyMusic"
@onready var countdown_label: Label = %CountdownLabel
@onready var timer: Timer = $"../CountdownTimer"
@onready var lobby_person: AnimatedSprite2D = $LobbyPerson
@onready var dialogue_ui: DialogueUI = $"../DialogueLayer"
@onready var brown_npc_area: Area2D = $"../BrownNPC"
@onready var interact_prompt: Label = $"../BrownNPC/InteractPrompt"
@onready var coord_label: Label = %CoordLabel
@onready var scary_overlay: ColorRect = $"../ScaryOverlay/OverlayRect"
@onready var come_back_label: Label = $"../ScaryOverlay/ComeBackLabel"
@onready var font_swap_timer: Timer = $"../ScaryOverlay/FontSwapTimer"
@onready var red_flower_area: Area2D = $"../RedFlower"
@onready var flower_prompt: Label = $"../RedFlower/FlowerPrompt"
@onready var evil_potato_area: Area2D = $"../EvilPotato"
@onready var potato_prompt: Label = $"../EvilPotato/PotatoPrompt"

@onready var browngrass_dialogue: DialogueLine = preload("res://resources/browngrass_dialogue.tres")
@onready var flower_dialogue: DialogueLine = preload("res://resources/flower_dialogue.tres")
@onready var evil_potato_dialogue: DialogueLine = preload("res://resources/evil_potato_dialogue.tres")
@onready var evil_potato_dialogue_repeat: DialogueLine = preload("res://resources/evil_potato_dialogue_repeat.tres")


var infade_tween: Tween

enum Direction { DOWN, UP, LEFT, RIGHT }

var _time_remaining: float = 0.0
var _last_direction: Direction = Direction.DOWN
var _brown_state: int = 0  # 0=first, 1=returned (left early), 2=finished
var _flower_dialogue_done: bool = false
var _potato_dialogue_done: bool = false

var _scare_active: bool = false
var _e_pressed_last_frame: bool = false
var _dialogue_cooldown: float = 0.0
var _screenshot_flash: ColorRect = null
var _shop_layer: ShopLayer = null
var _inventory_layer: InventoryLayer = null
var _settings_layer: SettingsLayer = null
var _analysis_overlay: CanvasLayer = null
var _analysis_timer: float = 0.0

# BitmapLabel references (Font1 sprite text replacements)
var _bitmap_countdown: BitmapLabel = null
var _bitmap_comeback: BitmapLabel = null

const SHOP_LAYER_SCENE: String = "res://scenes/shop_layer.tscn"
const INVENTORY_LAYER_SCENE: String = "res://scenes/inventory_layer.tscn"
const SETTINGS_LAYER_SCENE: String = "res://scenes/settings_layer.tscn"
const BACKGROUND_UI_TEXTURE: String = "res://The Darkness Of The Grasslands assets/UI/Lobby/Shop and inventory background UI.png"
const ANALYSIS_DURATION: float = 15.0

const NOTIF_FOCUS_OUT = NOTIFICATION_WM_WINDOW_FOCUS_OUT
const NOTIF_FOCUS_IN = NOTIFICATION_WM_WINDOW_FOCUS_IN


func _ready() -> void:
	_time_remaining = countdown_duration
	_replace_labels_with_bitmap()
	_update_label()
	timer.start(1.0)
	
	# Make music loop using finished signal (works on any AudioStream type)
	lobby_music.finished.connect(_on_music_finished)
	lobby_music.play()
	
	_show_idle_frame()
	
	# Brown NPC signals
	brown_npc_area.body_entered.connect(_on_brown_area_entered)
	brown_npc_area.body_exited.connect(_on_brown_area_exited)
	
	# Red Flower signals
	red_flower_area.body_entered.connect(_on_flower_area_entered)
	red_flower_area.body_exited.connect(_on_flower_area_exited)
	
	# Evil Potato signals
	evil_potato_area.body_entered.connect(_on_potato_area_entered)
	evil_potato_area.body_exited.connect(_on_potato_area_exited)
	
	interact_prompt.hide()
	flower_prompt.hide()
	potato_prompt.hide()
	_start_potato_flying()
	dialogue_ui.hide()
	_setup_screenshot_prank()
	_setup_shop_inventory()
	_create_leaderboard()
	_setup_chat()
	_setup_role_toggle()
	countdown_finished.connect(_on_lobby_countdown_finished)
	
	# Show match-end analysis if returning from a match
	if GameState.show_analysis:
		_show_match_analysis()


func _setup_chat() -> void:
	"""Create ChatLayer instance and connect its signals."""
	var chat := ChatLayer.new()
	chat.name = "ChatLayer"
	chat.chat_sent.connect(_on_chat_sent)
	add_child(chat)


func _on_chat_sent(text: String, is_admin: bool) -> void:
	"""Handle a chat message sent from ChatLayer."""
	# Handle "G" or "G help" locally (show all admin commands)
	var trimmed: String = text.strip_edges().to_lower()
	if trimmed == "g" or trimmed == "g help":
		_show_admin_help()
		return
	
	# "G setenv dev/prod" — toggle environment locally
	# "G env" — show current environment
	if trimmed == "g env" or trimmed == "g environment":
		var env_config = Engine.get_singleton("EnvironmentConfig") if Engine.has_singleton("EnvironmentConfig") else null
		var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
		if not chat_layer:
			return
		if not env_config:
			chat_layer.add_system_message("EnvironmentConfig not available")
			return
		var env_name: String = env_config.get_environment_name(env_config.environment)
		var ws_url: String = env_config.get_ws_url()
		chat_layer.add_system_message("Environment: " + env_name)
		chat_layer.add_system_message("WebSocket: " + ws_url)
		return
	
	if trimmed.begins_with("g setenv ") or trimmed.begins_with("g env "):
		var env_arg: String = trimmed.split(" ")[-1]
		var env_config = Engine.get_singleton("EnvironmentConfig") if Engine.has_singleton("EnvironmentConfig") else null
		if not env_config:
			var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
			if chat_layer:
				chat_layer.add_system_message("ERROR: EnvironmentConfig not found")
			return
		if env_arg == "dev" or env_arg == "development":
			env_config.set_dev()
			var msg: String = "Switched to DEV environment (ngrok tunnel)"
			var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
			if chat_layer: chat_layer.add_system_message(msg)
		elif env_arg == "prod" or env_arg == "production":
			env_config.set_prod()
			var msg: String = "Switched to PRODUCTION environment (Render live)"
			var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
			if chat_layer: chat_layer.add_system_message(msg)
		else:
			var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
			if chat_layer: chat_layer.add_system_message("Usage: G setenv dev | G setenv prod")
		return
	
	# "G ..." commands: forward to server if connected
	if is_admin and GameState.connected_to_server:
		var nm: Node = Engine.get_singleton("NetworkManager")
		if is_instance_valid(nm) and nm.has_method("send_admin_command"):
			nm.send_admin_command(text.trim_prefix("G "))
		return
	
	# Normal chat: forward to server if connected
	if GameState.connected_to_server:
		var nm: Node = Engine.get_singleton("NetworkManager")
		if is_instance_valid(nm) and nm.has_method("send_chat"):
			nm.send_chat(text)
	else:
		# Local echo for offline mode
		var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
		if chat_layer:
			chat_layer.add_system_message("Chat sent (offline): %s" % text)


func _show_admin_help() -> void:
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
	chat_layer.add_system_message("G setenv dev | G setenv prod - Toggle ngrok / Render")
	chat_layer.add_system_message("G env - Show current environment")
	chat_layer.add_system_message("=====================")


var _fm_retries: int = 0

func _replace_labels_with_bitmap() -> void:
	"""Hide scene Labels and create BitmapLabel replacements for key text."""
	# Use get_node(/root/FontManager) instead of Engine.get_singleton()
	# (custom autoload singletons may not work via Engine API in Godot 4.7.1)
	var fm_check: Node = get_node_or_null("/root/FontManager")
	if not is_instance_valid(fm_check):
		_fm_retries += 1
		if _fm_retries < 60:
			call_deferred("_replace_labels_with_bitmap")
		return
	# FontManager found via /root/ — proceed with label replacement
	# Replace CountdownLabel (Intermission text) with BitmapLabel
	if is_instance_valid(countdown_label):
		countdown_label.visible = false
		var bl := BitmapLabel.new()
		bl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bl.name = "BmpCountdown"
		bl.label_text = countdown_label.text
		bl.font_scale = 0.35
		bl.char_spacing = 6.0
		bl.horizontal_align = 1
		bl.font_color = Color(1, 1, 1, 1)
		bl.position = Vector2(0, 4)
		bl.size = Vector2(1024, 40)
		# Pixel font countdown replacement complete
		countdown_label.get_parent().add_child(bl)
		_bitmap_countdown = bl
		# BitmapLabel countdown created successfully
	
	# Replace COME BACK label with BitmapLabel
	if is_instance_valid(come_back_label):
		come_back_label.visible = false
		var bl2 := BitmapLabel.new()
		bl2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bl2.name = "BmpComeBack"
		bl2.label_text = "COME BACK."
		bl2.font_scale = 3.0
		bl2.char_spacing = 8.0
		bl2.horizontal_align = 1
		bl2.vertical_align = 1
		bl2.font_color = Color(1, 0, 0, 1)
		bl2.position = Vector2(0, 0)
		bl2.size = Vector2(1024, 768)
		bl2.visible = false
		come_back_label.get_parent().add_child(bl2)
		_bitmap_comeback = bl2

func _on_music_finished() -> void:
	lobby_music.play()


func _physics_process(_delta: float) -> void:
	if dialogue_ui.is_dialogue_active() or _is_any_ui_open():
		velocity = Vector2.ZERO
		_show_idle_frame()
		return
	
	var input_dir: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1
	input_dir = input_dir.normalized()
	var speed: float = movement_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= sprint_multiplier
	if input_dir != Vector2.ZERO:
		velocity = input_dir * speed
		_set_walking_animation(input_dir)
	else:
		velocity = Vector2.ZERO
		_show_idle_frame()
	move_and_slide()
	_update_coords()


func _notification(what: int) -> void:
	match what:
		NOTIF_FOCUS_OUT:
			_trigger_scare()
		NOTIF_FOCUS_IN:
			if _scare_active:
				_restore_focus()


# ------------------ Screenshot Prank ------------------

func _setup_screenshot_prank() -> void:
	# Create an invisible fullscreen black rect that flashes when F12 is pressed
	_screenshot_flash = ColorRect.new()
	_screenshot_flash.color = Color(0, 0, 0, 1)
	_screenshot_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screenshot_flash.anchors_preset = Control.PRESET_FULL_RECT
	_screenshot_flash.hide()
	# Add it as a sibling of the scary overlay
	var parent: Node = $"../ScaryOverlay"
	parent.add_child(_screenshot_flash)


func _on_screenshot_taken() -> void:
	if not _screenshot_flash:
		return
	_screenshot_flash.show()
	await get_tree().create_timer(0.1).timeout
	_screenshot_flash.hide()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: Key = event.keycode if event.keycode != 0 else event.physical_keycode
		if k == KEY_F12 or k == KEY_PRINT:
			_on_screenshot_taken()
			get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE:
			if _settings_layer and _settings_layer.visible:
				_settings_layer.close()
				get_viewport().set_input_as_handled()
			elif _shop_layer and _shop_layer.visible:
				_shop_layer.close()
				get_viewport().set_input_as_handled()
			elif _inventory_layer and _inventory_layer.visible:
				_inventory_layer.close()
				get_viewport().set_input_as_handled()


# ------------------ Shop & Inventory ------------------

func _setup_shop_inventory() -> void:
	# Instance the shop layer scene
	var shop_scene: PackedScene = load(SHOP_LAYER_SCENE)
	if not shop_scene:
		push_error("Lobby: Could not load shop layer scene")
		return
	
	_shop_layer = shop_scene.instantiate() as ShopLayer
	add_child(_shop_layer)
	_shop_layer.shop_closed.connect(_on_shop_closed)
	_shop_layer.hide()
	
	# Instance the inventory layer scene
	var inv_scene: PackedScene = load(INVENTORY_LAYER_SCENE)
	if not inv_scene:
		push_error("Lobby: Could not load inventory layer scene")
		return
	_inventory_layer = inv_scene.instantiate() as InventoryLayer
	add_child(_inventory_layer)
	_inventory_layer.inventory_closed.connect(_on_inventory_closed)
	_inventory_layer.hide()
	
	# Instance the settings layer scene
	var set_scene: PackedScene = load(SETTINGS_LAYER_SCENE)
	if not set_scene:
		push_error("Lobby: Could not load settings layer scene")
		return
	_settings_layer = set_scene.instantiate() as SettingsLayer
	add_child(_settings_layer)
	_settings_layer.settings_closed.connect(_on_settings_closed)
	_settings_layer.hide()
	
	# Create inventory and shop buttons in the HUD (reverse order = top z-order)
	_create_settings_button()
	_create_inventory_button()
	_create_shop_button()


func _create_shop_button() -> void:
	var hud: CanvasLayer = $"../HUD"
	var btn := TextureButton.new()
	btn.name = "ShopButton"
	btn.size = shop_button_size
	btn.position = shop_button_pos
	var shop_tex: Texture2D = load("res://The Darkness Of The Grasslands assets/UI/Lobby/Shop icon.png")
	if shop_tex:
		btn.texture_normal = shop_tex
	
	btn.pressed.connect(_on_shop_button_pressed)
	hud.add_child(btn)


func _create_inventory_button() -> void:
	var hud: CanvasLayer = $"../HUD"
	var btn := TextureButton.new()
	btn.name = "InventoryButton"
	btn.size = inventory_button_size
	btn.position = inventory_button_pos
	
	var inv_tex: Texture2D = load("res://The Darkness Of The Grasslands assets/UI/Lobby/Inventory icon.png")
	if inv_tex:
		btn.texture_normal = inv_tex
	
	btn.pressed.connect(_on_inventory_button_pressed)
	hud.add_child(btn)


func _on_shop_button_pressed() -> void:
	if not _shop_layer:
		return
	if dialogue_ui.is_dialogue_active():
		return
	_shop_layer.open()
	_toggle_hud_buttons(false)


func _on_inventory_button_pressed() -> void:
	if not _inventory_layer:
		return
	if dialogue_ui.is_dialogue_active():
		return
	_inventory_layer.open()
	_toggle_hud_buttons(false)


func _create_settings_button() -> void:
	var hud: CanvasLayer = $"../HUD"
	var btn := TextureButton.new()
	btn.name = "SettingsButton"
	btn.size = settings_button_size
	btn.position = settings_button_pos
	
	var set_tex: Texture2D = load("res://The Darkness Of The Grasslands assets/UI/Lobby/Settings icon.png")
	if set_tex:
		btn.texture_normal = set_tex
	
	btn.pressed.connect(_on_settings_button_pressed)
	hud.add_child(btn)


func _on_settings_button_pressed() -> void:
	if not _settings_layer:
		return
	if dialogue_ui.is_dialogue_active():
		return
	_settings_layer.open()
	_toggle_hud_buttons(false)


func _on_shop_closed() -> void:
	_toggle_hud_buttons(true)


func _on_inventory_closed() -> void:
	_toggle_hud_buttons(true)


func _on_settings_closed() -> void:
	_toggle_hud_buttons(true)


func _is_any_ui_open() -> bool:
	return (_shop_layer and _shop_layer.visible) or (_inventory_layer and _inventory_layer.visible) or (_settings_layer and _settings_layer.visible)


func _toggle_hud_buttons(show_buttons: bool) -> void:
	var hud: CanvasLayer = $"../HUD"
	var shop_btn: Node = hud.get_node_or_null("ShopButton")
	var inv_btn: Node = hud.get_node_or_null("InventoryButton")
	var set_btn: Node = hud.get_node_or_null("SettingsButton")
	if shop_btn:
		shop_btn.visible = show_buttons
	if inv_btn:
		inv_btn.visible = show_buttons
	if set_btn:
		set_btn.visible = show_buttons


func _setup_role_toggle() -> void:
	"""Create a killer/survivor role toggle button."""
	var hud: CanvasLayer = $"../HUD"
	if not hud:
		return
	
	var btn := Button.new()
	btn.name = "RoleToggle"
	btn.size = Vector2(140, 32)
	btn.position = role_toggle_pos
	
	if GameState.is_killer:
		btn.text = "ROLE: KILLER"
		btn.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
	else:
		btn.text = "ROLE: SURVIVOR"
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	
	btn.toggle_mode = true
	btn.button_pressed = GameState.is_killer
	btn.pressed.connect(_on_role_toggle_pressed.bind(btn))
	hud.add_child(btn)


func _on_role_toggle_pressed(btn: Button) -> void:
	"""Toggle killer/survivor role."""
	GameState.is_killer = btn.button_pressed
	if GameState.is_killer:
		btn.text = "ROLE: KILLER"
		btn.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
	else:
		btn.text = "ROLE: SURVIVOR"
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	print("Lobby: Role toggled — is_killer = ", GameState.is_killer)


func _on_lobby_countdown_finished() -> void:
	# Transition directly to game map (uses role toggle state)
	get_tree().change_scene_to_file("res://scenes/game_map.tscn")


func _update_coords() -> void:
	var map_x: int = roundi(position.x)
	var map_y: int = roundi(position.y)
	var display_y: int = 653 - map_y
	coord_label.text = "Map: (%d, %d) | Y: %d" % [map_x, display_y, display_y]


func _trigger_scare() -> void:
	if _scare_active:
		return
	_scare_active = true
	scary_overlay.show()
	# Show BitmapLabel "COME BACK" if available, else scene Label
	if is_instance_valid(_bitmap_comeback):
		_bitmap_comeback.visible = true
	come_back_label.show()
	font_swap_timer.start(0.5)
	if infade_tween and infade_tween.is_valid():
		infade_tween.kill()
	infade_tween = create_tween()
	infade_tween.tween_method(_set_circle_radius, 2.0, 0.0, 1.5).set_ease(Tween.EASE_IN)
	infade_tween.finished.connect(_on_infade_done)


func _set_circle_radius(value: float) -> void:
	var mat: ShaderMaterial = scary_overlay.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("circle_radius", value)


func _on_infade_done() -> void:
	pass


func _on_font_swap_timer_timeout() -> void:
	var sizes: Array[int] = [56, 64, 48, 72, 52, 68]
	var outline_sizes: Array[int] = [8, 12, 6, 14, 10]
	come_back_label.add_theme_font_size_override("font_size", sizes[randi() % sizes.size()])
	come_back_label.add_theme_constant_override("outline_size", outline_sizes[randi() % outline_sizes.size()])
	come_back_label.add_theme_color_override("font_outline_color", Color(0.8 + randf() * 0.2, 0.0, 0.0, 1.0))
	var shake_offset: Vector2 = Vector2(randi() % 5 - 2, randi() % 5 - 2)
	come_back_label.set_position(shake_offset)
	# Also update BitmapLabel version
	if is_instance_valid(_bitmap_comeback):
		_bitmap_comeback.font_scale = 0.6 + randi() % 5 * 0.05
		_bitmap_comeback.font_color = Color(0.9 + randf() * 0.1, 0.0, 0.0, 1.0)
		_bitmap_comeback.position = shake_offset


func _restore_focus() -> void:
	_scare_active = false
	font_swap_timer.stop()
	if infade_tween and infade_tween.is_valid():
		infade_tween.kill()
	var restore_tween: Tween = create_tween()
	restore_tween.tween_method(_set_circle_radius, 0.0, 2.0, 0.5).set_ease(Tween.EASE_OUT)
	await restore_tween.finished
	scary_overlay.hide()
	come_back_label.hide()
	come_back_label.set_position(Vector2.ZERO)
	come_back_label.add_theme_font_size_override("font_size", 56)
	come_back_label.add_theme_constant_override("outline_size", 10)
	come_back_label.add_theme_color_override("font_outline_color", Color(1, 0, 0, 1))
	if is_instance_valid(_bitmap_comeback):
		_bitmap_comeback.visible = false
		_bitmap_comeback.position = Vector2.ZERO
		_bitmap_comeback.font_scale = 0.7
		_bitmap_comeback.font_color = Color(1, 1, 1, 1)


# ------------------ Brown NPC ------------------

func _on_brown_area_entered(_body: Node2D) -> void:
	if _brown_state == 2:
		return
	interact_prompt.text = "Press [E] to talk"
	interact_prompt.show()


func _on_brown_area_exited(_body: Node2D) -> void:
	interact_prompt.hide()


# ------------------ Red Flower NPC ------------------

func _on_flower_area_entered(_body: Node2D) -> void:
	if not _flower_dialogue_done:
		flower_prompt.text = "Press [E] to examine"
		flower_prompt.show()


func _on_flower_area_exited(_body: Node2D) -> void:
	flower_prompt.hide()


# ------------------ Evil Potato NPC ------------------

func _start_potato_flying() -> void:
	"""Make the Evil Potato hover up and down with a gentle bob."""
	if not is_instance_valid(evil_potato_area):
		return
	var sprite: Sprite2D = evil_potato_area.get_node_or_null("Visual")
	if not sprite:
		return
	var orig_y: float = sprite.position.y
	var tween: Tween = create_tween().set_loops()
	tween.tween_property(sprite, "position", Vector2(sprite.position.x, orig_y - 20.0), 1.5).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sprite, "position", Vector2(sprite.position.x, orig_y), 1.5).set_ease(Tween.EASE_IN_OUT)


func _on_potato_area_entered(_body: Node2D) -> void:
	potato_prompt.show()


func _on_potato_area_exited(_body: Node2D) -> void:
	potato_prompt.hide()


# ------------------ E Key + Dialogue ------------------

func _process(delta: float) -> void:
	# Handle analysis overlay timer
	if _analysis_overlay != null:
		_analysis_timer -= delta
		if _analysis_timer <= 0.0:
			_hide_match_analysis()
		# Don't block dialogue or movement — overlay stays on top
		if _analysis_overlay != null:
			return  # Wait until analysis is dismissed before processing lobby
	
	if dialogue_ui.is_dialogue_active():
		return
	
	# Cooldown after dialogue ends to prevent instant re-trigger
	if _dialogue_cooldown > 0.0:
		_dialogue_cooldown -= delta
		# Keep _e_pressed_last_frame true during cooldown
		_e_pressed_last_frame = true
		if Input.is_key_pressed(KEY_E):
			return  # Still holding E from dialogue, skip
	
	if Input.is_key_pressed(KEY_E) and not _e_pressed_last_frame:
		_e_pressed_last_frame = true
		if interact_prompt.visible:
			interact_prompt.hide()
			_ensure_dialogue_connect()
			# Determine which dialogue to start based on state
			match _brown_state:
				2:  # All questions finished
					dialogue_ui.start_dialogue_at_line_with(browngrass_dialogue, 19)
				1:  # Came back after leaving early
					dialogue_ui.start_dialogue_at_line_with(browngrass_dialogue, 18)
				_:  # First visit (state 0)
					dialogue_ui.start_dialogue_with(browngrass_dialogue)
		elif flower_prompt.visible and not _flower_dialogue_done:
			_flower_dialogue_done = true
			flower_prompt.hide()
			_ensure_dialogue_connect()
			dialogue_ui.start_dialogue_with(flower_dialogue)
		elif potato_prompt.visible:
			potato_prompt.hide()
			_ensure_dialogue_connect()
			if _potato_dialogue_done:
				dialogue_ui.start_dialogue_with(evil_potato_dialogue_repeat)
			else:
				_potato_dialogue_done = true
				dialogue_ui.start_dialogue_with(evil_potato_dialogue)
	elif not Input.is_key_pressed(KEY_E):
		_e_pressed_last_frame = false


func _ensure_dialogue_connect() -> void:
	if dialogue_ui.dialogue_finished.is_connected(_on_dialogue_finished):
		dialogue_ui.dialogue_finished.disconnect(_on_dialogue_finished)
	dialogue_ui.dialogue_finished.connect(_on_dialogue_finished)


func _on_dialogue_finished() -> void:
	dialogue_ui.dialogue_finished.disconnect(_on_dialogue_finished)
	dialogue_ui.hide()
	_dialogue_cooldown = 0.5  # Prevent instant re-trigger
	_e_pressed_last_frame = true  # Swallow the current E press
	_update_brown_state()


func _update_brown_state() -> void:
	if _brown_state == 2:
		return  # Already finished
	
	# Check if all hub questions are exhausted
	var all_exhausted: bool = dialogue_ui.is_all_questions_exhausted_at(8)
	
	if all_exhausted:
		_brown_state = 2
		interact_prompt.hide()
	elif _brown_state == 0:
		# First visit ended without exhausting everything - they left early
		_brown_state = 1


# ------------------ Countdown ------------------

func _on_countdown_timer_timeout() -> void:
	_time_remaining -= 1.0
	_update_label()
	
	if _time_remaining <= 0.0:
		_time_remaining = countdown_duration
		_update_label()
		countdown_finished.emit()


func _update_label() -> void:
	var seconds: int = ceili(_time_remaining)
	var txt: String = "Intermission: %d left." % seconds
	countdown_label.text = txt
	if is_instance_valid(_bitmap_countdown):
		_bitmap_countdown.label_text = txt


# ------------------ Animation ------------------

func _set_walking_animation(direction: Vector2) -> void:
	if abs(direction.x) > 0:
		if direction.x < 0:
			lobby_person.animation = &"walk_left"
			_last_direction = Direction.LEFT
		else:
			lobby_person.animation = &"walk_right"
			_last_direction = Direction.RIGHT
	else:
		if direction.y < 0:
			lobby_person.animation = &"walk_up"
			_last_direction = Direction.UP
		else:
			lobby_person.animation = &"walk_down"
			_last_direction = Direction.DOWN
	lobby_person.play()


func _show_idle_frame() -> void:
	match _last_direction:
		Direction.UP:
			lobby_person.animation = &"idle_up"
		Direction.LEFT:
			lobby_person.animation = &"idle_left"
		Direction.RIGHT:
			lobby_person.animation = &"idle_right"
		_:
			lobby_person.animation = &"idle_down"
	lobby_person.play()


# ------------------ Match Analysis Overlay ------------------

func _show_match_analysis() -> void:
	"""Show the end-of-round analysis overlay with zoom-in animation."""
	if _analysis_overlay != null:
		return
	
	_analysis_overlay = CanvasLayer.new()
	_analysis_overlay.name = "MatchAnalysis"
	_analysis_overlay.layer = 20
	# Add to scene root (not Player) so CanvasLayer renders properly
	get_parent().add_child(_analysis_overlay)
	
	# Dark background
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.size = Vector2(1280, 720)
	bg.color = Color(0, 0, 0, 0.7)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_analysis_overlay.add_child(bg)
	
	# Panel with Background UI texture (centered)
	var panel := Control.new()
	panel.name = "Panel"
	panel.size = Vector2(500, 480)
	panel.position = Vector2(390, 120)
	_analysis_overlay.add_child(panel)
	
	# Background texture
	var bg_tex := TextureRect.new()
	bg_tex.name = "BgTexture"
	bg_tex.size = Vector2(500, 480)
	bg_tex.texture = load(BACKGROUND_UI_TEXTURE)
	bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	panel.add_child(bg_tex)
	
	# Inner semi-transparent overlay for readability
	var inner := ColorRect.new()
	inner.name = "Inner"
	inner.size = Vector2(480, 300)
	inner.position = Vector2(10, 80)
	inner.color = Color(0.05, 0.05, 0.1, 0.75)
	panel.add_child(inner)
	
	# Title
	var title := Label.new()
	title.name = "Title"
	title.text = "ROUND SUMMARY"
	title.position = Vector2(20, 20)
	title.size = Vector2(460, 40)
	title.add_theme_color_override("font_color", Color(1, 1, 0.7, 1))
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	
	# Separator
	var sep := ColorRect.new()
	sep.position = Vector2(50, 65)
	sep.size = Vector2(400, 2)
	sep.color = Color(1, 1, 1, 0.3)
	panel.add_child(sep)
	
	# Character icon
	var char_icon_path: String = "res://The Darkness Of The Grasslands assets/UI/Lobby/%s - survivor icon.png" % GameState.match_character_name
	if ResourceLoader.exists(char_icon_path):
		var tex: Texture2D = load(char_icon_path)
		if tex:
			var icon := TextureRect.new()
			icon.name = "CharIcon"
			icon.texture = tex
			icon.size = Vector2(64, 64)
			icon.position = Vector2(218, 90)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			panel.add_child(icon)
	
	# Name label
	var name_lbl := Label.new()
	name_lbl.name = "NameLabel"
	name_lbl.text = GameState.match_character_name
	name_lbl.position = Vector2(20, 165)
	name_lbl.size = Vector2(460, 30)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(name_lbl)
	
	# Stats
	var stats_data: Array[Dictionary] = [
		{"label": "Damage Taken", "value": "%d" % GameState.match_damage_taken},
		{"label": "Punches Landed", "value": "%d" % GameState.match_damage_dealt},
	]
	var stat_y: float = 210.0
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
	
	# "Match Complete" footer
	var footer := Label.new()
	footer.text = "Match Complete"
	footer.position = Vector2(20, 310)
	footer.size = Vector2(460, 30)
	footer.add_theme_color_override("font_color", Color(0.5, 1, 0.5, 1))
	footer.add_theme_font_size_override("font_size", 18)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(footer)
	
	# Close / Dismiss button
	var close_btn := Button.new()
	close_btn.text = "Continue"
	close_btn.position = Vector2(150, 400)
	close_btn.size = Vector2(200, 44)
	close_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(_hide_match_analysis)
	panel.add_child(close_btn)
	
	# Play zoom-in animation (like shop/settings layers)
	panel.scale = Vector2(0.8, 0.8)
	panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "scale", Vector2(1, 1), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.2)
	
	# Auto-dismiss after 15 seconds
	_analysis_timer = ANALYSIS_DURATION


func _hide_match_analysis() -> void:
	"""Dismiss the analysis overlay and resume lobby."""
	if not is_instance_valid(_analysis_overlay):
		GameState.show_analysis = false
		return
	
	# Play shrink-out animation
	var panel: Control = _analysis_overlay.get_node_or_null("Panel")
	if panel:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(panel, "scale", Vector2(0.9, 0.9), 0.15)
		tween.tween_property(panel, "modulate", Color(1, 1, 1, 0), 0.15)
		await tween.finished
	
	if not is_instance_valid(_analysis_overlay):
		return
	
	_analysis_overlay.queue_free()
	_analysis_overlay = null
	GameState.show_analysis = false
	print("Lobby: Analysis dismissed")


# ---------- LEADERBOARD ----------

var _leaderboard_panel: Control = null
var _leaderboard_visible: bool = true
var _toggle_arrow: Button = null
var _leaderboard_entries: Array[Button] = []
var _info_popup: Control = null

@export var leaderboard_pos: Vector2 = Vector2(774, 80)
@export var leaderboard_size: Vector2 = Vector2(250, 200)
@export var leaderboard_arrow_pos: Vector2 = Vector2(-24, 80)

func _create_leaderboard() -> void:
	"""Create a collapsible leaderboard panel in the HUD with clickable entries."""
	var hud: CanvasLayer = $"../HUD"
	if not hud:
		return
	
	# Main panel container
	var panel := Control.new()
	panel.name = "Leaderboard"
	panel.position = leaderboard_pos
	panel.size = leaderboard_size
	hud.add_child(panel)
	_leaderboard_panel = panel
	
	# Dark background
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.size = leaderboard_size
	bg.color = Color(0.1, 0.1, 0.1, 0.75)
	panel.add_child(bg)
	
	# Title (BitmapLabel)
	var title := BitmapLabel.new()
	title.name = "Title"
	title.label_text = "LEADERBOARD"
	title.font_scale = 0.16
	title.char_spacing = 3.0
	title.font_color = Color(1, 1, 0.7, 1)
	title.position = Vector2(10, 4)
	title.size = Vector2(230, 28)
	panel.add_child(title)
	
	# Separator
	var sep := ColorRect.new()
	sep.name = "Sep"
	sep.position = Vector2(10, 34)
	sep.size = Vector2(180, 2)
	sep.color = Color(1, 1, 1, 0.3)
	panel.add_child(sep)
	
	# Entry container (will hold player rows)
	var entry_container := VBoxContainer.new()
	entry_container.name = "EntryContainer"
	entry_container.position = Vector2(10, 42)
	entry_container.size = Vector2(180, 150)
	panel.add_child(entry_container)
	
	# Populate entries
	_update_leaderboard_entries()
	
	# Toggle arrow button on the left edge
	var arrow := Button.new()
	arrow.name = "ToggleArrow"
	arrow.text = "<"
	arrow.position = leaderboard_arrow_pos
	arrow.size = Vector2(24, 32)
	arrow.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	arrow.add_theme_font_size_override("font_size", 14)
	arrow.pressed.connect(_toggle_leaderboard)
	panel.add_child(arrow)
	_toggle_arrow = arrow
	
	_update_leaderboard_visibility()


func _update_leaderboard_entries() -> void:
	"""Rebuild player entries from GameState player_rings."""
	var container: VBoxContainer = _leaderboard_panel.get_node_or_null("EntryContainer")
	if not container:
		return
	
	# Clear existing entries
	for child: Node in container.get_children():
		child.queue_free()
	_leaderboard_entries.clear()
	
	# Get sorted player list
	var players: Array[String] = GameState.get_players_sorted_by_rings()
	
	# Always include the local player (if not already in list)
	var local_name: String = "You"
	if Engine.has_singleton("AuthManager"):
		var am = Engine.get_singleton("AuthManager")
		if am.is_logged_in():
			local_name = am.current_username
	if local_name not in players:
		players.insert(0, local_name)
	
	# Create clickable entry for each player
	for pname: String in players:
		var rings: int = GameState.get_player_rings(pname)
		var is_self: bool = pname == local_name
		var entry := Button.new()
		entry.name = "Entry_%s" % pname
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.size.y = 22
		entry.text = "  %s — R:%d" % [pname, rings]
		entry.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6, 1) if is_self else Color(1, 1, 1, 1))
		entry.add_theme_font_size_override("font_size", 13)
		entry.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		entry.add_theme_constant_override("shadow_offset_x", 1)
		entry.add_theme_constant_override("shadow_offset_y", 1)
		entry.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		entry.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		entry.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		entry.pressed.connect(_on_leaderboard_entry_pressed.bind(pname))
		container.add_child(entry)
		_leaderboard_entries.append(entry)


func _on_leaderboard_entry_pressed(player_name: String) -> void:
	"""Show info popup for the clicked player."""
	_show_player_info_popup(player_name)


func _show_player_info_popup(player_name: String) -> void:
	"""Create an info popup positioned under the leaderboard."""
	# Remove existing popup if any
	if is_instance_valid(_info_popup):
		_info_popup.queue_free()
	
	var hud: CanvasLayer = $"../HUD"
	if not hud:
		return
	
	var popup := Control.new()
	popup.name = "PlayerInfoPopup"
	# Position directly under the leaderboard (leaderboard is at Y=80, size 200)
	popup.position = Vector2(774, 280)
	popup.size = Vector2(200, 180)
	hud.add_child(popup)
	_info_popup = popup
	
	# Background
	var bg := ColorRect.new()
	bg.size = Vector2(200, 180)
	bg.color = Color(0.05, 0.05, 0.05, 0.85)
	popup.add_child(bg)
	
	# Title
	var title := Label.new()
	title.text = "  " + player_name
	title.position = Vector2(8, 8)
	title.size = Vector2(200, 24)
	title.add_theme_color_override("font_color", Color(1, 1, 0.7, 1))
	title.add_theme_font_size_override("font_size", 16)
	popup.add_child(title)
	
	# Stats
	var stats: Array[String] = [
		"Rings: %d" % GameState.get_player_rings(player_name),
		"Killer: Violentgrass",
		"Survivor: Greengrass",
		"Playtime: --",
		"Wins (Killer): --",
		"Wins (Survivor): --",
	]
	
	var y_offset: float = 38.0
	for stat: String in stats:
		var stat_label := Label.new()
		stat_label.text = "  " + stat
		stat_label.position = Vector2(8, y_offset)
		stat_label.size = Vector2(200, 20)
		stat_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
		stat_label.add_theme_font_size_override("font_size", 13)
		popup.add_child(stat_label)
		y_offset += 22.0
	
	# Close button
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.position = Vector2(172, 4)
	close_btn.size = Vector2(24, 24)
	close_btn.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
	close_btn.pressed.connect(_close_player_info_popup)
	popup.add_child(close_btn)


func _close_player_info_popup() -> void:
	if is_instance_valid(_info_popup):
		_info_popup.queue_free()
		_info_popup = null


func _toggle_leaderboard() -> void:
	"""Toggle the leaderboard panel open/closed with animated arrow slide."""
	_leaderboard_visible = not _leaderboard_visible
	# Close info popup when toggling
	_close_player_info_popup()
	_update_leaderboard_visibility()


func _update_leaderboard_visibility() -> void:
	"""Update leaderboard visibility based on toggle and game settings."""
	if not is_instance_valid(_leaderboard_panel):
		return
	
	var hide_entirely: bool = "hide_leaderboard" in GameState and GameState.hide_leaderboard
	
	if hide_entirely:
		_leaderboard_panel.visible = false
		return
	
	_leaderboard_panel.visible = true
	
	var bg: ColorRect = _leaderboard_panel.get_node_or_null("Bg")
	var title = _leaderboard_panel.get_node_or_null("Title")
	var sep: ColorRect = _leaderboard_panel.get_node_or_null("Sep")
	var entry_container: VBoxContainer = _leaderboard_panel.get_node_or_null("EntryContainer")
	
	if _leaderboard_visible:
		if bg: bg.visible = true
		if title: title.visible = true
		if sep: sep.visible = true
		if entry_container: entry_container.visible = true
		if _toggle_arrow:
			_toggle_arrow.text = "<"
			# Slide arrow back to the left edge of the panel
			var tw: Tween = create_tween()
			tw.tween_property(_toggle_arrow, "position", leaderboard_arrow_pos, 0.15).set_ease(Tween.EASE_OUT)
	else:
		if bg: bg.visible = false
		if title: title.visible = false
		if sep: sep.visible = false
		if entry_container: entry_container.visible = false
		if _toggle_arrow:
			_toggle_arrow.text = ">"
			# Slide arrow to the right edge of the panel (so it sits at the screen edge)
			var collapsed_pos: Vector2 = Vector2(leaderboard_size.x - 24, leaderboard_arrow_pos.y)
			var tw: Tween = create_tween()
			tw.tween_property(_toggle_arrow, "position", collapsed_pos, 0.15).set_ease(Tween.EASE_OUT)
