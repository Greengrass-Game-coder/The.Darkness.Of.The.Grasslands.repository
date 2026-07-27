class_name ChatLayer
extends CanvasLayer

## Chat panel with message history and admin command input.
## Parses "G " prefix for admin commands.
## Visible in both lobby and game map.

signal chat_sent(text: String, is_admin: bool)

@export var panel_position: Vector2 = Vector2(20, 80)
@export var panel_size: Vector2 = Vector2(320, 200)
@export var input_position: Vector2 = Vector2(20, 280)
@export var input_size: Vector2 = Vector2(320, 30)
@export var max_messages: int = 50

var _message_container: VBoxContainer = null
var _chat_input: LineEdit = null
var _is_open: bool = false
var _messages: Array[String] = []


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# Background panel
	var bg := ColorRect.new()
	bg.name = "ChatBg"
	bg.position = panel_position
	bg.size = panel_size
	bg.color = Color(0, 0, 0, 0.6)
	add_child(bg)
	
	# Scroll container for messages
	var scroll := ScrollContainer.new()
	scroll.name = "ChatScroll"
	scroll.position = panel_position + Vector2(4, 4)
	scroll.size = panel_size - Vector2(8, 8)
	add_child(scroll)
	
	# Message container
	var vbox := VBoxContainer.new()
	vbox.name = "MessageContainer"
	vbox.size = scroll.size
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	_message_container = vbox
	
	# Input field
	var input := LineEdit.new()
	input.name = "ChatInput"
	input.position = input_position
	input.size = input_size
	input.placeholder_text = "Press T to chat... | G for admin"
	input.editable = false
	input.text_submitted.connect(_on_text_submitted)
	add_child(input)
	_chat_input = input
	
	hide()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.keycode == KEY_T or event.keycode == KEY_SLASH) and not _is_open:
			# Open chat
			_open_chat()
			if event.keycode == KEY_SLASH:
				_chat_input.text = "/"
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _is_open:
			_close_chat()
			get_viewport().set_input_as_handled()


func _open_chat() -> void:
	_is_open = true
	show()
	_chat_input.editable = true
	_chat_input.grab_focus()


func _close_chat() -> void:
	_is_open = false
	_chat_input.editable = false
	_chat_input.text = ""
	_chat_input.release_focus()
	hide()


func _on_text_submitted(text: String) -> void:
	if text.is_empty():
		_close_chat()
		return
	
	var is_admin_cmd: bool = text.begins_with("G ")
	chat_sent.emit(text, is_admin_cmd)
	
	# Add to local display
	add_message("You", text)
	
	_chat_input.text = ""
	_close_chat()


func add_message(sender: String, text: String) -> void:
	"""Add a message to the chat display."""
	if not is_instance_valid(_message_container):
		return
	
	var msg_text: String = "[%s]: %s" % [sender, text]
	_messages.append(msg_text)
	
	# Trim excess messages
	while _messages.size() > max_messages:
		_messages.pop_front()
	
	# Rebuild all labels
	_rebuild_messages()


func add_system_message(text: String) -> void:
	"""Add a system message (no sender prefix)."""
	if not is_instance_valid(_message_container):
		return
	
	var msg_text: String = "*** %s ***" % text
	_messages.append(msg_text)
	
	while _messages.size() > max_messages:
		_messages.pop_front()
	
	_rebuild_messages()


func _rebuild_messages() -> void:
	"""Clear and rebuild all message labels."""
	if not is_instance_valid(_message_container):
		return
	
	# Clear existing children
	for child: Node in _message_container.get_children():
		child.queue_free()
	
	# Add each message
	for msg: String in _messages:
		var label := Label.new()
		label.text = msg
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_message_container.add_child(label)
	
	# Auto-scroll to bottom
	var scroll: ScrollContainer = get_node_or_null("ChatScroll")
	if scroll:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
