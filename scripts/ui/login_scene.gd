class_name LoginScene
extends Control

## Dedicated login screen shown before the lobby.
## Handles username/password auth, admin detection,
## and transitions to lobby or queue on success.

signal login_completed()

@export var title_text: String = "THE DARKNESS OF THE GRASSLANDS"
@export var subtitle_text: String = "Enter the darkness..."

@onready var title_label: Label = $TitleLabel
@onready var subtitle_label: Label = $SubtitleLabel
@onready var username_input: LineEdit = $CenterPanel/VBoxContainer/UsernameInput
@onready var password_input: LineEdit = $CenterPanel/VBoxContainer/PasswordInput
@onready var login_button: Button = $CenterPanel/VBoxContainer/LoginButton
@onready var status_label: Label = $CenterPanel/VBoxContainer/StatusLabel
@onready var loading_indicator: ColorRect = $LoadingIndicator
@onready var server_url_input: LineEdit = $CenterPanel/VBoxContainer/ServerURLInput

const SERVER_URL_FILE: String = "user://server_url.cfg"

func _ready() -> void:
	title_label.text = title_text
	subtitle_label.text = subtitle_text
	loading_indicator.hide()
	status_label.text = ""
	
	# Load saved server URL
	_load_server_url()
	
	# Connect to NetworkManager auth signals
	var nm := get_node("/root/NetworkManager")
	if is_instance_valid(nm):
		if nm.has_signal("auth_result") and not nm.auth_result.is_connected(_on_auth_result):
			nm.auth_result.connect(_on_auth_result)
	
	# Pre-fill username from Steam if detected
	_detect_steam_and_prefill()
	
	# If already logged in (e.g. returning from match), skip login
	var am = get_node("/root/AuthManager")
	if is_instance_valid(am) and am.is_logged_in():
		status_label.text = "Welcome back, %s!" % am.current_username
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
		loading_indicator.show()
		# Connect to server
		if is_instance_valid(nm) and not nm.connected:
			nm.connect_to_server()
		await get_tree().create_timer(0.6).timeout
		_on_login_successful()
		return
	
	# Focus username field
	username_input.grab_focus()
	
	# Connect signals
	login_button.pressed.connect(_on_login_pressed)
	password_input.text_submitted.connect(_on_password_submitted)


func _load_server_url() -> void:
	"""Load the last-used server URL from disk."""
	var f := FileAccess.open(SERVER_URL_FILE, FileAccess.READ)
	if f:
		var url: String = f.get_as_text().strip_edges()
		if not url.is_empty():
			server_url_input.text = url
		f.close()
	# Otherwise, show the default from EnvironmentConfig
	if server_url_input.text.is_empty():
		var env := get_node_or_null("/root/EnvironmentConfig")
		if env and env.has_method("get_ws_url"):
			server_url_input.text = env.get_ws_url()


func _save_server_url() -> void:
	"""Save the server URL to disk so it persists."""
	var url: String = server_url_input.text.strip_edges()
	if url.is_empty():
		return
	var f := FileAccess.open(SERVER_URL_FILE, FileAccess.WRITE)
	if f:
		f.store_string(url)
		f.close()


func _detect_steam_and_prefill() -> void:
	"""If Steam is running (detected via environment variable), pre-fill the username field."""
	# Steam sets these env vars when launching a game through the client
	var steam_detected: bool = OS.has_environment("SteamAppId") or OS.has_environment("SteamUser")
	var steam_username: String = ""
	
	if steam_detected:
		steam_username = OS.get_environment("SteamUser")
	
	# Also check common OS username as a fallback
	if steam_username.is_empty():
		steam_username = OS.get_environment("USERNAME")
		if steam_username.is_empty():
			steam_username = OS.get_environment("USER")
	
	if not steam_username.is_empty():
		username_input.text = steam_username
		status_label.text = "Detected user: %s" % steam_username
		status_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 1))
		# Focus password field since username is filled
		password_input.grab_focus()


func _on_login_pressed() -> void:
	_attempt_login()


func _on_password_submitted(_text: String) -> void:
	_attempt_login()


func _attempt_login() -> void:
	var username: String = username_input.text.strip_edges()
	var password: String = password_input.text.strip_edges()
	
	if username.is_empty() or password.is_empty():
		status_label.text = "Please enter username and password."
		status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
		return
	
	# Save the server URL before connecting (if user changed it)
	_save_server_url()
	
	status_label.text = "Connecting to server..."
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	login_button.disabled = true
	loading_indicator.show()
	
	# Connect to server first if not connected
	var nm3 = get_node("/root/NetworkManager")
	if is_instance_valid(nm3):
		# Apply custom server URL if entered
		nm3.apply_custom_url(server_url_input.text.strip_edges())
		
		if not nm3.connected:
			nm3.connect_to_server()
			# Wait briefly for connection
			await get_tree().create_timer(0.5).timeout
		
		if not nm3.connected:
			status_label.text = "Could not reach server. Using offline mode."
			status_label.add_theme_color_override("font_color", Color(1, 0.7, 0, 1))
			# Fall back to local auth
			var am4 = get_node("/root/AuthManager")
			if is_instance_valid(am4) and am4.has_method("login"):
				am4.login(username, password)
			return
		
		# Send login to server
		nm3.login(username, password)
		# Wait for auth result
		var result: Array = await nm3.auth_result
		_on_auth_result(result[0], result[1], result[2])
	else:
		# No NetworkManager — local auth only
		var am4 = get_node("/root/AuthManager")
		if is_instance_valid(am4) and am4.has_method("login"):
			am4.login(username, password)


func _on_auth_result(success: bool, username: String, error_msg: String) -> void:
	if success:
		status_label.text = "Welcome, %s!" % username
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
		
		# Set auth state locally
		var am5 = get_node("/root/AuthManager")
		if is_instance_valid(am5) and am5.has_method("set_logged_in"):
			am5.set_logged_in(username, false)
		
		# Load saved data
		var sm := get_node_or_null("/root/SaveManager")
		if is_instance_valid(sm) and sm.has_method("autoload"):
			sm.autoload(username)
		
		# Small delay then transition
		await get_tree().create_timer(0.8).timeout
		_on_login_successful()
	else:
		status_label.text = error_msg
		status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
		login_button.disabled = false
		loading_indicator.hide()


func _on_auth_failed(reason: String) -> void:
	# Kept for backward compatibility with local auth fallback
	status_label.text = reason
	status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
	login_button.disabled = false
	loading_indicator.hide()


func _on_login_successful() -> void:
	login_completed.emit()
	
	# Transition directly to lobby (EOS handles lobby creation)
	var err: int = get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	if err != OK:
		push_error("LoginScene: Failed to load lobby!")
