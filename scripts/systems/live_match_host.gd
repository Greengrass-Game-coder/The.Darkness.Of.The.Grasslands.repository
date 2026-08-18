extends Node
## Persists the running game match so it survives a scene change (death → lobby).
##
## When the human survivor dies, the game_map does NOT destroy itself. Instead it
## hands itself over to this autoload (reparented out of the old scene BEFORE the
## lobby loads), so the killer bot + survivor bots keep playing. The lobby then
## reads `live_match` and renders it live into a SubViewport, letting the player
## spectate the ongoing round with arrows to switch between killer & survivors.

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
	print("LiveMatchHost: holding live match — spectate available")


func release() -> void:
	"""Drop the held match (used when spectate ends / user leaves)."""
	live_match = null
	has_live_match = false


func _exit_tree() -> void:
	release()
