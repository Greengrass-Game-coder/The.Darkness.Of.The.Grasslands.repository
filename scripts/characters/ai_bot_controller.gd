class_name AIBotController
extends ViolentgrassController

## AI-controlled killer bot with human-like behavior:
## - Sprints when far, walks when close
## - Predicts survivor blocks and waits/feints
## - Teleports only when no survivor is nearby (random position)
## - Patrols when no target is found
## - Adds fake delays + randomness to feel like a real player

# AI params
@export var aggro_range: float = 1200.0
@export var sprint_threshold: float = 350.0
@export var close_range: float = 150.0
@export var teleport_ai_cooldown: float = 12.0
@export var no_los_timeout: float = 3.5
@export var patrol_change_interval: float = 2.5

# Block prediction
@export var block_patience_time: float = 0.8
@export var block_feint_chance: float = 0.3

# Human-like randomness
@export var reaction_delay_min: float = 0.15
@export var reaction_delay_max: float = 0.45

var _no_los_timer: float = 0.0
var _ai_teleport_cd_timer: float = 0.0
var _ai_teleport_on_cd: bool = false
var _target: Node2D = null
var _patrol_dir: Vector2 = Vector2.RIGHT
var _patrol_timer: float = 0.0
var _waiting_on_block: float = 0.0
var _fake_reaction_timer: float = 0.0
var _pending_action: String = ""
var _strafing_dir: float = 1.0
var _last_known_target_pos: Vector2 = Vector2.ZERO
var _investigate_timer: float = 0.0
var _bored_timer: float = 0.0

# ── SMARTER TARGETING ──
# The killer prefers a lone / low-HP / puzzle-solving survivor over the merely
# nearest one, so it plays like a real hunter instead of blindly chasing whoever
# is closest. Also uses navigation to cut corners around walls.
var _nav_agent: NavigationAgent2D = null
var _nav_path_timer: float = 0.0
const NAV_PATH_RECOMPUTE: float = 0.25
var _target_retarget_timer: float = 0.0
const TARGET_RETARGET_INTERVAL: float = 1.2


func _ready() -> void:
	super()
	max_stamina = INF
	current_stamina = INF
	_patrol_dir = _random_dir()
	_strafing_dir = 1.0 if randf() > 0.5 else -1.0
	
	# Smart wall-aware pathing around corners.
	_nav_agent = NavigationAgent2D.new()
	_nav_agent.name = "NavAgent"
	_nav_agent.path_desired_distance = 12.0
	_nav_agent.target_desired_distance = 24.0
	add_child(_nav_agent)
	
	# Give bot a distinct purple tint to distinguish from player killers
	modulate = Color(1.0, 0.8, 1.0, 1.0)
	
	# Add a "KILLER BOT" label above the character
	var label := Label.new()
	label.name = "BotLabel"
	label.text = "KILLER BOT"
	label.position = Vector2(-30, -50)
	label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5, 1.0))
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)


func _input(_event: InputEvent) -> void:
	pass


func _physics_process(delta: float) -> void:
	if current_state == State.STUNNED:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_cooldowns(delta)
		return

	if current_state in [State.HITTING, State.TELEPORT_CHARGING, State.TELEPORT_CASTING, State.TELEPORTING]:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_cooldowns(delta)
		return

	if current_state == State.TELEPORT_CHARGING:
		_handle_teleport_charging(delta)
		move_and_slide()
		_update_cooldowns(delta)
		return
	if current_state == State.TELEPORT_CASTING:
		_handle_teleport_casting(delta)
		move_and_slide()
		_update_cooldowns(delta)
		return
	if current_state == State.TELEPORTING:
		_handle_teleporting(delta)
		move_and_slide()
		_update_cooldowns(delta)
		return

	_ai_find_target()
	_bored_timer += delta

	# Fake reaction delay — keep moving while "thinking"
	if _fake_reaction_timer > 0.0:
		_fake_reaction_timer -= delta
		if _fake_reaction_timer <= 0.0:
			_execute_pending_action()
		_ai_move(delta)
		_update_cooldowns(delta)
		return

	# No target — patrol
	if not is_instance_valid(_target):
		_ai_patrol(delta)
		_update_cooldowns(delta)
		return

	var dir: Vector2 = _target.global_position - global_position
	var dist: float = dir.length()
	var has_los: bool = _has_line_of_sight(_target)

	if has_los:
		_no_los_timer = 0.0
		_investigate_timer = 0.0
	else:
		_no_los_timer += delta
		_investigate_timer += delta

	# Teleport if stuck (no LOS) AND no survivor is close
	var closest_dist: float = _get_closest_survivor_distance()
	if _no_los_timer >= no_los_timeout and not _ai_teleport_on_cd and closest_dist > hit_range * 2:
		_set_fake_reaction("teleport", reaction_delay_min * 0.5)
		_update_cooldowns(delta)
		return

	# Block prediction
	if has_los and dist <= hit_range * 1.5:
		if _target_is_blocking():
			_waiting_on_block += delta
			if _waiting_on_block >= block_patience_time:
				if randf() < block_feint_chance:
					_ai_strafe(delta)
				else:
					_set_fake_reaction("hit", reaction_delay_min)
			else:
				_ai_strafe(delta)
			move_and_slide()
			_update_cooldowns(delta)
			return
		else:
			_waiting_on_block = 0.0

	# Attack decision
	if dist <= hit_range and has_los:
		if not hit_on_cooldown:
			_set_fake_reaction("hit", _rand_reaction())
		else:
			_ai_move(delta)
		move_and_slide()
		_update_cooldowns(delta)
		return

	# Move toward target
	_ai_move(delta)
	move_and_slide()
	_update_cooldowns(delta)

	if _ai_teleport_on_cd:
		_ai_teleport_cd_timer -= delta
		if _ai_teleport_cd_timer <= 0.0:
			_ai_teleport_on_cd = false


