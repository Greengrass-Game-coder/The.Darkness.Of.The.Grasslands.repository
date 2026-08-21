extends CharacterBody2D
# Scene root — accessed via scene path, no class_name needed (avoids EOSG plugin conflict)

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

# Friends
@export var friends_button_pos: Vector2 = Vector2(16, 130)
@export var friends_button_size: Vector2 = Vector2(64, 64)

# Spectate (see who's playing in the ongoing match while in the lobby)
@export var spectate_button_pos: Vector2 = Vector2(16, 410)
@export var spectate_button_size: Vector2 = Vector2(64, 64)
@export var spectate_panel_pos: Vector2 = Vector2(90, 160)
@export var spectate_panel_size: Vector2 = Vector2(260, 220)

# (Role toggle removed — server assigns roles)

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
@onready var evil_potato_orange_dialogue: DialogueLine = preload("res://resources/evil_potato_orange_guy_dialogue.tres")


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
var _friends_panel: FriendsPanel = null

# Spectate state — the toggleable "who's playing" panel + live match timer
var _spectate_btn: TextureButton = null
var _spectate_panel: Control = null
var _spectate_timer_label: Label = null
var _spectate_visible: bool = false
var _spectate_players: Array[Dictionary] = []
var _last_roster_sig: String = ""
var _spectate_phase: String = ""
var _spectate_time_remaining: float = 0.0
var _spectate_timer_tick: float = 0.0

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
	_setup_admin_panel()
	_setup_chat()
	_setup_spectate()
	# _setup_role_toggle() — removed, server assigns roles
	countdown_finished.connect(_on_lobby_countdown_finished)
	
	# Show match-end analysis if returning from a match
	if GameState.show_analysis:
		_show_match_analysis()


func _setup_chat() -> void:
	"""Create ChatLayer instance and connect its signals."""
	var chat := ChatLayer.new()
	chat.name = "ChatLayer"
	chat.chat_sent.connect(_on_chat_sent)
	chat.chat_opened.connect(_on_lobby_chat_opened)
	chat.chat_closed.connect(_on_lobby_chat_closed)
	add_child(chat)
	
	# Listen for incoming chat messages from the server
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if is_instance_valid(nm) and nm.has_signal("chat_message_received"):
		if not nm.chat_message_received.is_connected(_on_lobby_server_chat):
			nm.chat_message_received.connect(_on_lobby_server_chat)


func _on_lobby_chat_opened() -> void:
	"""Disable ALL player processing (movement + abilities) when chatting."""
	set_physics_process(false)
	process_mode = Node.PROCESS_MODE_DISABLED


func _on_lobby_server_chat(sender: String, text: String) -> void:
	"""Display a chat message received from the server relay."""
	var chat_layer: ChatLayer = get_node_or_null("ChatLayer")
	if chat_layer:
		if sender == "SERVER":
			chat_layer.add_system_message(text)
		else:
			chat_layer.add_message(sender, text)


func _on_lobby_chat_closed() -> void:
	"""Re-enable ALL player processing when done chatting."""
	set_physics_process(true)
	process_mode = Node.PROCESS_MODE_INHERIT


func _setup_admin_panel() -> void:
	"""Create the admin panel instance for private server hosts."""
	var panel := AdminPanel.new()
	panel.name = "AdminPanel"
	add_child(panel)


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
		var env_config = get_node("/root/EnvironmentConfig")
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
	
	# "G Gui" — toggle admin GUI panel
	if trimmed == "g gui":
		var panel: AdminPanel = get_node_or_null("AdminPanel")
		if panel:
			panel.toggle_gui()
		return
	
	if trimmed.begins_with("g setenv ") or trimmed.begins_with("g env "):
		var env_arg: String = trimmed.split(" ")[-1]
		var env_config = get_node("/root/EnvironmentConfig")
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
		var nm: Node = get_node("/root/NetworkManager")
		if is_instance_valid(nm) and nm.has_method("send_admin_command"):
			var admin_cmd: String = text
			if admin_cmd.begins_with("G "):
				admin_cmd = admin_cmd.trim_prefix("G ")
			elif admin_cmd.begins_with("g "):
				admin_cmd = admin_cmd.trim_prefix("g ")
			nm.send_admin_command(admin_cmd)
		return
	
	# Normal chat: forward to server if connected
	if GameState.connected_to_server:
		var nm: Node = get_node("/root/NetworkManager")
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
	chat_layer.add_system_message("G force AI / G next AI - Force next killer to be AI")
	chat_layer.add_system_message("G gamemode select double trouble - Toggle double trouble")
	chat_layer.add_system_message("G AUTH <pw> - Authenticate as admin")
	chat_layer.add_system_message("G Gui - Toggle admin GUI panel")
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
		bl.char_spacing = 4.0
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
		bl2.font_scale = 2.0
		bl2.char_spacing = 5.0
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
	
	# Create friends panel
	_create_friends_panel()
	
	# Create inventory and shop buttons in the HUD (reverse order = top z-order)
	_create_settings_button()
	_create_inventory_button()
	_create_shop_button()


