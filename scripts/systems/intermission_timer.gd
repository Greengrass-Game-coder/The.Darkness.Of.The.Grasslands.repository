extends Node
## IntermissionTimer — a global countdown that survives scene changes.
##
## The "intermission" is the lobby's countdown before the round starts. It used
## to live in the lobby node, so stepping into the arcade room (a scene change)
## silently reset it back to the full duration. This autoload owns the countdown
## so it keeps ticking across the lobby <-> arcade room transition, and both
## scenes read the same remaining time. The arcade room surfaces it as a
## top-left notification; the lobby renders it in its countdown label.
##
## Process mode is PAUSABLE: it stops while the pause menu is open (fair play)
## but, being an autoload, it is never freed, so it keeps running through scene
## changes. When it hits zero the round starts and we move to the game map.

signal ticked(seconds_left: int)
signal finished

const GAME_MAP_SCENE := "res://scenes/game_map.tscn"
const ARCADE_ROOM_SCENE := "res://scenes/arcade_room.tscn"

var duration: float = 60.0
var time_remaining: float = 60.0
var running: bool = false


func _ready() -> void:
	# PROCESS_MODE_ALWAYS so the countdown keeps running while the pause menu is
	# open — the game is multiplayer, so the intermission (and the match it leads
	# into) continues for everyone even if one player pauses.
	process_mode = Node.PROCESS_MODE_ALWAYS
	finished.connect(_on_finished)


func start(d: float = 60.0) -> void:
	duration = d
	time_remaining = d
	running = true


func stop() -> void:
	running = false


func seconds_left() -> int:
	return maxi(0, ceili(time_remaining))


func _process(delta: float) -> void:
	if not running:
		return
	var before: int = seconds_left()
	time_remaining -= delta
	var after: int = seconds_left()
	if after != before:
		ticked.emit(after)
	if time_remaining <= 0.0:
		time_remaining = 0.0
		running = false
		finished.emit()


func _on_finished() -> void:
	# Autosave player progress before the round starts.
	if not GameState.logged_in_username.is_empty():
		var sm := get_node_or_null("/root/SaveManager")
		if is_instance_valid(sm) and sm.has_method("autosave"):
			sm.autosave(GameState.logged_in_username)
	# If the player is in the arcade room, don't yank them out mid-arcade: the
	# room listens to `finished` and offers a JOIN / KEEP PLAYING choice instead
	# of auto-transitioning.
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == ARCADE_ROOM_SCENE:
		return
	get_tree().change_scene_to_file(GAME_MAP_SCENE)
