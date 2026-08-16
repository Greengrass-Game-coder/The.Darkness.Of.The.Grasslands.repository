extends Control

## Start Menu — shown after login. Offers Find a Game, Settings, Account Settings.
## Acts as a hub between login and the lobby.

const SETTINGS_LAYER_SCENE: String = "res://scenes/settings_layer.tscn"
const AVATAR_DIR: String = "res://assets/avatars/"

var _settings_layer: Node = null
var _avatar_buttons: Array[Button] = []
var _selected_avatar: String = ""
var _custom_avatar_path: String = ""

# Pre-defined avatar file names (without extension)
const BUILTIN_AVATARS: Array[String] = [
	"avatar_default",
	"avatar_red",
	"avatar_blue",
	"avatar_yellow",
	"avatar_purple",
	"avatar_orange",
]


func _ready() -> void:
	_setup_buttons()
	_setup_account_panel()
	_load_current_settings()


func _setup_buttons() -> void:
	"""Connect menu button signals."""
	var buttons: VBoxContainer = $MenuButtons if has_node("MenuButtons") else null
	if not buttons:
		return
	var find_btn: Button = buttons.get_node("FindGameBtn") as Button
	var host_btn: Button = buttons.get_node("HostGameBtn") as Button
	var settings_btn: Button = buttons.get_node("SettingsBtn") as Button
	var account_btn: Button = buttons.get_node("AccountSettingsBtn") as Button
	var logout_btn: Button = buttons.get_node("LogoutBtn") as Button
	
	if find_btn:
		find_btn.pressed.connect(_on_find_game_pressed)
	if host_btn:
		host_btn.pressed.connect(_on_host_game_pressed)
	if settings_btn:
		settings_btn.pressed.connect(_on_settings_pressed)
	if account_btn:
		account_btn.pressed.connect(_on_account_settings_pressed)
	if logout_btn:
		logout_btn.pressed.connect(_on_logout_pressed)


func _setup_account_panel() -> void:
	"""Setup the account settings sub-panel."""
	var close_btn: Button = %AccountPanel/CloseBtn
	close_btn.pressed.connect(_on_account_panel_close)
	
	var save_name_btn: Button = %AccountPanel/DisplayNameSection/SaveNameBtn
	save_name_btn.pressed.connect(_on_save_display_name)
	
	# Build avatar grid
	_build_avatar_grid()
	
	# Update username display
	var username_label: Label = %AccountPanel/UsernameDisplay
	var gs = get_node_or_null("/root/GameState")
	if gs:
		username_label.text = "Logged in as: " + gs.logged_in_username


func _load_current_settings() -> void:
	"""Load current display name and avatar settings."""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return
	
	# Load display name
	var name_input: LineEdit = %AccountPanel/DisplayNameSection/NameInput
	if "display_name" in gs:
		name_input.text = gs.display_name
	
	# Load avatar
	if "avatar_type" in gs and gs.avatar_type != "Lobby Person":
		_selected_avatar = gs.avatar_type
		_highlight_selected_avatar()


func _build_avatar_grid() -> void:
	"""Fill the avatar grid with pre-defined avatar buttons."""
	var grid: GridContainer = %AccountPanel/AvatarSection/AvatarGrid
	_avatar_buttons.clear()
	
	for avatar_name: String in BUILTIN_AVATARS:
		var btn := Button.new()
		btn.name = "AvatarBtn_" + avatar_name
		btn.custom_minimum_size = Vector2(64, 64)
		btn.size = Vector2(64, 64)
		btn.toggle_mode = true
		
		# Try to load the avatar texture
		var tex_path: String = AVATAR_DIR + avatar_name + ".png"
		if ResourceLoader.exists(tex_path):
			var tex: Texture2D = load(tex_path)
			if tex:
				btn.icon = tex
				btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		
		btn.pressed.connect(_on_avatar_selected.bind(avatar_name))
		grid.add_child(btn)
		_avatar_buttons.append(btn)
	
	# Add "custom upload" button
	var upload_btn := Button.new()
	upload_btn.name = "AvatarBtn_Upload"
	upload_btn.custom_minimum_size = Vector2(64, 64)
	upload_btn.size = Vector2(64, 64)
	upload_btn.text = "UPLOAD"
	upload_btn.add_theme_font_size_override("font_size", 10)
	upload_btn.pressed.connect(_on_upload_avatar)
	grid.add_child(upload_btn)
	_avatar_buttons.append(upload_btn)


func _highlight_selected_avatar() -> void:
	"""Highlight the currently selected avatar button."""
	for btn: Button in _avatar_buttons:
		if btn is Button and btn.name == "AvatarBtn_" + _selected_avatar:
			btn.button_pressed = true
			btn.modulate = Color(1, 1, 1, 1)
		else:
			btn.button_pressed = false
			btn.modulate = Color(0.6, 0.6, 0.6, 1)


func _on_avatar_selected(avatar_name: String) -> void:
	"""Handle clicking a pre-defined avatar."""
	_selected_avatar = avatar_name
	_custom_avatar_path = ""
	_highlight_selected_avatar()
	
	# Save immediately
	_save_avatar_setting(avatar_name)
	
	var status: Label = %AccountPanel/AvatarSection/AvatarStatus
	status.text = "Avatar set to: " + avatar_name
	status.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7, 1))


