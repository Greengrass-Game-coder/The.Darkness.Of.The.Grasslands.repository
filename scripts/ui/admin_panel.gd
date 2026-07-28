class_name AdminPanel
extends CanvasLayer

## Admin GUI panel for private server host.
## Only visible when GameState.is_admin and GameState.in_private_server.

signal double_trouble_toggled(enabled: bool)
signal force_killer_toggled(enabled: bool)

@export var panel_position: Vector2 = Vector2(1000, 8)
@export var panel_size: Vector2 = Vector2(200, 250)

var _double_trouble_btn: Button = null
var _force_killer_btn: Button = null
var _status_label: Label = null
var _player_list_label: Label = null


func _ready() -> void:
	_build_ui()
	_update_visibility()


func _process(_delta: float) -> void:
	# Continuously check visibility based on admin state
	_update_visibility()


func _update_visibility() -> void:
	var should_show: bool = GameState.is_admin and GameState.in_private_server
	visible = should_show


func _build_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.name = "AdminBg"
	bg.position = panel_position
	bg.size = panel_size
	bg.color = Color(0.1, 0.1, 0.15, 0.85)
	add_child(bg)
	
	# Title
	var title := Label.new()
	title.name = "Title"
	title.text = "ADMIN PANEL"
	title.position = panel_position + Vector2(8, 8)
	title.size = Vector2(panel_size.x - 16, 24)
	title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)
	
	# Status label
	var status := Label.new()
	status.name = "StatusLabel"
	status.text = "Private Server"
	status.position = panel_position + Vector2(8, 32)
	status.size = Vector2(panel_size.x - 16, 16)
	status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	status.add_theme_font_size_override("font_size", 10)
	add_child(status)
	_status_label = status
	
	# Double Trouble toggle
	var dt_btn := Button.new()
	dt_btn.name = "DoubleTroubleBtn"
	dt_btn.text = "Double Trouble: OFF"
	dt_btn.position = panel_position + Vector2(8, 56)
	dt_btn.size = Vector2(panel_size.x - 16, 30)
	dt_btn.toggle_mode = true
	dt_btn.toggled.connect(_on_double_trouble_toggled)
	add_child(dt_btn)
	_double_trouble_btn = dt_btn
	
	# Force Next Killer toggle
	var fk_btn := Button.new()
	fk_btn.name = "ForceKillerBtn"
	fk_btn.text = "Force Next Killer: OFF"
	fk_btn.position = panel_position + Vector2(8, 92)
	fk_btn.size = Vector2(panel_size.x - 16, 30)
	fk_btn.toggle_mode = true
	fk_btn.toggled.connect(_on_force_killer_toggled)
	add_child(fk_btn)
	_force_killer_btn = fk_btn
	
	# Separator
	var sep := ColorRect.new()
	sep.name = "Sep"
	sep.position = panel_position + Vector2(8, 128)
	sep.size = Vector2(panel_size.x - 16, 1)
	sep.color = Color(1, 1, 1, 0.2)
	add_child(sep)
	
	# Player list header
	var pl_header := Label.new()
	pl_header.name = "PlayerListHeader"
	pl_header.text = "Connected Players:"
	pl_header.position = panel_position + Vector2(8, 136)
	pl_header.size = Vector2(panel_size.x - 16, 16)
	pl_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	pl_header.add_theme_font_size_override("font_size", 10)
	add_child(pl_header)
	
	# Player list
	var pl := Label.new()
	pl.name = "PlayerList"
	pl.text = "(not connected)"
	pl.position = panel_position + Vector2(8, 156)
	pl.size = Vector2(panel_size.x - 16, 80)
	pl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	pl.add_theme_font_size_override("font_size", 10)
	pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(pl)
	_player_list_label = pl
	
	hide()


func _on_double_trouble_toggled(button_pressed: bool) -> void:
	GameState.double_trouble = button_pressed
	_double_trouble_btn.text = "Double Trouble: ON" if button_pressed else "Double Trouble: OFF"
	double_trouble_toggled.emit(button_pressed)
	
	# Send admin command to server
	var nm = Engine.get_singleton("NetworkManager")
	if is_instance_valid(nm) and nm.connected:
		var cmd: String = "Gamemode select Double trouble" if button_pressed else "Gamemode normal"
		nm.send_admin_command(cmd)


func _on_force_killer_toggled(button_pressed: bool) -> void:
	GameState.force_killer = button_pressed
	_force_killer_btn.text = "Force Next Killer: ON" if button_pressed else "Force Next Killer: OFF"
	force_killer_toggled.emit(button_pressed)
	
	var nm2 = Engine.get_singleton("NetworkManager")
	if button_pressed and is_instance_valid(nm2) and nm2.connected:
		nm2.send_admin_command("Force next killer")


func update_player_list(players: Array) -> void:
	"""Update the player list display from server data."""
	if not is_instance_valid(_player_list_label):
		return
	
	if players.is_empty():
		_player_list_label.text = "(not connected)"
		return
	
	var lines: Array[String] = []
	for p: Dictionary in players:
		var pname: String = p.get("username", "Unknown")
		var role: String = p.get("role", "?")
		var alive: bool = p.get("alive", true)
		var status_char: String = "[A]" if alive else "[D]"
		lines.append("%s %s - %s" % [status_char, pname, role.capitalize()])
	
	_player_list_label.text = "\n".join(lines)
