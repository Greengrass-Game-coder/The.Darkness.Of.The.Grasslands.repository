extends Node
## TouchControls — context-aware, player-repositionable on-screen controls.
##
## Autoload. Draws a transparent CanvasLayer with a virtual joystick and a set
## of clearly-labelled action buttons. Each mode (overworld / browser / tetris /
## minesweeper) shows only the controls it needs. Every button feeds the same
## rebindable actions the rest of the game uses (move_*, confirm, cancel,
## sprint, pause, tetris_rotate, tetris_harddrop, flag), so a phone plays
## exactly like a keyboard/controller player. The overlay only appears while a
## touch screen is actually in use (InputSystem.is_touch()).
##
## LAYOUT EDITING: tap the small "⚙" button (bottom-centre) to enter edit mode
## and drag any control wherever you like. Controls can never be dragged into
## the top strip of the screen (TOP_SAFE), which is reserved for the phone's
## status bar / notch / notifications. The layout is saved to
## user://touch_layout.cfg and remembered on this device across runs.

signal swipe(dir: Vector2)   # browser mode: a drag crossed the threshold
signal tap()                 # browser mode: a quick tap on empty space

const OVERWORLD := "overworld"
const BROWSER := "browser"
const TETRIS := "tetris"
const MINESWEEPER := "minesweeper"

const JOY_RADIUS := 90.0
const KNOB_RADIUS := 42.0
const DEADZONE := 0.25

const BTN_W := 118.0
const BTN_H := 58.0

const SWIPE_THRESHOLD := 60.0   # px of drag before a swipe fires
const TAP_DRIFT := 40.0         # px of drift that still counts as a tap
const TAP_TIME := 350           # ms for a press to count as a tap

const JOY := "joy"
const LAYOUT_PATH := "user://touch_layout.cfg"

# Top fraction of the screen reserved for the phone's status bar, notch and
# notifications. Controls can never be dragged above this line.
const TOP_SAFE := 0.16
const MIN_NORM := Vector2(0.05, TOP_SAFE)
const MAX_NORM := Vector2(0.95, 0.90)

var _layer: CanvasLayer
var _root: Control
var _base: Control
var _knob: Control
var _joy_touch := -1
var _buttons: Array = []          # {id, node, actions, modes, norm, accent}
var _touch_map: Dictionary = {}   # touch index -> "joy" | "btn:<i>" | "drag"

var _joy_norm := Vector2(0.12, 0.78)
var _edit_norm := Vector2(0.5, 0.90)
var _edit_btn: Button
var _hint: Label

var _mode: String = OVERWORLD
var _editing := false

# Edit-drag state.
var _drag_touch := -1     # touch index currently dragging (>=0), or -1
var _drag_mouse := false  # mouse is dragging (desktop testing)
var _drag_index := -1     # which button is being dragged (-1 = none)
var _drag_joy := false    # dragging the joystick instead of a button

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
	get_viewport().size_changed.connect(_layout)


func _on_device_changed(_device: String) -> void:
	_apply_visibility()


func _apply_visibility() -> void:
	if _layer == null:
		return
	_layer.visible = InputSystem.is_touch()
	if not _layer.visible:
		if _editing:
			_exit_edit()
		return
	# Joystick shows everywhere except the drag-navigate browser.
	if _base != null:
		_base.visible = _mode != BROWSER
	for b: Dictionary in _buttons:
		b["node"].visible = _mode in b["modes"]
	if _edit_btn != null:
		_edit_btn.visible = _mode != BROWSER
	if _hint != null:
		_hint.visible = _editing and _mode != BROWSER


## Set which control layout is shown. Call from scenes on state transitions.
func set_mode(mode: String) -> void:
	if mode == _mode:
		return
	_mode = mode
	# Clear any in-flight browser gesture when switching modes.
	_b_touch = -1
	_b_swiped = false
	if _editing and mode == BROWSER:
		_exit_edit()
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
	_build_edit_controls()
	_load_layout()
	_layout()


func _build_joystick() -> void:
	_base = Control.new()
	_base.name = "JoyBase"
	_base.size = Vector2(JOY_RADIUS * 2, JOY_RADIUS * 2)
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


const GREEN := Color(0.35, 0.72, 0.42, 0.6)
const RED := Color(0.8, 0.38, 0.32, 0.6)
const BLUE := Color(0.36, 0.58, 0.82, 0.6)
const PURPLE := Color(0.6, 0.46, 0.82, 0.6)
const YELLOW := Color(0.85, 0.7, 0.3, 0.6)
const NEUTRAL := Color(0.55, 0.55, 0.62, 0.6)


