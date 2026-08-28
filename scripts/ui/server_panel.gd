class_name ServerPanel
extends Control
## Host-only private server / developer panel. Lets the host (or a solo player)
## control the match, roster, AI, server settings and arbitrary values live.
##
## Opened from the pause menu (host/solo only). PROCESS_MODE_ALWAYS so it stays
## interactive while the pause menu has the tree paused underneath it.

signal panel_closed()

const MAX_VAL: float = 999999.0

@onready var _tabs: TabContainer = $Panel/VBox/Tabs
@onready var _close_button: Button = $Panel/VBox/Header/CloseButton

# Match tab
var _match_readout: Label
var _match_spin: SpinBox
# AI tab
var _difficulty_slider: HSlider
var _difficulty_value: Label
# Players tab
var _player_list: VBoxContainer
var _player_refresh_acc: float = 0.0
# Server tab
var _server_name_edit: LineEdit
var _broadcast_edit: LineEdit


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_close_button.pressed.connect(_close)
	_build_match_tab()
	_build_players_tab()
	_build_ai_tab()
	_build_server_tab()
	_build_values_tab()


func _process(delta: float) -> void:
	_refresh_match_readout()
	_player_refresh_acc += delta
	if _player_refresh_acc >= 1.0:
		_player_refresh_acc = 0.0
		_refresh_players()


# ── Helpers ────────────────────────────────────────────────────────────────

## The currently-open game map, or null if we aren't in a live match.
func _game_map() -> Node:
	var s: Node = get_tree().current_scene
	if s != null and "match_timer" in s:
		return s
	return null


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 36)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	return b


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	return l


func _close() -> void:
	panel_closed.emit()
	queue_free()


# ── Match tab ──────────────────────────────────────────────────────────────

func _build_match_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Match"
	tab.add_theme_constant_override("separation", 10)
	_tabs.add_child(tab)

	tab.add_child(_hint("Controls the round clock on the current map."))

	_match_readout = Label.new()
	_match_readout.add_theme_font_size_override("font_size", 22)
	tab.add_child(_match_readout)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	tab.add_child(row)

	_match_spin = SpinBox.new()
	_match_spin.min_value = 0.0
	_match_spin.max_value = MAX_VAL
	_match_spin.step = 5.0
	_match_spin.value = 240.0
	_match_spin.custom_minimum_size = Vector2(140, 36)
	row.add_child(_match_spin)
	row.add_child(_btn("Set Time", _set_match_time))
	row.add_child(_btn("+30s", func() -> void: _adjust_time(30.0)))
	row.add_child(_btn("-30s", func() -> void: _adjust_time(-30.0)))

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	tab.add_child(row2)
	row2.add_child(_btn("End Round Now", _end_round))
	row2.add_child(_btn("Restart Round", _restart_round))


func _refresh_match_readout() -> void:
	var gm := _game_map()
	if gm == null:
		_match_readout.text = "No active match."
		return
	var t: float = gm._time_remaining
	_match_readout.text = "Time left: %d s" % int(t)


func _set_match_time() -> void:
	var gm := _game_map()
	if gm == null:
		return
	gm._time_remaining = clampf(_match_spin.value, 0.0, gm.MATCH_DURATION)
	if gm.has_method("_update_timer_label"):
		gm._update_timer_label()
	if gm.match_timer and gm.match_timer.paused:
		gm.match_timer.paused = false


func _adjust_time(d: float) -> void:
	var gm := _game_map()
	if gm == null:
		return
	gm._time_remaining = clampf(gm._time_remaining + d, 0.0, gm.MATCH_DURATION)
	if gm.has_method("_update_timer_label"):
		gm._update_timer_label()


func _end_round() -> void:
	var gm := _game_map()
	if gm != null and gm.has_method("_end_match"):
		gm._end_match()


func _restart_round() -> void:
	if _game_map() == null:
		return
	var pm: Node = get_node_or_null("/root/PauseManager")
	if pm != null and pm.has_method("resume"):
		pm.resume()
	queue_free()
	get_tree().reload_current_scene()


# ── Players tab ────────────────────────────────────────────────────────────

func _build_players_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Players"
	tab.add_theme_constant_override("separation", 10)
	_tabs.add_child(tab)

	tab.add_child(_hint("Connected peers — kick works on the host only."))
	tab.add_child(_btn("Refresh", _refresh_players))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(scroll)

	_player_list = VBoxContainer.new()
	_player_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_player_list)
	_refresh_players()


func _refresh_players() -> void:
	if not is_inside_tree() or _player_list == null:
		return
	for c in _player_list.get_children():
		c.queue_free()
	_add_player_row(0, "Local game (solo).")


