extends Node
## FontManager ----- autoload that loads Font1 PNG characters as cropped textures.
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
	"""Load all font PNGs using a hardcoded file list (works in exported builds)."""
	var name_to_char: Dictionary = _build_name_map()
	var font_files: PackedStringArray = _get_font_files()
	var loaded_count: int = 0
	for fname in font_files:
		var base := fname.trim_prefix("FONT1_").trim_suffix(".png")
		var ch: String = name_to_char.get(base, "")
		if ch.is_empty():
			continue
		var path := FONT_DIR.path_join(fname)
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

func _get_font_files() -> PackedStringArray:
	"""Hardcoded list of font PNG filenames (no DirAccess needed, works in exports)."""
	return PackedStringArray([
		"FONT1_0.png", "FONT1_1.png", "FONT1_2.png", "FONT1_3.png", "FONT1_4.png",
		"FONT1_5.png", "FONT1_6.png", "FONT1_7.png", "FONT1_8.png", "FONT1_9.png",
		"FONT1_A.png", "FONT1_B.png", "FONT1_C.png", "FONT1_D.png", "FONT1_E.png",
		"FONT1_F.png", "FONT1_G.png", "FONT1_H.png", "FONT1_I.png", "FONT1_J.png",
		"FONT1_K.png", "FONT1_L.png", "FONT1_M.png", "FONT1_N.png", "FONT1_O.png",
		"FONT1_P.png", "FONT1_Q.png", "FONT1_R.png", "FONT1_S.png", "FONT1_T.png",
		"FONT1_U.png", "FONT1_V.png", "FONT1_W.png", "FONT1_X.png", "FONT1_Y.png",
		"FONT1_Z.png",
		"FONT1_ampersand.png", "FONT1_apostrophe.png", "FONT1_asterisk.png",
		"FONT1_at.png", "FONT1_backslash.png", "FONT1_caret.png",
		"FONT1_colon.png", "FONT1_comma.png", "FONT1_dollar.png",
		"FONT1_equals.png", "FONT1_exclamation.png", "FONT1_greater-than.png",
		"FONT1_hash.png", "FONT1_hyphen.png",
		"FONT1_left_brace.png", "FONT1_left_bracket.png", "FONT1_left_paren.png",
		"FONT1_less_than.png",
		"FONT1_minus.png",
		"FONT1_percent.png", "FONT1_period.png", "FONT1_pipe.png", "FONT1_plus.png",
		"FONT1_question.png", "FONT1_quote.png",
		"FONT1_right_brace.png", "FONT1_right_bracket.png", "FONT1_right_paren.png",
		"FONT1_semicolon.png", "FONT1_slash.png",
		"FONT1_tilde.png", "FONT1_upside_down_caret.png"
	])

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
	# New files (user-added)
	m["apostrophe"] = "'"
	m["comma"] = ","
	m["greater-than"] = ">"
	m["less_than"] = "<"
	m["quote"] = "\""
	m["upside_down_caret"] = "^"
	# Remaining old symbol mappings
	m["dollar"] = "$"
	m["exclamation"] = "!"
	m["question"] = "?"
	m["colon"] = ":"
	m["semicolon"] = ";"
	m["hyphen"] = "-"
	m["minus"] = "-"
	m["period"] = "."
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
	# Legacy fallbacks (no files, just safety — kept for forward compat)
	m["dash"] = "-"
	m["leftparenthesis"] = "("
	m["rightparenthesis"] = ")"
	m["leftsquarebracket"] = "["
	m["rightsquarebracket"] = "]"
	m["braceopen"] = "{"
	m["braceclose"] = "}"
	m["question mark"] = "?"
	m["underscore"] = "_"
	m["space"] = " "
	m["blank"] = " "
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
	"""Get cropped texture. Lowercase falls back to uppercase."""
	if dollar_mode and ch in dollar_textures:
		return dollar_textures[ch]
	if ch in char_textures:
		return char_textures[ch]
	var upper: String = ch.to_upper()
	if upper != ch and upper in char_textures:
		return char_textures[upper]
	return null

func get_char_size(ch: String, dollar_mode: bool = false) -> Vector2:
	"""Get size. Lowercase falls back to uppercase."""
	if dollar_mode and ch in dollar_char_sizes:
		return dollar_char_sizes[ch]
	if ch in char_sizes:
		return char_sizes[ch]
	var upper: String = ch.to_upper()
	if upper != ch and upper in char_sizes:
		return char_sizes[upper]
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
	var upper: String = ch.to_upper()
	return (upper != ch) and (upper in char_textures)
