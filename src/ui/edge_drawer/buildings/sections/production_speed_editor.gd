class_name ProductionSpeedEditor extends VBoxContainer
## Speed-throttle editor for production buildings.
## Shows a slider (0 % – building max %) and per-resource rate fields, all kept in sync.
## Emits save_requested(target_efficiency) or cancel_requested().
## BuildingDetailView owns show/hide and signal forwarding.

signal save_requested(target_efficiency: float)
signal cancel_requested()

const COLOR_TEXT     := Color(0.85, 0.85, 0.85, 1.0)
const COLOR_TEXT_DIM := Color(0.55, 0.55, 0.60, 1.0)
const COLOR_SEP      := Color(0.25, 0.26, 0.30, 1.0)

var _building_id: String = ""
var _max_efficiency: float = 1.0
## Working value while the editor is open. Absolute efficiency in [0, _max_efficiency].
var _pending: float = 0.0

var _slider:    HSlider
var _pct_edit:  LineEdit   ## shows/receives percentage integer (no "%" character)
var _max_label: Label      ## right-end label e.g. "70%"

## Container that holds per-resource rate rows — rebuilt on each setup() call.
var _rate_rows_container: VBoxContainer

## Each entry: {edit: LineEdit, base_qty: float, cycle_ticks: int, ticks_per_day: float}
var _rate_entries: Array[Dictionary] = []

## Guards against re-entrant slider ↔ lineedit ↔ rate-field loops.
var _updating: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	add_child(_build_header_row())
	add_child(_make_sep())
	add_child(_build_slider_block())
	add_child(_make_sep())

	var rate_pad := MarginContainer.new()
	rate_pad.name = "RatePad"
	rate_pad.add_theme_constant_override("margin_left",   8)
	rate_pad.add_theme_constant_override("margin_right",  8)
	rate_pad.add_theme_constant_override("margin_top",    6)
	rate_pad.add_theme_constant_override("margin_bottom", 6)
	add_child(rate_pad)

	_rate_rows_container = VBoxContainer.new()
	_rate_rows_container.name = "RateRows"
	_rate_rows_container.add_theme_constant_override("separation", 4)
	rate_pad.add_child(_rate_rows_container)


# ── Public API ─────────────────────────────────────────────────────────────────

## Loads data for [param building_id] and syncs all controls.
func setup(building_id: String) -> void:
	_building_id = building_id
	_rebuild_rate_rows()
	_sync_from_instance()


## Called from BuildingDetailView.refresh() when the building's computed max changes.
## Only does work when the editor is visible to avoid unnecessary updates.
func update_max(new_max: float) -> void:
	_max_efficiency = maxf(new_max, 0.001)
	_max_label.text = "%d%%" % int(_max_efficiency * 100.0)
	_slider.max_value = _max_efficiency
	if _pending > _max_efficiency:
		_set_pending(_max_efficiency)


# ── Builder helpers ────────────────────────────────────────────────────────────

