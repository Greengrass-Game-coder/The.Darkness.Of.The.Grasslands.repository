class_name AdminPanel
extends CanvasLayer

## Admin GUI panel. Starts hidden. Toggle via "G Gui" chat command or F3.
## Full admin controls for private server hosts. Sends "G <command>" admin
## commands to the dedicated server, which broadcasts effects back to all
## clients (teleport, heal, damage, role change, flower spawn, pause, timer).

signal double_trouble_toggled(enabled: bool)
signal force_killer_toggled(enabled: bool)
signal role_switch_requested(role: String)  # "killer" or "survivor" (local test)

@export var panel_position: Vector2 = Vector2(1000, 8)
@export var panel_size: Vector2 = Vector2(280, 520)

var _double_trouble_btn: Button = null
var _force_killer_btn: Button = null
var _status_label: BitmapLabel = null
var _player_list_label: BitmapLabel = null
var _cmd_status_label: BitmapLabel = null
var _announce_edit: LineEdit = null
var _timer_edit: LineEdit = null
var _amount_edit: LineEdit = null
var _tp_x_edit: LineEdit = null
var _tp_y_edit: LineEdit = null
var _player_selector: OptionButton = null
var _pause_btn: Button = null
var _is_limited: bool = false
var _is_moderator: bool = false  # TheAcTualDummy — moderator level
var _gui_forced: bool = false  # Toggled by "G Gui" command
var _is_paused: bool = false  # Local mirror of server pause state
var _players_cache: Array = []  # Last known player list from server


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


