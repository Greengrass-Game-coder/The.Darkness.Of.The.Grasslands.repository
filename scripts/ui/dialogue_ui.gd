class_name DialogueUI
extends CanvasLayer

signal dialogue_finished()

@export var dialogue_resource: Resource

@onready var panel: Panel = $Panel
@onready var speaker_label: Label = $Panel/SpeakerLabel
@onready var label: RichTextLabel = $Panel/RichTextLabel
@onready var continue_label: Label = $Panel/ContinueLabel
@onready var choice_container = $Panel/ChoiceContainer

var _dl: DialogueLine  # current dialogue resource being played
var _lines: Array[String] = []
var _current_index: int = 0
var _is_active: bool = false
var _waiting_for_choice: bool = false
var _auto_advance_pending: bool = false
var _auto_advance_target: int = -1

# Typewriter state: dialogue text reveals one character at a time (playing the
# speaker's blip sound) instead of appearing all at once.
var _typing: bool = false
var _typing_full_text: String = ""
var _typing_visible_chars: int = 0
var _typing_accum: float = 0.0
var _blip_player: AudioStreamPlayer = null
var _blip_streams: Dictionary = {}  # speaker name -> cached loaded AudioStream

# Track consumed choices across dialogue sessions: "resource_path|line_idx|choice_text" -> true
var _consumed_choices: Dictionary = {}

const SPEAKER_COLORS: Dictionary = {
	"Narration": Color(0.7, 0.7, 0.7, 1),
	"Lobby": Color(0.8, 0.9, 0.6, 1),
	"Browngrass": Color(0.6, 0.5, 0.3, 1),
	"Lobby Person": Color(0.5, 0.8, 0.9, 1),
}

# Seconds between each character revealed by the typewriter.
const TYPE_CHAR_INTERVAL: float = 0.045
# Undertale-style pauses: after revealing one of these characters, the typewriter
# waits extra before showing the next letter — so punctuation "breathes."
const CHAR_PAUSE: Dictionary = {
	".": 0.14,
	",": 0.08,
	"!": 0.14,
	"?": 0.14,
	":": 0.06,
	";": 0.06,
	"—": 0.06,
	"…": 0.22,
}
# Current per-character delay; changes dynamically when a special char is hit.
var _typing_current_delay: float = TYPE_CHAR_INTERVAL

# ── Per-speaker dialogue-box border styling ──
# Each speaker gets a distinctive border (width, color, corner shape, shadow)
# so you can tell who's talking just by looking at the box.
const SPEAKER_BORDER_STYLES: Dictionary = {
	"Browngrass": {
		"border_color": Color(0.55, 0.35, 0.15, 1),
		"border_width": 5,
		"corner_radius": 10,
		"bg_color": Color(0.1, 0.07, 0.03, 0.94),
		"shadow_size": 6,
		"text_color": Color(0.92, 0.85, 0.7, 1),
		"speaker_color": Color(0.7, 0.5, 0.2, 1),
	},
	"Evil Potato": {
		"border_color": Color(0.65, 0.15, 0.75, 1),
		"border_width": 5,
		"corner_radius": 2,
		"bg_color": Color(0.07, 0.03, 0.12, 0.94),
		"shadow_size": 8,
		"text_color": Color(0.92, 0.75, 0.95, 1),
		"speaker_color": Color(0.85, 0.35, 0.95, 1),
	},
	"Narration": {
		"border_color": Color(0.35, 0.35, 0.4, 0.5),
		"border_width": 2,
		"corner_radius": 4,
		"bg_color": Color(0.03, 0.03, 0.05, 0.85),
		"shadow_size": 2,
		"text_color": Color(0.7, 0.7, 0.7, 1),
		"speaker_color": Color(0.55, 0.55, 0.55, 1),
	},
	"Lobby": {
		"border_color": Color(0.25, 0.55, 0.15, 1),
		"border_width": 4,
		"corner_radius": 8,
		"bg_color": Color(0.05, 0.1, 0.03, 0.92),
		"shadow_size": 4,
		"text_color": Color(0.82, 0.92, 0.7, 1),
		"speaker_color": Color(0.45, 0.7, 0.25, 1),
	},
}
# Per-speaker "blip" sound path played once per character while typing. Loaded
# lazily (see _apply_speaker_blip) so a not-yet-imported sound just types
# silently instead of breaking the whole dialogue script. Only speakers listed
# here make a sound; everyone else types silently.
const BLIP_PATHS: Dictionary = {
	"Browngrass": "res://The Darkness Of The Grasslands assets/Sound/Lobby/Browngrass_blip_sound.wav",
	"Evil Potato": "res://The Darkness Of The Grasslands assets/Sound/Lobby/mister_evil_potato_blip_sound.wav",
}


