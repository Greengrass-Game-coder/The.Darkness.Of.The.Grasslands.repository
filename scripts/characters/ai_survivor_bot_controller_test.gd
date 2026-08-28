class_name AISurvivorBotControllerTest
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
# Performance: cache the killer reference and re-scan infrequently rather than
# calling get_nodes_in_group("killers") every physics frame.
var _killer_scan_timer: float = 0.0
const KILLER_REScan_INTERVAL: float = 0.5
# Cache the nearest unsolved puzzle so we don't rescan get_children() every frame.
var _cached_puzzles: Array[Area2D] = []
# Cache the chosen break-LOS flee target so the 9-raycast fan isn't computed
# every physics frame; recompute only every ~0.25s.
var _flee_target: Vector2 = Vector2.ZERO
var _flee_target_timer: float = 0.0
const FLEE_TARGET_RECOMPUTE_INTERVAL: float = 0.25
var _solved_names: Array[String] = []
var _patrol_dir: Vector2 = Vector2.RIGHT
var _patrol_target: Vector2 = Vector2.ZERO
var _patrol_timer: float = 0.0
var _solving: bool = false
var _solve_timer: float = 0.0
var _current_target_puzzle: Area2D = null
var _fleeing: bool = false
var _strafe_dir: float = 1.0
var _strafe_change_timer: float = 0.0
var _just_hit_timer: float = 0.0
var _has_los_to_killer: bool = false

# "human" behaviors:
var _hide_timer: float = 0.0      # Holds still (hidden) after LOS breaks mid-flee
var _puzzle_index: int = 0        # Bot's chosen puzzle slot for distribution

# NavigationAgent2D for pathfinding around walls
var _navigation_agent: NavigationAgent2D = null
var _nav_target: Vector2 = Vector2.ZERO
var _nav_target_set: bool = false

# Cached reference to the MapManager (provides patrol "tracks" and loop anchors).
var _map_mgr: Node = null
# Active "loop the killer" orbit state: the chosen obstacle's orbit group and
# which orbit point we're heading to next (cycling keeps us orbiting).
var _loop_group: Array = []
var _loop_index: int = 0

# Anti-stuck: detects when the bot is pushing into a wall (trying to move but
# barely progressing) and applies a perpendicular nudge + retarget to scrape off.
var _stuck_timer: float = 0.0
var _last_stuck_check_pos: Vector2 = Vector2.ZERO
const STUCK_PROGRESS_THRESHOLD: float = 4.0   # px moved in the window to count as "moving"
const STUCK_WINDOW: float = 0.5                # seconds before we consider the bot stuck
var _stuck_nudge_dir: float = 1.0             # which way to scrape off the wall

# Wall-avoidance steering: raycasts ahead of the bot and steers around obstacles
# so it doesn't run head-on into walls while pathing or patrolling.
var _avoid_cooldown: float = 0.0
const AVOID_RAY_LENGTH: float = 34.0          # how far ahead we probe for walls
const AVOID_RAY_COUNT: int = 5                # fan of rays around the heading
const AVOID_FOV_DEG: float = 70.0             # half-angle of the probe fan


func _ready() -> void:
	super()
	modulate = Color(0.7, 0.7, 1.0, 1.0)
	# Give each bot a distinct puzzle slot so several bots don't all swarm the
	# same puzzle. Parsed from the bot's name ("SurvivorBot_N").
	for ch: String in str(name).split(""):
		if ch.is_valid_int():
			_puzzle_index = int(ch)
			break
	
	# Create NavigationAgent2D for pathfinding
	_navigation_agent = NavigationAgent2D.new()
	_navigation_agent.name = "NavigationAgent"
	_navigation_agent.path_desired_distance = 8.0
	_navigation_agent.target_desired_distance = 8.0
	add_child(_navigation_agent)
	
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
		# Abort puzzle approach if the killer is too close to the puzzle OR is
		# actively chasing THIS bot (killer right on top of us).
		if is_instance_valid(_target_killer) and _is_killer_near_puzzle(_target_puzzle, dist_to_killer):
			_ai_patrol(delta)
			move_and_slide()
			return
		# SMART PACE: if the killer is clearly busy chasing another survivor far
		# away, this bot keeps solving instead of scattering — a "teamwork"
		# behavior real players rely on.
		if is_instance_valid(_target_killer) and _is_killer_busy_with_other(dist_to_killer):
			_ai_go_to_puzzle(delta)
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
	# Abort if killer is right on top of the bot too (it's chasing us)
	if killer_dist < block_threshold:
		return true
	var killer_to_puzzle: float = _target_killer.global_position.distance_to(puzzle.global_position)
	return killer_to_puzzle < flee_range * 0.6


