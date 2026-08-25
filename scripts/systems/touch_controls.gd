extends Node
## TouchControls — context-aware on-screen controls for phones/tablets.
##
## Registered as an autoload. Builds a transparent CanvasLayer overlay with a
## left-hand virtual joystick and a small cluster of clearly-labelled action
## buttons. It adapts to the current game mode so each screen shows only the
## controls it needs, with plain text labels (no cryptic symbols) and a
## low-key visual style.
##
## Modes:
##   overworld   — walking around a room: joystick + OK/BACK/SPRINT/MENU
##   browser     — arcade console browser: DRAG to navigate, TAP to launch
##                 (emits swipe/tap signals); a small BACK button
##   tetris      — Tetrino (menu + gameplay): joystick + DROP/ROTATE/OK/BACK
##   minesweeper — Dirtysweeper: joystick + REVEAL/FLAG/BACK
##
## Every button feeds the SAME rebindable actions the rest of the game uses
## (move_*, confirm, cancel, sprint, pause, tetris_rotate, tetris_harddrop,
## flag), so a phone plays exactly like a keyboard/controller player. Pure
## Godot input synthesis — works on Android and iOS.
##
## The overlay only appears while a touch screen is actually in use
## (InputSystem.is_touch()); plugging in a controller or a keyboard hides it.

signal swipe(dir: Vector2)   # browser mode: a drag crossed the threshold
signal tap()                 # browser mode: a quick tap on empty space

const OVERWORLD := "overworld"
const BROWSER := "browser"
const TETRIS := "tetris"
const MINESWEEPER := "minesweeper"

const JOY_RADIUS := 90.0
const KNOB_RADIUS := 42.0
const DEADZONE := 0.25

const BTN_W := 110.0
const BTN_H := 54.0
const GAP := 12.0

const SWIPE_THRESHOLD := 60.0   # px of drag before a swipe fires
const TAP_DRIFT := 40.0         # px of drift that still counts as a tap
const TAP_TIME := 350           # ms for a press to count as a tap

const JOY := "joy"

var _layer: CanvasLayer
var _root: Control
var _base: Control
var _knob: Control
var _joy_touch := -1
var _buttons: Array = []          # {node, actions, modes}
var _touch_map: Dictionary = {}   # touch index -> "joy" | "btn:<i>"

var _mode: String = OVERWORLD

# Browser drag/tap gesture state.
var _b_touch := -1
var _b_start := Vector2.ZERO
var _b_time := 0
var _b_swiped := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_apply_visibility()
	InputSystem.device_changed.connect(_on_device_changed)


func _on_device_changed(_device: String) -> void:
	_apply_visibility()


func _apply_visibility() -> void:
	if _layer == null:
		return
	_layer.visible = InputSystem.is_touch()
	if not _layer.visible:
		return
	# Joystick shows everywhere except the drag-navigate browser.
	if _base != null:
		_base.visible = _mode != BROWSER
	for b: Dictionary in _buttons:
		b["node"].visible = _mode in b["modes"]


## Set which control layout is shown. Call from scenes on state transitions.
func set_mode(mode: String) -> void:
	if mode == _mode:
		return
	_mode = mode
	# Clear any in-flight browser gesture when switching modes.
	_b_touch = -1
	_b_swiped = false
	_apply_visibility()


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
	_base.position = Vector2(30, -JOY_RADIUS * 2 - 54)
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
	_base.draw_circle(Vector2(JOY_RADIUS, JOY_RADIUS), JOY_RADIUS, Color(1, 1, 1, 0.08))
	_base.draw_arc(Vector2(JOY_RADIUS, JOY_RADIUS), JOY_RADIUS - 3, 0, TAU, 48, Color(1, 1, 1, 0.20), 2.0)


func _draw_joy_knob() -> void:
	_knob.draw_circle(Vector2(KNOB_RADIUS, KNOB_RADIUS), KNOB_RADIUS, Color(1, 1, 1, 0.22))
	_knob.draw_circle(Vector2(KNOB_RADIUS, KNOB_RADIUS), KNOB_RADIUS - 5, Color(1, 1, 1, 0.16))


const GREEN := Color(0.35, 0.72, 0.42, 0.55)
const RED := Color(0.8, 0.38, 0.32, 0.55)
const BLUE := Color(0.36, 0.58, 0.82, 0.55)
const PURPLE := Color(0.6, 0.46, 0.82, 0.55)
const YELLOW := Color(0.85, 0.7, 0.3, 0.55)
const NEUTRAL := Color(0.55, 0.55, 0.62, 0.55)


