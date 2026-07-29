extends Node
## FontManager — autoload that loads Font1 PNG characters as cropped textures.
## Dollar font ($) is a togglable alternate style meant for match/chat only.

signal fonts_loaded()

var char_textures: Dictionary = {}
var dollar_textures: Dictionary = {}
var char_sizes: Dictionary = {}
var dollar_char_sizes: Dictionary = {}

const FONT_DIR: String = "res://The Darkness Of The Grasslands assets/Fonts/Font1/"
const DEFAULT_CHAR_W: float = 100.0
const DEFAULT_CHAR_H: float = 120.0
var letter_spacing: float = 0.15
var is_ready: bool = false

func _ready() -> void:
	_load_fonts()

func _load_fonts() -> void:
	var dir := DirAccess.open(FONT_DIR)
	if not dir:
		push_error("FontManager: Cannot open font directory: ", FONT_DIR)
		return
	var files := dir.get_files()
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
		var cropped := _crop_texture(tex)
		if not cropped:
			continue
		char_textures[ch] = cropped
		char_sizes[ch] = cropped.get_size()
		loaded_count += 1
		if ch == "$":
			dollar_textures[ch] = cropped
			dollar_char_sizes[ch] = cropped.get_size()
	is_ready = true
	print("FontManager: Loaded ", loaded_count, " character textures")
	fonts_loaded.emit()

func _build_name_map() -> Dictionary:
	"""Build mapping from filename base to character string.
	Matches actual PNG filenames in Font1/ directory."""
	var m: Dictionary = {}
	for ch in ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"]:
		m[ch] = ch
	for ch in ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]:
		m[ch] = ch
	for d in ["0","1","2","3","4","5","6","7","8","9"]:
		m[d] = d
	m["dollar"] = "$"
	m["exclamation"] = "!"
	m["question"] = "?"
	m["colon"] = ":"
	m["colon_alt"] = ":"
	m["semicolon"] = ";"
	m["hyphen"] = "-"
	m["minus"] = "-"
	m["period"] = "."
	m["comma"] = ","
	m["slash"] = "/"
	m["backslash"] = "\\"
	m["left_paren"] = "("
	m["right_paren"] = ")"
	m["left_bracket"] = "["
	m["right_bracket"] = "]"
	m["left_brace"] = "{"
	m["right_brace"] = "}"
	m["pipe"] = "|"
	m["tilde"] = "~"
	m["plus"] = "+"
	m["asterisk"] = "*"
	m["hash"] = "#"
	m["at"] = "@"
	m["ampersand"] = "&"
	m["equals"] = "="
	m["percent"] = "%"
	m["caret"] = "^"
	m["underscore"] = "_"
	m["space"] = " "
	m["blank"] = " "
	m["approx"] = "~"
	m["not_equal"] = "!"
	m["vee"] = "v"
	# Legacy fallbacks
	m["dash"] = "-"
	m["leftparenthesis"] = "("
	m["rightparenthesis"] = ")"
	m["leftsquarebracket"] = "["
	m["rightsquarebracket"] = "]"
	m["braceopen"] = "{"
	m["braceclose"] = "}"
	m["question mark"] = "?"
	m["quote"] = "\""
	m["apostrophe"] = "'"
	m["greater-than"] = ">"
	m["less-than"] = "<"
	return m

func _crop_texture(tex: Texture2D) -> Texture2D:
	"""Crop a character PNG to its visible bounding box."""
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
		var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		return ImageTexture.create_from_image(blank)
	var bbox_w: int = max_x - min_x + 1
	var bbox_h: int = max_y - min_y + 1
	var cropped := img.get_region(Rect2i(min_x, min_y, bbox_w, bbox_h))
	return ImageTexture.create_from_image(cropped)

func get_char_texture(ch: String, dollar_mode: bool = false) -> Texture2D:
	"""Get cropped texture. Uppercase falls back to lowercase."""
	if dollar_mode and ch in dollar_textures:
		return dollar_textures[ch]
	if ch in char_textures:
		return char_textures[ch]
	var lower: String = ch.to_lower()
	if lower != ch and lower in char_textures:
		return char_textures[lower]
	return null

func get_char_size(ch: String, dollar_mode: bool = false) -> Vector2:
	if dollar_mode and ch in dollar_char_sizes:
		return dollar_char_sizes[ch]
	if ch in char_sizes:
		return char_sizes[ch]
	var lower: String = ch.to_lower()
	if lower != ch and lower in char_sizes:
		return char_sizes[lower]
	return Vector2(DEFAULT_CHAR_W, DEFAULT_CHAR_H)

func get_text_width(text: String, scale: float = 1.0, dollar_mode: bool = false) -> float:
	var total: float = 0.0
	for ch in text:
		var size := get_char_size(ch, dollar_mode)
		total += size.x * scale
		total += DEFAULT_CHAR_W * letter_spacing * scale
	return total

func get_text_height(text: String, scale: float = 1.0) -> float:
	var max_h: float = 0.0
	for ch in text:
		var size := get_char_size(ch)
		var h: float = size.y * scale
		if h > max_h:
			max_h = h
	return max_h if max_h > 0 else DEFAULT_CHAR_H * scale

func has_char(ch: String) -> bool:
	if ch in char_textures or ch in dollar_textures:
		return true
	var lower: String = ch.to_lower()
	return (lower != ch) and (lower in char_textures)