func _add_player_row(pid: int, name: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = "%s  (#%d)" % [name, pid]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var kick := _btn("Kick", _kick_player.bind(pid))
	row.add_child(kick)
	_player_list.add_child(row)


func _kick_player(_pid: int) -> void:
	_refresh_players()


# ── AI tab ─────────────────────────────────────────────────────────────────

func _build_ai_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "AI"
	tab.add_theme_constant_override("separation", 10)
	_tabs.add_child(tab)

	tab.add_child(_hint("Killer AI difficulty floor & bot spawns."))

	_difficulty_value = Label.new()
	_difficulty_value.add_theme_font_size_override("font_size", 18)
	tab.add_child(_difficulty_value)

	_difficulty_slider = HSlider.new()
	_difficulty_slider.min_value = 0.0
	_difficulty_slider.max_value = 1.0
	_difficulty_slider.step = 0.01
	_difficulty_slider.value = 0.28
	_difficulty_slider.custom_minimum_size = Vector2(420, 26)
	_difficulty_slider.value_changed.connect(_on_difficulty_changed)
	tab.add_child(_difficulty_slider)
	_on_difficulty_changed(_difficulty_slider.value)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	tab.add_child(row)
	row.add_child(_btn("Spawn Killer Bot", _spawn_killer))
	row.add_child(_btn("Spawn Survivor Bots", _spawn_survivors))


func _on_difficulty_changed(v: float) -> void:
	_difficulty_value.text = "Difficulty floor: %.2f" % v
	var gm := _game_map()
	if gm != null and gm._ai_difficulty and is_instance_valid(gm._ai_difficulty):
		gm._ai_difficulty.start_difficulty = v


func _spawn_killer() -> void:
	var gm := _game_map()
	if gm != null and gm.has_method("_spawn_bot_killer"):
		gm._spawn_bot_killer()


func _spawn_survivors() -> void:
	var gm := _game_map()
	if gm != null and gm.has_method("_spawn_survivor_bots"):
		gm._spawn_survivor_bots()


# ── Server tab ─────────────────────────────────────────────────────────────

func _build_server_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Server"
	tab.add_theme_constant_override("separation", 10)
	_tabs.add_child(tab)

	tab.add_child(_hint("Host server settings (host only)."))

	_server_name_edit = LineEdit.new()
	_server_name_edit.placeholder_text = "Server name"
	_server_name_edit.custom_minimum_size = Vector2(300, 36)
	tab.add_child(_server_name_edit)
	tab.add_child(_btn("Set Server Name", _set_server_name))

	_broadcast_edit = LineEdit.new()
	_broadcast_edit.placeholder_text = "Message to broadcast to players"
	_broadcast_edit.custom_minimum_size = Vector2(300, 36)
	tab.add_child(_broadcast_edit)
	tab.add_child(_btn("Broadcast", _broadcast))


func _set_server_name() -> void:
	# Local game — server name is cosmetic only.
	pass


func _broadcast() -> void:
	# Local game — no remote peers to broadcast to.
	_broadcast_edit.text = ""


# ── Values tab ─────────────────────────────────────────────────────────────

func _build_values_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Values"
	tab.add_theme_constant_override("separation", 10)
	_tabs.add_child(tab)

	tab.add_child(_hint("Tweak live values — changes apply immediately."))
	_add_value_row(tab, "Money", 0.0, MAX_VAL, 1.0, _get_money, _set_money)
	_add_value_row(tab, "Player Rings", 0.0, MAX_VAL, 1.0, _get_rings, _set_rings)
	_add_value_row(tab, "Match Time (s)", 0.0, 999.0, 1.0, _get_match_time, _set_match_time_value)


func _add_value_row(parent: Control, label: String, min: float, max: float, step: float, getter: Callable, setter: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var sb := SpinBox.new()
	sb.min_value = min
	sb.max_value = max
	sb.step = step
	sb.value = getter.call()
	sb.custom_minimum_size = Vector2(160, 36)
	row.add_child(sb)
	row.add_child(_btn("Set", setter.bind(sb)))


func _get_money() -> float:
	var gs: Node = get_node_or_null("/root/GameState")
	return float(gs.player_money) if gs != null else 0.0


func _set_money(sb: SpinBox) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.player_money = int(sb.value)


func _get_rings() -> float:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null or gs.logged_in_username == "":
		return 0.0
	return float(gs.get_player_rings(gs.logged_in_username))


func _set_rings(sb: SpinBox) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.logged_in_username != "":
		gs.set_player_rings(gs.logged_in_username, int(sb.value))


func _get_match_time() -> float:
	var gm := _game_map()
	return gm._time_remaining if gm != null else 0.0


func _set_match_time_value(sb: SpinBox) -> void:
	_match_spin.value = sb.value
	_set_match_time()
