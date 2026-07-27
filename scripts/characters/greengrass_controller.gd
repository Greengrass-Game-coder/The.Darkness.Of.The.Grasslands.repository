class_name GreengrassController
extends CharacterBody2D

signal block_unlocked_punch()
signal punch_landed(stunned: bool)
signal healed(amount: float, source: String)
signal stamina_changed(current: float, max_stamina: float)
signal slowed(duration: float)  # Emitted when block-dash makes player slow
signal hp_changed(current_hp: float, max_hp: float)

enum State { IDLE, WALKING, BLOCKING, DASH_BLOCKING, PUNCHING, PUNCH_CHARGING, HEALING, STUNNED, SLOWED }

# Blocking constants
const BLOCK_SLOW_SPEED: float = 80.0  # 40% of 200 move_speed
const DASH_SPEED: float = 600.0
const DASH_COST: float = 25.0  # 25% stamina cost
enum Direction { DOWN, LEFT, RIGHT, UP }

# Stats
@export var max_hp: float = 100.0
@export var move_speed: float = 160.0
@export var sprint_speed: float = 250.0
@export var max_stamina: float = 100.0
@export var sprint_stamina_drain: float = 6.67  # per second (100 / 15 = 15s sprint)
@export var stamina_regen: float = 25.0  # per second when not sprinting
@export var stamina_regen_delay: float = 1.0  # seconds before regen kicks in

# Ability cooldowns (seconds)
@export var block_cooldown: float = 20.0
@export var punch_cooldown: float = 20.0
@export var parry_punch_cooldown: float = 30.0
@export var spare_flower_cooldown: float = 45.0

# Ability params
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

# Ability state
var block_on_cooldown: bool = false
var punch_on_cooldown: bool = false
var flower_on_cooldown: bool = false
var block_timer: float = 0.0
var block_active: bool = false
var can_block_hit: bool = false

# Grass Punch state
var parry_window_active: bool = false     # 1.5-sec window after successful block
var is_parry_punch: bool = false          # Whether current punch is parry variant
var punch_target: Vector2 = Vector2.ZERO  # Mouse target position
var punch_locked: bool = true             # Grass Punch locked until block is used
var _charging: bool = false               # Currently charging a punch
var _charge_time: float = 0.0             # How long E has been held

# Spare Flower state
var healing_ally: Node = null
var heal_over_time_active: bool = false
var heal_tick_timer: float = 0.0
var heal_ticks_remaining: int = 7  # 70 total = 7 ticks of 10

# Block-dash slow state
var _slow_active: bool = false
var _slow_timer: float = 0.0
const SLOW_MULTIPLIER: float = 0.5  # Move at 50% speed while slowed

# Cooldown timers (declared before use to avoid GDScript ordering issues)
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
	# ability_4 (T) reserved for future use


func _physics_process(delta: float) -> void:
	# Track slow timer
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
	
	# Passive cooldown tracking
	_update_cooldowns(delta)
	
	# Heal-over-time ticks
	if heal_over_time_active:
		heal_tick_timer -= delta
		if heal_tick_timer <= 0:
			_tick_heal_over_time()


func _handle_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")
	
	# Stamina management — Sprint Limit: 100 (survivors)
	is_sprinting = Input.is_action_pressed("sprint")
	if is_sprinting and input_dir != Vector2.ZERO and current_stamina > 0.0:
		current_stamina -= sprint_stamina_drain * delta
		if current_stamina < 0.0:
			current_stamina = 0.0
		is_sprinting = true
		_stamina_regen_timer = stamina_regen_delay
	else:
		is_sprinting = false
	
	# Regenerate stamina after delay (even at 0, starts regen after delay)
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
	"""Slow movement while blocking — move at 40% speed.
	VFX plays once from use_block(), no need to re-trigger here."""
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
	"""Dash to mouse position while blocking — uses 25% stamina.
	VFX plays once from use_block()."""
	var target: Vector2 = get_global_mouse_position()
	var dir: Vector2 = (target - global_position).normalized()
	if dir.length() > 0.0:
		velocity = dir * DASH_SPEED
		_update_direction(dir)
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()
	
	# Check if we reached the target or close enough
	if global_position.distance_squared_to(target) < 400.0:  # 20px threshold
		_end_block()