func _on_upload_avatar() -> void:
	"""Open file dialog to upload a custom PNG avatar."""
	var file_dialog := FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.add_filter("*.png", "PNG Images")
	file_dialog.title = "Select Profile Picture (max 64x64)"
	file_dialog.file_selected.connect(_on_avatar_file_selected)
	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))


func _on_avatar_file_selected(file_path: String) -> void:
	"""Handle a custom PNG file being selected for avatar."""
	var status: Label = %AccountPanel/AvatarSection/AvatarStatus
	# Load the image
	var img := Image.new()
	var err: int = img.load(file_path)
	if err != OK:
		status.text = "Error: Could not load image."
		status.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
		return
	
	# Resize to max 64x64
	if img.get_width() > 64 or img.get_height() > 64:
		img.resize(64, 64, Image.INTERPOLATE_LANCZOS)
	
	# Save to user data directory
	var save_path: String = "user://avatars/" + _get_safe_username() + "_custom.png"
	var dir := DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("user://avatars"):
			dir.make_dir("user://avatars")
	
	var save_err: int = img.save_png(save_path)
	if save_err != OK:
		status.text = "Error: Could not save avatar."
		status.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
		return
	
	_custom_avatar_path = save_path
	_selected_avatar = "custom"
	
	# Update the upload button icon to show the selected image
	var tex := ImageTexture.create_from_image(img)
	for btn: Button in _avatar_buttons:
		if btn.name == "AvatarBtn_Upload":
			btn.icon = tex
			btn.text = ""
			btn.button_pressed = true
		else:
			btn.button_pressed = false
			btn.modulate = Color(0.6, 0.6, 0.6, 1)
	
	_save_avatar_setting("custom")
	
	status.text = "Custom avatar uploaded!"
	status.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7, 1))


func _on_save_display_name() -> void:
	"""Save the display name to GameState and SaveManager."""
	var name_input: LineEdit = %AccountPanel/DisplayNameSection/NameInput
	var new_name: String = name_input.text.strip_edges()
	var status: Label = %AccountPanel/DisplayNameSection/NameStatus
	var gs = get_node_or_null("/root/GameState")
	
	if not gs:
		status.text = "Error: GameState not available."
		status.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
		return
	
	# Validate: no empty names (means use username)
	if new_name.is_empty():
		gs.display_name = ""
		status.text = "Display name cleared. Will use your username."
		status.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	else:
		# Basic validation: no special characters that could break chat
		var valid: bool = true
		for c: String in new_name:
			if c in ["[", "]", "***", "@"]:
				valid = false
				break
		if not valid:
			status.text = "Invalid characters: [ ] *** @ are not allowed."
			status.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
			return
		gs.display_name = new_name
		status.text = "Display name saved: " + new_name
		status.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7, 1))
	
	# Save to persistent storage
	var sm = get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("autosave") and gs and "logged_in_username" in gs and not gs.logged_in_username.is_empty():
		sm.autosave(gs.logged_in_username)


func _save_avatar_setting(avatar_type: String) -> void:
	"""Save the avatar selection to GameState and SaveManager."""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return
	
	gs.avatar_type = avatar_type
	
	var sm = get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("autosave") and gs and "logged_in_username" in gs and not gs.logged_in_username.is_empty():
		sm.autosave(gs.logged_in_username)


func _get_safe_username() -> String:
	"""Get a filesystem-safe version of the current username."""
	var gs = get_node_or_null("/root/GameState")
	if not gs or gs.logged_in_username.is_empty():
		return "unknown"
	# Replace any characters that are problematic in filenames
	var safe: String = gs.logged_in_username.replace(" ", "_").replace(".", "_").replace("/", "_")
	return safe


func _on_find_game_pressed() -> void:
	"""Transition to the lobby via the loading screen, which pre-loads the game
	map in the background so the match starts instantly. If the game map is
	already pre-loaded (cached), the loading screen skips itself automatically."""
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")


func _on_host_game_pressed() -> void:
	"""Open the P2P host/join lobby (self-hosted public/private servers)."""
	get_tree().change_scene_to_file("res://scenes/p2p/p2p_lobby.tscn")


func _on_settings_pressed() -> void:
	"""Open the settings layer."""
	if not _settings_layer:
		var set_scene: PackedScene = load(SETTINGS_LAYER_SCENE) as PackedScene
		if not set_scene:
			push_error("StartMenu: Could not load settings layer scene")
			return
		_settings_layer = set_scene.instantiate()
		add_child(_settings_layer)
		_settings_layer.hide()
	
	_settings_layer.open()


func _on_account_settings_pressed() -> void:
	"""Show the account settings panel."""
	var panel: Control = %AccountPanel
	panel.visible = true


func _on_account_panel_close() -> void:
	"""Hide the account settings panel."""
	var panel: Control = %AccountPanel
	panel.visible = false
	# Reload settings in case they were changed
	_load_current_settings()


func _on_logout_pressed() -> void:
	"""Log out and return to login screen."""
	var am = get_node_or_null("/root/AuthManager")
	if am and am.has_method("logout"):
		am.logout()
	get_tree().change_scene_to_file("res://scenes/login.tscn")


func _input(event: InputEvent) -> void:
	"""Handle ESC to close account panel or settings."""
	if event.is_action_pressed("ui_cancel"):
		var panel: Control = %AccountPanel
		if panel.visible:
			panel.visible = false
			get_viewport().set_input_as_handled()
		elif _settings_layer and _settings_layer.visible:
			_settings_layer.close()
			get_viewport().set_input_as_handled()
