class_name InventoryLayer
extends Control

signal inventory_closed()

enum Tab { KILLERS, SURVIVORS, DETAILS, SKINS, SOUND_PACKS }

@onready var _ui_layer: CanvasLayer = $UILayer
@onready var panel: Control = $UILayer/Panel
@onready var close_button: Button = $UILayer/Panel/CloseButton
@onready var tab_killers: Button = $UILayer/Panel/TabButtons/KillersTab
@onready var tab_survivors: Button = $UILayer/Panel/TabButtons/SurvivorsTab
@onready var character_container: ScrollContainer = $UILayer/Panel/CharacterContainer
@onready var _card_list: VBoxContainer = $UILayer/Panel/CharacterContainer/CardList

var _current_tab: Tab = Tab.KILLERS
var _side_panel: Control = null
var _side_icon: TextureRect = null
var _side_name: BitmapLabel = null
var _side_status: BitmapLabel = null
var _side_buttons: VBoxContainer = null
var _selected_name: String = ""
var _selected_kind: String = ""
var _selected_def: Dictionary = {}
var _side_open: bool = false
var _side_tween: Tween = null
var _details_tab: Button = null
var _skins_tab: Button = null
var _packs_tab: Button = null
var _content_view: Control = null


func _sync_visibility() -> void:
	if is_instance_valid(_ui_layer):
		_ui_layer.visible = visible

func _ready() -> void:
	if has_node("UILayer/Panel/Background"):
		SubtleMotion.attach($UILayer/Panel/Background, SubtleMotion.Mode.BREATHE, 0.02, 0.8, 0.5)
	hide()
	_sync_visibility()
	_setup_signals()
	_create_side_panel()
	_switch_tab(Tab.KILLERS)

func open() -> void:
	show()
	_sync_visibility()
	_close_side_panel(true)

func close() -> void:
	visible = false
	_sync_visibility()
	_close_side_panel(true)
	inventory_closed.emit()


func _setup_signals() -> void:
	close_button.pressed.connect(close)
	tab_killers.pressed.connect(func(): _switch_tab(Tab.KILLERS))
	tab_survivors.pressed.connect(func(): _switch_tab(Tab.SURVIVORS))
	_create_extra_tabs()


func _switch_tab(tab: Tab) -> void:
	_current_tab = tab
	# Keep every tab clickable; the active one is shown by its colour.
	_set_tab_active(tab_killers, tab == Tab.KILLERS, Color(1, 0.3, 0.3, 1))
	_set_tab_active(tab_survivors, tab == Tab.SURVIVORS, Color(0.3, 1, 0.3, 1))
	if _details_tab:
		_set_tab_active(_details_tab, tab == Tab.DETAILS, Color(0.8, 0.8, 1, 1))
	if _skins_tab:
		_set_tab_active(_skins_tab, tab == Tab.SKINS, Color(1, 0.8, 1, 1))
	if _packs_tab:
		_set_tab_active(_packs_tab, tab == Tab.SOUND_PACKS, Color(1, 1, 0.6, 1))
	# Keep the side panel open (icon + equip/buy) while viewing DETAILS/SKINS.
	if tab == Tab.KILLERS or tab == Tab.SURVIVORS:
		_close_side_panel(true)
	if tab == Tab.DETAILS:
		_show_details_tab()
	elif tab == Tab.SKINS:
		_show_skins_tab()
	elif tab == Tab.SOUND_PACKS:
		_show_packs_tab()
	else:
		_show_character_list()


func _create_extra_tabs() -> void:
	var tab_bar: HBoxContainer = $UILayer/Panel/TabButtons
	_packs_tab = _make_top_tab("SOUND PACKS", Color(1, 1, 0.6, 1))
	_packs_tab.pressed.connect(func(): _switch_tab(Tab.SOUND_PACKS))
	tab_bar.add_child(_packs_tab)
	_content_view = Control.new()
	_content_view.name = "ContentView"
	_content_view.position = Vector2(140, 140)
	_content_view.size = Vector2(1000, 520)
	$UILayer/Panel.add_child(_content_view)
	_content_view.visible = false


