extends Node
## Persists the running game match so it survives a scene change (death → lobby).
##
## When the human survivor dies, the game_map does NOT destroy itself. Instead it
## hands itself over to this autoload (reparented into a SubViewport BEFORE the
## lobby loads), so the killer bot + survivor bots keep playing. The lobby is
## LINKED to this held match's status (roster + timer). When the dead player
## clicks SPECTATE, return_to_match() pulls the match back out of the SubViewport
## and makes it the current scene again so the round is watched from the game map.

## The still-running game_map node (null when no live match is being held).
var live_match: Node2D = null

## True while a live match is being held for spectating.
var has_live_match: bool = false

## SubViewport that renders the held live match.
var live_viewport: SubViewport = null


func _ready() -> void:
	# Create the live viewport. It shares the main world's 2D physics/navigation
	# so the map keeps simulating (bots pathfinding, collisions) after hand-off.
	live_viewport = SubViewport.new()
	live_viewport.name = "LiveMatchViewport"
	# Share the main world's 2D physics/navigation so the handed-off match keeps
	# simulating (bots pathfinding, collisions) exactly as it did in the map.
	live_viewport.world_2d = get_viewport().world_2d
	live_viewport.transparent_bg = true
	live_viewport.size = Vector2(1280, 768)
	live_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(live_viewport)


func hand_off(match_node: Node2D) -> void:
	"""Reparent the running match into this host's live viewport so it survives
	the scene change and keeps simulating. The lobby renders this viewport."""
	if not is_instance_valid(match_node):
		release()
		return
	live_match = match_node
	has_live_match = true
	# Move the match (and everything under it) into the live viewport.
	if match_node.get_parent() != live_viewport:
		var old_parent: Node = match_node.get_parent()
		if is_instance_valid(old_parent):
			old_parent.remove_child(match_node)
		live_viewport.add_child(match_node)
	# CRITICAL: after reparenting into the SubViewport, the match's spectate
	# camera must become the current camera OF THAT SubViewPORT (not the main
	# viewport). Otherwise the live view renders blank/black in the lobby.
	_make_spectate_cam_current(match_node)
	print("LiveMatchHost: holding live match — spectate available")


func _make_spectate_cam_current(match_node: Node2D) -> void:
	"""Re-apply the match's spectate camera as the current camera for the live
	SubViewport. Camera2D.make_current() targets whatever viewport the camera is
	currently inside; after hand_off the camera is inside live_viewport, so this
	makes it current there and the SubViewport renders the running round."""
	var cam: Camera2D = match_node.get_node_or_null("SpectateCamera") as Camera2D
	if not is_instance_valid(cam):
		# Fall back to the player camera if the spectate cam isn't present yet.
		var player: Node2D = match_node.get_node_or_null("Player") as Node2D
		if is_instance_valid(player):
			cam = player.get_node_or_null("Camera2D") as Camera2D
	if is_instance_valid(cam):
		cam.make_current()


func return_to_match() -> Node2D:
	"""Bring the held live match back as the active scene. Called from the lobby
	when the dead player clicks SPECTATE: the match (still running, still in its
	spectate mode) is pulled out of the SubViewport, made the current scene again,
	and the lobby scene is freed. Returns the match node (null if none held)."""
	if not is_instance_valid(live_match):
		return null
	var m: Node2D = live_match
	var cur: Node = get_tree().current_scene
	# Pull the match back out of the isolating SubViewport into the main tree.
	if m.get_parent() == live_viewport:
		live_viewport.remove_child(m)
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	live_match = null
	has_live_match = false
	get_tree().paused = false
	# Let the match restore its spectate camera/panel (now that it's visible again).
	if m.has_method("_on_returned_to_match"):
		m.call("_on_returned_to_match")
	# Free the lobby now that the match is the scene again.
	if is_instance_valid(cur) and cur != m:
		cur.queue_free()
	print("LiveMatchHost: returned live match to the game map for spectate")
	return m


func release() -> void:
	"""Drop the held match (used when spectate ends / user leaves)."""
	live_match = null
	has_live_match = false


func _exit_tree() -> void:
	release()
