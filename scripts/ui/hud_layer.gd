class_name HudLayer
extends CanvasLayer
## Professional HUD layer — manages health bar, stamina bar, ability icons,
## epilepsy overlay, ending vignette, death overlay, teleport indicator,
## timer display, and damage VFX (screen shake + vignette).
##
## Extracted from game_map.gd to keep GameMap focused on game logic.

signal hud_ready

# ── Health Bar ──
@export var health_bar_pos: Vector2 = Vector2(440, 555)
@export var health_bar_size: Vector2 = Vector2(400, 30)

# ── Stamina Bar ──
@export var stamina_bar_pos: Vector2 = Vector2(440, 590)
@export var stamina_bar_size: Vector2 = Vector2(400, 36)

# ── Ability Icons ──
@export var ability_icons_pos: Vector2 = Vector2(490, 652)
@export var ability_slot_start_x: float = 52.0
@export var ability_slot_spacing: float = 66.0

# ── Internal references ──
var _player: Node2D = null
var _character_name: String = "Greengrass"
var _last_hp: float = -1.0

# Health bar components
var _hp_fill: ColorRect = null
var _hp_label: Label = null

# Stamina bar components
var _stamina_fill: ColorRect = null

# Ability icon containers
var _ability_container: Control = null

# Epilepsy / Vignette
var _epilepsy_overlay: ColorRect = null
var _vignette_overlay: ColorRect = null

# Ending vignette
var _ending_vignette: ColorRect = null
var _ending_start_time: float = 0.0

# Death overlay
var _death_overlay: ColorRect = null
var _death_active: bool = false
var _death_fade_progress: float = 0.0

# Timer
var _timer_label: Label = null
var _bitmap_timer: BitmapLabel = null
var _timer_flash_red: float = 0.0

# Teleport indicator
var _teleport_indicator: Label = null
var _teleport_ring: ColorRect = null

# Damage tracking
var _last_damage_time: float = -10.0


func _ready() -> void:
	hud_ready.emit()


# ═══════════════ INITIALIZATION ═══════════════

func initialize(player: Node2D, character_name: String) -> void:
	"""Called by GameMap to set up all HUD elements for the current player."""
	_player = player
	_character_name = character_name
	
	_create_health_bar()
	_create_stamina_bar()
	_create_ability_icons()
	_create_epilepsy_overlay()
	_create_ending_vignette()
	_replace_timer_label()
	_connect_ability_signals()
	_apply_epilepsy_mode()


# ═══════════════ HEALTH BAR ═══════════════

func _create_health_bar() -> void:
	var container := Control.new()
	container.name = "HealthBar"
	container.position = health_bar_pos
	container.size = health_bar_size
	add_child(container)

	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.size = Vector2(404, 32)
	bg.position = Vector2(-2, -2)
	bg.color = Color(0.4, 0.4, 0.4, 0.6)
	container.add_child(bg)

	_hp_fill = ColorRect.new()
	_hp_fill.name = "Fill"
	_hp_fill.size = Vector2(400, 28)
	_hp_fill.color = Color(0.15, 0.9, 0.15, 0.9)
	container.add_child(_hp_fill)

	_hp_label = Label.new()
	_hp_label.name = "Label"
	_hp_label.text = "100 / 100"
	_hp_label.position = Vector2(0, 4)
	_hp_label.size = Vector2(400, 24)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_hp_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_hp_label.add_theme_constant_override("shadow_offset_x", 1)
	_hp_label.add_theme_constant_override("shadow_offset_y", 1)
	_hp_label.add_theme_font_size_override("font_size", 18)
	container.add_child(_hp_label)

	if _player and _player.has_signal("hp_changed"):
		_player.hp_changed.connect(_on_hp_changed)


