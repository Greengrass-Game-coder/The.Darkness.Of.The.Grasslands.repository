class_name QueueScreen
extends CanvasLayer

## Queue system UI — handles matchmaking queue display,
## join/cancel flow, and auto-joining ongoing matches.

signal queue_joined()
signal queue_left()
signal match_found()

@export var panel_position: Vector2 = Vector2(362, 240)
@export var panel_size: Vector2 = Vector2(300, 240)

var _status_label: Label = null
var _queue_btn: Button = null
var _cancel_btn: Button = null
var _player_count_label: Label = null
var _in_queue: bool = false
var _timer: float = 0.0


func _ready() -> void:
	_build_ui()
	GameState.game_phase = "IN_QUEUE"
	
	# Listen for match found
	var nm: Node = Engine.get_singleton("NetworkManager")
	if is_instance_valid(nm) and nm.has_signal("match_found"):
		if not nm.match_found.is_connected(_on_match_found):
			nm.match_found.connect(_on_match_found)


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
	title.text = "FIND MATCH"
	title.position = panel_position + Vector2(0, 12)
	title.size = Vector2(panel_size.x, 32)
	title.add_theme_color_override("font_color", Color(0.9, 0.1, 0.1, 1))
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	
	# Status label
	var status := Label.new()
	status.name = "StatusLabel"
	status.text = "Ready to play.\nSearching for opponents..."
	status.position = panel_position + Vector2(16, 60)
	status.size = Vector2(panel_size.x - 32, 60)
	status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	status.add_theme_font_size_override("font_size", 14)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	_status_label = status
	
	# Player count
	var count := Label.new()
	count.name = "PlayerCountLabel"
	count.text = "Players in queue: 0"
	count.position = panel_position + Vector2(16, 120)
	count.size = Vector2(panel_size.x - 32, 24)
	count.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	count.add_theme_font_size_override("font_size", 12)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(count)
	_player_count_label = count
	
	# Ongoing match indicator
	if GameState.match_in_progress:
		status.text = "Match in progress!\nJoining..."
		status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3, 1))
	
	# Join queue button
	var join_btn := Button.new()
	join_btn.name = "JoinBtn"
	join_btn.text = "FIND GAME"
	join_btn.position = panel_position + Vector2(50, 160)
	join_btn.size = Vector2(200, 40)
	join_btn.pressed.connect(_on_join_pressed)
	add_child(join_btn)
	_queue_btn = join_btn
	
	# Cancel button (hidden by default)
	var cancel_btn := Button.new()
	cancel_btn.name = "CancelBtn"
	cancel_btn.text = "CANCEL"
	cancel_btn.position = panel_position + Vector2(90, 160)
	cancel_btn.size = Vector2(120, 40)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	cancel_btn.hide()
	add_child(cancel_btn)
	_cancel_btn = cancel_btn
	
	# Listen for queue updates from NetworkManager
	var nm2 = Engine.get_singleton("NetworkManager")
	if is_instance_valid(nm2) and nm2.has_signal("player_list_updated"):
		if not nm2.player_list_updated.is_connected(_on_queue_player_list):
			nm2.player_list_updated.connect(_on_queue_player_list)
	
	# If match is in progress, auto-join
	if GameState.match_in_progress:
		_on_join_pressed()


func _process(delta: float) -> void:
	if _in_queue:
		_timer += delta
		var elapsed: int = int(_timer)
		var dots: String = ""
		for i in range(elapsed % 4):
			dots += "."
		_status_label.text = "Searching%s\nLooking for match..." % dots


func _on_join_pressed() -> void:
	"""Join the matchmaking queue."""
	_in_queue = true
	_timer = 0.0
	_queue_btn.hide()
	_cancel_btn.show()
	_status_label.text = "Searching\nJoining queue..."
	GameState.game_phase = "IN_QUEUE"
	
	var nm3 = Engine.get_singleton("NetworkManager")
	if is_instance_valid(nm3) and nm3.has_method("join_queue"):
		nm3.join_queue()
	queue_joined.emit()


func _on_cancel_pressed() -> void:
	"""Leave the queue."""
	_in_queue = false
	_queue_btn.show()
	_cancel_btn.hide()
	_status_label.text = "Ready to play.\nSearching for opponents..."
	GameState.match_in_progress = false
	
	var nm4 = Engine.get_singleton("NetworkManager")
	if is_instance_valid(nm4) and nm4.has_method("leave_queue"):
		nm4.leave_queue()
	queue_left.emit()


func _on_match_found(_match_data: Dictionary) -> void:
	"""Match found! Transition to game."""
	_in_queue = false
	_status_label.text = "MATCH FOUND!\nLoading..."
	_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
	
	GameState.game_phase = "ON_MATCH"
	match_found.emit()
	
	# Small delay then transition
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/game_map.tscn")


func _on_queue_player_list(players: Array) -> void:
	"""Update player count from server."""
	if not is_instance_valid(_player_count_label):
		return
	_player_count_label.text = "Players in queue: %d" % players.size()