func _handle_punching(_delta: float) -> void:
	velocity = Vector2.ZERO
	# Auto-transition handled by _on_punch_finished timer


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
	"""Play an animation on the character sprite.
	For idle, use the static single-frame idle.
	For walking, append direction suffix.
	For abilities, show VFX overlay."""
	match anim:
		"idle":
			var dir_name: String = ["down", "left", "right", "up"][current_direction as int]
			var full_anim: String = "idle_" + dir_name
			if animated_sprite.sprite_frames.has_animation(full_anim):
				animated_sprite.play(full_anim)
			else:
				animated_sprite.play("idle")  # Fallback to default
		"walk":
			var dir_name: String = ["down", "left", "right", "up"][current_direction as int]
			var full_anim: String = "walk_" + dir_name
			if animated_sprite.sprite_frames.has_animation(full_anim):
				animated_sprite.play(full_anim)
		"block":
			# Character stays on idle during block, VFX overlay shows the ability
			animated_sprite.play("idle")
			_play_ability_vfx(anim)
		"punch":
			# Play non-directional punch animation
			if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("punch"):
				animated_sprite.play("punch")
			else:
				animated_sprite.play("idle")
			_play_ability_vfx(anim)
		"punch_parry":
			# Play non-directional parry animation
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
		# Re-show character sprite if it was hidden by block
		if not animated_sprite.visible:
			animated_sprite.visible = true


# ---------- ABILITY VFX ----------

func _setup_ability_vfx_frames() -> void:
	"""Create sprite frames for ability VFX overlays (full-screen via CanvasLayer)."""
	var vfx_sf := SpriteFrames.new()
	
	# Block animation (13 frames: 0-12)
	var block_frames: Array[Texture2D] = []
	for i in range(13):
		var path: String = "res://The Darkness Of The Grasslands assets/Sprites/Greengrass/Abilities/Ability --- BLOCK/Ability_BLOCK_frame_%d.png" % i
		var tex: Texture2D = load(path)
		if tex:
			block_frames.append(tex)
	if not block_frames.is_empty():
		vfx_sf.add_animation("block")
		vfx_sf.set_animation_loop("block", false)
		vfx_sf.set_animation_speed("block", 10.0)  # Slow: 13 frames × 10fps = 1.3s
		for tex in block_frames:
			vfx_sf.add_frame("block", tex)
	
	# Punch animation (13 frames: 00000-00012)
	var punch_frames: Array[Texture2D] = []
	for i in range(13):
		var path: String = "res://The Darkness Of The Grasslands assets/Sprites/Greengrass/Abilities/Ability --- PUNCH/PUNCH_frame_%05d.png" % i
		var tex: Texture2D = load(path)
		if tex:
			punch_frames.append(tex)
	if not punch_frames.is_empty():
		vfx_sf.add_animation("punch")
		vfx_sf.set_animation_loop("punch", false)
		vfx_sf.set_animation_speed("punch", 8.0)  # 13 frames × 8fps = 1.625s
		for tex in punch_frames:
			vfx_sf.add_frame("punch", tex)
	
	# Parry punch (5 frames: 0000 uses 4 digits, 00001-00004 use 5 digits)
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
		vfx_sf.set_animation_speed("punch_parry", 12.0)  # 5 frames × 12fps = 0.42s
		for tex in parry_frames:
			vfx_sf.add_frame("punch_parry", tex)
	
	# Heal animation (9 frames: 0-8)
	var heal_frames: Array[Texture2D] = []
	for i in range(9):
		var path: String = "res://The Darkness Of The Grasslands assets/Sprites/Greengrass/Abilities/Ability --- SPARE FLOWER/ABILITY_HEAL_frame-%d.png" % i
		var tex: Texture2D = load(path)
		if tex:
			heal_frames.append(tex)
	if not heal_frames.is_empty():
		vfx_sf.add_animation("heal")
		vfx_sf.set_animation_loop("heal", false)
		vfx_sf.set_animation_speed("heal", 10.0)  # 9 frames × 10fps = 0.9s
		for tex in heal_frames:
			vfx_sf.add_frame("heal", tex)
	
	ability_vfx.sprite_frames = vfx_sf
	ability_vfx.visible = false


func _play_ability_vfx(anim: String) -> void:
	"""Play a full-screen VFX overlay animation without blocking state flow."""
	if ability_vfx.sprite_frames and ability_vfx.sprite_frames.has_animation(anim):
		ability_vfx.visible = true
		ability_vfx.play(anim)


