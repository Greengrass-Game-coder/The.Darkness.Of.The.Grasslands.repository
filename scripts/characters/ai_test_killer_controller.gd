class_name AITestKillerController
extends TestKillerController

## Simple AI for the Test Killer bot: chase the nearest survivor, hit when
## close, and periodically place "The Rage" information traps. The bot does
## not use the WASD-steered Tentacle (that's a player ability) — it focuses on
## chasing, M1 hits, and Rage traps to prepare ambushes.

const TARGET_RETARGET_INTERVAL := 0.5

var _target: Node2D = null
var _target_retarget_timer: float = 0.0
var _ai_rage_timer: float = 3.0
var _ai_better_sight_timer: float = 5.0


func _physics_process(delta: float) -> void:
	if current_hp <= 0.0:
		return
	_update_cooldowns(delta)
	_update_rage(delta)
	
	# Periodically use Better Sight to lock onto the nearest survivor.
	_ai_better_sight_timer -= delta
	if _ai_better_sight_timer <= 0.0:
		_ai_better_sight_timer = 8.0 + randf() * 6.0
		if not better_sight_on_cooldown:
			_activate_better_sight()
	
	# Periodically place a Rage trap to prepare ambushes.
	_ai_rage_timer -= delta
	if _ai_rage_timer <= 0.0:
		_ai_rage_timer = 4.0 + randf() * 4.0
		if not rage_on_cooldown and _rage_traps.size() < rage_max_traps:
			_place_rage_trap()
	
	match current_state:
		State.IDLE, State.WALKING:
			_ai_move(delta)
		State.HITTING:
			_handle_hitting(delta)
		State.STUNNED:
			_handle_stunned(delta)
		State.TENTACLE_SNATCH:
			_handle_tentacle_snatch(delta)
	
	if _stamina_exhausted:
		_exhaustion_timer -= delta
		if _exhaustion_timer <= 0.0:
			_stamina_exhausted = false


func _ai_find_target() -> void:
	_target_retarget_timer -= get_physics_process_delta_time()
	if is_instance_valid(_target) and _target_retarget_timer > 0.0:
		return
	_target_retarget_timer = TARGET_RETARGET_INTERVAL
	var best: Node2D = null
	var best_dist: float = 1400.0
	for group_name in ["survivors", "survivor_bots"]:
		for s in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(s) or not s.has_method("take_damage"):
				continue
			var d: float = global_position.distance_to(s.global_position)
			if d < best_dist:
				best_dist = d
				best = s as Node2D
	_target = best


func _ai_move(_delta: float) -> void:
	_ai_find_target()
	if not is_instance_valid(_target):
		velocity = Vector2.ZERO
		current_state = State.IDLE
		_play_idle_animation()
		move_and_slide()
		return
	
	var to_target: Vector2 = _target.global_position - global_position
	var dist: float = to_target.length()
	if dist <= hit_range:
		# In range — stop and strike.
		velocity = Vector2.ZERO
		current_state = State.IDLE
		_play_idle_animation()
		if not hit_on_cooldown:
			_start_hit()
		move_and_slide()
		return
	
	_update_facing(to_target.normalized())
	_play_walk_animation()
	var spd: float = move_speed * (better_sight_speed_mult if _better_sight_active else 1.0)
	velocity = to_target.normalized() * spd
	current_state = State.WALKING
	move_and_slide()