func _build_header_row() -> Control:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left",   8)
	pad.add_theme_constant_override("margin_right",  8)
	pad.add_theme_constant_override("margin_top",    4)
	pad.add_theme_constant_override("margin_bottom", 4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	pad.add_child(row)

	var save_btn := Button.new()
	save_btn.name = "SaveBtn"
	save_btn.text = "✓"
	save_btn.flat = true
	save_btn.add_theme_font_size_override("font_size", 14)
	save_btn.add_theme_color_override("font_color", Color(0.298, 0.686, 0.314))
	save_btn.tooltip_text = "Save"  # TODO: localize
	save_btn.pressed.connect(_on_save_pressed)
	row.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.name = "CancelBtn"
	cancel_btn.text = "✕"
	cancel_btn.flat = true
	cancel_btn.add_theme_font_size_override("font_size", 13)
	cancel_btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	cancel_btn.tooltip_text = "Cancel"  # TODO: localize
	cancel_btn.pressed.connect(_on_cancel_pressed)
	row.add_child(cancel_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var title := Label.new()
	title.name = "Title"
	title.text = "Produktion Speed"  # TODO: localize
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(title)

	return pad


func _build_slider_block() -> Control:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left",   8)
	pad.add_theme_constant_override("margin_right",  8)
	pad.add_theme_constant_override("margin_top",    6)
	pad.add_theme_constant_override("margin_bottom", 6)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	pad.add_child(vbox)

	# Slider row: [0%] [slider] [XX%]
	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 6)
	vbox.add_child(slider_row)

	var min_lbl := Label.new()
	min_lbl.text = "0%"
	min_lbl.add_theme_font_size_override("font_size", 11)
	min_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	min_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider_row.add_child(min_lbl)

	_slider = HSlider.new()
	_slider.name = "Slider"
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(_on_slider_changed)
	slider_row.add_child(_slider)

	_max_label = Label.new()
	_max_label.name = "MaxLabel"
	_max_label.text = "100%"
	_max_label.add_theme_font_size_override("font_size", 11)
	_max_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_max_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider_row.add_child(_max_label)

	# Center value row: [LineEdit] [%]
	var center_row := HBoxContainer.new()
	center_row.add_theme_constant_override("separation", 2)
	center_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(center_row)

	_pct_edit = LineEdit.new()
	_pct_edit.name = "PctEdit"
	_pct_edit.custom_minimum_size = Vector2(48, 0)
	_pct_edit.alignment           = HORIZONTAL_ALIGNMENT_CENTER
	_pct_edit.add_theme_font_size_override("font_size", 13)
	_pct_edit.text_submitted.connect(_on_pct_submitted)
	_pct_edit.focus_exited.connect(_on_pct_focus_exited)
	center_row.add_child(_pct_edit)

	var pct_lbl := Label.new()
	pct_lbl.text = "%"
	pct_lbl.add_theme_font_size_override("font_size", 13)
	pct_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	pct_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center_row.add_child(pct_lbl)

	return pad


# ── Rate rows ──────────────────────────────────────────────────────────────────

func _rebuild_rate_rows() -> void:
	for child in _rate_rows_container.get_children():
		child.queue_free()
	_rate_entries.clear()

	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		return
	var recipe: Dictionary = BuildingRegistry.get_active_recipe(instance)
	if recipe.is_empty():
		return

	var cycle_ticks: int = recipe.get("base_cycle_ticks", 1)
	var tpd: float = float(TickSystem.TICKS_PER_DAY)

	# Input rows
	var inputs: Array = recipe.get("inputs", [])
	if not inputs.is_empty():
		_rate_rows_container.add_child(_make_section_label("Verbrauch"))  # TODO: localize
	for spec: Dictionary in inputs:
		var res_id: StringName = spec.get("resource_id", &"")
		var qty: int = spec.get("quantity", 1)
		var entry: Dictionary = {"base_qty": float(qty), "cycle_ticks": cycle_ticks,
				"ticks_per_day": tpd, "edit": null}
		_rate_rows_container.add_child(_build_rate_row(res_id, entry))
		_rate_entries.append(entry)

	# Arrow separator (only when there are inputs)
	if not inputs.is_empty():
		var arrow := Label.new()
		arrow.text = "→"
		arrow.add_theme_font_size_override("font_size", 14)
		arrow.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		_rate_rows_container.add_child(arrow)

	# Output rows
	var output: Dictionary = recipe.get("output", {})
	if not output.is_empty():
		_rate_rows_container.add_child(_make_section_label("Produktion"))  # TODO: localize
	for res_id: StringName in output:
		var qty: int = output[res_id]
		var entry: Dictionary = {"base_qty": float(qty), "cycle_ticks": cycle_ticks,
				"ticks_per_day": tpd, "edit": null}
		_rate_rows_container.add_child(_build_rate_row(res_id, entry))
		_rate_entries.append(entry)


func _make_section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	return lbl


func _build_rate_row(res_id: StringName, entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var def: Object = ResourceRegistry.get_definition(res_id)
	var res_name: String = def.display_name if def != null else str(res_id)

	var lbl := Label.new()
	lbl.text = res_name
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	lbl.custom_minimum_size = Vector2(64, 0)
	row.add_child(lbl)

	var edit := LineEdit.new()
	edit.name = "RateEdit"
	edit.custom_minimum_size = Vector2(52, 0)
	edit.alignment           = HORIZONTAL_ALIGNMENT_RIGHT
	edit.add_theme_font_size_override("font_size", 11)
	entry["edit"] = edit
	edit.text_submitted.connect(func(_t: String) -> void: _apply_rate_edit(entry))
	edit.focus_exited.connect(func() -> void: _apply_rate_edit(entry))
	row.add_child(edit)

	var suffix := Label.new()
	suffix.text = "/day"  # TODO: localize
	suffix.add_theme_font_size_override("font_size", 11)
	suffix.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	row.add_child(suffix)

	return row


# ── Sync helpers ───────────────────────────────────────────────────────────────

func _sync_from_instance() -> void:
	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		return
	_max_efficiency = maxf(instance.efficiency, 0.001)
	_slider.max_value = _max_efficiency
	_max_label.text = "%d%%" % int(_max_efficiency * 100.0)
	var start: float = instance.efficiency if instance.target_efficiency < 0.0 \
			else instance.target_efficiency
	_set_pending(start)


## Sets _pending and pushes the value to slider, pct edit, and all rate fields atomically.
func _set_pending(value: float) -> void:
	if _updating:
		return
	_updating = true
	_pending = clampf(value, 0.0, _max_efficiency)
	_slider.value = _pending
	_pct_edit.text = str(int(roundf(_pending * 100.0)))
	for entry: Dictionary in _rate_entries:
		var per_day: float = 0.0
		if entry["cycle_ticks"] > 0 and entry["ticks_per_day"] > 0.0:
			per_day = entry["base_qty"] * _pending * entry["ticks_per_day"] \
					/ float(entry["cycle_ticks"])
		(entry["edit"] as LineEdit).text = "%.2f" % per_day
	_updating = false


# ── Event handlers ─────────────────────────────────────────────────────────────

func _on_slider_changed(value: float) -> void:
	_set_pending(value)


func _on_pct_submitted(_text: String) -> void:
	_apply_pct_edit()


func _on_pct_focus_exited() -> void:
	_apply_pct_edit()


func _apply_pct_edit() -> void:
	var parsed: float = float(_pct_edit.text.strip_edges()) / 100.0
	if is_nan(parsed):
		_set_pending(_pending)  # restore last valid value
		return
	_set_pending(parsed)


func _apply_rate_edit(entry: Dictionary) -> void:
	var parsed: float = float((entry["edit"] as LineEdit).text.strip_edges())
	if is_nan(parsed) or entry["cycle_ticks"] <= 0 or entry["ticks_per_day"] <= 0.0:
		_set_pending(_pending)  # restore
		return
	# Reverse-calculate efficiency from the entered per-day rate.
	var eff: float = parsed * float(entry["cycle_ticks"]) \
			/ (entry["base_qty"] * entry["ticks_per_day"])
	_set_pending(eff)


func _on_save_pressed() -> void:
	save_requested.emit(_pending)


func _on_cancel_pressed() -> void:
	cancel_requested.emit()


func _make_sep() -> HSeparator:
	var sep := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_SEP
	sb.content_margin_top    = 0
	sb.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", sb)
	return sep
