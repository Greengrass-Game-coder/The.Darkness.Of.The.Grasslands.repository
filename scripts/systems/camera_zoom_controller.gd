class_name CameraZoomController
extends Node
## Adds scroll-wheel zoom controls to the player camera.
## Attached as a child of the player node — works with any character.
##
## Controls:
##   Mouse wheel up = zoom in    (lower zoom value = more zoomed in)
##   Mouse wheel down = zoom out (higher zoom value = more zoomed out)
##
## Shows a brief zoom level indicator when zoom changes.

signal zoom_changed(new_zoom: float)

# ── Config ──
@export var min_zoom: float = 0.35    # Maximum zoom-in level
@export var max_zoom: float = 3.0     # Maximum zoom-out level
@export var default_zoom: float = 1.25  # Starting zoom (was 1.0)
@export var zoom_step: float = 0.1    # How much each scroll tick changes zoom
@export var smoothing_speed: float = 8.0  # How fast zoom animates

# ── Indicator config ──
@export var indicator_duration: float = 1.2  # How long zoom indicator stays visible
@export var indicator_font_size: int = 24
@export var indicator_color: Color = Color(1, 1, 1, 1)

var _camera: Camera2D = null
var _target_zoom: float = 1.25
var _indicator_label: Label = null
var _indicator_timer: float = 0.0

# Backing store for the current zoom value to avoid Tween conflicts
var _current_zoom: float = 1.25


func _ready() -> void:
	# Find camera on parent or create one
	_camera = get_parent().get_node_or_null("Camera2D") as Camera2D
	if not _camera:
		# Create camera on parent if needed
		_camera = Camera2D.new()
		_camera.name = "Camera2D"
		get_parent().add_child(_camera)
	
	# Set default zoom
	_target_zoom = default_zoom
	_current_zoom = default_zoom
	_camera.zoom = Vector2(default_zoom, default_zoom)
	_camera.enabled = true
	_camera.make_current()
	
	# Position smoothing
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 6.0


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_change_zoom(-zoom_step)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_change_zoom(zoom_step)


func _change_zoom(delta: float) -> void:
	_target_zoom = clampf(_target_zoom + delta, min_zoom, max_zoom)
	_show_zoom_indicator(_target_zoom)
	zoom_changed.emit(_target_zoom)


func _process(delta: float) -> void:
	# Smooth zoom interpolation
	if _camera and abs(_camera.zoom.x - _target_zoom) > 0.001:
		_current_zoom = lerpf(_current_zoom, _target_zoom, smoothing_speed * delta)
		_camera.zoom = Vector2(_current_zoom, _current_zoom)
	
	# Handle indicator fade
	if _indicator_label and _indicator_timer > 0:
		_indicator_timer -= delta
		if _indicator_timer <= 0:
			if is_instance_valid(_indicator_label):
				_indicator_label.queue_free()
			_indicator_label = null


func _show_zoom_indicator(_zoom_level: float) -> void:
	"""Show a brief zoom level indicator on screen."""
	if not _indicator_label or not is_instance_valid(_indicator_label):
		# Create new indicator
		_indicator_label = Label.new()
		_indicator_label.name = "ZoomIndicator"
		_indicator_label.add_theme_color_override("font_color", indicator_color)
		_indicator_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		_indicator_label.add_theme_constant_override("shadow_offset_x", 1)
		_indicator_label.add_theme_constant_override("shadow_offset_y", 1)
		_indicator_label.add_theme_font_size_override("font_size", indicator_font_size)
		_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_indicator_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_indicator_label.size = Vector2(120, 40)
		_indicator_label.position = Vector2(
			get_viewport().size.x / 2.0 - 60,
			get_viewport().size.y / 2.0 - 80
		)
		
		# Find a CanvasLayer to show on (creates one if needed)
		var parent_layer: CanvasLayer = get_node_or_null("/root/GameMap/HUD/ZoomLayer")
		if not parent_layer:
			# Create a HUD ZoomLayer
			var hud: CanvasLayer = get_node_or_null("/root/GameMap/HUD")
			if hud:
				var zl := CanvasLayer.new()
				zl.name = "ZoomLayer"
				zl.layer = 128  # Above everything
				hud.add_child(zl)
				parent_layer = zl
			else:
				parent_layer = get_node_or_null("/root/GameMap/HUD")
		
		if parent_layer:
			parent_layer.add_child(_indicator_label)
	
	# Update text
	var pct: int = int(round(_target_zoom * 100))
	_indicator_label.text = "ZOOM: %d%%" % pct
	_indicator_timer = indicator_duration


## Public API — set zoom programmatically
func set_zoom(level: float, animated: bool = true) -> void:
	_target_zoom = clampf(level, min_zoom, max_zoom)
	if not animated:
		_current_zoom = _target_zoom
		if _camera:
			_camera.zoom = Vector2(_target_zoom, _target_zoom)
	_show_zoom_indicator(_target_zoom)


## Map zoom — zoom out to show the entire map, centered on a position
@export var map_zoom: float = 0.45  # Zoom level to show the full map (lower = more zoomed out)

func zoom_to_map_view() -> void:
	"""Zoom out to show the full map — camera stays on player, but at map_zoom the whole map is visible."""
	if not is_instance_valid(_camera):
		return
	_target_zoom = map_zoom
	_current_zoom = _target_zoom
	_camera.zoom = Vector2(_target_zoom, _target_zoom)
	_camera.position_smoothing_enabled = false


## Restore normal zoom and follow the parent character
func restore_normal_zoom() -> void:
	"""Restore zoom to default and re-enable camera smoothing."""
	if not is_instance_valid(_camera):
		return
	_target_zoom = default_zoom
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 6.0
	_show_zoom_indicator(_target_zoom)
