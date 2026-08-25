class_name Dirtysweeper
extends Control
## Dirtysweeper — a full classic minesweeper minigame for the arcade console.
##
## Launched as its own scene from the arcade room browser. Self-contained:
## renders its own board, handles keyboard/controller (via InputSystem actions)
## and touch/mouse, awards Grass coins on a win, and returns to the arcade room.
##
## Controls:
##   Arrows / WASD / left stick  — move cursor
##   ENTER / A (confirm)         — reveal the cursor's cell
##   F                          — toggle flag mode (then confirm flags)
##   Mouse / touch              — tap a cell to reveal (flag-mode to flag)
##   ESC / B (cancel)           — quit back to the arcade room
##   Click the face / R         — restart

const CELL := 46.0
const GRID := 9
const MINES := 10
const MINES_HARD := 16

const THUMB: String = "res://The Darkness Of The Grasslands assets/Thumbnails/Minigame_dirtysweeper.thumbnail.png"
const FACE_NEUTRAL: String = "res://The Darkness Of The Grasslands assets/UI/minigames/Minigame_minesweeper_neutral_face.png"
const FACE_WARNING: String = "res://The Darkness Of The Grasslands assets/UI/minigames/Minigame_minesweeper_warning_face.png"
const FACE_DEAD: String = "res://The Darkness Of The Grasslands assets/UI/minigames/Minigame_minesweeper_dead_face.png"
const FACE_NEUTRAL_G: String = "res://The Darkness Of The Grasslands assets/UI/minigames/Minigame_minesweeper_neutral_face_gambling.png"
const FACE_WARNING_G: String = "res://The Darkness Of The Grasslands assets/UI/minigames/Minigame_minesweeper_warning_face_gambling.png"
const FACE_DEAD_G: String = "res://The Darkness Of The Grasslands assets/UI/minigames/Minigame_minesweeper_dead_face_gambling.png"
const ARCADE_SCENE: String = "res://scenes/arcade_room.tscn"

# Classic minesweeper number colours.
const NUM_COLORS: Array = [Color.BLACK, Color(0.2,0.35,0.9), Color(0.1,0.6,0.2), Color(0.85,0.15,0.15),
	Color(0.3,0.1,0.6), Color(0.5,0.15,0.4), Color(0.1,0.6,0.65), Color.BLACK, Color(0.4,0.4,0.4)]

var _board: Array = []            # _board[r][c] = {mine, revealed, flagged, count}
var _cursor := Vector2i(0, 0)
var _hard := false
var _game_over := false
var _won := false
var _flag_mode := false
var _move_timer := 0.0

var _buttons: Array = []          # _buttons[r][c] = Button
var _cursor_rect: ColorRect
var _face_btn: Button
var _face_tex: TextureRect
var _status: Label
var _counts: Label               # remaining mines


func _ready() -> void:
	_hard = GameState.dirtysweeper_hard
	_build()

func _exit_tree() -> void:
	# Save the chosen difficulty so it persists across sessions.
	GameState.dirtysweeper_hard = _hard


## ── Board generation ───────────────────────────────────────────────

func _new_board(exclude: Vector2i) -> void:
	var mines: int = MINES_HARD if _hard else MINES
	_board = []
	for r in range(GRID):
		var row: Array = []
		for c in range(GRID):
			row.append({"mine": false, "revealed": false, "flagged": false, "count": 0})
		_board.append(row)
	# Place mines, never on the first-clicked cell or its neighbours.
	var placed := 0
	while placed < mines:
		var r: int = randi() % GRID
		var c: int = randi() % GRID
		if Vector2i(r, c) == exclude:
			continue
		if absi(r - exclude.x) <= 1 and absi(c - exclude.y) <= 1:
			continue
		if _board[r][c]["mine"]:
			continue
		_board[r][c]["mine"] = true
		placed += 1
	_compute_counts()
	_game_over = false
	_won = false
	_flag_mode = false
	_cursor = exclude


func _compute_counts() -> void:
	for r in range(GRID):
		for c in range(GRID):
			var n := 0
			for dr in [-1, 0, 1]:
				for dc in [-1, 0, 1]:
					if dr == 0 and dc == 0:
						continue
					var rr: int = r + dr
					var cc: int = c + dc
					if rr >= 0 and rr < GRID and cc >= 0 and cc < GRID and _board[rr][cc]["mine"]:
						n += 1
			_board[r][c]["count"] = n


func _mines_flagged() -> int:
	var n := 0
	for r in range(GRID):
		for c in range(GRID):
			if _board[r][c]["flagged"]:
				n += 1
	return n


func _unrevealed_safe() -> int:
	var n := 0
	for r in range(GRID):
		for c in range(GRID):
			if not _board[r][c]["mine"] and not _board[r][c]["revealed"]:
				n += 1
	return n


## ── UI build ───────────────────────────────────────────────────────

