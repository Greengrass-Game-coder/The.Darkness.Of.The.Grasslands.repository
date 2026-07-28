class_name SettingsLayer
extends Control

signal settings_closed()

@onready var _ui_layer: CanvasLayer = $UILayer
@onready var panel: Control = $UILayer/Panel
@onready var close_button: Button = $UILayer/Panel/CloseButton
@onready var sections_container: VBoxContainer = $UILayer/Panel/ScrollContainer/SectionsContainer

const BACKGROUND_TEXTURE: String = "res://The Darkness Of The Grasslands assets/UI/Lobby/Shop and inventory background UI.png"

# Section definitions: title, items.
# Supported item types:
#   String label       → plain text label
#   {"type":"toggle", "label","var","default"} → CheckBox bound to GameState
#   {"type":"slider", "label","bus"} → HSlider bound to AudioServer bus volume
#   {"type":"action", "label","action_name"} → CheckBox that triggers a function
const SECTIONS: Array[Dictionary] = [
	{
		"title": "KEYBINDING",
		"items": ["Move: WASD", "Sprint: Shift", "Ability 1: Q", "Ability 2: E", "Ability 3: R", "Ability 4: T"]
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
			{"label": "Resolution Scale", "type": "slider", "bus": ""},
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
	hide()
	_sync_visibility()
	_setup_signals()
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
	
	check.toggled.connect(_on_toggle_changed.bind(var_name))
	hbox.add_child(check)
	section.add_child(hbox)


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


func _on_toggle_changed(value: bool, var_name: String) -> void:
	"""Update GameState when a toggle setting changes."""
	if var_name != "" and var_name in GameState:
		GameState.set(var_name, value)


func _on_slider_changed(value: float, bus_name: String, value_label: Label) -> void:
	"""Update AudioServer bus volume when slider changes."""
	value_label.text = "%d%%" % int(value)
	if bus_name != "":
		var bus_idx: int = AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0:
			var linear: float = value / 100.0
			var db: float = linear_to_db(linear)
			AudioServer.set_bus_volume_db(bus_idx, db)


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
