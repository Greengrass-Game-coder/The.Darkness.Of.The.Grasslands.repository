class_name SettingsLayer
extends Control

signal settings_closed()

@onready var _ui_layer: CanvasLayer = $UILayer
@onready var panel: Control = $UILayer/Panel
@onready var close_button: Button = $UILayer/Panel/CloseButton
@onready var sections_container: VBoxContainer = $UILayer/Panel/ScrollContainer/SectionsContainer

const BACKGROUND_TEXTURE: String = "res://The Darkness Of The Grasslands assets/UI/Lobby/Shop and inventory background UI.png"

var _rebinding_action: String = ""   # Action currently waiting for input
var _rebinding_mode: String = ""     # "key" or "pad"
var _rebinding_button: Button = null
var _rebind_key_buttons: Dictionary = {}   # action -> Key button
var _rebind_pad_buttons: Dictionary = {}   # action -> Pad button

# Section definitions: title, items.
# Supported item types:
#   String label       → plain text label
#   {"type":"toggle", "label","var","default"} → CheckBox bound to GameState
#   {"type":"slider", "label","bus"} → HSlider bound to AudioServer bus volume
#   {"type":"action", "label","action_name"} → CheckBox that triggers a function
#   {"type":"keybind", "label","action"}     → Key + gamepad rebinding buttons
const SECTIONS: Array[Dictionary] = [
	{
		"title": "KEYBINDING",
		"items": [
			{"type": "keybind", "label": "Move Left", "action": "move_left"},
			{"type": "keybind", "label": "Move Right", "action": "move_right"},
			{"type": "keybind", "label": "Move Up", "action": "move_up"},
			{"type": "keybind", "label": "Move Down", "action": "move_down"},
			{"type": "keybind", "label": "Sprint", "action": "sprint"},
			{"type": "keybind", "label": "Interact", "action": "interact"},
			{"type": "keybind", "label": "Cancel / Back", "action": "cancel"},
			{"type": "keybind", "label": "Confirm / Select", "action": "confirm"},
			{"type": "keybind", "label": "Pause", "action": "pause"},
			{"type": "keybind", "label": "Ability 1", "action": "ability_1"},
			{"type": "keybind", "label": "Ability 2", "action": "ability_2"},
			{"type": "keybind", "label": "Ability 3", "action": "ability_3"},
			{"type": "keybind", "label": "Ability 4", "action": "ability_4"},
			{"type": "keybind", "label": "Display (console)", "action": "display_toggle"},
			{"type": "keybind", "label": "Gamble (win screen)", "action": "gamble"},
			{"type": "keybind", "label": "Tetris Left", "action": "tetris_left"},
			{"type": "keybind", "label": "Tetris Right", "action": "tetris_right"},
			{"type": "keybind", "label": "Tetris Soft Drop", "action": "tetris_down"},
			{"type": "keybind", "label": "Tetris Rotate", "action": "tetris_rotate"},
			{"type": "keybind", "label": "Tetris Hard Drop", "action": "tetris_harddrop"},
		]
	},
	{
		"title": "CONTROLLER",
		"items": [
			{"label": "Controller Vibration", "type": "toggle", "var": "vibration_enabled", "default": true},
		]
	},
	{
		"title": "GAMEPLAY",
		"items": [
			{"label": "Hide Leaderboard", "type": "toggle", "var": "hide_leaderboard", "default": false},
			{"label": "Ragdoll", "type": "toggle", "var": "ragdoll", "default": false},
		]
	},
	{
		"title": "AUDIO",
		"items": [
			{"label": "Master Volume", "type": "slider", "bus": "Master"},
			{"label": "Music Volume", "type": "slider", "bus": "Music"},
			{"label": "Music Muted", "type": "bus_mute", "bus": "Music", "default": false},
			{"label": "SFX Volume", "type": "slider", "bus": "SFX"},
			{"label": "Sound Effects Muted", "type": "bus_mute", "bus": "SFX", "default": false},
		]
	},
	{
		"title": "VIDEO",
		"items": [
			{"label": "Fullscreen", "type": "action", "action_name": "fullscreen"},
			{"label": "VSync", "type": "action", "action_name": "vsync"},
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
	_build_sections()


func open() -> void:
	_play_zoom_animation()
	show()
	_sync_visibility()
	if _ui_layer:
		_ui_layer.visible = true
		var first_btn := _first_button()
		if first_btn:
			first_btn.grab_focus()


func close() -> void:
	visible = false
	_sync_visibility()
	settings_closed.emit()


func _first_button() -> Button:
	var btns := _collect_buttons(panel)
	return btns[0] if not btns.is_empty() else null


func _collect_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			out.append(child)
		out.append_array(_collect_buttons(child))
	return out


func _setup_signals() -> void:
	close_button.pressed.connect(close)


func _build_sections() -> void:
	"""Build the settings sections with titles and items."""
	for section_data: Dictionary in SECTIONS:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 4)
		section.size_flags_horizontal = Control.SIZE_EXPAND_FILL

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

		var sep := ColorRect.new()
		sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sep.size.y = 2
		sep.color = Color(1, 1, 1, 0.3)
		section.add_child(sep)

		for item_data in section_data["items"]:
			if typeof(item_data) == TYPE_DICTIONARY:
				var item_type: String = item_data.get("type", "")
				match item_type:
					"toggle":
						_add_toggle_item(item_data, section)
					"slider":
						_add_slider_item(item_data, section)
					"bus_mute":
						_add_bus_mute_item(item_data, section)
					"action":
						_add_action_item(item_data, section)
					"keybind":
						_add_keybind_item(item_data, section)
			else:
				var item_text: String = str(item_data)
				var item := Label.new()
				item.text = "  •  " + item_text
				item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				item.add_theme_font_size_override("font_size", 16)
				item.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
				section.add_child(item)

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
		_save_settings()


func _add_slider_item(item_data: Dictionary, section: VBoxContainer) -> void:
	"""Add an HSlider for audio volume control."""
	var label_text: String = item_data.get("label", "Volume")
	var bus_name: String = item_data.get("bus", "Master")

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

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

	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.value = 100.0
	slider.step = 1.0

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


func _add_bus_mute_item(item_data: Dictionary, section: VBoxContainer) -> void:
	"""Add a CheckBox that mutes/unmutes an audio bus."""
	var label_text: String = item_data.get("label", "Mute")
	var bus_name: String = item_data.get("bus", "Master")

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var check := CheckBox.new()
	check.text = "  " + label_text
	check.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	check.add_theme_font_size_override("font_size", 16)

	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		check.button_pressed = AudioServer.is_bus_mute(bus_idx)
	else:
		check.button_pressed = item_data.get("default", false)

	check.toggled.connect(_on_bus_mute_toggled.bind(bus_name))
	hbox.add_child(check)
	section.add_child(hbox)


func _on_bus_mute_toggled(value: bool, bus_name: String) -> void:
	"""Mute/unmute an audio bus and persist the state."""
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_mute(bus_idx, value)
	_save_settings()


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

	match action_name:
		"fullscreen":
			check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		"vsync":
			check.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED

	check.toggled.connect(_on_action_toggled.bind(action_name))
	hbox.add_child(check)
	section.add_child(hbox)


func _add_keybind_item(item_data: Dictionary, section: VBoxContainer) -> void:
	"""Add a keybind row with two buttons: one for the keyboard key and one for
	the gamepad button. Click one, then press the new key/button to rebind."""
	var label_text: String = item_data.get("label", "")
	var action_name: String = item_data.get("action", "")

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var name_label := Label.new()
	name_label.text = "  " + label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	hbox.add_child(name_label)

	var key_btn := Button.new()
	key_btn.name = "KeyBtn_%s" % action_name
	key_btn.text = _key_name(action_name)
	key_btn.custom_minimum_size = Vector2(120, 30)
	key_btn.pressed.connect(_on_keybind_pressed.bind(action_name, key_btn, "key"))
	hbox.add_child(key_btn)
	_rebind_key_buttons[action_name] = key_btn

	var pad_btn := Button.new()
	pad_btn.name = "PadBtn_%s" % action_name
	pad_btn.text = _pad_name(action_name)
	pad_btn.custom_minimum_size = Vector2(120, 30)
	pad_btn.pressed.connect(_on_keybind_pressed.bind(action_name, pad_btn, "pad"))
	hbox.add_child(pad_btn)
	_rebind_pad_buttons[action_name] = pad_btn

	section.add_child(hbox)


func _key_name(action: String) -> String:
	var key: int = InputSystem.current_key(action)
	if key == 0:
		return "—"
	return OS.get_keycode_string(key)


func _pad_name(action: String) -> String:
	var button: int = InputSystem.current_button(action)
	if button < 0:
		return "—"
	return _joy_button_name(button)


func _joy_button_name(button: int) -> String:
	return {
		JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
		JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down",
		JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right",
		JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	}.get(button, "Btn%d" % button)


func _on_keybind_pressed(action_name: String, button: Button, mode: String) -> void:
	"""Enter rebinding mode for the given action's key or gamepad button."""
	if not _rebinding_action.is_empty():
		_cancel_rebinding()
	_rebinding_action = action_name
	_rebinding_mode = mode
	_rebinding_button = button
	button.text = "..."
	button.disabled = true


func _unhandled_input(event: InputEvent) -> void:
	"""Capture a new key or gamepad button during rebinding."""
	if _rebinding_action.is_empty():
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_cancel_rebinding()
		get_viewport().set_input_as_handled()
		return

	if _rebinding_mode == "key":
		if not (event is InputEventKey and event.pressed and not event.echo):
			return
		var action: String = _rebinding_action
		InputSystem.rebind_key(action, event.keycode)
		var btn: Button = _rebind_key_buttons.get(action)
		if btn:
			btn.text = OS.get_keycode_string(event.keycode)
			btn.disabled = false
		_finish_rebinding()
	elif _rebinding_mode == "pad":
		if not (event is InputEventJoypadButton and event.pressed):
			return
		var action2: String = _rebinding_action
		InputSystem.rebind_button(action2, event.button_index)
		var pbtn: Button = _rebind_pad_buttons.get(action2)
		if pbtn:
			pbtn.text = _joy_button_name(event.button_index)
			pbtn.disabled = false
		_finish_rebinding()
	get_viewport().set_input_as_handled()


func _finish_rebinding() -> void:
	_rebinding_action = ""
	_rebinding_mode = ""
	_rebinding_button = null


func _cancel_rebinding() -> void:
	"""Cancel the current rebinding operation."""
	if not _rebinding_action.is_empty():
		if _rebinding_mode == "key":
			var kb: Button = _rebind_key_buttons.get(_rebinding_action)
			if kb:
				kb.text = _key_name(_rebinding_action)
				kb.disabled = false
		elif _rebinding_mode == "pad":
			var pb: Button = _rebind_pad_buttons.get(_rebinding_action)
			if pb:
				pb.text = _pad_name(_rebinding_action)
				pb.disabled = false
	_rebinding_action = ""
	_rebinding_mode = ""
	_rebinding_button = null


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
