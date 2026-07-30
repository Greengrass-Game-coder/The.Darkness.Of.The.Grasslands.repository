class_name AdminPanel
extends CanvasLayer

## Admin GUI panel. Starts hidden. Toggle via "G Gui" chat command.
## Shows full controls for full admin, limited controls for reserved testers.
## Also auto-shows for private server hosts.

signal double_trouble_toggled(enabled: bool)
signal force_killer_toggled(enabled: bool)

@export var panel_position: Vector2 = Vector2(1000, 8)
@export var panel_size: Vector2 = Vector2(200, 250)

var _double_trouble_btn: Button = null
var _force_killer_btn: Button = null
var _status_label: BitmapLabel = null
var _player_list_label: BitmapLabel = null
var _is_limited: bool = false
var _is_moderator: bool = false  # TheAcTualDummy — moderator level
var _gui_forced: bool = false  # Toggled by "G Gui" command


func _ready() -> void:
	_build_ui()
	_update_visibility()


func _process(_delta: float) -> void:
	_update_visibility()


func toggle_gui() -> void:
	"""Toggle admin GUI via 'G Gui' command."""
	_gui_forced = not _gui_forced
	_refresh_visibility()


func _update_visibility() -> void:
	"""Called every frame — checks both auto-conditions and gui_forced."""
	var should_show: bool = _gui_forced
	if not should_show:
		should_show = GameState.is_admin and GameState.in_private_server
	
	if should_show:
		if not visible or _needs_rebuild():
			var was_limited: bool = _is_limited
			_is_limited = GameState.is_limited_admin
			_is_moderator = GameState.logged_in_username.to_lower() == "theactualdummy"
			if was_limited != _is_limited:
				_build_ui()
			_refresh_visibility()
	else:
		visible = false


func _needs_rebuild() -> bool:
	return visible == false


func _refresh_visibility() -> void:
	"""Update visible state without rebuilding."""
	if _gui_forced:
		visible = true
	elif GameState.is_admin and GameState.in_private_server:
		visible = true
	else:
		visible = false


func _build_ui() -> void:
	# Clear existing children
	for child: Node in get_children():
		child.queue_free()
	
	_is_limited = GameState.is_limited_admin
	_is_moderator = GameState.logged_in_username.to_lower() == "theactualdummy"
	
	# Background
	var bg := ColorRect.new()
	bg.name = "AdminBg"
	bg.position = panel_position
	bg.size = panel_size
	bg.color = Color(0.1, 0.1, 0.15, 0.85)
	add_child(bg)
	
	# Title (BitmapLabel)
	var title := BitmapLabel.new()
	title.name = "Title"
	if _is_moderator:
		title.label_text = "MODERATOR"
		title.font_color = Color(0.3, 0.8, 1.0, 1)  # Cyan for moderator
	elif _is_limited:
		title.label_text = "LIMITED ADMIN"
		title.font_color = Color(1.0, 0.7, 0.2, 1)  # Amber for limited
	else:
		title.label_text = "ADMIN PANEL"
		title.font_color = Color(0.3, 1.0, 0.3, 1)  # Green for full
	title.position = panel_position + Vector2(8, 8)
	title.size = Vector2(panel_size.x - 16, 24)
	title.font_scale = 0.16
	add_child(title)
	
	# Status label
	var status := BitmapLabel.new()
	status.name = "StatusLabel"
	if _is_moderator:
		status.label_text = "Moderator (TheAcTualDummy)"
	elif _is_limited:
		status.label_text = "Reserved Tester (limited)"
	else:
		status.label_text = "Private Server"
	status.position = panel_position + Vector2(8, 32)
	status.size = Vector2(panel_size.x - 16, 16)
	status.font_scale = 0.10
	status.font_color = Color(0.7, 0.7, 0.7, 1)
	add_child(status)
	_status_label = status
	
	# Controls (safe, non-destructive only for limited users)
	var y_offset: float = 56.0
	
	# Double Trouble toggle (safe — fun mode toggle)
	var dt_btn := Button.new()
	dt_btn.name = "DoubleTroubleBtn"
	dt_btn.text = "Double Trouble: OFF"
	dt_btn.position = panel_position + Vector2(8, y_offset)
	dt_btn.size = Vector2(panel_size.x - 16, 30)
	dt_btn.toggle_mode = true
	dt_btn.toggled.connect(_on_double_trouble_toggled)
	add_child(dt_btn)
	_double_trouble_btn = dt_btn
	y_offset += 36
	
	if not _is_limited or _is_moderator:
		# Force Next Killer toggle (moderators and full admins only)
		var fk_btn := Button.new()
		fk_btn.name = "ForceKillerBtn"
		fk_btn.text = "Force Next Killer: OFF"
		fk_btn.position = panel_position + Vector2(8, y_offset)
		fk_btn.size = Vector2(panel_size.x - 16, 30)
		fk_btn.toggle_mode = true
		fk_btn.toggled.connect(_on_force_killer_toggled)
		add_child(fk_btn)
		_force_killer_btn = fk_btn
		y_offset += 36
	
	# Separator
	var sep := ColorRect.new()
	sep.name = "Sep"
	sep.position = panel_position + Vector2(8, y_offset)
	sep.size = Vector2(panel_size.x - 16, 1)
	sep.color = Color(1, 1, 1, 0.2)
	add_child(sep)
	y_offset += 8
	
	# Player list header
	var pl_header := BitmapLabel.new()
	pl_header.name = "PlayerListHeader"
	pl_header.label_text = "Connected Players:"
	pl_header.position = panel_position + Vector2(8, y_offset)
	pl_header.size = Vector2(panel_size.x - 16, 16)
	pl_header.font_scale = 0.10
	pl_header.font_color = Color(0.8, 0.8, 0.8, 1)
	add_child(pl_header)
	y_offset += 20
	
	# Player list
	var pl := BitmapLabel.new()
	pl.name = "PlayerList"
	pl.label_text = "(not connected)"
	pl.position = panel_position + Vector2(8, y_offset)
	pl.size = Vector2(panel_size.x - 16, panel_size.y - y_offset - 8)
	pl.font_scale = 0.10
	pl.font_color = Color(0.6, 0.6, 0.6, 1)
	add_child(pl)
	_player_list_label = pl
	
	hide()


func _on_double_trouble_toggled(button_pressed: bool) -> void:
	GameState.double_trouble = button_pressed
	_double_trouble_btn.text = "Double Trouble: ON" if button_pressed else "Double Trouble: OFF"
	double_trouble_toggled.emit(button_pressed)
	
	var nm = get_node("/root/NetworkManager")
	if is_instance_valid(nm) and nm.connected:
		var cmd: String = "Gamemode select Double trouble" if button_pressed else "Gamemode normal"
		nm.send_admin_command(cmd)


func _on_force_killer_toggled(button_pressed: bool) -> void:
	if _is_limited and not _is_moderator:
		return  # Only moderators and full admins can force killer
	GameState.force_killer = button_pressed
	_force_killer_btn.text = "Force Next Killer: ON" if button_pressed else "Force Next Killer: OFF"
	force_killer_toggled.emit(button_pressed)
	
	var nm2 = get_node("/root/NetworkManager")
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
