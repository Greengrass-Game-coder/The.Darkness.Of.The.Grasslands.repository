extends Node
## Central input system for the whole game.
##
## Owns every rebindable action and its keyboard + gamepad bindings, detects
## which input device the player is currently using (so UI can show the right
## prompts), and lets the player rebind keyboard keys and gamepad buttons
## independently — rebinding one device never wipes the other.
##
## Devices detected: "keyboard", "gamepad", and "touch" (phones / tablets).
## Everything is persisted to user://keybinds.cfg and applied at startup, so
## the player's bindings survive restarts. Gameplay code should poll these
## actions via is_pressed()/just_pressed() instead of hard-coding raw keys.

signal device_changed(device: String)  # "keyboard", "gamepad", or "touch"

const CFG := "user://keybinds.cfg"

## Every rebindable action, with its default keyboard key and default gamepad
## button. "key" of 0 means no keyboard binding, "button" of -1 means no button.
const ACTIONS: Dictionary = {
	"move_left":       {"label": "Move Left",       "key": KEY_A,        "button": JOY_BUTTON_DPAD_LEFT},
	"move_right":      {"label": "Move Right",      "key": KEY_D,        "button": JOY_BUTTON_DPAD_RIGHT},
	"move_up":         {"label": "Move Up",         "key": KEY_W,        "button": JOY_BUTTON_DPAD_UP},
	"move_down":       {"label": "Move Down",       "key": KEY_S,        "button": JOY_BUTTON_DPAD_DOWN},
	"sprint":          {"label": "Sprint",          "key": KEY_SHIFT,    "button": JOY_BUTTON_RIGHT_SHOULDER},
	"ability_1":       {"label": "Ability 1",       "key": KEY_Q,        "button": JOY_BUTTON_LEFT_SHOULDER},
	"ability_2":       {"label": "Ability 2",       "key": KEY_E,        "button": JOY_BUTTON_RIGHT_SHOULDER},
	"ability_3":       {"label": "Ability 3",       "key": KEY_R,        "button": JOY_BUTTON_X},
	"ability_4":       {"label": "Ability 4",       "key": KEY_T,        "button": JOY_BUTTON_Y},
	"interact":        {"label": "Interact",        "key": KEY_E,        "button": JOY_BUTTON_A},
	"cancel":          {"label": "Cancel / Back",   "key": KEY_ESCAPE,   "button": JOY_BUTTON_B},
	"confirm":         {"label": "Confirm / Select","key": KEY_ENTER,    "button": JOY_BUTTON_A},
	"pause":           {"label": "Pause",           "key": KEY_ESCAPE,   "button": JOY_BUTTON_START},
	"display_toggle":  {"label": "Display (console)","key": KEY_T,       "button": JOY_BUTTON_Y},
	"tetris_left":     {"label": "Tetris Left",     "key": KEY_LEFT,     "button": JOY_BUTTON_DPAD_LEFT},
	"tetris_right":    {"label": "Tetris Right",    "key": KEY_RIGHT,    "button": JOY_BUTTON_DPAD_RIGHT},
	"tetris_down":     {"label": "Tetris Soft Drop","key": KEY_DOWN,     "button": JOY_BUTTON_DPAD_DOWN},
	"tetris_rotate":   {"label": "Tetris Rotate",   "key": KEY_UP,       "button": JOY_BUTTON_DPAD_UP},
	"tetris_harddrop": {"label": "Tetris Hard Drop","key": KEY_SPACE,    "button": JOY_BUTTON_A},
	"gamble":          {"label": "Gamble (win screen)","key": KEY_G,     "button": JOY_BUTTON_Y},
	"flag":            {"label": "Flag (Minesweeper)","key": KEY_F,      "button": JOY_BUTTON_X},
}

## Godot's built-in UI actions get gamepad bindings so menus are fully
## navigable with a controller (D-pad/stick to move focus, A to activate,
## B to cancel) with no per-menu code.
const UI_GAMEPAD: Dictionary = {
	"ui_accept":      [JOY_BUTTON_A],
	"ui_cancel":      [JOY_BUTTON_B],
	"ui_left":        [JOY_BUTTON_DPAD_LEFT],
	"ui_right":       [JOY_BUTTON_DPAD_RIGHT],
	"ui_up":          [JOY_BUTTON_DPAD_UP],
	"ui_down":        [JOY_BUTTON_DPAD_DOWN],
	"ui_focus_next":  [JOY_BUTTON_RIGHT_SHOULDER],
	"ui_focus_prev":  [JOY_BUTTON_LEFT_SHOULDER],
}

var current_device: String = "keyboard"


func _ready() -> void:
	if is_phone():
		current_device = "touch"
	_apply_defaults()
	_add_ui_gamepad()
	_load()
	_add_left_stick()


func _add_left_stick() -> void:
	"""Bind the left analog stick to the movement actions so controller movement
	is smooth. Called after defaults/load; rebinding a key later only touches
	keyboard events, so the stick bindings are preserved."""
	_add_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)


