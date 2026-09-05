class_name FlowerItem
extends Area2D

## A manual pickup item that a survivor grabs (press 1/2/3) and later uses to
## heal/cure. Only survivors can pick it up; killers can't grab items. It no
## longer heals on contact; the survivor must grab it and then use it.

const FLOWER_ITEM := "flower"
const HEAL_AMOUNT: float = 90.0
const PICKUP_RADIUS: float = 70.0

var _consumed: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1  # Detect survivor bodies (layer 1)
	monitoring = true
	monitorable = false
	add_to_group("flower_items")

	# Sprite
	var sprite := Sprite2D.new()
	var tex: Texture2D = load("res://The Darkness Of The Grasslands assets/items/flower.png")
	if tex:
		sprite.texture = tex
	# Scale the 194x353 source to a reasonable world pickup size
	sprite.scale = Vector2(0.16, 0.16)
	sprite.z_index = 100
	add_child(sprite)

	# Collision
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 28.0
	col.shape = shape
	add_child(col)


func is_consumed() -> bool:
	return _consumed


func _is_survivor(body: Node2D) -> bool:
	return body.is_in_group("survivors") or body.is_in_group("survivor_bots")


func in_pickup_range(body: Node2D) -> bool:
	return global_position.distance_to(body.global_position) <= PICKUP_RADIUS


## Only a nearby survivor can grab this flower. Killers are never accepted.
func try_pickup(body: Node2D) -> bool:
	if _consumed:
		return false
	if not _is_survivor(body):
		return false
	if not in_pickup_range(body):
		return false
	_consumed = true
	queue_free()
	return true
