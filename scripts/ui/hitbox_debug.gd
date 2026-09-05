class_name HitboxDebug
extends Node2D

## Draws a character's collision shape (its "hitbox") as a translucent filled
## shape with a bright outline. Attach as a child of a CharacterBody2D and set
## `shape_owner` to that character. Used by the "Show Hitboxes" and
## "See Collision Hitboxes" settings. This draws player bodies only — walls and
## tilemaps are never included.

## The character whose CollisionShape2D we outline.
var shape_owner: Node2D = null

func _ready() -> void:
	z_index = 300


func _draw() -> void:
	var cs: CollisionShape2D = _find_shape()
	if cs == null or cs.shape == null:
		return
	var pos: Vector2 = cs.position
	var sh: Shape2D = cs.shape
	var fill := Color(0.2, 1.0, 0.3, 0.15)
	var line := Color(0.2, 1.0, 0.3, 0.9)

	if sh is CircleShape2D:
		var r: float = (sh as CircleShape2D).radius
		draw_circle(pos, r, fill)
		draw_arc(pos, r, 0.0, TAU, 32, line, 1.5)
	elif sh is RectangleShape2D:
		var rect_sh := sh as RectangleShape2D
		var half: Vector2 = rect_sh.size * 0.5
		var rect := Rect2(pos - half, rect_sh.size)
		draw_rect(rect, fill, true)
		draw_rect(rect, line, false, 1.5)
	elif sh is CapsuleShape2D:
		var cap := sh as CapsuleShape2D
		var half_h: float = cap.height * 0.5
		var r: float = cap.radius
		var top_center: Vector2 = pos + Vector2(0, -half_h + r)
		var bot_center: Vector2 = pos + Vector2(0, half_h - r)
		draw_circle(top_center, r, fill)
		draw_circle(bot_center, r, fill)
		draw_rect(Rect2(pos + Vector2(-r, -half_h + r), Vector2(r * 2.0, (half_h - r) * 2.0)), fill, true)
		draw_arc(top_center, r, 0.0, TAU, 24, line, 1.5)
		draw_arc(bot_center, r, 0.0, TAU, 24, line, 1.5)
		draw_line(pos + Vector2(-r, -half_h + r), pos + Vector2(-r, half_h - r), line, 1.5)
		draw_line(pos + Vector2(r, -half_h + r), pos + Vector2(r, half_h - r), line, 1.5)
	elif sh is ConvexPolygonShape2D:
		var poly := sh as ConvexPolygonShape2D
		var pts: PackedVector2Array = poly.points
		if pts.size() >= 3:
			var moved := PackedVector2Array()
			for p in pts:
				moved.append(p + pos)
			var colors := PackedColorArray()
			colors.resize(moved.size())
			colors.fill(fill)
			draw_polygon(moved, colors)
			draw_polyline(moved, line, 1.5, true)


func _find_shape() -> CollisionShape2D:
	if is_instance_valid(shape_owner):
		var n: Node = shape_owner.get_node_or_null("CollisionShape2D")
		if n is CollisionShape2D:
			return n
	return null
