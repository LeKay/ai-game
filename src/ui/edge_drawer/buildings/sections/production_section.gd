class_name ProductionSection extends VBoxContainer
## Displays the active recipe's input/output buffers and throughput rate
## for a production building inside the Buildings Drawer.
## Spec: design/gdd/buildings-drawer.md §5.1 B4

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when the player taps the ⚙️ recipe-picker button.
## Kept for external listeners (e.g. BuildingDetailView) that want to know the picker opened.
signal recipe_picker_requested()
## Emitted when the player edits a rate field — callers should invoke BuildingRegistry.set_production_speed().
signal production_speed_changed(building_id: String, target_efficiency: float)
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

var _section_label: Label
var _settings_btn:  Button
var _flow: TileFlowContainer
## Container wrapping the rate label + tile flow (hidden while picker is visible).
var _body_container: VBoxContainer
## Inline recipe picker — shown in place of _body_container when ⚙️ is tapped.
var _recipe_picker_view: RecipePickerView

# ── State ─────────────────────────────────────────────────────────────────────

var _building_id: String = ""
var _rate_editing: bool = false
## Cache of input ItemTiles keyed by resource_id for efficient refresh.
var _input_tiles: Dictionary[StringName, ItemTile] = {}
## Cache of output ItemTiles keyed by resource_id for efficient refresh.
var _output_tiles: Dictionary[StringName, ItemTile] = {}
## Rate edits updated every refresh (when not focused) to reflect the current effective efficiency.
var _input_rate_labels:  Dictionary[StringName, LineEdit] = {}
var _output_rate_labels: Dictionary[StringName, LineEdit] = {}
## Per-resource base quantities and recipe data needed to recompute rates in refresh().
var _recipe_cycle_ticks: int = 0
var _input_base_qty:  Dictionary[StringName, int] = {}
var _output_base_qty: Dictionary[StringName, int] = {}

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

	_section_label = Label.new()
	_section_label.name = "SectionLabel"
	_section_label.text = "Production"  # TODO: localize
	_section_label.add_theme_font_size_override("font_size", 12)
	_section_label.add_theme_color_override("font_color", COLOR_TEXT)
	_section_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_section_label)

	_settings_btn = Button.new()
	_settings_btn.name        = "SettingsBtn"
	_settings_btn.text        = "⚙"
	_settings_btn.flat        = true
	_settings_btn.toggle_mode = true
	_settings_btn.tooltip_text = "Edit production speed"  # TODO: localize
	_settings_btn.add_theme_font_size_override("font_size", 14)
	_settings_btn.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_settings_btn.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	_settings_btn.toggled.connect(_on_settings_toggled)
	header.add_child(_settings_btn)

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

	# ── Refresh rate edits (skip if the field is focused — user is typing) ───────
	if _recipe_cycle_ticks > 0:
		var tpd: float = float(TickSystem.TICKS_PER_DAY)
		var eff: float = instance.get_effective_efficiency()
		for res_id: StringName in _input_rate_labels:
			var edit: LineEdit = _input_rate_labels[res_id]
			if not edit.has_focus():
				var per_day: float = float(_input_base_qty.get(res_id, 1)) * eff * tpd / float(_recipe_cycle_ticks)
				edit.text = _format_rate(per_day)
		for res_id: StringName in _output_rate_labels:
			var edit: LineEdit = _output_rate_labels[res_id]
			if not edit.has_focus():
				var per_day: float = float(_output_base_qty.get(res_id, 1)) * eff * tpd / float(_recipe_cycle_ticks)
				edit.text = _format_rate(per_day)



# ── Private helpers ───────────────────────────────────────────────────────────

