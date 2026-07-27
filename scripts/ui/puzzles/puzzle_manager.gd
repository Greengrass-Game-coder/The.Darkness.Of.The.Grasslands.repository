class_name PuzzleManager
extends Node

## Orchestrates puzzle minigames. Randomly picks Memory, Wiring, or Rhythm.
## Each puzzle has levels 1-5. Emits solved when completed.

const SCRIPT_MEMORY: GDScript = preload("res://scripts/ui/puzzles/memory_puzzle_controller.gd")
const SCRIPT_WIRING: GDScript = preload("res://scripts/ui/puzzles/wiring_puzzle_controller.gd")
const SCRIPT_RHYTHM: GDScript = preload("res://scripts/ui/puzzles/rhythm_puzzle_controller.gd")

enum PuzzleType { MEMORY, WIRING, RHYTHM }

signal puzzle_completed(puzzle_area: Area2D)
signal puzzle_closed()

var _current_puzzle: Control = null
var _current_area: Area2D = null
var _panel: Panel = null
var _title_label: Label = null
var _player_ref: Node2D = null
var _puzzle_level: int = 1
var _chosen_type: PuzzleType = PuzzleType.MEMORY


func open_puzzle(area: Area2D, player: Node2D, _level: int = 1) -> void:
	"""Open a random puzzle overlay, starting at level 1."""
	if _current_puzzle != null:
		return
	
	_current_area = area
	_player_ref = player
	_puzzle_level = max(1, _level)  # Respect passed level, minimum 1
	
	# Freeze player
	if player.has_method("set_physics_process"):
		player.set_physics_process(false)
	
	# Pick random puzzle type
	var types: Array[PuzzleType] = [PuzzleType.MEMORY, PuzzleType.WIRING, PuzzleType.RHYTHM]
	_chosen_type = types[randi() % types.size()]
	
	_start_current_level()


func _build_panel(title: String) -> Panel:
	"""Create the base dark panel overlay for any puzzle."""
	var panel := Panel.new()
	panel.name = "PuzzlePanel"
	panel.size = Vector2(480, 360)
	panel.position = Vector2(400, 180)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.6, 0.3, 0.8, 1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	
	# Title
	var title_lbl := Label.new()
	title_lbl.name = "PuzzleTitle"
	title_lbl.text = title
	title_lbl.position = Vector2(20, 16)
	title_lbl.size = Vector2(440, 30)
	title_lbl.add_theme_color_override("font_color", Color(1, 1, 0.7, 1))
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	title_lbl.add_theme_constant_override("shadow_offset_x", 1)
	title_lbl.add_theme_constant_override("shadow_offset_y", 1)
	panel.add_child(title_lbl)
	_title_label = title_lbl
	
	# Difficulty label
	var diff_lbl := Label.new()
	diff_lbl.name = "DiffLabel"
	diff_lbl.text = "Level %d/5" % _puzzle_level
	diff_lbl.position = Vector2(20, 44)
	diff_lbl.size = Vector2(200, 20)
	diff_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	diff_lbl.add_theme_font_size_override("font_size", 14)
	panel.add_child(diff_lbl)
	
	# Close hint
	var close_hint := Label.new()
	close_hint.name = "CloseHint"
	close_hint.text = "[ESC] Cancel"
	close_hint.position = Vector2(380, 44)
	close_hint.size = Vector2(100, 20)
	close_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	close_hint.add_theme_font_size_override("font_size", 12)
	panel.add_child(close_hint)
	
	# Add to scene
	var canvas := CanvasLayer.new()
	canvas.name = "PuzzleOverlay"
	canvas.layer = 10
	canvas.add_child(panel)
	add_child(canvas)
	
	_panel = panel
	return panel


func _close_puzzle(solved: bool = false) -> void:
	"""Close the puzzle, unfreeze player, emit result."""
	# Remove overlay
	var overlay: CanvasLayer = get_node_or_null("PuzzleOverlay")
	if overlay:
		overlay.queue_free()
	
	# Unfreeze player
	if _player_ref != null and is_instance_valid(_player_ref):
		_player_ref.set_physics_process(true)
	
	_current_puzzle = null
	_panel = null
	_title_label = null
	
	if solved and _current_area != null:
		puzzle_completed.emit(_current_area)
	
	puzzle_closed.emit()
	_current_area = null
	_player_ref = null


func _start_current_level() -> void:
	"""Start (or restart) the puzzle at the current level."""
	match _chosen_type:
		PuzzleType.MEMORY:
			_open_memory_puzzle()
		PuzzleType.WIRING:
			_open_wiring_puzzle()
		PuzzleType.RHYTHM:
			_open_rhythm_puzzle()


