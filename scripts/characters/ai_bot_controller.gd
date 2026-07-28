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


func _ready() -> void:
	super()
	max_stamina = INF
	current_stamina = INF
	_patrol_dir = _random_dir()
	_strafing_dir = 1.0 if randf() > 0.5 else -1.0
	
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

	if has_los:
		velocity = dir.normalized() * speed
	else:
		velocity = dir.normalized() * move_speed

	_update_direction(velocity)
	_play_animation("walk")
	_change_state(State.WALKING)


func _ai_strafe(_delta: float) -> void:
	if not is_instance_valid(_target):
		return
	var to_target: Vector2 = (_target.global_position - global_position).normalized()
	var strafe_vec: Vector2 = Vector2(-to_target.y, to_target.x) * _strafing_dir
	velocity = strafe_vec * move_speed * 0.7
	_update_direction(velocity)
	_play_animation("walk")
	if randf() < 0.02:
		_strafing_dir *= -1


# ---------- TARGETING ----------

func _ai_find_target() -> void:
	var survivors: Array[Node] = get_tree().get_nodes_in_group("survivors")
	var nearest: Node2D = null
	var nearest_dsq: float = INF
	for s in survivors:
		if is_instance_valid(s):
			var dsq: float = global_position.distance_squared_to(s.global_position)
			if dsq < nearest_dsq:
				nearest_dsq = dsq
				nearest = s as Node2D
	if nearest != null and sqrt(nearest_dsq) <= aggro_range:
		_target = nearest
		_last_known_target_pos = _target.global_position
		_bored_timer = 0.0
	elif _investigate_timer < 5.0 and _last_known_target_pos != Vector2.ZERO:
		var dist_to_last: float = global_position.distance_to(_last_known_target_pos)
		if dist_to_last <= 50.0:
			_target = null
			_last_known_target_pos = Vector2.ZERO
	else:
		_target = null


func _get_closest_survivor_distance() -> float:
	var survivors: Array[Node] = get_tree().get_nodes_in_group("survivors")
	var nearest_dist: float = INF
	for s in survivors:
		if is_instance_valid(s):
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

	_change_state(State.TELEPORTING)
	_play_animation("teleport")

	# Random destination
	var offset: Vector2 = Vector2(
		randf_range(-teleport_range, teleport_range),
		randf_range(-teleport_range, teleport_range)
	)
	var destination: Vector2 = global_position + offset

	if is_instance_valid(_target):
		var to_target: Vector2 = _target.global_position - destination
		if to_target.length() > aggro_range * 0.8:
			destination = _target.global_position + _random_dir() * teleport_range * 0.5

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

	modulate = Color(0.7, 0.3, 0.9, 0.5)
	get_tree().create_timer(0.3).timeout.connect(_ai_end_teleport_visual)


func _ai_end_teleport_visual() -> void:
	if not is_instance_valid(self):
		return
	modulate = Color.WHITE
	if current_state == State.TELEPORTING:
		_change_state(State.IDLE)