func _create_friends_panel() -> void:
	"""Create the friends panel and its open/close control."""
	var fp := FriendsPanel.new()
	fp.name = "FriendsPanel"
	fp.friends_panel_closed.connect(_on_friends_closed)
	add_child(fp)
	_friends_panel = fp
	
	# Create friends button in HUD
	var hud: CanvasLayer = $"../HUD"
	var fri_tex: Texture2D = load("res://The Darkness Of The Grasslands assets/UI/Lobby/Friends_Icon.png")
	if fri_tex:
		var btn := TextureButton.new()
		btn.name = "FriendsButton"
		btn.size = friends_button_size
		btn.position = friends_button_pos
		btn.texture_normal = fri_tex
		btn.pressed.connect(_on_friends_button_pressed)
		hud.add_child(btn)
	else:
		var btn := Button.new()
		btn.name = "FriendsButton"
		btn.size = friends_button_size
		btn.position = friends_button_pos
		btn.text = "FRIENDS"
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(_on_friends_button_pressed)
		hud.add_child(btn)


func _on_friends_button_pressed() -> void:
	if dialogue_ui.is_dialogue_active():
		return
	if _friends_panel:
		_friends_panel.open()
		_toggle_hud_buttons(false)


func _on_friends_closed() -> void:
	_toggle_hud_buttons(true)


# ═══════════════ SPECTATE (see who's playing in the ongoing match) ═══════════════

const SPECTATE_ICON: String = "res://The Darkness Of The Grasslands assets/UI/Lobby/Spectate icon.png"
const LMS_MUSIC_PATH: String = "res://The Darkness Of The Grasslands assets/Music/Match/SPECIAL LMSES/Greengrass_VS_Violentgrass_Violent_bells_LMS.wav"

func _setup_spectate() -> void:
	"""Create the Spectate button, its 'who's playing' panel, and the ticking
	match-timer label. Connects to NetworkManager so the panel stays live even
	while sitting in the lobby during an ongoing match."""
	_create_spectate_button()
	_create_spectate_panel()
	_create_spectate_timer_label()
	_update_spectate_visibility()
	_apply_intermission_music()
	
	# Live match data from the server (broadcast to ALL clients, including lobby).
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if is_instance_valid(nm):
		if nm.has_signal("player_list_updated") and not nm.player_list_updated.is_connected(_on_spectate_player_list):
			nm.player_list_updated.connect(_on_spectate_player_list)
		if nm.has_signal("phase_changed") and not nm.phase_changed.is_connected(_on_spectate_phase):
			nm.phase_changed.connect(_on_spectate_phase)
	# If we returned from a match where the LMS finale was playing, carry that
	# LMS track into the lobby (intermission) instead of the normal lobby tune.
	if GameState.returning_from_lms:
		_play_lms_in_lobby()


func _create_spectate_button() -> void:
	var hud: CanvasLayer = $"../HUD"
	if not hud:
		return
	var btn := TextureButton.new()
	btn.name = "SpectateButton"
	btn.size = spectate_button_size
	btn.position = spectate_button_pos
	var icon: Texture2D = load(SPECTATE_ICON)
	if icon:
		btn.texture_normal = icon
	btn.pressed.connect(_on_spectate_button_pressed)
	btn.mouse_entered.connect(func(): _spectate_show_hint(true))
	btn.mouse_exited.connect(func(): _spectate_show_hint(false))
	_spectate_btn = btn
	# Start transparent + unactivatable until a match is begun (or just was).
	_update_spectate_button_state()
	hud.add_child(btn)


