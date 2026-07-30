class_name QueueScreen
extends CanvasLayer

## Queue/Lobby info screen.
## Shows connection status and button to enter the main lobby.

signal queue_joined()
signal queue_left()

@export var panel_position: Vector2 = Vector2(362, 240)
@export var panel_size: Vector2 = Vector2(300, 240)

var _status_label: Label = null
var _code_label: Label = null
var _player_count_label: Label = null
var _start_btn: Button = null
var _in_lobby: bool = false
var _timer: float = 0.0


func _ready() -> void:
	_build_ui()
	GameState.game_phase = "IN_LOBBY"
	
	# Connect to WebSocket server
	var nm = get_node("/root/NetworkManager")
	if is_instance_valid(nm):
		if not nm.connected_to_server.is_connected(_on_connected):
			nm.connected_to_server.connect(_on_connected)
		if not nm.connection_failed.is_connected(_on_connect_failed):
			nm.connection_failed.connect(_on_connect_failed)
		nm.connect_to_server()


func _build_ui() -> void:
	# Semi-transparent backdrop
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0, 0, 0, 0.5)
	backdrop.anchors_preset = Control.PRESET_FULL_RECT
	add_child(backdrop)
	
	# Panel background
	var bg := ColorRect.new()
	bg.name = "PanelBg"
	bg.position = panel_position
	bg.size = panel_size
	bg.color = Color(0.08, 0.08, 0.12, 0.95)
	add_child(bg)
	
	# Title
	var title := Label.new()
	title.name = "Title"
	title.text = "GAME LOBBY"
	title.position = panel_position + Vector2(0, 12)
	title.size = Vector2(panel_size.x, 32)
	title.add_theme_color_override("font_color", Color(0.9, 0.1, 0.1, 1))
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	
	# Status label
	var status := Label.new()
	status.name = "StatusLabel"
	status.text = "Connecting to server..."
	status.position = panel_position + Vector2(16, 60)
	status.size = Vector2(panel_size.x - 32, 60)
	status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	status.add_theme_font_size_override("font_size", 14)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	_status_label = status
	
	# Join code display
	var code := Label.new()
	code.name = "CodeLabel"
	code.text = "WebSocket ready"
	code.position = panel_position + Vector2(16, 90)
	code.size = Vector2(panel_size.x - 32, 30)
	code.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3, 1))
	code.add_theme_font_size_override("font_size", 18)
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(code)
	_code_label = code
	
	# Player count
	var count := Label.new()
	count.name = "PlayerCountLabel"
	count.text = "Players: 0"
	count.position = panel_position + Vector2(16, 120)
	count.size = Vector2(panel_size.x - 32, 24)
	count.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	count.add_theme_font_size_override("font_size", 12)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(count)
	_player_count_label = count
	
	# Start / Go to Lobby button
	var start_btn := Button.new()
	start_btn.name = "StartBtn"
	start_btn.text = "GO TO LOBBY"
	start_btn.position = panel_position + Vector2(50, 160)
	start_btn.size = Vector2(200, 40)
	start_btn.pressed.connect(_on_start_pressed)
	add_child(start_btn)
	_start_btn = start_btn
	
	# Listen for player list updates from NetworkManager
	var nm = get_node("/root/NetworkManager")
	if is_instance_valid(nm) and nm.has_signal("player_list_updated"):
		if not nm.player_list_updated.is_connected(_on_player_list_updated):
			nm.player_list_updated.connect(_on_player_list_updated)


func _on_connected() -> void:
	_in_lobby = true
	_status_label.text = "Connected to server!"
	_code_label.text = "Ready to play"
	_start_btn.disabled = false


func _on_connect_failed(error_msg: String) -> void:
	_status_label.text = "Connection failed: %s" % error_msg


func _on_start_pressed() -> void:
	# Transition to the main lobby scene
	queue_joined.emit()
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_player_list_updated(players: Array) -> void:
	if not is_instance_valid(_player_count_label):
		return
	_player_count_label.text = "Players: %d" % players.size()
