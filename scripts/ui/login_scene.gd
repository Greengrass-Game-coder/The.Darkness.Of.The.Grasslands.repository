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

func _ready() -> void:
	title_label.text = title_text
	subtitle_label.text = subtitle_text
	loading_indicator.hide()
	status_label.text = ""
	
	# Pre-fill username from Steam if detected
	_detect_steam_and_prefill()
	
	# If already logged in (e.g. returning from match), skip login
	var am = Engine.get_singleton("AuthManager")
	if is_instance_valid(am) and am.is_logged_in():
		status_label.text = "Welcome back, %s!" % am.current_username
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
		loading_indicator.show()
		# Connect to server if not already
		var nm = Engine.get_singleton("NetworkManager")
		if is_instance_valid(nm) and not nm.connected:
			nm.connect_to_server()
		# Small delay then go to queue screen
		await get_tree().create_timer(0.6).timeout
		_on_login_successful()
		return
	
	# Focus username field
	username_input.grab_focus()
	
	# Connect signals
	login_button.pressed.connect(_on_login_pressed)
	password_input.text_submitted.connect(_on_password_submitted)
	var am2 = Engine.get_singleton("AuthManager")
	if is_instance_valid(am2):
		am2.login_succeeded.connect(_on_auth_succeeded)
		am2.login_failed.connect(_on_auth_failed)


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
	
	status_label.text = "Connecting..."
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	login_button.disabled = true
	
	var am3 = Engine.get_singleton("AuthManager")
	if is_instance_valid(am3) and am3.has_method("login"):
		am3.login(username, password)


func _on_auth_succeeded(username: String, _is_admin: bool) -> void:
	status_label.text = "Welcome, %s!" % username
	status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
	
	# Show loading indicator briefly
	loading_indicator.show()
	
	# Connect to server
	var nm2 = Engine.get_singleton("NetworkManager")
	if is_instance_valid(nm2) and nm2.has_method("connect_to_server"):
		nm2.connect_to_server()
	
	# Small delay then transition
	await get_tree().create_timer(0.8).timeout
	
	_on_login_successful()


func _on_auth_failed(reason: String) -> void:
	status_label.text = reason
	status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
	login_button.disabled = false
	loading_indicator.hide()


func _on_login_successful() -> void:
	login_completed.emit()
	
	# Transition to queue screen (matchmaking)
	var err: int = get_tree().change_scene_to_file("res://scenes/queue_screen.tscn")
	if err != OK:
		push_error("LoginScene: Failed to load queue screen!")
		# Fallback to lobby
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
