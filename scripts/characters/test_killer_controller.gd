class_name TestKillerController
extends CharacterBody2D

signal hit_landed(target: Node2D, damage: float)
signal stamina_changed(current: float, max_stamina: float)
signal hp_changed(current_hp: float, max_hp: float)
signal teleported(new_position: Vector2)
signal teleport_fx_started()
signal teleport_zoom_started()
signal teleport_zoom_ended()
signal entered_chase()
signal exited_chase()
## Emitted when Tentacle Snatch catches a survivor
signal tentacle_caught(survivor: Node2D)

enum State { IDLE, WALKING, HITTING, STUNNED, TENTACLE_SNATCH }
enum Direction { DOWN, LEFT, RIGHT, UP }

# ── Stats ──
@export var max_hp: float = 6666.0
@export var move_speed: float = 240.0
@export var sprint_speed: float = 350.0
@export var max_stamina: float = 110.0
@export var sprint_stamina_drain: float = 7.33
@export var stamina_regen: float = 25.0
@export var stamina_regen_delay: float = 1.0

# ── M1 Hit ──
@export var hit_damage: float = 25.0
@export var hit_cooldown: float = 2.5
@export var hit_range: float = 120.0

# ── Tentacle Snatch ──
@export var tentacle_max_range: float = 500.0
@export var tentacle_speed_mult: float = 2.0
@export var tentacle_catch_damage: float = 15.0
@export var tentacle_wall_damage: float = 2.0
@export var tentacle_stun_duration: float = 1.0
@export var tentacle_m1_damage: float = 10.0
@export var tentacle_activation_delay: float = 0.4
@export var tentacle_max_duration: float = 6.0
@export var tentacle_cooldown_success: float = 28.0
@export var tentacle_cooldown_miss: float = 18.0
@export var tentacle_cooldown_cancel: float = 12.0

# ── Size ──
@export var size_mult: float = 1.0:
	set(value):
		size_mult = value
		_apply_size()

# ── Chase music ──
@export var chase_in_chase: float = 120.0
@export var chase_out_chase: float = 200.0
@export var chase_fade_in_duration: float = 0.5
@export var chase_fade_out_duration: float = 0.5

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_timer: Timer = $StateTimer
@onready var ability_vfx: AnimatedSprite2D = $AbilityVFX
@onready var hit_sound: AudioStreamPlayer2D = $HitSound

# ── Runtime state ──
var current_state: State = State.IDLE
var facing_direction: Direction = Direction.DOWN
var current_hp: float
var current_stamina: float
var hit_on_cooldown: bool = false
var hit_cooldown_timer: float = 0.0
var tentacle_on_cooldown: bool = false
var tentacle_cooldown_timer: float = 0.0
var is_sprinting: bool = false
var _stamina_exhausted: bool = false
var _exhaustion_timer: float = 0.0
var _base_sprite_scale: float = 1.0
var _base_col_scale: float = 1.0

# ── Tentacle state ──
var _tentacle_active: bool = false
var _tentacle_node: Node2D = null  # The tentacle tip sprite
var _tentacle_target_pos: Vector2 = Vector2.ZERO
var _tentacle_activation_timer: float = 0.0
var _tentacle_duration_timer: float = 0.0
var _tentacle_caught_survivor: Node2D = null
var _tentacle_retracting: bool = false
var _tentacle_was_cancelled: bool = false
var _tentacle_expired: bool = false


# ═══════════════ LIFECYCLE ═══════════════

func _ready() -> void:
	current_hp = max_hp
	current_stamina = max_stamina
	_base_sprite_scale = animated_sprite.scale.x if animated_sprite else 1.0
	_base_col_scale = $CollisionShape2D.scale.x if has_node("CollisionShape2D") else 1.0
	_apply_size()


func _physics_process(delta: float) -> void:
	if current_hp <= 0.0:
		return
	
	_update_cooldowns(delta)
	
	match current_state:
		State.IDLE, State.WALKING:
			_handle_movement(delta)
		State.HITTING:
			_handle_hitting(delta)
		State.STUNNED:
			_handle_stunned(delta)
		State.TENTACLE_SNATCH:
			_handle_tentacle_snatch(delta)
	
	# Stamina exhaustion
	if _stamina_exhausted:
		_exhaustion_timer -= delta
		if _exhaustion_timer <= 0:
			_stamina_exhausted = false