func _set_tab_active(btn: Button, active: bool, color: Color) -> void:
	btn.disabled = false
	btn.add_theme_color_override("font_color", color if active else Color(0.55, 0.55, 0.6, 1))


func _make_top_tab(label: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(250, 40)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_font_size_override("font_size", 18)
	return btn


func _show_character_list() -> void:
	character_container.visible = true
	if _content_view:
		_content_view.visible = false
	_build_character_cards()


func _show_details_tab() -> void:
	character_container.visible = false
	if _content_view:
		_content_view.visible = true
	_build_details_view()


func _show_skins_tab() -> void:
	character_container.visible = false
	if _content_view:
		_content_view.visible = true
	_build_skins_view()


func _show_placeholder(msg: String) -> void:
	if not _content_view:
		return
	for c in _content_view.get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.size = _content_view.size
	bg.color = Color(0.05, 0.05, 0.08, 0.92)
	_content_view.add_child(bg)
	var lbl := Label.new()
	lbl.text = msg
	lbl.position = Vector2(24, 200)
	lbl.size = Vector2(_content_view.size.x - 48, 40)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	lbl.add_theme_font_size_override("font_size", 16)
	_content_view.add_child(lbl)


func _build_details_view() -> void:
	if not _content_view:
		return
	for c in _content_view.get_children():
		c.queue_free()
	var def: Dictionary = _selected_def
	if def.is_empty() or _selected_name.is_empty():
		_show_placeholder("Select a character from the list to see details.")
		return
	var name_text: String = _selected_name
	var kind: String = _selected_kind
	var bg := ColorRect.new()
	bg.size = _content_view.size
	bg.color = Color(0.05, 0.05, 0.08, 0.92)
	_content_view.add_child(bg)
	var y: float = 12.0
	var title := BitmapLabel.new()
	title.label_text = "%s (%s)" % [name_text, kind.capitalize()]
	title.font_scale = 0.18
	title.font_color = Color(1, 0.9, 0.3, 1)
	title.position = Vector2(16, y)
	title.size = Vector2(_content_view.size.x - 32, 26)
	_content_view.add_child(title)
	y += 32
	var cost: int = int(def.get("cost", 0))
	var owned: bool = GameState.is_character_owned(kind, name_text)
	var value := BitmapLabel.new()
	value.label_text = "COST: $%d  |  YOUR GOLD: $%d" % [cost, GameState.player_money]
	value.font_scale = 0.11
	value.font_color = Color(0.5, 1, 0.5, 1) if owned else Color(1, 0.85, 0.2, 1)
	value.position = Vector2(16, y)
	value.size = Vector2(_content_view.size.x - 32, 20)
	_content_view.add_child(value)
	y += 24
	var exp_lbl := BitmapLabel.new()
	exp_lbl.label_text = "CHARACTER EXP: %d" % GameState.get_character_exp(name_text)
	exp_lbl.font_scale = 0.11
	exp_lbl.font_color = Color(0.6, 0.9, 1, 1)
	exp_lbl.position = Vector2(16, y)
	exp_lbl.size = Vector2(_content_view.size.x - 32, 20)
	_content_view.add_child(exp_lbl)
	y += 24
	var sep := ColorRect.new()
	sep.position = Vector2(16, y)
	sep.size = Vector2(_content_view.size.x - 32, 1)
	sep.color = Color(1, 1, 1, 0.15)
	_content_view.add_child(sep)
	y += 10
	var stats_header := BitmapLabel.new()
	stats_header.label_text = "STATS"
	stats_header.font_scale = 0.13
	stats_header.font_color = Color(0.7, 0.9, 1, 1)
	stats_header.position = Vector2(16, y)
	stats_header.size = Vector2(_content_view.size.x - 32, 20)
	_content_view.add_child(stats_header)
	y += 20
	var stats: Dictionary = def.get("stats", {})
	for stat_name: String in stats:
		var stat_lbl := Label.new()
		stat_lbl.text = "  %s:  %s" % [stat_name, stats[stat_name]]
		stat_lbl.position = Vector2(16, y)
		stat_lbl.size = Vector2(_content_view.size.x - 32, 16)
		stat_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
		stat_lbl.add_theme_font_size_override("font_size", 11)
		_content_view.add_child(stat_lbl)
		y += 16
	y += 4
	var ab_header := BitmapLabel.new()
	ab_header.label_text = "ABILITIES"
	ab_header.font_scale = 0.13
	ab_header.font_color = Color(0.7, 0.9, 1, 1)
	ab_header.position = Vector2(16, y)
	ab_header.size = Vector2(_content_view.size.x - 32, 20)
	_content_view.add_child(ab_header)
	y += 20
	var abilities: Array = def.get("abilities", [])
	for ab: Dictionary in abilities:
		var ab_name := Label.new()
		ab_name.text = "  " + ab.get("name", "???")
		ab_name.position = Vector2(16, y)
		ab_name.size = Vector2(_content_view.size.x - 32, 15)
		ab_name.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
		ab_name.add_theme_font_size_override("font_size", 11)
		_content_view.add_child(ab_name)
		y += 15
		var ab_desc := Label.new()
		ab_desc.text = "      " + ab.get("desc", "")
		ab_desc.position = Vector2(16, y)
		ab_desc.size = Vector2(_content_view.size.x - 32, 24)
		ab_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ab_desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		ab_desc.add_theme_font_size_override("font_size", 10)
		_content_view.add_child(ab_desc)
		y += 26


func _build_skins_view() -> void:
	if not _content_view:
		return
	for c in _content_view.get_children():
		c.queue_free()
	var name_text: String = _selected_name
	if name_text.is_empty():
		_show_placeholder("Select a character from the list to see skins.")
		return
	var bg := ColorRect.new()
	bg.size = _content_view.size
	bg.color = Color(0.05, 0.05, 0.08, 0.92)
	_content_view.add_child(bg)
	var title := BitmapLabel.new()
	title.label_text = "%s - SKINS" % name_text
	title.font_scale = 0.18
	title.font_color = Color(1, 0.9, 0.3, 1)
	title.position = Vector2(16, 12)
	title.size = Vector2(_content_view.size.x - 32, 26)
	_content_view.add_child(title)
	var skins: Array = _character_skins(name_text)
	var lines: Array[String] = []
	if skins.size() <= 1:
		lines.append("  %s (base)" % name_text)
		lines.append("  No skins yet.")
	else:
		for i in skins.size():
			var tag: String = "(base)" if i == 0 else ""
			lines.append("  - %s %s" % [skins[i], tag])
	var content := Label.new()
	content.text = "\n".join(lines)
	content.position = Vector2(16, 52)
	content.size = Vector2(_content_view.size.x - 32, _content_view.size.y - 70)
	content.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	content.add_theme_font_size_override("font_size", 14)
	_content_view.add_child(content)


func _character_skins(base_name: String) -> Array[String]:
	var skins: Array[String] = [base_name]
	var roots := [
		"res://The Darkness Of The Grasslands assets/Skins/%s/" % base_name,
		"res://The Darkness Of The Grasslands assets/Sprites/%s/Skins/" % base_name,
		"res://The Darkness Of The Grasslands assets/Sprites/%s/skins/" % base_name,
	]
	for root in roots:
		if not DirAccess.dir_exists_absolute(root):
			continue
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with("."):
				skins.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	return skins


# ═══════════════ SIDE PANEL ═══════════════

func _create_side_panel() -> void:
	_side_panel = Control.new()
	_side_panel.name = "SidePanel"
	_side_panel.size = Vector2(280, 520)
	_side_panel.position = Vector2(-280, 80)
	_ui_layer.add_child(_side_panel)

	var side_bg := ColorRect.new()
	side_bg.name = "SideBg"
	side_bg.size = _side_panel.size
	side_bg.color = Color(0.06, 0.06, 0.1, 0.95)
	_side_panel.add_child(side_bg)

	var border := ColorRect.new()
	border.name = "SideBorder"
	border.size = Vector2(3, _side_panel.size.y)
	border.color = Color(1, 0.85, 0.2, 0.7)
	_side_panel.add_child(border)

	var tab := Button.new()
	tab.name = "SideTab"
	tab.text = "▶"
	tab.flat = true
	tab.position = Vector2(280, 0)
	tab.size = Vector2(28, 60)
	tab.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))
	tab.add_theme_font_size_override("font_size", 14)
	tab.pressed.connect(_toggle_side_panel)
	_side_panel.add_child(tab)

	var content_margin: float = 16.0
	var cy: float = 16.0

	_side_icon = TextureRect.new()
	_side_icon.name = "SideIcon"
	_side_icon.custom_minimum_size = Vector2(200, 200)
	_side_icon.size = Vector2(200, 200)
	_side_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_side_icon.position = Vector2(content_margin, cy)
	_side_panel.add_child(_side_icon)
	cy += 208

	_side_name = BitmapLabel.new()
	_side_name.name = "SideName"
	_side_name.font_scale = 0.17
	_side_name.font_color = Color(1, 1, 1, 1)
	_side_name.position = Vector2(content_margin, cy)
	_side_name.size = Vector2(240, 26)
	_side_panel.add_child(_side_name)
	cy += 28

	_side_status = BitmapLabel.new()
	_side_status.name = "SideStatus"
	_side_status.font_scale = 0.11
	_side_status.position = Vector2(content_margin, cy)
	_side_status.size = Vector2(240, 20)
	_side_panel.add_child(_side_status)
	cy += 28

	var sep := ColorRect.new()
	sep.position = Vector2(content_margin, cy)
	sep.size = Vector2(240, 1)
	sep.color = Color(1, 1, 1, 0.15)
	_side_panel.add_child(sep)
	cy += 12

	_side_buttons = VBoxContainer.new()
	_side_buttons.name = "SideButtons"
	_side_buttons.position = Vector2(content_margin, cy)
	_side_buttons.size = Vector2(240, 130)
	_side_buttons.add_theme_constant_override("separation", 6)
	_side_panel.add_child(_side_buttons)


