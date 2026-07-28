extends Node
## FontHelpers — utility functions for creating BitmapLabel instances
## with common configurations. Use these instead of Label.new() for
## game-styled text using Font1 character sprites.
##
## Usage:  FontHelpers.make_text("Hello", 20, Vector2(100, 100))

static func make_text(text: String, font_size: float, position: Vector2, color: Color = Color(1,1,1,1), center: bool = false) -> BitmapLabel:
	"""Create a BitmapLabel configured to approximate the given font_size (in points, matching Label font sizes)."""
	var bl := BitmapLabel.new()
	bl.label_text = text
	bl.font_color = color

	# Map font_size (pt) to scale_factor: ~100px native char height / 56pt default = ~1.78
	# So scale = font_size / 56.0 gives approximate sizing
	# But our char height is ~100-150px, 56pt system font is ~56px tall
	# Scale factor of ~0.4-0.6 should be right for most text
	# Empirical: 56pt system font ≈ 56px → scale 56/120 = 0.47
	bl.font_scale = font_size / 120.0
	bl.char_spacing = font_size * 0.12

	if center:
		bl.horizontal_align = 1

	bl.position = position
	# Set size to fill available space (default large)
	bl.size = Vector2(800, font_size * 2)
	return bl

static func make_big_text(text: String, scale: float, position: Vector2, color: Color = Color(1,1,1,1)) -> BitmapLabel:
	"""Create a BitmapLabel with explicit scale factor for large/prominent text."""
	var bl := BitmapLabel.new()
	bl.label_text = text
	bl.font_scale = scale
	bl.font_color = color
	bl.horizontal_align = 1
	bl.vertical_align = 1
	bl.position = position
	bl.size = Vector2(1024, 768)
	return bl
