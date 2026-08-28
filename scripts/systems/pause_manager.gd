extends Node
## PauseManager — a global, controller-friendly pause menu.
##
## The Pause action (keyboard Esc / gamepad Start) opens:
##   • In normal gameplay scenes: a Pause menu with Resume / Settings / Quit.
##   • While the arcade console UI is on-screen: opens Settings directly (the
##     console pause), because Esc in the console already means cancel/back.
## Settings are opened from the existing SettingsLayer, and everything is
## navigable with a gamepad (D-pad/stick + A to select, B to go back) because
## the gamepad is bound to Godot's built-in ui_* actions.

const SETTINGS_SCENE := "res://scenes/settings_layer.tscn"
const START_MENU_SCENE := "res://scenes/start_menu.tscn"
const SERVER_PANEL_SCENE := "res://scenes/server_panel.tscn"

# Pure menu scenes handle their own Esc/cancel, so the global pause ignores them.
const MENU_SCENE_FILES: Array[String] = ["login.tscn", "start_menu.tscn"]

var _paused: bool = false
var _overlay: Control = null
var _settings: Node = null
var _server_panel: Control = null
var _pause_scene: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# If gameplay timers keep running while paused (multiplayer integrity) and one
# of them ends the match (which changes scene) while the pause menu is open,
# make sure we don't leave the next scene stuck paused with the overlay up.
func _process(_delta: float) -> void:
	if _paused and not is_instance_valid(_pause_scene):
		# The scene we paused in is gone (a scene change happened while paused).
		_resume()
		return
	if _paused and is_instance_valid(_pause_scene) and get_tree().current_scene != _pause_scene:
		_resume()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _is_menu_scene():
		return
	var console: bool = _console_ui_active()
	if console:
		# In the console only the gamepad Start button opens Settings; the
		# keyboard Esc keeps meaning cancel/back (handled by the console).
		if event is InputEventJoypadButton:
			_open_settings()
			get_viewport().set_input_as_handled()
		return
	toggle_pause()
	get_viewport().set_input_as_handled()


func _is_menu_scene() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return true
	var file: String = scene.scene_file_path.get_file()
	return file in MENU_SCENE_FILES


func _console_ui_active() -> bool:
	var scene := get_tree().current_scene
	if scene and scene.has_method("console_ui_active"):
		return scene.console_ui_active()
	return false


func toggle_pause() -> void:
	if _paused:
		_resume()
	else:
		_pause()


func _pause() -> void:
	if _paused:
		return
	_paused = true
	_pause_scene = get_tree().current_scene
	_build_overlay()
	get_tree().paused = true


func _resume() -> void:
	get_tree().paused = false
	_paused = false
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	if _settings:
		_settings.queue_free()
		_settings = null
	if _server_panel:
		_server_panel.queue_free()
		_server_panel = null


## Public: unpause if we're currently paused. Used e.g. by the server panel's
## "Restart Round" so the reload doesn't start a fresh match while still paused.
func resume() -> void:
	if _paused:
		_resume()


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)

	var title := Label.new()
	title.text = "PAUSED"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position.y = 120
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(400, 60)
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_overlay.add_child(title)

	var menu := VBoxContainer.new()
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 16)
	_overlay.add_child(menu)

	_add_menu_button(menu, "Resume", _resume)
	_add_menu_button(menu, "Settings", _open_settings)
	if _can_use_server_panel():
		_add_menu_button(menu, "Server Panel", _open_server_panel)
	_add_menu_button(menu, "Quit to Main Menu", _quit_to_menu)

	# Focus the first button so a gamepad can navigate the menu immediately.
	var first := menu.get_child(0) as Button
	if first:
		first.grab_focus()


func _add_menu_button(menu: VBoxContainer, text: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(320, 48)
	btn.add_theme_font_size_override("font_size", 24)
	btn.pressed.connect(cb)
	menu.add_child(btn)


func _open_settings() -> void:
	if _settings == null:
		var packed: PackedScene = load(SETTINGS_SCENE)
		_settings = packed.instantiate()
		_settings.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child(_settings)
	_settings.open()


## The private server panel is always available to a solo local player.
func _can_use_server_panel() -> bool:
	return true


func _open_server_panel() -> void:
	if _server_panel == null:
		var packed: PackedScene = load(SERVER_PANEL_SCENE)
		_server_panel = packed.instantiate()
		_server_panel.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child(_server_panel)


func _quit_to_menu() -> void:
	_resume()
	get_tree().change_scene_to_file(START_MENU_SCENE)