func _build() -> void:
	var p := _palette()
	var bg := ColorRect.new()
	bg.color = p["bg"]
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Title.
	var title := Label.new()
	title.text = "DIRTYSWEEPER"
	title.position = Vector2(0, 24)
	title.size = Vector2(1280, 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", p["accent"])
	title.add_theme_font_size_override("font_size", 52)
	add_child(title)

	# Face button (also restarts) at top-centre.
	_face_tex = TextureRect.new()
	_face_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_face_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face_tex.size = Vector2(64, 64)
	_face_tex.position = Vector2(1280 / 2.0 - 32, 92)
	_face_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face_tex)
	_face_btn = Button.new()
	_face_btn.position = Vector2(1280 / 2.0 - 40, 88)
	_face_btn.size = Vector2(80, 72)
	_face_btn.flat = true
	_face_btn.pressed.connect(_restart)
	add_child(_face_btn)
	_refresh_face()

	# Status + remaining mines.
	_status = Label.new()
	_status.position = Vector2(0, 158)
	_status.size = Vector2(1280, 30)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", p["text"])
	_status.add_theme_font_size_override("font_size", 20)
	add_child(_status)
	_counts = Label.new()
	_counts.position = Vector2(0, 184)
	_counts.size = Vector2(1280, 26)
	_counts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counts.add_theme_color_override("font_color", Color(1, 0.8, 0.3, 1))
	_counts.add_theme_font_size_override("font_size", 20)
	add_child(_counts)

	# Board grid of buttons.
	var grid_w: float = GRID * CELL
	var ox: float = (1280 - grid_w) / 2.0
	var oy: float = 230.0
	for r in range(GRID):
		var row_arr: Array = []
		for c in range(GRID):
			var b := Button.new()
			b.position = Vector2(ox + c * CELL, oy + r * CELL)
			b.size = Vector2(CELL, CELL)
			b.custom_minimum_size = Vector2(CELL, CELL)
			b.add_theme_font_size_override("font_size", 22)
			b.add_theme_stylebox_override("normal", _cell_style(Color(0.45,0.45,0.5), 2))
			b.add_theme_stylebox_override("hover", _cell_style(Color(0.55,0.55,0.62), 2))
			b.add_theme_stylebox_override("pressed", _cell_style(Color(0.3,0.3,0.34), 2))
			b.add_theme_stylebox_override("focus", _cell_style(Color(1,1,1,0), 2))
			b.focus_mode = Control.FOCUS_NONE
			var cell := Vector2i(r, c)
			b.pressed.connect(_on_cell_pressed.bind(cell))
			add_child(b)
			row_arr.append(b)
		_buttons.append(row_arr)

	# Cursor highlight overlay.
	_cursor_rect = ColorRect.new()
	_cursor_rect.color = Color(1, 1, 1, 0.28)
	_cursor_rect.size = Vector2(CELL, CELL)
	_cursor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cursor_rect)

	# Help / hint line.
	var hint := Label.new()
	hint.text = "ENTER reveal   •   F flag   •   arrows/WASD move   •   ESC quit   •   face restarts"
	hint.position = Vector2(0, oy + grid_w + 14)
	hint.size = Vector2(1280, 26)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", p["text_dim"])
	hint.add_theme_font_size_override("font_size", 18)
	add_child(hint)

	_new_board(Vector2i(GRID / 2, GRID / 2))
	_update_all()
	_update_cursor_rect()