func _hide_vfx() -> void:
	"""Hide the VFX overlay."""
	ability_vfx.visible = false
	ability_vfx.stop()


func _on_ability_vfx_finished() -> void:
	"""Handle VFX animation finished — hide VFX and transition state."""
	_hide_vfx()
	if current_state in [State.PUNCHING, State.HEALING, State.BLOCKING]:
		current_state = State.IDLE


# ---------- HITBOX (for punch) ----------

func _get_hitbox_shape() -> RectangleShape2D:
	"""Create a hitbox rectangle extending in the facing direction."""
	var hitbox := RectangleShape2D.new()
	hitbox.size = Vector2(punch_range, 48)
	return hitbox


func _get_hitbox_position() -> Vector2:
	"""Get position for hitbox based on facing direction."""
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
	"""Check if punch connects with a killer in range."""
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
	
	# Hide the character sprite during block, show VFX instead
	animated_sprite.visible = false
	
	# Check for dash block (sprint + block) — must have stamina and be sprinting
	var is_dashing: bool = is_sprinting and current_stamina >= DASH_COST
	
	if is_dashing:
		current_stamina -= DASH_COST
		stamina_changed.emit(current_stamina, max_stamina)
		_change_state(State.DASH_BLOCKING)
		_play_animation("block")
		# After dash-block ends, apply 3s slow
		get_tree().create_timer(0.8).timeout.connect(_on_dash_block_end)
	else:
		_change_state(State.BLOCKING)
		_play_animation("block")
		# Normal block lasts 1.5s
		get_tree().create_timer(1.5).timeout.connect(_end_block)


func on_block_hit() -> bool:
	"""Called when an M1 or manual-hit Killer ability connects during block.
	Returns true if the block absorbed the hit and opens parry window."""
	if not block_active or not can_block_hit:
		return false
	
	# Absorb the damage (handled by caller with block_absorption)
	can_block_hit = false
	parry_window_active = true
	punch_locked = false  # Unlock Grass Punch
	animated_sprite.visible = true  # Re-show sprite on hit
	
	# Clear any block-dash slow since the player was hit
	_clear_slow()
	
	block_unlocked_punch.emit()
	
	# Parry window lasts 2 seconds — next E (Grass Punch) becomes parry punch
	get_tree().create_timer(parry_window).timeout.connect(_end_parry_window)
	
	_end_block()
	return true


func _end_block() -> void:
	block_active = false
	can_block_hit = false
	animated_sprite.visible = true  # Re-show sprite
	if current_state == State.BLOCKING or current_state == State.DASH_BLOCKING:
		_change_state(State.IDLE)


func _end_parry_window() -> void:
	parry_window_active = false
	punch_locked = true  # Re-lock Grass Punch when parry window ends


func _on_dash_block_end() -> void:
	"""Called when dash-block duration finishes. Applies 3s slow."""
	_end_block()
	# Apply slow
	_slow_active = true
	_slow_timer = 3.0
	slowed.emit(3.0)


func _clear_slow() -> void:
	"""Remove the block-dash slow effect (called when hit by killer)."""
	_slow_active = false
	_slow_timer = 0.0


func take_damage(amount: float) -> void:
	"""Take damage from a killer attack."""
	if block_active and can_block_hit:
		# Block absorbed the hit
		var _absorbed: float = amount * block_absorption
		current_hp -= amount * (1.0 - block_absorption)
		on_block_hit()
	else:
		current_hp -= amount
	
	if current_hp <= 0.0:
		current_hp = 0.0
		# Death logic could go here
	
	hp_changed.emit(current_hp, max_hp)
	_clear_slow()  # Hit by killer clears slow


# ---------- GRASS PUNCH ----------

func _start_charge_punch() -> void:
	"""Start charging the Grass Punch (hold E)."""
	if current_state != State.IDLE and current_state != State.WALKING:
		return
	if punch_on_cooldown:
		return
	if punch_locked and not parry_window_active:
		# Punch is locked — show visual feedback
		modulate = Color(0.8, 0.8, 0.8, 1)
		get_tree().create_timer(0.15).timeout.connect(_restore_modulate)
		return
	
	_charging = true
	_charge_time = 0.0
	_change_state(State.PUNCH_CHARGING)
	_play_animation("idle")  # Show idle during charge
	ability_vfx.visible = true
	ability_vfx.play("punch")  # Play VFX as charge indicator
	
	# Visual: start yellow tint
	animated_sprite.modulate = Color(1.0, 1.0, 0.2, 1)


