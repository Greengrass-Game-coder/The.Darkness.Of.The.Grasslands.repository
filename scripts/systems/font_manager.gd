extends Node
## FontManager — autoload that loads Font1 PNG characters as cropped textures.
## Provides bitmap-style character rendering for in-game text.
## Dollar font ($) is a togglable alternate style meant for match/chat only.

# Autoload singleton — accessible globally as FontManager

# Emitted when all font textures are loaded and ready
signal fonts_loaded()

# Character texture dictionary: char -> Texture2D
var char_textures: Dictionary = {}
var dollar_textures: Dictionary = {}

# Character sizes: char -> Vector2 (width, height in pixels at native scale)
var char_sizes: Dictionary = {}
var dollar_char_sizes: Dictionary = {}

# Base font directory
const FONT_DIR: String = "res://The Darkness Of The Grasslands assets/Fonts/Font1/"

# Default character width/height for unknown/missing chars
const DEFAULT_CHAR_W: float = 100.0
const DEFAULT_CHAR_H: float = 120.0

# Spacing between characters as a ratio of previous char width
var letter_spacing: float = 0.15

# Whether font data is ready
var is_ready: bool = false

# Dollar mode characters — when enabled, "$" toggles dollar-style rendering
var _dollar_mode_active: bool = false

func _ready() -> void:
	_load_fonts()

func _load_fonts() -> void:
	"""Scan Font1 directory, load and crop all character PNGs."""
	var dir := DirAccess.open(FONT_DIR)
	if not dir:
		push_error("FontManager: Cannot open font directory: ", FONT_DIR)
		return

	var files := dir.get_files()
	# Map filename base names to character strings
	var name_to_char: Dictionary = _build_name_map()

	var loaded_count: int = 0
	for fname in files:
		if not fname.ends_with(".png") or fname.contains(".import"):
			continue
		var base := fname.trim_prefix("FONT1_").trim_suffix(".png")
		var ch: String = name_to_char.get(base, "")
		if ch.is_empty():
			continue

		var path := FONT_DIR.path_join(fname)
		if not ResourceLoader.exists(path):
			continue

		var tex := load(path) as Texture2D
		if not tex:
			continue

		# Crop to bounding box
		var cropped := _crop_texture(tex)
		if not cropped:
			continue

		# Store in regular font map
		char_textures[ch] = cropped
		char_sizes[ch] = cropped.get_size()
		loaded_count += 1

		# If this is dollar, also store in dollar map
		if ch == "$":
			dollar_textures[ch] = cropped
			dollar_char_sizes[ch] = cropped.get_size()

	is_ready = true
	print("FontManager: Loaded ", loaded_count, " character textures")
	fonts_loaded.emit()

func _build_name_map() -> Dictionary:
	"""Build mapping from file base name (e.g. 'A', 'exclamation') to the character string (e.g. 'A', '!')."""
	var m: Dictionary = {}
	m["A"] = "A"
	m["B"] = "B"
	m["C"] = "C"
	m["D"] = "D"
	m["E"] = "E"
	m["F"] = "F"
	m["G"] = "G"
	m["H"] = "H"
	m["I"] = "I"
	m["J"] = "J"
	m["N"] = "N"
	m["O"] = "O"
	m["P"] = "P"
	m["Q"] = "Q"
	m["R"] = "R"
	m["S"] = "S"
	m["T"] = "T"
	m["Y"] = "Y"
	m["a"] = "a"
	m["k"] = "k"
	m["l"] = "l"
	m["m"] = "m"
	m["u"] = "u"
	m["v"] = "v"
	m["w"] = "w"
	m["x"] = "x"
	m["z"] = "z"
	m["0"] = "0"
	m["1"] = "1"
	m["2"] = "2"
	m["3"] = "3"
	m["4"] = "4"
	m["5"] = "5"
	m["6"] = "6"
	m["7"] = "7"
	m["8"] = "8"
	m["9"] = "9"
	m["dollar"] = "$"
	m["exclamation"] = "!"
	m["question mark"] = "?"
	m["colon"] = ":"
	m["comma"] = ","
	m["dash"] = "-"
	m["underscore"] = "_"
	m["slash"] = "/"
	m["backslash"] = "\\"
	m["pipe"] = "|"
	m["tilde"] = "~"
	m["plus"] = "+"
	m["asterisk"] = "*"
	m["hash"] = "#"
	m["at"] = "@"
	m["ampersand"] = "&"
	m["equals"] = "="
	m["quote"] = "\""
	m["apostrophe"] = "'"
	m[" leftparenthesis"] = "("
	m[" rightparenthesis"] = ")"
	m["leftsquarebracket"] = "["
	m["rightsquarebracket"] = "]"
	m["braceopen"] = "{"
	m["braceclose"] = "}"
	m["greater-than"] = ">"
	m["less-than"] = "<"
	m["caret"] = "^"
	m["space"] = " "
	m["period"] = "."
	m["_"] = "_"
	return m