func _mk_label(text: String, size: float, color: Color = Color(0.8, 0.8, 0.8, 1)) -> BitmapLabel:
	var l := BitmapLabel.new()
	l.label_text = text
	l.font_scale = size
	l.font_color = color
	l.custom_minimum_size = Vector2(panel_size.x - 20, 0)
	return l


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
	bg.color = Color(0.1, 0.1, 0.15, 0.92)
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
	title.position = panel_position + Vector2(8, 6)
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
	status.position = panel_position + Vector2(8, 30)
	status.size = Vector2(panel_size.x - 16, 16)
	status.font_scale = 0.10
	status.font_color = Color(0.7, 0.7, 0.7, 1)
	add_child(status)
	_status_label = status

	# Scrollable content area below the header
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.position = panel_position + Vector2(8, 52)
	scroll.size = Vector2(panel_size.x - 16, panel_size.y - 60)
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	# ── Double Trouble toggle ──
	var dt_btn := Button.new()
	dt_btn.name = "DoubleTroubleBtn"
	dt_btn.text = "Double Trouble: OFF"
	dt_btn.toggle_mode = true
	dt_btn.toggled.connect(_on_double_trouble_toggled)
	vbox.add_child(dt_btn)
	_double_trouble_btn = dt_btn

	if not _is_limited or _is_moderator:
		var fk_btn := Button.new()
		fk_btn.name = "ForceKillerBtn"
		fk_btn.text = "Force Next Killer: OFF"
		fk_btn.toggle_mode = true
		fk_btn.toggled.connect(_on_force_killer_toggled)
		vbox.add_child(fk_btn)
		_force_killer_btn = fk_btn

	# ── End Round ──
	var end_btn := Button.new()
	end_btn.name = "EndRoundBtn"
	end_btn.text = "End Round"
	end_btn.pressed.connect(_on_end_round)
	vbox.add_child(end_btn)

	# ── Player selector (shared by many commands) ──
	vbox.add_child(_mk_label("Target player:", 0.09))
	var selector := OptionButton.new()
	selector.name = "PlayerSelector"
	vbox.add_child(selector)
	_player_selector = selector

	# ── Set Killer ──
	var mk_btn := Button.new()
	mk_btn.name = "SetKillerBtn"
	mk_btn.text = "Set as KILLER"
	mk_btn.pressed.connect(_on_set_killer_pressed)
	vbox.add_child(mk_btn)

	# ── Eliminate ──
	var elim_btn := Button.new()
	elim_btn.name = "EliminateBtn"
	elim_btn.text = "Eliminate Player"
	elim_btn.pressed.connect(_on_eliminate_pressed)
	vbox.add_child(elim_btn)

	# ── Teleport ──
	vbox.add_child(_mk_label("Teleport X / Y:", 0.09))
	var tp_row := HBoxContainer.new()
	vbox.add_child(tp_row)
	var tp_x := LineEdit.new()
	tp_x.name = "TpX"
	tp_x.placeholder_text = "X"
	tp_x.custom_minimum_size = Vector2(60, 26)
	tp_row.add_child(tp_x)
	_tp_x_edit = tp_x
	var tp_y := LineEdit.new()
	tp_y.name = "TpY"
	tp_y.placeholder_text = "Y"
	tp_y.custom_minimum_size = Vector2(60, 26)
	tp_row.add_child(tp_y)
	_tp_y_edit = tp_y
	var tp_btn := Button.new()
	tp_btn.name = "TeleportBtn"
	tp_btn.text = "Teleport"
	tp_btn.pressed.connect(_on_teleport_pressed)
	tp_row.add_child(tp_btn)

	# ── Heal / Damage ──
	vbox.add_child(_mk_label("Heal / Damage amount:", 0.09))
	var amt_row := HBoxContainer.new()
	vbox.add_child(amt_row)
	var amount := LineEdit.new()
	amount.name = "AmountEdit"
	amount.placeholder_text = "e.g. 50"
	amount.custom_minimum_size = Vector2(70, 26)
	amt_row.add_child(amount)
	_amount_edit = amount
	var heal_btn := Button.new()
	heal_btn.name = "HealBtn"
	heal_btn.text = "Heal"
	heal_btn.pressed.connect(_on_heal_pressed)
	amt_row.add_child(heal_btn)
	var dmg_btn := Button.new()
	dmg_btn.name = "DamageBtn"
	dmg_btn.text = "Damage"
	dmg_btn.pressed.connect(_on_damage_pressed)
	amt_row.add_child(dmg_btn)

	# ── Spawn Flower ──
	var flower_btn := Button.new()
	flower_btn.name = "SpawnFlowerBtn"
	flower_btn.text = "Spawn Flower for Target"
	flower_btn.pressed.connect(_on_spawn_flower_pressed)
	vbox.add_child(flower_btn)

	# ── Kick / Ban ──
	var kick_row := HBoxContainer.new()
	vbox.add_child(kick_row)
	var kick_btn := Button.new()
	kick_btn.name = "KickBtn"
	kick_btn.text = "Kick"
	kick_btn.pressed.connect(_on_kick_pressed)
	kick_row.add_child(kick_btn)
	var ban_btn := Button.new()
	ban_btn.name = "BanBtn"
	ban_btn.text = "Ban"
	ban_btn.pressed.connect(_on_ban_pressed)
	kick_row.add_child(ban_btn)
	var unban_btn := Button.new()
	unban_btn.name = "UnbanBtn"
	unban_btn.text = "Unban"
	unban_btn.pressed.connect(_on_unban_pressed)
	kick_row.add_child(unban_btn)

	# ── Timer ──
	vbox.add_child(_mk_label("Round timer (seconds):", 0.09))
	var timer_row := HBoxContainer.new()
	vbox.add_child(timer_row)
	var timer_edit := LineEdit.new()
	timer_edit.name = "TimerEdit"
	timer_edit.placeholder_text = "e.g. 120"
	timer_edit.custom_minimum_size = Vector2(70, 26)
	timer_row.add_child(timer_edit)
	_timer_edit = timer_edit
	var timer_btn := Button.new()
	timer_btn.name = "TimerBtn"
	timer_btn.text = "Set Timer"
	timer_btn.pressed.connect(_on_timer_pressed)
	timer_row.add_child(timer_btn)

	# ── Pause / Resume ──
	var pause_btn := Button.new()
	pause_btn.name = "PauseBtn"
	pause_btn.text = "Pause Game"
	pause_btn.toggle_mode = true
	pause_btn.toggled.connect(_on_pause_toggled)
	vbox.add_child(pause_btn)
	_pause_btn = pause_btn

	# ── Announce ──
	vbox.add_child(_mk_label("Announce to all:", 0.09))
	var announce_edit := LineEdit.new()
	announce_edit.name = "AnnounceEdit"
	announce_edit.placeholder_text = "Message..."
	vbox.add_child(announce_edit)
	_announce_edit = announce_edit
	var ann_btn := Button.new()
	ann_btn.name = "AnnounceBtn"
	ann_btn.text = "Announce"
	ann_btn.pressed.connect(_on_announce_pressed)
	vbox.add_child(ann_btn)

	# ── Refresh player status ──
	var refresh_btn := Button.new()
	refresh_btn.name = "RefreshBtn"
	refresh_btn.text = "Refresh Player Status"
	refresh_btn.pressed.connect(_on_refresh_pressed)
	vbox.add_child(refresh_btn)

	# ── Command status ──
	var cmd_status := BitmapLabel.new()
	cmd_status.name = "CmdStatus"
	cmd_status.label_text = ""
	cmd_status.font_scale = 0.09
	cmd_status.font_color = Color(0.6, 1.0, 0.6, 1)
	vbox.add_child(cmd_status)
	_cmd_status_label = cmd_status

	# ── Separator ──
	var sep := ColorRect.new()
	sep.name = "Sep"
	sep.color = Color(1, 1, 1, 0.2)
	sep.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(sep)

	# ── Local role switcher (debug/test) ──
	vbox.add_child(_mk_label("Role (test):", 0.09))
	var killer_btn := Button.new()
	killer_btn.name = "RoleKillerBtn"
	killer_btn.text = "Switch to KILLER (local)"
	killer_btn.pressed.connect(func() -> void: role_switch_requested.emit("killer"))
	vbox.add_child(killer_btn)
	var survivor_btn := Button.new()
	survivor_btn.name = "RoleSurvivorBtn"
	survivor_btn.text = "Switch to SURVIVOR (local)"
	survivor_btn.pressed.connect(func() -> void: role_switch_requested.emit("survivor"))
	vbox.add_child(survivor_btn)

	# ── Player list header ──
	vbox.add_child(_mk_label("Players:", 0.09, Color(0.9, 0.9, 0.9, 1)))
	var pl := BitmapLabel.new()
	pl.name = "PlayerList"
	pl.label_text = "(not connected)"
	pl.font_scale = 0.08
	pl.font_color = Color(0.6, 0.6, 0.6, 1)
	vbox.add_child(pl)
	_player_list_label = pl

	hide()


