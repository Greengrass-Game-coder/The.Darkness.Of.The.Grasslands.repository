extends Control
## BitmapLabel ----- renders text using FontManager's cropped character textures.
## Uses _draw() to render directly.
## Dollar-mode: "$" in text toggles golden rendering style.
## Context controls when "$" is visible: "menu" strips it, "match"/"chat" shows it.

class_name BitmapLabel

enum Context { MENU, MATCH, CHAT }

var _fm_connected: bool = false

@export var label_text: String = "":
	set(v):
		if v != label_text:
			label_text = v
			queue_redraw()

## Alias for label_text ----- allows Label API compatibility (Label.text -->- BitmapLabel.label_text)
var text: String:
	get:
		return label_text
	set(v):
		label_text = v
		queue_redraw()

@export var font_scale: float = 1.0:
	set(v):
		font_scale = v
		queue_redraw()

@export var char_spacing: float = 8.0:
	set(v):
		char_spacing = v
		queue_redraw()

@export var horizontal_align: int = 0:
	set(v):
		horizontal_align = v
		queue_redraw()

@export var vertical_align: int = 0:
	set(v):
		vertical_align = v
		queue_redraw()

@export var dollar_mode: bool = false:
	set(v):
		dollar_mode = v
		queue_redraw()

@export var context: int = Context.MENU:
	set(v):
		context = v
		queue_redraw()

@export var font_color: Color = Color(1, 1, 1, 1):
	set(v):
		font_color = v
		queue_redraw()

func _try_connect_fm() -> void:
	"""Connect to FontManager via /root path (Engine.get_singleton may not work for custom autoloads)."""
	if _fm_connected:
		return
	var fm = get_node_or_null("/root/FontManager")
	if not is_instance_valid(fm):
		return
	if fm.has_signal("fonts_loaded") and not fm.fonts_loaded.is_connected(_on_fonts_loaded):
		fm.fonts_loaded.connect(_on_fonts_loaded)
		_fm_connected = true
		if fm.is_ready and not label_text.is_empty():
			queue_redraw()


func _on_fonts_loaded() -> void:
	"""FontManager finished loading ----- redraw if we have text."""
	queue_redraw()


func set_text(t: String) -> void:
	label_text = t

func get_text() -> String:
	return label_text

func _draw() -> void:
	# Try connecting to FontManager signal if not done yet
	_try_connect_fm()
	
	var fm = get_node_or_null("/root/FontManager")
	if not is_instance_valid(fm) or not fm.is_ready:
		return

	var raw: String = label_text
	if raw.is_empty():
		return

	var use_dollar: bool = dollar_mode and context != Context.MENU
	var dollar_active: bool = false
	var x: float = 0.0
	var max_h: float = 0.0
	var char_data: Array[Dictionary] = []

	for i in range(raw.length()):
		var ch: String = raw[i]
		if use_dollar and ch == "$":
			dollar_active = not dollar_active
			continue

		var tex = fm.get_char_texture(ch, dollar_active)
		if not tex:
			char_data.append({"tex": null, "w": fm.DEFAULT_CHAR_W * font_scale, "h": fm.DEFAULT_CHAR_H * font_scale, "dollar": dollar_active, "ch": ch})
			x += fm.DEFAULT_CHAR_W * font_scale + char_spacing
			continue

		var tw: float = tex.get_size().x * font_scale
		var th: float = tex.get_size().y * font_scale
		char_data.append({"tex": tex, "w": tw, "h": th, "dollar": dollar_active, "ch": ch})
		if th > max_h:
			max_h = th
		x += tw + char_spacing

	if char_data.is_empty():
		return

	var total_w: float = x - char_spacing
	var h_off: float = 0.0
	match horizontal_align:
		1: h_off = (size.x - total_w) * 0.5
		2: h_off = size.x - total_w

	var v_off: float = 0.0
	match vertical_align:
		1: v_off = (size.y - max_h) * 0.5
		2: v_off = size.y - max_h

	var draw_x: float = h_off
	for cd in char_data:
		var tex = cd["tex"] as Texture2D
		if tex:
			var w: float = cd["w"]
			var h: float = cd["h"]
			var is_dollar: bool = cd["dollar"]
			var draw_col: Color = Color(1.0, 0.85, 0.3, font_color.a) if is_dollar else font_color
			var draw_y: float = v_off + (max_h - h) * 0.5
			var rect := Rect2(draw_x, draw_y, w, h)
			draw_texture_rect(tex, rect, false, draw_col)

		draw_x += cd["w"] + char_spacing