func _build_buttons() -> void:
	# --- Overworld: joystick + a right-side cluster + a top-left MENU. ---
	# All defaults live BELOW TOP_SAFE so nothing overlaps the notifications.
	_add_pill("ovw_ok", "OK", ["confirm", "interact"], [OVERWORLD],
		Vector2(0.74, 0.82), GREEN)
	_add_pill("ovw_back", "BACK", ["cancel"], [OVERWORLD],
		Vector2(0.74, 0.72), RED)
	_add_pill("ovw_sprint", "SPRINT", ["sprint"], [OVERWORLD],
		Vector2(0.74, 0.62), NEUTRAL)
	_add_pill("ovw_menu", "MENU", ["pause"], [OVERWORLD],
		Vector2(0.05, 0.18), NEUTRAL)

	# --- Tetris (Tetrivo): joystick moves; dedicated action buttons. ---
	_add_pill("tet_drop", "DROP", ["tetris_harddrop"], [TETRIS],
		Vector2(0.74, 0.82), BLUE)
	_add_pill("tet_rotate", "ROTATE", ["tetris_rotate"], [TETRIS],
		Vector2(0.74, 0.72), PURPLE)
	_add_pill("tet_ok", "OK", ["confirm"], [TETRIS],
		Vector2(0.74, 0.62), GREEN)
	_add_pill("tet_back", "BACK", ["cancel"], [TETRIS],
		Vector2(0.05, 0.18), RED)

	# --- Minesweeper (Dirtysweeper): joystick moves the cursor. ---
	_add_pill("ms_reveal", "REVEAL", ["confirm"], [MINESWEEPER],
		Vector2(0.74, 0.82), GREEN)
	_add_pill("ms_flag", "FLAG", ["flag"], [MINESWEEPER],
		Vector2(0.74, 0.72), YELLOW)
	_add_pill("ms_back", "BACK", ["cancel"], [MINESWEEPER],
		Vector2(0.05, 0.18), RED)

	# --- Browser: drag/tap navigation handled in _input; just a BACK. ---
	_add_pill("br_back", "BACK", ["cancel"], [BROWSER],
		Vector2(0.05, 0.18), RED)


func _add_pill(id: String, label: String, actions: Array, modes: Array, norm: Vector2, accent: Color) -> void:
	var c := Control.new()
	c.name = "Btn_" + id
	c.size = Vector2(BTN_W, BTN_H)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void: _draw_pill_face(c, label, accent))
	_root.add_child(c)
	_buttons.append({
		"id": id, "node": c, "actions": actions, "modes": modes,
		"norm": _clamp_norm(norm), "accent": accent
	})


func _draw_pill_face(c: Control, label: String, accent: Color) -> void:
	var size: Vector2 = c.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.12, 0.72)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = accent.lightened(0.15)
	if _editing:
		sb.bg_color = Color(0.16, 0.16, 0.22, 0.88)
		sb.set_border_width_all(3)
		sb.border_color = Color(1, 1, 1, 0.95)
	c.draw_style_box(sb, Rect2(Vector2.ZERO, size))
	c.draw_string(ThemeDB.fallback_font, Vector2(0, size.y * 0.62), label,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color(1, 1, 1, 0.95))


func _build_edit_controls() -> void:
	_hint = Label.new()
	_hint.name = "EditHint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.visible = false
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_hint.add_theme_constant_override("outline_size", 6)
	_root.add_child(_hint)

	_edit_btn = Button.new()
	_edit_btn.name = "EditBtn"
	_edit_btn.text = "⚙"
	_edit_btn.add_theme_font_size_override("font_size", 24)
	_edit_btn.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.15, 0.6)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.35)
	_edit_btn.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate()
	sb_h.bg_color = Color(0.2, 0.2, 0.25, 0.8)
	_edit_btn.add_theme_stylebox_override("hover", sb_h)
	_edit_btn.add_theme_stylebox_override("pressed", sb_h)
	_edit_btn.pressed.connect(_toggle_edit)
	_root.add_child(_edit_btn)


## ── Positioning (normalized → pixels) ─────────────────────────────────

