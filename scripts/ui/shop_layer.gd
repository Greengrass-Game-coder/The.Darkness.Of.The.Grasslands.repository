class_name ShopLayer
extends Control

signal shop_closed()

enum Tab { KILLERS, SURVIVORS }

@onready var _ui_layer: CanvasLayer = $UILayer
@onready var panel: Control = $UILayer/Panel
@onready var background: TextureRect = $UILayer/Panel/Background
@onready var close_button: Button = $UILayer/Panel/CloseButton
@onready var tab_killers: Button = $UILayer/Panel/TabButtons/KillersTab
@onready var tab_survivors: Button = $UILayer/Panel/TabButtons/SurvivorsTab
@onready var character_container: ScrollContainer = $UILayer/Panel/CharacterContainer
@onready var _card_list: VBoxContainer = $UILayer/Panel/CharacterContainer/CardList

var _current_tab: Tab = Tab.KILLERS


func _ready() -> void:
	hide()
	_sync_visibility()
	_setup_signals()
	_switch_tab(Tab.KILLERS)


func open() -> void:
	_play_zoom_animation()
	show()
	_sync_visibility()


func _sync_visibility() -> void:
	if is_instance_valid(_ui_layer):
		_ui_layer.visible = visible

func close() -> void:
	visible = false
	_sync_visibility()
	shop_closed.emit()


func _setup_signals() -> void:
	close_button.pressed.connect(close)
	tab_killers.pressed.connect(func(): _switch_tab(Tab.KILLERS))
	tab_survivors.pressed.connect(func(): _switch_tab(Tab.SURVIVORS))


func _switch_tab(tab: Tab) -> void:
	_current_tab = tab
	tab_killers.disabled = (tab != Tab.KILLERS)
	tab_survivors.disabled = (tab != Tab.SURVIVORS)
	_build_character_cards()


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
	# ── Card container (horizontal layout: icon left, info right) ──
	var card := Panel.new()
	card.custom_minimum_size = Vector2(460, 160)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.clip_contents = true

	# ── Icon (left side) ──
	var icon := TextureRect.new()
	icon.texture = load(def.get("icon", ""))
	icon.custom_minimum_size = Vector2(100, 100)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(20, 30)
	icon.modulate = Color(1, 1, 1, 1)
	card.add_child(icon)

	# ── Info column (right of icon) ──
	var info_x: float = 135.0

	# Name
	var name_lbl := BitmapLabel.new()
	name_lbl.label_text = name_text
	name_lbl.font_scale = 0.17
	name_lbl.font_color = Color(1, 1, 1, 1)
	name_lbl.position = Vector2(info_x, 20)
	name_lbl.size = Vector2(310, 26)
	card.add_child(name_lbl)

	var owned: bool = GameState.is_character_owned(kind, name_text)
	var cost: int = int(def.get("cost", 0))

	# Status / price
	var status_lbl := BitmapLabel.new()
	status_lbl.font_scale = 0.12
	status_lbl.position = Vector2(info_x, 50)
	status_lbl.size = Vector2(310, 20)
	if owned:
		status_lbl.label_text = "OWNED"
		status_lbl.font_color = Color(0.5, 1, 0.5, 1)
	else:
		status_lbl.label_text = "PRICE: $%d" % cost
		status_lbl.font_color = Color(1, 0.85, 0.2, 1)
	card.add_child(status_lbl)

	# Brief description
	var desc_lbl := Label.new()
	desc_lbl.text = def.get("description", "")
	desc_lbl.position = Vector2(info_x, 74)
	desc_lbl.size = Vector2(310, 36)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	desc_lbl.add_theme_font_size_override("font_size", 11)
	card.add_child(desc_lbl)

	# ── Buttons row (below info) ──
	var btn_y: float = 118.0

	# DETAILS button (always visible)
	var details_btn := Button.new()
	details_btn.text = "DETAILS"
	details_btn.position = Vector2(info_x, btn_y)
	details_btn.size = Vector2(90, 28)
	details_btn.pressed.connect(_show_details.bind(name_text, kind, def))
	card.add_child(details_btn)

	# SKINS button
	var skins_btn := Button.new()
	skins_btn.text = "SKINS"
	skins_btn.position = Vector2(info_x + 98, btn_y)
	skins_btn.size = Vector2(90, 28)
	skins_btn.pressed.connect(_open_lms_linking.bind(name_text))
	card.add_child(skins_btn)

	# BUY button (only if not owned)
	if not owned:
		var buy_btn := Button.new()
		buy_btn.text = "BUY — $%d" % cost
		buy_btn.position = Vector2(info_x + 196, btn_y)
		buy_btn.size = Vector2(114, 28)
		buy_btn.pressed.connect(_buy_character.bind(kind, name_text, cost))
		card.add_child(buy_btn)

	_card_list.add_child(card)


# ═══════════════ BUY ═══════════════

func _buy_character(kind: String, name_text: String, cost: int) -> void:
	if GameState.is_character_owned(kind, name_text):
		return
	if cost > 0 and GameState.player_money < cost:
		return
	if cost > 0:
		GameState.spend_money(cost)
	GameState.own_character(kind, name_text)
	if SaveManager and SaveManager.has_method("autosave"):
		SaveManager.autosave(GameState.logged_in_username)
	_build_character_cards()


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

	# Title
	var title := BitmapLabel.new()
	title.label_text = name_text + " (" + kind.capitalize() + ")"
	title.font_scale = 0.18
	title.font_color = Color(1, 0.9, 0.3, 1)
	title.position = Vector2(14, y)
	title.size = Vector2(370, 26)
	popup.add_child(title)
	y += 30

	# Cost / value line
	var cost: int = int(def.get("cost", 0))
	var owned: bool = GameState.is_character_owned(kind, name_text)
	var value_lbl := BitmapLabel.new()
	value_lbl.label_text = "COST: $%d  |  YOUR GOLD: $%d" % [cost, GameState.player_money]
	value_lbl.font_scale = 0.11
	value_lbl.font_color = Color(0.5, 1, 0.5, 1) if owned else Color(1, 0.85, 0.2, 1)
	value_lbl.position = Vector2(14, y)
	value_lbl.size = Vector2(370, 20)
	popup.add_child(value_lbl)
	y += 22

	# EXP for this character
	var character_exp: int = GameState.get_character_exp(name_text)
	var exp_lbl := BitmapLabel.new()
	exp_lbl.label_text = "CHARACTER EXP: %d" % character_exp
	exp_lbl.font_scale = 0.11
	exp_lbl.font_color = Color(0.6, 0.9, 1, 1)
	exp_lbl.position = Vector2(14, y)
	exp_lbl.size = Vector2(370, 20)
	popup.add_child(exp_lbl)
	y += 22

	# Separator
	var sep := ColorRect.new()
	sep.position = Vector2(14, y)
	sep.size = Vector2(370, 1)
	sep.color = Color(1, 1, 1, 0.15)
	popup.add_child(sep)
	y += 10

	# ── Stats ──
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

	# ── Abilities ──
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

	# Close button
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.position = Vector2(popup.size.x - 100, popup.size.y - 36)
	close_btn.size = Vector2(86, 28)
	close_btn.pressed.connect(popup.queue_free)
	popup.add_child(close_btn)

	# Click background to close
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


func _play_zoom_animation() -> void:
	panel.scale = Vector2(0.8, 0.8)
	panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "scale", Vector2(1, 1), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.2)
