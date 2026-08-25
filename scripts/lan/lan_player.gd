class_name LanPlayer
extends Node2D
## A player in the LAN arena. Each peer owns exactly one of these (authority is
## set from the node name), and a MultiplayerSynchronizer (added by the arena's
## spawn function) replicates its position to every other device. Only the
## owning device reads input and moves it; everyone else just receives its
## position over the network.

const RADIUS := 18.0

var player_color: Color = Color(0.4, 0.9, 0.4, 1.0)
var player_name: String = "PLAYER"
var player_tag: String = ""

const SPEED := 240.0
const ARENA := Vector2(1200, 680)


func _enter_tree() -> void:
	# "Player_2" → owner id 2. Deterministic on every peer.
	var owner_id: int = int(str(name).trim_prefix("Player_"))
	set_multiplayer_authority(owner_id)


func _ready() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	position += dir * SPEED * delta
	position.x = clampf(position.x, RADIUS, ARENA.x - RADIUS)
	position.y = clampf(position.y, RADIUS + 40.0, ARENA.y - RADIUS)


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, player_color)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, Color(0, 0, 0, 0.45), 3.0)
	draw_circle(Vector2.ZERO, RADIUS * 0.42, Color(1, 1, 1, 0.9))