func set_health(current_hp: float, max_hp: float) -> void:
	"""Update health bar display."""
	var ratio: float = current_hp / max_hp if max_hp > 0 else 0.0
	if is_instance_valid(_hp_fill):
		_hp_fill.size.x = 400.0 * clampf(ratio, 0.0, 1.0)
	if is_instance_valid(_hp_label):
		_hp_label.text = "%d / %d" % [current_hp, max_hp]

	if ratio < 0.3:
		if is_instance_valid(_hp_fill):
			_hp_fill.color = Color(0.9, 0.15, 0.15, 0.9)
	elif ratio < 0.6:
		if is_instance_valid(_hp_fill):
			_hp_fill.color = Color(0.9, 0.7, 0.1, 0.9)
	else:
		if is_instance_valid(_hp_fill):
			_hp_fill.color = Color(0.15, 0.9, 0.15, 0.9)


func _on_hp_changed(current_hp: float, max_hp: float) -> void:
	"""Handle hp_changed signal directly for damage VFX."""
	if _last_hp >= 0 and current_hp < _last_hp:
		var dmg: float = _last_hp - current_hp
		_trigger_screen_shake(clampf(dmg * 0.2, 2.0, 8.0), 0.25)
		_trigger_vignette()
		_last_damage_time = Time.get_ticks_msec() / 1000.0
	set_health(current_hp, max_hp)
	_last_hp = current_hp


# ═══════════════ STAMINA BAR ═══════════════

func _create_stamina_bar() -> void:
	var container := Control.new()
	container.name = "StaminaBar"
	container.position = stamina_bar_pos
	container.size = stamina_bar_size
	add_child(container)

	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.size = Vector2(400, 14)
	bg.color = Color(0.15, 0.15, 0.15, 0.8)
	container.add_child(bg)

	_stamina_fill = ColorRect.new()
	_stamina_fill.name = "Fill"
	_stamina_fill.size = Vector2(400, 14)
	_stamina_fill.color = Color(0.2, 0.8, 0.2, 0.9)
	container.add_child(_stamina_fill)

	var label := Label.new()
	label.name = "Label"
	label.text = "SPRINT LIMIT"
	label.position = Vector2(0, 16)
	label.size = Vector2(400, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 10)
	container.add_child(label)

	if _player and _player.has_signal("stamina_changed"):
		_player.stamina_changed.connect(_on_stamina_changed)


func _on_stamina_changed(current: float, max_stamina: float) -> void:
	if not is_instance_valid(_stamina_fill):
		return
	var ratio: float = current / max_stamina if max_stamina > 0 else 0.0
	_stamina_fill.size.x = 400.0 * clampf(ratio, 0.0, 1.0)
	_stamina_fill.color.a = 0.5 if ratio < 0.2 else 0.9


# ═══════════════ ABILITY ICONS ═══════════════

