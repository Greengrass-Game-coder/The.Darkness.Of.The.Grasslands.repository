class_name ThistleController
extends GreengrassController

## THISTLE — a phase/teleport survivor. Reuses the Greengrass sprite body and
## movement/physics, but has its OWN kit (no punch, no heal):
##   Q — Phase Dash:   blink a short distance toward the mouse/move direction.
##   E — Spectral Veil: turn semi-transparent + intangible for a moment.
##   R — Bloom Burst:  a small pulse that stuns nearby killers to break a chase.
##
## The HUD reads the base controller's block/punch/flower cooldown vars, so
## Thistle reuses those three cooldown slots for its own abilities and the
## ability icons/countdowns work with zero extra HUD changes.

@export var dash_distance: float = 180.0
@export var dash_speed: float = 720.0
@export var dash_cooldown: float = 6.0
@export var veil_duration: float = 2.5
@export var veil_cooldown: float = 12.0
@export var bloom_range: float = 170.0
@export var bloom_stun: float = 1.5
@export var bloom_cooldown: float = 18.0

var _dash_timer: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
var _veil_active: bool = false
var _veil_timer: float = 0.0
var _bloom_flash: float = 0.0
var _ability_anim_name: String = ""
var _ability_anim_timer: float = 0.0


func _physics_process(delta: float) -> void:
	# Dead — no movement, no abilities.
	if current_hp <= 0.0:
		return

	# Phase Dash: take over movement while the dash is running.
	if _dash_timer > 0.0:
		_dash_timer -= delta
		velocity = _dash_dir * dash_speed
		move_and_slide()
		if _dash_timer <= 0.0:
			velocity = Vector2.ZERO
			_change_state(State.IDLE)
			modulate = Color.WHITE
		return

	# Spectral Veil: tick the timed veil and auto-end it if held too long.
	if _veil_timer > 0.0:
		_veil_timer -= delta
		if _veil_timer <= 0.0:
			_end_veil()

	# Fade the Bloom Burst ring out.
	if _bloom_flash > 0.0:
		_bloom_flash -= delta
		if _bloom_flash <= 0.0:
			_bloom_flash = 0.0
			modulate = Color.WHITE
		queue_redraw()

	# Ability animation window: keep the ability anim showing for its brief
	# span, then hand back to the normal idle/walk cycle. We do NOT re-call
	# _play_character_ability here — it resets _ability_anim_timer, which
	# would lock the window open forever (character stuck + cooldowns frozen).
	if _ability_anim_timer > 0.0:
		_ability_anim_timer -= delta
		if _ability_anim_timer <= 0.0:
			_ability_anim_name = ""
			_play_animation("idle")
		return

	super._physics_process(delta)


# ---------- Q — PHASE DASH ----------

func use_block() -> void:
	"""Phase Dash: blink a short distance toward the mouse (or facing dir)."""
	if current_state != State.IDLE and current_state != State.WALKING:
		return
	if block_on_cooldown:
		return
	var to_mouse: Vector2 = get_global_mouse_position() - global_position
	var dir: Vector2 = to_mouse.normalized()
	if to_mouse.length() < 8.0:
		dir = _facing_dir()
	_dash_dir = dir
	_dash_timer = dash_distance / dash_speed
	block_on_cooldown = true
	_block_cd_timer = dash_cooldown
	_change_state(State.DASH_BLOCKING)
	# Quick translucent "phase" flash while blinking.
	modulate = Color(0.75, 0.95, 1.0, 0.65)
	_play_character_ability("dash")


# ---------- E — SPECTRAL VEIL (hold) ----------

func _start_charge_punch() -> void:
	"""Begin Spectral Veil on E press."""
	if current_state != State.IDLE and current_state != State.WALKING:
		return
	if punch_on_cooldown:
		return
	_charging = true
	_veil_active = true
	_veil_timer = veil_duration
	modulate = Color(0.6, 0.9, 1.0, 0.35)
	_change_state(State.IDLE)
	_play_character_ability("veil")


func _fire_charged_punch() -> void:
	"""E release: start the cooldown, but let the veil run its full duration
	(auto-ended by the timer) instead of cutting it off on release."""
	if not _charging:
		return
	_charging = false
	punch_on_cooldown = true
	_punch_cd_timer = veil_cooldown


func _end_veil() -> void:
	_veil_active = false
	_veil_timer = 0.0
	modulate = Color.WHITE
	_hide_vfx()


func take_damage(amount: float) -> void:
	"""While veiled, Thistle is intangible and takes no damage."""
	if _veil_active:
		return
	super.take_damage(amount)


# ---------- R — BLOOM BURST ----------

func use_spare_flower() -> void:
	"""Bloom Burst: stun nearby killers to break a chase."""
	if current_state != State.IDLE and current_state != State.WALKING:
		return
	if flower_on_cooldown:
		return
	flower_on_cooldown = true
	_flower_cd_timer = bloom_cooldown
	# Character blooms outward for the burst.
	_bloom_flash = 0.3
	modulate = Color(1.0, 0.9, 0.6, 0.8)
	_play_character_ability("bloom")
	# Stun every killer within range (breaks the chase).
	for k in get_tree().get_nodes_in_group("killers"):
		if is_instance_valid(k) and k != self:
			if global_position.distance_to(k.global_position) <= bloom_range:
				if k.has_method("take_stun"):
					k.take_stun(bloom_stun)


# ---------- VISUAL HELPER ----------

func _play_character_ability(anim: String) -> void:
	"""Play one of Thistle's directional ability animations on the character's
	own AnimatedSprite2D (e.g. 'dash_down'), instead of a VFX overlay. The
	animation auto-returns to idle on completion (non-looping)."""
	var dir_name: String = ["down", "left", "right", "up"][int(current_direction)]
	var full: String = anim + "_" + dir_name
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(full):
		# Hide the (unused) VFX overlay so only the character anim shows.
		ability_vfx.visible = false
		ability_vfx.stop()
		animated_sprite.visible = true
		animated_sprite.play(full)
		# Keep the ability anim playing for a short window before resuming
		# idle/walk. Dash has its own movement timer (early-returns), so only
		# veil/bloom rely on this window.
		if anim != "dash":
			_ability_anim_name = anim
			# Match the 4-frame @8.0 ability anim length (0.5s) so it plays out.
			_ability_anim_timer = 0.5


func _draw() -> void:
	# Small expanding ring for the Bloom Burst (super's _draw draws the aim
	# arrow only while charging, which Thistle never does — so this is safe).
	if _bloom_flash > 0.0:
		var radius: float = bloom_range * (1.0 - _bloom_flash / 0.3)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(1.0, 0.85, 0.5, _bloom_flash), 3.0)
	super._draw()