func _ready() -> void:
	panel.hide()
	choice_container.hide()
	_blip_player = AudioStreamPlayer.new()
	_blip_player.bus = "SFX"
	add_child(_blip_player)


func _process(delta: float) -> void:
	"""Reveal the current line one character at a time (typewriter)."""
	if not _typing:
		return
	_typing_accum += delta
	if _typing_accum >= _typing_current_delay and _typing_visible_chars < _typing_full_text.length():
		_typing_accum -= _typing_current_delay
		_typing_visible_chars += 1
		label.text = _typing_full_text.substr(0, _typing_visible_chars)
		_play_blip()
		# Set the delay for the NEXT character based on the one we just revealed.
		# Punctuation like . , ! ? pauses the typewriter (Undertale-style).
		if _typing_visible_chars < _typing_full_text.length():
			var just_revealed: String = _typing_full_text[_typing_visible_chars - 1]
			_typing_current_delay = TYPE_CHAR_INTERVAL + CHAR_PAUSE.get(just_revealed, 0.0)
		else:
			_finish_typewriter()
	elif _typing_visible_chars >= _typing_full_text.length():
		_finish_typewriter()


func is_dialogue_active() -> bool:
	return _is_active


func start_dialogue() -> void:
	start_dialogue_with(dialogue_resource)


func start_dialogue_at_line_with(resource: Resource, start_line: int) -> void:
	if _is_active:
		return
	
	if not _setup_dialogue(resource):
		return
	
	if start_line < 0 or start_line >= _lines.size():
		start_line = 0
	
	_is_active = true
	_current_index = start_line
	show()
	panel.show()
	_show_line()


func start_dialogue_with(resource: Resource) -> void:
	if _is_active:
		return
	
	if not _setup_dialogue(resource):
		return
	
	if _lines.is_empty():
		dialogue_finished.emit()
		return
	
	_is_active = true
	_current_index = 0
	show()
	panel.show()
	_show_line()


func _setup_dialogue(resource: Resource) -> bool:
	if resource is DialogueLine:
		_dl = resource as DialogueLine
		_dl.flags = {}  # Reset flags each dialogue session
		_lines = _dl.lines.duplicate()
		# Apply consumed choices from previous sessions
		var rsrc_path: String = resource.resource_path
		for key in _consumed_choices:
			if key.begins_with(rsrc_path + "|"):
				var parts: PackedStringArray = key.split("|")
				if parts.size() >= 3:
					var line_idx: int = int(parts[1])
					var choice_text: String = parts[2]
					if _dl.choices.has(line_idx):
						var opts: Array = _dl.choices[line_idx]
						for opt in opts:
							if opt.get("text", "") == choice_text:
								opt["consumed"] = true
		return true
	else:
		push_error("DialogueUI: invalid dialogue resource")
		return false


func _show_line() -> void:
	if _current_index >= _lines.size():
		_end_dialogue()
		return
	
	continue_label.hide()
	choice_container.hide()
	_clear_choices()
	
	var raw_line: String = _lines[_current_index]
	var speaker_name: String = ""
	var display_text: String = raw_line
	
	if raw_line.begins_with("["):
		var close_bracket: int = raw_line.find("]")
		if close_bracket > 0:
			speaker_name = raw_line.substr(1, close_bracket - 1)
			display_text = raw_line.substr(close_bracket + 1).strip_edges()
			if display_text.begins_with(":") or display_text.begins_with(","):
				display_text = display_text.substr(1).strip_edges()
	
	if speaker_name.is_empty():
		speaker_label.hide()
	else:
		speaker_label.show()
		speaker_label.text = speaker_name
		if SPEAKER_COLORS.has(speaker_name):
			speaker_label.add_theme_color_override("font_color", SPEAKER_COLORS[speaker_name])
		else:
			speaker_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		if speaker_name == "Narration":
			speaker_label.hide()
			label.add_theme_color_override("default_color", Color(0.7, 0.7, 0.7, 1))
		else:
			label.add_theme_color_override("default_color", Color(1, 1, 1, 1))
	
	# ── Per-character panel styling ──
	_apply_speaker_style(speaker_name)
	
	_apply_speaker_blip(speaker_name)
	_start_typewriter(display_text)