func _update_spectate_button_state() -> void:
	"""Gate the Spectate button: transparent + disabled until a match is running
	(or has just ended — the LOBBY_ANALYSIS phase). Only then is it fully opaque
	and clickable. This lets the lobby 'know there's a game going' via the live
	match phase + roster broadcast from the server, backed up by GameState."""
	if not is_instance_valid(_spectate_btn):
		return
	var match_active: bool = (
		_spectate_phase in ["ROUND_ACTIVE", "LAST_MAN_STANDING", "LOBBY_ANALYSIS"]
		or not _spectate_players.is_empty()
		or GameState.match_in_progress
	)
	_spectate_btn.disabled = not match_active
	_spectate_btn.modulate = Color(1, 1, 1, 1.0 if match_active else 0.35)


func _create_spectate_panel() -> void:
	var hud: CanvasLayer = $"../HUD"
	if not hud:
		return
	var panel := Control.new()
	panel.name = "SpectatePanel"
	panel.position = spectate_panel_pos
	panel.size = spectate_panel_size
	hud.add_child(panel)
	_spectate_panel = panel
	
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.size = spectate_panel_size
	bg.color = Color(0.1, 0.1, 0.1, 0.78)
	panel.add_child(bg)
	
	var title := BitmapLabel.new()
	title.name = "Title"
	title.label_text = "SPECTATE"
	title.font_scale = 0.16
	title.char_spacing = 3.0
	title.font_color = Color(1, 0.8, 0.5, 1)
	title.position = Vector2(10, 4)
	title.size = Vector2(240, 28)
	panel.add_child(title)
	
	var sep := ColorRect.new()
	sep.name = "Sep"
	sep.position = Vector2(10, 34)
	sep.size = Vector2(180, 2)
	sep.color = Color(1, 1, 1, 0.3)
	panel.add_child(sep)
	
	# Rows (username + role + alive marker)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.position = Vector2(12, 42)
	rows.size = Vector2(spectate_panel_size.x - 24, spectate_panel_size.y - 56)
	rows.add_theme_constant_override("separation", 4)
	panel.add_child(rows)
	
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Players currently in the match appear here.\n(Requires a connected match.)"
	hint.position = Vector2(12, spectate_panel_size.y - 58)
	hint.size = Vector2(spectate_panel_size.x - 24, 50)
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	panel.add_child(hint)
	
	_update_spectate_rows()


func _create_spectate_timer_label() -> void:
	var hud: CanvasLayer = $"../HUD"
	if not hud:
		return
	var lbl := Label.new()
	lbl.name = "SpectateTimerLabel"
	lbl.text = ""
	lbl.position = Vector2(spectate_panel_pos.x, spectate_panel_pos.y - 30)
	lbl.size = Vector2(spectate_panel_size.x, 26)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1, 1, 0.6, 1))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", 4)
	hud.add_child(lbl)
	_spectate_timer_label = lbl


func _on_spectate_button_pressed() -> void:
	if dialogue_ui.is_dialogue_active():
		return
	# Cannot spectate unless a match is active (or just ended).
	if is_instance_valid(_spectate_btn) and _spectate_btn.disabled:
		return
	_spectate_visible = not _spectate_visible
	_update_spectate_visibility()


func _spectate_show_hint(visible_hint: bool) -> void:
	if not is_instance_valid(_spectate_panel):
		return
	var hint: Label = _spectate_panel.get_node_or_null("Hint")
	if hint:
		hint.visible = visible_hint and not _spectate_visible


func _update_spectate_visibility() -> void:
	if is_instance_valid(_spectate_panel):
		_spectate_panel.visible = _spectate_visible
	if is_instance_valid(_spectate_timer_label):
		_spectate_timer_label.visible = _spectate_visible


func _on_spectate_player_list(players: Array) -> void:
	"""Live update of who's in the match (role + alive) from the server."""
	var normalized: Array[Dictionary] = []
	for p: Variant in players:
		if p is Dictionary:
			normalized.append(p as Dictionary)
	_spectate_players = normalized
	_update_spectate_rows()
	_update_spectate_button_state()


