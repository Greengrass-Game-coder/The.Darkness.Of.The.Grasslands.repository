class_name AISurvivorBotController
extends GreengrassController

## AI-controlled survivor bot with improved smart behavior:
## - Flees from killer with wall avoidance + line-of-sight awareness
## - Blocks when killer is close and facing the bot
## - Heals with Spare Flower when low HP (panic-heals when critically low)
## - Solves puzzles efficiently, circles toward puzzles behind walls
## - Double-backs mid-flee to evade killer prediction
## - Conserves stamina efficiently (burst sprinting)

signal bot_solved_puzzle(_area_name: String, area_ref: Area2D)

# AI params
@export var flee_range: float = 500.0
@export var puzzle_approach_range: float = 100.0
@export var patrol_change_interval: float = 3.0
@export var solve_time: float = 3.0              # Slightly faster solve
@export var block_threshold: float = 220.0       # Block when killer is this close
@export var heal_hp_threshold: float = 35.0       # Heal when HP% below this
@export var panic_heal_threshold: float = 20.0   # Panic-heal even when killer is somewhat close
@export var safe_los_distance: float = 300.0      # Consider safe if wall blocks view at this range

@export var double_back_chance: float = 0.2       # Chance to suddenly reverse flee direction
@export var puzzle_circle_range: float = 400.0    # Try to path toward puzzles even when far

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
var _double_backed: bool = false
var _stamina_saver: bool = false                  # Don't sprint when killer is far



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
	
	# PRIORITY 0: Block if killer is facing the bot and within block range
	# (Only when not already fleeing — prevents interrupting a retreat)
	if is_instance_valid(_target_killer) and current_hp > 0.0 and not block_on_cooldown:
		if dist_to_killer <= block_threshold and not _fleeing:
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
	
	# PRIORITY 1.5: Heal when low HP
	if current_hp > 0.0 and not flower_on_cooldown and not _fleeing:
		# Panic heal: heal even when killer is close if HP is critically low
		if current_hp < panic_heal_threshold and is_instance_valid(_target_killer):
			# Only heal if killer is not in hit range
			if dist_to_killer > block_threshold:
				use_spare_flower()
				if current_state == State.HEALING:
					velocity = Vector2.ZERO
					move_and_slide()
					return
		# Normal heal: heal when safe
		elif current_hp < heal_hp_threshold:
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
	
	# PRIORITY 3: Go to nearest unsolved puzzle (with killer awareness)
	_target_puzzle = _find_nearest_unsolved_puzzle()
	if _target_puzzle != null:
		# Abort puzzle approach if killer is too close to the puzzle
		if is_instance_valid(_target_killer) and _is_killer_near_puzzle(_target_puzzle, dist_to_killer):
			_ai_patrol(delta)
			move_and_slide()
			return
		_ai_go_to_puzzle(delta)
		move_and_slide()
		return
	
	# PRIORITY 4: Patrol
	_ai_patrol(delta)
	move_and_slide()


