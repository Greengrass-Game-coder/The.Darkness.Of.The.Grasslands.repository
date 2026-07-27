class_name LmsLinking
extends CanvasLayer

## LMS (Last Man Standing) Linking UI.
## Shows all available killers/survivors and their skin variants.
## Read-only display — just tracks what exists.
## Disabled by default (GameState.lms_enabled = false).

@export var panel_position: Vector2 = Vector2(300, 80)
@export var panel_size: Vector2 = Vector2(600, 400)

var _character_data: Dictionary = {}  # type -> [name, skins...]
var _current_tab: String = "survivors"


func _ready() -> void:
	_scan_characters()
	_build_ui()
	hide()


func _scan_characters() -> void:
	"""Scan the project for available character scenes."""
	_character_data = {
		"survivors": [],
		"killers": []
	}
	
	# Scan survivors directory
	var _survivor_dir: String = "res://scenes/"
	var _killer_dir: String = "res://scenes/"
	
	# Check known survivors
	if ResourceLoader.exists("res://scenes/greengrass.tscn"):
		_scan_skins("survivors", "Greengrass")
	
	# Check known killers
	if ResourceLoader.exists("res://scenes/violentgrass.tscn"):
		_scan_skins("killers", "Violentgrass")


func _scan_skins(type: String, base_name: String) -> void:
	"""Scan for skins of a character type."""
	var skins: Array[String] = [base_name]
	
	# Look for alternate textures in the assets folder
	var _texture_patterns: Array[String] = [
		"The Darkness Of The Grasslands assets/Characters/%s/" % base_name,
		"The Darkness Of The Grasslands assets/Skins/%s/" % base_name,
		"The Darkness Of The Grasslands assets/Skins/%s_*" % base_name
	]
	
	# Note: Full skin scanning would require DirectoryAccess
	# For now, we just register the base character
	
	_character_data[type].append({
		"name": base_name,
		"skins": skins
	})


func _build_ui() -> void:
	"""Build the LMS Linking UI panel."""
	# Background
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.position = panel_position
	bg.size = panel_size
	bg.color = Color(0.05, 0.05, 0.1, 0.85)
	add_child(bg)
	
	# Title
	var title := Label.new()
	title.name = "Title"
	title.text = "LMS LINKING"
	title.position = panel_position + Vector2(8, 8)
	title.size = Vector2(panel_size.x - 16, 28)
	title.add_theme_color_override("font_color", Color(1, 1, 0.7, 1))
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	add_child(title)
	
	# Status label
	var status := Label.new()
	status.name = "StatusLabel"
	status.text = "Status: DISABLED — Enable in admin panel"
	status.position = panel_position + Vector2(8, 40)
	status.size = Vector2(panel_size.x - 16, 20)
	status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	status.add_theme_font_size_override("font_size", 12)
	add_child(status)
	
	# Tab buttons
	var survivor_tab := Button.new()
	survivor_tab.name = "SurvivorTab"
	survivor_tab.text = "Survivors"
	survivor_tab.position = panel_position + Vector2(8, 68)
	survivor_tab.size = Vector2(120, 28)
	survivor_tab.pressed.connect(_on_tab_changed.bind("survivors"))
	add_child(survivor_tab)
	
	var killer_tab := Button.new()
	killer_tab.name = "KillerTab"
	killer_tab.text = "Killers"
	killer_tab.position = panel_position + Vector2(136, 68)
	killer_tab.size = Vector2(120, 28)
	killer_tab.pressed.connect(_on_tab_changed.bind("killers"))
	add_child(killer_tab)
	
	# Content area
	var content_bg := ColorRect.new()
	content_bg.name = "ContentBg"
	content_bg.position = panel_position + Vector2(8, 104)
	content_bg.size = Vector2(panel_size.x - 16, panel_size.y - 164)
	content_bg.color = Color(0, 0, 0, 0.3)
	add_child(content_bg)
	
	# Content label
	var content := Label.new()
	content.name = "ContentLabel"
	content.text = _get_content_text()
	content.position = panel_position + Vector2(16, 112)
	content.size = Vector2(panel_size.x - 32, panel_size.y - 180)
	content.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	content.add_theme_font_size_override("font_size", 13)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(content)
	
	# Close button
	var close_btn := Button.new()
	close_btn.name = "CloseBtn"
	close_btn.text = "Close"
	close_btn.position = panel_position + Vector2(panel_size.x - 80, panel_size.y - 28)
	close_btn.size = Vector2(72, 24)
	close_btn.pressed.connect(_on_close)
	add_child(close_btn)


func _on_tab_changed(tab: String) -> void:
	_current_tab = tab
	var content: Label = get_node_or_null("ContentLabel")
	if content:
		content.text = _get_content_text()


func _get_content_text() -> String:
	"""Generate the content text for the current tab."""
	var data: Array = _character_data.get(_current_tab, [])
	if data.is_empty():
		return "No %s found." % _current_tab
	
	var lines: Array[String] = []
	for entry: Dictionary in data:
		lines.append("=== %s ===" % entry["name"])
		for skin: String in entry["skins"]:
			var status_str: String = "NEW!" if skin == entry["name"] else ""
			lines.append("  - %s %s" % [skin, status_str])
	
	return "\n".join(lines)


func open() -> void:
	"""Open the LMS Linking panel."""
	self.visible = GameState.lms_enabled
	if GameState.lms_enabled:
		var content: Label = get_node_or_null("ContentLabel")
		if content:
			content.text = _get_content_text()
		print("LMSLinking: Opened")


func close() -> void:
	"""Close the panel."""
	hide()


func _on_close() -> void:
	close()
