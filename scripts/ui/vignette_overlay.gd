class_name VignetteOverlay
extends ColorRect

## Circular HUD vignette: a filled circle faded in the middle so the player can
## always see the map / camera clearly at screen center. Stays on through LMS.

const SHADER_PATH := "res://assets/shaders/circular_vignette.gdshader"

var _shader_mat: ShaderMaterial


func _ready() -> void:
	# Cover the whole screen.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100

	var shader: Shader = load(SHADER_PATH)
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	material = _shader_mat


func set_vignette_intensity(value: float) -> void:
	if _shader_mat:
		_shader_mat.set_shader_parameter("intensity", clampf(value, 0.0, 1.0))
