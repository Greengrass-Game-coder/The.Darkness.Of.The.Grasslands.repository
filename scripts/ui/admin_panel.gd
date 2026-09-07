class_name AdminPanel
extends CanvasLayer

## Admin GUI panel. Starts hidden. Toggle via "G Gui" chat command.
## Shows full controls for full admin, limited controls for reserved testers.
## Also auto-shows for private server hosts.
## Upgraded: End Round, Eliminate Player, Announce, and admin command feedback.

signal double_trouble_toggled(enabled: bool)
signal force_killer_toggled(enabled: bool)
signal role_switch_requested(role: String)  # "killer" or "survivor"

@export var panel_position: Vector2 = Vector2(1000, 8)
@export var panel_size: Vector2 = Vector2(250, 440)

var _double_trouble_btn: Button = null
var _force_killer_btn: Button = null
var _status_label: BitmapLabel = null
var _player_list_label: BitmapLabel = null
var _player_selector: OptionButton = null
var _announce_edit: LineEdit = null
var _cmd_status_label: BitmapLabel = null
var _is_limited: bool = false
var _is_moderator: bool = false  # TheAcTualDummy — moderator level
var _gui_forced: bool = false  # Toggled by "G Gui" command


func _ready() -> void:
	_build_ui()
	_update_visibility()
	var nm = get_node("/root/NetworkManager")
	if is_instance_valid(nm):
		if not nm.admin_command_result.is_connected(_on_admin_result):
			nm.admin_command_result.connect(_on_admin_result)


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
	bg.color = Color(0.1, 0.1, 0.15, 0.88)
	add_child(bg)

	# Title
	var title := BitmapLabel.new()
	title.name = "Title"
	if _is_moderator:
		title.label_text = "MODERATOR"
		title.font_color = Color(0.3, 0.8, 1.0, 1)
	elif _is_limited:
		title.label_text = "LIMITED ADMIN"
		title.font_color = Color(1.0, 0.7, 0.2, 1)
	else:
		title.label_text = "ADMIN PANEL"
		title.font_color = Color(0.3, 1.0, 0.3, 1)
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

	var y_offset: float = 52.0

	# Double Trouble toggle
	var dt_btn := Button.new()
	dt_btn.name = "DoubleTroubleBtn"
	dt_btn.text = "Double Trouble: OFF"
	dt_btn.position = panel_position + Vector2(8, y_offset)
	dt_btn.size = Vector2(panel_size.x - 16, 26)
	dt_btn.toggle_mode = true
	dt_btn.toggled.connect(_on_double_trouble_toggled)
	add_child(dt_btn)
	_double_trouble_btn = dt_btn
	y_offset += 32

	if not _is_limited or _is_moderator:
		var fk_btn := Button.new()
		fk_btn.name = "ForceKillerBtn"
		fk_btn.text = "Force Next Killer: OFF"
		fk_btn.position = panel_position + Vector2(8, y_offset)
		fk_btn.size = Vector2(panel_size.x - 16, 26)
		fk_btn.toggle_mode = true
		fk_btn.toggled.connect(_on_force_killer_toggled)
		add_child(fk_btn)
		_force_killer_btn = fk_btn
		y_offset += 32

	# End Round (all admins)
	var end_btn := Button.new()
	end_btn.name = "EndRoundBtn"
	end_btn.text = "End Round"
	end_btn.position = panel_position + Vector2(8, y_offset)
	end_btn.size = Vector2(panel_size.x - 16, 26)
	end_btn.pressed.connect(_on_end_round)
	add_child(end_btn)
	y_offset += 32

	# Eliminate Player (all admins)
	var elim_label := BitmapLabel.new()
	elim_label.name = "ElimLabel"
	elim_label.label_text = "Eliminate Player:"
	elim_label.position = panel_position + Vector2(8, y_offset)
	elim_label.size = Vector2(panel_size.x - 16, 14)
	elim_label.font_scale = 0.09
	elim_label.font_color = Color(0.8, 0.8, 0.8, 1)
	add_child(elim_label)
	y_offset += 18

	var selector := OptionButton.new()
	selector.name = "PlayerSelector"
	selector.position = panel_position + Vector2(8, y_offset)
	selector.size = Vector2(panel_size.x - 92, 26)
	add_child(selector)
	_player_selector = selector

	var elim_btn := Button.new()
	elim_btn.name = "EliminateBtn"
	elim_btn.text = "Eliminate"
	elim_btn.position = panel_position + Vector2(panel_size.x - 76, y_offset)
	elim_btn.size = Vector2(68, 26)
	elim_btn.pressed.connect(_on_eliminate_pressed)
	add_child(elim_btn)
	y_offset += 32

	# Announce
	var ann_label := BitmapLabel.new()
	ann_label.name = "AnnLabel"
	ann_label.label_text = "Announce to all:"
	ann_label.position = panel_position + Vector2(8, y_offset)
	ann_label.size = Vector2(panel_size.x - 16, 14)
	ann_label.font_scale = 0.09
	ann_label.font_color = Color(0.8, 0.8, 0.8, 1)
	add_child(ann_label)
	y_offset += 18

	var announce_edit := LineEdit.new()
	announce_edit.name = "AnnounceEdit"
	announce_edit.placeholder_text = "Message..."
	announce_edit.position = panel_position + Vector2(8, y_offset)
	announce_edit.size = Vector2(panel_size.x - 16, 26)
	add_child(announce_edit)
	_announce_edit = announce_edit
	y_offset += 26

	var ann_btn := Button.new()
	ann_btn.name = "AnnounceBtn"
	ann_btn.text = "Announce"
	ann_btn.position = panel_position + Vector2(8, y_offset)
	ann_btn.size = Vector2(panel_size.x - 16, 26)
	ann_btn.pressed.connect(_on_announce_pressed)
	add_child(ann_btn)
	y_offset += 32

	# Command status
	var cmd_status := BitmapLabel.new()
	cmd_status.name = "CmdStatus"
	cmd_status.label_text = ""
	cmd_status.position = panel_position + Vector2(8, y_offset)
	cmd_status.size = Vector2(panel_size.x - 16, 16)
	cmd_status.font_scale = 0.09
	cmd_status.font_color = Color(0.6, 1.0, 0.6, 1)
	add_child(cmd_status)
	_cmd_status_label = cmd_status
	y_offset += 20

	# Separator
	var sep := ColorRect.new()
	sep.name = "Sep"
	sep.position = panel_position + Vector2(8, y_offset)
	sep.size = Vector2(panel_size.x - 16, 1)
	sep.color = Color(1, 1, 1, 0.2)
	add_child(sep)
	y_offset += 8

	# Role switcher (debug/test)
	var role_header := BitmapLabel.new()
	role_header.name = "RoleHeader"
	role_header.label_text = "Role (test):"
	role_header.position = panel_position + Vector2(8, y_offset)
	role_header.size = Vector2(panel_size.x - 16, 14)
	role_header.font_scale = 0.09
	role_header.font_color = Color(0.8, 0.8, 0.8, 1)
	add_child(role_header)
	y_offset += 18

	var killer_btn := Button.new()
	killer_btn.name = "RoleKillerBtn"
	killer_btn.text = "Switch to KILLER"
	killer_btn.position = panel_position + Vector2(8, y_offset)
	killer_btn.size = Vector2(panel_size.x - 16, 24)
	killer_btn.pressed.connect(func() -> void: role_switch_requested.emit("killer"))
	add_child(killer_btn)
	y_offset += 28

	var survivor_btn := Button.new()
	survivor_btn.name = "RoleSurvivorBtn"
	survivor_btn.text = "Switch to SURVIVOR"
	survivor_btn.position = panel_position + Vector2(8, y_offset)
	survivor_btn.size = Vector2(panel_size.x - 16, 24)
	survivor_btn.pressed.connect(func() -> void: role_switch_requested.emit("survivor"))
	add_child(survivor_btn)
	y_offset += 30

	# Player list header
	var pl_header := BitmapLabel.new()
	pl_header.name = "PlayerListHeader"
	pl_header.label_text = "Connected Players:"
	pl_header.position = panel_position + Vector2(8, y_offset)
	pl_header.size = Vector2(panel_size.x - 16, 14)
	pl_header.font_scale = 0.09
	pl_header.font_color = Color(0.8, 0.8, 0.8, 1)
	add_child(pl_header)
	y_offset += 18

	var pl := BitmapLabel.new()
	pl.name = "PlayerList"
	pl.label_text = "(not connected)"
	pl.position = panel_position + Vector2(8, y_offset)
	pl.size = Vector2(panel_size.x - 16, panel_size.y - y_offset - 8)
	pl.font_scale = 0.09
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
		_set_cmd_status("Sent: " + cmd, Color(1, 1, 1, 1))


