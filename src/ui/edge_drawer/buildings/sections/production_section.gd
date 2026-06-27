class_name ProductionSection extends VBoxContainer
## Displays the active recipe's input/output buffers and throughput rate
## for a production building inside the Buildings Drawer.
## Spec: design/gdd/buildings-drawer.md §5.1 B4

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when the player taps the ⚙️ recipe-picker button.
## Kept for external listeners (e.g. BuildingDetailView) that want to know the picker opened.
signal recipe_picker_requested()
## Emitted when the player confirms a recipe selection inside the inline picker.
## Callers should invoke BuildingRegistry.set_active_recipe() with the matching index.
signal recipe_changed(building_id: String, recipe_id: StringName)
## Forwarded from child ItemTiles — storage drag from an input buffer item.
signal storage_drag_started(resource_id: StringName, container_id: StringName, tile_pos: Vector2i)
## Forwarded from child ItemTiles — input buffer drag.
signal input_drag_started(resource_id: StringName, building_id: String, tile_pos: Vector2i)
## Forwarded from child ItemTiles — output buffer drag.
signal output_drag_started(resource_id: StringName, building_id: String, tile_pos: Vector2i)

# ── Constants ─────────────────────────────────────────────────────────────────

const COLOR_TEXT     := Color(0.85, 0.85, 0.85, 1.0)
const COLOR_TEXT_DIM := Color(0.55, 0.55, 0.60, 1.0)

# ── Node refs ─────────────────────────────────────────────────────────────────

var _recipe_btn: Button
var _flow: TileFlowContainer
## Container wrapping the rate label + tile flow (hidden while picker is visible).
var _body_container: VBoxContainer
## Inline recipe picker — shown in place of _body_container when ⚙️ is tapped.
var _recipe_picker_view: RecipePickerView

# ── State ─────────────────────────────────────────────────────────────────────

var _building_id: String = ""
## Cache of input ItemTiles keyed by resource_id for efficient refresh.
var _input_tiles: Dictionary[StringName, ItemTile] = {}
## Cache of output ItemTiles keyed by resource_id for efficient refresh.
var _output_tiles: Dictionary[StringName, ItemTile] = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)

	# ── Header row ────────────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 4)

	var pad_h := MarginContainer.new()
	pad_h.add_theme_constant_override("margin_left",   12)
	pad_h.add_theme_constant_override("margin_right",  8)
	pad_h.add_theme_constant_override("margin_top",    6)
	pad_h.add_theme_constant_override("margin_bottom", 4)
	pad_h.add_child(header)
	add_child(pad_h)

	var section_label := Label.new()
	section_label.name = "SectionLabel"
	section_label.text = "Production"  # TODO: localize
	section_label.add_theme_font_size_override("font_size", 12)
	section_label.add_theme_color_override("font_color", COLOR_TEXT)
	section_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(section_label)

	_recipe_btn = Button.new()
	_recipe_btn.name    = "RecipeBtn"
	_recipe_btn.text    = "⚙"
	_recipe_btn.flat    = true
	_recipe_btn.tooltip_text = "Change recipe"  # TODO: localize
	_recipe_btn.add_theme_font_size_override("font_size", 14)
	_recipe_btn.visible = false
	_recipe_btn.pressed.connect(_on_recipe_btn_pressed)
	header.add_child(_recipe_btn)

	# ── Body container (rate label + tile flow) ───────────────────────────────
	# This container is hidden when the recipe picker is shown.
	_body_container = VBoxContainer.new()
	_body_container.name = "BodyContainer"
	_body_container.add_theme_constant_override("separation", 0)
	add_child(_body_container)

	# ── Tile flow ─────────────────────────────────────────────────────────────
	_flow = TileFlowContainer.new()
	_flow.name = "TileFlow"
	_body_container.add_child(_flow)

	# ── Recipe picker view (hidden until ⚙️ is tapped) ───────────────────────
	_recipe_picker_view = RecipePickerView.new()
	_recipe_picker_view.name    = "RecipePickerView"
	_recipe_picker_view.visible = false
	_recipe_picker_view.back_pressed.connect(_hide_picker)
	_recipe_picker_view.recipe_selected.connect(_on_recipe_selected)
	add_child(_recipe_picker_view)


# ── Public API ────────────────────────────────────────────────────────────────

## Loads production data for [param building_id] and rebuilds the tile layout.
func setup(building_id: String) -> void:
	_building_id = building_id
	_rebuild_tiles()
	refresh()
	_connect_live_signals()


func _connect_live_signals() -> void:
	if not BuildingRegistry.production_output_ready.is_connected(_on_output_changed_with_id):
		BuildingRegistry.production_output_ready.connect(_on_output_changed_with_id)
	if not BuildingRegistry.building_output_changed.is_connected(_on_output_changed_id_only):
		BuildingRegistry.building_output_changed.connect(_on_output_changed_id_only)
	if not TickSystem.ticks_advanced.is_connected(_on_ticks_advanced):
		TickSystem.ticks_advanced.connect(_on_ticks_advanced)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		if BuildingRegistry.production_output_ready.is_connected(_on_output_changed_with_id):
			BuildingRegistry.production_output_ready.disconnect(_on_output_changed_with_id)
		if BuildingRegistry.building_output_changed.is_connected(_on_output_changed_id_only):
			BuildingRegistry.building_output_changed.disconnect(_on_output_changed_id_only)
		if TickSystem.ticks_advanced.is_connected(_on_ticks_advanced):
			TickSystem.ticks_advanced.disconnect(_on_ticks_advanced)


func _on_output_changed_with_id(building_id: String, _output: Dictionary, _ticks: int) -> void:
	if building_id == _building_id:
		refresh()


func _on_output_changed_id_only(building_id: String) -> void:
	if building_id == _building_id:
		refresh()