func _send(cmd: String) -> void:
	"""Send an admin command to the server."""
	var nm = get_node("/root/NetworkManager")
	if is_instance_valid(nm) and nm.has_method("send_admin_command"):
		nm.send_admin_command(cmd)
		_set_cmd_status("Sent: " + cmd, Color(1, 1, 1, 1))
	else:
		_set_cmd_status("Not connected to server", Color(1.0, 0.5, 0.4, 1))


func _selected_player() -> String:
	if _player_selector == null or _player_selector.get_item_count() == 0:
		return ""
	var idx: int = _player_selector.selected
	if idx < 0:
		return ""
	return _player_selector.get_item_text(idx)


func _on_double_trouble_toggled(button_pressed: bool) -> void:
	GameState.double_trouble = button_pressed
	_double_trouble_btn.text = "Double Trouble: ON" if button_pressed else "Double Trouble: OFF"
	double_trouble_toggled.emit(button_pressed)
	_send("Gamemode select Double trouble" if button_pressed else "Gamemode normal")


func _on_force_killer_toggled(button_pressed: bool) -> void:
	if _is_limited and not _is_moderator:
		return  # Only moderators and full admins can force killer
	GameState.force_killer = button_pressed
	_force_killer_btn.text = "Force Next Killer: ON" if button_pressed else "Force Next Killer: OFF"
	force_killer_toggled.emit(button_pressed)
	if button_pressed:
		_send("Force next killer")


func _on_end_round() -> void:
	_send("End")


func _on_set_killer_pressed() -> void:
	var p: String = _selected_player()
	if p == "":
		_set_cmd_status("No player selected", Color(1.0, 0.6, 0.2, 1))
		return
	_send("SetKiller " + p)


func _on_eliminate_pressed() -> void:
	var p: String = _selected_player()
	if p == "":
		_set_cmd_status("No player selected", Color(1.0, 0.6, 0.2, 1))
		return
	_send("Kill " + p)


func _on_teleport_pressed() -> void:
	var p: String = _selected_player()
	if p == "":
		_set_cmd_status("No player selected", Color(1.0, 0.6, 0.2, 1))
		return
	var x: String = _tp_x_edit.text.strip_edges()
	var y: String = _tp_y_edit.text.strip_edges()
	if x.is_empty() or y.is_empty():
		_set_cmd_status("Enter X and Y", Color(1.0, 0.6, 0.2, 1))
		return
	_send("Tp %s %s %s" % [p, x, y])


func _on_heal_pressed() -> void:
	var p: String = _selected_player()
	if p == "":
		_set_cmd_status("No player selected", Color(1.0, 0.6, 0.2, 1))
		return
	var amt: String = _amount_edit.text.strip_edges()
	if amt.is_empty():
		_set_cmd_status("Enter an amount", Color(1.0, 0.6, 0.2, 1))
		return
	_send("Heal %s %s" % [p, amt])


