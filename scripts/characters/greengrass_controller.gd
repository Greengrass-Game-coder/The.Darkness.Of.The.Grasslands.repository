class_name GreengrassController
extends CharacterBody2D

signal block_unlocked_punch()
signal punch_locked_changed(locked: bool)
signal punch_landed(stunned: bool)
signal healed(amount: float, source: String)
signal stamina_changed(current: float, max_stamina: float)
signal slowed(duration: float)
signal hp_changed(current_hp: float, max_hp: float)

enum State { IDLE, WALKING, BLOCKING, DASH_BLOCKING, PUNCHING, PUNCH_CHARGING, HEALING, STUNNED, SLOWED }

const BLOCK_SLOW_SPEED: float = 80.0
const DASH_SPEED: float = 600.0
const DASH_COST: float = 25.0
enum Direction { DOWN, LEFT, RIGHT, UP }

@export var max_hp: float = 100.0
@export var move_speed: float = 160.0
@export var sprint_speed: float = 250.0
@export var max_stamina: float = 100.0
@export var sprint_stamina_drain: float = 6.67
@export var stamina_regen: float = 25.0
@export var stamina_regen_delay: float = 1.0

@export var block_cooldown: float = 20.0
@export var punch_cooldown: float = 20.0
@export var parry_punch_cooldown: float = 30.0
@export var spare_flower_cooldown: float = 45.0

@export var block_defense: int = 5
@export var block_absorption: float = 0.85
@export var parry_window: float = 1.5
@export var normal_stun: float = 2.0
@export var parry_stun: float = 3.0
@export var spare_flower_heal: float = 70.0
@export var ally_detect_radius: float = 300.0
@export var punch_range: float = 80.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_timer: Timer = $StateTimer
@onready var ability_vfx: AnimatedSprite2D = $AbilityVFX

var current_hp: float
var current_stamina: float
var current_state: State = State.IDLE
var current_direction: Direction = Direction.DOWN
var is_sprinting: bool = false
var _stamina_regen_timer: float = 0.0

var block_on_cooldown: bool = false
var punch_on_cooldown: bool = false
var flower_on_cooldown: bool = false
var block_timer: float = 0.0
var block_active: bool = false
var can_block_hit: bool = false

var parry_window_active: bool = false
var is_parry_punch: bool = false
var punch_target: Vector2 = Vector2.ZERO
var punch_locked: bool = true
var _charging: bool = false
var _charge_time: float = 0.0

var healing_ally: Node = null
var heal_over_time_active: bool = false
var heal_tick_timer: float = 0.0
var heal_ticks_remaining: int = 7

var _slow_active: bool = false
var _slow_timer: float = 0.0
const SLOW_MULTIPLIER: float = 0.5

var _block_cd_timer: float = 0.0
var _punch_cd_timer: float = 0.0
var _flower_cd_timer: float = 0.0


func _ready() -> void:
	current_hp = max_hp
	current_stamina = max_stamina
	_change_state(State.IDLE)
	add_to_group("survivors")
	hp_changed.emit(current_hp, max_hp)
	stamina_changed.emit(current_stamina, max_stamina)
	_setup_ability_vfx_frames()
	if not ability_vfx.animation_finished.is_connected(_on_ability_vfx_finished):
		ability_vfx.animation_finished.connect(_on_ability_vfx_finished)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ability_1"):
		use_block()
	elif event.is_action_pressed("ability_2"):
		_start_charge_punch()
	elif event.is_action_released("ability_2") and _charging:
		_fire_charged_punch()
	elif event.is_action_pressed("ability_3"):
		use_spare_flower()


func _physics_process(delta: float) -> void:
	if _slow_active:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_active = false

	match current_state:
		State.IDLE, State.WALKING:
			_handle_movement(delta)
		State.BLOCKING:
			_handle_blocking(delta)
		State.DASH_BLOCKING:
			_handle_dash_blocking(delta)
		State.PUNCHING:
			_handle_punching(delta)
		State.PUNCH_CHARGING:
			_handle_charge(delta)
		State.HEALING:
			_handle_healing(delta)
		State.STUNNED:
			_handle_stunned(delta)

	_update_cooldowns(delta)

	if heal_over_time_active:
		heal_tick_timer -= delta
		if heal_tick_timer <= 0:
			_tick_heal_over_time()