func _crop_texture(tex: Texture2D) -> Texture2D:
	"""Crop a 1280x720 character PNG to its visible bounding box."""
	var img := tex.get_image()
	if not img:
		return tex
	img.convert(Image.FORMAT_RGBA8)

	var w: int = img.get_width()
	var h: int = img.get_height()
	var min_x: int = w
	var min_y: int = h
	var max_x: int = 0
	var max_y: int = 0

	for y in range(h):
		for x in range(w):
			var px := img.get_pixel(x, y)
			if px.a > 0.1:
				if x < min_x: min_x = x
				if y < min_y: min_y = y
				if x > max_x: max_x = x
				if y > max_y: max_y = y

	if max_x < min_x or max_y < min_y:
		# Fully transparent — return a small blank texture
		var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		return ImageTexture.create_from_image(blank)

	var bbox_w: int = max_x - min_x + 1
	var bbox_h: int = max_y - min_y + 1
	var cropped := img.get_region(Rect2i(min_x, min_y, bbox_w, bbox_h))
	return ImageTexture.create_from_image(cropped)

func get_char_texture(ch: String, dollar_mode: bool = false) -> Texture2D:
	"""Get the cropped texture for a given character.
	If dollar_mode is true and the character has a dollar variant, return that.
	"""
	if dollar_mode and ch in dollar_textures:
		return dollar_textures[ch]
	return char_textures.get(ch)

func get_char_size(ch: String, dollar_mode: bool = false) -> Vector2:
	"""Get the native pixel size of a character texture."""
	if dollar_mode and ch in dollar_char_sizes:
		return dollar_char_sizes[ch]
	return char_sizes.get(ch, Vector2(DEFAULT_CHAR_W, DEFAULT_CHAR_H))

func get_text_width(text: String, scale: float = 1.0, dollar_mode: bool = false) -> float:
	"""Calculate the total width of text at the given scale."""
	var total: float = 0.0
	for ch in text:
		if ch == "$":
			# The dollar character itself has width; dollar_mode toggling doesn't affect width calc per-char here
			pass
		var size := get_char_size(ch, dollar_mode)
		total += size.x * scale
		total += DEFAULT_CHAR_W * letter_spacing * scale
	return total

func get_text_height(text: String, scale: float = 1.0) -> float:
	"""Get the tallest character height in the text."""
	var max_h: float = 0.0
	for ch in text:
		if ch == "$":
			continue
		var size := get_char_size(ch)
		var h: float = size.y * scale
		if h > max_h:
			max_h = h
	return max_h if max_h > 0 else DEFAULT_CHAR_H * scale

func has_char(ch: String) -> bool:
	"""Check if a character texture exists (either in regular or dollar map)."""
	return ch in char_textures or ch in dollar_textures

func enable_dollar_mode(enabled: bool) -> void:
	"""Enable or disable dollar font mode for '$'-prefixed text segments."""
	_dollar_mode_active = enabled

func is_dollar_mode_active() -> bool:
	return _dollar_mode_active
