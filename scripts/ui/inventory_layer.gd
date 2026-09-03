class_name InventoryLayer
extends Control

signal inventory_closed()

enum Tab { KILLERS, SURVIVORS }

# Character card element positions — editable in inspector
@export var card_icon_pos: Vector2 = Vector2(20, 30)
@export var card_name_pos: Vector2 = Vector2(80, 310)
@export var card_status_pos: Vector2 = Vector2(90, 360)

@onready var _ui_layer: CanvasLayer = $UILayer
@onready var panel: Control = $UILayer/Panel
@onready var close_button: Button = $UILayer/Panel/CloseButton
@onready var tab_killers: Button = $UILayer/Panel/TabButtons/KillersTab
@onready var tab_survivors: Button = $UILayer/Panel/TabButtons/SurvivorsTab
@onready var character_container: Control = $UILayer/Panel/CharacterContainer

var _current_tab: Tab = Tab.KILLERS


func _sync_visibility() -> void:
	if is_instance_valid(_ui_layer):
		_ui_layer.visible = visible

func _ready() -> void:
	hide()
	_sync_visibility()
	_setup_signals()
	_switch_tab(Tab.KILLERS)

func open() -> void:
	show()
	_sync_visibility()

func close() -> void:
	visible = false
	_sync_visibility()
	inventory_closed.emit()


func _setup_signals() -> void:
	close_button.pressed.connect(close)
	tab_killers.pressed.connect(func(): _switch_tab(Tab.KILLERS))
	tab_survivors.pressed.connect(func(): _switch_tab(Tab.SURVIVORS))


func _switch_tab(tab: Tab) -> void:
	_current_tab = tab
	tab_killers.disabled = (tab == Tab.KILLERS)
	tab_survivors.disabled = (tab == Tab.SURVIVORS)
	_build_character_card()


func _build_character_card() -> void:
	for c in character_container.get_children():
		c.queue_free()

	# Data-driven from the catalog so every owned/unowned character shows up and
	# the equipped one is highlighted.
	var kind: String = "killer" if _current_tab == Tab.KILLERS else "survivor"
	for name_text: String in GameState.CHARACTER_CATALOG:
		var def: Dictionary = GameState.CHARACTER_CATALOG[name_text]
		if def.get("kind", "") != kind:
			continue
		_add_character_card(name_text, def.get("icon", ""), kind)


func _add_character_card(name_text: String, icon_path: String, kind: String) -> void:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(300, 450)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Bigger icon
	var icon := TextureRect.new()
	icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(260, 260)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.position = card_icon_pos
	card.add_child(icon)

	# Name label (BitmapLabel)
	var name_lbl := BitmapLabel.new()
	name_lbl.label_text = name_text
	name_lbl.font_scale = 0.18
	name_lbl.font_color = Color(1, 1, 1, 1)
	name_lbl.position = card_name_pos
	name_lbl.size = Vector2(260, 30)
	card.add_child(name_lbl)

	var owned: bool = GameState.is_character_owned(kind, name_text)
	var equipped: bool = GameState.get_equipped_character(kind) == name_text

	# Status label — LOCKED / OWNED / EQUIPPED
	var status_lbl := BitmapLabel.new()
	status_lbl.font_scale = 0.14
	status_lbl.position = card_status_pos
	status_lbl.size = Vector2(260, 24)
	if not owned:
		status_lbl.label_text = "LOCKED — BUY IN SHOP"
		status_lbl.font_color = Color(0.6, 0.6, 0.6, 1)
		icon.modulate = Color(0.4, 0.4, 0.4, 1)
	elif equipped:
		status_lbl.label_text = "EQUIPPED"
		status_lbl.font_color = Color(0.5, 1, 0.5, 1)
	else:
		status_lbl.label_text = "OWNED"
		status_lbl.font_color = Color(1, 1, 1, 1)
	card.add_child(status_lbl)

	# SKINS button — opens the LMS character/skin browser for this character
	var skins_btn := Button.new()
	skins_btn.name = "SkinsBtn"
	skins_btn.text = "SKINS"
	skins_btn.position = card_status_pos + Vector2(0, 34)
	skins_btn.size = Vector2(120, 30)
	skins_btn.pressed.connect(_open_lms_linking.bind(name_text))
	card.add_child(skins_btn)

	# EQUIP button — only for owned characters that aren't already equipped
	if owned and not equipped:
		var equip_btn := Button.new()
		equip_btn.name = "EquipBtn"
		equip_btn.text = "EQUIP"
		equip_btn.position = card_status_pos + Vector2(0, 70)
		equip_btn.size = Vector2(140, 34)
		equip_btn.pressed.connect(_equip_character.bind(kind, name_text))
		card.add_child(equip_btn)

	character_container.add_child(card)


func _equip_character(kind: String, name_text: String) -> void:
	"""Equip a character and persist the choice."""
	if GameState.equip_character(kind, name_text):
		if SaveManager and SaveManager.has_method("autosave"):
			SaveManager.autosave(GameState.logged_in_username)
		_build_character_card()


func _open_lms_linking(character_name: String) -> void:
	"""Open the LMS Linking character/skin browser for the given character controller."""
	var existing := get_node_or_null("LmsLinkingPanel")
	if existing:
		existing.free()
	var lms := LmsLinking.new()
	lms.name = "LmsLinkingPanel"
	add_child(lms)
	lms.open(character_name)