func _populate_side_panel(name_text: String, kind: String, def: Dictionary) -> void:
	_selected_name = name_text
	_selected_kind = kind
	_selected_def = def

	if not _side_panel:
		return

	var icon_path: String = def.get("icon", "")
	if icon_path.is_empty():
		_side_icon.texture = null
	else:
		_side_icon.texture = load(icon_path)

	_side_name.label_text = name_text

	var owned: bool = GameState.is_character_owned(kind, name_text)
	var equipped: bool = GameState.get_equipped_character(kind) == name_text

	if equipped:
		_side_status.label_text = "★ EQUIPPED"
		_side_status.font_color = Color(0.5, 1, 0.5, 1)
	elif owned:
		_side_status.label_text = "OWNED"
		_side_status.font_color = Color(0.5, 1, 0.5, 1)
	else:
		_side_status.label_text = "LOCKED"
		_side_status.font_color = Color(0.6, 0.6, 0.6, 1)

	for c in _side_buttons.get_children():
		c.queue_free()

	var details_btn := _make_side_button("DETAILS")
	details_btn.pressed.connect(func(): _switch_tab(Tab.DETAILS))
	_side_buttons.add_child(details_btn)

	var skins_btn := _make_side_button("SKINS")
	skins_btn.pressed.connect(func(): _switch_tab(Tab.SKINS))
	_side_buttons.add_child(skins_btn)

	if owned and not equipped:
		var equip_btn := _make_side_button("EQUIP")
		equip_btn.pressed.connect(_equip_character.bind(kind, name_text))
		_side_buttons.add_child(equip_btn)

	_open_side_panel()


