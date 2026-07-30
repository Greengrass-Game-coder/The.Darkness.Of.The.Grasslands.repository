class_name SettingsLayer
extends Control

signal settings_closed()

@onready var _ui_layer: CanvasLayer = $UILayer
@onready var panel: Control = $UILayer/Panel
@onready var close_button: Button = $UILayer/Panel/CloseButton
@onready var sections_container: VBoxContainer = $UILayer/Panel/ScrollContainer/SectionsContainer

const BACKGROUND_TEXTURE: String = "res://The Darkness Of The Grasslands assets/UI/Lobby/Shop and inventory background UI.png"
const KEYBINDS_FILE: String = "user://keybinds.cfg"

# All rebindable actions with their display labels and default keycodes
const KEYBINDABLE_ACTIONS: Array[Dictionary] = [
	{"action": "move_left",  "label": "Move Left",  "default": KEY_A},
	{"action": "move_right", "label": "Move Right", "default": KEY_D},
	{"action": "move_up",    "label": "Move Up",    "default": KEY_W},
	{"action": "move_down",  "label": "Move Down",  "default": KEY_S},
	{"action": "sprint",     "label": "Sprint",     "default": KEY_SHIFT},
	{"action": "ability_1",  "label": "Ability 1 (Block)",   "default": KEY_Q},
	{"action": "ability_2",  "label": "Ability 2 (Punch)",   "default": KEY_E},
	{"action": "ability_3",  "label": "Ability 3 (Flower)",  "default": KEY_R},
	{"action": "ability_4",  "label": "Ability 4",           "default": KEY_T},
]

var _rebinding_action: String = ""  # Action currently waiting for a keypress
var _rebinding_button: Button = null  # The button that was clicked to start rebinding
var _rebind_labels: Dictionary = {}  # Maps action_name -> Button for updating display

# Section definitions: title, items.
# Supported item types:
#   String label       → plain text label
#   {"type":"toggle", "label","var","default"} → CheckBox bound to GameState
#   {"type":"slider", "label","bus"} → HSlider bound to AudioServer bus volume
#   {"type":"action", "label","action_name"} → CheckBox that triggers a function
#   {"type":"keybind", "label","action"}     → Rebiddable keybinding button
const SECTIONS: Array[Dictionary] = [
	{
		"title": "KEYBINDING",
		"items": [
			{"type": "keybind", "label": "Move Left", "action": "move_left"},
			{"type": "keybind", "label": "Move Right", "action": "move_right"},
			{"type": "keybind", "label": "Move Up", "action": "move_up"},
			{"type": "keybind", "label": "Move Down", "action": "move_down"},
			{"type": "keybind", "label": "Sprint", "action": "sprint"},
			{"type": "keybind", "label": "Ability 1 (Block)", "action": "ability_1"},
			{"type": "keybind", "label": "Ability 2 (Punch)", "action": "ability_2"},
			{"type": "keybind", "label": "Ability 3 (Flower)", "action": "ability_3"},
			{"type": "keybind", "label": "Ability 4", "action": "ability_4"},
		]
	},
	{
		"title": "GAMEPLAY",
		"items": [
			{"label": "Hide Leaderboard", "type": "toggle", "var": "hide_leaderboard", "default": false},
		]
	},
	{
		"title": "AUDIO",
		"items": [
			{"label": "Master Volume", "type": "slider", "bus": "Master"},
			{"label": "Music Volume", "type": "slider", "bus": "Music"},
			{"label": "SFX Volume", "type": "slider", "bus": "SFX"},
		]
	},
	{
		"title": "VIDEO",
		"items": [
			{"label": "Fullscreen", "type": "action", "action_name": "fullscreen"},
			{"label": "VSync", "type": "action", "action_name": "vsync"},
			# Resolution Scale removed — slider did nothing (empty bus name)
		]
	},
	{
		"title": "ACCESSIBILITY",
		"items": [
			{"label": "Epilepsy Safe Mode", "type": "toggle", "var": "epilepsy_safe_mode", "default": true},
		]
	}
]


func _sync_visibility() -> void:
	if is_instance_valid(_ui_layer):
		_ui_layer.visible = visible

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS  # So _unhandled_input works while hidden
	hide()
	_sync_visibility()
	_setup_signals()
	_load_keybinds()
	_build_sections()


func open() -> void:
	_play_zoom_animation()
	show()
	_sync_visibility()


func close() -> void:
	visible = false
	_sync_visibility()
	settings_closed.emit()


func _setup_signals() -> void:
	close_button.pressed.connect(close)


