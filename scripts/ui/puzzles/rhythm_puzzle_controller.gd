class_name RhythmPuzzleController
extends Node

## Rhythm puzzle controller.
## Notes scroll toward a hit line. Press SPACE to hit notes on the beat.

# Editable settings — tweak in inspector via PuzzleManager's @export vars
var bpm: int = 100
var hit_zone: ColorRect = null
var track_bg: ColorRect = null
var score_label: Label = null
var feedback_label: Label = null
var panel_ref: Control = null
var solved_callback: Callable = Callable()
var cancelled_callback: Callable = Callable()
var beat_flash: ColorRect = null  # Visual beat flash indicator

var _notes: Array[ColorRect] = []
var _note_spacing: float = 0.0
var _scroll_speed: float = 0.0
var _hit_count: int = 0
var _total_notes: int = 10
var _next_note_index: int = 0
var _active: bool = false
var _time_since_start: float = 0.0
var _spawned_count: int = 0
var _hit_tolerance: float = 0.18  # seconds - how close to beat to count as hit
var _feedback_busy: bool = false  # Prevent race conditions in feedback coroutines
var _all_notes_done: bool = false  # Track if all notes have been processed

const NOTE_COLOR: Color = Color(0.4, 0.8, 1.0, 1.0)
const HIT_COLOR: Color = Color(0.3, 0.9, 0.3, 1.0)
const MISS_COLOR: Color = Color(0.9, 0.3, 0.3, 1.0)
const TRACK_LEFT: float = 200.0
const TRACK_WIDTH: float = 200.0
const HIT_LINE_X: float = 340.0  # Center of hit zone
const NOTE_SIZE: float = 16.0
const START_DELAY: float = 2.0  # seconds before first note appears

func start() -> void:
	"""Begin the rhythm puzzle."""
	if bpm <= 0:
		bpm = 100  # Safety fallback — prevent division by zero
	# Spacing between notes at this BPM
	var beat_interval: float = 60.0 / float(bpm)
	_note_spacing = beat_interval  # seconds between notes
	_scroll_speed = 200.0 / beat_interval  # pixels per second to reach hit line
	
	# Pre-compute note timings (10 notes, evenly spaced)
	_total_notes = 10
	_hit_count = 0
	_next_note_index = 0
	_spawned_count = 0
	_time_since_start = 0.0
	_active = true
	_all_notes_done = false
	
	if score_label:
		score_label.text = "Hits: 0 / %d  |  BPM: %d" % [_total_notes, bpm]
	if feedback_label:
		feedback_label.text = ""
		feedback_label.visible = false
	
	print("RhythmPuzzle: Started at %d BPM, beat interval = %.2fs" % [bpm, 60.0 / bpm])


func _process(delta: float) -> void:
	if not _active:
		return
	
	_time_since_start += delta
	
	# Calculate next spawn time based on beat interval
	var beat_interval: float = 60.0 / float(bpm)
	var travel_time: float = (HIT_LINE_X - TRACK_LEFT - NOTE_SIZE * 0.5) / _scroll_speed  # time to travel from left to hit line
	
	# Spawn notes at the right time so they arrive at hit line on beat
	if _spawned_count < _total_notes:
		var spawn_time: float = _next_note_index * beat_interval - travel_time + beat_interval + START_DELAY  # offset so first note arrives at beat 1 + START_DELAY
		if _time_since_start >= spawn_time:
			_spawn_note()
	
	# Visual beat flash — briefly brighten the hit zone on each beat
	if beat_flash and not _all_notes_done:
		var next_beat_time: float = _next_note_index * beat_interval + START_DELAY
		if _time_since_start >= next_beat_time + 0.05 and beat_flash.visible:
			beat_flash.visible = false
		if not beat_flash.visible:
			if _time_since_start >= next_beat_time - 0.02 and _time_since_start <= next_beat_time + 0.05:
				beat_flash.visible = true
				beat_flash.modulate = Color(1, 1, 1, 0.3)
	
	# Move notes and check for misses (use a copy of array to avoid race with _input)
	var to_remove: Array[ColorRect] = []
	for note in _notes:
		if not is_instance_valid(note):
			to_remove.append(note)
			continue
		# Move toward hit line
		note.position.x -= delta * _scroll_speed
		
		# If passed the hit line too far, it's a miss
		var note_center_x: float = note.position.x + NOTE_SIZE * 0.5
		if note_center_x < HIT_LINE_X - _hit_tolerance * _scroll_speed:
			to_remove.append(note)
			_note_missed()
	
	for note in to_remove:
		if is_instance_valid(note):
			_notes.erase(note)
			note.queue_free()
	
	# Check loss condition: all notes spawned AND none left in play
	if _spawned_count >= _total_notes and _notes.is_empty() and not _all_notes_done:
		_all_notes_done = true
		_check_end_condition()