func _create_ability_icons() -> void:
	_ability_container = Control.new()
	_ability_container.name = "AbilityIcons"
	_ability_container.position = ability_icons_pos
	_ability_container.size = Vector2(300, 60)
	add_child(_ability_container)

	var is_killer: bool = _character_name == "Violentgrass"
	var abilities: Array[Dictionary] = []
	if is_killer:
		abilities = [
			{"icon": "res://assets/generated/icon_ability_hit.png", "key": "Q", "cooldown_var": "hit_on_cooldown"},
			{"icon": "res://assets/generated/icon_ability_teleport.png", "key": "E", "cooldown_var": "teleport_on_cooldown"},
		]
	else:
		abilities = [
			{"icon": "res://assets/generated/icon_ability_block.png", "key": "Q", "cooldown_var": "block_on_cooldown"},
			{"icon": "res://assets/generated/icon_ability_grass_punch.png", "key": "E", "cooldown_var": "punch_on_cooldown"},
			{"icon": "res://assets/generated/icon_ability_spare_flower.png", "key": "R", "cooldown_var": "flower_on_cooldown"},
		]

	for i: int in range(abilities.size()):
		var data: Dictionary = abilities[i]
		var slot := Control.new()
		slot.name = "Ability%d" % i
		slot.position = Vector2(ability_slot_start_x + i * ability_slot_spacing, 0)
		slot.size = Vector2(56, 56)
		_ability_container.add_child(slot)

		# Icon
		var icon := TextureRect.new()
		icon.name = "Icon"
		if ResourceLoader.exists(data["icon"]):
			icon.texture = load(data["icon"])
		icon.size = Vector2(56, 56)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.add_child(icon)

		# Lock overlay for Grass Punch
		if i == 1 and not is_killer:
			var lock_overlay := ColorRect.new()
			lock_overlay.name = "LockOverlay"
			lock_overlay.size = Vector2(56, 56)
			lock_overlay.color = Color(0.3, 0.3, 0.3, 0.7)
			lock_overlay.visible = true
			slot.add_child(lock_overlay)

		# Key label
		var key_label := Label.new()
		key_label.name = "KeyLabel"
		key_label.text = data["key"]
		key_label.position = Vector2(2, 36)
		key_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		key_label.add_theme_constant_override("shadow_offset_x", 1)
		key_label.add_theme_constant_override("shadow_offset_y", 1)
		slot.add_child(key_label)

		# Cooldown overlay
		var cd_overlay := ColorRect.new()
		cd_overlay.name = "CooldownOverlay"
		cd_overlay.size = Vector2(56, 56)
		cd_overlay.color = Color(0.0, 0.0, 0.0, 0.6)
		cd_overlay.visible = false
		slot.add_child(cd_overlay)

		var cd_label := Label.new()
		cd_label.name = "CooldownLabel"
		cd_label.size = Vector2(56, 56)
		cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		cd_label.add_theme_font_size_override("font_size", 20)
		cd_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		cd_label.add_theme_constant_override("shadow_offset_x", 1)
		cd_label.add_theme_constant_override("shadow_offset_y", 1)
		cd_overlay.add_child(cd_label)

		slot.set_meta("cooldown_var", data["cooldown_var"])


func _connect_ability_signals() -> void:
	if not is_instance_valid(_player):
		return
	if _player.has_signal("block_unlocked_punch") and not _player.block_unlocked_punch.is_connected(_on_punch_unlocked):
		_player.block_unlocked_punch.connect(_on_punch_unlocked)
	if _player.has_signal("punch_locked_changed") and not _player.punch_locked_changed.is_connected(_on_punch_locked_changed):
		_player.punch_locked_changed.connect(_on_punch_locked_changed)


func _on_punch_unlocked() -> void:
	if not _ability_container:
		return
	var punch_slot: Node = _ability_container.get_child(1) if _ability_container.get_child_count() > 1 else null
	if not punch_slot:
		return
	var icon: TextureRect = punch_slot.get_node_or_null("Icon")
	if not icon:
		return
	var orig_mod: Color = icon.modulate
	icon.modulate = Color(3.0, 3.0, 0.2, 1.0)
	var tween: Tween = create_tween()
	tween.tween_property(icon, "modulate", orig_mod, 0.5).set_ease(Tween.EASE_OUT)


func _on_punch_locked_changed(locked: bool) -> void:
	if not _ability_container:
		return
	var punch_slot: Node = _ability_container.get_child(1) if _ability_container.get_child_count() > 1 else null
	if not punch_slot:
		return
	var lock_overlay: ColorRect = punch_slot.get_node_or_null("LockOverlay")
	if lock_overlay:
		lock_overlay.visible = locked