func _on_damage_pressed() -> void:
	var p: String = _selected_player()
	if p == "":
		_set_cmd_status("No player selected", Color(1.0, 0.6, 0.2, 1))
		return
	var amt: String = _amount_edit.text.strip_edges()
	if amt.is_empty():
		_set_cmd_status("Enter an amount", Color(1.0, 0.6, 0.2, 1))
		return
	_send("Damage %s %s" % [p, amt])


func _on_spawn_flower_pressed() -> void:
	var p: String = _selected_player()
	if p == "":
		_set_cmd_status("No player selected", Color(1.0, 0.6, 0.2, 1))
		return
	_send("Spawnflower " + p)


func _on_kick_pressed() -> void:
	var p: String = _selected_player()
	if p == "":
		_set_cmd_status("No player selected", Color(1.0, 0.6, 0.2, 1))
		return
	_send("Kick " + p)


func _on_ban_pressed() -> void:
	var p: String = _selected_player()
	if p == "":
		_set_cmd_status("No player selected", Color(1.0, 0.6, 0.2, 1))
		return
	_send("Ban " + p)


func _on_unban_pressed() -> void:
	var p: String = _selected_player()
	if p == "":
		_set_cmd_status("No player selected", Color(1.0, 0.6, 0.2, 1))
		return
	_send("Unban " + p)


func _on_timer_pressed() -> void:
	var t: String = _timer_edit.text.strip_edges()
	if t.is_empty():
		_set_cmd_status("Enter seconds", Color(1.0, 0.6, 0.2, 1))
		return
	_send("Timer " + t)


func _on_pause_toggled(button_pressed: bool) -> void:
	_is_paused = button_pressed
	_pause_btn.text = "Resume Game" if button_pressed else "Pause Game"
	_send("Pause" if button_pressed else "Resume")


func _on_announce_pressed() -> void:
	if _announce_edit == null or _announce_edit.text.strip_edges().is_empty():
		return
	var nm = get_node("/root/NetworkManager")
	if is_instance_valid(nm) and nm.has_method("send_chat"):
		nm.send_chat(_announce_edit.text, false)
	_announce_edit.clear()
	_set_cmd_status("Announcement sent", Color(0.6, 1.0, 0.6, 1))


func _on_refresh_pressed() -> void:
	_send("Status")


func _on_admin_result(success: bool, message: String) -> void:
	_set_cmd_status(message, Color(0.6, 1.0, 0.6, 1) if success else Color(1.0, 0.5, 0.4, 1))


func _set_cmd_status(text: String, color: Color) -> void:
	if is_instance_valid(_cmd_status_label):
		_cmd_status_label.label_text = text
		_cmd_status_label.font_color = color


func update_player_list(players: Array) -> void:
	"""Update the player selector + list from server player_list data."""
	_players_cache = players
	if not is_instance_valid(_player_list_label):
		return

	if players.is_empty():
		_player_list_label.label_text = "(not connected)"
	else:
		var lines: Array[String] = []
		for p: Dictionary in players:
			var pname: String = p.get("username", "Unknown")
			var role: String = p.get("role", "?")
			var alive: bool = p.get("alive", true)
			var status_char: String = "[A]" if alive else "[D]"
			lines.append("%s %s - %s" % [status_char, pname, role.capitalize()])
		_player_list_label.label_text = "\n".join(lines)

	_populate_selector(players)


func update_player_status(players: Array) -> void:
	"""Update the player list with full status (HP, role, alive, position)."""
	_players_cache = players
	if not is_instance_valid(_player_list_label):
		return
	if players.is_empty():
		_player_list_label.label_text = "(no players)"
	else:
		var lines: Array[String] = []
		for p: Dictionary in players:
			var pname: String = p.get("username", "Unknown")
			var role: String = p.get("role", "?")
			var alive: bool = p.get("alive", true)
			var hp: float = p.get("hp", 0.0)
			var max_hp: float = p.get("max_hp", 100.0)
			var status_char: String = "[A]" if alive else "[D]"
			lines.append("%s %s - %s  HP %d/%d" % [status_char, pname, role.capitalize(), int(hp), int(max_hp)])
		_player_list_label.label_text = "\n".join(lines)
	_populate_selector(players)


func _populate_selector(players: Array) -> void:
	"""Fill the player dropdown, preserving current selection."""
	if not is_instance_valid(_player_selector):
		return
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