func _on_spectate_phase(phase: String, time_remaining: float) -> void:
	"""Track the live match phase + remaining time for the lobby timer."""
	_spectate_phase = phase
	_spectate_time_remaining = time_remaining
	_spectate_timer_tick = 0.0
	_update_spectate_timer_text()
	_update_spectate_button_state()
	_apply_intermission_music()


func _update_spectate_rows() -> void:
	if not is_instance_valid(_spectate_panel):
		return
	var rows: VBoxContainer = _spectate_panel.get_node_or_null("Rows")
	if not rows:
		return
	for child: Node in rows.get_children():
		child.queue_free()
	
	if _spectate_players.is_empty():
		var empty := Label.new()
		empty.text = "No active match data."
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		rows.add_child(empty)
		return
	
	for p: Dictionary in _spectate_players:
		var uname: String = str(p.get("username", "Unknown"))
		var role: String = str(p.get("role", "survivor"))
		var alive: bool = bool(p.get("alive", true))
		var row := Label.new()
		var role_txt: String = "KILLER" if role == "killer" else "SURVIVOR"
		var alive_txt: String = "" if alive else "  [DEAD]"
		row.text = "%s  (%s)%s" % [uname, role_txt, alive_txt]
		row.add_theme_font_size_override("font_size", 13)
		row.add_theme_color_override("font_color", Color(1, 0.7, 0.4, 1) if role == "killer" else Color(0.7, 1, 0.7, 1))
		if not alive:
			row.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		rows.add_child(row)


func _update_spectate_timer_text() -> void:
	if not is_instance_valid(_spectate_timer_label):
		return
	var in_match: bool = _spectate_phase == "ROUND_ACTIVE" or _spectate_phase == "LAST_MAN_STANDING"
	if not in_match:
		_spectate_timer_label.text = "Match: not in progress"
		return
	var secs: int = maxi(0, ceili(_spectate_time_remaining))
	var mm: int = int(secs / 60.0)
	var ss: int = secs % 60
	var phase_txt: String = "LAST MAN STANDING" if _spectate_phase == "LAST_MAN_STANDING" else "ROUND ACTIVE"
	_spectate_timer_label.text = "%s  —  %02d:%02d" % [phase_txt, mm, ss]


# ── Intermission music: lobby music yields to any match music ──────────────

func _apply_intermission_music() -> void:
	"""The lobby is the intermission. When a match (round or LMS) is active, its
	music is the score — so mute the lobby music. It returns on a real
	intermission (no active phase / LOBBY_ANALYSIS)."""
	var in_match: bool = _spectate_phase == "ROUND_ACTIVE" or _spectate_phase == "LAST_MAN_STANDING"
	if not is_instance_valid(lobby_music):
		return
	if in_match or GameState.returning_from_lms:
		# Any match music is "coming" — mute the intermission tune.
		if lobby_music.volume_db > -60.0:
			lobby_music.volume_db = -80.0
	else:
		if lobby_music.volume_db < -60.0:
			lobby_music.volume_db = 0.0


func _play_lms_in_lobby() -> void:
	"""When returning from an LMS finale, play the LMS track in the lobby
	(instead of the normal lobby tune) — it's the intermission carry-over."""
	if not ResourceLoader.exists(LMS_MUSIC_PATH):
		return
	var stream: AudioStream = load(LMS_MUSIC_PATH)
	if not stream:
		return
	if is_instance_valid(lobby_music):
		lobby_music.stop()
		lobby_music.volume_db = 0.0
	lobby_music.stream = stream
	lobby_music.play()
	# Clear the carry-over flag so a later intermission uses the normal tune.
	GameState.returning_from_lms = false


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
	return (_shop_layer and _shop_layer.visible) or (_inventory_layer and _inventory_layer.visible) or (_settings_layer and _settings_layer.visible) or (_friends_panel and _friends_panel.visible)