func _fire_charged_punch() -> void:
	"""Release the charged punch toward mouse position."""
	if not _charging:
		return
	_charging = false
	punch_on_cooldown = true
	_punch_cd_timer = parry_punch_cooldown if parry_window_active else punch_cooldown
	
	var target_pos: Vector2 = get_global_mouse_position()
	punch_target = target_pos
	_change_state(State.PUNCHING)
	
	# Determine if this is a parry punch (used within parry window)
	is_parry_punch = parry_window_active
	if parry_window_active:
		parry_window_active = false
		punch_locked = true  # Re-lock after use
	_play_animation("punch_parry" if is_parry_punch else "punch")
	
	# Charge amplification: 1.0x at min, 2.0x at max (1.5s cap)
	var charge_ratio: float = min(_charge_time / 1.5, 1.0)
	var dmg_mult: float = 0.5 + charge_ratio * 1.5  # 0.5x to 2.0x
	_charge_time = 0.0
	
	# Visual emphasis - YELLOW flash + scale bounce
	var orig_scale: Vector2 = animated_sprite.scale
	var orig_mod: Color = animated_sprite.modulate
	var vfx_tween: Tween = create_tween().set_parallel(true)
	vfx_tween.tween_property(animated_sprite, "modulate", Color(3, 3, 0.3, 1), 0.08)
	vfx_tween.tween_property(animated_sprite, "modulate", orig_mod, 0.25).set_delay(0.08).set_ease(Tween.EASE_OUT)
	vfx_tween.tween_property(animated_sprite, "scale", orig_scale * (1.3 + charge_ratio * 0.4), 0.08)
	vfx_tween.tween_property(animated_sprite, "scale", orig_scale, 0.25).set_delay(0.08).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	# Hitbox check — find killers in range
	var hits: Array[Node2D] = _check_punch_hit()
	for target in hits:
		punch_landed.emit(is_parry_punch)
		var stun_duration: float = (parry_stun if is_parry_punch else normal_stun) * dmg_mult
		if target.has_method("take_stun"):
			target.take_stun(stun_duration)
		break  # Only hit one target
	
	# Auto-exit punch after 1s
	state_timer.start(1.0)
	await state_timer.timeout
	if current_state == State.PUNCHING:
		_change_state(State.IDLE)
		_restore_modulate()


func _handle_charge(delta: float) -> void:
	"""While charging, track time and show VFX."""
	_charge_time += delta
	if _charge_time > 1.5:
		_charge_time = 1.5  # Cap at 1.5s
	
	# Pulse yellow brightness based on charge
	var pulse: float = sin(_charge_time * 12.0) * 0.3 + 0.7
	var bright: float = 1.0 + _charge_time * 1.0  # 1.0 → 2.5
	animated_sprite.modulate = Color(bright * pulse, bright * pulse * 0.8, 0.2, 1)
	
	# Hover in place
	velocity = Vector2.ZERO
	move_and_slide()


func _restore_modulate() -> void:
	if is_instance_valid(animated_sprite):
		animated_sprite.modulate = Color.WHITE


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
	
	# Always heal self first (instant)
	_apply_heal(spare_flower_heal, "self")
	
	# Also heal nearby ally if one exists (over-time)
	var ally := _find_nearest_ally()
	if ally != null:
		healing_ally = ally
		heal_over_time_active = true
		heal_ticks_remaining = 7
		heal_tick_timer = 1.0  # Tick every second
	
	# Go back to movement after heal animation completes
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
	# Actually heal HP
	if target == self:
		current_hp = min(current_hp + amount, max_hp)
		hp_changed.emit(current_hp, max_hp)
	elif target.has_method("get_current_hp") and target.has_method("set_current_hp"):
		var hp: float = target.get("current_hp")
		target.set("current_hp", min(hp + amount, target.get("max_hp")))
	# Emit signals
	if target.has_signal("healed"):
		target.healed.emit(amount, source)
	healed.emit(amount, source)


# ---------- COOLDOWN ----------

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