func _build_buttons() -> void:
	# --- Overworld: joystick + a small right-side cluster + a small menu. ---
	_add_pill("OK", ["confirm", "interact"], [OVERWORLD],
		Control.PRESET_BOTTOM_RIGHT, Vector2(-(24 + BTN_W), -(24 + BTN_H)), BTN_W, BTN_H, GREEN)
	_add_pill("BACK", ["cancel"], [OVERWORLD],
		Control.PRESET_BOTTOM_RIGHT, Vector2(-(24 + BTN_W), -(24 + BTN_H + GAP) - BTN_H), BTN_W, BTN_H, RED)
	_add_pill("SPRINT", ["sprint"], [OVERWORLD],
		Control.PRESET_BOTTOM_RIGHT, Vector2(-(24 + BTN_W), -(24 + BTN_H + GAP + BTN_H + GAP) - BTN_H), BTN_W, BTN_H, NEUTRAL)
	_add_pill("MENU", ["pause"], [OVERWORLD],
		Control.PRESET_CENTER_TOP, Vector2(-40, 18), 80, 40, NEUTRAL)

	# --- Tetris (Tetrino): joystick moves; dedicated action buttons. ---
	_add_pill("DROP", ["tetris_harddrop"], [TETRIS],
		Control.PRESET_BOTTOM_RIGHT, Vector2(-(24 + BTN_W), -(24 + BTN_H)), BTN_W, BTN_H, BLUE)
	_add_pill("ROTATE", ["tetris_rotate"], [TETRIS],
		Control.PRESET_BOTTOM_RIGHT, Vector2(-(24 + BTN_W), -(24 + BTN_H + GAP) - BTN_H), BTN_W, BTN_H, PURPLE)
	_add_pill("OK", ["confirm"], [TETRIS],
		Control.PRESET_BOTTOM_RIGHT, Vector2(-(24 + BTN_W), -(24 + BTN_H + GAP + BTN_H + GAP) - BTN_H), BTN_W, BTN_H, GREEN)
	_add_pill("BACK", ["cancel"], [TETRIS],
		Control.PRESET_TOP_LEFT, Vector2(24, 18), 80, 40, RED)

	# --- Minesweeper (Dirtysweeper): joystick moves the cursor. ---
	_add_pill("REVEAL", ["confirm"], [MINESWEEPER],
		Control.PRESET_BOTTOM_RIGHT, Vector2(-(24 + BTN_W), -(24 + BTN_H)), BTN_W, BTN_H, GREEN)
	_add_pill("FLAG", ["flag"], [MINESWEEPER],
		Control.PRESET_BOTTOM_RIGHT, Vector2(-(24 + BTN_W), -(24 + BTN_H + GAP) - BTN_H), BTN_W, BTN_H, YELLOW)
	_add_pill("BACK", ["cancel"], [MINESWEEPER],
		Control.PRESET_TOP_LEFT, Vector2(24, 18), 80, 40, RED)

	# --- Browser: drag/tap navigation handled in _input; just a BACK. ---
	_add_pill("BACK", ["cancel"], [BROWSER],
		Control.PRESET_TOP_LEFT, Vector2(24, 18), 80, 40, RED)


func _add_pill(label: String, actions: Array, modes: Array, anchor: int, pos: Vector2, w: float, h: float, accent: Color) -> void:
	var c := Control.new()
	c.name = "Btn_" + label
	c.size = Vector2(w, h)
	c.set_anchors_preset(anchor)
	c.position = pos
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void: _draw_pill_face(c, label, accent))
	_root.add_child(c)
	_buttons.append({"node": c, "actions": actions, "modes": modes})


func _draw_pill_face(c: Control, label: String, accent: Color) -> void:
	var size: Vector2 = c.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.13, 0.62)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = accent.lightened(0.1)
	c.draw_style_box(sb, Rect2(Vector2.ZERO, size))
	c.draw_string(ThemeDB.fallback_font, Vector2(0, size.y * 0.62), label,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(1, 1, 1, 0.95))


## ── Input handling ────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _layer == null or not _layer.visible:
		return
	if _mode == BROWSER:
		# Only touch events are owned by the browser drag; keyboard/controller
		# (WASD, Enter) pass through to the browser's own handling.
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			_handle_browser_touch(event)
			get_viewport().set_input_as_handled()
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


func _handle_browser_touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			# Buttons (BACK) take priority over the drag gesture.
			for i in _buttons.size():
				if _buttons[i]["node"].get_global_rect().has_point(t.position):
					_touch_map[t.index] = "btn:%d" % i
					_press_actions(_buttons[i]["actions"])
					return
			if _b_touch == -1:
				_b_touch = t.index
				_b_start = t.position
				_b_time = Time.get_ticks_msec()
				_b_swiped = false
		else:
			if _touch_map.has(t.index):
				_release_touch(t.index)
				return
			if t.index == _b_touch:
				var d: Vector2 = t.position - _b_start
				var dt: int = Time.get_ticks_msec() - _b_time
				if not _b_swiped and d.length() <= TAP_DRIFT and dt <= TAP_TIME:
					tap.emit()
				_b_touch = -1
	elif event is InputEventScreenDrag and event.index == _b_touch and not _b_swiped:
		var d: Vector2 = event.position - _b_start
		if d.length() >= SWIPE_THRESHOLD:
			_b_swiped = true
			swipe.emit(d.normalized())


func _assign_touch(index: int, pos: Vector2) -> void:
	for i in _buttons.size():
		if _buttons[i]["node"].get_global_rect().has_point(pos):
			_touch_map[index] = "btn:%d" % i
			_press_actions(_buttons[i]["actions"])
			return
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
