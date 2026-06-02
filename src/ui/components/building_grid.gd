class_name BuildingGrid extends VBoxContainer
## Reusable building selection grid — one block per buildable type.
## Feed via populate(). Emits building_selected(building_type) on left-click.

signal building_selected(building_type: int)

const BLOCK_WIDTH  := 88
const BLOCK_HEIGHT := 84
const BLOCK_GAP    := 8
const ICON_SIZE    := 48

const COLOR_BLOCK_BG       := Color("#2a2a2a")
const COLOR_BLOCK_BORDER   := Color("#4a4a4a")
const COLOR_HOVER_BORDER   := Color("#A8A49C")
const COLOR_NAME_TEXT      := Color("#F0EDE6")
const COLOR_DISABLED_BG    := Color("#1a1a1a")
const COLOR_DISABLED_BORDER := Color("#2e2e2e")
const DISABLED_ALPHA       := 0.5

var _flow: HFlowContainer
var _empty_label: Label


func _ready() -> void:
	_flow = HFlowContainer.new()
	_flow.name = "BuildingFlow"
	_flow.add_theme_constant_override("h_separation", BLOCK_GAP)
	_flow.add_theme_constant_override("v_separation", BLOCK_GAP)
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_flow)

	_empty_label = Label.new()
	_empty_label.name                 = "EmptyLabel"
	_empty_label.text                 = "No buildings available"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.visible = false
	add_child(_empty_label)


## Replaces all blocks with a fresh render of `buildings`.
## Each entry must have keys: building_type (int), display_name (String).
func populate(buildings: Array[Dictionary]) -> void:
	for child in _flow.get_children():
		child.queue_free()

	if buildings.is_empty():
		_flow.visible        = false
		_empty_label.visible = true
		return

	_flow.visible        = true
	_empty_label.visible = false

	for entry: Dictionary in buildings:
		_flow.add_child(_make_block(
			entry[&"building_type"],
			entry[&"display_name"],
			entry.get(&"can_afford", true),
			entry.get(&"cost", {}),
			entry.get(&"available", {}),
			entry.get(&"energy_cost", 0),
			entry.get(&"current_energy", 0),
		))


func _make_block(building_type: int, display_name: String, can_afford: bool, cost: Dictionary, available: Dictionary, energy_cost: int, current_energy: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(BLOCK_WIDTH, BLOCK_HEIGHT)
	panel.mouse_filter        = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color            = COLOR_BLOCK_BG if can_afford else COLOR_DISABLED_BG
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color        = COLOR_BLOCK_BORDER if can_afford else COLOR_DISABLED_BORDER
	panel.add_theme_stylebox_override("panel", style)

	if not can_afford:
		panel.modulate = Color(1.0, 1.0, 1.0, DISABLED_ALPHA)

	panel.tooltip_text = _build_cost_tooltip(cost, available, energy_cost, current_energy)

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
	icon_lbl.text                 = _building_icon(building_type)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_lbl.add_theme_font_size_override("font_size", 28)
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.text                  = display_name
	name_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", COLOR_NAME_TEXT)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	if can_afford:
		panel.mouse_entered.connect(func() -> void: style.border_color = COLOR_HOVER_BORDER)
		panel.mouse_exited.connect(func() -> void:  style.border_color = COLOR_BLOCK_BORDER)
		panel.gui_input.connect(func(event: InputEvent) -> void:
			var mb := event as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				building_selected.emit(building_type)
		)

	return panel


func _build_cost_tooltip(cost: Dictionary, available: Dictionary, energy_cost: int, current_energy: int) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for res_id: StringName in cost:
		var needed: int = cost[res_id]
		var have: int   = available.get(res_id, 0)
		lines.append("%s %d/%d" % [_resource_emoji(res_id), have, needed])
	if energy_cost > 0:
		lines.append("⚡ %d/%d" % [current_energy, energy_cost])
	if lines.is_empty():
		return "Free to place"
	return "\n".join(lines)


func _resource_emoji(res_id: StringName) -> String:
	match res_id:
		&"wood":  return "🪵"
		&"stone": return "🪨"
		&"food":  return "🍖"
		&"iron":  return "⛏️"
	return "📦"


func _building_icon(building_type: int) -> String:
	match building_type:
		BuildingRegistry.BuildingType.STORAGE_AREA:      return "📦"
		BuildingRegistry.BuildingType.STORAGE_BUILDING:  return "🏗️"
		BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE: return "🏠"
		BuildingRegistry.BuildingType.LUMBER_CAMP:       return "🪚"
	return "🏛️"
