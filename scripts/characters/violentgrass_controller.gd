class_name ViolentgrassController
extends CharacterBody2D

signal hit_landed(target: Node2D, damage: float)
signal stamina_changed(current: float, max_stamina: float)
signal hp_changed(current_hp: float, max_hp: float)
signal teleport_scan_started()  # Emitted when killer starts teleport charge
signal teleport_cancelled()  # Emitted when killer cancels teleport charge
signal teleported(new_position: Vector2)  # Emitted when teleport completes (at destination)
signal teleport_zoom_started()  # Emitted to request camera zoom-out + map view
signal teleport_zoom_ended()   # Emitted to restore normal camera view
## (teleport_target_selected removed — unused)

enum State { IDLE, WALKING, HITTING, TELEPORT_CHARGING, TELEPORT_CASTING, TELEPORTING, STUNNED }
enum Direction { DOWN, LEFT, RIGHT, UP }

# Stats
@export var max_hp: float = 6666.0
@export var move_speed: float = 240.0
@export var sprint_speed: float = 350.0
@export var max_stamina: float = 110.0
@export var sprint_stamina_drain: float = 7.33  # per second (110 / 15 = 15s sprint)
@export var stamina_regen: float = 25.0  # per second when not sprinting
@export var stamina_regen_delay: float = 1.0  # seconds before regen kicks in

# Hit ability
@export var hit_damage: float = 25.0
@export var hit_cooldown: float = 2.5
@export var hit_range: float = 120.0  # Extended range — hits outside collision body

# Teleportation ability (nerfed: circles + decoy guessing game)
@export var teleport_range: float = 350.0  # Used by AI bot; human teleport is full-distance via circles
const TELEPORT_COOLDOWN_USED: float = 45.0   # Cooldown after teleporting
const TELEPORT_COOLDOWN_CANCEL: float = 25.0 # Cooldown after cancel
const teleport_cooldown: float = TELEPORT_COOLDOWN_USED  # Backward compat (AI bot refs this)

# ---------- SIZE ----------
@export var size_mult: float = 1.0:
	set(value):
		size_mult = value
		_apply_size()


# ---------- CHASE MUSIC SETTINGS ----------
# Only Chase layer plays (no build-up layers)
@export var chase_in_chase: float = 120.0     # Enter Chase (close to survivor)
@export var chase_out_chase: float = 200.0    # Leave Chase (hysteresis)

# Fade timing (seconds)
@export var chase_fade_in_duration: float = 0.5
@export var chase_fade_out_duration: float = 0.5

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_timer: Timer = $StateTimer
@onready var ability_vfx: AnimatedSprite2D = $AbilityVFX
@onready var hit_sound: AudioStreamPlayer2D = $HitSound
@onready var teleport_sound: AudioStreamPlayer2D = $TeleportSound

var current_hp: float
var current_stamina: float
var current_state: State = State.IDLE
var current_direction: Direction = Direction.DOWN
var is_sprinting: bool = false
var _stamina_regen_timer: float = 0.0

# Cooldown state
var hit_on_cooldown: bool = false
var teleport_on_cooldown: bool = false
var _hit_cd_timer: float = 0.0
var _teleport_cd_timer: float = 0.0
var _base_col_scale: Vector2 = Vector2.ONE  # Saved collision shape scale at init
var _base_sprite_scale: float = 0.25
var stair_climbing: bool = false

# Teleport scan state (no charging — press E to scan, click to teleport)
var _teleport_scan_active: bool = false

# Teleport charge animation state (retained for backward compat, no longer used)
const TELEPORT_FRAME_TIME: float = 1.0 / 14.0  # 14 fps
var _teleport_anim_frame: int = 0
var _teleport_anim_timer: float = 0.0
var _teleport_reversing: bool = false
var _teleport_target_dir: Vector2 = Vector2.ZERO

# Teleport reverse VFX playback (plays when arriving at destination)
var _teleport_reverse_playing: bool = false
var _teleport_reverse_frame: int = 0
var _teleport_reverse_timer: float = 0.0

# Stamina exhaustion
var _stamina_exhausted: bool = false
var _exhaustion_timer: float = 0.0