func _is_killer_busy_with_other(self_dist_to_killer: float) -> bool:
	"""true when the killer is far from THIS bot, meaning they're likely chasing
	(or hunting) another survivor. Real survivors keep doing puzzles then."""
	if not is_instance_valid(_target_killer):
		return false
	# If the killer is way outside our flee range, they're not after us → keep
	# working. (self_dist is the distance to the killer this frame.)
	return self_dist_to_killer > flee_range


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
	# Cache the killer reference; only re-scan the group when the cached ref is
	# freed or after the scan interval elapses (there is at most one killer).
	if is_instance_valid(_target_killer):
		_killer_scan_timer -= get_physics_process_delta_time()
		if _killer_scan_timer > 0.0:
			return
	_killer_scan_timer = KILLER_REScan_INTERVAL
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
	# Cache the list of puzzle Area2D children once, then reuse it. The puzzle
	# nodes are created at match start and only removed when solved/freed, so a
	# full get_children() scan every frame is wasteful.
	if _cached_puzzles.is_empty():
		var parent: Node = get_parent()
		if parent:
			for child in parent.get_children():
				if child is Area2D and child.name.begins_with("Puzzle_"):
					_cached_puzzles.append(child as Area2D)
	# Distribution: each bot claims a DIFFERENT unsolved puzzle slot so several
	# bots spread across the map instead of all piling onto one puzzle.
	if not _cached_puzzles.is_empty() and _cached_puzzles.size() > 1:
		var unsolved: Array[Area2D] = []
		for puzzle in _cached_puzzles:
			if is_instance_valid(puzzle) and not puzzle.name in _solved_names:
				unsolved.append(puzzle as Area2D)
		if not unsolved.is_empty():
			return unsolved[_puzzle_index % unsolved.size()]
	
	var nearest: Area2D = null
	var nearest_dist: float = INF
	for puzzle in _cached_puzzles:
		if not is_instance_valid(puzzle):
			continue
		if puzzle.name in _solved_names:
			continue
		var d: float = global_position.distance_to(puzzle.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = puzzle
	return nearest


func _ai_go_to_puzzle(delta: float) -> void:
	if not is_instance_valid(_target_puzzle):
		_ai_patrol(delta)
		return
	
	var target_pos: Vector2 = _target_puzzle.global_position
	var dir: Vector2 = target_pos - global_position
	var dist_to_puzzle: float = dir.length()
	
	if dist_to_puzzle <= puzzle_approach_range:
		_solving = true
		_solve_timer = solve_time
		_current_target_puzzle = _target_puzzle
		_change_state(State.IDLE)
		_play_animation("idle")
		velocity = Vector2.ZERO
		return
	
	# Use NavigationAgent2D to find path around walls to puzzle
	var nav_dir: Vector2 = _navigate_to(target_pos)
	if nav_dir.length_squared() > 0.01:
		dir = nav_dir
	
	# Conserve stamina if killer might be nearby
	var killer_threat: bool = is_instance_valid(_target_killer) and \
		global_position.distance_to(_target_killer.global_position) < flee_range * 0.8
	var use_sprint: bool = dist_to_puzzle > 200.0 and not _stamina_exhausted and not killer_threat
	var speed: float = sprint_speed if use_sprint else move_speed
	# Steer around walls before committing to this heading.
	dir = _avoid_walls(dir.normalized())
	
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
	
	var to_killer: Vector2 = _target_killer.global_position - global_position
	var dist_from_killer: float = to_killer.length()
	var away_dir: Vector2 = (-to_killer).normalized()
	var perpendicular: Vector2 = Vector2(-to_killer.y, to_killer.x).normalized()
	
	# ── 0. HIDE IN COVER ──
	# Once the bot has broken LOS from the killer (wall between them) and the
	# killer is farther out, it stops and "hides" briefly instead of sprinting for
	# ever — like a real player holding still behind a corner. Peek/re-approach
	# after a short hold so it doesn't camp forever.
	if not _has_los_to_killer and dist_from_killer > block_threshold * 0.7:
		_hide_timer += delta
		if _hide_timer < 0.9:
			velocity = Vector2.ZERO
			_change_state(State.IDLE)
			_play_animation("idle")
			move_and_slide()
			return
	# Reset the hide timer whenever the killer actually sees/approaches us again.
	if _has_los_to_killer and dist_from_killer < safe_los_distance:
		_hide_timer = 0.0
	
	# ── 0.5 LOOP THE KILLER ──
	# When the killer has a clear line of sight and is actively chasing, run to
	# a nearby wall obstacle and orbit it. The wall stays between the bot and
	# the killer, so the killer can't catch the bot in a straight line — the
	# classic survivor "loop." Falls back to normal fleeing if no obstacle is
	# handy. Only when LOS is present (killer is actually chasing).
	if _has_los_to_killer and dist_from_killer < flee_range * 0.75:
		var loop_dir: Vector2 = _ai_loop_killer(away_dir)
		if loop_dir != Vector2.ZERO:
			var move_dir2: Vector2 = _anti_stuck(delta, loop_dir)
			move_dir2 = _avoid_walls(move_dir2.normalized())
			var use_sprint2: bool = (not _stamina_exhausted) and (dist_from_killer < 220.0 or _has_los_to_killer)
			var speed2: float = sprint_speed if use_sprint2 else (move_speed * 0.75)
			if use_sprint2:
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
			velocity = move_dir2 * speed2
			_update_direction(velocity)
			_play_animation("walk")
			_change_state(State.WALKING)
			return
	# Killer broke chase (or no obstacle to loop) — drop the active orbit so the
	# next chase picks a fresh loop point.
	_loop_group = []

	# ── 1. Choose a flee target that BREAKS line-of-sight (runs around walls) ──
	# The bot samples a fan of candidate directions and picks the one that both
	# moves away from the killer AND puts a wall between them — so it disappears
	# around corners instead of sprinting in a straight, predictable line.
	# Recompute the break-LOS flee target only periodically (it runs a 9-way
	# raycast fan); reuse the cached target between recomputes.
	_flee_target_timer -= delta
	if _flee_target_timer <= 0.0:
		_flee_target = _pick_break_los_target(away_dir)
		_flee_target_timer = FLEE_TARGET_RECOMPUTE_INTERVAL
	var flee_target: Vector2 = _flee_target
	
	# ── 2. Perpendicular cut when the killer is very close ──
	# When the killer is nearly on top of the bot, dodge laterally (perpendicular
	# to the killer's approach) to cut vision and avoid a direct lunge, rather
	# than running straight away.
	var move_dir: Vector2 = (flee_target - global_position).normalized()
	if move_dir.length_squared() < 0.01:
		move_dir = away_dir
	if dist_from_killer < 220.0:
		move_dir = (away_dir + perpendicular * 0.9).normalized()
	
	# ── 3. Navigation around walls ──
	var nav_dir: Vector2 = _navigate_to(flee_target)
	if nav_dir.length_squared() > 0.01:
		move_dir = nav_dir.normalized()
	
	# ── 4. Deliberate juke only when the killer is about to hit ──
	# Instead of randomly strafing every 0.5-1.5s (which reads as chaotic), only
	# reverse direction when the killer is genuinely close — that reads as a real
	# dodge, not a dumb zig-zag.
	var juke: Vector2 = Vector2.ZERO
	if dist_from_killer < 200.0:
		_strafe_change_timer -= delta
		if _strafe_change_timer <= 0.0:
			_strafe_dir *= -1.0
			_strafe_change_timer = randf_range(0.3, 0.6)
		juke = perpendicular * _strafe_dir * 0.5
	move_dir = (move_dir + juke).normalized()

	# ── 5b. Anti-stuck: scrape off walls the bot is pushing into ──
	move_dir = _anti_stuck(delta, move_dir)
	# ── 5c. Wall-avoidance steering: don't run head-on into walls ──
	move_dir = _avoid_walls(move_dir.normalized())

	# ── 5. Smarter stamina ──
	# Sprint only when the killer has line-of-sight AND is close (or is right on
	# top of us). When LOS is broken by a wall, the bot slows down and conserves
	# stamina instead of sprinting endlessly.
	var use_sprint: bool = false
	if not _stamina_exhausted:
		if dist_from_killer < 200.0:
			use_sprint = true  # Emergency speed when killer is on top of us
		elif _has_los_to_killer and dist_from_killer < flee_range * 0.6:
			use_sprint = true  # Killer sees us and is chasing — burn stamina
	
	# When LOS is broken, move cautiously (hide) rather than sprint on.
	var speed: float = sprint_speed if use_sprint else (move_speed * 0.7)
	
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


func _pick_break_los_target(away_dir: Vector2) -> Vector2:
	"""
	Choose a flee position that moves away from the killer AND breaks line-of-sight
	(so the bot runs around/behind walls instead of straight away). Samples a fan
	of candidate directions and scores each: LOS-breaking corners are strongly
	preferred, with a secondary preference for moving away.
	"""
	if not is_instance_valid(_target_killer):
		return global_position + away_dir * 250.0
	
	var candidates: Array[Vector2] = []
	var base: float = away_dir.angle()
	var step: float = 0.45  # ~26 degrees — 5 candidates still cover the fan
	for j: int in range(-2, 3):
		var ang: float = base + step * float(j)
		candidates.append(Vector2.RIGHT.rotated(ang))
	
	var best: Vector2 = global_position + away_dir * 250.0
	var best_score: float = -INF
	
	for cand_dir: Vector2 in candidates:
		var target: Vector2 = global_position + cand_dir * 250.0
		var breaks_los: bool = _point_breaks_los(target)
		var score: float = (1000.0 if breaks_los else 0.0) \
			+ cand_dir.dot(away_dir) * 200.0 \
			+ (1.0 / (1.0 + global_position.distance_to(target) / 100.0))
		if score > best_score:
			best_score = score
			best = target
	
	return best


func _point_breaks_los(target_pos: Vector2) -> bool:
	"""True if a wall blocks the killer's line of sight to target_pos."""
	if not is_instance_valid(_target_killer):
		return false
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		_target_killer.global_position,
		target_pos
	)
	query.collision_mask = 4  # Wall layer
	query.exclude = [self, _target_killer]
	var result: Dictionary = space_state.intersect_ray(query)
	return not result.is_empty()