func update_ability_cooldowns() -> void:
	"""Update cooldown overlays with countdown numbers."""
	if not is_instance_valid(_ability_container) or not is_instance_valid(_player):
		return

	var is_killer: bool = _character_name == "Violentgrass"
	var data_list: Array[Dictionary] = _get_ability_data(is_killer)

	for i: int in range(_ability_container.get_child_count()):
		if i >= data_list.size():
			continue
		var slot: Node = _ability_container.get_child(i)
		var cooldown_var: String = data_list[i]["cooldown_var"]
		var overlay: ColorRect = slot.get_node_or_null("CooldownOverlay")
		if not overlay:
			continue

		var is_on_cd: bool = cooldown_var in _player and _player.get(cooldown_var)
		overlay.visible = is_on_cd

		if is_on_cd:
			var cd_label: Label = overlay.get_node_or_null("CooldownLabel")
			if cd_label:
				var timer_var: String = "_" + cooldown_var.trim_suffix("_on_cooldown") + "_cd_timer"
				if timer_var in _player:
					var remaining: float = _player.get(timer_var)
					cd_label.text = str(ceili(remaining))
				else:
					cd_label.text = ""
		else:
			var cd_label: Label = overlay.get_node_or_null("CooldownLabel")
			if cd_label:
				cd_label.text = ""


func _get_ability_data(is_killer: bool) -> Array[Dictionary]:
	if is_killer:
		return [
			{"icon": "", "key": "Q", "cooldown_var": "hit_on_cooldown"},
			{"icon": "", "key": "E", "cooldown_var": "teleport_on_cooldown"},
		]
	else:
		return [
			{"icon": "", "key": "Q", "cooldown_var": "block_on_cooldown"},
			{"icon": "", "key": "E", "cooldown_var": "punch_on_cooldown"},
			{"icon": "", "key": "R", "cooldown_var": "flower_on_cooldown"},
		]


# ═══════════════ EPILEPSY & VIGNETTE ═══════════════

func _create_epilepsy_overlay() -> void:
	_epilepsy_overlay = ColorRect.new()
	_epilepsy_overlay.name = "EpilepsyOverlay"
	_epilepsy_overlay.position = Vector2.ZERO
	_epilepsy_overlay.size = Vector2(1280, 720)
	_epilepsy_overlay.color = Color(0.5, 0.5, 0.5, 0.0)
	_epilepsy_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_epilepsy_overlay)

	_vignette_overlay = ColorRect.new()
	_vignette_overlay.name = "Vignette"
	_vignette_overlay.position = Vector2.ZERO
	_vignette_overlay.size = Vector2(1280, 720)
	_vignette_overlay.color = Color(0, 0, 0, 0.0)
	_vignette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette_overlay)


func _apply_epilepsy_mode() -> void:
	var gs = get_node_or_null("/root/GameState")
	var enabled: bool = gs != null and "epilepsy_safe_mode" in gs and gs.epilepsy_safe_mode
	if is_instance_valid(_epilepsy_overlay):
		_epilepsy_overlay.color = Color(0.5, 0.5, 0.5, 0.2) if enabled else Color(0.5, 0.5, 0.5, 0.0)


func _trigger_vignette() -> void:
	if not is_instance_valid(_vignette_overlay):
		return
	var enabled: bool = "epilepsy_safe_mode" in GameState and GameState.epilepsy_safe_mode
	var target_alpha: float = 0.25 if enabled else 0.4
	_vignette_overlay.color = Color(0, 0, 0, target_alpha)
	var tween := create_tween()
	tween.tween_property(_vignette_overlay, "color", Color(0, 0, 0, 0), 0.8).set_ease(Tween.EASE_OUT)


func _trigger_screen_shake(intensity: float = 5.0, duration: float = 0.2) -> void:
	if not is_instance_valid(_player):
		return
	var cam: Camera2D = _player.get_node_or_null("Camera2D")
	if not cam:
		return
	cam.set("_shake_elapsed", 0.0)
	cam.set("_shake_orig", cam.offset)
	var tween: Tween = create_tween()
	tween.tween_method(_apply_shake.bind(cam, intensity), 0.0, 1.0, duration).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_end_shake.bind(cam))


func _apply_shake(progress: float, cam: Camera2D, intensity: float) -> void:
	if not is_instance_valid(cam):
		return
	var orig: Vector2 = cam.get("_shake_orig") if cam.get("_shake_orig") != null else Vector2.ZERO
	var decay: float = 1.0 - progress
	cam.offset = orig + Vector2(
		randf_range(-intensity, intensity) * decay,
		randf_range(-intensity, intensity) * decay
	)