func _input(event: InputEvent) -> void:
	if current_hp <= 0.0:
		return
	
	if event.is_action_pressed("ability_1"):
		_start_hit()
	elif event.is_action_pressed("ability_2"):
		_activate_tentacle_snatch()


func _update_cooldowns(delta: float) -> void:
	if hit_on_cooldown:
		hit_cooldown_timer -= delta
		if hit_cooldown_timer <= 0.0:
			hit_on_cooldown = false
	if tentacle_on_cooldown:
		tentacle_cooldown_timer -= delta
		if tentacle_cooldown_timer <= 0.0:
			tentacle_on_cooldown = false


# ═══════════════ SIZE ═══════════════

func _apply_size() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(animated_sprite):
		animated_sprite.scale = Vector2(_base_sprite_scale * size_mult, _base_sprite_scale * size_mult)
	if is_instance_valid(ability_vfx):
		ability_vfx.scale = Vector2(_base_sprite_scale * size_mult, _base_sprite_scale * size_mult)
	var cs2: CollisionShape2D = $CollisionShape2D
	if is_instance_valid(cs2):
		cs2.scale = Vector2(_base_col_scale, _base_col_scale) * size_mult


# ═══════════════ MOVEMENT ═══════════════

func _handle_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")
	
	is_sprinting = Input.is_action_pressed("sprint")
	if is_sprinting and input_dir != Vector2.ZERO and current_stamina > 0.0 and not _stamina_exhausted:
		current_stamina -= sprint_stamina_drain * delta
		if current_stamina <= 0.0:
			current_stamina = 0.0
			_stamina_exhausted = true
			_exhaustion_timer = 1.0
	else:
		current_stamina = min(current_stamina + stamina_regen * delta, max_stamina)
	stamina_changed.emit(current_stamina, max_stamina)
	
	var speed: float = sprint_speed if is_sprinting and current_stamina > 0.0 else move_speed
	if input_dir != Vector2.ZERO:
		velocity = input_dir.normalized() * speed
		current_state = State.WALKING
		_update_facing(input_dir)
		_play_walk_animation()
	else:
		velocity = Vector2.ZERO
		current_state = State.IDLE
		_play_idle_animation()
	
	move_and_slide()


func _update_facing(dir: Vector2) -> void:
	if abs(dir.x) > abs(dir.y):
		facing_direction = Direction.RIGHT if dir.x > 0 else Direction.LEFT
	else:
		facing_direction = Direction.DOWN if dir.y > 0 else Direction.UP


func _play_walk_animation() -> void:
	match facing_direction:
		Direction.DOWN: animated_sprite.play("walk_down")
		Direction.LEFT: animated_sprite.play("walk_left")
		Direction.RIGHT: animated_sprite.play("walk_right")
		Direction.UP: animated_sprite.play("walk_up")


func _play_idle_animation() -> void:
	match facing_direction:
		Direction.DOWN: animated_sprite.play("idle_down")
		Direction.LEFT: animated_sprite.play("idle_left")
		Direction.RIGHT: animated_sprite.play("idle_right")
		Direction.UP: animated_sprite.play("idle_up")


# ═══════════════ M1 HIT ═══════════════

func _start_hit() -> void:
	if hit_on_cooldown:
		return
	if current_state == State.TENTACLE_SNATCH:
		return
	current_state = State.HITTING
	hit_on_cooldown = true
	hit_cooldown_timer = hit_cooldown
	ability_vfx.play("hit_down")
	ability_vfx.visible = true
	state_timer.start(0.35)


func _handle_hitting(_delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	if state_timer.is_stopped():
		# Hit lands
		_perform_hit()
		current_state = State.IDLE
		ability_vfx.visible = false


func _perform_hit() -> void:
	var hit_dir := Vector2.ZERO
	match facing_direction:
		Direction.DOWN: hit_dir = Vector2.DOWN
		Direction.LEFT: hit_dir = Vector2.LEFT
		Direction.RIGHT: hit_dir = Vector2.RIGHT
		Direction.UP: hit_dir = Vector2.UP
	
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + hit_dir * hit_range)
	query.collision_mask = 1  # Survivors layer
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	
	if not result.is_empty():
		var target: Node = result.collider
		if is_instance_valid(target) and target.has_method("take_damage"):
			var dmg: float = hit_damage
			# Tentacle follow-up: boosted M1 after a successful snatch
			if _tentacle_caught_survivor and target == _tentacle_caught_survivor:
				dmg = tentacle_m1_damage
				_tentacle_caught_survivor = null
			target.take_damage(dmg)
			hit_landed.emit(target, dmg)
	
	if hit_sound:
		hit_sound.play()


