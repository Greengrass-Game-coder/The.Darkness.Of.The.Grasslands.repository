class_name SettingsLayer
extends Control

signal settings_closed()

@onready var _ui_layer: CanvasLayer = $UILayer
@onready var panel: Control = $UILayer/Panel
@onready var close_button: Button = $UILayer/Panel/CloseButton
@onready var sections_container: VBoxContainer = $UILayer/Panel/ScrollContainer/SectionsContainer

const BACKGROUND_TEXTURE: String = "res://The Darkness Of The Grasslands assets/UI/Lobby/Shop and inventory background UI.png"

# Section definitions: title, items.
# For toggle items, use a Dictionary: {"label": "...", "type": "toggle", "var": "game_state_var_name", "default": bool}
const SECTIONS: Array[Dictionary] = [
	{
		"title": "KEYBINDING",
		"items": ["Move: WASD", "Sprint: Shift", "Ability 1: Q", "Ability 2: R"]
	},
	{
		"title": "GAMEPLAY",
		"items": [
			{"label": "Hide Leaderboard", "type": "toggle", "var": "hide_leaderboard", "default": false},
		]
	},
	{
		"title": "AUDIO",
		"items": ["Master Volume", "Music Volume", "SFX Volume"]
	},
	{
		"title": "VIDEO",
		"items": ["Fullscreen", "VSync", "Resolution Scale"]
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
			if typeof(item_data) == TYPE_DICTIONARY and item_data.get("type") == "toggle":
				# Create a toggle (CheckBox) for interactive settings
				var var_name: String = item_data.get("var", "")
				var default_val: bool = item_data.get("default", false)
				
				var hbox := HBoxContainer.new()
				hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hbox.alignment = BoxContainer.ALIGNMENT_CENTER
				
				var check := CheckBox.new()
				check.text = "  " + item_data.get("label", "")
				check.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
				check.add_theme_font_size_override("font_size", 16)
				
				# Load current value from GameState
				if var_name != "" and var_name in GameState:
					check.button_pressed = GameState.get(var_name)
				else:
					check.button_pressed = default_val
				
				check.toggled.connect(_on_toggle_changed.bind(var_name))
				hbox.add_child(check)
				section.add_child(hbox)
			else:
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


func _on_toggle_changed(value: bool, var_name: String) -> void:
	"""Update GameState when a toggle setting changes."""
	if var_name != "" and var_name in GameState:
		GameState.set(var_name, value)


func _play_zoom_animation() -> void:
	panel.scale = Vector2(0.8, 0.8)
	panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "scale", Vector2(1, 1), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.2)