func _ai_patrol(delta: float) -> void:
	# Bias patrol toward nearest unsolved puzzle
	_target_puzzle = _find_nearest_unsolved_puzzle()
	
	_patrol_timer -= delta
	if _patrol_timer <= 0.0:
		if is_instance_valid(_target_puzzle):
			# Patrol toward puzzle zone
			_patrol_target = _target_puzzle.global_position + Vector2(randf_range(-100, 100), randf_range(-100, 100))
			_patrol_timer = patrol_change_interval * 2.0
		else:
			# Follow the map's patrol 'tracks' (waypoint lanes) when no puzzle is
			# active, so bots move along readable lines instead of wandering.
			var wp: Vector2 = _pick_patrol_waypoint()
			if wp != Vector2.ZERO:
				_patrol_target = wp
			else:
				_patrol_target = global_position + _random_dir() * randf_range(150, 300)
			_patrol_timer = patrol_change_interval
	
	# Use NavigationAgent2D to navigate to patrol target
	if _patrol_target.length_squared() > 0.0:
		var nav_dir: Vector2 = _navigate_to(_patrol_target)
		if nav_dir.length_squared() > 0.01:
			_patrol_dir = nav_dir
	
	# Anti-stuck: scrape off walls while patrolling too
	_patrol_dir = _anti_stuck(delta, _patrol_dir)
	# Wall-avoidance steering while patrolling.
	_patrol_dir = _avoid_walls(_patrol_dir.normalized())
	
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


