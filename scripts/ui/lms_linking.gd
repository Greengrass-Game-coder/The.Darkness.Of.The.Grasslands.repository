class_name LmsLinking
extends CanvasLayer

## LMS (Last Man Standing) Linking UI.
## Character/skin browser for the character controllers (Greengrass, Violentgrass).
## Shows each character and their skin variants (read-only display).
## Linked from the character cards in the Shop and Inventory screens.

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
	
	# Dynamic scan — all characters from catalog
	for cd in CharacterData.get_catalog():
		var dir_name: String = cd.character_type + "s"
		if ResourceLoader.exists(cd.scene_path):
			_scan_skins(dir_name, cd.display_name)
		# Fallback: check standard scene paths
		elif ResourceLoader.exists("res://scenes/" + cd.display_name.to_lower() + ".tscn"):
			_scan_skins(dir_name, cd.display_name)


func _scan_skins(type: String, base_name: String) -> void:
	"""Scan for skin variants of a character (real DirectoryAccess scan).

	A skin = any subfolder inside a "Skins" directory for the character.
	No Skins folder yet = the character only has its base sprite (no LMS content).
	"""
	var skins: Array[String] = [base_name]
	
	# Where skin folders would live for this character
	var _skin_roots: Array[String] = [
		"res://The Darkness Of The Grasslands assets/Skins/%s/" % base_name,
		"res://The Darkness Of The Grasslands assets/Sprites/%s/Skins/" % base_name,
		"res://The Darkness Of The Grasslands assets/Sprites/%s/skins/" % base_name,
	]
	
	for root in _skin_roots:
		if not DirAccess.dir_exists_absolute(root):
			continue
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with("."):
				skins.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	
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
	var title := BitmapLabel.new()
	title.name = "Title"
	title.label_text = "LMS LINKING"
	title.position = panel_position + Vector2(8, 8)
	title.size = Vector2(panel_size.x - 16, 28)
	title.font_color = Color(1, 1, 0.7, 1)
	title.font_scale = 0.16
	add_child(title)
	
	# Status label
	var status := BitmapLabel.new()
	status.name = "StatusLabel"
	status.label_text = "Status: DISABLED ----- Enable in admin panel"
	status.position = panel_position + Vector2(8, 40)
	status.size = Vector2(panel_size.x - 16, 20)
	status.font_color = Color(0.7, 0.7, 0.7, 1)
	status.font_scale = 0.10
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
	var content := BitmapLabel.new()
	content.name = "ContentLabel"
	content.label_text = _get_content_text()
	content.position = panel_position + Vector2(16, 112)
	content.size = Vector2(panel_size.x - 32, panel_size.y - 180)
	content.font_color = Color(0.85, 0.85, 0.85, 1)
	content.font_scale = 0.11
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
	var content = get_node_or_null("ContentLabel")
	if content:
		content.label_text = _get_content_text()


func _get_content_text() -> String:
	"""Generate the content text for the current tab."""
	var data: Array = _character_data.get(_current_tab, [])
	if data.is_empty():
		return "No %s found." % _current_tab
	
	var lines: Array[String] = []
	for entry: Dictionary in data:
		lines.append("=== %s ===" % entry["name"])
		var skins: Array = entry["skins"]
		if skins.size() <= 1:
			lines.append("  - %s (base)" % entry["name"])
			lines.append("  No skins yet.")
		else:
			for i in skins.size():
				var skin: String = skins[i]
				var tag: String = "(base)" if i == 0 else ""
				lines.append("  - %s %s" % [skin, tag])
	
	return "
".join(lines)


func open(character_name: String = "") -> void:
	"""Open the LMS Linking panel, optionally focused on one character."""
	if character_name != "":
		var cd := CharacterData.get_by_name(character_name)
		if cd != null:
			_current_tab = "killers" if cd.character_type == "killer" else "survivors"
	
	# Status label reflects what the scan found (LMS exists only when skins exist)
	var total_skins: int = 0
	for entries in _character_data.values():
		for e in entries:
			total_skins += (e["skins"] as Array).size() - 1
	var status = get_node_or_null("StatusLabel")
	if status:
		if total_skins > 0:
			status.label_text = "Status: %d skin(s) found" % total_skins
		else:
			status.label_text = "Status: No skins yet — base sprites only"
	
	var content = get_node_or_null("ContentLabel")
	if content:
		content.label_text = _get_content_text()
	self.visible = true
	print("LMSLinking: Opened (", _current_tab, ")")


func close() -> void:
	"""Close the panel."""
	hide()


func _on_close() -> void:
	close()