func _make_side_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(220, 30)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return btn


func _open_side_panel() -> void:
	if _side_open:
		return
	_side_open = true
	if _side_tween and _side_tween.is_valid():
		_side_tween.kill()
	_side_tween = create_tween()
	_side_tween.tween_property(_side_panel, "position:x", 0.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var tab: Button = _side_panel.get_node_or_null("SideTab")
	if tab:
		tab.text = "◀"


func _close_side_panel(instant: bool = false) -> void:
	if not _side_open and instant:
		return
	_side_open = false
	if _side_tween and _side_tween.is_valid():
		_side_tween.kill()
	if instant:
		_side_panel.position.x = -280.0
	else:
		_side_tween = create_tween()
		_side_tween.tween_property(_side_panel, "position:x", -280.0, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	var tab: Button = _side_panel.get_node_or_null("SideTab")
	if tab:
		tab.text = "▶"


func _toggle_side_panel() -> void:
	if _side_open:
		_close_side_panel()
	else:
		_open_side_panel()


# ═══════════════ CHARACTER CARDS ═══════════════

# ═══ SOUND PACKS (buyable audio layers) ═══

func _show_packs_tab() -> void:
	character_container.visible = false
	if _content_view:
		_content_view.visible = true
	_build_packs_view()


func _build_packs_view() -> void:
	if not _content_view:
		return
	for c in _content_view.get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.size = _content_view.size
	bg.color = Color(0.05, 0.05, 0.08, 0.92)
	_content_view.add_child(bg)
	var title := BitmapLabel.new()
	title.label_text = "SOUND PACKS"
	title.font_scale = 0.2
	title.font_color = Color(1, 0.9, 0.3, 1)
	title.position = Vector2(16, 12)
	title.size = Vector2(_content_view.size.x - 32, 28)
	_content_view.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(16, 48)
	scroll.size = Vector2(_content_view.size.x - 32, _content_view.size.y - 64)
	_content_view.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for id: String in GameState.SOUND_PACK_CATALOG:
		var def: Dictionary = GameState.SOUND_PACK_CATALOG[id]
		_add_pack_card(id, def, list)


func _add_pack_card(id: String, def: Dictionary, list: VBoxContainer) -> void:
	var card := Button.new()
	card.custom_minimum_size = Vector2(460, 92)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.clip_contents = true
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(1, 1, 1, 0.1)
	card.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.12, 0.12, 0.18, 0.9)
	hover.border_width_left = 2
	hover.border_width_right = 2
	hover.border_width_top = 2
	hover.border_width_bottom = 2
	hover.border_color = Color(1, 0.85, 0.2, 0.4)
	card.add_theme_stylebox_override("hover", hover)
	var name_lbl := BitmapLabel.new()
	name_lbl.label_text = id
	name_lbl.font_scale = 0.16
	name_lbl.position = Vector2(12, 12)
	name_lbl.size = Vector2(430, 24)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)
	var owned: bool = GameState.is_sound_pack_owned(id)
	var equipped: bool = GameState.get_equipped_sound_pack() == id
	var cost: int = int(def.get("cost", 0))
	var version: int = int(def.get("version", 1))
	var upd: bool = GameState.can_update_sound_pack(id)
	var status := BitmapLabel.new()
	status.font_scale = 0.10
	status.position = Vector2(12, 38)
	status.size = Vector2(430, 16)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if equipped:
		status.label_text = "★ EQUIPPED (v%d)" % version
		status.font_color = Color(0.5, 1, 0.5, 1)
	elif owned and upd:
		status.label_text = "UPDATE AVAILABLE → v%d" % version
		status.font_color = Color(1, 0.85, 0.2, 1)
	elif owned:
		status.label_text = "OWNED (v%d)" % version
		status.font_color = Color(0.5, 1, 0.5, 1)
	else:
		status.label_text = "PRICE: $%d (2 layers)" % cost
		status.font_color = Color(1, 0.85, 0.2, 1)
	card.add_child(status)
	var desc := Label.new()
	desc.text = def.get("description", "")
	desc.position = Vector2(12, 56)
	desc.size = Vector2(430, 30)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 1))
	desc.add_theme_font_size_override("font_size", 10)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc)
	card.pressed.connect(_populate_pack_side.bind(id, def))
	list.add_child(card)


