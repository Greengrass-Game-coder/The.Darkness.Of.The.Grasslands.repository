class_name ChatLayer
extends CanvasLayer

## Chat panel with message history and admin command input.
## Parses "G " prefix for admin commands.
## Visible in both lobby and game map.
## Features: hover-to-show, auto-font-fit, movement-blocking when typing,
##           reserved username tag colors, punctuation highlighting.
##           Uses _root_control (Control) for modulate since CanvasLayer has none.

signal chat_sent(text: String, is_admin: bool)
signal chat_opened()
signal chat_closed()

@export var panel_position: Vector2 = Vector2(20, 60)
@export var panel_size: Vector2 = Vector2(420, 280)
@export var input_position: Vector2 = Vector2(20, 345)
@export var input_size: Vector2 = Vector2(420, 36)
@export var max_messages: int = 50

# Reserved username tag colors (lowercase keys)
const TAG_COLORS: Dictionary = {
	"prograss": Color(0, 0, 0, 1),       # Black (oreo)
	"orange guy": Color(1.0, 0.55, 0.0, 1),
	"juangoat": Color(1.0, 0.5, 0.3, 1),
	"charon": Color(0.3, 0.0, 0.5, 1),  # Dark purple (co-owner)
}

var _root_control: Control = null  # Wrapper Control with modulate (CanvasLayer has no modulate)
var _message_container: VBoxContainer = null
var _chat_input: LineEdit = null
var _is_open: bool = false
var _messages: Array[String] = []
var _hover_timer: float = 0.0
var _hover_active: bool = false


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_build_ui()


func _process(_delta: float) -> void:
	if _is_open:
		return  # Manually open — don't auto-hide
	
	# Hover detection: show when mouse is over the chat area
	var viewport: Viewport = get_viewport()
	var mouse_pos: Vector2 = viewport.get_mouse_position() if viewport else Vector2()
	var chat_rect: Rect2 = Rect2(panel_position - Vector2(10, 10), panel_size + Vector2(20, 70))
	var over: bool = chat_rect.has_point(mouse_pos)
	
	if over and not _hover_active:
		_hover_active = true
		_hover_timer = 0.0
		show()
		_chat_input.editable = false  # Show but don't allow typing yet
		if is_instance_valid(_root_control):
			_root_control.modulate = Color(0.6, 0.6, 0.6, 0.4)  # Dim when hover-only
	elif not over and _hover_active:
		_hover_active = false
		if not _is_open:
			hide()


func _build_ui() -> void:
	# Root Control wrapper (CanvasLayer has no modulate, so we need a child Control for dimming)
	var root := Control.new()
	root.name = "ChatRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root_control = root
	
	# Background panel
	var bg := ColorRect.new()
	bg.name = "ChatBg"
	bg.position = panel_position
	bg.size = panel_size
	bg.color = Color(0, 0, 0, 0.6)
	root.add_child(bg)
	
	# Scroll container for messages
	var scroll := ScrollContainer.new()
	scroll.name = "ChatScroll"
	scroll.position = panel_position + Vector2(4, 4)
	scroll.size = panel_size - Vector2(8, 8)
	root.add_child(scroll)
	
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
	root.add_child(input)
	_chat_input = input
	
	# Make the input clickable to open chat
	input.mouse_entered.connect(_on_input_mouse_entered)
	
	hide()


func _on_input_mouse_entered() -> void:
	# If chat is not open but we're in hover mode, clicking the input opens chat
	pass


func _input(event: InputEvent) -> void:
	"""Use _input() to catch T/Slash BEFORE GUI/shortcut pipeline consumes them.
	
	T is bound to 'ability_4' action, which gets consumed by the engine's
	input processing before _unhandled_input would see it. By using _input(),
	we catch the raw key event at the earliest stage."""
	if event is InputEventKey and event.pressed and not event.echo:
		if _is_open:
			# Chat is open — absorb ALL keyboard input to prevent game movement
			if event.keycode == KEY_ESCAPE:
				_close_chat()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_T or event.keycode == KEY_SLASH:
			# Open chat
			_open_chat()
			if event.keycode == KEY_SLASH:
				_chat_input.text = "/"
			get_viewport().set_input_as_handled()


func _open_chat() -> void:
	_is_open = true
	show()
	if is_instance_valid(_root_control):
		_root_control.modulate = Color(1, 1, 1, 1)  # Full brightness when typing
	_chat_input.editable = true
	_chat_input.grab_focus()
	chat_opened.emit()


func _close_chat() -> void:
	_is_open = false
	_chat_input.editable = false
	_chat_input.text = ""
	_chat_input.release_focus()
	chat_closed.emit()
	# If mouse is still hovering, stay visible but dimmed
	var viewport: Viewport = get_viewport()
	var mouse_pos: Vector2 = viewport.get_mouse_position() if viewport else Vector2(-999, -999)
	var chat_rect: Rect2 = Rect2(panel_position - Vector2(10, 10), panel_size + Vector2(20, 70))
	if not chat_rect.has_point(mouse_pos):
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


func _get_sender_color(sender: String) -> Color:
	"""Get tag color for a sender name. Returns white if not reserved."""
	var lower: String = sender.to_lower()
	if TAG_COLORS.has(lower):
		return TAG_COLORS[lower]
	return Color(0.9, 0.9, 0.9, 1)


func _rebuild_messages() -> void:
	"""Clear and rebuild all message labels."""
	if not is_instance_valid(_message_container):
		return
	
	# Clear existing children
	for child: Node in _message_container.get_children():
		child.queue_free()
	
	# Add each message
	for msg: String in _messages:
		var label := BitmapLabel.new()
		label.label_text = msg
		label.font_scale = 0.12
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size.y = 28
		
		# Determine sender color for tag formatting
		if msg.begins_with("["):
			var close_bracket: int = msg.find("]")
			if close_bracket > 0:
				var sender: String = msg.substr(1, close_bracket - 1)
				var sender_lower: String = sender.to_lower()
				if TAG_COLORS.has(sender_lower):
					label.font_color = TAG_COLORS[sender_lower]
					# Charon gets a spacy ✦ prefix in chat
					if sender_lower == "charon":
						var inner: String = msg.substr(close_bracket + 1).strip_edges()
						label.label_text = msg.substr(0, close_bracket + 1) + " ✦" + inner
				else:
					label.font_color = Color(0.9, 0.9, 0.9, 1)
			else:
				label.font_color = Color(0.9, 0.9, 0.9, 1)
		elif msg.begins_with("***"):
			label.font_color = Color(0.5, 0.5, 0.5, 1)
		else:
			label.font_color = Color(0.9, 0.9, 0.9, 1)
		
		_message_container.add_child(label)
	
	# Auto-scroll to bottom
	var scroll: ScrollContainer = _root_control.get_node_or_null("ChatScroll") if _root_control else null
	if scroll:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