func _on_force_killer_toggled(button_pressed: bool) -> void:
	if _is_limited and not _is_moderator:
		return  # Only moderators and full admins can force killer
	GameState.force_killer = button_pressed
	_force_killer_btn.text = "Force Next Killer: ON" if button_pressed else "Force Next Killer: OFF"
	force_killer_toggled.emit(button_pressed)

	var nm2 = get_node("/root/NetworkManager")
	if button_pressed and is_instance_valid(nm2) and nm2.connected:
		nm2.send_admin_command("Force next killer")
		_set_cmd_status("Forcing next killer", Color(1, 1, 1, 1))


func _on_end_round() -> void:
	var nm = get_node("/root/NetworkManager")
	if is_instance_valid(nm) and nm.connected:
		nm.send_admin_command("End")
		_set_cmd_status("Ending round...", Color(1, 1, 1, 1))


func _on_eliminate_pressed() -> void:
	if _player_selector == null or _player_selector.get_item_count() == 0:
		_set_cmd_status("No players to eliminate", Color(1, 0.6, 0.2, 1))
		return
	var idx: int = _player_selector.selected
	if idx < 0:
		return
	var pname: String = _player_selector.get_item_text(idx)
	var nm = get_node("/root/NetworkManager")
	if is_instance_valid(nm) and nm.connected:
		nm.send_admin_command("Kill " + pname)
		_set_cmd_status("Eliminating %s..." % pname, Color(1, 1, 1, 1))