func _populate_pack_side(id: String, def: Dictionary) -> void:
	_selected_name = id
	_selected_kind = "sound_pack"
	_selected_def = def
	if not _side_panel:
		return
	_side_icon.texture = null
	_side_name.label_text = id
	var owned: bool = GameState.is_sound_pack_owned(id)
	var equipped: bool = GameState.get_equipped_sound_pack() == id
	var cost: int = int(def.get("cost", 0))
	var version: int = int(def.get("version", 1))
	var upd: bool = GameState.can_update_sound_pack(id)
	var fee: int = int(def.get("update_cost", 15))
	if equipped:
		_side_status.label_text = "★ EQUIPPED (v%d)" % version
		_side_status.font_color = Color(0.5, 1, 0.5, 1)
	elif owned and upd:
		_side_status.label_text = "UPDATE → v%d" % version
		_side_status.font_color = Color(1, 0.85, 0.2, 1)
	elif owned:
		_side_status.label_text = "OWNED (v%d)" % version
		_side_status.font_color = Color(0.5, 1, 0.5, 1)
	else:
		_side_status.label_text = "PRICE: $%d (2 layers)" % cost
		_side_status.font_color = Color(1, 0.85, 0.2, 1)
	for c in _side_buttons.get_children():
		c.queue_free()
	if equipped:
		if upd:
			var ubtn := _make_side_button("UPDATE — $%d" % fee)
			ubtn.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))
			ubtn.pressed.connect(_update_sound_pack.bind(id))
			_side_buttons.add_child(ubtn)
		var hint := Label.new()
		hint.text = "Equipped on the lobby OST."
		hint.size = Vector2(220, 30)
		hint.add_theme_color_override("font_color", Color(0.5, 1, 0.5, 1))
		_side_buttons.add_child(hint)
		var rm := _make_side_button("REMOVE")
		rm.pressed.connect(_equip_sound_pack.bind(""))
		_side_buttons.add_child(rm)
	elif owned:
		if upd:
			var ubtn2 := _make_side_button("UPDATE — $%d" % fee)
			ubtn2.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))
			ubtn2.pressed.connect(_update_sound_pack.bind(id))
			_side_buttons.add_child(ubtn2)
		var eq := _make_side_button("EQUIP")
		eq.pressed.connect(_equip_sound_pack.bind(id))
		_side_buttons.add_child(eq)
	else:
		var hint2 := Label.new()
		hint2.text = "Not owned \u2014 buy it in\nthe Shop."
		hint2.size = Vector2(220, 40)
		hint2.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		_side_buttons.add_child(hint2)


	_open_side_panel()