func _on_puzzle_round_solved() -> void:
	"""Called when a puzzle round is solved — advance to next level or finish."""
	if not is_instance_valid(_panel):
		return
	if _puzzle_level < 5:
		# Show level complete briefly, then advance
		_puzzle_level += 1
		if _title_label:
			_title_label.text = "Level %d/5 Complete!" % (_puzzle_level - 1)
		
		var diff_lbl: Label = _panel.get_node_or_null("DiffLabel")
		if diff_lbl:
			diff_lbl.text = "Next: Level %d/5" % _puzzle_level
		
		# Clean up old puzzle controller children
		for child in get_children():
			if child is Node and child.name in ["MemoryController", "WiringController", "RhythmController"]:
				child.queue_free()
		
		await get_tree().create_timer(1.2).timeout
		if not is_instance_valid(_panel):
			return
		
		# Restart with same type at new level
		_start_current_level()
	else:
		# All 5 levels complete!
		if _title_label:
			_title_label.text = "All Levels Complete! ✓"
		await get_tree().create_timer(1.0).timeout
		_close_puzzle(true)


func _on_puzzle_cancelled() -> void:
	"""Called when player cancels the puzzle."""
	_close_puzzle(false)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.keycode == KEY_ESCAPE):
		if _current_puzzle != null:
			_on_puzzle_cancelled()
			get_viewport().set_input_as_handled()


# ----- Memory Puzzle -----

func _open_memory_puzzle() -> void:
	"""Open a Memory (Simon-says) puzzle."""
	var panel: Panel = _build_panel("Memory Puzzle")
	
	var tile_count: int = 2 + _puzzle_level  # Levels 1-5 → 3-7 tiles
	var tile_w: float = 56.0
	var tile_h: float = 56.0
	var gap: float = 12.0
	var total_w: float = tile_count * (tile_w + gap) - gap
	var start_x: float = (panel.size.x - total_w) * 0.5
	var start_y: float = 100.0
	
	# Create tiles
	var tiles: Array[ColorRect] = []
	for i in range(tile_count):
		var tile := ColorRect.new()
		tile.name = "Tile_%d" % i
		tile.size = Vector2(tile_w, tile_h)
		tile.position = Vector2(start_x + i * (tile_w + gap), start_y)
		tile.color = Color(0.2, 0.2, 0.25, 1.0)
		panel.add_child(tile)
		tiles.append(tile)
	
	# Instruction label
	var instr := Label.new()
	instr.name = "InstrLabel"
	instr.text = "Watch the sequence..."
	instr.position = Vector2(20, start_y + tile_h + 12)
	instr.size = Vector2(440, 24)
	instr.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	instr.add_theme_font_size_override("font_size", 16)
	instr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(instr)
	
	_current_puzzle = panel
	
	# Create the memory controller
	var mem := Node.new()
	mem.set_script(SCRIPT_MEMORY)
	mem.name = "MemoryController"
	mem.tiles = tiles
	mem.tile_count = tile_count
	mem.instruction_label = instr
	mem.panel_ref = panel
	mem.solved_callback = _on_puzzle_round_solved
	mem.cancelled_callback = _on_puzzle_cancelled
	add_child(mem)
	mem.start_sequence()


# ----- Wiring Puzzle -----

func _open_wiring_puzzle() -> void:
	"""Open a Wiring (match colors) puzzle."""
	var panel: Panel = _build_panel("Wiring Puzzle")
	
	var wire_count: int = 1 + _puzzle_level  # Levels 1-5 → 2-6 wires
	var colors: Array[Color] = [
		Color(1, 0.2, 0.2, 1),    # Red
		Color(0.2, 1, 0.2, 1),    # Green
		Color(0.2, 0.6, 1, 1),    # Blue
		Color(1, 1, 0.2, 1),      # Yellow
		Color(1, 0.4, 0.8, 1),    # Pink
		Color(0.8, 0.4, 1, 1),    # Purple
	]
	
	# Shuffle two arrays of colors so left and right are mismatched
	var left_colors: Array[Color] = colors.slice(0, wire_count)
	var right_colors: Array[Color] = colors.slice(0, wire_count)
	right_colors.shuffle()
	
	# Track which index on right matches each left index
	var right_matches: Array[int] = []
	for c in left_colors:
		right_matches.append(right_colors.find(c))
	
	var wire_h: float = 32.0
	var gap: float = 8.0
	var total_h: float = wire_count * (wire_h + gap) - gap
	var start_y: float = (panel.size.y - total_h - 60) * 0.5 + 70
	
	# Left side: wire labels (clickable TextureRects)
	var left_wires: Array[TextureRect] = []
	for i in range(wire_count):
		var lbl := TextureRect.new()
		lbl.name = "LeftWire_%d" % i
		lbl.position = Vector2(30, start_y + i * (wire_h + gap))
		lbl.size = Vector2(160, wire_h)
		lbl.modulate = left_colors[i]
		panel.add_child(lbl)
		# Add label text via a child Label
		var ltext := Label.new()
		ltext.text = "⬤ Wire %d" % (i + 1)
		ltext.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		ltext.add_theme_font_size_override("font_size", 16)
		lbl.add_child(ltext)
		left_wires.append(lbl)
	
	# Click detection areas for left wires (transparent buttons)
	var left_buttons: Array[Button] = []
	for i in range(wire_count):
		var btn := Button.new()
		btn.name = "LeftBtn_%d" % i
		btn.position = Vector2(30, start_y + i * (wire_h + gap))
		btn.size = Vector2(160, wire_h)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.add_child(btn)
		left_buttons.append(btn)
	
	# Right side: plug buttons
	var right_buttons: Array[Button] = []
	for i in range(wire_count):
		var btn := Button.new()
		btn.name = "RightBtn_%d" % i
		btn.text = "Plug %d" % (i + 1)
		btn.position = Vector2(280, start_y + i * (wire_h + gap))
		btn.size = Vector2(160, wire_h)
		btn.add_theme_color_override("font_color", right_colors[i])
		btn.add_theme_font_size_override("font_size", 16)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# Add colored circle indicator
		var color_dot := ColorRect.new()
		color_dot.name = "Dot"
		color_dot.size = Vector2(16, 16)
		color_dot.position = Vector2(130, 8)
		color_dot.color = right_colors[i]
		btn.add_child(color_dot)
		panel.add_child(btn)
		right_buttons.append(btn)
	
	_current_puzzle = panel
	
	# Create wiring controller
	var wiring := Node.new()
	wiring.set_script(SCRIPT_WIRING)
	wiring.name = "WiringController"
	wiring.left_wires = left_wires
	wiring.left_buttons = left_buttons
	wiring.right_buttons = right_buttons
	wiring.left_colors = left_colors
	wiring.right_colors = right_colors
	wiring.right_matches = right_matches
	wiring.wire_count = wire_count
	wiring.panel_ref = panel
	wiring.solved_callback = _on_puzzle_round_solved
	wiring.cancelled_callback = _on_puzzle_cancelled
	add_child(wiring)
	wiring.start()