# ---------- MOVEMENT ----------

func _ai_move(_delta: float) -> void:
	if not is_instance_valid(_target):
		return
	var dir: Vector2 = _target.global_position - global_position
	var dist: float = dir.length()
	var has_los: bool = _has_line_of_sight(_target)
	var use_sprint: bool = dist > sprint_threshold and has_los
	var speed: float = sprint_speed if use_sprint else move_speed

	# SMARTER MOVEMENT: when the target is behind a wall (no LOS), use the nav
	# region to cut around the corner instead of grinding into the wall face.
	if not has_los and is_instance_valid(_nav_agent):
		_nav_path_timer -= _delta
		if _nav_path_timer <= 0.0 or _nav_agent.is_target_reached():
			_nav_path_timer = NAV_PATH_RECOMPUTE
			_nav_agent.target_position = _target.global_position
		if _nav_agent.is_navigation_finished():
			velocity = Vector2.ZERO
		else:
			velocity = _nav_agent.get_next_path_position() - global_position
			velocity = velocity.normalized() * speed
	elif has_los:
		velocity = dir.normalized() * speed
	else:
		velocity = dir.normalized() * move_speed

	_update_direction(velocity)
	_play_animation("walk")
	_spawn_walk_circles(_delta)
	_change_state(State.WALKING)


func _ai_strafe(_delta: float) -> void:
	if not is_instance_valid(_target):
		return
	var to_target: Vector2 = (_target.global_position - global_position).normalized()
	var strafe_vec: Vector2 = Vector2(-to_target.y, to_target.x) * _strafing_dir
	velocity = strafe_vec * move_speed * 0.7
	_update_direction(velocity)
	_play_animation("walk")
	_spawn_walk_circles(_delta)
	if randf() < 0.02:
		_strafing_dir *= -1


# ---------- TARGETING ----------

func _ai_find_target() -> void:
	# Retarget infrequently so a "locked" hunt feels committed, not jittery.
	_target_retarget_timer -= get_physics_process_delta_time()
	var survivors: Array[Node] = get_tree().get_nodes_in_group("survivors")
	if is_instance_valid(_target) and is_instance_valid(_target.get_parent()) and _target_retarget_timer > 0.0:
		# Drop a dead target — the killer never keeps chasing a corpse.
		if _is_dead_survivor(_target):
			_target = null
		# Keep the current target if it's still alive and close enough.
		elif global_position.distance_to(_target.global_position) <= aggro_range * 1.3:
			_last_known_target_pos = _target.global_position
			return
	_target_retarget_timer = TARGET_RETARGET_INTERVAL
	
	var best: Node2D = null
	var best_score: float = INF
	for s in survivors:
		if not is_instance_valid(s):
			continue
		if _is_dead_survivor(s):
			continue
		var d: float = global_position.distance_to(s.global_position)
		if d > aggro_range:
			continue
		# Score: punish distance, but reward a lone survivor (few allies nearby),
		# a low-HP survivor, and one who is isolated from the pack. This makes the
		# AI pick off split survivors instead of always hounding the same person.
		var allies_near: int = 0
		for t in survivors:
			if not is_instance_valid(t) or t == s:
				continue
			if s.global_position.distance_to(t.global_position) < 260.0:
				allies_near += 1
		var hp_ratio: float = 1.0
		if "current_hp" in s and "max_hp" in s:
			var chp: float = s.get("current_hp")
			hp_ratio = chp / maxf(s.get("max_hp"), 1.0)
		var move_speed_ratio: float = 160.0
		if "move_speed" in s:
			move_speed_ratio = float(s.get("move_speed"))
		var speed_ratio: float = 160.0 / maxf(move_speed_ratio, 1.0)
		# Weighted score: distance matters, but lone-wolf + injured targets score
		# far better than clustered healthy ones within the same area.
		var score: float = d
		score += allies_near * 140.0
		score += hp_ratio * 90.0
		score -= speed_ratio * 40.0
		if score < best_score:
			best_score = score
			best = s as Node2D
	if best != null:
		_target = best
		_last_known_target_pos = _target.global_position
		_bored_timer = 0.0
	elif _investigate_timer < 5.0 and _last_known_target_pos != Vector2.ZERO:
		var dist_to_last: float = global_position.distance_to(_last_known_target_pos)
		if dist_to_last <= 50.0:
			_target = null
			_last_known_target_pos = Vector2.ZERO
	else:
		_target = null


