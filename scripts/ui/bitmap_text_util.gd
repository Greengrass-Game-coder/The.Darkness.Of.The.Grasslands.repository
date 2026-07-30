## BitmapTextUtil ----- convenience functions for creating properly-sized BitmapLabels.
## Use these in game_map.gd, chat_layer.gd, and other scripts to create
## text that uses Font1 character sprites.

static func make_label(text: String, font_size: float = 16.0, color: Color = Color(1,1,1,1), center: bool = false) -> BitmapLabel:
	"""Create a BitmapLabel at the given approximate font size (in points)."""
	var bl := BitmapLabel.new()
	bl.label_text = text
	bl.font_color = color
	# Map: 100px native char height -%- 56pt system font -->- scale_factor = font_size / 120.0
	bl.font_scale = font_size / 120.0
	bl.char_spacing = font_size * 0.12
	if center:
		bl.horizontal_align = 1
	return bl

static func make_key_label(key_text: String) -> BitmapLabel:
	"""Create a small key hint label (like 'Q', 'E', 'R')."""
	var bl := BitmapLabel.new()
	bl.label_text = key_text
	bl.font_color = Color(1, 1, 1, 0.8)
	bl.font_scale = 0.10  # ~12pt
	bl.char_spacing = 2.0
	return bl

static func make_cooldown_label() -> BitmapLabel:
	"""Create a centered cooldown number label."""
	var bl := BitmapLabel.new()
	bl.font_color = Color(1, 1, 1, 0.9)
	bl.font_scale = 0.16  # ~19pt
	bl.horizontal_align = 1
	bl.vertical_align = 1
	bl.char_spacing = 2.0
	return bl

static func replace_scene_label(parent: Node, scene_label: Label, new_text: String = "", font_size: float = 16.0, color: Color = Color(1,1,1,1), center: bool = false) -> BitmapLabel:
	"""Hide a scene's Label node, create a BitmapLabel overlay at the same position/size.
	Returns the new BitmapLabel for further manipulation.
	"""
	if not is_instance_valid(scene_label) or not is_instance_valid(parent):
		return null
	var bl := make_label(new_text if new_text else scene_label.text, font_size, color, center)
	bl.position = scene_label.position
	bl.size = scene_label.size
	bl.name = "Bmp_" + scene_label.name
	scene_label.visible = false
	parent.add_child(bl)
	return bl
