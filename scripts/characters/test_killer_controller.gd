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
## Emitted when a survivor steps on a Rage trap and gets revealed
signal rage_triggered(survivor: Node2D)
## Emitted when Better Sight locks onto the nearest survivor
signal better_sight_triggered(survivor: Node2D)
## Emitted when an ability is blocked by a rule (e.g. survivor too close for Tentacle Snatch)
signal ability_blocked(message: String)

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
@export var tentacle_max_range: float = 1000.0
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

# ── The Rage (information trap) ──
@export var rage_max_traps: int = 5
@export var rage_cooldown: float = 5.0
@export var rage_reveal_duration: float = 10.0
@export var rage_trap_radius: float = 88.0

# ── Better Sight (tracking / chase) ──
@export var better_sight_cooldown: float = 8.0
@export var better_sight_speed_mult: float = 1.5
@export var better_sight_reach_distance: float = 120.0
@export var better_sight_arrow_radius: float = 60.0

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
var _hit_vfx_timer: float = 0.0
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
var _tentacle_body: Sprite2D = null  # Stretchable tentacle body (killer -> tip)

# Tentacle SFX (user-provided, in Sound/Sfx/Abilities/Test Killer/)
const TENTACLE_STRETCH_SOUND := "res://The Darkness Of The Grasslands assets/Sound/Sfx/Abilities/Test Killer/tentacle_stretch_looped.wav"
const TENTACLE_CATCH_SOUND := "res://The Darkness Of The Grasslands assets/Sound/Sfx/Abilities/Test Killer/tentacle_catch_notlooped.wav"
const TENTACLE_STOP_SOUND := "res://The Darkness Of The Grasslands assets/Sound/Sfx/Abilities/Test Killer/tentacle_stops_stretch_notlooped.wav"
const TENTACLE_RETRACT_SOUND := "res://The Darkness Of The Grasslands assets/Sound/Sfx/Abilities/Test Killer/tentacle_retract_looped.wav"
var _tentacle_stretch_audio: AudioStreamPlayer2D = null
var _tentacle_catch_audio: AudioStreamPlayer2D = null
var _tentacle_stop_audio: AudioStreamPlayer2D = null
var _tentacle_retract_audio: AudioStreamPlayer2D = null
var rage_on_cooldown: bool = false
var rage_cooldown_timer: float = 0.0
var _rage_traps: Array = []
var _rage_elapsed: float = 0.0
## How long The Rage freezes the killer in place after placing a trap.
const RAGE_FREEZE_DURATION: float = 2.5
var _rage_freeze_timer: float = 0.0
var _revealed_survivor: Node2D = null
var _reveal_marker: Node2D = null
var _reveal_timer: float = 0.0
var better_sight_on_cooldown: bool = false
var better_sight_cooldown_timer: float = 0.0
var _better_sight_active: bool = false
var _better_sight_target: Node2D = null
var _better_sight_marker: Node2D = null


# ═══════════════ LIFECYCLE ═══════════════

func _ready() -> void:
	current_hp = max_hp
	current_stamina = max_stamina
	_base_sprite_scale = animated_sprite.scale.x if animated_sprite else 1.0
	_base_col_scale = $CollisionShape2D.scale.x if has_node("CollisionShape2D") else 1.0
	_apply_size()
	# Set up tentacle SFX players (stretch/retract loop while active).
	_tentacle_stretch_audio = _make_audio_player(TENTACLE_STRETCH_SOUND, true)
		if _tentacle_stretch_audio:
			_tentacle_stretch_audio.volume_db = linear_to_db(1.1)  # +10% louder
	_tentacle_catch_audio = _make_audio_player(TENTACLE_CATCH_SOUND, false)
	_tentacle_stop_audio = _make_audio_player(TENTACLE_STOP_SOUND, false)
	_tentacle_retract_audio = _make_audio_player(TENTACLE_RETRACT_SOUND, true)


