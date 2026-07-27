class_name KillerIntro
extends CanvasLayer

## Reusable killer intro cinematic.
## Shows killer name + optional art, plays briefly, then fades out.
## Works for ANY killer character — just pass the name and optional texture.

signal intro_finished()

@export var display_duration: float = 3.0
@export var fade_in_duration: float = 0.5
@export var fade_out_duration: float = 0.8

var _tween: Tween = null
var _fade_overlay: ColorRect = null


func play_intro(killer_name: String, texture: Texture2D = null) -> void:
	"""Play the killer intro cinematic."""
	_build_intro(killer_name, texture)
	
	show()
	
	# Fade overlay starts transparent, we fade it in
	_fade_overlay.modulate = Color(1, 1, 1, 0)
	
	# Animate: fade in → hold → fade out → emit finished
	var tween: Tween = create_tween()
	tween.set_parallel(false)
	
	# Fade in
	tween.tween_property(_fade_overlay, "modulate", Color(1, 1, 1, 1), fade_in_duration)
	
	# Hold
	tween.tween_interval(display_duration - fade_in_duration - fade_out_duration)
	
	# Fade out
	tween.tween_property(_fade_overlay, "modulate", Color(1, 1, 1, 0), fade_out_duration)
	
	# Done
	_tween = tween
	tween.finished.connect(_on_intro_done)


func _build_intro(killer_name: String, texture: Texture2D) -> void:
	"""Build the intro UI elements."""
	# Clear any existing children
	for child: Node in get_children():
		child.queue_free()
	
	# Full-screen container (Control — supports modulate)
	var container := Control.new()
	container.name = "IntroContainer"
	container.anchors_preset = Control.PRESET_FULL_RECT
	add_child(container)
	
	# Full-screen black background
	var bg := ColorRect.new()
	bg.name = "IntroBg"
	bg.color = Color(0, 0, 0, 1)
	bg.anchors_preset = Control.PRESET_FULL_RECT
	container.add_child(bg)
	
	# Killer art (if provided)
	if texture:
		var art := TextureRect.new()
		art.name = "KillerArt"
		art.texture = texture
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.anchors_preset = Control.PRESET_CENTER
		art.size = Vector2(300, 300)
		art.position = Vector2(-150, -120)
		container.add_child(art)
	
	# Killer name
	var name_label := Label.new()
	name_label.name = "KillerName"
	name_label.text = killer_name
	name_label.anchors_preset = Control.PRESET_CENTER
	name_label.size = Vector2(600, 60)
	name_label.position = Vector2(-300, 80)
	name_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 1))
	name_label.add_theme_font_size_override("font_size", 42)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	name_label.add_theme_constant_override("shadow_offset_x", 3)
	name_label.add_theme_constant_override("shadow_offset_y", 3)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_outline_color", Color(0.3, 0, 0, 1))
	name_label.add_theme_constant_override("outline_size", 4)
	container.add_child(name_label)
	
	# Subtitle
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "is hunting..."
	subtitle.anchors_preset = Control.PRESET_CENTER
	subtitle.size = Vector2(400, 30)
	subtitle.position = Vector2(-200, 130)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	subtitle.add_theme_constant_override("shadow_offset_x", 2)
	subtitle.add_theme_constant_override("shadow_offset_y", 2)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(subtitle)
	
	# Fade overlay — added LAST so it renders ON TOP of all content
	_fade_overlay = ColorRect.new()
	_fade_overlay.name = "FadeOverlay"
	_fade_overlay.color = Color(0, 0, 0, 1)
	_fade_overlay.anchors_preset = Control.PRESET_FULL_RECT
	container.add_child(_fade_overlay)


func _on_intro_done() -> void:
	"""Called when the intro sequence finishes."""
	intro_finished.emit()
	queue_free()