func _equip_sound_pack(id: String) -> void:
	if GameState.equip_sound_pack(id):
		if SaveManager and SaveManager.has_method("autosave"):
			SaveManager.autosave(GameState.logged_in_username)
		_build_packs_view()
		if id != "":
			_populate_pack_side(id, GameState.SOUND_PACK_CATALOG[id])


func _update_sound_pack(id: String) -> void:
	var def: Dictionary = GameState.SOUND_PACK_CATALOG.get(id, {})
	if def.is_empty() or not GameState.can_update_sound_pack(id):
		return
	var fee: int = int(def.get("update_cost", 15))
	if GameState.player_money < fee:
		return
	GameState.spend_money(fee)
	GameState.update_sound_pack(id)
	if SaveManager and SaveManager.has_method("autosave"):
		SaveManager.autosave(GameState.logged_in_username)
	_build_packs_view()
	_populate_pack_side(id, def)



	_open_side_panel()


func _build_character_cards() -> void:
	for c in _card_list.get_children():
		c.queue_free()

	var kind: String = "killer" if _current_tab == Tab.KILLERS else "survivor"
	for name_text: String in GameState.CHARACTER_CATALOG:
		var def: Dictionary = GameState.CHARACTER_CATALOG[name_text]
		if def.get("kind", "") != kind:
			continue
		_add_character_card(name_text, def, kind)