func _add_axis(action: String, axis: int, axis_value: float) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion and e.axis == axis and signf(e.axis_value) == signf(axis_value):
			return
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis as JoyAxis
	ev.axis_value = axis_value
	InputMap.action_add_event(action, ev)


func is_pressed(action: String) -> bool:
	return Input.is_action_pressed(action)


func just_pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action)


func just_released(action: String) -> bool:
	return Input.is_action_just_released(action)


## True when the game is running on a phone/tablet (Android/iOS/mobile web),
## regardless of which input the player is using right now.
func is_phone() -> bool:
	return OS.has_feature("mobile") \
		or DisplayServer.get_name() == "android" \
		or DisplayServer.get_name() == "iOS"


## True when the player is currently using the touchscreen.
func is_touch() -> bool:
	return current_device == "touch"


func _input(event: InputEvent) -> void:
	var dev: String = current_device
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		dev = "gamepad"
	elif event is InputEventScreenTouch or event is InputEventScreenDrag \
			or event is InputEventMagnifyGesture or event is InputEventPanGesture \
			or (is_phone() and (event is InputEventMouseButton or event is InputEventMouseMotion)):
		# Touch input. On phones Godot also synthesizes mouse events from
		# touches, so treat those as touch too, otherwise the device would
		# flicker between "touch" and "keyboard" on every tap.
		dev = "touch"
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		dev = "keyboard"
	if dev != current_device:
		current_device = dev
		device_changed.emit(dev)


## ── Binding application ───────────────────────────────────────────────

func _apply_defaults() -> void:
	"""Create/refresh every action with its default key + gamepad binding."""
	for action: String in ACTIONS:
		var key: int = ACTIONS[action]["key"]
		var button: int = ACTIONS[action]["button"]
		_apply_action(action, key, button)


func _add_ui_gamepad() -> void:
	"""Add gamepad events to Godot's built-in ui_* actions (keeping keyboard).
	Only adds the default gamepad buttons the first time so we don't duplicate
	them on every launch."""
	for action: String in UI_GAMEPAD:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for b: int in UI_GAMEPAD[action]:
			if not _has_button(action, b):
				var ev := InputEventJoypadButton.new()
				ev.button_index = b as JoyButton
				InputMap.action_add_event(action, ev)


func _apply_action(action: String, key: int, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	if key != 0:
		var kev := InputEventKey.new()
		kev.keycode = key as Key
		InputMap.action_add_event(action, kev)
	if button >= 0:
		var bev := InputEventJoypadButton.new()
		bev.button_index = button as JoyButton
		InputMap.action_add_event(action, bev)


func _has_button(action: String, button: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and e.button_index == button:
			return true
	return false


## ── Rebinding ─────────────────────────────────────────────────────────

func rebind_key(action: String, keycode: int) -> void:
	"""Replace only the keyboard binding for an action, keeping its gamepad
	binding. Saving afterwards preserves both."""
	if not ACTIONS.has(action):
		return
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	# remove only keyboard events
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	if keycode != 0:
		var ev := InputEventKey.new()
		ev.keycode = keycode as Key
		InputMap.action_add_event(action, ev)
	_save()


func rebind_button(action: String, button: int) -> void:
	"""Replace only the gamepad binding for an action, keeping its keyboard
	binding."""
	if not ACTIONS.has(action):
		return
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			InputMap.action_erase_event(action, e)
	if button >= 0:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button as JoyButton
		InputMap.action_add_event(action, ev)
	_save()


func reset_action(action: String) -> void:
	if not ACTIONS.has(action):
		return
	_apply_action(action, ACTIONS[action]["key"], ACTIONS[action]["button"])
	_save()


func reset_all() -> void:
	_apply_defaults()
	_save()


func action_label(action: String) -> String:
	return ACTIONS.get(action, {}).get("label", action)


func current_key(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return e.keycode
	return 0


func current_button(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			return e.button_index
	return -1


## Return a short display string for an action's primary binding on the current
## device, so UI prompts read out the ASSIGNED key/button (e.g. "E", "A", "TAP")
## instead of a hard-coded one. `fallback` is used when no keyboard binding
## exists. Action need not be in ACTIONS — any InputMap action works.
func prompt_for(action: String, fallback: String = "") -> String:
	match current_device:
		"touch":
			return "TAP"
		"gamepad":
			var button: int = current_button(action)
			return _button_name(button) if button >= 0 else fallback
		_:
			var key: int = current_key(action)
			return OS.get_keycode_string(key) if key != 0 else fallback


func _button_name(button: int) -> String:
	return {
		JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
		JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down",
		JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right",
	}.get(button, "Btn%d" % button)


## ── Persistence ───────────────────────────────────────────────────────

func _save() -> void:
	var cfg := ConfigFile.new()
	for action: String in ACTIONS:
		cfg.set_value("key", action, current_key(action))
		cfg.set_value("button", action, current_button(action))
	cfg.save(CFG)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG) != OK:
		return
	for action: String in ACTIONS:
		var key: int = cfg.get_value("key", action, -1)
		var button: int = cfg.get_value("button", action, -1)
		if key >= 0 or button >= 0:
			_apply_action(action, key if key >= 0 else 0, button)
