class_name MatchManager
extends Node
## Professional match state manager — handles timer, puzzle interaction,
## scoring, elimination tracking, and match lifecycle.
##
## Extracted from game_map.gd to separate game logic from UI/HUD/map concerns.

signal match_ended
signal timer_updated(time_remaining: float)
signal puzzle_solved(area_name: String, level: int)
signal survivor_eliminated(name: String)

const MATCH_DURATION: float = 240.0  # 4 minutes
const ELIMINATION_BONUS: float = 5.0  # +5s per elimination
const PUZZLE_DEDUCTION: float = 3.25  # seconds per puzzle level

var time_remaining: float = MATCH_DURATION
var solved_puzzles: Array[String] = []
var puzzle_open: bool = false
var match_active: bool = false

# Bonus timer animation
var _bonus_target: float = 0.0
var _bonus_tick_timer: float = 0.0

# Stats
var total_damage_taken: float = 0.0
var total_damage_dealt: float = 0.0
var character_name: String = "Greengrass"

# Local references
var _map_manager: MapManager = null
var _current_interactable: Area2D = null
var _e_was_pressed: bool = false
var _killer_bot: Node2D = null

# Timer for 1s ticks
var _tick_timer: float = 0.0


func _ready() -> void:
	_tick_timer = 0.0
	match_active = true


func _process(delta: float) -> void:
	if not match_active:
		return
	_update_tick(delta)
	_update_bonus_timer(delta)
	_check_interact_input(delta)


# ── Timer Tick ──

func _update_tick(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer >= 1.0:
		_tick_timer -= 1.0
		time_remaining -= 1.0
		time_remaining = max(time_remaining, 0.0)
		timer_updated.emit(time_remaining)

		if time_remaining <= 0.0:
			match_active = false
			match_ended.emit()


# ── Bonus Timer Animation ──

func _update_bonus_timer(delta: float) -> void:
	if _bonus_target <= 0.0:
		return
	_bonus_tick_timer += delta
	var tick_speed: float = 0.15
	while _bonus_tick_timer >= tick_speed and time_remaining < _bonus_target:
		_bonus_tick_timer -= tick_speed
		time_remaining = min(time_remaining + 1.0, _bonus_target)
		timer_updated.emit(time_remaining)
	if time_remaining >= _bonus_target:
		_bonus_target = 0.0
		_bonus_tick_timer = 0.0


func add_time_bonus(seconds: float) -> void:
	_bonus_target = min(time_remaining + seconds, MATCH_DURATION)


func deduct_time(seconds: float) -> void:
	time_remaining = max(0.0, time_remaining - seconds)
	timer_updated.emit(time_remaining)


# ── Elimination ──

func on_killer_eliminated(victim_name: String) -> void:
	add_time_bonus(ELIMINATION_BONUS)
	survivor_eliminated.emit(victim_name)


# ── Puzzle System ──

func set_interactable(area: Area2D) -> void:
	_current_interactable = area
	var prompt: Label = area.get_node_or_null("InteractPrompt")
	if prompt:
		prompt.visible = true


func clear_interactable(area: Area2D) -> void:
	if _current_interactable == area:
		_current_interactable = null
	var prompt: Label = area.get_node_or_null("InteractPrompt")
	if prompt:
		prompt.visible = false


func _check_interact_input(_delta: float) -> void:
	if _current_interactable == null:
		return
	if puzzle_open:
		return
	var area_name: String = _current_interactable.name
	if area_name in solved_puzzles:
		return

	if InputSystem.is_pressed("interact") and not _e_was_pressed:
		_e_was_pressed = true
		puzzle_open = true
		_open_puzzle()
	elif not InputSystem.is_pressed("interact"):
		_e_was_pressed = false


func _open_puzzle() -> void:
	if _current_interactable == null:
		return
	var area: Area2D = _current_interactable

	var prompt: Label = area.get_node_or_null("InteractPrompt")
	if prompt:
		prompt.visible = false

	var puz_scene: PuzzleManager = PuzzleManager.new()
	add_child(puz_scene)

	var forced_type: int = PuzzleManager.PuzzleType.RHYTHM
	var zone_type: String = area.get_meta("puzzle_type", "Rhythm")
	match zone_type:
		"Memory": forced_type = PuzzleManager.PuzzleType.MEMORY
		"Wiring": forced_type = PuzzleManager.PuzzleType.WIRING

	puz_scene.open_puzzle(area, get_parent().get("_player"), 1, forced_type)
	puz_scene.puzzle_completed.connect(_on_puzzle_completed.bind(area))
	puz_scene.puzzle_closed.connect(_on_puzzle_closed.bind(puz_scene))


func _on_puzzle_completed(area: Area2D, puzzle_level: int = 1) -> void:
	var area_name: String = area.name
	if not area_name in solved_puzzles:
		solved_puzzles.append(area_name)

	# Rewards
	var gs = get_node("/root/GameState")
	if gs != null:
		gs.add_money(5)
		var username: String = gs.logged_in_username
		if username != "":
			var rings: int = gs.get_player_rings(username)
			gs.set_player_rings(username, rings + 1)

	deduct_time(PUZZLE_DEDUCTION * puzzle_level)
	puzzle_solved.emit(area_name, puzzle_level)

	var prompt: Label = area.get_node_or_null("InteractPrompt")
	if prompt:
		prompt.text = "✓ Solved!"
	if area.has_node("ColorRect"):
		var rect: ColorRect = area.get_node("ColorRect")
		rect.color = Color(0.2, 0.8, 0.2, 0.5)


func _on_puzzle_closed(puz_scene: PuzzleManager) -> void:
	puzzle_open = false
	if is_instance_valid(puz_scene):
		puz_scene.queue_free()


func set_references(map_manager: MapManager, killer_bot: Node2D) -> void:
	_map_manager = map_manager
	_killer_bot = killer_bot


func get_timer_text() -> String:
	var total_seconds: int = int(time_remaining)
	var minutes: int = int(total_seconds / 60.0)
	var seconds: int = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]
