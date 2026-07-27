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

# Track consumed choices across dialogue sessions: "resource_path|line_idx|choice_text" -> true
var _consumed_choices: Dictionary = {}

const SPEAKER_COLORS: Dictionary = {
	"Narration": Color(0.7, 0.7, 0.7, 1),
	"Lobby": Color(0.8, 0.9, 0.6, 1),
	"Browngrass": Color(0.6, 0.5, 0.3, 1),
	"Lobby Person": Color(0.5, 0.8, 0.9, 1),
}


func _ready() -> void:
	panel.hide()
	choice_container.hide()


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
	
	label.text = display_text
	
	# Check if this line has choices
	if _dl and _dl.has_choices_at(_current_index):
		_waiting_for_choice = true
		_show_choices()
	elif _dl and _dl.get_auto_target_at(_current_index) >= 0:
		# Auto-return: show this line's text, then auto-advance after a brief pause
		var target: int = _dl.get_auto_target_at(_current_index)
		_waiting_for_choice = true
		_auto_advance_pending = true
		# Use a one-shot timer to auto-advance so the text is visible
		var auto_timer: Timer = Timer.new()
		auto_timer.one_shot = true
		auto_timer.wait_time = 1.5
		auto_timer.timeout.connect(func():
			_current_index = target
			_waiting_for_choice = false
			_auto_advance_pending = false
			auto_timer.queue_free()
			_show_line()
		)
		add_child(auto_timer)
		auto_timer.start()
	else:
		_waiting_for_choice = false
		continue_label.show()


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
	if not _dl or not _dl.choices.has(choice_line):
		return true
	var opts: Array = _dl.choices[choice_line]
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
	panel.hide()
	hide()
	dialogue_finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_active or _waiting_for_choice or _auto_advance_pending:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_text_newline"):
		_advance()
		get_viewport().set_input_as_handled()


# Clear all choice buttons
func _clear_choices() -> void:
	for child in choice_container.get_children():
		child.queue_free()