# ── Navigation helpers ──

func _get_map_manager() -> Node:
	"""Cache a reference to the map's MapManager (group 'map_manager'), which
	holds the patrol 'track' waypoints and the loop-the-killer orbit anchors."""
	if _map_mgr == null or not is_instance_valid(_map_mgr):
		_map_mgr = get_tree().get_first_node_in_group("map_manager")
	return _map_mgr


func _pick_patrol_waypoint() -> Vector2:
	"""Return a patrol waypoint (a 'track' point) to head toward. Prefers one a
	healthy distance away so the bot actually travels the map along the lanes,
	falling back to the nearest one. Returns Vector2.ZERO if no tracks exist."""
	var mm: Node = _get_map_manager()
	if mm == null or mm.patrol_waypoints.is_empty():
		return Vector2.ZERO
	var candidates: Array[Vector2] = []
	for wp: Vector2 in mm.patrol_waypoints:
		if global_position.distance_to(wp) > 160.0:
			candidates.append(wp)
	if not candidates.is_empty():
		return candidates[randi() % candidates.size()]
	var nearest: Vector2 = mm.patrol_waypoints[0]
	var nd: float = INF
	for wp: Vector2 in mm.patrol_waypoints:
		var d: float = global_position.distance_to(wp)
		if d < nd:
			nd = d
			nearest = wp
	return nearest


