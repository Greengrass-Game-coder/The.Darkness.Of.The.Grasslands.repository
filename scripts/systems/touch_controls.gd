extends Node
## TouchControls — on-screen virtual joystick + buttons for phones/tablets.
##
## Registered as an autoload. Builds a transparent CanvasLayer overlay with a
## left-hand virtual joystick and a cluster of right-hand action buttons. Each
## control feeds the SAME rebindable input actions the rest of the game uses
## (move_*, confirm, cancel, sprint, pause, tetris_rotate, tetris_harddrop),
## so a phone plays exactly like a keyboard/controller player with zero
## gameplay changes. Works on both Android and iOS because it is pure Godot
## input synthesis.
##
## The overlay only appears while a touch screen is actually in use
## (InputSystem.is_touch()); plugging in a controller or using a keyboard
## hides it automatically. All controls are multi-touch and positioned by
## anchors so they adapt to any screen size / safe area.

const JOY_RADIUS := 90.0
const KNOB_RADIUS := 42.0
const BTN_RADIUS := 44.0
const DEADZONE := 0.25

var _layer: CanvasLayer
var _root: Control
var _base: Control
var _knob: Control
var _joy_touch := -1
var _buttons: Array = []          # {node, actions}
var _touch_map: Dictionary = {}   # touch index -> "joy" or "btn:<i>"

const JOY := "joy"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_apply_visibility()
	InputSystem.device_changed.connect(_on_device_changed)


func _on_device_changed(_device: String) -> void:
	_apply_visibility()


func _apply_visibility() -> void:
	if _layer != null:
		_layer.visible = InputSystem.is_touch()


## ── Build ──────────────────────────────────────────────────────────────

func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 200
	add_child(_layer)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)

	_build_joystick()
	_build_buttons()


func _build_joystick() -> void:
	_base = Control.new()
	_base.name = "JoyBase"
	_base.size = Vector2(JOY_RADIUS * 2, JOY_RADIUS * 2)
	_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_base.position = Vector2(40, -JOY_RADIUS * 2 - 70)
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.draw.connect(_draw_joy_base)
	_root.add_child(_base)

	_knob = Control.new()
	_knob.name = "JoyKnob"
	_knob.size = Vector2(KNOB_RADIUS * 2, KNOB_RADIUS * 2)
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_knob.draw.connect(_draw_joy_knob)
	_base.add_child(_knob)
	_knob.position = Vector2(JOY_RADIUS - KNOB_RADIUS, JOY_RADIUS - KNOB_RADIUS)


func _draw_joy_base() -> void:
	_base.draw_circle(Vector2(JOY_RADIUS, JOY_RADIUS), JOY_RADIUS, Color(1, 1, 1, 0.15))
	_base.draw_arc(Vector2(JOY_RADIUS, JOY_RADIUS), JOY_RADIUS - 3, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)


func _draw_joy_knob() -> void:
	_knob.draw_circle(Vector2(KNOB_RADIUS, KNOB_RADIUS), KNOB_RADIUS, Color(1, 1, 1, 0.35))
	_knob.draw_circle(Vector2(KNOB_RADIUS, KNOB_RADIUS), KNOB_RADIUS - 4, Color(1, 1, 1, 0.25))


func _build_buttons() -> void:
	var gap := 16.0
	var w := BTN_RADIUS * 2
	var dx1 := 24.0                    # rightmost column, distance from right edge
	var dx0 := dx1 + w + gap           # left column
	var base_dy := 70.0                # bottom row, distance from bottom edge
	var step := w + gap                # vertical spacing between rows

	var specs: Array = [
		{"label": "ⓐ", "actions": ["confirm", "interact"], "row": 0, "col": 1, "color": Color(0.2, 0.7, 0.4, 0.4)},
		{"label": "ⓧ", "actions": ["cancel"],              "row": 1, "col": 1, "color": Color(0.8, 0.35, 0.3, 0.4)},
		{"label": "↻", "actions": ["tetris_rotate"],       "row": 0, "col": 0, "color": Color(0.3, 0.55, 0.85, 0.4)},
		{"label": "⤓", "actions": ["tetris_harddrop"],     "row": 1, "col": 0, "color": Color(0.55, 0.4, 0.8, 0.4)},
	]
	for spec: Dictionary in specs:
		var dx: float = dx1 if spec["col"] == 1 else dx0
		var dy: float = base_dy + step * float(spec["row"])
		var node := _make_button(spec["label"], spec["color"],
			Vector2(-dx - w, -dy - w), Control.PRESET_BOTTOM_RIGHT)
		_buttons.append({"node": node, "actions": spec["actions"]})

	# Sprint: wide pill, right side above the cluster.
	var sprint_dy := base_dy + step * 2.0 + 12.0
	_buttons.append({"node": _make_pill("Sprint", Color(0.9, 0.65, 0.2, 0.4),
		Vector2(-dx1 - 90.0, -sprint_dy - 44.0), Control.PRESET_BOTTOM_RIGHT, 90.0, 44.0),
		"actions": ["sprint"]})

	# Pause: small pill, top-right corner.
	_buttons.append({"node": _make_pill("❚❚", Color(0.4, 0.4, 0.4, 0.45),
		Vector2(-dx1 - 70.0, -40.0), Control.PRESET_TOP_RIGHT, 70.0, 44.0),
		"actions": ["pause"]})