func _add_character_card(name_text: String, def: Dictionary, kind: String) -> void:
	var card := Button.new()
	card.custom_minimum_size = Vector2(440, 100)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.clip_contents = true
	card.flat = false

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	normal_style.border_width_left = 2
	normal_style.border_width_right = 2
	normal_style.border_width_top = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = Color(1, 1, 1, 0.1)
	card.add_theme_stylebox_override("normal", normal_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.12, 0.12, 0.18, 0.9)
	hover_style.border_width_left = 2
	hover_style.border_width_right = 2
	hover_style.border_width_top = 2
	hover_style.border_width_bottom = 2
	hover_style.border_color = Color(1, 0.85, 0.2, 0.4)
	card.add_theme_stylebox_override("hover", hover_style)

	var info_x: float = 12.0

	var name_lbl := BitmapLabel.new()
	name_lbl.label_text = name_text
	name_lbl.font_scale = 0.16
	name_lbl.font_color = Color(1, 1, 1, 1)
	name_lbl.position = Vector2(info_x, 12)
	name_lbl.size = Vector2(410, 24)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var owned: bool = GameState.is_character_owned(kind, name_text)
	var _cost: int = int(def.get("cost", 0))
	var equipped: bool = GameState.get_equipped_character(kind) == name_text

	var status_lbl := BitmapLabel.new()
	status_lbl.font_scale = 0.10
	status_lbl.position = Vector2(info_x, 38)
	status_lbl.size = Vector2(410, 16)
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not owned:
		status_lbl.label_text = "LOCKED — BUY IN SHOP"
		status_lbl.font_color = Color(0.6, 0.6, 0.6, 1)
	elif equipped:
		status_lbl.label_text = "★ EQUIPPED"
		status_lbl.font_color = Color(0.5, 1, 0.5, 1)
	else:
		status_lbl.label_text = "OWNED"
		status_lbl.font_color = Color(1, 1, 1, 1)
	card.add_child(status_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = def.get("description", "")
	desc_lbl.position = Vector2(info_x, 56)
	desc_lbl.size = Vector2(410, 32)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 1))
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc_lbl)

	card.pressed.connect(_populate_side_panel.bind(name_text, kind, def))

	_card_list.add_child(card)


# ═══════════════ EQUIP ═══════════════

func _equip_character(kind: String, name_text: String) -> void:
	if GameState.equip_character(kind, name_text):
		if SaveManager and SaveManager.has_method("autosave"):
			SaveManager.autosave(GameState.logged_in_username)
		_build_character_cards()
		_populate_side_panel(name_text, kind, GameState.CHARACTER_CATALOG[name_text])


# ═══════════════ DETAILS POPUP ═══════════════