func _toggle_hud_buttons(show_buttons: bool) -> void:
	var hud: CanvasLayer = $"../HUD"
	var shop_btn: Node = hud.get_node_or_null("ShopButton")
	var inv_btn: Node = hud.get_node_or_null("InventoryButton")
	var set_btn: Node = hud.get_node_or_null("SettingsButton")
	var fri_btn: Node = hud.get_node_or_null("FriendsButton")
	if shop_btn:
		shop_btn.visible = show_buttons
	if inv_btn:
		inv_btn.visible = show_buttons
	if set_btn:
		set_btn.visible = show_buttons
	if fri_btn:
		fri_btn.visible = show_buttons


# ---------- ROLE TOGGLE REMOVED (server assigns roles) ----------


func _on_lobby_countdown_finished() -> void:
	# Autosave player progress before game starts
	if not GameState.logged_in_username.is_empty():
		var sm := get_node_or_null("/root/SaveManager")
		if is_instance_valid(sm) and sm.has_method("autosave"):
			sm.autosave(GameState.logged_in_username)
	# Transition directly to TEST game map (uses role toggle state)
	get_tree().change_scene_to_file("res://scenes/game_map_test.tscn")


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
		_bitmap_comeback.font_scale = 0.5 + randi() % 5 * 0.05
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
		_bitmap_comeback.font_scale = 0.5
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
	# Tick the spectate match-timer between server phase updates so it stays live.
	if _spectate_visible and _spectate_phase in ["ROUND_ACTIVE", "LAST_MAN_STANDING"]:
		_spectate_timer_tick += delta
		if _spectate_timer_tick >= 1.0:
			_spectate_timer_tick -= 1.0
			_spectate_time_remaining = maxf(0.0, _spectate_time_remaining - 1.0)
			_update_spectate_timer_text()

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
			# Check if current player is Orange Guy (case-insensitive)
			var am_node := get_node("/root/AuthManager")
			var player_name: String = am_node.current_username if is_instance_valid(am_node) else ""
			var is_orange_guy: bool = player_name.to_lower() == "orange guy"
			if is_orange_guy:
				dialogue_ui.start_dialogue_with(evil_potato_orange_dialogue)
			elif _potato_dialogue_done:
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
	
	# Check if all hub questions are exhausted.
	# IMPORTANT: check the BROWNGRASS dialogue specifically, NOT dialogue_ui._dl
	# (which points to whatever dialogue was last played). Checking the wrong
	# resource made Browngrass appear "finished" after any other dialogue (e.g.
	# Evil Potato) because that dialogue has no line-8 choices.
	var all_exhausted: bool = dialogue_ui.is_all_questions_exhausted_in(browngrass_dialogue, 8)
	
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


## Get the special tag color for a reserved username. Returns white for normal players.
func _get_display_name(pname: String) -> String:
	"""Get the display name for a player. Returns the username if no display name is set."""
	# Local player
	if pname == "You" or pname == GameState.logged_in_username:
		if not GameState.display_name.is_empty():
			return GameState.display_name
		return pname if pname != "You" else GameState.logged_in_username
	# For other players, we use the username for now (server doesn't sync display names yet)
	return pname


func _get_avatar_texture(pname: String) -> Texture2D:
	"""Get the avatar texture for a player. Returns null if no custom avatar."""
	# Check if this is the local player
	var avatar_type: String = ""
	if pname == "You" or pname == GameState.logged_in_username:
		avatar_type = GameState.avatar_type
	else:
		# For other players, we don't have their avatar info (server not synced)
		return null
	
	if avatar_type.is_empty() or avatar_type == "Lobby Person":
		return null
	
	# Handle custom uploaded avatar
	if avatar_type == "custom":
		var safe_name: String = pname.replace(" ", "_").replace(".", "_").replace("/", "_")
		var custom_path: String = "user://avatars/" + safe_name + "_custom.png"
		if ResourceLoader.exists(custom_path):
			return load(custom_path)
		return null
	
	# Check for built-in avatar
	var builtin_path: String = "res://assets/avatars/" + avatar_type + ".png"
	if ResourceLoader.exists(builtin_path):
		return load(builtin_path)
	
	return null