func _is_dead_survivor(s: Node) -> bool:
	"""A survivor is 'dead' when their current HP is 0 or below. The killer must
	ignore these greyed-out corpses (never target, chase, or attack them)."""
	if not is_instance_valid(s):
		return true
	if "current_hp" in s:
		return float(s.get("current_hp")) <= 0.0
	# Fallback: any survivor that's been fully disabled/greyed counts as dead.
	return not s.is_physics_processing()


func _get_closest_survivor_distance() -> float:
	var survivors: Array[Node] = get_tree().get_nodes_in_group("survivors")
	var nearest_dist: float = INF
	for s in survivors:
		if is_instance_valid(s) and not _is_dead_survivor(s):
			var d: float = global_position.distance_to(s.global_position)
			if d < nearest_dist:
				nearest_dist = d
	return nearest_dist


func _target_is_blocking() -> bool:
	if not is_instance_valid(_target):
		return false
	if _target.has_method("is_blocking"):
		return _target.is_blocking()
	return false


# ---------- PATROL ----------

func _ai_patrol(delta: float) -> void:
	_patrol_timer += delta
	if _patrol_timer >= patrol_change_interval:
		_patrol_dir = _random_dir()
		_patrol_timer = 0.0
	velocity = _patrol_dir * move_speed * 0.6
	_update_direction(velocity)
	_play_animation("walk")
	_spawn_walk_circles(delta)
	move_and_slide()


func _random_dir() -> Vector2:
	var angle: float = randf() * TAU
	return Vector2(cos(angle), sin(angle))


# ---------- FAKE REACTION ----------

func _set_fake_reaction(action: String, delay: float) -> void:
	_pending_action = action
	_fake_reaction_timer = delay


func _execute_pending_action() -> void:
	if _pending_action == "hit":
		_ai_attack()
	elif _pending_action == "teleport":
		_ai_teleport_to_random()
	_pending_action = ""


func _rand_reaction() -> float:
	return reaction_delay_min + randf() * (reaction_delay_max - reaction_delay_min)


# ---------- ATTACK ----------

func _ai_attack() -> void:
	if not is_instance_valid(_target):
		return
	if _is_dead_survivor(_target):
		_target = null
		return
	if hit_on_cooldown:
		return
	if not _has_line_of_sight(_target):
		return
	velocity = Vector2.ZERO
	use_hit()


# ---------- TELEPORT ----------

func _ai_teleport_to_random() -> void:
	_no_los_timer = 0.0
	_ai_teleport_on_cd = true
	_ai_teleport_cd_timer = teleport_ai_cooldown

	teleport_on_cooldown = true
	_teleport_cd_timer = teleport_cooldown

	# Play teleport sound
	if is_instance_valid(teleport_sound) and not teleport_sound.playing:
		teleport_sound.play()
	_play_voiceline("teleporting")

	_change_state(State.TELEPORTING)
	_play_animation("teleport")

	# SMARTER DESTINATION: teleport to just off-line-of-sight of the target,
	# landing relatively close so the killer reappears near them (practically the
	# killer "cuts them off") rather than somewhere random on the map.
	var destination: Vector2 = global_position + _random_dir() * teleport_range * 0.6

	if is_instance_valid(_target):
		var target_dir: Vector2 = (_target.global_position - global_position).normalized()
		var lateral: Vector2 = Vector2(-target_dir.y, target_dir.x)
		var dist_to_target: float = global_position.distance_to(_target.global_position)
		# Land just behind / beside the target at moderate range, on the far side
		# of where they're facing (running away), so we come out chasing.
		var approach: Vector2 = target_dir * 150.0 + lateral * (150.0 if _strafing_dir > 0.0 else -150.0)
		destination = _target.global_position + approach
		# Keep it within aggro range so it's never useless.
		if dist_to_target > aggro_range * 0.9:
			destination = _target.global_position + target_dir * teleport_range * 0.8

	# Raycast to avoid walls
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, destination)
	query.exclude = [self]
	query.collision_mask = 4  # Wall layer
	var result: Dictionary = space_state.intersect_ray(query)

	if result.is_empty():
		global_position = destination
	else:
		var hit_pos: Vector2 = result.position
		var approach_dir: Vector2 = (hit_pos - global_position).normalized()
		global_position = hit_pos - approach_dir * 24.0

	# Notify game_map that teleport completed (sound + indicator)
	teleported.emit(global_position)
	
	modulate = Color(0.7, 0.3, 0.9, 0.5)
	get_tree().create_timer(0.3).timeout.connect(_ai_end_teleport_visual)


func _ai_end_teleport_visual() -> void:
	if not is_instance_valid(self):
		return
	modulate = Color.WHITE
	if current_state == State.TELEPORTING:
		_change_state(State.IDLE)
