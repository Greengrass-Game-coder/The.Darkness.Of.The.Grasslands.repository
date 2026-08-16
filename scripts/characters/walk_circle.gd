class_name WalkCircle
extends Node2D

## Black circle with a red outline spawned on Violentgrass's feet while walking.
## It "evaporates" by shrinking down and fading out over `lifetime` seconds.

@export var radius: float = 18.0
@export var lifetime: float = 2.0
@export var outline_width: float = 3.0

func _ready() -> void:
	z_index = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	modulate.a = 0.9

	# Shrink to a tiny remnant while fading to invisible over `lifetime` seconds,
	# then remove the node. Uses a lambda-free tween so no bind() conversion errors.
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.15, 0.15), lifetime) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "modulate:a", 0.0, lifetime) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	# Black fill
	draw_circle(Vector2.ZERO, radius, Color(0.02, 0.02, 0.02, 0.9))
	# Red outline
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.92, 0.04, 0.04, 1.0), outline_width, true)
	# Faint inner red ring for extra definition
	draw_arc(Vector2.ZERO, radius * 0.55, 0.0, TAU, 32, Color(0.6, 0.02, 0.02, 0.55), outline_width * 0.5, true)