func _handle_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")

	is_sprinting = Input.is_action_pressed("sprint")
	if is_sprinting and input_dir != Vector2.ZERO and current_stamina > 0.0:
		current_stamina -= sprint_stamina_drain * delta
		if current_stamina < 0.0:
			current_stamina = 0.0
		is_sprinting = true
		_stamina_regen_timer = stamina_regen_delay
	else:
		is_sprinting = false

	if current_stamina < max_stamina:
		_stamina_regen_timer -= delta
		if _stamina_regen_timer <= 0.0:
			current_stamina += stamina_regen * delta
			if current_stamina > max_stamina:
				current_stamina = max_stamina

	stamina_changed.emit(current_stamina, max_stamina)

	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		var speed: float = sprint_speed if is_sprinting else move_speed
		if _slow_active:
			speed *= SLOW_MULTIPLIER
		velocity = input_dir * speed
		_update_direction(input_dir)
		_play_animation("walk")
		_change_state(State.WALKING)
	else:
		velocity = Vector2.ZERO
		_play_animation("idle")
		_change_state(State.IDLE)

	move_and_slide()


func _handle_blocking(_delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		velocity = input_dir * BLOCK_SLOW_SPEED
		_update_direction(input_dir)
	else:
		velocity = Vector2.ZERO
	move_and_slide()


func _handle_dash_blocking(_delta: float) -> void:
	var target: Vector2 = get_global_mouse_position()
	var dir: Vector2 = (target - global_position).normalized()
	if dir.length() > 0.0:
		velocity = dir * DASH_SPEED
		_update_direction(dir)
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	if global_position.distance_squared_to(target) < 400.0:
		_end_block()


func _handle_punching(_delta: float) -> void:
	velocity = Vector2.ZERO


func _handle_healing(_delta: float) -> void:
	velocity = Vector2.ZERO
	_play_animation("heal")


func _handle_stunned(_delta: float) -> void:
	velocity = Vector2.ZERO


func _update_direction(input_dir: Vector2) -> void:
	if abs(input_dir.x) > abs(input_dir.y):
		current_direction = Direction.RIGHT if input_dir.x > 0 else Direction.LEFT
	else:
		current_direction = Direction.DOWN if input_dir.y > 0 else Direction.UP


func _play_animation(anim: String) -> void:
	match anim:
		"idle":
			var dir_name: String = ["down", "left", "right", "up"][current_direction as int]
			var full_anim: String = "idle_" + dir_name
			if animated_sprite.sprite_frames.has_animation(full_anim):
				animated_sprite.play(full_anim)
			else:
				animated_sprite.play("idle")
		"walk":
			var dir_name: String = ["down", "left", "right", "up"][current_direction as int]
			var full_anim: String = "walk_" + dir_name
			if animated_sprite.sprite_frames.has_animation(full_anim):
				animated_sprite.play(full_anim)
		"block":
			animated_sprite.play("idle")
			_play_ability_vfx(anim)
		"punch":
			if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("punch"):
				animated_sprite.play("punch")
			else:
				animated_sprite.play("idle")
			_play_ability_vfx(anim)
		"punch_parry":
			if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("punch_parry"):
				animated_sprite.play("punch_parry")
			else:
				animated_sprite.play("idle")
			_play_ability_vfx(anim)
		"heal":
			animated_sprite.play("idle")
			_play_ability_vfx(anim)


func _change_state(new_state: State) -> void:
	current_state = new_state
	if new_state == State.IDLE:
		_hide_vfx()
		if not animated_sprite.visible:
			animated_sprite.visible = true


# ---------- ABILITY VFX ----------

func _setup_ability_vfx_frames() -> void:
	var vfx_sf := SpriteFrames.new()

	var block_frames: Array[Texture2D] = []
	for i in range(13):
		var path: String = "res://The Darkness Of The Grasslands assets/Sprites/Greengrass/Abilities/Ability --- BLOCK/Ability_BLOCK_frame_%d.png" % i
		var tex: Texture2D = load(path)
		if tex:
			block_frames.append(tex)
	if not block_frames.is_empty():
		vfx_sf.add_animation("block")
		vfx_sf.set_animation_loop("block", false)
		vfx_sf.set_animation_speed("block", 10.0)
		for tex in block_frames:
			vfx_sf.add_frame("block", tex)

	var punch_frames: Array[Texture2D] = []
	for i in range(13):
		var path: String = "res://The Darkness Of The Grasslands assets/Sprites/Greengrass/Abilities/Ability --- PUNCH/PUNCH_frame_%05d.png" % i
		var tex: Texture2D = load(path)
		if tex:
			punch_frames.append(tex)
	if not punch_frames.is_empty():
		vfx_sf.add_animation("punch")
		vfx_sf.set_animation_loop("punch", false)
		vfx_sf.set_animation_speed("punch", 8.0)
		for tex in punch_frames:
			vfx_sf.add_frame("punch", tex)

	var parry_frames: Array[Texture2D] = []
	var parry_paths: Array[String] = [
		"res://The Darkness Of The Grasslands assets/Sprites/Greengrass/Abilities/Ability --- PUNCH/ABILITY_PARRY_punch_CHARGE_frame_0000.png",
		"res://The Darkness Of The Grasslands assets/Sprites/Greengrass/Abilities/Ability --- PUNCH/ABILITY_PARRY_punch_CHARGE_frame_00001.png",
		"res://The Darkness Of The Grasslands assets/Sprites/Greengrass/Abilities/Ability --- PUNCH/ABILITY_PARRY_punch_CHARGE_frame_00002.png",
		"res://The Darkness Of The Grasslands assets/Sprites/Greengrass/Abilities/Ability --- PUNCH/ABILITY_PARRY_punch_CHARGE_frame_00003.png",
		"res://The Darkness Of The Grasslands assets/Sprites/Greengrass/Abilities/Ability --- PUNCH/ABILITY_PARRY_punch_CHARGE_frame_00004.png",
	]
	for path in parry_paths:
		var tex: Texture2D = load(path)
		if tex:
			parry_frames.append(tex)
	if not parry_frames.is_empty():
		vfx_sf.add_animation("punch_parry")
		vfx_sf.set_animation_loop("punch_parry", false)
		vfx_sf.set_animation_speed("punch_parry", 12.0)
		for tex in parry_frames:
			vfx_sf.add_frame("punch_parry", tex)

	var heal_frames: Array[Texture2D] = []
	for i in range(9):
		var path: String = "res://The Darkness Of The Grasslands assets/Sprites/Greengrass/Abilities/Ability --- SPARE FLOWER/ABILITY_HEAL_frame-%d.png" % i
		var tex: Texture2D = load(path)
		if tex:
			heal_frames.append(tex)
	if not heal_frames.is_empty():
		vfx_sf.add_animation("heal")
		vfx_sf.set_animation_loop("heal", false)
		vfx_sf.set_animation_speed("heal", 10.0)
		for tex in heal_frames:
			vfx_sf.add_frame("heal", tex)

	ability_vfx.sprite_frames = vfx_sf
	ability_vfx.visible = false


func _play_ability_vfx(anim: String) -> void:
	if ability_vfx.sprite_frames and ability_vfx.sprite_frames.has_animation(anim):
		ability_vfx.visible = true
		ability_vfx.play(anim)


func _hide_vfx() -> void:
	ability_vfx.visible = false
	ability_vfx.stop()


func _on_ability_vfx_finished() -> void:
	_hide_vfx()
	if current_state in [State.PUNCHING, State.HEALING, State.BLOCKING]:
		current_state = State.IDLE


# ---------- HITBOX ----------

func _get_hitbox_shape() -> RectangleShape2D:
	var hitbox := RectangleShape2D.new()
	hitbox.size = Vector2(punch_range, 48)
	return hitbox


func _get_hitbox_position() -> Vector2:
	match current_direction:
		Direction.DOWN:
			return global_position + Vector2(0, 32)
		Direction.UP:
			return global_position - Vector2(0, 32)
		Direction.RIGHT:
			return global_position + Vector2(32, 0)
		Direction.LEFT:
			return global_position - Vector2(32, 0)
	return global_position


func _check_punch_hit() -> Array[Node2D]:
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = punch_range
	query.shape = shape
	query.transform = Transform2D(0, global_position)
	query.exclude = [self]
	query.collision_mask = 1
	var results: Array[Dictionary] = space_state.intersect_shape(query)
	var hits: Array[Node2D] = []
	for r in results:
		var node: Node = r.collider
		if node is Node2D and node.is_in_group("killers"):
			hits.append(node as Node2D)
	return hits


# ---------- BLOCK ----------

func use_block() -> void:
	if current_state != State.IDLE and current_state != State.WALKING:
		return
	if block_on_cooldown:
		return

	block_active = true
	can_block_hit = true
	block_on_cooldown = true
	_block_cd_timer = block_cooldown

	animated_sprite.visible = false

	var is_dashing: bool = is_sprinting and current_stamina >= DASH_COST

	if is_dashing:
		current_stamina -= DASH_COST
		stamina_changed.emit(current_stamina, max_stamina)
		_change_state(State.DASH_BLOCKING)
		_play_animation("block")
		get_tree().create_timer(0.8).timeout.connect(_on_dash_block_end)
	else:
		_change_state(State.BLOCKING)
		_play_animation("block")
		get_tree().create_timer(1.5).timeout.connect(_end_block)


func on_block_hit() -> bool:
	if not block_active or not can_block_hit:
		return false

	can_block_hit = false
	parry_window_active = true
	punch_locked = false
	animated_sprite.visible = true

	_clear_slow()

	punch_locked_changed.emit(false)
	block_unlocked_punch.emit()

	get_tree().create_timer(parry_window).timeout.connect(_end_parry_window)

	_end_block()
	return true


func _end_parry_window() -> void:
	parry_window_active = false
	# Punch stays unlocked — becomes normal punch instead of relocking


func _end_block() -> void:
	block_active = false
	can_block_hit = false
	animated_sprite.visible = true
	if current_state == State.BLOCKING or current_state == State.DASH_BLOCKING:
		_change_state(State.IDLE)


func _on_dash_block_end() -> void:
	_end_block()
	_slow_active = true
	_slow_timer = 3.0
	slowed.emit(3.0)


func _clear_slow() -> void:
	_slow_active = false
	_slow_timer = 0.0


func take_damage(amount: float) -> void:
	if block_active and can_block_hit:
		var _absorbed: float = amount * block_absorption
		current_hp -= amount * (1.0 - block_absorption)
		on_block_hit()
	else:
		current_hp -= amount

	if current_hp <= 0.0:
		current_hp = 0.0

	hp_changed.emit(current_hp, max_hp)
	_clear_slow()


# ---------- GRASS PUNCH ----------

func _start_charge_punch() -> void:
	if current_state != State.IDLE and current_state != State.WALKING:
		return
	if punch_on_cooldown:
		return
	if punch_locked and not parry_window_active:
		# Punch is locked — tell HUD to flash icon
		punch_locked_changed.emit(true)
		return

	_charging = true
	_charge_time = 0.0
	_change_state(State.PUNCH_CHARGING)
	_play_animation("idle")
	ability_vfx.visible = true
	ability_vfx.play("punch")


func _fire_charged_punch() -> void:
	if not _charging:
		return
	_charging = false
	punch_on_cooldown = true
	_punch_cd_timer = parry_punch_cooldown if parry_window_active else punch_cooldown

	var target_pos: Vector2 = get_global_mouse_position()
	punch_target = target_pos
	_change_state(State.PUNCHING)

	is_parry_punch = parry_window_active
	if parry_window_active:
		parry_window_active = false
		punch_locked = true  # Re-lock after parry punch is used
	_play_animation("punch_parry" if is_parry_punch else "punch")

	var charge_ratio: float = min(_charge_time / 1.5, 1.0)
	var dmg_mult: float = 0.5 + charge_ratio * 1.5
	_charge_time = 0.0

	var hits: Array[Node2D] = _check_punch_hit()
	for target in hits:
		punch_landed.emit(is_parry_punch)
		var stun_duration: float = (parry_stun if is_parry_punch else normal_stun) * dmg_mult
		if target.has_method("take_stun"):
			target.take_stun(stun_duration)
		break

	state_timer.start(1.0)
	await state_timer.timeout
	if current_state == State.PUNCHING:
		_change_state(State.IDLE)


func _handle_charge(delta: float) -> void:
	_charge_time += delta
	if _charge_time > 1.5:
		_charge_time = 1.5

	velocity = Vector2.ZERO
	move_and_slide()


# ---------- SPARE FLOWER ----------

func use_spare_flower() -> void:
	if current_state != State.IDLE and current_state != State.WALKING:
		return
	if flower_on_cooldown:
		return

	flower_on_cooldown = true
	_flower_cd_timer = spare_flower_cooldown
	_change_state(State.HEALING)
	_play_animation("heal")

	_apply_heal(spare_flower_heal, "self")

	var ally := _find_nearest_ally()
	if ally != null:
		healing_ally = ally
		heal_over_time_active = true
		heal_ticks_remaining = 7
		heal_tick_timer = 1.0

	await get_tree().create_timer(0.9).timeout
	if current_state == State.HEALING:
		_change_state(State.IDLE)


func _find_nearest_ally() -> Node:
	var allies: Array[Node] = get_tree().get_nodes_in_group("survivors")
	var nearest: Node = null
	var nearest_dist: float = ally_detect_radius
	for ally in allies:
		if ally == self:
			continue
		var dist: float = global_position.distance_to(ally.global_position)
		if dist <= nearest_dist:
			nearest = ally
			nearest_dist = dist
	return nearest


func _tick_heal_over_time() -> void:
	if not heal_over_time_active:
		return
	if healing_ally == null or not is_instance_valid(healing_ally):
		heal_over_time_active = false
		return

	var tick_heal: float = spare_flower_heal / 7.0
	_apply_heal(tick_heal, "spare_flower", healing_ally)
	heal_ticks_remaining -= 1

	if heal_ticks_remaining <= 0:
		heal_over_time_active = false
		healing_ally = null
	else:
		heal_tick_timer = 1.0


func _apply_heal(amount: float, source: String, target: Node = null) -> void:
	if target == null:
		target = self
	if target == self:
		current_hp = min(current_hp + amount, max_hp)
		hp_changed.emit(current_hp, max_hp)
	elif target.has_method("get_current_hp") and target.has_method("set_current_hp"):
		var hp: float = target.get("current_hp")
		target.set("current_hp", min(hp + amount, target.get("max_hp")))
	if target.has_signal("healed"):
		target.healed.emit(amount, source)
	healed.emit(amount, source)


func _update_cooldowns(delta: float) -> void:
	if block_on_cooldown:
		_block_cd_timer -= delta
		if _block_cd_timer <= 0:
			block_on_cooldown = false

	if punch_on_cooldown:
		_punch_cd_timer -= delta
		if _punch_cd_timer <= 0:
			punch_on_cooldown = false

	if flower_on_cooldown:
		_flower_cd_timer -= delta
		if _flower_cd_timer <= 0:
			flower_on_cooldown = false


func get_block_absorption() -> float:
	return block_absorption if block_active else 0.0


func is_blocking() -> bool:
	return block_active