# ═══════════════ STUNNED ═══════════════

func _handle_stunned(_delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()


# ═══════════════ TENTACLE SNATCH ═══════════════

func _activate_tentacle_snatch() -> void:
	"""Player pressed ability_2 — activate or deactivate Tentacle Snatch."""
	if tentacle_on_cooldown:
		return
	if current_state == State.TENTACLE_SNATCH:
		# Already active — cancel it
		_deactivate_tentacle(false, true)
		return
	if current_state == State.HITTING or current_state == State.STUNNED:
		return
	
	# Start tentacle snatch
	current_state = State.TENTACLE_SNATCH
	_tentacle_active = true
	_tentacle_activation_timer = 0.0
	_tentacle_duration_timer = 0.0
	_tentacle_caught_survivor = null
	_tentacle_retracting = false
	_tentacle_was_cancelled = false
	_tentacle_expired = false
	
	# Spawn tentacle tip at killer position
	_tentacle_node = Sprite2D.new()
	_tentacle_node.name = "TentacleTip"
	_tentacle_node.texture = load("res://The Darkness Of The Grasslands assets/Sprites/test killer/abilities/Tentacle UI/tentacle_vertical.png")
	_tentacle_node.position = Vector2.ZERO
	_tentacle_node.z_index = 200
	add_child(_tentacle_node)
	
	# Tentacle catch area
	var area := Area2D.new()
	area.name = "TentacleCatchArea"
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 24.0
	col.shape = shape
	area.add_child(col)
	area.collision_layer = 0
	area.collision_mask = 1  # Detect survivors
	area.body_entered.connect(_on_tentacle_catch)
	_tentacle_node.add_child(area)
	
	print("TestKiller: Tentacle Snatch ACTIVATED")


func _handle_tentacle_snatch(delta: float) -> void:
	"""Main tentacle control loop."""
	# Killer is immobile during tentacle snatch
	velocity = Vector2.ZERO
	move_and_slide()
	
	if not is_instance_valid(_tentacle_node):
		_deactivate_tentacle(false, false)
		return
	
	# Activation delay
	_tentacle_activation_timer += delta
	if _tentacle_activation_timer < tentacle_activation_delay:
		return
	
	# Max duration check
	_tentacle_duration_timer += delta
	if _tentacle_duration_timer >= tentacle_max_duration:
		_tentacle_expired = true
		_deactivate_tentacle(true, false)
		return
	
	# Retracting with a caught survivor
	if _tentacle_retracting:
		_retract_tentacle(delta)
		return
	
	# Control the tentacle toward the mouse/aim position
	var aim_dir: Vector2 = _get_aim_direction()
	if aim_dir.length_squared() < 0.01:
		aim_dir = Vector2.DOWN
	
	var tentacle_speed: float = move_speed * tentacle_speed_mult
	var target_pos: Vector2 = _tentacle_node.position + aim_dir * tentacle_speed * delta
	
	# Clamp to max range from killer
	if target_pos.length() > tentacle_max_range:
		target_pos = target_pos.normalized() * tentacle_max_range
	
	_tentacle_node.position = target_pos
	
	# Rotate tentacle to face movement direction
	_tentacle_node.rotation = aim_dir.angle() + PI / 2


func _get_aim_direction() -> Vector2:
	"""Get the direction from the tentacle toward where the player is aiming."""
	# Use mouse position relative to screen center for aiming
	var viewport := get_viewport()
	if not viewport:
		return Vector2.DOWN
	var mouse_pos: Vector2 = viewport.get_mouse_position()
	var screen_center: Vector2 = viewport.get_visible_rect().size / 2.0
	var raw_dir: Vector2 = (mouse_pos - screen_center).normalized()
	if raw_dir.length_squared() < 0.01:
		raw_dir = Vector2.DOWN
	return raw_dir


func _on_tentacle_catch(body: Node2D) -> void:
	"""A survivor body entered the tentacle's catch area."""
	if _tentacle_retracting:
		return
	if not is_instance_valid(body) or not body.has_method("take_damage"):
		return
	
	_tentacle_retracting = true
	_tentacle_caught_survivor = body
	
	# Deal initial catch damage
	body.take_damage(tentacle_catch_damage)
	tentacle_caught.emit(body)
	
	# Disable survivor movement by setting them as a child of the tentacle
	# so they get pulled along during retraction.
	if body is CharacterBody2D:
		(body as CharacterBody2D).velocity = Vector2.ZERO
	
	print("TestKiller: Tentacle caught ", body.name, " — ", tentacle_catch_damage, " dmg")


func _retract_tentacle(delta: float) -> void:
	"""Pull the tentacle (and caught survivor) back toward the killer."""
	if not is_instance_valid(_tentacle_node):
		_deactivate_tentacle(true, false)
		return
	
	var retract_speed: float = move_speed * tentacle_speed_mult * 1.5  # Faster retraction
	var dir_to_killer: Vector2 = -_tentacle_node.position.normalized()
	if _tentacle_node.position.length() < 10.0:
		# Reached killer — apply stun and finish
		_finish_tentacle_catch()
		return
	
	_tentacle_node.position += dir_to_killer * retract_speed * delta
	
	# Move caught survivor with the tentacle
	if is_instance_valid(_tentacle_caught_survivor):
		var survivor_global: Vector2 = global_position + _tentacle_node.position
		var prev_pos: Vector2 = _tentacle_caught_survivor.global_position
		_tentacle_caught_survivor.global_position = survivor_global
		
		# Check for wall collisions during retraction
		if _tentacle_caught_survivor is CharacterBody2D:
			var surv: CharacterBody2D = _tentacle_caught_survivor as CharacterBody2D
			var collision: KinematicCollision2D = surv.move_and_collide(Vector2.ZERO, true)
			if collision:
				var collider: Node = collision.get_collider()
				if collider and collider is StaticBody2D:
					# Wall hit during retraction — deal wall damage
					_tentacle_caught_survivor.take_damage(tentacle_wall_damage)
					# Push survivor away from wall
					_tentacle_caught_survivor.global_position += collision.get_normal() * 8.0


func _finish_tentacle_catch() -> void:
	"""Tentacle reached the killer — stun the survivor and clean up."""
	if is_instance_valid(_tentacle_caught_survivor):
		# Stun the survivor
		if _tentacle_caught_survivor.has_method("set_stunned"):
			_tentacle_caught_survivor.set_stunned(tentacle_stun_duration)
		elif "current_state" in _tentacle_caught_survivor:
			_tentacle_caught_survivor.set("current_state", 6)  # STUNNED enum value
	
	_deactivate_tentacle(true, false)


func _deactivate_tentacle(success: bool, cancelled: bool) -> void:
	"""Clean up tentacle and set cooldown."""
	_tentacle_active = false
	
	if is_instance_valid(_tentacle_node):
		_tentacle_node.queue_free()
		_tentacle_node = null
	
	_tentacle_caught_survivor = null
	_tentacle_retracting = false
	current_state = State.IDLE
	
	tentacle_on_cooldown = true
	if success:
		tentacle_cooldown_timer = tentacle_cooldown_success
	elif cancelled:
		tentacle_cooldown_timer = tentacle_cooldown_cancel
	else:
		tentacle_cooldown_timer = tentacle_cooldown_miss
	
	print("TestKiller: Tentacle Snatch DEACTIVATED (cooldown=", tentacle_cooldown_timer, "s)")


# ═══════════════ DAMAGE ═══════════════

func take_damage(amount: float) -> void:
	if current_hp <= 0.0:
		return
	current_hp -= amount
	if current_hp <= 0.0:
		current_hp = 0.0
	hp_changed.emit(current_hp, max_hp)


func set_stunned(duration: float) -> void:
	if current_state == State.TENTACLE_SNATCH:
		_deactivate_tentacle(false, true)
	current_state = State.STUNNED
	state_timer.start(duration)
	if state_timer.timeout.is_connected(_on_stun_end):
		state_timer.timeout.disconnect(_on_stun_end)
	state_timer.timeout.connect(_on_stun_end)


func _on_stun_end() -> void:
	if current_state == State.STUNNED:
		current_state = State.IDLE