func _is_killer_near_puzzle(puzzle: Area2D, killer_dist: float) -> bool:
	"""Check if the killer is too close to the target puzzle for safe approach."""
	if not is_instance_valid(_target_killer) or not is_instance_valid(puzzle):
		return false
	var killer_to_puzzle: float = _target_killer.global_position.distance_to(puzzle.global_position)
	return killer_to_puzzle < flee_range * 0.6


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
	
	# Conserve stamina if killer might be nearby
	var killer_threat: bool = is_instance_valid(_target_killer) and \
		global_position.distance_to(_target_killer.global_position) < flee_range * 0.8
	var use_sprint: bool = dist_to_puzzle > 200.0 and not _stamina_exhausted and not killer_threat
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
	var dist_from_killer: float = away_dir.length()
	
	# ── Double-back mechanic ──
	# Randomly reverse direction to throw off killer prediction
	if not _double_backed and randf() < double_back_chance * delta * 10.0:
		_strafe_dir *= -1.0
		_double_backed = true
		_strafe_change_timer = 0.1  # force a sharp turn next frame
	if _double_backed:
		_double_backed = false
	
	# ── Circle toward nearest puzzle while fleeing ──
	# If a puzzle exists, bias flee direction toward it (safe flanking route)
	var puzzle_bias: Vector2 = Vector2.ZERO
	_target_puzzle = _find_nearest_unsolved_puzzle()
	if is_instance_valid(_target_puzzle):
		var to_puzzle: Vector2 = _target_puzzle.global_position - global_position
		var puzzle_dist: float = to_puzzle.length()
		# Only bias if puzzle is not in the killer's direction
		var to_killer: Vector2 = _target_killer.global_position - global_position
		if to_puzzle.dot(to_killer) < 0.0 and puzzle_dist < puzzle_circle_range:
			puzzle_bias = to_puzzle.normalized() * 0.2
	
	# Strafe direction changes periodically for unpredictable movement
	_strafe_change_timer -= delta
	if _strafe_change_timer <= 0.0:
		_strafe_dir = 1.0 if randf() > 0.5 else -1.0
		_strafe_change_timer = randf_range(0.5, 1.5)
	
	var strafe: Vector2 = Vector2(-away_dir.y, away_dir.x).normalized() * _strafe_dir
	var strafe_amount: float = randf_range(0.2, 0.5)
	
	var move_dir: Vector2 = (away_dir.normalized() + strafe * strafe_amount + puzzle_bias).normalized()
	
	# Multi-raycast wall avoidance — check 7 directions for better coverage
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var ray_dists: Array[float] = [120.0, 100.0, 80.0, 60.0, 100.0, 80.0, 60.0]
	var ray_offsets: Array[float] = [0.0, -30.0, -60.0, -90.0, 30.0, 60.0, 90.0]  # Degrees
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
		# Try strafe first
		var try_dir: Vector2 = strafe.normalized()
		var try_query := PhysicsRayQueryParameters2D.create(
			global_position,
			global_position + try_dir * 80.0
		)
		try_query.collision_mask = 4
		try_query.exclude = [self]
		var try_result: Dictionary = space_state.intersect_ray(try_query)
		if try_result.is_empty():
			move_dir = try_dir
		else:
			# Try the opposite strafe direction
			try_dir = -strafe.normalized()
			try_query = PhysicsRayQueryParameters2D.create(
				global_position,
				global_position + try_dir * 80.0
			)
			try_query.collision_mask = 4
			try_query.exclude = [self]
			try_result = space_state.intersect_ray(try_query)
			if try_result.is_empty():
				move_dir = try_dir
			else:
				# Last resort: reverse away from wall
				move_dir = (away_dir.normalized() * -1.0).normalized()
	
	# ── Smart stamina management: burst sprinting ──
	# Sprint in bursts: sprint for ~2-3s, then walk for ~1s to regen
	# Don't sprint if killer is far enough away to be safe
	var use_sprint: bool = false
	if not _stamina_exhausted:
		if dist_from_killer < flee_range * 0.5:
			# Killer is close — sprint hard
			use_sprint = true
		elif dist_from_killer < flee_range:
			# Killer is moderately close — burst sprint
			_stamina_saver = not _stamina_saver if randf() < 0.01 else _stamina_saver
			use_sprint = _stamina_saver
		# If killer is far, don't sprint — conserve stamina
	
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
	
	velocity = move_dir * speed
	_update_direction(velocity)
	_play_animation("walk")
	_change_state(State.WALKING)


func _ai_patrol(delta: float) -> void:
	# Bias patrol toward nearest unsolved puzzle
	_target_puzzle = _find_nearest_unsolved_puzzle()
	if is_instance_valid(_target_puzzle):
		var to_puzzle: Vector2 = _target_puzzle.global_position - global_position
		var puzzle_dir: Vector2 = to_puzzle.normalized()
		_patrol_dir = (_patrol_dir + puzzle_dir * 0.3).normalized()
	
	_patrol_timer -= delta
	if _patrol_timer <= 0.0:
		if is_instance_valid(_target_puzzle):
			# Patrol toward puzzle zone
			_patrol_dir = _random_dir()
			_patrol_timer = patrol_change_interval * 2.0  # Longer patrol toward puzzles
		else:
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