func _ready() -> void:
	current_hp = max_hp
	current_stamina = max_stamina
	hp_changed.emit(current_hp, max_hp)
	_change_state(State.IDLE)
	add_to_group("killers")
	# Save base scales for size_mult adjustments
	var cs: CollisionShape2D = $CollisionShape2D
	if is_instance_valid(cs):
		_base_col_scale = cs.scale
	if is_instance_valid(animated_sprite):
		_base_sprite_scale = animated_sprite.scale.x
	_apply_size()
	# Collision: killer on layer 2, only collide with survivor (layer 1) + walls (layer 3)
	collision_layer = 2  # Killer layer
	collision_mask = 1 | 4  # Survivor (1) + Walls (4)
	stamina_changed.emit(current_stamina, max_stamina)
	_setup_ability_vfx_frames()
	if not ability_vfx.animation_finished.is_connected(_on_ability_vfx_finished):
		ability_vfx.animation_finished.connect(_on_ability_vfx_finished)


func _input(event: InputEvent) -> void:
	# Q key OR left mouse button triggers hit
	if event.is_action_pressed("ability_1"):
		use_hit()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# During teleport scan, left click targets circles instead of hitting
		if _teleport_scan_active:
			return  # Let screen-edge UI buttons handle the click
		use_hit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ability_2"):
		if _teleport_scan_active:
			# Cancel teleport scan — press E again
			_cancel_teleport_charge()
		else:
			_start_teleport_charge()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	match current_state:
		State.IDLE, State.WALKING:
			_handle_movement(delta)
		State.HITTING:
			_handle_hitting(delta)
		State.TELEPORT_CHARGING:
			_handle_teleport_charging(delta)
		State.TELEPORT_CASTING:
			_handle_teleport_casting(delta)
		State.TELEPORTING:
			_handle_teleporting(delta)
		State.STUNNED:
			_handle_stunned(delta)
	
	# Stamina exhaustion countdown
	if _stamina_exhausted:
		_exhaustion_timer -= delta
		if _exhaustion_timer <= 0:
			_stamina_exhausted = false

	_update_cooldowns(delta)


# ---------- SIZE ----------

func _apply_size() -> void:
	"""Apply size_mult to sprite, VFX, and collision shape."""
	if not is_inside_tree():
		return
	if is_instance_valid(animated_sprite):
		animated_sprite.scale = Vector2(_base_sprite_scale * size_mult, _base_sprite_scale * size_mult)
	if is_instance_valid(ability_vfx):
		ability_vfx.scale = Vector2(_base_sprite_scale * size_mult, _base_sprite_scale * size_mult)
	var cs2: CollisionShape2D = $CollisionShape2D
	if is_instance_valid(cs2):
		cs2.scale = _base_col_scale * size_mult
	# Scale hit range proportionally
	hit_range = 120.0 * size_mult


func _handle_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")
	
	# Stamina management — Sprint Limit: 110 (killers, slightly faster than survivors)
	is_sprinting = Input.is_action_pressed("sprint")
	if is_sprinting and input_dir != Vector2.ZERO and current_stamina > 0.0 and not _stamina_exhausted:
		current_stamina -= sprint_stamina_drain * delta
		if current_stamina <= 0.0:
			current_stamina = 0.0
			_stamina_exhausted = true
			_exhaustion_timer = 3.0
			is_sprinting = false
		else:
			_stamina_regen_timer = stamina_regen_delay
	else:
		is_sprinting = false
	
	# Regenerate stamina after delay
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
		# 80% slow while teleport scanning (20% speed)
		if _teleport_scan_active:
			speed *= 0.2
		velocity = input_dir * speed
		_update_direction(input_dir)
		_play_animation("walk")
		_change_state(State.WALKING)
	else:
		velocity = Vector2.ZERO
		_play_animation("idle")
		_change_state(State.IDLE)
	
	move_and_slide()


func _handle_hitting(_delta: float) -> void:
	# Movement is allowed while hitting — don't lock the killer in place
	move_and_slide()
	# Hitting state persists for hit animation duration, then falls back to IDLE
	# The cooldown prevents spam, not the state lock


func _handle_teleport_charging(delta: float) -> void:
	"""Loop frames 3-6 (indices 2-5) while charging, with frames 1-2 as startup."""
	velocity = Vector2.ZERO
	
	_teleport_anim_timer += delta
	while _teleport_anim_timer >= TELEPORT_FRAME_TIME:
		_teleport_anim_timer -= TELEPORT_FRAME_TIME
		
		if _teleport_reversing:
			# Playing backwards — step down until frame 0
			_teleport_anim_frame -= 1
			if _teleport_anim_frame < 0:
				_do_teleport_move()
				return
		else:
			# Playing forward: startup frames 0->1, then loop 2->5
			_teleport_anim_frame += 1
			if _teleport_anim_frame > 5:
				_teleport_anim_frame = 2  # Loop back to frame 3 (index 2)
		
		ability_vfx.frame = _teleport_anim_frame


