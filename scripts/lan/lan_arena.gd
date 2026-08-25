class_name LanArena
extends Node2D
## LAN Party arena — a quick 2-player competitive round on the local network.
##
## The host (laptop, peer 1) is the authority: it owns the MultiplayerSpawner,
## spawns orbs, detects pickups and does the scoring. The guest (phone, peer 2)
## sends its own position (via its player's MultiplayerSynchronizer) and receives
## orb + score updates. First player to reach WIN_SCORE orbs wins.

const ARENA := Vector2(1200, 680)
const WIN_SCORE := 10
const ORB_RADIUS := 11.0
const PICKUP_DIST := 36.0

var _players: Node
var _spawner: MultiplayerSpawner
var _scores: Dictionary = {1: 0, 2: 0}
var _orbs: PackedVector2Array = PackedVector2Array()
var _ended := false
var _rng := RandomNumberGenerator.new()

var _score_host: Label
var _score_guest: Label
var _msg: Label
var _hud: CanvasLayer


func _ready() -> void:
	_rng.randomize()
	_build_arena()
	TouchControls.set_mode(TouchControls.OVERWORLD)
	# Allow running the arena directly (headless test) without a prior lobby.
	if not LANManager.connected:
		LANManager.host()
	_setup_spawner()
	if LANManager.is_host:
		_init_orbs()
		_host_spawn_all()
	_update_score_labels()


## ── Visuals / HUD ───────────────────────────────────────────────────

func _build_arena() -> void:
	queue_redraw()
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)

	var title := Label.new()
	title.text = "LAN PARTY — ORB RUSH"
	title.position = Vector2(0, 10)
	title.size = Vector2(ARENA.x, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	_hud.add_child(title)

	_score_host = _make_score_label(40, 60)
	_score_guest = _make_score_label(ARENA.x - 300, 60)
	_hud.add_child(_score_host)
	_hud.add_child(_score_guest)

	_msg = Label.new()
	_msg.position = Vector2(0, ARENA.y - 60)
	_msg.size = Vector2(ARENA.x, 40)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_font_size_override("font_size", 28)
	_msg.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_hud.add_child(_msg)
	_msg.text = "Collect %d orbs to win!" % WIN_SCORE


func _make_score_label(x: float, y: float) -> Label:
	var l := Label.new()
	l.position = Vector2(x, y)
	l.size = Vector2(260, 60)
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	return l


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, ARENA), Color(0.07, 0.08, 0.10, 1))
	# floor grid lines
	for x in range(60, int(ARENA.x), 60):
		draw_line(Vector2(x, 0), Vector2(x, ARENA.y), Color(1, 1, 1, 0.03))
	for y in range(60, int(ARENA.y), 60):
		draw_line(Vector2(0, y), Vector2(ARENA.x, y), Color(1, 1, 1, 0.03))
	draw_rect(Rect2(Vector2.ZERO, ARENA), Color(0.7, 0.7, 0.8, 1), false, 6.0)
	for o in _orbs:
		draw_circle(o, ORB_RADIUS, Color(1, 0.85, 0.25, 1))
		draw_arc(o, ORB_RADIUS, 0.0, TAU, 24, Color(0.6, 0.4, 0, 1), 2.0)


## ── Networking: spawn players ──────────────────────────────────────

func _setup_spawner() -> void:
	_players = Node.new()
	_players.name = "Players"
	add_child(_players)
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "Spawner"
	add_child(_spawner)
	_spawner.spawn_path = _spawner.get_path_to(_players)
	_spawner.spawn_function = Callable(self, "_spawn_player")
	# Only the host spawns.
	_spawner.set_multiplayer_authority(1)
	multiplayer.peer_connected.connect(_on_peer_connected)


func _spawn_player(data) -> Node:
	var id: int = int(data)
	var p := Node2D.new()
	p.name = "Player_%d" % id
	p.set_script(load("res://scripts/lan/lan_player.gd"))
	if id == 1:
		p.set("player_name", "HOST")
		p.set("player_color", Color(0.4, 0.9, 0.4, 1))
	else:
		p.set("player_name", "GUEST")
		p.set("player_color", Color(0.4, 0.6, 1.0, 1))
	p.position = Vector2(200.0 + id * 320.0, 360.0)
	var sync := MultiplayerSynchronizer.new()
	sync.replication_interval = 0.0
	var cfg := SceneReplicationConfig.new()
	cfg.add_property(NodePath(".:position"))
	cfg.property_set_spawn(NodePath(".:position"), true)
	cfg.property_set_replication_mode(NodePath(".:position"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = cfg
	sync.root_path = NodePath("..")
	p.add_child(sync)
	return p


func _host_spawn_all() -> void:
	if not LANManager.is_host:
		return
	_spawn_player_safe(1)
	for p in multiplayer.get_peers():
		_spawn_player_safe(int(p))


func _spawn_player_safe(id: int) -> void:
	if id <= 0:
		return
	if _players.has_node("Player_%d" % id):
		return
	_spawner.spawn(id)


func _on_peer_connected(peer_id: int) -> void:
	if LANManager.is_host:
		_spawn_player_safe(peer_id)


## ── Orbs + scoring (host-authoritative) ────────────────────────────

func _init_orbs() -> void:
	_orbs = PackedVector2Array()
	for i in range(5):
		_orbs.append(_rand_orb_pos())
	_sync_orbs.rpc(_orbs)


func _rand_orb_pos() -> Vector2:
	return Vector2(
		_rng.randf_range(60.0, ARENA.x - 60.0),
		_rng.randf_range(90.0, ARENA.y - 60.0)
	)


@rpc("any_peer", "call_local", "reliable")
func _sync_orbs(positions: PackedVector2Array) -> void:
	_orbs = positions
	queue_redraw()


@rpc("any_peer", "call_local", "reliable")
func _sync_score(peer_id: int, score: int) -> void:
	_scores[peer_id] = score
	_update_score_labels()


@rpc("any_peer", "call_local", "reliable")
func _end_game(winner_name: String) -> void:
	_ended = true
	_msg.text = winner_name + " WINS!  (ENTER / BACK to return)"


func _process(_delta: float) -> void:
	if not LANManager.is_host or _ended:
		return
	# Server checks every player against every orb.
	for child in _players.get_children():
		var pid: int = int(str(child.name).trim_prefix("Player_"))
		for oi in range(_orbs.size()):
			if child.position.distance_to(_orbs[oi]) < PICKUP_DIST:
				_collect(pid, oi)
				break


func _collect(pid: int, orb_index: int) -> void:
	_orbs[orb_index] = _rand_orb_pos()
	_sync_orbs.rpc(_orbs)
	var s: int = int(_scores.get(pid, 0)) + 1
	_scores[pid] = s
	_sync_score.rpc(pid, s)
	if s >= WIN_SCORE:
		_end_game.rpc("HOST" if pid == 1 else "GUEST")


func _update_score_labels() -> void:
	var host_name := "HOST"
	var guest_name := "GUEST"
	_score_host.text = "%s: %d" % [host_name, int(_scores.get(1, 0))]
	_score_guest.text = "%s: %d" % [guest_name, int(_scores.get(2, 0))]


## ── Quit ───────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	var leave: bool = event.is_action_pressed("ui_cancel") \
		or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) \
		or InputSystem.just_pressed("cancel")
	# On the win screen, ENTER / OK also returns.
	if _ended and (leave or InputSystem.just_pressed("confirm")):
		leave = true
	if leave:
		LANManager.stop()
		get_tree().change_scene_to_file("res://scenes/arcade_room.tscn")
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	LANManager.stop()