func _layout() -> void:
	if _root == null:
		return
	var vs := get_viewport().get_visible_rect().size
	if vs.x <= 0 or vs.y <= 0:
		return
	for b: Dictionary in _buttons:
		b["node"].position = b["norm"] * vs
	if _base != null:
		_base.position = _joy_norm * vs
	if _edit_btn != null:
		_edit_btn.position = _edit_norm * vs
		_edit_btn.size = Vector2(84, 44)
	if _hint != null:
		_hint.position = Vector2(0, TOP_SAFE * vs.y + 4)
		_hint.size = Vector2(vs.x, 40)


func _clamp_norm(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, MIN_NORM.x, MAX_NORM.x),
		clampf(p.y, MIN_NORM.y, MAX_NORM.y)
	)


func _load_layout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_PATH) != OK:
		return
	for b: Dictionary in _buttons:
		if cfg.has_section_key("layout", b["id"]):
			b["norm"] = _clamp_norm(cfg.get_value("layout", b["id"], b["norm"]))
	_joy_norm = _clamp_norm(cfg.get_value("layout", "joy", _joy_norm))


func _save_layout() -> void:
	var cfg := ConfigFile.new()
	for b: Dictionary in _buttons:
		cfg.set_value("layout", b["id"], b["norm"])
	cfg.set_value("layout", "joy", _joy_norm)
	cfg.save(LAYOUT_PATH)


## ── Layout editing ────────────────────────────────────────────────────

func _toggle_edit() -> void:
	if _editing:
		_exit_edit()
	else:
		_enter_edit()


func _enter_edit() -> void:
	_editing = true
	_clear_touches()
	_edit_btn.text = "✓"
	_hint.text = "Drag the buttons where you like — they stay out of the top notification area."
	_hint.visible = true
	for b: Dictionary in _buttons:
		b["node"].queue_redraw()


func _exit_edit() -> void:
	_editing = false
	_clear_touches()
	_edit_btn.text = "⚙"
	_hint.visible = false
	_save_layout()
	for b: Dictionary in _buttons:
		b["node"].queue_redraw()


func _clear_touches() -> void:
	for k in _touch_map.keys():
		var role: String = _touch_map[k]
		if role == JOY:
			_joy_touch = -1
			_set_joy(Vector2.ZERO)
		elif role.begins_with("btn:"):
			var i: int = int(role.substr(4))
			if i < _buttons.size():
				_release_actions(_buttons[i]["actions"])
	_touch_map.clear()
	_drag_touch = -1
	_drag_mouse = false
	_drag_index = -1
	_drag_joy = false


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
	if _editing:
		_handle_edit_input(event)
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


func _handle_edit_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_begin_edit_drag(t.index, t.position)
		else:
			_end_edit_drag(t.index)
	elif event is InputEventScreenDrag and not _drag_mouse and _drag_touch == event.index:
		_move_edit_drag(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_edit_drag(-1, event.position)
		else:
			_end_edit_drag(-1)
	elif event is InputEventMouseMotion and _drag_mouse:
		_move_edit_drag(event.position)
		get_viewport().set_input_as_handled()


func _begin_edit_drag(index: int, pos: Vector2) -> void:
	for i in _buttons.size():
		var b: Dictionary = _buttons[i]
		if _mode in b["modes"] and b["node"].get_global_rect().has_point(pos):
			if index >= 0:
				_drag_touch = index
				_touch_map[index] = "drag"
			else:
				_drag_mouse = true
			_drag_index = i
			_drag_joy = false
			get_viewport().set_input_as_handled()
			return
	# Not on a button — try the joystick.
	if _in_joy_zone(pos):
		if index >= 0:
			_drag_touch = index
			_touch_map[index] = "drag"
		else:
			_drag_mouse = true
		_drag_index = -1
		_drag_joy = true
		get_viewport().set_input_as_handled()


func _move_edit_drag(pos: Vector2) -> void:
	var vs := get_viewport().get_visible_rect().size
	if vs.x <= 0 or vs.y <= 0:
		return
	var p := _clamp_norm(pos / vs)
	if _drag_joy:
		_joy_norm = p
		_base.position = p * vs
	elif _drag_index >= 0 and _drag_index < _buttons.size():
		var b: Dictionary = _buttons[_drag_index]
		b["norm"] = p
		b["node"].position = p * vs
		b["node"].queue_redraw()


func _end_edit_drag(index: int) -> void:
	if _drag_mouse:
		_drag_mouse = false
		_drag_index = -1
		_drag_joy = false
	elif _drag_touch == index:
		_drag_touch = -1
		_drag_index = -1
		_drag_joy = false
		_touch_map.erase(index)


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
	# Same directions drive the Tetrivo grid (soft drop = down).
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