func _handle_teleport_casting(_delta: float) -> void:
	"""Wait briefly during the casting animation."""
	velocity = Vector2.ZERO


func _handle_teleporting(delta: float) -> void:
	velocity = Vector2.ZERO
	# Reverse teleport VFX playback (frames 6→0)
	if _teleport_reverse_playing:
		_teleport_reverse_timer += delta
		while _teleport_reverse_timer >= TELEPORT_FRAME_TIME:
			_teleport_reverse_timer -= TELEPORT_FRAME_TIME
			_teleport_reverse_frame -= 1
			if _teleport_reverse_frame < 0:
				_teleport_reverse_playing = false
				_hide_vfx()
				if current_state == State.TELEPORTING:
					_change_state(State.IDLE)
				return
			ability_vfx.frame = _teleport_reverse_frame


func _handle_stunned(_delta: float) -> void:
	velocity = Vector2.ZERO


func _update_direction(input_dir: Vector2) -> void:
	if abs(input_dir.x) > abs(input_dir.y):
		current_direction = Direction.RIGHT if input_dir.x > 0 else Direction.LEFT
	else:
		current_direction = Direction.DOWN if input_dir.y > 0 else Direction.UP


func _play_animation(anim: String) -> void:
	"""Play an animation - idle/walk on character, abilities on VFX overlay."""
	if not is_instance_valid(animated_sprite):
		return
	match anim:
		"idle":
			var dir_name: String = ["down", "left", "right", "up"][current_direction as int]
			var full_anim: String = "idle_" + dir_name
			if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(full_anim):
				animated_sprite.play(full_anim)
			else:
				animated_sprite.play("idle")  # Fallback to default
		"walk":
			var dir_name: String = ["down", "left", "right", "up"][current_direction as int]
			var full_anim: String = "walk_" + dir_name
			if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(full_anim):
				animated_sprite.play(full_anim)
			else:
				animated_sprite.play("idle")  # Fallback if walk anim missing
		"hit", "teleport":
			animated_sprite.play("idle")  # Character stays on idle
			_play_ability_vfx(anim)  # Show full-screen VFX overlay


func _change_state(new_state: State) -> void:
	current_state = new_state
	if new_state == State.IDLE:
		_hide_vfx()


# ---------- ABILITY VFX ----------

func _setup_ability_vfx_frames() -> void:
	"""Create sprite frames for ability VFX overlays."""
	var vfx_sf := SpriteFrames.new()
	
	# Hit animation (10 frames: 1-10)
	var hit_frames: Array[Texture2D] = []
	for i in range(1, 11):
		var path: String = "res://The Darkness Of The Grasslands assets/Sprites/Violentgrass/abilities/Hit MB1/Hit_MB1_frame-%d.png" % i
		var tex: Texture2D = load(path)
		if tex:
			hit_frames.append(tex)
	if not hit_frames.is_empty():
		vfx_sf.add_animation("hit")
		vfx_sf.set_animation_loop("hit", false)
		vfx_sf.set_animation_speed("hit", 20.0)
		for tex in hit_frames:
			vfx_sf.add_frame("hit", tex)
	
	# Teleport animation (7 frames: 1-7)
	var teleport_frames: Array[Texture2D] = []
	for i in range(1, 8):
		var path: String = "res://The Darkness Of The Grasslands assets/Sprites/Violentgrass/abilities/Teleportation/Teleportation_frame-(%d).png" % i
		var tex: Texture2D = load(path)
		if tex:
			teleport_frames.append(tex)
	if not teleport_frames.is_empty():
		vfx_sf.add_animation("teleport")
		vfx_sf.set_animation_loop("teleport", false)
		vfx_sf.set_animation_speed("teleport", 14.0)
		for tex in teleport_frames:
			vfx_sf.add_frame("teleport", tex)
	
	ability_vfx.sprite_frames = vfx_sf
	ability_vfx.visible = false


func _play_ability_vfx(anim: String) -> void:
	"""Play a full-screen VFX overlay animation."""
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
	if current_state == State.HITTING or current_state == State.TELEPORTING:
		current_state = State.IDLE


