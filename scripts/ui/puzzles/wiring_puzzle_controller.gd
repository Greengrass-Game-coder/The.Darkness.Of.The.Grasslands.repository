class_name WiringPuzzleController
extends Node

## Wiring puzzle controller ----- drag-and-drop.
## Press and drag from a left wire to its matching right plug.

var left_wires: Array[TextureRect] = []
var left_buttons: Array[Button] = []
var right_buttons: Array[Button] = []
var left_colors: Array[Color] = []
var right_colors: Array[Color] = []
var right_matches: Array[int] = []  # For each left index, which right index matches
var wire_count: int = 2
var panel_ref: Control = null
var solved_callback: Callable = Callable()
var cancelled_callback: Callable = Callable()

var _connected: Array[bool] = []
var _connection_lines: Array[ColorRect] = []
var _drag_active: bool = false
var _drag_wire_idx: int = -1
var _drag_line: Line2D = null
var _panel_pos: Vector2 = Vector2(400, 180)
var _hovered_plug: int = -1  # Index of right plug currently hovered, -1 if none

func start() -> void:
	"""Initialize the wiring puzzle."""
	_connected = []
	_connected.resize(wire_count)
	for i in range(wire_count):
		_connected[i] = false
	
	# Connect drag signals (disconnect first to prevent duplicates if start() called twice)
	for i in range(wire_count):
		if left_buttons[i].button_down.is_connected(_on_wire_press):
			left_buttons[i].button_down.disconnect(_on_wire_press)
		if left_buttons[i].button_up.is_connected(_on_wire_release):
			left_buttons[i].button_up.disconnect(_on_wire_release)
		if right_buttons[i].mouse_entered.is_connected(_on_plug_hovered):
			right_buttons[i].mouse_entered.disconnect(_on_plug_hovered)
		if right_buttons[i].mouse_exited.is_connected(_on_plug_unhovered):
			right_buttons[i].mouse_exited.disconnect(_on_plug_unhovered)
		
		left_buttons[i].button_down.connect(_on_wire_press.bind(i))
		left_buttons[i].button_up.connect(_on_wire_release)
		# Track mouse hover on right plugs for drop detection
		right_buttons[i].mouse_entered.connect(_on_plug_hovered.bind(i))
		right_buttons[i].mouse_exited.connect(_on_plug_unhovered)
	
	# Create drag line (hidden initially)
	_drag_line = Line2D.new()
	_drag_line.name = "DragLine"
	_drag_line.width = 3.0
	_drag_line.default_color = Color(1, 1, 1, 0.7)
	_drag_line.add_point(Vector2.ZERO)
	_drag_line.add_point(Vector2.ZERO)
	_drag_line.visible = false
	panel_ref.add_child(_drag_line)


func _on_wire_press(idx: int) -> void:
	"""Start dragging from a wire."""
	if _connected[idx]:
		return
	_drag_active = true
	_drag_wire_idx = idx
	_hovered_plug = -1
	_drag_line.visible = true
	_drag_line.default_color = left_colors[idx]
	var wire_y: float = _get_wire_center_y(idx)
	# Set both points at the wire start position initially (end follows cursor)
	_drag_line.set_point_position(0, Vector2(190, wire_y))
	_drag_line.set_point_position(1, Vector2(190, wire_y))


func _on_plug_hovered(plug_idx: int) -> void:
	"""Mouse entered a right plug while dragging."""
	if _drag_active and _drag_wire_idx >= 0:
		_hovered_plug = plug_idx


func _on_plug_unhovered() -> void:
	"""Mouse left a right plug."""
	if _drag_active:
		_hovered_plug = -1


func _on_wire_release() -> void:
	"""Drop wire on the currently hovered plug, or cancel."""
	if not _drag_active:
		return
	
	var wire_idx: int = _drag_wire_idx
	_drag_active = false
	_drag_line.visible = false
	
	if wire_idx < 0 or _connected[wire_idx]:
		_drag_wire_idx = -1
		return
	
	# Check if we're hovering over a plug
	if _hovered_plug >= 0:
		var plug_idx: int = _hovered_plug
		_hovered_plug = -1
		
		if right_matches[wire_idx] == plug_idx:
			_connect_wire(wire_idx, plug_idx)
		else:
			# Wrong - flash red briefly
			right_buttons[plug_idx].modulate = Color(0.9, 0.2, 0.2, 1)
			await get_tree().create_timer(0.3).timeout
			if is_instance_valid(right_buttons[plug_idx]) and not _connected[wire_idx]:
				right_buttons[plug_idx].modulate = Color(1, 1, 1, 1)
	
	_drag_wire_idx = -1


func _connect_wire(wire_idx: int, plug_idx: int) -> void:
	"""Connect a wire to its matching plug."""
	_connected[wire_idx] = true
	
	# Update left wire appearance
	var left_label: Label = left_wires[wire_idx].get_child(0) if left_wires[wire_idx].get_child_count() > 0 else null
	if left_label:
		left_label.text = "-...- Wire %d" % (wire_idx + 1)
	left_wires[wire_idx].modulate = Color(0.3, 0.9, 0.3, 1)
	
	# Update right plug appearance
	right_buttons[plug_idx].disabled = true
	right_buttons[plug_idx].modulate = Color(0.3, 0.9, 0.3, 1)
	var dot: ColorRect = right_buttons[plug_idx].get_node_or_null("Dot")
	if dot:
		dot.color = Color(0.3, 0.9, 0.3, 1)
	
	_draw_connection(wire_idx, plug_idx)
	_drag_wire_idx = -1
	
	if _all_connected():
		await get_tree().create_timer(0.5).timeout
		if solved_callback.is_valid():
			solved_callback.call()


func _process(_delta: float) -> void:
	"""Update drag line while dragging ----- follow cursor."""
	if not _drag_active or _drag_wire_idx < 0 or not _drag_line.visible:
		return
	
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	# Derive panel position dynamically from panel_ref to stay in sync
	var panel_pos: Vector2 = panel_ref.global_position if panel_ref else _panel_pos
	var local_mouse: Vector2 = mouse_pos - panel_pos
	var wire_y: float = _get_wire_center_y(_drag_wire_idx)
	# Keep start at wire position, move end to cursor
	_drag_line.set_point_position(0, Vector2(190, wire_y))
	_drag_line.set_point_position(1, Vector2(local_mouse.x, local_mouse.y))


func _draw_connection(wire_idx: int, _plug_idx: int) -> void:
	"""Draw a permanent connection line."""
	var line := ColorRect.new()
	line.name = "Connection_%d" % wire_idx
	line.size = Vector2(90, 3)
	line.position = Vector2(190, _get_wire_center_y(wire_idx))
	line.color = left_colors[wire_idx]
	panel_ref.add_child(line)
	_connection_lines.append(line)


func _get_wire_center_y(idx: int) -> float:
	"""Get Y center of wire/plug at given index."""
	var wire_h: float = 32.0
	var gap: float = 8.0
	var total_h: float = wire_count * (wire_h + gap) - gap
	var start_y: float = (panel_ref.size.y - total_h - 60) * 0.5 + 70 + wire_h * 0.5
	return start_y + idx * (wire_h + gap)


func _all_connected() -> bool:
	for c in _connected:
		if not c:
			return false
	return true