func _make_button(label: String, color: Color, pos: Vector2, anchor: int) -> Control:
	var c := Control.new()
	c.size = Vector2(BTN_RADIUS * 2, BTN_RADIUS * 2)
	c.set_anchors_preset(anchor)
	c.position = pos
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void: _draw_button_face(c, color, label))
	_root.add_child(c)
	return c


func _make_pill(label: String, color: Color, pos: Vector2, anchor: int, w: float, h: float) -> Control:
	var c := Control.new()
	c.size = Vector2(w, h)
	c.set_anchors_preset(anchor)
	c.position = pos
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void: _draw_pill_face(c, color, label))
	_root.add_child(c)
	return c


func _draw_button_face(c: Control, color: Color, label: String) -> void:
	var center := Vector2(BTN_RADIUS, BTN_RADIUS)
	c.draw_circle(center, BTN_RADIUS, color)
	c.draw_arc(center, BTN_RADIUS, 0, TAU, 40, color.lightened(0.3), 3.0)
	c.draw_string(ThemeDB.fallback_font, center + Vector2(-BTN_RADIUS * 0.5, BTN_RADIUS * 0.26), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(1, 1, 1, 0.95))


func _draw_pill_face(c: Control, color: Color, label: String) -> void:
	var size: Vector2 = c.size
	c.draw_rect(Rect2(Vector2.ZERO, size), color, true)
	c.draw_rect(Rect2(Vector2.ZERO, size), color.lightened(0.3), false, 3.0)
	c.draw_string(ThemeDB.fallback_font, Vector2(12, size.y * 0.68), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.95))


## ── Input handling ────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _layer == null or not _layer.visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_assign_touch(t.index, t.position)
		else:
			_release_touch(t.index)
	elif event is InputEventScreenDrag and _touch_map.has(event.index):
		var d := event as InputEventScreenDrag
		if _touch_map[d.index] == JOY:
			_update_joy(d.position)


func _assign_touch(index: int, pos: Vector2) -> void:
	# Buttons take priority (they sit on the right, above the joystick area).
	for i in _buttons.size():
		if _buttons[i]["node"].get_global_rect().has_point(pos):
			_touch_map[index] = "btn:%d" % i
			_press_actions(_buttons[i]["actions"])
			return
	# Otherwise start the joystick if the touch is near its base.
	if _joy_touch == -1 and _in_joy_zone(pos):
		_joy_touch = index
		_touch_map[index] = JOY
		_update_joy(pos)


func _release_touch(index: int) -> void:
	if not _touch_map.has(index):
		return
	var role: String = _touch_map[index]
	_touch_map.erase(index)
	if role == JOY:
		if _joy_touch == index:
			_joy_touch = -1
			_set_joy(Vector2.ZERO)
	elif role.begins_with("btn:"):
		var i: int = int(role.substr(4))
		if i < _buttons.size():
			_release_actions(_buttons[i]["actions"])


func _in_joy_zone(pos: Vector2) -> bool:
	var c := _base.global_position + Vector2(JOY_RADIUS, JOY_RADIUS)
	return pos.distance_to(c) <= JOY_RADIUS + 30.0


func _update_joy(pos: Vector2) -> void:
	var c := _base.global_position + Vector2(JOY_RADIUS, JOY_RADIUS)
	var v := pos - c
	if v.length() > JOY_RADIUS:
		v = v.normalized() * JOY_RADIUS
	_set_joy(v / JOY_RADIUS)


func _set_joy(v: Vector2) -> void:
	var clamped := v
	if clamped.length() < DEADZONE:
		clamped = Vector2.ZERO
	_knob.position = Vector2(JOY_RADIUS - KNOB_RADIUS, JOY_RADIUS - KNOB_RADIUS) + clamped * JOY_RADIUS
	_press_move("move_left", clamped.x < -DEADZONE)
	_press_move("move_right", clamped.x > DEADZONE)
	_press_move("move_up", clamped.y < -DEADZONE)
	_press_move("move_down", clamped.y > DEADZONE)
	# Same directions drive the Tetrino grid (soft drop = down).
	_press_move("tetris_left", clamped.x < -DEADZONE)
	_press_move("tetris_right", clamped.x > DEADZONE)
	_press_move("tetris_down", clamped.y > DEADZONE)


func _press_move(action: String, on: bool) -> void:
	if on:
		if not Input.is_action_pressed(action):
			Input.action_press(action)
	else:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _press_actions(actions: Array) -> void:
	for a: String in actions:
		Input.action_press(a)


func _release_actions(actions: Array) -> void:
	for a: String in actions:
		Input.action_release(a)
