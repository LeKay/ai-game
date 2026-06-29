class_name RecipePickerView extends VBoxContainer
## Inline recipe picker embedded within ProductionSection.
## Shows all available recipes for a building and lets the player select one.
## Does NOT push itself onto the drawer navigation stack — it replaces the
## body_container content inside ProductionSection directly.

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when the player selects a recipe.
## The caller is responsible for calling BuildingRegistry.set_active_recipe().
signal recipe_selected(recipe_id: StringName)

# ── Constants ─────────────────────────────────────────────────────────────────

const COLOR_TEXT_DIM        := Color(0.55, 0.55, 0.60, 1.0)
const COLOR_NAME            := Color(0.70, 0.70, 0.74, 1.0)
const COLOR_BG              := Color(0.14, 0.15, 0.18, 1.0)
const COLOR_BG_HOVER        := Color(0.20, 0.22, 0.27, 1.0)
const COLOR_BG_ACTIVE       := Color(0.18, 0.32, 0.42, 1.0)
const COLOR_BORDER_HOVER    := Color(0.4, 0.6, 0.8, 0.6)
const COLOR_BORDER_ACTIVE   := Color(0.3, 0.7, 1.0, 0.9)

# ── Node refs ─────────────────────────────────────────────────────────────────

var _tile_list: VBoxContainer

# ── State ─────────────────────────────────────────────────────────────────────

var _building_id: String = ""

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	_tile_list = VBoxContainer.new()
	_tile_list.name = "TileList"
	_tile_list.add_theme_constant_override("separation", 4)

	var list_pad := MarginContainer.new()
	list_pad.add_theme_constant_override("margin_left",   8)
	list_pad.add_theme_constant_override("margin_right",  8)
	list_pad.add_theme_constant_override("margin_top",    4)
	list_pad.add_theme_constant_override("margin_bottom", 8)
	list_pad.add_child(_tile_list)
	add_child(list_pad)


# ── Public API ────────────────────────────────────────────────────────────────

## Loads available recipes for [param building_id] and rebuilds the tile list.
func setup(building_id: String) -> void:
	_building_id = building_id
	refresh()


## Rebuilds recipe rows from current BuildingRegistry state.
func refresh() -> void:
	if _building_id == "":
		return
	for child: Node in _tile_list.get_children():
		child.queue_free()

	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		return

	var available_indices: Array[int] = \
			BuildingRegistry.get_available_recipe_indices(_building_id)
	var all_recipes: Array = BuildingRegistry.RECIPES.get(instance.type, [])

	for idx: int in available_indices:
		if idx < 0 or idx >= all_recipes.size():
			continue
		var recipe: Dictionary = all_recipes[idx]
		var recipe_id: StringName = recipe.get("id", StringName(str(idx)))
		var is_active: bool = (instance.active_recipe_index == idx)
		_tile_list.add_child(_build_recipe_row(recipe, recipe_id, instance, is_active))


# ── Private helpers ───────────────────────────────────────────────────────────

func _build_recipe_row(
		recipe: Dictionary,
		recipe_id: StringName,
		instance: BuildingRegistry.BuildingInstance,
		is_active: bool) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_row(row, is_active)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left",   6)
	pad.add_theme_constant_override("margin_right",  6)
	pad.add_theme_constant_override("margin_top",    6)
	pad.add_theme_constant_override("margin_bottom", 6)
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(pad)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_child(hbox)

	var cycle_ticks: int  = recipe.get("base_cycle_ticks", 0)
	var tpd: float        = float(TickSystem.TICKS_PER_DAY)
	var eff: float        = instance.get_effective_efficiency()

	var inputs: Array = recipe.get("inputs", [])
	for spec: Dictionary in inputs:
		var res_id: StringName = spec.get("resource_id", &"")
		if res_id == &"":
			continue
		var qty: int = spec.get("quantity", 1)
		var rate: float = float(qty) * eff * tpd / float(cycle_ticks) if cycle_ticks > 0 else 0.0
		hbox.add_child(_make_resource_column(res_id, qty, rate, is_active))

	if not inputs.is_empty():
		var arrow := Label.new()
		arrow.text = "→"
		arrow.add_theme_font_size_override("font_size", 18)
		arrow.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		arrow.mouse_filter = Control.MOUSE_FILTER_PASS
		hbox.add_child(arrow)

	var output: Dictionary = recipe.get("output", {})
	for res_id: StringName in output:
		var qty: int = output[res_id]
		var rate: float = float(qty) * eff * tpd / float(cycle_ticks) if cycle_ticks > 0 else 0.0
		hbox.add_child(_make_resource_column(res_id, qty, rate, is_active))

	row.mouse_entered.connect(func() -> void: _style_row(row, is_active, true))
	row.mouse_exited.connect(func() -> void:  _style_row(row, is_active, false))

	var captured_id: StringName = recipe_id
	row.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			recipe_selected.emit(captured_id)
	)

	return row


## Builds a VBox column: rate label above, DrawerTile icon (with cycle qty), resource name below.
func _make_resource_column(res_id: StringName, cycle_qty: int, rate_per_day: float, is_active: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_PASS

	# Rate label above the tile.
	var rate_lbl := Label.new()
	rate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rate_lbl.add_theme_font_size_override("font_size", 9)
	rate_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	rate_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	if rate_per_day > 0.0:
		rate_lbl.text = "~%d/d" % roundi(rate_per_day)  # TODO: localize
		rate_lbl.tooltip_text = "%.2f/day" % rate_per_day
	col.add_child(rate_lbl)

	# Icon tile (no quantity label).
	var tile := DrawerTile.new()
	var tex: Texture2D = ResourceRegistry.get_icon_texture(res_id, 28)
	if tex != null:
		tile.set_icon_texture(tex)
	else:
		tile.set_icon_glyph(ResourceRegistry.get_glyph(res_id))
	tile.set_label("×%d" % cycle_qty)
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	if is_active:
		tile.set_state(DrawerTile.TileState.ACTIVE)
	col.add_child(tile)

	# Resource name below the tile.
	var name_lbl := Label.new()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", COLOR_NAME)
	name_lbl.custom_minimum_size  = Vector2(DrawerTile.TILE_SIZE.x, 0)
	name_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_lbl.mouse_filter          = Control.MOUSE_FILTER_PASS
	var def: ResourceRegistry._ResourceDefinition = ResourceRegistry.get_definition(res_id)
	name_lbl.text = def.display_name if def != null else str(res_id)
	col.add_child(name_lbl)

	return col


func _style_row(row: PanelContainer, is_active: bool, hovered: bool = false) -> void:
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left     = 4
	sb.corner_radius_top_right    = 4
	sb.corner_radius_bottom_left  = 4
	sb.corner_radius_bottom_right = 4
	sb.border_width_left   = 2
	sb.border_width_right  = 2
	sb.border_width_top    = 2
	sb.border_width_bottom = 2
	if is_active:
		sb.bg_color     = COLOR_BG_ACTIVE
		sb.border_color = COLOR_BORDER_ACTIVE
	elif hovered:
		sb.bg_color     = COLOR_BG_HOVER
		sb.border_color = COLOR_BORDER_HOVER
	else:
		sb.bg_color     = COLOR_BG
		sb.border_color = Color(0.0, 0.0, 0.0, 0.0)
	row.add_theme_stylebox_override("panel", sb)
