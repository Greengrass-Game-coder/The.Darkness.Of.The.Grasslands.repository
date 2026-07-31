class_name SceneFader
extends CanvasLayer
## Professional scene transition system with fade-to-black,
## loading bar, and smooth cross-scene transitions.
##
## Usage:
##   SceneFader.transition_to("res://scenes/lobby.tscn")
##   SceneFader.transition_to("res://scenes/game_map.tscn", "Loading match...")
##
## Add as autoload or instantiate when needed.

signal transition_finished

# ── Config ──
const FADE_DURATION: float = 0.5
const LOAD_BAR_WIDTH: float = 400.0
const LOAD_BAR_HEIGHT: float = 20.0

# ── State ──
var _active: bool = false
var _target_scene: String = ""
var _loading_text: String = ""
var _fade_rect: ColorRect = null
var _bar_bg: ColorRect = null
var _bar_fill: ColorRect = null
var _loading_label: Label = null


func _ready() -> void:
	layer = 100  # Above everything
	_create_elements()
	# Start fully visible, fade in on first frame
	if _fade_rect:
		_fade_rect.color = Color(0, 0, 0, 0)
		_fade_in()


func _create_elements() -> void:
	var vs := get_viewport().get_visible_rect().size

	_fade_rect = ColorRect.new()
	_fade_rect.size = vs
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_fade_rect)

	# Loading bar (centered)
	_bar_bg = ColorRect.new()
	_bar_bg.size = Vector2(LOAD_BAR_WIDTH + 4, LOAD_BAR_HEIGHT + 4)
	_bar_bg.position = Vector2((vs.x - _bar_bg.size.x) / 2, vs.y * 0.75)
	_bar_bg.color = Color(0.3, 0.3, 0.3, 0.8)
	_bar_bg.visible = false
	add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.size = Vector2(LOAD_BAR_WIDTH, LOAD_BAR_HEIGHT)
	_bar_fill.position = Vector2((vs.x - LOAD_BAR_WIDTH) / 2, vs.y * 0.75 + 2)
	_bar_fill.color = Color(0.15, 0.9, 0.15, 0.9)
	_bar_fill.visible = false
	add_child(_bar_fill)

	_loading_label = Label.new()
	_loading_label.position = Vector2(0, vs.y * 0.75 + LOAD_BAR_HEIGHT + 12)
	_loading_label.size = Vector2(vs.x, 30)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_loading_label.add_theme_font_size_override("font_size", 16)
	_loading_label.visible = false
	add_child(_loading_label)


func _fade_in() -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color", Color(0, 0, 0, 0), FADE_DURATION)
	await tween.finished
	queue_free()


func transition_to(scene_path: String, loading_text: String = "") -> void:
	if _active:
		return
	_active = true
	_target_scene = scene_path
	_loading_text = loading_text

	# Fade to black
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color", Color(0, 0, 0, 1), FADE_DURATION)
	await tween.finished

	# Show loading elements
	if not loading_text.is_empty():
		_loading_label.text = loading_text
		_loading_label.visible = true
		_bar_bg.visible = true
		_bar_fill.visible = true

		# Animate loading bar over 0.5s
		var lt := create_tween()
		lt.tween_property(_bar_fill, "size:x", 0.0, 0.0)
		lt.tween_property(_bar_fill, "size:x", LOAD_BAR_WIDTH, 0.5)
		await lt.finished

	# Preload scene in background
	var err: int = ResourceLoader.load_threaded_request(scene_path)
	if err != OK:
		# Direct load
		_do_transition()
		return

	# Wait for threaded load
	var load_statuses: Array = []
	while true:
		ResourceLoader.load_threaded_get_status(scene_path, load_statuses)
		var load_status: int = load_statuses[0] if load_statuses.size() > 0 else 0
		if load_status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		await get_tree().process_frame

	_do_transition()


func _do_transition() -> void:
	get_tree().change_scene_to_file(_target_scene)
	transition_finished.emit()
	queue_free()


## Static convenience — instantiate and transition
static func go(scene_path: String, loading_text: String = "") -> void:
	var fader := SceneFader.new()
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.add_child(fader)
		fader.transition_to(scene_path, loading_text)