func _start_typewriter(text: String) -> void:
	"""Begin revealing `text` one character at a time."""
	_typing_full_text = text
	_typing_visible_chars = 0
	_typing_accum = 0.0
	_typing_current_delay = TYPE_CHAR_INTERVAL
	label.text = ""
	if text.is_empty():
		_typing = false
		_finish_typewriter()
	else:
		_typing = true


func _finish_typewriter() -> void:
	"""Stop typing, show the full line, then reveal the continue prompt/choices."""
	_typing = false
	label.text = _typing_full_text
	_typing_full_text = ""
	
	# Check if this line has choices
	if _dl and _dl.has_choices_at(_current_index):
		_waiting_for_choice = true
		_show_choices()
	elif _dl and _dl.get_auto_target_at(_current_index) >= 0:
		# Auto-return: show this line's text, then jump to the target only when the
		# player presses Space/Enter — never auto-skip, so they have time to read.
		_auto_advance_target = _dl.get_auto_target_at(_current_index)
		_waiting_for_choice = true
		_auto_advance_pending = true
		continue_label.text = "Press %s to continue" % _continue_key_label()
		continue_label.show()
	else:
		_waiting_for_choice = false
		continue_label.text = "Press %s to continue" % _continue_key_label()
		continue_label.show()


func _apply_speaker_blip(speaker: String) -> void:
	"""Set the blip player's stream to the speaker's blip sound, if they have one."""
	if _blip_player == null:
		return
	if BLIP_PATHS.has(speaker):
		if not _blip_streams.has(speaker):
			_blip_streams[speaker] = load(BLIP_PATHS[speaker])
		_blip_player.stream = _blip_streams[speaker]
	else:
		_blip_player.stream = null


func _apply_speaker_style(speaker: String) -> void:
	"""Build a distinctive border + background for the dialogue panel matching
	who is speaking — different border widths, corner shapes, and shadow sizes
	per character so the box itself tells you who's talking."""
	var s: Dictionary = SPEAKER_BORDER_STYLES.get(speaker, {})
	
	# ── Build a StyleBoxFlat with the speaker's border ──
	var sb := StyleBoxFlat.new()
	sb.bg_color = s.get("bg_color", Color(0.06, 0.06, 0.08, 0.92))
	sb.border_width_left   = s.get("border_width", 3)
	sb.border_width_right  = s.get("border_width", 3)
	sb.border_width_top    = s.get("border_width", 3)
	sb.border_width_bottom = s.get("border_width", 3)
	sb.border_color = s.get("border_color", Color(0.4, 0.4, 0.45, 0.8))
	var cr: int = s.get("corner_radius", 6)
	sb.corner_radius_top_left = cr
	sb.corner_radius_top_right = cr
	sb.corner_radius_bottom_left = cr
	sb.corner_radius_bottom_right = cr
	sb.shadow_size = s.get("shadow_size", 4)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_offset = Vector2(2, 3)
	# Give Evil Potato sharp bottom corners for a sinister look.
	if speaker == "Evil Potato":
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.border_width_bottom = s.get("border_width", 5) + 3
	panel.add_theme_stylebox_override("panel", sb)
	
	# ── Text / speaker colors ──
	if s.has("text_color"):
		label.add_theme_color_override("default_color", s["text_color"])
	if s.has("speaker_color"):
		speaker_label.add_theme_color_override("font_color", s["speaker_color"])
	
	# ── "Alive" animation: the box bounces + border briefly glows on each new line ──
	var t := create_tween().set_parallel(true)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(panel, "scale", Vector2(1.02, 1.02), 0.04)
	t.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.1).set_delay(0.04)
	# Flash the border brighter for a moment, then settle back.
	var flash: Color = s.get("border_color", Color.WHITE)
	flash = flash.lightened(0.4)
	sb.border_color = flash
	var settle := create_tween()
	settle.tween_property(sb, "border_color", s.get("border_color", Color.WHITE), 0.3).set_delay(0.08)


func _play_blip() -> void:
	"""Play the speaker's blip once for the just-revealed character."""
	if _blip_player != null and _blip_player.stream != null:
		_blip_player.play()