func _ai_loop_killer(away_dir: Vector2) -> Vector2:
	"""Pick a direction that navigates to the nearest wall obstacle and ORBITS
	it, keeping the wall between the bot and the killer — the classic
	'loop the killer' escape. Returns Vector2.ZERO if no loop target is nearby."""
	var mm: Node = _get_map_manager()
	if mm == null or mm.loop_orbits.is_empty():
		return Vector2.ZERO
	if not is_instance_valid(_target_killer):
		return Vector2.ZERO
	# If we have no active orbit, grab the nearest obstacle's orbit group and
	# start at the point farthest from the killer (the far side of the obstacle).
	if _loop_group.is_empty():
		var best_group: Array = []
		var best_dist: float = flee_range
		for orbit: Array in mm.loop_orbits:
			for p: Vector2 in orbit:
				var d: float = global_position.distance_to(p)
				if d < best_dist:
					best_dist = d
					best_group = orbit
		if best_group.is_empty():
			return Vector2.ZERO
		_loop_group = best_group
		_loop_index = 0
		var best_score: float = -INF
		for i in range(_loop_group.size()):
			var p: Vector2 = _loop_group[i]
			var score: float = p.distance_to(_target_killer.global_position) - global_position.distance_to(p)
			if score > best_score:
				best_score = score
				_loop_index = i
	# Cycle to the next orbit point once we reach the current one, so we keep
	# circling the obstacle (the killer has to run around it after us).
	var cur: Vector2 = _loop_group[_loop_index]
	if global_position.distance_to(cur) < 46.0:
		_loop_index = (_loop_index + 1) % _loop_group.size()
		cur = _loop_group[_loop_index]
	var nav_dir: Vector2 = _navigate_to(cur)
	if nav_dir.length_squared() < 0.01:
		return (cur - global_position).normalized()
	return nav_dir.normalized()


