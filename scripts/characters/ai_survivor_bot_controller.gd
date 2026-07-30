class_name AISurvivorBotController
extends GreengrassController

## AI-controlled survivor bot with smart behavior:
## - Flees from killer with wall avoidance + line-of-sight awareness
## - Blocks when killer is close and facing the bot
## - Heals with Spare Flower when low HP
## - Solves puzzles and patrols when safe

signal bot_solved_puzzle(_area_name: String, area_ref: Area2D)

# AI params
@export var flee_range: float = 500.0
@export var puzzle_approach_range: float = 100.0
@export var patrol_change_interval: float = 3.0
@export var solve_time: float = 4.0
@export var block_threshold: float = 200.0       # Block when killer is this close
@export var heal_hp_threshold: float = 30.0       # Heal when HP% below this
@export var safe_los_distance: float = 300.0      # Consider safe if wall blocks view at this range

var _target_killer: Node2D = null
var _target_puzzle: Area2D = null
var _solved_names: Array[String] = []
var _patrol_dir: Vector2 = Vector2.RIGHT
var _patrol_timer: float = 0.0
var _solving: bool = false
var _solve_timer: float = 0.0
var _current_target_puzzle: Area2D = null
var _fleeing: bool = false
var _strafe_dir: float = 1.0
var _strafe_change_timer: float = 0.0
var _just_hit_timer: float = 0.0
var _has_los_to_killer: bool = false


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
		_just_hit_timer = 0.5
		return
	
	if current_state in [State.PUNCHING, State.PUNCH_CHARGING, State.HEALING]:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_cooldowns(delta)
		return
	
	_update_cooldowns(delta)
	
	if _just_hit_timer > 0.0:
		_just_hit_timer -= delta
	
	if _stamina_exhausted:
		_exhaustion_timer -= delta
		if _exhaustion_timer <= 0:
			_stamina_exhausted = false
	
	_find_nearest_killer()
	_check_los_to_killer()
	
	var dist_to_killer: float = INF
	if is_instance_valid(_target_killer):
		dist_to_killer = global_position.distance_to(_target_killer.global_position)
	
	# Effective flee range: shorter if wall blocks LOS (bot feels safer behind walls)
	var effective_flee: float = flee_range if _has_los_to_killer else safe_los_distance
	var killer_close: bool = is_instance_valid(_target_killer) and dist_to_killer <= effective_flee
	
	# PRIORITY 0: Block if killer is close, facing the bot, and not already fleeing
	if is_instance_valid(_target_killer) and current_hp > 0.0 and not killer_close:
		if dist_to_killer <= block_threshold and not block_on_cooldown and not _fleeing:
			var killer_dir: Vector2 = _target_killer.get("facing_direction") if "facing_direction" in _target_killer else Vector2.DOWN
			var to_bot: Vector2 = (global_position - _target_killer.global_position).normalized()
			if killer_dir.dot(to_bot) > 0.3:
				use_block()
	
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
	
	# PRIORITY 1.5: Heal when low HP and safe (not fleeing)
	if current_hp > 0.0 and current_hp < heal_hp_threshold and not flower_on_cooldown and not _fleeing:
		use_spare_flower()
		if current_state == State.HEALING:
			velocity = Vector2.ZERO
			move_and_slide()
			return
	
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


func _check_los_to_killer() -> void:
	"""Check if a wall blocks LOS from killer to bot."""
	if not is_instance_valid(_target_killer):
		_has_los_to_killer = false
		return
	
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		_target_killer.global_position,
		global_position
	)
	query.collision_mask = 4  # Wall layer
	query.exclude = [self, _target_killer]
	var result: Dictionary = space_state.intersect_ray(query)
	_has_los_to_killer = result.is_empty()


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
	var _dist: float = away_dir.length()
	
	# Strafe direction changes periodically for unpredictable movement
	_strafe_change_timer -= delta
	if _strafe_change_timer <= 0.0:
		_strafe_dir = 1.0 if randf() > 0.5 else -1.0
		_strafe_change_timer = randf_range(0.5, 1.5)
	
	var strafe: Vector2 = Vector2(-away_dir.y, away_dir.x).normalized() * _strafe_dir
	var strafe_amount: float = randf_range(0.2, 0.5)
	
	var move_dir: Vector2 = (away_dir.normalized() + strafe * strafe_amount).normalized()
	
	# Multi-raycast wall avoidance — check center, left, and right
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var ray_dists: Array[float] = [60.0, 80.0, 100.0]
	var ray_offsets: Array[float] = [0.0, 45.0, -45.0]  # Degrees
	var blocked: bool = false
	
	for i in range(ray_offsets.size()):
		var rotated_dir: Vector2 = move_dir.rotated(deg_to_rad(ray_offsets[i]))
		var query := PhysicsRayQueryParameters2D.create(
			global_position,
			global_position + rotated_dir * ray_dists[i]
		)
		query.collision_mask = 4  # Wall layer
		query.exclude = [self]
		var result: Dictionary = space_state.intersect_ray(query)
		if not result.is_empty():
			blocked = true
			break
	
	if blocked:
		move_dir = strafe.normalized()
		# Check if strafe is also blocked
		var strafe_query := PhysicsRayQueryParameters2D.create(
			global_position,
			global_position + move_dir * 60.0
		)
		strafe_query.collision_mask = 4
		strafe_query.exclude = [self]
		if not space_state.intersect_ray(strafe_query).is_empty():
			# Last resort: reverse direction
			move_dir = (away_dir.normalized() * -0.5 + strafe.normalized()).normalized()
	
	var use_sprint: bool = not _stamina_exhausted
	var speed: float = sprint_speed if use_sprint else move_speed
	
	if use_sprint:
		current_stamina -= sprint_stamina_drain * delta
		if current_stamina <= 0.0:
			current_stamina = 0.0
			_stamina_exhausted = true
			_exhaustion_timer = 3.0
		_stamina_regen_timer = stamina_regen_delay
	
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