func _build_sections() -> void:
	"""Build the settings sections with titles and items."""
	for section_data: Dictionary in SECTIONS:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 4)
		section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# Section title — centered
		var title := Label.new()
		title.text = section_data["title"]
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color(1, 1, 0.7, 1))
		title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		title.add_theme_constant_override("shadow_offset_x", 1)
		title.add_theme_constant_override("shadow_offset_y", 1)
		section.add_child(title)
		
		# Separator line — fill section width
		var sep := ColorRect.new()
		sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sep.size.y = 2
		sep.color = Color(1, 1, 1, 0.3)
		section.add_child(sep)
		
		# Items — centered
		for item_data in section_data["items"]:
			if typeof(item_data) == TYPE_DICTIONARY:
				var item_type: String = item_data.get("type", "")
				match item_type:
					"toggle":
						_add_toggle_item(item_data, section)
					"slider":
						_add_slider_item(item_data, section)
					"action":
						_add_action_item(item_data, section)
					"keybind":
						_add_keybind_item(item_data, section)
			else:
				# Plain text label
				var item_text: String = str(item_data)
				var item := Label.new()
				item.text = "  •  " + item_text
				item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				item.add_theme_font_size_override("font_size", 16)
				item.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
				section.add_child(item)
		
		# Spacer between sections
		var spacer := ColorRect.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.size.y = 16
		spacer.color = Color.TRANSPARENT
		section.add_child(spacer)
		
		sections_container.add_child(section)


func _add_toggle_item(item_data: Dictionary, section: VBoxContainer) -> void:
	"""Add a CheckBox toggle bound to a GameState var."""
	var var_name: String = item_data.get("var", "")
	var default_val: bool = item_data.get("default", false)
	
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var check := CheckBox.new()
	check.text = "  " + item_data.get("label", "")
	check.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	check.add_theme_font_size_override("font_size", 16)
	
	if var_name != "" and var_name in GameState:
		check.button_pressed = GameState.get(var_name)
	else:
		check.button_pressed = default_val
	
	if var_name != "" and var_name in GameState:
		check.toggled.connect(_on_game_state_toggle.bind(var_name))
	else:
		check.toggled.connect(_on_action_toggled.bind(var_name))
	hbox.add_child(check)
	section.add_child(hbox)


func _on_game_state_toggle(value: bool, var_name: String) -> void:
	"""Update a GameState boolean toggle."""
	if var_name in GameState:
		GameState.set(var_name, value)
		# Autosave settings when toggles change
		_save_settings()


func _add_slider_item(item_data: Dictionary, section: VBoxContainer) -> void:
	"""Add an HSlider for audio volume control."""
	var label_text: String = item_data.get("label", "Volume")
	var bus_name: String = item_data.get("bus", "Master")
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Label row: "Volume" and current value
	var label_row := HBoxContainer.new()
	label_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_row.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var name_label := Label.new()
	name_label.text = "  " + label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	label_row.add_child(name_label)
	
	var value_label := Label.new()
	value_label.name = "ValueLabel"
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	label_row.add_child(value_label)
	vbox.add_child(label_row)
	
	# Slider
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.value = 100.0
	slider.step = 1.0
	
	# Read current AudioServer volume if bus name is valid
	if bus_name != "":
		var bus_idx: int = AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0:
			var db: float = AudioServer.get_bus_volume_db(bus_idx)
			slider.value = db_to_linear(db) * 100.0
		value_label.text = "%d%%" % int(slider.value)
	else:
		value_label.text = "100%"
	
	slider.value_changed.connect(_on_slider_changed.bind(bus_name, value_label))
	vbox.add_child(slider)
	section.add_child(vbox)


func _add_action_item(item_data: Dictionary, section: VBoxContainer) -> void:
	"""Add a CheckBox that triggers a DisplayServer action (Fullscreen/VSync)."""
	var label_text: String = item_data.get("label", "")
	var action_name: String = item_data.get("action_name", "")
	
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var check := CheckBox.new()
	check.text = "  " + label_text
	check.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	check.add_theme_font_size_override("font_size", 16)
	
	# Set initial state from DisplayServer
	match action_name:
		"fullscreen":
			check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		"vsync":
			check.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	
	check.toggled.connect(_on_action_toggled.bind(action_name))
	hbox.add_child(check)
	section.add_child(hbox)


func _add_keybind_item(item_data: Dictionary, section: VBoxContainer) -> void:
	"""Add a clickable keybind button that captures key presses."""
	var label_text: String = item_data.get("label", "")
	var action_name: String = item_data.get("action", "")
	
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# Label
	var name_label := Label.new()
	name_label.text = "  " + label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	hbox.add_child(name_label)
	
	# Key button
	var key_btn := Button.new()
	key_btn.name = "KeyBtn_%s" % action_name
	key_btn.text = _get_key_display_name(action_name)
	key_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_btn.custom_minimum_size.x = 80
	key_btn.pressed.connect(_on_keybind_pressed.bind(action_name, key_btn))
	hbox.add_child(key_btn)
	
	_rebind_labels[action_name] = key_btn
	section.add_child(hbox)