# ----- Rhythm Puzzle -----

func _open_rhythm_puzzle() -> void:
	"""Open a Rhythm (press key on beat) puzzle."""
	var panel: Panel = _build_panel("Rhythm Puzzle")
	
	var bpms: Array[int] = [100, 110, 120, 130, 140]
	var bpm: int = bpms[_puzzle_level - 1]
	
	# Hit zone area
	var hit_zone := ColorRect.new()
	hit_zone.name = "HitZone"
	hit_zone.size = Vector2(6, 200)
	hit_zone.position = Vector2(340, 90)
	hit_zone.color = Color(1, 1, 0.4, 0.6)
	panel.add_child(hit_zone)
	
	# Center line
	var center_line := ColorRect.new()
	center_line.name = "CenterLine"
	center_line.size = Vector2(2, 200)
	center_line.position = Vector2(342, 90)
	center_line.color = Color(1, 1, 1, 0.4)
	panel.add_child(center_line)
	
	# Beat flash — brightens the hit zone on each beat for visual feedback
	var beat_flash := ColorRect.new()
	beat_flash.name = "BeatFlash"
	beat_flash.size = Vector2(10, 200)
	beat_flash.position = Vector2(338, 90)
	beat_flash.color = Color(1, 1, 1, 0.3)
	beat_flash.visible = false
	panel.add_child(beat_flash)
	
	# Note track area (where notes appear)
	var track_bg := ColorRect.new()
	track_bg.name = "TrackBg"
	track_bg.size = Vector2(200, 200)
	track_bg.position = Vector2(200, 90)
	track_bg.color = Color(0.12, 0.12, 0.15, 0.5)
	panel.add_child(track_bg)
	
	# Score label
	var score_lbl := Label.new()
	score_lbl.name = "ScoreLabel"
	score_lbl.text = "Hits: 0 / 10  |  BPM: %d" % bpm
	score_lbl.position = Vector2(20, 90)
	score_lbl.size = Vector2(160, 30)
	score_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	score_lbl.add_theme_font_size_override("font_size", 14)
	panel.add_child(score_lbl)
	
	# Hit feedback
	var feedback := Label.new()
	feedback.name = "Feedback"
	feedback.position = Vector2(200, 40)
	feedback.size = Vector2(200, 36)
	feedback.add_theme_color_override("font_color", Color(1, 1, 0.4, 1))
	feedback.add_theme_font_size_override("font_size", 20)
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.visible = false
	panel.add_child(feedback)
	
	_current_puzzle = panel
	
	# Create rhythm controller
	var rhythm := Node.new()
	rhythm.set_script(SCRIPT_RHYTHM)
	rhythm.name = "RhythmController"
	rhythm.bpm = bpm
	rhythm.hit_zone = hit_zone
	rhythm.track_bg = track_bg
	rhythm.score_label = score_lbl
	rhythm.feedback_label = feedback
	rhythm.beat_flash = beat_flash
	rhythm.panel_ref = panel
	rhythm.solved_callback = _on_puzzle_round_solved
	rhythm.cancelled_callback = _on_puzzle_cancelled
	add_child(rhythm)
	rhythm.start()
