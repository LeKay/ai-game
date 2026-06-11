class_name DayOverviewPanel extends CanvasLayer
## Day Overview Panel — shown at each day transition.
## Displays day number, NPC count, hunger consumption, and resource deltas.
## Dismisses via "Nächster Tag" button, resuming the game.
## Per ADR-0003 (InputContext push/pop). Story 008.

const BLOCK_WIDTH  := 72
const BLOCK_HEIGHT := 84
const ICON_SIZE    := 48

const COLOR_BLOCK_BG     := Color("#2a2a2a")
const COLOR_BLOCK_BORDER := Color("#4a4a4a")
const COLOR_QTY_TEXT     := Color("#F0EDE6")
const COLOR_GAIN         := Color("#4CAF50")
const COLOR_LOSS         := Color("#E05555")

@onready var _day_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HeaderRow/DayLabel
@onready var _npc_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HeaderRow/NpcLabel
@onready var _hunger_list: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/SectionsRow/LeftSection/HungerList
@onready var _delta_list: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/SectionsRow/RightSection/DeltaList
@onready var _next_day_btn: Button = $PanelContainer/MarginContainer/VBoxContainer/NextDayButton


func _ready() -> void:
	hide()
	TickSystem.day_transition.connect(_on_day_transition)
	_next_day_btn.pressed.connect(_on_next_day_pressed)


func _on_day_transition(_days: int) -> void:
	if visible:
		return
	_populate()
	show()
	InputContext.push_context(InputContext.Context.UI_ACTIVE)
	_next_day_btn.grab_focus()


func _populate() -> void:
	_day_label.text = "Tag %d" % TickSystem.get_current_day()
	_npc_label.text = "%d Bewohner" % NPCSystem.get_npc_count()
	_fill_item_grid(_hunger_list, DayLedger.get_last_hunger_consumed(), false)
	_fill_item_grid(_delta_list, DayLedger.get_last_day_deltas(), true)


func _fill_item_grid(container: VBoxContainer, data: Dictionary, show_sign: bool) -> void:
	for child in container.get_children():
		child.queue_free()
	if data.is_empty():
		var lbl := Label.new()
		lbl.text = "Keine Änderungen" if show_sign else "Keine Nahrung verbraucht"
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.modulate = Color("#A8A49C")
		container.add_child(lbl)
		return
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	container.add_child(flow)
	for resource_id: StringName in data:
		flow.add_child(_make_item_block(resource_id, data[resource_id], show_sign))


func _make_item_block(resource_id: StringName, quantity: int, show_sign: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(BLOCK_WIDTH, BLOCK_HEIGHT)
	panel.mouse_filter        = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color            = COLOR_BLOCK_BG
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	if show_sign:
		style.border_color = COLOR_GAIN if quantity >= 0 else COLOR_LOSS
	else:
		style.border_color = COLOR_BLOCK_BORDER
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var icon_container := Control.new()
	icon_container.custom_minimum_size   = Vector2(ICON_SIZE, ICON_SIZE)
	icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_container.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_container)

	var icon_lbl := Label.new()
	icon_lbl.text                = _resource_icon(resource_id)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_lbl.add_theme_font_size_override("font_size", 28)
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon_lbl)

	var qty_lbl := Label.new()
	if show_sign:
		var prefix := "+" if quantity >= 0 else ""
		qty_lbl.text = "%s%d" % [prefix, quantity]
		qty_lbl.add_theme_color_override("font_color", COLOR_GAIN if quantity >= 0 else COLOR_LOSS)
	else:
		qty_lbl.text = "×%d" % quantity
		qty_lbl.add_theme_color_override("font_color", COLOR_QTY_TEXT)
	qty_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	qty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qty_lbl.add_theme_font_size_override("font_size", 14)
	qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(qty_lbl)

	return panel


func _resource_icon(resource_id: StringName) -> String:
	match resource_id:
		&"wood":  return "🪵"
		&"stone": return "🪨"
		&"berry": return "🫐"
		&"fiber": return "🌿"
		&"tool":  return "🪓"
		_:        return "📦"


func _on_next_day_pressed() -> void:
	hide()
	InputContext.pop_context()
	TickSystem.set_pause(false)