# ---------- HIT (MB1) ----------

# ---------- TELEPORT CHARGE & CAST ----------

func _start_teleport_charge() -> void:
	"""Start teleport scan — zoom out to map view shows circles. Press E again to cancel."""
	if current_state != State.IDLE and current_state != State.WALKING:
		return
	if teleport_on_cooldown:
		return
	
	_teleport_scan_active = true
	_hide_vfx()
	
	# Emit zoom request so game_map zoomes out + shows circles
	teleport_zoom_started.emit()
	teleport_scan_started.emit()


func _execute_teleport_release() -> void:
	"""Release teleport charge — play reverse animation, then teleport."""
	if current_state != State.TELEPORT_CHARGING:
		return
	
	_teleport_reversing = true
	# Determine teleport direction from mouse cursor
	var mouse_pos: Vector2 = get_global_mouse_position()
	_teleport_target_dir = mouse_pos - global_position
	_change_state(State.TELEPORT_CASTING)


func _cancel_teleport_charge() -> void:
	"""Cancel teleport scan — 25s cooldown penalty."""
	if not _teleport_scan_active:
		return
	_teleport_scan_active = false
	teleport_on_cooldown = true
	_teleport_cd_timer = TELEPORT_COOLDOWN_CANCEL
	teleport_cancelled.emit()
	teleport_zoom_ended.emit()


func teleport_to_position(target_pos: Vector2) -> void:
	"""Public method: teleport directly to a target position (called by game_map mini-map)."""
	if not is_instance_valid(self):
		return
	
	var delta_dir: Vector2 = target_pos - global_position
	var distance: float = delta_dir.length()
	
	# No range clamp — circles are the range limit, teleport goes full distance
	
	if distance > 0.0:
		var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + delta_dir)
		query.exclude = [self]
		query.collision_mask = 4  # Wall layer
		var result: Dictionary = space_state.intersect_ray(query)
		
		if result.is_empty():
			global_position += delta_dir
		else:
			var hit_pos: Vector2 = result.position
			var approach_dir: Vector2 = (hit_pos - global_position).normalized()
			global_position = hit_pos - approach_dir * 16.0
		
		# Visual effect shift
		modulate = Color(0.7, 0.3, 0.9, 0.5)
		get_tree().create_timer(0.3).timeout.connect(_end_teleport_visual)
	
	# Teleport executed — clear scan state
	_teleport_scan_active = false
	
	# Set cooldown AFTER teleport completes (45s penalty)
	teleport_on_cooldown = true
	_teleport_cd_timer = TELEPORT_COOLDOWN_USED
	
	# Emit teleported signal so game_map can play sound + show indicator
	teleported.emit(global_position)
	
	# Restore camera view
	teleport_zoom_ended.emit()
	
	# Play reverse teleport VFX (arrival effect)
	_play_teleport_vfx_reverse()
	
	_change_state(State.TELEPORTING)
	
	# 2.5 second stun — no movement, no abilities
	take_stun(2.5)


func _do_teleport_move() -> void:
	"""Actually execute the teleport movement."""
	if not is_instance_valid(self):
		return
	
	var distance: float = _teleport_target_dir.length()
	
	# No range clamp — full distance teleport
	
	if distance > 0.0:
		var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + _teleport_target_dir)
		query.exclude = [self]
		query.collision_mask = 4  # Wall layer
		var result: Dictionary = space_state.intersect_ray(query)
		
		if result.is_empty():
			global_position += _teleport_target_dir
		else:
			var hit_pos: Vector2 = result.position
			var approach_dir: Vector2 = (hit_pos - global_position).normalized()
			global_position = hit_pos - approach_dir * 16.0
		
		# Visual effect shift
		modulate = Color(0.7, 0.3, 0.9, 0.5)
		get_tree().create_timer(0.3).timeout.connect(_end_teleport_visual)
	
	# Emit teleported signal so game_map can play sound + show indicator
	teleported.emit(global_position)
	
	_change_state(State.TELEPORTING)
	_hide_vfx()


func _end_teleport_visual() -> void:
	if not is_instance_valid(self):
		return
	modulate = Color.WHITE
	if current_state == State.TELEPORTING:
		_change_state(State.IDLE)


# ---------- HIT (MB1) ----------

