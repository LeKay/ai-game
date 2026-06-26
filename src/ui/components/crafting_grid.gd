class_name CraftingGrid extends VBoxContainer
## Reusable crafting recipe grid — one block per craftable recipe.
## Feed via populate(). Emits recipe_selected(recipe_id) on left-click.
## Mirrors BuildingGrid: same block style, tooltip, and disabled-state logic.
## The active recipe block shows a golden progress arc over its icon.

signal recipe_selected(recipe_id: StringName)

const BLOCK_WIDTH  := 88
const BLOCK_HEIGHT := 84
const BLOCK_GAP    := 8
const ICON_SIZE    := 48

const COLOR_BLOCK_BG        := UiPalette.BLOCK_BG
const COLOR_BLOCK_BORDER    := UiPalette.BLOCK_BORDER
const COLOR_HOVER_BORDER    := UiPalette.HOVER_BORDER
const COLOR_NAME_TEXT       := UiPalette.TEXT_PRIMARY
const COLOR_DISABLED_BG     := UiPalette.BLOCK_BG_DISABLED
const COLOR_DISABLED_BORDER := UiPalette.BLOCK_BORDER_DISABLED
const DISABLED_ALPHA        := UiPalette.DISABLED_ALPHA

## Draws a circular progress arc over an icon.
class ProgressRing extends Control:
	var progress: float = 0.0
	const RING_COLOR := Color(1.0, 0.85, 0.3, 0.95)
	const BG_COLOR   := Color(0.1, 0.1, 0.1, 0.55)
	const RING_WIDTH := 4.0

	func set_progress(p: float) -> void:
		progress = clampf(p, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - RING_WIDTH
		draw_arc(center, radius, 0.0, TAU, 64, BG_COLOR, RING_WIDTH, true)
		if progress > 0.001:
			draw_arc(center, radius, -PI * 0.5,
				-PI * 0.5 + TAU * progress, 64, RING_COLOR, RING_WIDTH, true)


var _flow: HFlowContainer
var _empty_label: Label
var _progress_ring: ProgressRing = null


func _ready() -> void:
	_flow = HFlowContainer.new()
	_flow.name = "CraftingFlow"
	_flow.add_theme_constant_override("h_separation", BLOCK_GAP)
	_flow.add_theme_constant_override("v_separation", BLOCK_GAP)
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_flow)

	_empty_label = Label.new()
	_empty_label.name                  = "EmptyLabel"
	_empty_label.text                  = "No recipes available"
	_empty_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.visible = false
	add_child(_empty_label)


## Replaces all blocks with a fresh render of `recipes`.
## Each entry must have keys: recipe_id (StringName), display_name (String),
## can_afford (bool), cost (Dictionary), available (Dictionary),
## energy_cost (int), current_energy (int).
## active_recipe_id: recipe currently being crafted — shows a progress arc.
## craft_progress: [0.0, 1.0] fill for the active recipe's arc.
func populate(recipes: Array[Dictionary], active_recipe_id: StringName = &"",
		craft_progress: float = 0.0) -> void:
	_progress_ring = null
	for child in _flow.get_children():
		child.queue_free()

	if recipes.is_empty():
		_flow.visible        = false
		_empty_label.visible = true
		return

	_flow.visible        = true
	_empty_label.visible = false

	for entry: Dictionary in recipes:
		var rid: StringName = entry[&"recipe_id"]
		var is_active := rid == active_recipe_id and active_recipe_id != &""
		_flow.add_child(_make_block(
			rid,
			entry[&"display_name"],
			entry.get(&"can_afford", true),
			entry.get(&"cost", {}),
			entry.get(&"available", {}),
			entry.get(&"energy_cost", 0),
			entry.get(&"current_energy", 0),
			is_active,
			craft_progress,
		))


## Updates the progress arc on the active recipe block without rebuilding all blocks.
func update_progress(progress: float) -> void:
	if _progress_ring != null and is_instance_valid(_progress_ring):
		_progress_ring.set_progress(progress)


func _make_block(recipe_id: StringName, display_name: String, can_afford: bool,
		cost: Dictionary, available: Dictionary, energy_cost: int, current_energy: int,
		is_active: bool, craft_progress: float) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(BLOCK_WIDTH, BLOCK_HEIGHT)
	panel.mouse_filter        = Control.MOUSE_FILTER_STOP

	var style := StyleFactory.block(
		COLOR_BLOCK_BG if can_afford else COLOR_DISABLED_BG,
		COLOR_BLOCK_BORDER if can_afford else COLOR_DISABLED_BORDER, 1, 0)
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

	var icon_rect := TextureRect.new()
	icon_rect.texture      = ResourceRegistry.get_icon_texture(recipe_id, ICON_SIZE / 2)
	icon_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon_rect)

	if is_active:
		var ring := ProgressRing.new()
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.set_progress(craft_progress)
		icon_container.add_child(ring)
		_progress_ring = ring

	var name_lbl := Label.new()
	name_lbl.text                  = display_name
	name_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", COLOR_NAME_TEXT)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	# Active recipe blocks are not clickable — they are already being crafted.
	if can_afford and not is_active:
		panel.mouse_entered.connect(func() -> void: style.border_color = COLOR_HOVER_BORDER)
		panel.mouse_exited.connect(func() -> void:  style.border_color = COLOR_BLOCK_BORDER)
		panel.gui_input.connect(func(event: InputEvent) -> void:
			var mb := event as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				recipe_selected.emit(recipe_id)
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
		return "Free to craft"
	return "\n".join(lines)


func _resource_emoji(res_id: StringName) -> String:
	return ResourceRegistry.get_glyph(res_id)