func _on_ticks_advanced(_delta: int) -> void:
	refresh()


## Re-reads buffer quantities and rate label — call on every tick advance.
func refresh() -> void:
	if _building_id == "":
		return
	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		return

	# ── Refresh input-buffer badge counts ────────────────────────────────────
	for res_id: StringName in _input_tiles:
		var qty: int = int(instance.input_buffer.get(res_id, 0.0))
		_input_tiles[res_id].update_quantity(qty)

	# ── Refresh output-buffer badge counts ───────────────────────────────────
	for res_id: StringName in _output_tiles:
		var qty: int = instance.buffered_output.get(res_id, 0)
		_output_tiles[res_id].update_quantity(qty)



# ── Private helpers ───────────────────────────────────────────────────────────

## Clears and recreates all ItemTiles from the current recipe definition.
func _rebuild_tiles() -> void:
	_flow.clear_tiles()
	_input_tiles.clear()
	_output_tiles.clear()

	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		return

	# Show/hide recipe button.
	var all_recipes: Array = BuildingRegistry.RECIPES.get(instance.type, [])
	_recipe_btn.visible = all_recipes.size() > 1

	var recipe: Dictionary = BuildingRegistry.get_active_recipe(instance)
	if recipe.is_empty():
		return

	var cycle_ticks: int = recipe.get("base_cycle_ticks", 0)
	var ticks_per_day: float = float(TickSystem.TICKS_PER_DAY)

	# ── Input tiles ───────────────────────────────────────────────────────────
	var inputs: Array = recipe.get("inputs", [])
	for spec: Dictionary in inputs:
		var res_id: StringName = spec.get("resource_id", &"")
		if res_id == &"":
			continue
		var spec_qty: int = spec.get("quantity", 1)
		var buf_qty: int = int(instance.input_buffer.get(res_id, 0.0))

		var wrapper := VBoxContainer.new()
		wrapper.add_theme_constant_override("separation", 2)

		var rate_lbl := Label.new()
		rate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rate_lbl.add_theme_font_size_override("font_size", 9)
		rate_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		rate_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		if cycle_ticks > 0:
			var per_day: float = float(spec_qty) * instance.get_effective_efficiency() * ticks_per_day / float(cycle_ticks)
			rate_lbl.text = "~%d/day" % int(per_day)  # TODO: localize
			rate_lbl.tooltip_text = "%.2f/day" % per_day
		wrapper.add_child(rate_lbl)

		var tile := ItemTile.new()
		tile.input_drag_started.connect(_on_input_drag_started)
		wrapper.add_child(tile)
		_flow.add_tile(wrapper)   # enters tree → _ready() fires before setup()
		tile.setup(res_id, buf_qty, "input", _building_id, instance.tile)
		_input_tiles[res_id] = tile

	# ── Arrow separator (only when there are inputs) ──────────────────────────
	if not inputs.is_empty():
		var arrow := Label.new()
		arrow.text = "→"
		arrow.add_theme_font_size_override("font_size", 18)
		arrow.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_flow.add_tile(arrow)

	# ── Output tiles ──────────────────────────────────────────────────────────
	var output: Dictionary = recipe.get("output", {})
	for res_id: StringName in output:
		var base_qty: int = output[res_id]
		var buf_qty: int = instance.buffered_output.get(res_id, 0)

		var wrapper := VBoxContainer.new()
		wrapper.add_theme_constant_override("separation", 2)

		var rate_lbl := Label.new()
		rate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rate_lbl.add_theme_font_size_override("font_size", 9)
		rate_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		rate_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		if cycle_ticks > 0:
			var per_day: float = (float(base_qty) * instance.get_effective_efficiency()) \
					* ticks_per_day / float(cycle_ticks)
			rate_lbl.text = "~%d/day" % int(per_day)  # TODO: localize
			rate_lbl.tooltip_text = "%.2f/day" % per_day
		wrapper.add_child(rate_lbl)

		var tile := ItemTile.new()
		tile.output_drag_started.connect(_on_output_drag_started)
		wrapper.add_child(tile)
		_flow.add_tile(wrapper)   # enters tree → _ready() fires before setup()
		tile.setup(res_id, buf_qty, "output", _building_id, instance.tile)
		_output_tiles[res_id] = tile



# ── Picker sub-state ──────────────────────────────────────────────────────────

## Called when the ⚙️ button is pressed. Emits the external signal and shows the picker.
func _on_recipe_btn_pressed() -> void:
	recipe_picker_requested.emit()
	_show_picker()


## Shows the recipe picker and hides the body content.
func _show_picker() -> void:
	_recipe_picker_view.setup(_building_id)
	_body_container.visible      = false
	_recipe_picker_view.visible  = true


## Hides the recipe picker and restores the body content.
func _hide_picker() -> void:
	_recipe_picker_view.visible = false
	_body_container.visible     = true


## Forwarded from RecipePickerView — emits recipe_changed so callers can update BuildingRegistry.
func _on_recipe_selected(recipe_id: StringName) -> void:
	_hide_picker()
	recipe_changed.emit(_building_id, recipe_id)
	# Rebuild tiles to reflect new recipe immediately (caller will also call refresh()).
	_rebuild_tiles()
	refresh()


# ── Signal forwarding ─────────────────────────────────────────────────────────

func _on_storage_drag_started(res_id: StringName, cid: StringName, tp: Vector2i) -> void:
	storage_drag_started.emit(res_id, cid, tp)


func _on_input_drag_started(res_id: StringName, bid: String, tp: Vector2i) -> void:
	input_drag_started.emit(res_id, bid, tp)


func _on_output_drag_started(res_id: StringName, bid: String, tp: Vector2i) -> void:
	output_drag_started.emit(res_id, bid, tp)