func use_hit() -> void:
	# Play hit sound
	if is_instance_valid(hit_sound) and not hit_sound.playing:
		hit_sound.play()
	
	if current_state != State.IDLE and current_state != State.WALKING:
		return
	if hit_on_cooldown:
		return
	
	# Check if we hit a survivor in range WITH line-of-sight
	var target := _find_survivor_in_range()
	if target == null or not _has_line_of_sight(target):
		# Hit NO ONE → no cooldown penalty, no state change, just visual + sound
		_play_animation("hit")
		return
	
	# Hit connects — apply cooldown and damage (movement continues; no state lock)
	hit_on_cooldown = true
	_hit_cd_timer = hit_cooldown
	_play_animation("hit")
	
	_ping_hit(target)
	hit_landed.emit(target, hit_damage)
	# Check if target is blocking
	if target.has_method("on_block_hit"):
		if target.on_block_hit():
			# Block absorbed — unlocks their punch
			pass
		else:
			# Apply damage
			var absorption: float = target.get_block_absorption() if target.has_method("get_block_absorption") else 0.0
			var final_damage: float = hit_damage * (1.0 - absorption)
			_apply_damage(target, final_damage)


func find_survivors_in_range() -> Array[Node2D]:
	var survivors: Array[Node] = get_tree().get_nodes_in_group("survivors")
	var in_range: Array[Node2D] = []
	for s in survivors:
		if is_instance_valid(s):
			var dist: float = global_position.distance_to(s.global_position)
			if dist <= hit_range:
				in_range.append(s)
	return in_range


func _find_survivor_in_range() -> Node2D:
	var in_range := find_survivors_in_range()
	if in_range.is_empty():
		return null
	return in_range[0]


func _apply_damage(target: Node2D, damage: float) -> void:
	if target.has_method("take_damage"):
		target.take_damage(damage)


# ---------- PING HANDLER ----------

func _has_line_of_sight(target: Node2D) -> bool:
	"""Check if there's clear line-of-sight to the target (no walls between)."""
	if not is_instance_valid(target):
		return false
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, 1)
	# Only collide with walls (layer 3)
	query.collision_mask = 4
	query.exclude = [self, target]
	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()


func _ping_hit(target: Node2D) -> void:
	"""Visual feedback when a LOS hit connects — flash the target white."""
	if not is_instance_valid(target):
		return
	var orig: Color = target.modulate
	target.modulate = Color(2.0, 2.0, 2.0, 1.0)
	var tween := create_tween()
	tween.tween_property(target, "modulate", orig, 0.25).set_ease(Tween.EASE_OUT)


# ---------- COOLDOWNS ----------

func _update_cooldowns(delta: float) -> void:
	if hit_on_cooldown:
		_hit_cd_timer -= delta
		if _hit_cd_timer <= 0:
			hit_on_cooldown = false
	
	if teleport_on_cooldown:
		_teleport_cd_timer -= delta
		if _teleport_cd_timer <= 0:
			teleport_on_cooldown = false


# ---------- STUN ----------

func take_stun(duration: float) -> void:
	"""Stun this character for the given duration."""
	if current_state == State.STUNNED:
		return
	print("Violentgrass stunned for ", duration, "s")
	_change_state(State.STUNNED)
	state_timer.start(duration)
	
	# Visual feedback
	modulate = Color(0.5, 0.5, 0.5, 1.0)
	get_tree().create_timer(duration).timeout.connect(_end_stun)


func _end_stun() -> void:
	if not is_instance_valid(self):
		return
	modulate = Color.WHITE
	if current_state == State.STUNNED:
		_change_state(State.IDLE)


# ---------- TELEPORT REVERSE VFX ----------

func _play_teleport_vfx_reverse() -> void:
	"""Play the teleport VFX in reverse (frames 7→1) as an arrival effect."""
	if not ability_vfx.sprite_frames or not ability_vfx.sprite_frames.has_animation("teleport"):
		return
	_teleport_reverse_playing = true
	_teleport_reverse_frame = 6  # 0-indexed, last frame (frame 7 in 1-indexed)
	_teleport_reverse_timer = 0.0
	ability_vfx.visible = true
	ability_vfx.frame = _teleport_reverse_frame
	ability_vfx.stop()  # Don't play forward


# ---------- DAMAGE ----------

func take_damage(amount: float) -> void:
	current_hp -= amount
	print("Violentgrass took ", amount, " damage, HP: ", current_hp)
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		current_hp = 0
		queue_free()