func _show_details(name_text: String, kind: String, def: Dictionary) -> void:
	var existing := get_node_or_null("DetailsPopup")
	if existing:
		existing.queue_free()

	var popup := Control.new()
	popup.name = "DetailsPopup"
	popup.position = Vector2(40, 40)
	popup.size = Vector2(400, 380)
	add_child(popup)

	var bg := ColorRect.new()
	bg.size = popup.size
	bg.color = Color(0.05, 0.05, 0.08, 0.92)
	popup.add_child(bg)

	var border_style := StyleBoxFlat.new()
	border_style.border_width_left = 2
	border_style.border_width_right = 2
	border_style.border_width_top = 2
	border_style.border_width_bottom = 2
	border_style.border_color = Color(1, 0.85, 0.2, 0.6)
	border_style.bg_color = Color(0, 0, 0, 0)
	popup.add_theme_stylebox_override("panel", border_style)

	var y: float = 10.0

	var title := BitmapLabel.new()
	title.label_text = name_text + " (" + kind.capitalize() + ")"
	title.font_scale = 0.18
	title.font_color = Color(1, 0.9, 0.3, 1)
	title.position = Vector2(14, y)
	title.size = Vector2(370, 26)
	popup.add_child(title)
	y += 30

	var cost: int = int(def.get("cost", 0))
	var owned: bool = GameState.is_character_owned(kind, name_text)
	var equipped: bool = GameState.get_equipped_character(kind) == name_text
	var value_lbl := BitmapLabel.new()
	if equipped:
		value_lbl.label_text = "★ CURRENTLY EQUIPPED"
		value_lbl.font_color = Color(0.5, 1, 0.5, 1)
	elif owned:
		value_lbl.label_text = "OWNED  |  COST: $%d" % cost
		value_lbl.font_color = Color(0.5, 1, 0.5, 1)
	else:
		value_lbl.label_text = "COST: $%d  |  YOUR GOLD: $%d" % [cost, GameState.player_money]
		value_lbl.font_color = Color(1, 0.85, 0.2, 1)
	value_lbl.font_scale = 0.11
	value_lbl.position = Vector2(14, y)
	value_lbl.size = Vector2(370, 20)
	popup.add_child(value_lbl)
	y += 22

	var character_exp: int = GameState.get_character_exp(name_text)
	var exp_lbl := BitmapLabel.new()
	exp_lbl.label_text = "CHARACTER EXP: %d" % character_exp
	exp_lbl.font_scale = 0.11
	exp_lbl.font_color = Color(0.6, 0.9, 1, 1)
	exp_lbl.position = Vector2(14, y)
	exp_lbl.size = Vector2(370, 20)
	popup.add_child(exp_lbl)
	y += 22

	var sep := ColorRect.new()
	sep.position = Vector2(14, y)
	sep.size = Vector2(370, 1)
	sep.color = Color(1, 1, 1, 0.15)
	popup.add_child(sep)
	y += 10

	var stats_header := BitmapLabel.new()
	stats_header.label_text = "STATS"
	stats_header.font_scale = 0.13
	stats_header.font_color = Color(0.7, 0.9, 1, 1)
	stats_header.position = Vector2(14, y)
	stats_header.size = Vector2(370, 20)
	popup.add_child(stats_header)
	y += 20

	var stats: Dictionary = def.get("stats", {})
	for stat_name: String in stats:
		var stat_lbl := Label.new()
		stat_lbl.text = "  %s:  %s" % [stat_name, stats[stat_name]]
		stat_lbl.position = Vector2(14, y)
		stat_lbl.size = Vector2(370, 16)
		stat_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
		stat_lbl.add_theme_font_size_override("font_size", 11)
		popup.add_child(stat_lbl)
		y += 16

	y += 4

	var ab_header := BitmapLabel.new()
	ab_header.label_text = "ABILITIES"
	ab_header.font_scale = 0.13
	ab_header.font_color = Color(0.7, 0.9, 1, 1)
	ab_header.position = Vector2(14, y)
	ab_header.size = Vector2(370, 20)
	popup.add_child(ab_header)
	y += 20

	var abilities: Array = def.get("abilities", [])
	for ab: Dictionary in abilities:
		var ab_name := Label.new()
		ab_name.text = "  " + ab.get("name", "???")
		ab_name.position = Vector2(14, y)
		ab_name.size = Vector2(370, 15)
		ab_name.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
		ab_name.add_theme_font_size_override("font_size", 11)
		popup.add_child(ab_name)
		y += 15

		var ab_desc := Label.new()
		ab_desc.text = "      " + ab.get("desc", "")
		ab_desc.position = Vector2(14, y)
		ab_desc.size = Vector2(370, 24)
		ab_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ab_desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		ab_desc.add_theme_font_size_override("font_size", 10)
		popup.add_child(ab_desc)
		y += 26

	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.position = Vector2(popup.size.x - 100, popup.size.y - 36)
	close_btn.size = Vector2(86, 28)
	close_btn.pressed.connect(popup.queue_free)
	popup.add_child(close_btn)

	var dismiss_area := Button.new()
	dismiss_area.flat = true
	dismiss_area.size = popup.size
	dismiss_area.mouse_filter = Control.MOUSE_FILTER_STOP
	dismiss_area.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	dismiss_area.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	dismiss_area.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	dismiss_area.pressed.connect(popup.queue_free)
	popup.add_child(dismiss_area)
	popup.move_child(dismiss_area, 0)


# ═══════════════ MISC ═══════════════

func _open_lms_linking(character_name: String) -> void:
	var existing := get_node_or_null("LmsLinkingPanel")
	if existing:
		existing.free()
	var lms := LmsLinking.new()
	lms.name = "LmsLinkingPanel"
	add_child(lms)
	lms.open(character_name)