func _get_username_tag_color(uname: String) -> Color:
	var lower: String = uname.to_lower()
	match lower:
		"orange guy":
			return Color(1.0, 0.55, 0.0, 1)  # Orange
		"juangoat":
			return Color(1.0, 0.5, 0.3, 1)  # Coral mixed with orange
		"charon":
			return Color(0.3, 0.0, 0.5, 1)  # Dark purple (co-owner)
		"theactualdummy":
			return Color(0.2, 0.8, 0.1, 1)  # Green (moderator)
		_:
			return Color(1, 1, 1, 1)  # Default white


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
	var am = get_node("/root/AuthManager")
	if is_instance_valid(am):
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
		var display_pname: String = _get_display_name(pname)
		entry.text = "  " + display_pname
		# Add avatar icon if available
		var avatar_tex: Texture2D = _get_avatar_texture(pname)
		if avatar_tex:
			entry.icon = avatar_tex
			entry.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Add ring icon + count as child
		var ring_hbox := HBoxContainer.new()
		ring_hbox.name = "RingHBox"
		ring_hbox.position = Vector2(entry.size.x - 80, 3)
		ring_hbox.size = Vector2(80, 18)
		var ring_icon := TextureRect.new()
		ring_icon.name = "RingIcon"
		var ring_tex: Texture2D = load("res://The Darkness Of The Grasslands assets/UI/Lobby/Rings icon.png")
		if ring_tex:
			ring_icon.texture = ring_tex
			ring_icon.size = Vector2(16, 16)
			ring_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		var ring_label := Label.new()
		ring_label.name = "RingCount"
		ring_label.text = str(rings)
		ring_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4, 1))
		ring_label.add_theme_font_size_override("font_size", 12)
		ring_hbox.add_child(ring_icon)
		ring_hbox.add_child(ring_label)
		entry.add_child(ring_hbox)
		# Apply tag color for reserved usernames
		var tag: Color = _get_username_tag_color(pname)
		if pname.to_lower() == "prograss":
			# Oreo style: black text on white shadow
			entry.add_theme_color_override("font_color", Color(0, 0, 0, 1) if not is_self else Color(0.2, 0.2, 0.2, 1))
			entry.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 1))
		elif tag != Color(1, 1, 1, 1):
			entry.add_theme_color_override("font_color", tag)
			var pname_lower: String = pname.to_lower()
			if pname_lower == "charon":
				# Purple outline with light purple shadow (spacy)
				entry.add_theme_color_override("font_shadow_color", Color(0.8, 0.5, 1.0, 1))
				entry.add_theme_constant_override("shadow_offset_x", 2)
				entry.add_theme_constant_override("shadow_offset_y", 2)
			elif pname_lower == "theactualdummy":
				# Green font with bold black shadow (green mixed with black)
				entry.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
				entry.add_theme_constant_override("shadow_offset_x", 2)
				entry.add_theme_constant_override("shadow_offset_y", 2)
			else:
				entry.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		elif is_self:
			entry.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6, 1))
			entry.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		else:
			entry.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			entry.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		entry.add_theme_font_size_override("font_size", 13)
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
	popup.size = Vector2(200, 200)
	hud.add_child(popup)
	_info_popup = popup
	
	# Background
	var bg := ColorRect.new()
	bg.size = Vector2(200, 200)
	bg.color = Color(0.05, 0.05, 0.05, 0.85)
	popup.add_child(bg)
	
	# Title — show display name if available, with actual username below
	var display_pname: String = _get_display_name(player_name)
	var title := Label.new()
	title.text = "  " + display_pname
	title.position = Vector2(8, 8)
	title.size = Vector2(200, 24)
	title.add_theme_color_override("font_color", Color(1, 1, 0.7, 1))
	title.add_theme_font_size_override("font_size", 16)
	popup.add_child(title)
	
	# Show actual username below display name if they differ
	if display_pname != player_name:
		var uname_label := Label.new()
		uname_label.text = "  @" + player_name
		uname_label.position = Vector2(8, 28)
		uname_label.size = Vector2(200, 16)
		uname_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		uname_label.add_theme_font_size_override("font_size", 11)
		popup.add_child(uname_label)
	
	# Stats
	var stats: Array[String] = [
		"Rings: %d" % GameState.get_player_rings(player_name),
		"Rounds Played: %d" % GameState.get_player_rounds(player_name),
		"Killer: Violentgrass",
		"Survivor: Greengrass",
		"Wins (Killer): --",
		"Wins (Survivor): --",
	]
	
	var y_offset: float = 50.0
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
