class_name PerkChoicePanel extends CanvasLayer
## Standalone level-up perk picker (Perk System, design/perks/perk-catalog.md).
## Technically separate from the Day Overview: its own CanvasLayer, shown on top while the player
## resolves pending level-ups. For each NPC with pending choices it presents 3 large cards; picking
## one applies it (NPCSystem.apply_perk_choice) and advances to the next choice. When none remain it
## hides and emits `resolved`.

## Emitted once every pending perk choice across all NPCs has been resolved.
signal resolved

const CARD_WIDTH  := 240
const CARD_HEIGHT := 320
const CARD_GAP    := 24

const COLOR_BACKDROP    := Color(0.0, 0.0, 0.0, 0.6)
const COLOR_CARD_BG     := Color("#23211C")
const COLOR_CARD_BORDER := Color("#4a4a4a")
const COLOR_CARD_HOVER  := Color("#E8C860")
const COLOR_TITLE       := Color("#E8C860")
const COLOR_TEXT        := Color("#F0EDE6")
const COLOR_TEXT_DIM    := Color("#A8A49C")

var _root: Control
var _header: Label
var _card_row: HBoxContainer

var _current_npc: StringName = &""


func _ready() -> void:
	layer = 12
	add_to_group(&"perk_choice_panel")
	_build_ui()
	_root.visible = false


## Starts resolving all pending perk choices. Call from the Day Overview gate.
func begin() -> void:
	_root.visible = true
	_show_next()


func _show_next() -> void:
	var pending: Array[StringName] = NPCSystem.get_npcs_with_pending_perk_choices()
	if pending.is_empty():
		_finish()
		return
	_current_npc = pending[0]
	var npc: Object = NPCSystem.get_npc_instance(_current_npc)
	if npc == null:
		_finish()
		return
	var cards: Array = PerkRegistry.generate_choices(npc, 3)
	if cards.is_empty():
		# No valid cards (e.g. no perk-eligible goods yet) — skip so the gate cannot soft-lock.
		NPCSystem.skip_perk_choice(_current_npc)
		_show_next()
		return
	_render(NPCSystem.get_npc_display_name(_current_npc), npc.level, cards)


func _render(npc_name: String, level: int, cards: Array) -> void:
	for child in _card_row.get_children():
		child.queue_free()
	var remaining: int = NPCSystem.get_total_pending_perk_choices()
	var job: String = NPCSystem.get_npc_job_name(_current_npc)
	var who: String = "%s (%s)" % [npc_name, job] if job != "" else npc_name
	_header.text = "%s — Level %d: Choose a perk   (remaining: %d)" % [who, level, remaining]
	for card: Dictionary in cards:
		_card_row.add_child(_make_card(card))


func _on_card_chosen(card: Dictionary) -> void:
	NPCSystem.apply_perk_choice(_current_npc, card)
	_show_next()


func _finish() -> void:
	_root.visible = false
	resolved.emit()


# ── UI construction ─────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = COLOR_BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(vbox)

	_header = Label.new()
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_theme_font_size_override("font_size", 20)
	_header.add_theme_color_override("font_color", COLOR_TITLE)
	vbox.add_child(_header)

	_card_row = HBoxContainer.new()
	_card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_row.add_theme_constant_override("separation", CARD_GAP)
	vbox.add_child(_card_row)


func _make_card(card: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_CARD_BG
	style.set_border_width_all(2)
	style.border_color = COLOR_CARD_BORDER
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = str(card.get(&"name", "?"))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", COLOR_TITLE)
	vbox.add_child(name_lbl)

	vbox.add_child(StyleFactory.separator(COLOR_CARD_BORDER))

	# Building binding (resolved early so the description can use the name).
	var building_type: int = int(card.get(&"building_type", -1))

	var desc_lbl := Label.new()
	var desc_text: String = str(card.get(&"desc", ""))
	if building_type != -1:
		desc_text = desc_text.replace("this building type", PerkRegistry.building_type_name(building_type))
	desc_lbl.text = desc_text
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(desc_lbl)
	if building_type != -1:
		var b_box := VBoxContainer.new()
		b_box.alignment = BoxContainer.ALIGNMENT_CENTER
		b_box.add_theme_constant_override("separation", 4)
		b_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(b_box)

		var b_icon := TextureRect.new()
		b_icon.texture = BuildingRegistry.get_building_texture(building_type)
		b_icon.custom_minimum_size = Vector2(64, 64)
		b_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		b_icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b_box.add_child(b_icon)

		var b_lbl := Label.new()
		b_lbl.text = PerkRegistry.building_type_name(building_type)
		b_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b_lbl.add_theme_font_size_override("font_size", 13)
		b_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		b_box.add_child(b_lbl)

	# Bound good (consumed daily, like food).
	var good: StringName = card.get(&"good", &"")
	if good != &"":
		var good_row := HBoxContainer.new()
		good_row.add_theme_constant_override("separation", 6)
		good_row.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(good_row)

		var icon := TextureRect.new()
		icon.texture = ResourceRegistry.get_icon_texture(good, 16)
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		good_row.add_child(icon)

		var good_lbl := Label.new()
		var def: Object = ResourceRegistry.get_definition(good)
		var good_name: String = def.display_name if def != null else str(good)
		good_lbl.text = "Requires: %s/day" % good_name
		good_lbl.add_theme_font_size_override("font_size", 13)
		good_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		good_row.add_child(good_lbl)

	panel.mouse_entered.connect(func() -> void: style.border_color = COLOR_CARD_HOVER)
	panel.mouse_exited.connect(func() -> void:  style.border_color = COLOR_CARD_BORDER)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_card_chosen(card)
	)
	return panel