func _end_shake(cam: Camera2D) -> void:
	if is_instance_valid(cam):
		var orig: Vector2 = cam.get("_shake_orig") if cam.get("_shake_orig") != null else Vector2.ZERO
		cam.offset = orig


func check_epilepsy_updates() -> void:
	_apply_epilepsy_mode()


# ═══════════════ ENDING VIGNETTE ═══════════════

func _create_ending_vignette() -> void:
	_ending_vignette = ColorRect.new()
	_ending_vignette.name = "EndingVignette"
	_ending_vignette.position = Vector2.ZERO
	_ending_vignette.size = Vector2(1280, 720)
	_ending_vignette.color = Color(0.4, 0.0, 0.0, 0.0)
	_ending_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ending_vignette)


func update_ending_vignette(time_remaining: float, ending_start_time: float) -> void:
	_ending_start_time = ending_start_time
	if not is_instance_valid(_ending_vignette):
		return
	if time_remaining > 30.0:
		_ending_vignette.color = Color(0.4, 0.0, 0.0, 0.0)
		return

	var epilepsy_on: bool = "epilepsy_safe_mode" in GameState and GameState.epilepsy_safe_mode
	var seconds_left: int = int(time_remaining)
	var progress: float = 1.0 - (time_remaining / 30.0)

	if epilepsy_on:
		var alpha: float = clampf(progress * 0.75, 0.0, 0.75)
		_ending_vignette.color = Color(0.35, 0.0, 0.0, alpha)
	else:
		var color_index: int = clampi(int(seconds_left / 3.0), 0, 9)
		var colors: Array[Color] = [
			Color(1.0, 0.0, 0.0, 0.7), Color(1.0, 0.5, 0.0, 0.7),
			Color(1.0, 1.0, 0.0, 0.7), Color(0.5, 1.0, 0.0, 0.7),
			Color(0.0, 1.0, 0.5, 0.7), Color(0.0, 0.8, 1.0, 0.7),
			Color(0.0, 0.3, 1.0, 0.7), Color(0.5, 0.0, 1.0, 0.7),
			Color(1.0, 0.0, 1.0, 0.7), Color(1.0, 0.3, 0.6, 0.7),
		]
		var base: Color = colors[color_index]
		var pulse_speed: float = 4.0 + progress * 8.0
		var pulse: float = sin(_ending_start_time * pulse_speed) * 0.5 + 0.5
		_ending_vignette.color = Color(
			base.r * (0.7 + pulse * 0.3),
			base.g * (0.7 + pulse * 0.3),
			base.b * (0.7 + pulse * 0.3),
			clampf(0.5 + pulse * 0.4, 0.3, 0.85)
		)


# ═══════════════ DEATH OVERLAY ═══════════════

func start_death_sequence() -> void:
	if _death_active:
		return
	_death_active = true
	_death_fade_progress = 0.0

	if is_instance_valid(_player):
		_player.set_physics_process(false)
		_player.modulate = Color(0.6, 0.6, 0.6, 1.0)

	_death_overlay = ColorRect.new()
	_death_overlay.name = "DeathOverlay"
	_death_overlay.color = Color(0.15, 0.15, 0.15, 0.0)
	_death_overlay.size = get_viewport().get_visible_rect().size
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_death_overlay)


func update_death_fade(delta: float) -> bool:
	"""Returns true when death fade completes (match should end)."""
	if not _death_active:
		return false
	_death_fade_progress += delta / 5.0
	var alpha: float = clampf(_death_fade_progress, 0.0, 1.0)
	if is_instance_valid(_death_overlay):
		_death_overlay.color = Color(0.15, 0.15, 0.15, alpha * 0.85)
	if _death_fade_progress >= 1.0:
		_death_active = false
		if is_instance_valid(_death_overlay):
			_death_overlay.queue_free()
		return true
	return false


# ═══════════════ TIMER DISPLAY ═══════════════

