class_name AIBotController
extends ViolentgrassController

## AI-controlled killer bot that chases survivors, uses M1 attacks,
## and teleports when stuck/losing line-of-sight.

# AI params
@export var aggro_range: float = 1000.0
@export var teleport_ai_cooldown: float = 10.0
@export var no_los_timeout: float = 3.0  # seconds without LOS before teleporting

var _no_los_timer: float = 0.0
var _ai_teleport_cd_timer: float = 0.0
var _ai_teleport_on_cd: bool = false
var _target: Node2D = null


func _ready() -> void:
	# Start with IDLE state
	super()
	# Remove stamina regen — bot has infinite stamina
	max_stamina = INF
	current_stamina = INF


func _input(_event: InputEvent) -> void:
	pass  # No player input — AI drives this


func _physics_process(delta: float) -> void:
	# Override the parent's physics to use AI logic instead of player input
	
	# Handle stun
	if current_state == State.STUNNED:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_cooldowns(delta)
		return
	
	# Don't override during ability animations
	if current_state in [State.HITTING, State.TELEPORT_CHARGING, State.TELEPORT_CASTING, State.TELEPORTING]:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_cooldowns(delta)
		return
	
	# Teleport charge (handle reversing if we got here)
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
	
	# AI logic
	_ai_find_target()
	
	if not is_instance_valid(_target):
		velocity = Vector2.ZERO
		_play_animation("idle")
		move_and_slide()
		_update_cooldowns(delta)
		return
	
	var dir: Vector2 = _target.global_position - global_position
	var dist: float = dir.length()
	
	var has_los: bool = _has_line_of_sight(_target)
	
	# Track LOS status for teleport decision
	if has_los:
		_no_los_timer = 0.0
	else:
		_no_los_timer += delta
	
	# Teleport if stuck (no LOS too long) or blocked against wall
	if _no_los_timer >= no_los_timeout and not _ai_teleport_on_cd:
		_ai_use_teleport()
		move_and_slide()
		_update_cooldowns(delta)
		return
	
	# If we're close enough and have LOS, attack
	if dist <= hit_range and has_los:
		velocity = Vector2.ZERO
		_play_animation("idle")
		if not hit_on_cooldown:
			use_hit()
		move_and_slide()
		_update_cooldowns(delta)
		return
	
	# Move toward the survivor
	if has_los:
		# Direct path — move straight
		velocity = dir.normalized() * move_speed
		_update_direction(dir)
		_play_animation("walk")
	else:
		# No LOS — try to navigate walls by sliding along them
		# Move toward the target — move_and_slide handles wall sliding
		velocity = dir.normalized() * move_speed
		_update_direction(dir)
		_play_animation("walk")
	
	move_and_slide()
	_update_cooldowns(delta)
	
	# If teleport is off cooldown, enable it
	if _ai_teleport_on_cd:
		_ai_teleport_cd_timer -= delta
		if _ai_teleport_cd_timer <= 0.0:
			_ai_teleport_on_cd = false


func _ai_find_target() -> void:
	"""Find the nearest survivor within aggro range."""
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
	else:
		_target = null


func _ai_use_teleport() -> void:
	"""AI uses teleport toward the target."""
	if not is_instance_valid(_target):
		return
	
	_no_los_timer = 0.0
	_ai_teleport_on_cd = true
	_ai_teleport_cd_timer = teleport_ai_cooldown
	
	# Skip charge for AI — use the old instant teleport approach
	teleport_on_cooldown = true
	_teleport_cd_timer = teleport_cooldown
	
	_change_state(State.TELEPORTING)
	_play_animation("teleport")
	
	# Teleport toward target
	var teleport_dir: Vector2 = _target.global_position - global_position
	var distance: float = teleport_dir.length()
	
	if distance > teleport_range:
		teleport_dir = teleport_dir.normalized() * teleport_range
	
	if distance > 0.0:
		var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + teleport_dir)
		query.exclude = [self]
		query.collision_mask = 1
		var result: Dictionary = space_state.intersect_ray(query)
		
		if result.is_empty():
			global_position += teleport_dir
		else:
			var hit_pos: Vector2 = result.position
			var approach_dir: Vector2 = (hit_pos - global_position).normalized()
			global_position = hit_pos - approach_dir * 16.0
	
	# VFX flash
	modulate = Color(0.7, 0.3, 0.9, 0.5)
	get_tree().create_timer(0.3).timeout.connect(_ai_end_teleport_visual)


func _ai_end_teleport_visual() -> void:
	if not is_instance_valid(self):
		return
	modulate = Color.WHITE
	if current_state == State.TELEPORTING:
		_change_state(State.IDLE)
