class_name FlowerItem
extends Area2D

## A map pickup that heals a survivor who walks over it, then disappears.

const HEAL_AMOUNT: float = 90.0

var _consumed: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1  # Detect survivor bodies (layer 1)
	monitoring = true
	monitorable = false

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

	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _consumed:
		return
	if not (body.is_in_group("survivors") or body.is_in_group("survivor_bots")):
		return
	if not body.has_method("take_damage"):
		return
	_consumed = true

	# Heal the survivor
	if "max_hp" in body and "current_hp" in body:
		var maxhp: float = float(body.get("max_hp"))
		var new_hp: float = min(float(body.get("current_hp")) + HEAL_AMOUNT, maxhp)
		body.set("current_hp", new_hp)
		if body.has_signal("hp_changed"):
			body.hp_changed.emit(new_hp, maxhp)
		print("FlowerItem: healed ", body.name, " +", HEAL_AMOUNT, " HP")
	queue_free()