func _physics_process(delta: float) -> void:
	if current_hp <= 0.0:
		return
	
	_update_cooldowns(delta)
	_update_rage(delta)
	_update_better_sight(delta)
	
	# Auto-hide the non-blocking M1 swing effect.
	if _hit_vfx_timer > 0.0:
		_hit_vfx_timer -= delta
		if _hit_vfx_timer <= 0.0 and is_instance_valid(ability_vfx):
			ability_vfx.visible = false
	
	# Freeze in place briefly after placing The Rage.
	if _rage_freeze_timer > 0.0:
		_rage_freeze_timer -= delta
		velocity = Vector2.ZERO
		current_state = State.IDLE
		_play_idle_animation()
		move_and_slide()
		return
	
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
	# The Rage freeze locks the killer in place — no actions allowed for 2.5s.
	if _rage_freeze_timer > 0.0:
		return
	
	if event.is_action_pressed("ability_1"):
		_start_hit()
	elif event.is_action_pressed("ability_2"):
		_activate_tentacle_snatch()
	elif event.is_action_pressed("ability_3"):
		_place_rage_trap()
	elif event.is_action_pressed("ability_4"):
		_activate_better_sight()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_start_hit()


func _update_cooldowns(delta: float) -> void:
	if hit_on_cooldown:
		hit_cooldown_timer -= delta
		if hit_cooldown_timer <= 0.0:
			hit_on_cooldown = false
	if tentacle_on_cooldown:
		tentacle_cooldown_timer -= delta
		if tentacle_cooldown_timer <= 0.0:
			tentacle_on_cooldown = false
	if rage_on_cooldown:
		rage_cooldown_timer -= delta
		if rage_cooldown_timer <= 0.0:
			rage_on_cooldown = false
	if better_sight_on_cooldown:
		better_sight_cooldown_timer -= delta
		if better_sight_cooldown_timer <= 0.0:
			better_sight_on_cooldown = false


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
	if _better_sight_active:
		speed *= better_sight_speed_mult
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
	if hit_on_cooldown or _rage_freeze_timer > 0.0:
		return
	if current_state == State.TENTACLE_SNATCH:
		# M1 during the tentacle releases the grabbed survivor so they can run.
		_release_tentacle_target()
		_deactivate_tentacle(false, true)
		return
	# M1 is a quick, non-blocking swing — the killer keeps moving freely while
	# attacking instead of being forced to stop (no HITTING state freeze).
	hit_on_cooldown = true
	hit_cooldown_timer = hit_cooldown
	_perform_hit()
	ability_vfx.play("hit_down")
	ability_vfx.visible = true
	_hit_vfx_timer = 0.35


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
	
	# Damage the nearest living survivor in front of the killer. Uses group
	# lookup instead of a physics ray so hits reliably land on survivor bots
	# regardless of collision-layer quirks (bots were taking no damage from M1).
	var target: Node2D = _find_survivor_in_hit_range(hit_dir)
	if is_instance_valid(target):
		var dmg: float = hit_damage
		# Tentacle follow-up: boosted M1 after a successful snatch
		if _tentacle_caught_survivor and target == _tentacle_caught_survivor:
			dmg = tentacle_m1_damage
			_tentacle_caught_survivor = null
		target.take_damage(dmg)
		hit_landed.emit(target, dmg)
		# M1 unstuns the grabbed/stunned survivor so they can run away.
		if target.has_method("clear_stun"):
			target.clear_stun()
	
	if hit_sound:
		hit_sound.play()


func _find_survivor_in_hit_range(hit_dir: Vector2) -> Node2D:
	"""Return the nearest living survivor (player or bot) within hit range that is
	roughly in front of the killer (matching the old forward-ray cone)."""
	var best: Node2D = null
	var best_dist: float = hit_range
	for group_name in ["survivors", "survivor_bots"]:
		for s in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(s) or not s.has_method("take_damage"):
				continue
			if s.get("current_hp") != null and float(s.get("current_hp")) <= 0.0:
				continue
			var to_s: Vector2 = s.global_position - global_position
			var dist: float = to_s.length()
			if dist > hit_range or dist <= 0.0:
				continue
			if hit_dir != Vector2.ZERO and to_s.normalized().dot(hit_dir) < 0.5:
				continue  # behind the killer
			if dist < best_dist:
				best_dist = dist
				best = s as Node2D
	return best


