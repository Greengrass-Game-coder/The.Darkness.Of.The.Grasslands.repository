class_name MemoryPuzzleController
extends Node

## Memory (Simon-says) puzzle controller.
## Tiles flash in sequence, player repeats the sequence by clicking tiles.

var tiles: Array[ColorRect] = []
var tile_count: int = 3
var instruction_label = null  # Label or BitmapLabel; use duck typing for .text
var panel_ref: Control = null
var solved_callback: Callable = Callable()
var cancelled_callback: Callable = Callable()

var _sequence: Array[int] = []
var _player_step: int = 0
var _showing_sequence: bool = false
var _accept_input: bool = false

# Colors
const COLOR_OFF: Color = Color(0.2, 0.2, 0.25, 1.0)
const COLOR_ON: Color = Color(0.4, 0.7, 1.0, 1.0)
const COLOR_SUCCESS: Color = Color(0.3, 0.9, 0.3, 1.0)
const COLOR_FAIL: Color = Color(0.9, 0.2, 0.2, 1.0)

func start_sequence() -> void:
	"""Begin the memory puzzle."""
	_generate_sequence()
	await get_tree().create_timer(0.5).timeout
	_show_sequence()


func _generate_sequence() -> void:
	_sequence = []
	for i in range(tile_count):
		_sequence.append(randi() % tile_count)


func _show_sequence() -> void:
	"""Flash tiles one by one."""
	_showing_sequence = true
	_accept_input = false
	_player_step = 0
	
	if instruction_label:
		instruction_label.text = "Watch the sequence..."
	
	var tile_colors: Dictionary = {}
	for i in range(tile_count):
		tile_colors[i] = tiles[i].color
		tiles[i].color = COLOR_OFF
	
	for idx in range(_sequence.size()):
		var tile_idx: int = _sequence[idx]
		if not is_instance_valid(tiles[tile_idx]):
			return
		
		tiles[tile_idx].color = COLOR_ON
		await get_tree().create_timer(0.4).timeout
		
		if not is_instance_valid(tiles[tile_idx]):
			return
		tiles[tile_idx].color = COLOR_OFF
		await get_tree().create_timer(0.15).timeout
	
	# Restore colors
	for i in range(tile_count):
		if is_instance_valid(tiles[i]):
			tiles[i].color = COLOR_OFF
	
	_showing_sequence = false
	_accept_input = true
	
	if instruction_label:
		instruction_label.text = "Your turn! Click tiles in order."


func _input(event: InputEvent) -> void:
	if not _accept_input or not event.is_pressed():
		return
	if not is_instance_valid(panel_ref):
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(tile_count):
			if not is_instance_valid(tiles[i]):
				continue
			var rect: Rect2 = Rect2(tiles[i].position + panel_ref.position, tiles[i].size)
			if rect.has_point(get_viewport().get_mouse_position()):
				_on_tile_clicked(i)
				return


func _on_tile_clicked(idx: int) -> void:
	"""Handle player clicking a tile."""
	if not _accept_input or not is_instance_valid(tiles[idx]):
		return
	
	# Flash the clicked tile
	tiles[idx].color = COLOR_ON
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(tiles[idx]):
		tiles[idx].color = COLOR_OFF
	
	# Check if correct
	if idx == _sequence[_player_step]:
		_player_step += 1
		if _player_step >= _sequence.size():
			# Completed successfully
			_accept_input = false
			if instruction_label:
				instruction_label.text = "-...- Solved!"
			for i in range(tile_count):
				if is_instance_valid(tiles[i]):
					tiles[i].color = COLOR_SUCCESS
			await get_tree().create_timer(1.0).timeout
			if solved_callback.is_valid():
				solved_callback.call()
	else:
		# Wrong - reset and replay
		_accept_input = false
		for i in range(tile_count):
			if is_instance_valid(tiles[i]):
				tiles[i].color = COLOR_FAIL
		if instruction_label:
			instruction_label.text = "Wrong! Try again..."
		await get_tree().create_timer(1.0).timeout
		# Restore colors
		for i in range(tile_count):
			if is_instance_valid(tiles[i]):
				tiles[i].color = COLOR_OFF
		_player_step = 0
		_show_sequence()