func _get_key_display_name(action_name: String) -> String:
	"""Get the display name of the current key for an action."""
	if not InputMap.has_action(action_name):
		return "?"
	var events: Array = InputMap.action_get_events(action_name)
	if events.is_empty():
		return "?"
	var event: InputEvent = events[0]
	if event is InputEventKey:
		return OS.get_keycode_string(event.keycode)
	return "?"


func _on_keybind_pressed(action_name: String, button: Button) -> void:
	"""Enter rebinding mode for the given action."""
	if not _rebinding_action.is_empty():
		# Cancel previous rebinding
		if _rebind_labels.has(_rebinding_action):
			_rebind_labels[_rebinding_action].disabled = false
			_rebind_labels[_rebinding_action].text = _get_key_display_name(_rebinding_action)
	
	_rebinding_action = action_name
	_rebinding_button = button
	button.text = "..."
	button.disabled = true


func _unhandled_input(event: InputEvent) -> void:
	"""Capture key presses during rebinding."""
	if _rebinding_action.is_empty():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	
	var action_name: String = _rebinding_action
	var keycode: int = event.keycode
	
	# Escape cancels rebinding
	if keycode == KEY_ESCAPE:
		_cancel_rebinding()
		get_viewport().set_input_as_handled()
		return
	
	# Remove old events for this action
	if InputMap.has_action(action_name):
		InputMap.action_erase_events(action_name)
	
	# Add new event
	var new_event := InputEventKey.new()
	new_event.keycode = keycode
	InputMap.action_add_event(action_name, new_event)
	
	# Update display
	var btn = _rebind_labels.get(action_name)
	if btn:
		btn.text = OS.get_keycode_string(keycode)
		btn.disabled = false
	
	_save_keybinds()
	_rebinding_action = ""
	_rebinding_button = null
	
	print("Settings: Rebound '%s' to %s" % [action_name, OS.get_keycode_string(keycode)])
	get_viewport().set_input_as_handled()


func _cancel_rebinding() -> void:
	"""Cancel the current rebinding operation."""
	if not _rebinding_action.is_empty():
		var btn = _rebind_labels.get(_rebinding_action)
		if btn:
			btn.text = _get_key_display_name(_rebinding_action)
			btn.disabled = false
	_rebinding_action = ""
	_rebinding_button = null


func _save_keybinds() -> void:
	"""Save current keybindings to disk."""
	var config := ConfigFile.new()
	for action_data: Dictionary in KEYBINDABLE_ACTIONS:
		var aname: String = action_data["action"]
		if InputMap.has_action(aname):
			var events: Array = InputMap.action_get_events(aname)
			if not events.is_empty() and events[0] is InputEventKey:
				config.set_value("keybinds", aname, events[0].keycode)
	config.save(KEYBINDS_FILE)


func _load_keybinds() -> void:
	"""Load saved keybindings from disk."""
	var config := ConfigFile.new()
	if config.load(KEYBINDS_FILE) != OK:
		return
	for action_data: Dictionary in KEYBINDABLE_ACTIONS:
		var aname: String = action_data["action"]
		var keycode: int = config.get_value("keybinds", aname, -1)
		if keycode < 0:
			continue
		if InputMap.has_action(aname):
			InputMap.action_erase_events(aname)
			var ev := InputEventKey.new()
			ev.keycode = keycode
			InputMap.action_add_event(aname, ev)


func _on_slider_changed(value: float, bus_name: String, value_label: Label) -> void:
	"""Update AudioServer bus volume when slider changes."""
	value_label.text = "%d%%" % int(value)
	if bus_name != "":
		var bus_idx: int = AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0:
			var linear: float = value / 100.0
			var db: float = linear_to_db(linear)
			AudioServer.set_bus_volume_db(bus_idx, db)
			_save_settings()


func _save_settings() -> void:
	"""Save all settings to disk via SaveManager."""
	var username: String = GameState.logged_in_username
	if username.is_empty():
		return
	var sm = get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("autosave"):
		sm.autosave(username)


func _on_action_toggled(value: bool, action_name: String) -> void:
	"""Handle fullscreen/VSync toggles."""
	match action_name:
		"fullscreen":
			if value:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED
			)


func _play_zoom_animation() -> void:
	panel.scale = Vector2(0.8, 0.8)
	panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "scale", Vector2(1, 1), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.2)