## Clears and recreates all ItemTiles from the current recipe definition.
func _rebuild_tiles() -> void:
	_flow.clear_tiles()
	_input_tiles.clear()
	_output_tiles.clear()
	_input_rate_labels.clear()
	_output_rate_labels.clear()
	_input_base_qty.clear()
	_output_base_qty.clear()

	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		return

	var recipe: Dictionary = BuildingRegistry.get_active_recipe(instance)
	if recipe.is_empty():
		return

	var cycle_ticks: int = recipe.get("base_cycle_ticks", 0)
	_recipe_cycle_ticks = cycle_ticks
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

		var rate_edit := LineEdit.new()
		rate_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		rate_edit.add_theme_font_size_override("font_size", 9)
		rate_edit.custom_minimum_size = Vector2(0, 16)
		rate_edit.tooltip_text = "Rate per day — edit to change speed"  # TODO: localize
		rate_edit.editable = _rate_editing
		if cycle_ticks > 0:
			var per_day: float = float(spec_qty) * instance.get_effective_efficiency() * ticks_per_day / float(cycle_ticks)
			rate_edit.text = _format_rate(per_day)
		var captured_qty_in: int = spec_qty
		rate_edit.text_submitted.connect(func(t: String) -> void:
			if t.is_valid_float():
				_apply_rate(t.to_float(), captured_qty_in)
			rate_edit.release_focus()
		)
		rate_edit.focus_exited.connect(func() -> void:
			if rate_edit.text.is_valid_float():
				_apply_rate(rate_edit.text.to_float(), captured_qty_in)
		)
		wrapper.add_child(rate_edit)

		var tile := ItemTile.new()
		tile.input_drag_started.connect(_on_input_drag_started)
		wrapper.add_child(tile)
		_flow.add_tile(wrapper)   # enters tree → _ready() fires before setup()
		tile.setup(res_id, buf_qty, "input", _building_id, instance.tile)
		_input_tiles[res_id] = tile
		_input_rate_labels[res_id] = rate_edit
		_input_base_qty[res_id] = spec_qty

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

		var rate_edit := LineEdit.new()
		rate_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		rate_edit.add_theme_font_size_override("font_size", 9)
		rate_edit.custom_minimum_size = Vector2(0, 16)
		rate_edit.tooltip_text = "Rate per day — edit to change speed"  # TODO: localize
		rate_edit.editable = _rate_editing
		if cycle_ticks > 0:
			var per_day: float = (float(base_qty) * instance.get_effective_efficiency()) \
					* ticks_per_day / float(cycle_ticks)
			rate_edit.text = _format_rate(per_day)
		var captured_qty_out: int = base_qty
		rate_edit.text_submitted.connect(func(t: String) -> void:
			if t.is_valid_float():
				_apply_rate(t.to_float(), captured_qty_out)
			rate_edit.release_focus()
		)
		rate_edit.focus_exited.connect(func() -> void:
			if rate_edit.text.is_valid_float():
				_apply_rate(rate_edit.text.to_float(), captured_qty_out)
		)
		wrapper.add_child(rate_edit)

		var tile := ItemTile.new()
		tile.output_drag_started.connect(_on_output_drag_started)
		wrapper.add_child(tile)
		_flow.add_tile(wrapper)   # enters tree → _ready() fires before setup()
		tile.setup(res_id, buf_qty, "output", _building_id, instance.tile)
		_output_tiles[res_id] = tile
		_output_rate_labels[res_id] = rate_edit
		_output_base_qty[res_id] = base_qty



# ── Rate editing ─────────────────────────────────────────────────────────────

func _on_settings_toggled(pressed: bool) -> void:
	_rate_editing = pressed
	for key: StringName in _input_rate_labels:
		_input_rate_labels[key].editable = pressed
	for key: StringName in _output_rate_labels:
		_output_rate_labels[key].editable = pressed
	refresh()


func _format_rate(per_day: float) -> String:
	return "%.2f" % per_day if _rate_editing else "%.2f/day" % per_day

## Converts a desired [param rate_per_day] (for [param base_qty] units/cycle) into an efficiency
## value, clamps it to [0, building max], and emits [signal production_speed_changed].
func _apply_rate(rate_per_day: float, base_qty: int) -> void:
	if _recipe_cycle_ticks <= 0 or base_qty <= 0:
		return
	var tpd: float = float(TickSystem.TICKS_PER_DAY)
	if tpd <= 0.0:
		return
	var target_eff: float = rate_per_day * float(_recipe_cycle_ticks) / (float(base_qty) * tpd)
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_building_id)
	if instance != null:
		target_eff = clampf(target_eff, 0.0, instance.efficiency)
	production_speed_changed.emit(_building_id, target_eff)


# ── Picker sub-state ──────────────────────────────────────────────────────────

## Toggles the recipe picker open/closed. Called by BuildingDetailView's bottom Recipe button.
func toggle_picker() -> void:
	if _recipe_picker_view.visible:
		_hide_picker()
	else:
		recipe_picker_requested.emit()
		_show_picker()


## Shows the recipe picker and hides the body content.
func _show_picker() -> void:
	_recipe_picker_view.setup(_building_id)
	_body_container.visible     = false
	_recipe_picker_view.visible = true
	_section_label.text = "Recipes"  # TODO: localize


## Hides the recipe picker and restores the body content.
func _hide_picker() -> void:
	_recipe_picker_view.visible = false
	_body_container.visible     = true
	_section_label.text = "Production"  # TODO: localize


## Returns true while the inline recipe picker is visible.
func is_picker_open() -> bool:
	return _recipe_picker_view != null and _recipe_picker_view.visible


## Closes the recipe picker without confirming a selection. No-op if not open.
func cancel_picker() -> void:
	if _recipe_picker_view.visible:
		_hide_picker()


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