func _navigate_to(target_pos: Vector2) -> Vector2:
	"""
	Set a navigation target and return the movement direction toward it.
	Returns the direction to the next path waypoint, or Vector2.ZERO if
	no path is available (navigation not synced yet).
	Falls back to direct direction if NavigationAgent2D isn't ready.
	"""
	if not is_instance_valid(_navigation_agent):
		return Vector2.ZERO

	# Update target if it changed
	if _nav_target.distance_squared_to(target_pos) > 100.0 or not _nav_target_set:
		_navigation_agent.target_position = target_pos
		_nav_target = target_pos
		_nav_target_set = true

	# Check if navigation map is synced
	if NavigationServer2D.map_get_iteration_id(_navigation_agent.get_navigation_map()) == 0:
		# Navigation not ready yet — fall back to direct direction
		return (target_pos - global_position).normalized()

	if _navigation_agent.is_navigation_finished():
		return (target_pos - global_position).normalized()

	var next_pos: Vector2 = _navigation_agent.get_next_path_position()
	var dir: Vector2 = (next_pos - global_position).normalized()
	if dir.length_squared() < 0.01:
		return (target_pos - global_position).normalized()
	return dir


func _anti_stuck(delta: float, move_dir: Vector2) -> Vector2:
	"""
	Detect and recover from wall-sticking. If the bot has been trying to move but
	has barely progressed over the window, it is likely pushing into a wall. Apply
	a perpendicular nudge to scrape along the wall and force a flee-target retarget.
	Returns a possibly-nudged movement direction.
	"""
	if _last_stuck_check_pos == Vector2.ZERO:
		_last_stuck_check_pos = global_position
		return move_dir

	var moved: float = global_position.distance_to(_last_stuck_check_pos)
	if moved < STUCK_PROGRESS_THRESHOLD:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
	_last_stuck_check_pos = global_position

	if _stuck_timer < STUCK_WINDOW:
		return move_dir

	# Stuck against a wall: nudge perpendicular to clear it, then retarget.
	_stuck_timer = 0.0
	_stuck_nudge_dir *= -1.0
	var perp: Vector2 = Vector2(-move_dir.y, move_dir.x)
	var nudged: Vector2 = (move_dir + perp * _stuck_nudge_dir * 0.8).normalized()
	# Force a flee-target recompute so nav picks a path around the wall.
	_flee_target_timer = 0.0
	_nav_target_set = false
	return nudged


func _avoid_walls(move_dir: Vector2) -> Vector2:
	"""Steer around obstacles instead of running head-on into them.
	Fires a fan of raycasts in the movement direction; if the front is blocked
	but a side is open, rotate toward the open side. Lightweight (only re-probes
	after a short cooldown) so it layers cleanly on top of navigation."""
	if _avoid_cooldown > 0.0:
		_avoid_cooldown -= get_physics_process_delta_time()
		return move_dir
	if move_dir.length_squared() < 0.01:
		return move_dir

	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var base_angle: float = move_dir.angle()
	var front_blocked: bool = false
	var best_open_angle: float = 0.0
	var best_open: float = -1.0
	var center_idx: int = int(AVOID_RAY_COUNT * 0.5)

	for i in range(AVOID_RAY_COUNT):
		var rel: float = (float(i) / float(AVOID_RAY_COUNT - 1) - 0.5) * 2.0
		var ang: float = base_angle + deg_to_rad(rel * AVOID_FOV_DEG)
		var dir: Vector2 = Vector2.from_angle(ang)
		var from: Vector2 = global_position + dir * 10.0
		var to: Vector2 = global_position + dir * AVOID_RAY_LENGTH
		var query := PhysicsRayQueryParameters2D.create(from, to)
		query.collision_mask = 4  # Wall layer
		query.exclude = [get_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			if i == center_idx:
				front_blocked = true
		else:
			# This ray is clear — remember how far from center it is.
			var openness: float = 1.0 - absf(rel)
			if openness > best_open:
				best_open = openness
				best_open_angle = ang

	if front_blocked and best_open > 0.0:
		_avoid_cooldown = 0.15
		return Vector2.from_angle(best_open_angle)
	return move_dir


func _set_nav_target(target_pos: Vector2) -> void:
	"""Force-set a navigation target (used for flee direction updates)."""
	if is_instance_valid(_navigation_agent):
		_navigation_agent.target_position = target_pos
		_nav_target = target_pos
		_nav_target_set = true