func _cell_style(color: Color, border: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_border_width_all(border)
	sb.border_color = Color(0.2, 0.2, 0.22, 1)
	return sb


func _palette() -> Dictionary:
	return {
		"bg": Color(0.05, 0.05, 0.08, 1),
		"accent": Color(0.5, 1.0, 0.5, 1),
		"text": Color(0.85, 0.85, 0.85, 1),
		"text_dim": Color(0.5, 0.5, 0.5, 1),
	}


func _face_path() -> String:
	if _game_over and not _won:
		return FACE_DEAD_G if _hard else FACE_DEAD
	if _won:
		return FACE_NEUTRAL_G if _hard else FACE_NEUTRAL
	if _flag_mode:
		return FACE_WARNING_G if _hard else FACE_WARNING
	return FACE_NEUTRAL_G if _hard else FACE_NEUTRAL


func _refresh_face() -> void:
	_face_tex.texture = load(_face_path())


## ── Rendering ──────────────────────────────────────────────────────

func _update_all() -> void:
	for r in range(GRID):
		for c in range(GRID):
			_update_cell(r, c)
	_counts.text = "MINES LEFT: %d" % maxi(MINES_HARD if _hard else MINES - _mines_flagged(), 0)
	if _won:
		_status.text = "YOU WIN! +%d Grass coin" % (2 if _hard else 1)
	elif _game_over:
		_status.text = "BOOM! GAME OVER"
	else:
		_status.text = ("FLAG MODE" if _flag_mode else "SAFE") + ("  [HARD]" if _hard else "  [NORMAL]")


func _update_cell(r: int, c: int) -> void:
	var b: Button = _buttons[r][c]
	var cell: Dictionary = _board[r][c]
	if cell["revealed"]:
		if cell["mine"]:
			b.text = "💣"
			b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			b.add_theme_stylebox_override("normal", _cell_style(Color(0.6, 0.2, 0.2), 2))
		else:
			var n: int = cell["count"]
			b.text = "" if n == 0 else str(n)
			b.add_theme_color_override("font_color", NUM_COLORS[n] if n > 0 else Color(0.8, 0.8, 0.8, 1))
			b.add_theme_stylebox_override("normal", _cell_style(Color(0.72, 0.72, 0.78), 2))
	else:
		if cell["flagged"]:
			b.text = "⚑"
			b.add_theme_color_override("font_color", Color(1, 0.5, 0.2, 1))
		else:
			b.text = ""
		b.add_theme_stylebox_override("normal", _cell_style(Color(0.45, 0.45, 0.5), 2))


func _update_cursor_rect() -> void:
	if _game_over:
		_cursor_rect.visible = false
		return
	_cursor_rect.visible = true
	var grid_w: float = GRID * CELL
	var ox: float = (1280 - grid_w) / 2.0
	_cursor_rect.position = Vector2(ox + _cursor.y * CELL, 230.0 + _cursor.x * CELL)


## ── Game logic ─────────────────────────────────────────────────────

func _reveal(r: int, c: int) -> void:
	if _game_over or _won:
		return
	var cell: Dictionary = _board[r][c]
	if cell["flagged"]:
		return
	if cell["mine"]:
		cell["revealed"] = true
		_game_over = true
		_reveal_all_mines()
		_update_all()
		_refresh_face()
		return
	_flood_reveal(r, c)
	_update_all()
	if _unrevealed_safe() == 0:
		_win()
		return


func _flood_reveal(r: int, c: int) -> void:
	var cell: Dictionary = _board[r][c]
	if cell["revealed"] or cell["flagged"]:
		return
	cell["revealed"] = true
	if cell["count"] != 0:
		return
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var rr: int = r + dr
			var cc: int = c + dc
			if rr >= 0 and rr < GRID and cc >= 0 and cc < GRID:
				_flood_reveal(rr, cc)


func _reveal_all_mines() -> void:
	for r in range(GRID):
		for c in range(GRID):
			if _board[r][c]["mine"]:
				_board[r][c]["revealed"] = true


func _flag(r: int, c: int) -> void:
	if _game_over or _won:
		return
	var cell: Dictionary = _board[r][c]
	if cell["revealed"]:
		return
	cell["flagged"] = not cell["flagged"]
	_update_all()
	_refresh_face()


func _on_cell_pressed(cell: Vector2i) -> void:
	if _flag_mode:
		_flag(cell.x, cell.y)
	else:
		_reveal(cell.x, cell.y)


func _restart() -> void:
	_new_board(Vector2i(GRID / 2, GRID / 2))
	_update_all()
	_update_cursor_rect()
	_refresh_face()


func _win() -> void:
	_won = true
	_award_win()
	_update_all()
	_refresh_face()


## ── Coin economy (mirrors the arcade's farmable rules) ─────────────

func _award_win() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	# Reset the daily gamble bonus when a new day begins.
	if _daily_available(now):
		GameState.tetrino_gambled = false
	var awarded := 0
	if _hard and not GameState.tetrino_gambled:
		awarded = 2
		GameState.tetrino_coins_earned += 2
		GameState.tetrino_gambled = true
		GameState.tetrino_last_coin_time = now
	else:
		awarded = 1
		GameState.tetrino_coins_earned += 1
		GameState.tetrino_last_coin_time = now
	if awarded > 0:
		GameState.add_money(awarded)
		_autosave()


func _daily_available(now: float) -> bool:
	var last: float = float(GameState.tetrino_last_coin_time)
	if last <= 0:
		return true
	var d0 := Time.get_datetime_dict_from_unix_time(last)
	var d1 := Time.get_datetime_dict_from_unix_time(now)
	return d0["year"] != d1["year"] or d0["month"] != d1["month"] or d0["day"] != d1["day"]


func _autosave() -> void:
	if AuthManager.current_username.is_empty():
		return
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("autosave"):
		sm.autosave(AuthManager.current_username)


func _quit() -> void:
	get_tree().change_scene_to_file(ARCADE_SCENE)


## ── Input ──────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _game_over or _won:
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		_move_timer -= delta
		if _move_timer <= 0.0:
			_move_cursor(dir)
			_move_timer = 0.13
	else:
		_move_timer = 0.0


func _move_cursor(dir: Vector2) -> void:
	var nx: int = clampi(_cursor.x + int(round(dir.y)), 0, GRID - 1)
	var ny: int = clampi(_cursor.y + int(round(dir.x)), 0, GRID - 1)
	_cursor = Vector2i(nx, ny)
	_update_cursor_rect()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_flag(_cursor.x, _cursor.y)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_quit()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			_restart()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			_flag_mode = not _flag_mode
			_update_all()
			_refresh_face()
			get_viewport().set_input_as_handled()
	if InputSystem.just_pressed("confirm"):
		_reveal(_cursor.x, _cursor.y)
		get_viewport().set_input_as_handled()
	elif InputSystem.just_pressed("cancel"):
		_quit()
		get_viewport().set_input_as_handled()
