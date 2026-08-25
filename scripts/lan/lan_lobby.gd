class_name LanLobby
extends Control
## LAN Party lobby. Reached from the arcade console's "LAN PARTY" cartridge.
##
## One device presses HOST (the laptop), the other presses JOIN and types the
## laptop's LAN IP (shown on the laptop). Once the phone is connected, the host
## presses START and both devices load the LAN arena together.

const ARENA_SCENE: String = "res://scenes/lan_arena.tscn"
const ARCADE_SCENE: String = "res://scenes/arcade_room.tscn"

var _panel: Control
var _status: Label
var _host_btn: Button
var _join_btn: Button
var _start_btn: Button
var _back_btn: Button
var _ip_edit: LineEdit
var _ip_label: Label
var _waiting := false


func _ready() -> void:
	_build()
	LANManager.host_started.connect(_on_host_started)
	LANManager.join_started.connect(_on_join_started)
	LANManager.connected_to_host.connect(_on_connected_to_host)
	LANManager.connection_failed.connect(_on_connection_failed)
	LANManager.host_disconnected.connect(_on_host_disconnected)
	LANManager.peer_joined.connect(_on_peer_joined)
	TouchControls.set_mode(TouchControls.OVERWORLD)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.text = "LAN PARTY"
	title.position = Vector2(0, 60)
	title.size = Vector2(1280, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5, 1))
	add_child(title)

	var sub := Label.new()
	sub.text = "Play together on the same Wi-Fi — one device hosts, the other joins."
	sub.position = Vector2(0, 132)
	sub.size = Vector2(1280, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	add_child(sub)

	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(0, 0)
	_panel.size = Vector2(560, 420)
	add_child(_panel)

	_status = Label.new()
	_status.text = "Choose a role to start."
	_status.position = Vector2(0, 0)
	_status.size = Vector2(560, 40)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 24)
	_status.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	_panel.add_child(_status)

	_host_btn = _make_button("HOST GAME", Vector2(80, 60), Vector2(400, 70), Color(0.18, 0.55, 0.25, 1))
	_host_btn.pressed.connect(_on_host_pressed)
	_panel.add_child(_host_btn)

	_ip_label = Label.new()
	_ip_label.text = "JOIN — enter the host's LAN IP:"
	_ip_label.position = Vector2(80, 165)
	_ip_label.size = Vector2(400, 30)
	_ip_label.add_theme_font_size_override("font_size", 18)
	_ip_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	_panel.add_child(_ip_label)

	_ip_edit = LineEdit.new()
	_ip_edit.position = Vector2(80, 200)
	_ip_edit.size = Vector2(400, 50)
	_ip_edit.placeholder_text = "e.g. 192.168.1.5"
	_ip_edit.text = LANManager.primary_ip()
	_panel.add_child(_ip_edit)

	_join_btn = _make_button("JOIN", Vector2(80, 265), Vector2(400, 60), Color(0.18, 0.35, 0.55, 1))
	_join_btn.pressed.connect(_on_join_pressed)
	_panel.add_child(_join_btn)

	_start_btn = _make_button("START", Vector2(80, 330), Vector2(400, 60), Color(0.9, 0.7, 0.2, 1))
	_start_btn.disabled = true
	_start_btn.visible = false
	_start_btn.pressed.connect(_on_start_pressed)
	_panel.add_child(_start_btn)

	_back_btn = _make_button("BACK", Vector2(640, 640), Vector2(140, 56), Color(0.3, 0.3, 0.34, 1))
	_back_btn.pressed.connect(_on_back_pressed)
	add_child(_back_btn)

	_ip_edit.grab_focus()
	_show_idle()


func _make_button(text: String, pos: Vector2, size: Vector2, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.set_border_width_all(2)
	sb.border_color = Color(0.9, 0.9, 0.9, 0.3)
	b.add_theme_stylebox_override("normal", sb)
	return b


## ── UI states ──────────────────────────────────────────────────────

func _show_idle() -> void:
	_status.text = "Choose a role to start."
	_host_btn.visible = true
	_ip_label.visible = true
	_ip_edit.visible = true
	_join_btn.visible = true
	_start_btn.visible = false


func _show_host_waiting(ips: String) -> void:
	_status.text = "Waiting for the phone to join..."
	_host_btn.visible = false
	_ip_label.visible = true
	_ip_edit.visible = false
	_join_btn.visible = false
	_status.text += "\nYour IP: %s" % ips
	_start_btn.visible = true
	_start_btn.disabled = true
	_start_btn.text = "START (waiting...)"


func _show_connecting() -> void:
	_status.text = "Connecting..."
	_host_btn.visible = false
	_ip_label.visible = true
	_ip_edit.visible = false
	_join_btn.visible = false
	_start_btn.visible = false


func _show_connected_guest() -> void:
	_status.text = "Connected to host! Waiting for the host to start..."
	_start_btn.visible = false


## ── Actions ────────────────────────────────────────────────────────

func _on_host_pressed() -> void:
	var err: Error = LANManager.host()
	if err != OK:
		_status.text = "Could not host (%s)" % error_string(err)
		return
	_show_host_waiting(LANManager.display_ips())


func _on_join_pressed() -> void:
	_show_connecting()
	var err: Error = LANManager.join(_ip_edit.text)
	if err != OK:
		_show_idle()
		_status.text = "Could not join (%s)" % error_string(err)


func _on_start_pressed() -> void:
	_start_arena.rpc()


@rpc("any_peer", "call_local", "reliable")
func _start_arena() -> void:
	get_tree().change_scene_to_file(ARENA_SCENE)


func _on_back_pressed() -> void:
	LANManager.stop()
	get_tree().change_scene_to_file(ARCADE_SCENE)


## ── LANManager signal handlers ─────────────────────────────────────

func _on_host_started(_ips: Array) -> void:
	pass  # UI already set by _on_host_pressed


func _on_join_started() -> void:
	_show_connecting()


func _on_connected_to_host() -> void:
	_show_connected_guest()


func _on_connection_failed() -> void:
	_show_idle()
	_status.text = "Connection failed — check the IP and that both devices are on the same Wi-Fi."


func _on_host_disconnected() -> void:
	LANManager.stop()
	_show_idle()
	_status.text = "Connection lost."


func _on_peer_joined(_peer_id: int) -> void:
	_start_btn.disabled = false
	_start_btn.text = "START"


func _exit_tree() -> void:
	LANManager.stop()
