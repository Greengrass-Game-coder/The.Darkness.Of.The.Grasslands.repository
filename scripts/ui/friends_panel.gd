class_name FriendsPanel
extends CanvasLayer

## Friend list panel showing friends, incoming requests,
## and an "Add Friend" input for sending requests via username.

signal friends_panel_closed()

@export var panel_position: Vector2 = Vector2(720, 60)
@export var panel_size: Vector2 = Vector2(280, 350)

var _friends_manager: Node = null
var _main_bg: ColorRect = null
# Actually used below — keep this var
var _title_label: Control = null
var _friend_list: VBoxContainer = null
var _add_input: LineEdit = null
var _add_btn: Button = null
var _close_btn: Button = null
var _requests_label: Label = null
var _status_label: Label = null
var _is_open: bool = false


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_friends_manager = get_node("/root/FriendsManager")
	if _friends_manager and _friends_manager.has_signal("friends_loaded"):
		if not _friends_manager.friends_loaded.is_connected(_on_friends_loaded):
			_friends_manager.friends_loaded.connect(_on_friends_loaded)
	_build_ui()
	refresh()
	# Auto-query friends list
	if _friends_manager and _friends_manager.has_method("query_friends"):
		_friends_manager.query_friends()


func _on_friends_loaded(_friends: Array) -> void:
	refresh()


func _build_ui() -> void:
	# Full-screen blocker (click to close)
	var blocker := ColorRect.new()
	blocker.name = "Blocker"
	blocker.color = Color(0, 0, 0, 0)
	blocker.anchors_preset = Control.PRESET_FULL_RECT
	blocker.mouse_filter = Control.MOUSE_FILTER_PASS
	blocker.gui_input.connect(_on_blocker_click)
	add_child(blocker)

	# Panel background
	var bg := ColorRect.new()
	bg.name = "PanelBg"
	bg.position = panel_position
	bg.size = panel_size
	bg.color = Color(0.06, 0.06, 0.1, 0.95)
	add_child(bg)
	_main_bg = bg

	# Title
	var title := Label.new()
	title.name = "Title"
	title.text = "FRIENDS"
	title.position = panel_position + Vector2(8, 8)
	title.size = Vector2(panel_size.x - 50, 28)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)
	_title_label = title

	# Close button
	var close_btn := Button.new()
	close_btn.name = "CloseBtn"
	close_btn.text = "X"
	close_btn.position = panel_position + Vector2(panel_size.x - 32, 6)
	close_btn.size = Vector2(26, 26)
	close_btn.pressed.connect(_on_close)
	add_child(close_btn)
	_close_btn = close_btn

	# Status label
	var st := Label.new()
	st.name = "StatusLabel"
	st.position = panel_position + Vector2(8, 38)
	st.size = Vector2(panel_size.x - 16, 20)
	st.add_theme_color_override("font_color", Color(0.6, 0.6, 0.8, 1))
	st.add_theme_font_size_override("font_size", 11)
	add_child(st)
	_status_label = st

	# Friend list scroll
	var scroll := ScrollContainer.new()
	scroll.name = "FriendScroll"
	scroll.position = panel_position + Vector2(4, 60)
	scroll.size = Vector2(panel_size.x - 8, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "FriendList"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	_friend_list = vbox

	# Requests label
	var rq := Label.new()
	rq.name = "RequestsLabel"
	rq.position = panel_position + Vector2(8, 248)
	rq.size = Vector2(panel_size.x - 16, 18)
	rq.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0, 1))
	rq.add_theme_font_size_override("font_size", 11)
	rq.hide()
	add_child(rq)
	_requests_label = rq

	# Add friend input row
	var inp := LineEdit.new()
	inp.name = "AddInput"
	inp.placeholder_text = "Type username to add..."
	inp.position = panel_position + Vector2(8, 280)
	inp.size = Vector2(panel_size.x - 76, 28)
	add_child(inp)
	_add_input = inp

	var add_btn := Button.new()
	add_btn.name = "AddBtn"
	add_btn.text = "ADD"
	add_btn.position = panel_position + Vector2(panel_size.x - 64, 280)
	add_btn.size = Vector2(56, 28)
	add_btn.pressed.connect(_on_add_friend)
	add_child(add_btn)
	_add_btn = add_btn

	hide()


func _on_blocker_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_close()


func _on_close() -> void:
	hide()
	_is_open = false
	friends_panel_closed.emit()


func open() -> void:
	_is_open = true
	refresh()
	show()


func refresh() -> void:
	"""Reload friends list from FriendsManager and rebuild UI."""
	if not is_instance_valid(_friends_manager):
		_status_label.text = "Friends system not ready"
		return

	# Clear list
	for child in _friend_list.get_children():
		child.queue_free()

	# Show friends from cache (cached_friends is a var, checked via "in" operator)
	var friends: Array = _friends_manager.cached_friends if "cached_friends" in _friends_manager else []
	var count: int = 0
	for f in friends:
		var name_str: String = f.get("display_name", f.get("account_id", "???"))
		var is_online: bool = f.get("is_online", false)

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var dot := ColorRect.new()
		dot.size = Vector2(10, 10)
		dot.color = Color(0, 1, 0, 1) if is_online else Color(0.4, 0.4, 0.4, 1)
		row.add_child(dot)

		var name_label := Label.new()
		name_label.text = name_str
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var remove_btn := Button.new()
		remove_btn.text = "X"
		remove_btn.size = Vector2(20, 20)
		var aid: String = f.get("account_id", "")
		remove_btn.pressed.connect(_on_remove_friend.bind(aid))
		row.add_child(remove_btn)

		_friend_list.add_child(row)
		count += 1

	if count == 0:
		var empty := Label.new()
		empty.text = "No friends yet.\nAdd friends by username!"
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		empty.add_theme_font_size_override("font_size", 11)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_friend_list.add_child(empty)

	# Show incoming requests (pending_incoming is a var, checked via "in" operator)
	if "pending_incoming" in _friends_manager:
		var incoming: Array = _friends_manager.pending_incoming
		if incoming.size() > 0:
			var rq_text: String = "Incoming requests:"
			for r in incoming:
				rq_text += "\n  " + r.get("display_name", "???")
			_requests_label.text = rq_text
			_requests_label.show()
		else:
			_requests_label.hide()

	_status_label.text = "Friends: %d" % count


func _on_add_friend() -> void:
	var friend_name: String = _add_input.text.strip_edges()
	if friend_name.is_empty():
		return
	if _friends_manager and _friends_manager.has_method("send_friend_request"):
		_friends_manager.send_friend_request(friend_name)
	_add_input.text = "Request sent!"
	await get_tree().create_timer(1.5).timeout
	_add_input.text = ""
	_add_input.placeholder_text = "Type username to add..."


func _on_remove_friend(_account_id: String) -> void:
	if _friends_manager and _friends_manager.has_method("remove_friend"):
		_friends_manager.remove_friend(_account_id)
	refresh()
