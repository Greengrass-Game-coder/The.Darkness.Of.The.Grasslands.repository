class_name AISurvivorBotController
extends GreengrassController

## AI-controlled survivor bot:
## - Moves toward unsolved puzzle zones and "solves" them
## - Runs away from the killer when close

signal bot_solved_puzzle(_area_name: String, area_ref: Area2D)

# AI params
@export var flee_range: float = 500.0
@export var puzzle_approach_range: float = 100.0
@export var patrol_change_interval: float = 3.0
@export var solve_time: float = 4.0

var _target_killer: Node2D = null
var _target_puzzle: Area2D = null
var _solved_names: Array[String] = []
var _patrol_dir: Vector2 = Vector2.RIGHT
var _patrol_timer: float = 0.0
var _solving: bool = false
var _solve_timer: float = 0.0
var _current_target_puzzle: Area2D = null
var _fleeing: bool = false


func _ready() -> void:
	super()
	modulate = Color(0.7, 0.7, 1.0, 1.0)
	
	var label := BitmapLabel.new()
	label.name = "BotLabel"
	label.label_text = "SURVIVOR BOT"
	label.position = Vector2(-35, -50)
	label.font_scale = 0.12
	label.font_color = Color(0.5, 0.8, 1.0, 1.0)
	add_child(label)


func _input(_event: InputEvent) -> void:
	pass


func _physics_process(delta: float) -> void:
	if current_state == State.STUNNED:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_cooldowns(delta)
		return
	
	if current_state in [State.PUNCHING, State.PUNCH_CHARGING, State.HEALING]:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_cooldowns(delta)
		return
	
	_update_cooldowns(delta)
	
	if _stamina_exhausted:
		_exhaustion_timer -= delta
		if _exhaustion_timer <= 0:
			_stamina_exhausted = false
	
	_find_nearest_killer()
	
	var killer_close: bool = is_instance_valid(_target_killer) and 		global_position.distance_to(_target_killer.global_position) <= flee_range
	
	# PRIORITY 1: Flee from killer
	if killer_close and is_instance_valid(_target_killer):
		_fleeing = true
		_solving = false
		_current_target_puzzle = null
		_ai_flee(delta)
		move_and_slide()
		return
	else:
		_fleeing = false
	
	# PRIORITY 2: Solve a puzzle
	if _solving and _current_target_puzzle != null:
		_solve_timer -= delta
		if _solve_timer <= 0:
			_on_puzzle_solved()
		velocity = Vector2.ZERO
		move_and_slide()
		_change_state(State.IDLE)
		_play_animation("idle")
		return
	_solving = false
	_current_target_puzzle = null
	
	# PRIORITY 3: Go to nearest unsolved puzzle
	_target_puzzle = _find_nearest_unsolved_puzzle()
	if _target_puzzle != null:
		_ai_go_to_puzzle(delta)
		move_and_slide()
		return
	
	# PRIORITY 4: Patrol
	_ai_patrol(delta)
	move_and_slide()


func _find_nearest_killer() -> void:
	var killers: Array[Node] = get_tree().get_nodes_in_group("killers")
	var nearest: Node2D = null
	var nearest_dist: float = flee_range * 2.0
	for k in killers:
		if is_instance_valid(k) and k != self:
			var d: float = global_position.distance_to(k.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = k as Node2D
	_target_killer = nearest


func _find_nearest_unsolved_puzzle() -> Area2D:
	var parent: Node = get_parent()
	if not parent:
		return null
	var nearest: Area2D = null
	var nearest_dist: float = INF
	for child in parent.get_children():
		if child is Area2D and child.name.begins_with("Puzzle_"):
			if child.name in _solved_names:
				continue
			var d: float = global_position.distance_to(child.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = child as Area2D
	return nearest


func _ai_go_to_puzzle(delta: float) -> void:
	if not is_instance_valid(_target_puzzle):
		_ai_patrol(delta)
		return
	
	var dir: Vector2 = _target_puzzle.global_position - global_position
	var dist_to_puzzle: float = dir.length()
	
	if dist_to_puzzle <= puzzle_approach_range:
		_solving = true
		_solve_timer = solve_time
		_current_target_puzzle = _target_puzzle
		_change_state(State.IDLE)
		_play_animation("idle")
		velocity = Vector2.ZERO
		return
	
	var use_sprint: bool = dist_to_puzzle > 200.0 and not _stamina_exhausted
	var speed: float = sprint_speed if use_sprint else move_speed
	
	if use_sprint:
		current_stamina -= sprint_stamina_drain * delta
		if current_stamina <= 0.0:
			current_stamina = 0.0
			_stamina_exhausted = true
			_exhaustion_timer = 3.0
		_stamina_regen_timer = stamina_regen_delay
	else:
		if current_stamina < max_stamina:
			_stamina_regen_timer -= delta
			if _stamina_regen_timer <= 0.0:
				current_stamina += stamina_regen * delta
				if current_stamina > max_stamina:
					current_stamina = max_stamina
	
	velocity = dir.normalized() * speed
	_update_direction(velocity)
	_play_animation("walk")
	_change_state(State.WALKING)


func _ai_flee(delta: float) -> void:
	if not is_instance_valid(_target_killer):
		_ai_patrol(delta)
		return
	
	var away_dir: Vector2 = global_position - _target_killer.global_position
	var _dist: float = global_position.distance_to(_target_killer.global_position)
	
	var strafe: Vector2 = Vector2(-away_dir.y, away_dir.x).normalized()
	var strafe_amount: float = 0.3 if randf() < 0.02 else 0.15
	
	var move_dir: Vector2 = (away_dir.normalized() + strafe * strafe_amount).normalized()
	
	var use_sprint: bool = not _stamina_exhausted
	var speed: float = sprint_speed if use_sprint else move_speed
	
	if use_sprint:
		current_stamina -= sprint_stamina_drain * delta
		if current_stamina <= 0.0:
			current_stamina = 0.0
			_stamina_exhausted = true
			_exhaustion_timer = 3.0
		_stamina_regen_timer = stamina_regen_delay
	
	# Wall avoidance raycast
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var wall_query := PhysicsRayQueryParameters2D.create(global_position, global_position + move_dir * 80.0)
	wall_query.collision_mask = 4
	wall_query.exclude = [self]
	var wall_result: Dictionary = space_state.intersect_ray(wall_query)
	
	if not wall_result.is_empty():
		move_dir = strafe.normalized()
	
	velocity = move_dir * speed
	_update_direction(velocity)
	_play_animation("walk")
	_change_state(State.WALKING)


func _ai_patrol(delta: float) -> void:
	_patrol_timer -= delta
	if _patrol_timer <= 0.0:
		_patrol_dir = _random_dir()
		_patrol_timer = patrol_change_interval
	
	velocity = _patrol_dir * move_speed * 0.6
	_update_direction(velocity)
	_play_animation("walk")
	_change_state(State.WALKING)


func _random_dir() -> Vector2:
	var dirs: Array[Vector2] = [
		Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP,
		Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(),
		Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()
	]
	return dirs[randi() % dirs.size()]


func _on_puzzle_solved() -> void:
	if not is_instance_valid(_current_target_puzzle):
		_solving = false
		return
	
	var area_name: String = _current_target_puzzle.name
	_solved_names.append(area_name)
	bot_solved_puzzle.emit(area_name, _current_target_puzzle)
	_solving = false
	_current_target_puzzle = null
	print("AISurvivorBot: Solved puzzle ", area_name)


func is_bot() -> bool:
	return true