func _on_announce_pressed() -> void:
	if _announce_edit == null or _announce_edit.text.strip_edges().is_empty():
		return
	var nm = get_node("/root/NetworkManager")
	if is_instance_valid(nm) and nm.connected:
		nm.send_chat(_announce_edit.text, false)
	_announce_edit.clear()
	_set_cmd_status("Announcement sent", Color(0.6, 1.0, 0.6, 1))


func _on_admin_result(success: bool, message: String) -> void:
	_set_cmd_status(message, Color(0.6, 1.0, 0.6, 1) if success else Color(1.0, 0.5, 0.4, 1))


func _set_cmd_status(text: String, color: Color) -> void:
	if is_instance_valid(_cmd_status_label):
		_cmd_status_label.label_text = text
		_cmd_status_label.font_color = color


func update_player_list(players: Array) -> void:
	"""Update the player list display + eliminate selector from server data."""
	if not is_instance_valid(_player_list_label):
		return

	if players.is_empty():
		_player_list_label.text = "(not connected)"
	else:
		var lines: Array[String] = []
		for p: Dictionary in players:
			var pname: String = p.get("username", "Unknown")
			var role: String = p.get("role", "?")
			var alive: bool = p.get("alive", true)
			var status_char: String = "[A]" if alive else "[D]"
			lines.append("%s %s - %s" % [status_char, pname, role.capitalize()])
		_player_list_label.text = "\n".join(lines)

	# Populate the eliminate-player selector
	if is_instance_valid(_player_selector):
		var prev: String = ""
		if _player_selector.selected >= 0 and _player_selector.get_item_count() > 0:
			prev = _player_selector.get_item_text(_player_selector.selected)
		_player_selector.clear()
		for p: Dictionary in players:
			_player_selector.add_item(p.get("username", "Unknown"))
		if prev != "":
			for i in range(_player_selector.item_count):
				if _player_selector.get_item_text(i) == prev:
					_player_selector.select(i)
					break