func _show_choices() -> void:
	var opts: Array = _dl.get_available_choices_at(_current_index)
	if opts.is_empty():
		_advance()
		return
	
	# If only "Bye" remains and all questions are done, end dialogue
	if opts.size() == 1 and opts[0].get("text", "") == "Bye":
		_waiting_for_choice = false
		_end_dialogue()
		return
	
	choice_container.show()
	for opt in opts:
		var btn: Button = Button.new()
		btn.text = opt.get("text", "")
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.custom_minimum_size = Vector2(0, 36)
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_constant_override("minimum_width", 160)
		btn.pressed.connect(_on_choice_selected.bind(opt))
		choice_container.add_child(btn)


func _on_choice_selected(opt: Dictionary) -> void:
	# Mark this choice as consumed (unless it's "Bye")
	var is_bye: bool = opt.get("text", "") == "Bye"
	if _dl and not is_bye:
		var rsrc_path: String = _dl.resource_path
		# Find the line index for this choice
		for line_idx in _dl.choices:
			var opts: Array = _dl.choices[line_idx]
			for o in opts:
				if o.get("text", "") == opt.get("text", "") and o.get("target", -1) == opt.get("target", -1):
					o["consumed"] = true
					var key: String = rsrc_path + "|" + str(line_idx) + "|" + opt.get("text", "")
					_consumed_choices[key] = true
					break
	
	var flag: String = opt.get("set_flag", "")
	if flag != "":
		if _dl:
			_dl.flags[flag] = true
	
	var target: int = opt.get("target", -1)
	if target == -2:
		# Special "end dialogue" target
		_waiting_for_choice = false
		_end_dialogue()
		return
	elif target >= 0:
		_current_index = target
	else:
		_current_index += 1
	_waiting_for_choice = false
	_show_line()


func _advance() -> void:
	_current_index += 1
	_show_line()


# Returns true if all non-"Bye" choices at this line are consumed
func is_all_questions_exhausted_at(choice_line: int) -> bool:
	if _dl:
		return is_all_questions_exhausted_in(_dl, choice_line)
	return true


# Returns true if all non-"Bye" choices at the given line of the given dialogue
# resource are consumed. Unlike is_all_questions_exhausted_at, this does NOT
# depend on the currently-loaded _dl — it checks a specific dialogue resource,
# so a caller can correctly query Browngrass's state even right after a
# different dialogue (e.g. Evil Potato) was played.
func is_all_questions_exhausted_in(dialogue: DialogueLine, choice_line: int) -> bool:
	if not dialogue or not dialogue.choices.has(choice_line):
		return true
	var opts: Array = dialogue.choices[choice_line]
	var non_bye_available := false
	for opt in opts:
		if opt.get("text", "") == "Bye":
			continue  # Skip "Bye" - it's always available
		if not opt.get("consumed", false):
			non_bye_available = true
			break
	return not non_bye_available


func _end_dialogue() -> void:
	_is_active = false
	_waiting_for_choice = false
	_typing = false
	_typing_full_text = ""
	panel.hide()
	hide()
	dialogue_finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_active:
		return
	# While a line is still typing, the first press just reveals the rest of the
	# line instantly (it doesn't skip past it).
	if _typing:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_text_newline"):
			_finish_typewriter()
			get_viewport().set_input_as_handled()
		return
	# Auto-return lines wait for the player to press Space/Enter before jumping
	# to their target line, so the text stays readable.
	if _auto_advance_pending:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_text_newline"):
			_finish_auto_advance()
			get_viewport().set_input_as_handled()
		return
	if _waiting_for_choice:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_text_newline"):
		_advance()
		get_viewport().set_input_as_handled()


func _finish_auto_advance() -> void:
	_auto_advance_pending = false
	var target: int = _auto_advance_target
	_auto_advance_target = -1
	_waiting_for_choice = false
	_current_index = target
	_show_line()


## The continue prompt shows the key that actually advances the dialogue on the
## current device (SPACE on keyboard, A on gamepad, Tap on touch), instead of a
## vague "..." that leaves players guessing what to press.
func _continue_key_label() -> String:
	match InputSystem.current_device:
		"gamepad":
			return "A"
		"touch":
			return "Tap"
		_:
			return "SPACE"


# Clear all choice buttons
func _clear_choices() -> void:
	for child in choice_container.get_children():
		child.queue_free()