func _replace_timer_label() -> void:
	"""Replace the default timer Label with a BitmapLabel."""
	var old_label: Label = get_node_or_null("TimerLabel")
	if not old_label:
		return
	_bitmap_timer = BitmapLabel.new()
	_bitmap_timer.name = "BmpTimer"
	_bitmap_timer.label_text = old_label.text
	_bitmap_timer.font_scale = 0.18
	_bitmap_timer.char_spacing = 3.0
	_bitmap_timer.horizontal_align = old_label.horizontal_alignment
	_bitmap_timer.font_color = Color(1, 1, 1, 1)
	_bitmap_timer.position = old_label.position
	_bitmap_timer.size = old_label.size
	old_label.visible = false
	add_child(_bitmap_timer)


func set_timer_text(txt: String) -> void:
	var old_label: Label = get_node_or_null("TimerLabel")
	if old_label:
		old_label.text = txt
	if is_instance_valid(_bitmap_timer):
		_bitmap_timer.label_text = txt


func flash_timer_red(alpha: float) -> void:
	var old_label: Label = get_node_or_null("TimerLabel")
	if old_label:
		old_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, alpha))
	if is_instance_valid(_bitmap_timer):
		_bitmap_timer.font_color = Color(1.0, 0.2, 0.2, alpha)


func reset_timer_color() -> void:
	var old_label: Label = get_node_or_null("TimerLabel")
	if old_label:
		old_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	if is_instance_valid(_bitmap_timer):
		_bitmap_timer.font_color = Color(1, 1, 1, 1)


# ═══════════════ TELEPORT INDICATOR ═══════════════

func show_teleport_indicator(teleport_pos: Vector2, player_pos: Vector2) -> void:
	"""Show a directional arrow pointing toward the teleport location."""
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var dir: Vector2 = (teleport_pos - player_pos).normalized()
	var angle: float = atan2(dir.y, dir.x)

	_teleport_indicator = Label.new()
	_teleport_indicator.name = "TeleportIndicator"
	_teleport_indicator.text = "▶"
	_teleport_indicator.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 0.95))
	_teleport_indicator.add_theme_font_size_override("font_size", 32)
	_teleport_indicator.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_teleport_indicator.add_theme_constant_override("outline_size", 3)
	_teleport_indicator.size = Vector2(40, 40)
	_teleport_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_teleport_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_teleport_indicator.pivot_offset = Vector2(20, 20)
	_teleport_indicator.rotation = angle

	var margin: float = 40.0
	var edge_x: float = viewport_size.x * 0.5 + dir.x * (viewport_size.x * 0.5 - margin)
	var edge_y: float = viewport_size.y * 0.5 + dir.y * (viewport_size.y * 0.5 - margin)
	_teleport_indicator.position = Vector2(
		clamp(edge_x, margin, viewport_size.x - margin) - 20,
		clamp(edge_y, margin, viewport_size.y - margin) - 20
	)
	add_child(_teleport_indicator)

	_teleport_ring = ColorRect.new()
	_teleport_ring.name = "TeleportIndicatorRing"
	_teleport_ring.size = Vector2(6, 6)
	_teleport_ring.position = _teleport_indicator.position + Vector2(17, 17)
	_teleport_ring.color = Color(1, 0.2, 0.2, 0.6)
	add_child(_teleport_ring)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_teleport_ring, "size", Vector2(20, 20), 0.5)
	tween.tween_property(_teleport_ring, "modulate:a", 0.0, 0.5)
	tween.tween_property(_teleport_indicator, "modulate:a", 0.0, 0.5).set_delay(2.5)

	get_tree().create_timer(3.0).timeout.connect(_clear_teleport_indicator)


func _clear_teleport_indicator() -> void:
	if is_instance_valid(_teleport_indicator):
		_teleport_indicator.queue_free()
	if is_instance_valid(_teleport_ring):
		_teleport_ring.queue_free()
	_teleport_indicator = null
	_teleport_ring = null