# ═══════════════ STUNNED ═══════════════

func _handle_stunned(_delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()


# ═══════════════ TENTACLE SNATCH ═══════════════

func _make_audio_player(path: String, looped: bool) -> AudioStreamPlayer2D:
	"""Create a positional audio player for a tentacle SFX (optionally looped)."""
	var p := AudioStreamPlayer2D.new()
	var s: AudioStream = load(path)
	if s is AudioStreamWAV and looped:
		var w := s as AudioStreamWAV
		# Compute the real frame count from the stream's own length (the wavs
		# import as QOA, so data.size() does NOT map to PCM frames).
		var frames: int = int(w.get_length() * w.mix_rate)
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = frames
	p.stream = s
	p.bus = "SFX"
	add_child(p)
	return p


func _play_tentacle_stretch_sound() -> void:
	if _tentacle_stretch_audio and not _tentacle_stretch_audio.playing:
		_tentacle_stretch_audio.play()


func _stop_tentacle_stretch_sound() -> void:
	if _tentacle_stretch_audio and _tentacle_stretch_audio.playing:
		_tentacle_stretch_audio.stop()
		if _tentacle_stop_audio:
			_tentacle_stop_audio.play()


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
	if _rage_freeze_timer > 0.0:
		return
	# Can't start Tentacle Snatch while a survivor is too close (within 500px).
	if _nearest_survivor_distance() < 500.0:
		var msg := "Can't use Tentacle Snatch — a survivor is too close!"
		ability_blocked.emit(msg)
		print("TestKiller: ", msg)
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
	# No texture: the static tip PNG is removed - only the stretching body is shown
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
	
	# Stretchable tentacle body from the killer to the tip
	_tentacle_body = Sprite2D.new()
	_tentacle_body.name = "TentacleBody"
	_tentacle_body.texture = load("res://The Darkness Of The Grasslands assets/Sprites/test killer/abilities/Tentacle UI/tentacle_vertical.png")
	_tentacle_body.z_index = 190
	add_child(_tentacle_body)
	
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
	
	# Control the tentacle with WASD — it only extends while steered and holds
	# still when no direction is held (it no longer auto-stretches downward).
	var aim_dir: Vector2 = _get_aim_direction()
	if aim_dir.length_squared() < 0.01:
		# Holding still — stop the stretch hum.
		_stop_tentacle_stretch_sound()
		return
	
	# Extending — hum the stretch loop.
	_play_tentacle_stretch_sound()
	
	var tentacle_speed: float = move_speed * tentacle_speed_mult
	var target_pos: Vector2 = _tentacle_node.position + aim_dir * tentacle_speed * delta
	
	# Clamp to max range from killer
	if target_pos.length() > tentacle_max_range:
		target_pos = target_pos.normalized() * tentacle_max_range
	
	_tentacle_node.position = target_pos
	
	# Rotate tentacle to face movement direction
	_tentacle_node.rotation = aim_dir.angle() + PI / 2
	
	# Stretch tentacle body from killer to tip and follow with camera
	_apply_tentacle_stretch()
	_follow_tentacle_with_camera()


func _get_aim_direction() -> Vector2:
	"""Get the direction from the tentacle using WASD input (ZERO = hold still)."""
	var raw_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	return raw_dir.normalized()


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
	# SFX: catch thunk, stop the stretch hum, start the retract loop.
	if _tentacle_catch_audio:
		_tentacle_catch_audio.play()
	if _tentacle_stretch_audio:
		_tentacle_stretch_audio.stop()
	if _tentacle_retract_audio and not _tentacle_retract_audio.playing:
		_tentacle_retract_audio.play()


func _retract_tentacle(delta: float) -> void:
	"""Pull the tentacle (and caught survivor) back toward the killer."""
	if not is_instance_valid(_tentacle_node):
		_deactivate_tentacle(true, false)
		return
	
	if _tentacle_retract_audio and not _tentacle_retract_audio.playing:
		_tentacle_retract_audio.play()
	var retract_speed: float = move_speed * tentacle_speed_mult * 1.5  # Faster retraction
	var dir_to_killer: Vector2 = -_tentacle_node.position.normalized()
	if _tentacle_node.position.length() < 10.0:
		# Reached killer — apply stun and finish
		_finish_tentacle_catch()
		return
	
	_tentacle_node.position += dir_to_killer * retract_speed * delta
	
	# Stretch tentacle body from killer to tip and follow with camera
	_apply_tentacle_stretch()
	_follow_tentacle_with_camera()
	
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


func _release_tentacle_target() -> void:
	"""Release a grabbed survivor from the tentacle so they can move again."""
	if is_instance_valid(_tentacle_caught_survivor):
		if _tentacle_caught_survivor.has_method("clear_stun"):
			_tentacle_caught_survivor.clear_stun()
	_tentacle_caught_survivor = null
	_tentacle_retracting = false


func _apply_tentacle_stretch() -> void:
	"""Stretch the tentacle body sprite from the killer (0,0) to the tip."""
	if not is_instance_valid(_tentacle_body) or not is_instance_valid(_tentacle_node):
		return
	var tip: Vector2 = _tentacle_node.position
	var dist: float = tip.length()
	if dist < 1.0:
		dist = 1.0
	var tex_h: float = 128.0
	if _tentacle_body.texture:
		tex_h = float(_tentacle_body.texture.get_height())
	_tentacle_body.position = tip * 0.5
	_tentacle_body.rotation = tip.angle() + PI / 2
	# Neutral body size: thin it out from the full texture width (was 1.0 = 169px thick)
	_tentacle_body.scale = Vector2(0.25, dist / tex_h)


func _follow_tentacle_with_camera() -> void:
	"""Move the player's camera to follow the tentacle tip."""
	if not is_instance_valid(_tentacle_node):
		return
	var cam: Camera2D = get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.global_position = global_position + _tentacle_node.position


func _restore_camera_to_killer() -> void:
	"""Return the camera to following the killer."""
	var cam: Camera2D = get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.global_position = global_position


func _deactivate_tentacle(success: bool, cancelled: bool) -> void:
	"""Clean up tentacle and set cooldown."""
	_tentacle_active = false
	
	# Stop tentacle SFX: snap-back "stop" if the stretch hum was still going.
	if _tentacle_stretch_audio and _tentacle_stretch_audio.playing:
		_tentacle_stretch_audio.stop()
		if _tentacle_stop_audio:
			_tentacle_stop_audio.play()
	if _tentacle_retract_audio:
		_tentacle_retract_audio.stop()
	
	if is_instance_valid(_tentacle_node):
		_tentacle_node.queue_free()
		_tentacle_node = null
	if is_instance_valid(_tentacle_body):
		_tentacle_body.queue_free()
		_tentacle_body = null
	_restore_camera_to_killer()
	
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


# ═══════════════ THE RAGE (INFORMATION TRAP) ═══════════════

func _place_rage_trap() -> void:
	"""Place a pulsing black/red trap at the killer's own position (ability_3 / R)."""
	if rage_on_cooldown:
		return
	if current_state == State.TENTACLE_SNATCH or current_state == State.HITTING:
		return
	if _rage_freeze_timer > 0.0:
		return
	_rage_traps = _rage_traps.filter(func(t): return is_instance_valid(t))
	if _rage_traps.size() >= rage_max_traps:
		return
	rage_on_cooldown = true
	rage_cooldown_timer = rage_cooldown

	var trap := Node2D.new()
	trap.name = "RageTrap"
	trap.global_position = global_position
	trap.z_index = 150
	trap.set_meta("born", _rage_elapsed)
	# Outer red ring (pulses brighter)
	var ring := _make_circle_polygon(rage_trap_radius, Color(0.9, 0.05, 0.05, 0.8))
	ring.name = "Ring"
	trap.add_child(ring)
	# Dark inner circle (black core)
	var inner := _make_circle_polygon(rage_trap_radius * 0.7, Color(0.06, 0.02, 0.02, 0.9))
	inner.name = "Inner"
	trap.add_child(inner)
	# Detection area
	var area := Area2D.new()
	area.name = "TrapArea"
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = rage_trap_radius
	col.shape = shape
	area.add_child(col)
	area.collision_layer = 0
	area.collision_mask = 1  # Detect survivors
	area.body_entered.connect(_on_rage_triggered.bind(trap))
	trap.add_child(area)
	# Add to the map so it stays put when the killer walks away
	get_parent().add_child(trap)
	_rage_traps.append(trap)
	_rage_freeze_timer = RAGE_FREEZE_DURATION
	print("TestKiller: The Rage trap placed at ", global_position, " (", _rage_traps.size(), "/", rage_max_traps, ")")


func _on_rage_triggered(body: Node2D, trap: Node2D) -> void:
	"""A survivor stepped on a trap - it vanishes and the survivor is revealed.
	An already-infected survivor does NOT trigger the trap, and it stays put."""
	if not is_instance_valid(body) or not body.has_method("take_damage"):
		return
	# An infected survivor walking over the trap triggers nothing and the trap stays.
	if body.get("red_sickness") == true:
		return
	# Trap disappears
	if is_instance_valid(trap):
		trap.queue_free()
		_rage_traps = _rage_traps.filter(func(t): return t != trap and is_instance_valid(t))
	_reveal_survivor(body)
	if body.has_method("inflict_red_sickness"):
		body.inflict_red_sickness()


func _reveal_survivor(body: Node2D) -> void:
	"""Reveal a survivor's location to the killer for rage_reveal_duration seconds."""
	_revealed_survivor = body
	_reveal_timer = rage_reveal_duration
	if is_instance_valid(_reveal_marker):
		_reveal_marker.queue_free()
	var marker := Node2D.new()
	marker.name = "RageRevealMarker"
	var lbl := Label.new()
	lbl.text = "!"
	lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.position = Vector2(-10, -44)
	marker.add_child(lbl)
	body.add_child(marker)
	_reveal_marker = marker
	SubtleMotion.attach(marker, SubtleMotion.Mode.PULSE, 0.06, 2.0)
	rage_triggered.emit(body)
	print("TestKiller: SURVIVOR REVEALED at ", body.global_position, " for ", rage_reveal_duration, "s")


func reveal_survivor_to_killer(survivor: Node2D) -> void:
	"""Public API: reveal a survivor to this killer (used by cure/fail events)."""
	if is_instance_valid(survivor):
		_reveal_survivor(survivor)


func _update_rage(delta: float) -> void:
	"""Animate trap pulses and track the survivor reveal timer."""
	_rage_elapsed += delta
	for trap: Node2D in _rage_traps:
		if not is_instance_valid(trap):
			continue
		var born: float = trap.get_meta("born", 0.0)
		var t: float = _rage_elapsed - born
		var pulse: float = (sin(t * 3.0) + 1.0) / 2.0  # 0..1
		trap.scale = Vector2(1.0 + 0.12 * sin(t * 4.0), 1.0 + 0.12 * sin(t * 4.0))
		var ring: Polygon2D = trap.get_node_or_null("Ring") as Polygon2D
		if ring:
			# Red grows more prominent as it pulses
			ring.color = Color(0.9, 0.05 * (1.0 - pulse), 0.05 * (1.0 - pulse), 0.6 + 0.4 * pulse)
		var inner: Polygon2D = trap.get_node_or_null("Inner") as Polygon2D
		if inner:
			inner.color = Color(0.06, 0.02, 0.02, 0.85 + 0.1 * pulse)
	# Survivor reveal expiry
	if is_instance_valid(_revealed_survivor):
		_reveal_timer -= delta
		if _reveal_timer <= 0.0:
			if is_instance_valid(_reveal_marker):
				_reveal_marker.queue_free()
			_reveal_marker = null
			_revealed_survivor = null


# ═══════════════ BETTER SIGHT (TRACKING / CHASE) ═══════════════

func _activate_better_sight() -> void:
	"""Identify the nearest survivor and gain a speed boost until reaching them."""
	if better_sight_on_cooldown:
		return
	if current_state == State.TENTACLE_SNATCH or current_state == State.HITTING:
		return
	if _rage_freeze_timer > 0.0:
		return
	var target: Node2D = _find_nearest_survivor()
	if not is_instance_valid(target):
		print("TestKiller: Better Sight — no survivor to track")
		return
	better_sight_on_cooldown = true
	better_sight_cooldown_timer = better_sight_cooldown
	_better_sight_active = true
	_better_sight_target = target
	_show_better_sight_marker(target)
	better_sight_triggered.emit(target)
	print("TestKiller: Better Sight LOCKED ON ", target.name, " at ", target.global_position, " — speed x", better_sight_speed_mult)


func _nearest_survivor_distance() -> float:
	"""Smallest distance to any living survivor (player or bot); INF if none."""
	var best: float = INF
	for group_name in ["survivors", "survivor_bots"]:
		for s in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(s) or not s.has_method("take_damage"):
				continue
			if s.get("current_hp") != null and float(s.get("current_hp")) <= 0.0:
				continue
			var d: float = global_position.distance_to(s.global_position)
			if d < best:
				best = d
	return best


func _find_nearest_survivor() -> Node2D:
	"""Return the closest living survivor (player or bot)."""
	var best: Node2D = null
	var best_dist: float = INF
	for group_name in ["survivors", "survivor_bots"]:
		for s in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(s) or not s.has_method("take_damage"):
				continue
			if s.get("current_hp") != null and float(s.get("current_hp")) <= 0.0:
				continue
			var d: float = global_position.distance_to(s.global_position)
			if d < best_dist:
				best_dist = d
				best = s as Node2D
	return best


func _update_better_sight(_delta: float) -> void:
	"""The speed boost is NOT timed — it ends the moment the killer reaches the target."""
	if not _better_sight_active:
		return
	var target: Node2D = _better_sight_target
	if not is_instance_valid(target):
		_end_better_sight()
		return
	if target.get("current_hp") != null and float(target.get("current_hp")) <= 0.0:
		_end_better_sight()
		return
	# Keep the on-screen arrow pointed at the tracked survivor.
	_update_better_sight_arrow(target)
	var dist: float = global_position.distance_to(target.global_position)
	if dist <= better_sight_reach_distance:
		print("TestKiller: Better Sight reached ", target.name, " — speed boost ended")
		_end_better_sight()


func _end_better_sight() -> void:
	_better_sight_active = false
	_better_sight_target = null
	if is_instance_valid(_better_sight_marker):
		_better_sight_marker.queue_free()
	_better_sight_marker = null


func _show_better_sight_marker(target: Node2D) -> void:
	"""Put an arrow over the killer's head that points toward the tracked survivor."""
	if is_instance_valid(_better_sight_marker):
		_better_sight_marker.queue_free()
	var marker := Node2D.new()
	marker.name = "BetterSightMarker"
	var arrow := _make_arrow_polygon(Color(1.0, 0.85, 0.2, 1.0))
	arrow.name = "Arrow"
	marker.add_child(arrow)
	marker.position = Vector2.ZERO
	marker.z_index = 200
	add_child(marker)
	_better_sight_marker = marker
	_update_better_sight_arrow(target)


func _update_better_sight_arrow(target: Node2D) -> void:
	"""Orbit the arrow around the killer on the side facing the tracked survivor."""
	if not is_instance_valid(_better_sight_marker) or not is_instance_valid(target):
		return
	var dir: Vector2 = target.global_position - global_position
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	_better_sight_marker.position = dir * better_sight_arrow_radius
	_better_sight_marker.rotation = dir.angle()

func _make_circle_polygon(radius: float, color: Color, points: int = 32) -> Polygon2D:
	"""Build a filled-circle Polygon2D for the Rage trap visual."""
	var p := Polygon2D.new()
	p.color = color
	var pts := PackedVector2Array()
	for i: int in points:
		var a: float = TAU * float(i) / float(points)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	p.polygon = pts
	return p


func _make_arrow_polygon(color: Color) -> Polygon2D:
	"""Build a triangle arrow Polygon2D pointing along +X (rotated toward the target)."""
	var p := Polygon2D.new()
	p.color = color
	p.polygon = PackedVector2Array([
		Vector2(0, 0),
		Vector2(-22, -13),
		Vector2(-22, 13),
	])
	return p


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
