class_name KillerBot
extends CharacterBody2D

## AI-controlled killer bot that moves toward survivors and hits with rapid M1s.
## Uses Violentgrass's visual appearance and animations.

const VIOLENTGRASS_SCENE: PackedScene = preload("res://scenes/violentgrass.tscn")

# Ability params
@export var move_speed: float = 240.0
@export var hit_damage: float = 25.0
@export var hit_range: float = 80.0
@export var hit_cooldown: float = 0.5

enum Direction { DOWN, LEFT, RIGHT, UP }

var _hit_cd_timer: float = 0.0
var _hit_on_cooldown: bool = false
var _stun_timer: float = 0.0
var _current_direction: Direction = Direction.DOWN
var _target: Node2D = null

var visual_sprite: AnimatedSprite2D = null
var vfx_sprite: AnimatedSprite2D = null


func _ready() -> void:
	# Instantiate Violentgrass scene as visual child (before any @onready that reference it)
	var vg: Node2D = VIOLENTGRASS_SCENE.instantiate()
	vg.name = "Visual"
	vg.set_process(false)
	vg.set_physics_process(false)
	vg.set_process_input(false)
	add_child(vg)
	
	# Set references (can't use @onready since Visual child is created here)
	visual_sprite = $Visual/AnimatedSprite2D
	vfx_sprite = $Visual/VFXLayer/AbilityVFX
	
	# Use Violentgrass scene's own CollisionShape2D (removes our duplicate)
	# Resize it slightly for the bot's bigger hitbox
	var vg_col := $Visual/CollisionShape2D as CollisionShape2D
	if is_instance_valid(vg_col) and vg_col.shape is RectangleShape2D:
		vg_col.shape.size = Vector2(32, 32)
	
	# Stop VFX autoplay from scene file
	if is_instance_valid(vfx_sprite) and vfx_sprite.sprite_frames:
		vfx_sprite.stop()
		vfx_sprite.visible = false
	
	# Show the killer on the map
	$Visual.visible = true
	
	add_to_group("killers")


func _physics_process(delta: float) -> void:
	if _stun_timer > 0.0:
		_stun_timer -= delta
		velocity = Vector2.ZERO
		_play_dir_anim("idle")
		move_and_slide()
		_update_cooldown(delta)
		return
	
	_find_nearest_survivor()
	
	if _target == null:
		velocity = Vector2.ZERO
		_play_dir_anim("idle")
		move_and_slide()
		_update_cooldown(delta)
		return
	
	var dir: Vector2 = _target.global_position - global_position
	var dist: float = dir.length()
	
	if dist > hit_range * 0.7:
		velocity = dir.normalized() * move_speed
		_update_direction(dir)
		_play_dir_anim("walk")
	else:
		velocity = Vector2.ZERO
		_play_dir_anim("idle")
		if not _hit_on_cooldown:
			_do_hit()
	
	move_and_slide()
	_update_cooldown(delta)


func _find_nearest_survivor() -> void:
	var survivors: Array[Node] = get_tree().get_nodes_in_group("survivors")
	_target = null
	var nearest_dist: float = INF
	for s in survivors:
		if is_instance_valid(s) and s != self:
			var dsq: float = global_position.distance_squared_to(s.global_position)
			if dsq < nearest_dist:
				nearest_dist = dsq
				_target = s


func _do_hit() -> void:
	_hit_on_cooldown = true
	_hit_cd_timer = hit_cooldown
	
	# Play VFX only if the visual parent is visible
	var visual_node: Node2D = $Visual if is_instance_valid($Visual) else null
	if is_instance_valid(vfx_sprite) and visual_node != null and visual_node.visible \
			and vfx_sprite.sprite_frames and vfx_sprite.sprite_frames.has_animation("hit_down"):
		vfx_sprite.visible = true
		vfx_sprite.play("hit_down")
	
	if not is_instance_valid(_target):
		return
	if global_position.distance_to(_target.global_position) > hit_range:
		return
	
	# Ping handler: only deal damage if we have line-of-sight
	if _has_line_of_sight(_target):
		_ping_hit(_target)
		if _target.has_method("take_damage"):
			_target.take_damage(hit_damage)


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


func take_stun(duration: float) -> void:
	if _stun_timer > 0.0:
		return
	_stun_timer = duration
	modulate = Color(0.5, 0.5, 0.5, 1.0)
	get_tree().create_timer(duration).timeout.connect(_end_stun)


func _end_stun() -> void:
	if not is_instance_valid(self):
		return
	modulate = Color.WHITE
	if _stun_timer <= 0.0:
		_stun_timer = 0.0
	if is_instance_valid(vfx_sprite):
		vfx_sprite.visible = false
		vfx_sprite.stop()


func _update_cooldown(delta: float) -> void:
	if _hit_on_cooldown:
		_hit_cd_timer -= delta
		if _hit_cd_timer <= 0.0:
			_hit_on_cooldown = false


func _play_dir_anim(anim: String) -> void:
	if not is_instance_valid(visual_sprite):
		return
	var dir_name: String = ["down", "left", "right", "up"][_current_direction as int]
	var full_anim: String = anim + "_" + dir_name
	if visual_sprite.sprite_frames.has_animation(full_anim):
		visual_sprite.play(full_anim)
	else:
		visual_sprite.play(anim)


func _update_direction(input_dir: Vector2) -> void:
	if abs(input_dir.x) > abs(input_dir.y):
		_current_direction = Direction.RIGHT if input_dir.x > 0 else Direction.LEFT
	else:
		_current_direction = Direction.DOWN if input_dir.y > 0 else Direction.UP