func _spawn_note() -> void:
	"""Spawn a new note at the right edge of the track."""
	var note := ColorRect.new()
	note.name = "Note_%d" % _spawned_count
	note.size = Vector2(NOTE_SIZE, NOTE_SIZE)
	# Start just off the right side of the track, centered vertically in track
	var track_center_y: float = track_bg.position.y + track_bg.size.y * 0.5
	note.position = Vector2(track_bg.position.x + track_bg.size.x - NOTE_SIZE, track_center_y - NOTE_SIZE * 0.5)
	note.color = NOTE_COLOR
	panel_ref.add_child(note)
	_notes.append(note)
	_spawned_count += 1
	_next_note_index += 1


func _check_end_condition() -> void:
	"""Check if the puzzle should end (win or loss) after all notes are processed."""
	if not _active:
		return
	if _hit_count >= _total_notes * 0.8:
		# WIN!
		_active = false
		if feedback_label:
			feedback_label.text = "♪ Puzzle Complete! ♪"
			feedback_label.visible = true
		await get_tree().create_timer(1.5).timeout
		if _active == false and solved_callback.is_valid():
			solved_callback.call()
	else:
		# Not enough hits
		_active = false
		if feedback_label:
			feedback_label.text = "Not enough hits..."
			feedback_label.visible = true
		await get_tree().create_timer(1.5).timeout
		if _active == false and cancelled_callback.is_valid():
			cancelled_callback.call()


func _input(event: InputEvent) -> void:
	if not _active or not event.is_pressed():
		return
	
	# Check for SPACE key
	var is_space: bool = false
	if event is InputEventKey and event.keycode == KEY_SPACE:
		is_space = true
	elif event.is_action_pressed("ui_accept"):
		is_space = true
	
	if not is_space:
		return
	
	# Find the nearest note to the hit line
	var best_note: ColorRect = null
	var best_dist: float = INF
	
	for note in _notes:
		if not is_instance_valid(note):
			continue
		var note_center_x: float = note.position.x + NOTE_SIZE * 0.5
		var dist: float = abs(note_center_x - HIT_LINE_X)
		if dist < best_dist and dist <= _hit_tolerance * _scroll_speed:
			best_dist = dist
			best_note = note
	
	if best_note != null:
		# HIT!
		_hit_count += 1
		_notes.erase(best_note)
		best_note.queue_free()
		
		if score_label:
			score_label.text = "Hits: %d / %d  |  BPM: %d" % [_hit_count, _total_notes, bpm]
		
		if feedback_label:
			feedback_label.text = "HIT!"
			feedback_label.visible = true
			feedback_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3, 1))
		
		# Win or loss checked by _process when all notes are done
		if beat_flash:
			beat_flash.visible = false
	else:
		# Miss - pressed but no note nearby
		_miss_press()


func _note_missed() -> void:
	"""Called when a note passes the hit line without being hit."""
	if _feedback_busy:
		return
	_feedback_busy = true
	if feedback_label:
		feedback_label.text = "MISS"
		feedback_label.visible = true
		feedback_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3, 1))
		await get_tree().create_timer(0.3).timeout
		if is_instance_valid(feedback_label):
			feedback_label.visible = false
	_feedback_busy = false


func _miss_press() -> void:
	"""Called when player presses SPACE but no note is near."""
	if _feedback_busy:
		return
	_feedback_busy = true
	if feedback_label:
		feedback_label.text = "Too early!"
		feedback_label.visible = true
		feedback_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.2, 1))
		await get_tree().create_timer(0.3).timeout
		if is_instance_valid(feedback_label):
			feedback_label.visible = false
	_feedback_busy = false
