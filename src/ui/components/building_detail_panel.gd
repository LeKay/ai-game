class_name BuildingDetailPanel extends Control
## Building Detail Panel — UX spec: design/ux/building-detail.md
## Non-modal centered overlay opened when the player left-clicks a building tile.
## Displays building state, progress, production info, NPC and transport status.
## All write actions (assign NPC, demolish) delegate to BuildingRegistry — this panel
## is read-only; it owns no game state.

# ── Signals (UX spec: Events Fired) ──────────────────────────────────────────

signal storage_drag_started(resource_id: StringName, container_id: StringName, building_tile: Vector2i)
signal input_drag_started(resource_id: StringName, building_id: String, building_tile: Vector2i)
signal output_drag_started(resource_id: StringName, building_id: String, building_tile: Vector2i)
signal building_selected(building_id: String, tile: Vector2i)
signal building_deselected(building_id: String)
signal building_demolish_confirmed(building_id: String)
signal building_demolish_cancelled(building_id: String)
signal npc_assigned(building_id: String, npc_id: StringName)
signal npc_released(building_id: String, npc_id: StringName)
signal npc_assignment_cancelled(building_id: String)
signal transport_management_opened(building_id: String)

# ── Constants ─────────────────────────────────────────────────────────────────

const PANEL_WIDTH       := 380
const PANEL_ANIM_DURATION := 0.20  ## 200ms per UX spec
const COLOR_BG          := Color(0.176, 0.176, 0.176, 0.97)  ## #2D2D2D
const COLOR_TEXT        := Color(0.941, 0.941, 0.941)         ## #F0F0F0
const COLOR_TEXT_DIM    := Color(0.816, 0.816, 0.816)         ## #D0D0D0
const COLOR_WARN        := Color(1.0, 0.757, 0.027)           ## #FFC107
const COLOR_ERR         := Color(0.898, 0.451, 0.451)         ## #E57373
const COLOR_LINK        := Color(0.659, 0.643, 0.612)         ## #A8A49C
const COLOR_PROGRESS_BG := Color(0.227, 0.227, 0.227)         ## #3A3A3A
const COLOR_PROGRESS_FG := Color(0.831, 0.659, 0.361)         ## #D4A85C
const COLOR_BTN_NORMAL  := Color(0.353, 0.353, 0.353)         ## #5A5A5A
const COLOR_BTN_TEXT    := Color(0.659, 0.643, 0.612)         ## #A8A49C
const COLOR_BTN_HOVER   := Color(0.290, 0.494, 0.659)         ## #4A7EA8
const COLOR_BTN_DESTRUCT := Color(0.706, 0.173, 0.173)        ## #B32C2C
const COLOR_SEP         := Color(0.35, 0.35, 0.35, 1.0)
const COLOR_CAP_GREEN   := Color("#4CAF50")
const COLOR_CAP_AMBER   := Color("#D4A85C")
const COLOR_CAP_RED     := Color("#E05555")

## State dot colors (per UX spec component inventory).
const STATE_COLORS: Dictionary = {
	"PRODUCING":    Color(0.298, 0.686, 0.314),  ## green
	"OPERATING":    Color(0.298, 0.686, 0.314),  ## green
	"BLOCKED":      Color(1.0, 0.757, 0.027),    ## yellow
	"STALLED":      Color(0.898, 0.239, 0.239),  ## red
	"CONSTRUCTING": Color(1.0, 0.596, 0.0),      ## orange
	"IDLE":         Color(0.6, 0.6, 0.6),         ## gray
}

# ── Node refs ─────────────────────────────────────────────────────────────────

var _panel:              PanelContainer
var _name_label:         Label
var _state_dot:          ColorRect
var _state_label:        Label
var _demolish_btn:       Button

var _progress_zone:      Control
var _progress_bar_fill:  ColorRect
var _progress_label:     Label

var _production_zone:      Control
var _input_grid:           ItemGrid
var _input_drop_zone:      Control
var _input_rate_label:     Label
var _output_grid:          ItemGrid
var _output_rate_label:    Label

## Placeholder cycle constants until recipe system exists.
const _CYCLE_TICKS  := 120
const _INPUT_QTY    := 1
const _OUTPUT_QTY   := 5

var _npc_zone:           Control
var _npc_label:          Label
var _assign_npc_btn:     Button
var _release_npc_btn:    Button

var _transport_zone:      Control
var _carrier_in_label:    Label
var _carrier_in_btn:      Button
var _carrier_out_label:   Label
var _carrier_out_btn:     Button

var _storage_zone:              Control
var _storage_capacity_label:    Label
var _storage_bar_fill:          ColorRect
var _storage_item_grid:         ItemGrid

var _demolish_dialog:    Control
var _npc_popup:          Control

# ── State ─────────────────────────────────────────────────────────────────────

var _current_building_id: String = ""
var _tween: Tween = null
var _storage_pulse_tween: Tween = null
var _is_storage_pulsing: bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()
	_connect_registry()
	visible = false
	modulate.a = 0.0


func _exit_tree() -> void:
	if BuildingRegistry.building_state_changed.is_connected(_on_state_changed):
		BuildingRegistry.building_state_changed.disconnect(_on_state_changed)
	if BuildingRegistry.building_construction_complete.is_connected(_on_construction_complete):
		BuildingRegistry.building_construction_complete.disconnect(_on_construction_complete)
	if TickSystem.ticks_advanced.is_connected(_on_ticks_advanced):
		TickSystem.ticks_advanced.disconnect(_on_ticks_advanced)
	if InventorySystem.storage_changed.is_connected(_on_storage_changed):
		InventorySystem.storage_changed.disconnect(_on_storage_changed)
	if BuildingRegistry.building_input_changed.is_connected(_on_input_changed):
		BuildingRegistry.building_input_changed.disconnect(_on_input_changed)
	if BuildingRegistry.production_output_ready.is_connected(_on_production_output_ready):
		BuildingRegistry.production_output_ready.disconnect(_on_production_output_ready)
	if BuildingRegistry.building_output_changed.is_connected(_on_output_changed):
		BuildingRegistry.building_output_changed.disconnect(_on_output_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _current_building_id == "":
		return
	# Escape closes panel.
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		if _demolish_dialog != null and _demolish_dialog.visible:
			_close_demolish_dialog()
		elif _npc_popup != null and _npc_popup.visible:
			_close_npc_popup()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	# Click outside panel closes it (only when no sub-dialog is open).
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		if _demolish_dialog != null and _demolish_dialog.visible:
			return
		if _npc_popup != null and _npc_popup.visible:
			return
		if not _panel.get_global_rect().has_point(click.global_position):
			close()
			get_viewport().set_input_as_handled()

# ── Public API ────────────────────────────────────────────────────────────────

## Opens the panel for the given building_id. Animates in if already hidden.
## If the same building is already shown, closes the panel (toggle behaviour).
func open_for(building_id: String) -> void:
	if _current_building_id == building_id and visible:
		close()
		return
	_current_building_id = building_id
	_refresh()
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(building_id)
	var tile := instance.tile if instance != null else Vector2i.ZERO
	building_selected.emit(building_id, tile)
	_animate_in()


## Hides the panel.
func close() -> void:
	if _current_building_id != "":
		building_deselected.emit(_current_building_id)
	_current_building_id = ""
	_stop_storage_pulse()
	_animate_out()


## Returns the building_id currently displayed, or "" if closed.
func get_current_building_id() -> String:
	return _current_building_id


# ── Signal handlers ───────────────────────────────────────────────────────────

func _connect_registry() -> void:
	BuildingRegistry.building_state_changed.connect(_on_state_changed)
	BuildingRegistry.building_construction_complete.connect(_on_construction_complete)
	TickSystem.ticks_advanced.connect(_on_ticks_advanced)
	InventorySystem.storage_changed.connect(_on_storage_changed)
	BuildingRegistry.building_input_changed.connect(_on_input_changed)
	BuildingRegistry.production_output_ready.connect(_on_production_output_ready)
	BuildingRegistry.building_output_changed.connect(_on_output_changed)


func _on_state_changed(building_id: String, _new_state: int, _reason: String) -> void:
	if building_id == _current_building_id:
		_refresh()


func _on_construction_complete(building_id: String, _type: int) -> void:
	if building_id == _current_building_id:
		_refresh()


func _on_ticks_advanced(_delta: int) -> void:
	if not visible or _current_building_id == "":
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance != null:
		_refresh_header(instance)
		_refresh_progress(instance)


func _on_storage_changed(container_id: StringName) -> void:
	if not visible or _current_building_id == "":
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance != null and container_id == instance.assigned_container_id:
		_refresh_storage_zone(instance)


func _on_input_changed(building_id: String) -> void:
	if building_id != _current_building_id or not visible:
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(building_id)
	if instance != null:
		_refresh_production_zone(instance)


func _on_production_output_ready(building_id: String, _output: Dictionary) -> void:
	if building_id != _current_building_id or not visible:
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(building_id)
	if instance != null:
		_refresh_production_zone(instance)


func _on_output_changed(building_id: String) -> void:
	if building_id != _current_building_id or not visible:
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(building_id)
	if instance != null:
		_refresh_production_zone(instance)
		_refresh_header(instance)


## Returns true if data is a valid drag payload for this building's input.
func _can_accept_drop(data: Variant) -> bool:
	if _current_building_id == "" or not visible:
		return false
	if not data is Dictionary:
		return false
	var res_id: StringName = data.get(&"resource_id", &"")
	if res_id == &"":
		return false
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance == null:
		return false
	var allowed: Array = BuildingRegistry.INPUT_RESOURCES.get(instance.type, [])
	if not res_id in allowed:
		return false
	return InventorySystem.get_global_quantity(res_id) > 0


## Called when the player drops a valid payload onto the input drop zone.
func _on_input_drop(data: Variant) -> void:
	if not data is Dictionary:
		return
	var res_id: StringName = data.get(&"resource_id", &"")
	if res_id == &"" or _current_building_id == "":
		return
	BuildingRegistry.add_to_input(_current_building_id, res_id, 1)

# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance == null:
		close()
		return
	_refresh_header(instance)
	_refresh_progress(instance)
	_refresh_storage_zone(instance)
	_refresh_production_zone(instance)
	_refresh_npc_zone(instance)
	_refresh_transport_zone(instance)


func _refresh_header(instance: BuildingRegistry.BuildingInstance) -> void:
	_name_label.text = BuildingRegistry._building_type_name(instance.type)
	var state_key: String = _state_key(instance)
	var dot_color: Color = STATE_COLORS.get(state_key, Color.GRAY)
	_state_dot.color = dot_color
	_state_label.text = _state_text(instance)


func _refresh_progress(instance: BuildingRegistry.BuildingInstance) -> void:
	var is_constructing := instance.state == BuildingRegistry.BuildingInstance.State.CONSTRUCTING
	var is_producing := (instance.state == BuildingRegistry.BuildingInstance.State.OPERATING
		and instance.cycle_running)
	_progress_zone.visible = is_constructing or is_producing
	if not (is_constructing or is_producing):
		return
	var total: int
	var current: int
	var label_prefix: String
	if is_constructing:
		total = instance.build_time
		current = mini(instance.accumulated_ticks, total)
		label_prefix = "Construction"
	else:
		total = instance.production_cycle_duration
		current = mini(instance.production_cycle_ticks, total)
		label_prefix = "Production"
	var pct: float = float(current) / float(total) if total > 0 else 1.0
	_progress_bar_fill.size.x = _progress_bar_fill.get_parent().size.x * pct
	_progress_label.text = "%s: %d/%d ticks (%d%%)" % [label_prefix, current, total, int(pct * 100.0)]


func _refresh_progress_only() -> void:
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance != null:
		_refresh_progress(instance)


func _refresh_storage_zone(instance: BuildingRegistry.BuildingInstance) -> void:
	var is_storage := (instance.type == BuildingRegistry.BuildingType.STORAGE_AREA
		or instance.type == BuildingRegistry.BuildingType.STORAGE_BUILDING)
	_storage_zone.visible = is_storage
	if not is_storage:
		return
	var container: InventoryContainer = InventorySystem.get_container(instance.assigned_container_id)
	if container == null:
		_storage_capacity_label.text = "Storage: —"
		_storage_item_grid.populate([])
		return
	var used := container.get_occupied_count()
	var total := container.capacity
	var ratio := clampf(float(used) / float(total), 0.0, 1.0) if total > 0 else 0.0
	var pct := int(ratio * 100.0)
	_storage_capacity_label.text = "Storage: %d / %d  %d%%" % [used, total, pct]
	_storage_bar_fill.anchor_right = ratio
	if ratio >= 0.90:
		_storage_bar_fill.color = COLOR_CAP_RED
		_start_storage_pulse()
	elif ratio >= 0.75:
		_storage_bar_fill.color = COLOR_CAP_AMBER
		_stop_storage_pulse()
	else:
		_storage_bar_fill.color = COLOR_CAP_GREEN
		_stop_storage_pulse()
	var resources: Dictionary[StringName, int] = {}
	for slot: InventorySlot in container.slots:
		if not slot.is_empty():
			resources[slot.resource_id] = resources.get(slot.resource_id, 0) + slot.quantity
	var items: Array[Dictionary] = []
	for res_id: StringName in resources:
		items.append({&"resource_id": res_id, &"quantity": resources[res_id]})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a[&"resource_id"]) < str(b[&"resource_id"])
	)
	_storage_item_grid.populate(items)


func _start_storage_pulse() -> void:
	if _is_storage_pulsing:
		return
	_is_storage_pulsing = true
	_storage_pulse_tween = create_tween().set_loops()
	_storage_pulse_tween.tween_property(_storage_bar_fill, "modulate:a", 0.3, 0.5)
	_storage_pulse_tween.tween_property(_storage_bar_fill, "modulate:a", 1.0, 0.5)


func _stop_storage_pulse() -> void:
	if not _is_storage_pulsing:
		return
	_is_storage_pulsing = false
	if _storage_pulse_tween != null and _storage_pulse_tween.is_valid():
		_storage_pulse_tween.kill()
	_storage_bar_fill.modulate.a = 1.0


func _on_storage_item_drag_started(resource_id: StringName) -> void:
	if _current_building_id == "":
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance == null or instance.assigned_container_id == &"":
		return
	storage_drag_started.emit(resource_id, instance.assigned_container_id, instance.tile)


func _on_input_item_drag_started(resource_id: StringName) -> void:
	if _current_building_id == "":
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance == null or instance.cycle_running:
		return
	if instance.input_buffer.get(resource_id, 0.0) <= 0.0:
		return
	input_drag_started.emit(resource_id, _current_building_id, instance.tile)


func _on_output_item_drag_started(resource_id: StringName) -> void:
	if _current_building_id == "":
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance == null:
		return
	if instance.buffered_output.get(resource_id, 0) <= 0:
		return
	output_drag_started.emit(resource_id, _current_building_id, instance.tile)


func _refresh_production_zone(instance: BuildingRegistry.BuildingInstance) -> void:
	var is_production := (instance.type == BuildingRegistry.BuildingType.LUMBER_CAMP)
	_production_zone.visible = is_production
	if not is_production:
		return
	var input_qty: int = instance.input_buffer.get(&"tool", 0)
	_input_grid.populate([{&"resource_id": &"tool", &"quantity": input_qty}])
	_input_grid.modulate.a = 1.0 if input_qty > 0 else 0.35
	var table_entry: Dictionary = BuildingRegistry.PRODUCTION_TABLE.get(instance.type, {})
	var output_items: Array[Dictionary] = []
	for res_id: StringName in table_entry.get("output", {}):
		output_items.append({&"resource_id": res_id, &"quantity": instance.buffered_output.get(res_id, 0)})
	_output_grid.populate(output_items)
	_output_grid.modulate.a = 1.0 if not instance.buffered_output.is_empty() else 0.35
	var cycles_per_day: float = float(TickSystem.TICKS_PER_DAY) / float(_CYCLE_TICKS)
	_input_rate_label.text  = "%d / cycle  ·  ~%d / day" % [_INPUT_QTY,  int(cycles_per_day * _INPUT_QTY)]
	_output_rate_label.text = "%d / cycle  ·  ~%d / day" % [_OUTPUT_QTY, int(cycles_per_day * _OUTPUT_QTY)]



func _refresh_npc_zone(instance: BuildingRegistry.BuildingInstance) -> void:
	# Residential house spawns NPC automatically — no assign/release buttons.
	var is_residential := (instance.type == BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE)
	# Storage area has no NPC.
	var is_storage := (instance.type == BuildingRegistry.BuildingType.STORAGE_AREA
					or instance.type == BuildingRegistry.BuildingType.STORAGE_BUILDING)

	_npc_zone.visible = not is_storage

	if is_residential:
		if instance.state == BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
			_npc_label.text = "First NPC spawns on completion"
		else:
			_npc_label.text = "NPC: Resident (auto-assigned)"
		_assign_npc_btn.visible = false
		_release_npc_btn.visible = false
		return

	# Production buildings.
	var has_npc := (instance.state == BuildingRegistry.BuildingInstance.State.OPERATING
				or instance.state == BuildingRegistry.BuildingInstance.State.STALLED)
	if has_npc:
		_npc_label.text = "Worker (pending NPC system)"
		_npc_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		_assign_npc_btn.visible = false
		_release_npc_btn.visible = true
	else:
		_npc_label.text = "No NPC assigned"
		_npc_label.add_theme_color_override("font_color", COLOR_WARN)
		_assign_npc_btn.visible = (instance.state != BuildingRegistry.BuildingInstance.State.CONSTRUCTING)
		_release_npc_btn.visible = false


func _refresh_transport_zone(instance: BuildingRegistry.BuildingInstance) -> void:
	var is_production := (instance.type == BuildingRegistry.BuildingType.LUMBER_CAMP)
	_transport_zone.visible = is_production

	if not is_production:
		return

	# Transport system not yet implemented — show placeholder for both sides.
	_carrier_in_label.text = "No carrier"
	_carrier_in_label.add_theme_color_override("font_color", COLOR_WARN)
	_carrier_in_btn.visible = true

	_carrier_out_label.text = "No carrier"
	_carrier_out_label.add_theme_color_override("font_color", COLOR_WARN)
	_carrier_out_btn.visible = true

# ── Button callbacks ──────────────────────────────────────────────────────────

func _on_demolish_pressed() -> void:
	_open_demolish_dialog()


func _on_assign_npc_pressed() -> void:
	_open_npc_popup()


func _on_release_npc_pressed() -> void:
	BuildingRegistry.assign_npc(_current_building_id, &"")  # stub
	npc_released.emit(_current_building_id, &"")
	_refresh()



func _on_confirm_demolish_pressed() -> void:
	BuildingRegistry.demolish_building(_current_building_id)  # stub
	building_demolish_confirmed.emit(_current_building_id)
	_close_demolish_dialog()
	close()


func _on_cancel_demolish_pressed() -> void:
	building_demolish_cancelled.emit(_current_building_id)
	_close_demolish_dialog()


func _on_npc_cancel_pressed() -> void:
	npc_assignment_cancelled.emit(_current_building_id)
	_close_npc_popup()

# ── Sub-dialogs ───────────────────────────────────────────────────────────────

func _open_demolish_dialog() -> void:
	if _demolish_dialog == null:
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	var bname := BuildingRegistry._building_type_name(instance.type) if instance != null else "Building"
	var title_lbl: Label = _demolish_dialog.get_node_or_null("VBox/Title") as Label
	if title_lbl != null:
		title_lbl.text = "Demolish %s?" % bname
	_demolish_dialog.visible = true


func _close_demolish_dialog() -> void:
	if _demolish_dialog != null:
		_demolish_dialog.visible = false


func _open_npc_popup() -> void:
	if _npc_popup == null:
		return
	_npc_popup.visible = true


func _close_npc_popup() -> void:
	if _npc_popup != null:
		_npc_popup.visible = false

# ── Animation ─────────────────────────────────────────────────────────────────

func _animate_in() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = true
	modulate.a = 0.0
	scale = Vector2(0.95, 0.95)
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "modulate:a", 1.0, PANEL_ANIM_DURATION)
	_tween.tween_property(self, "scale", Vector2(1.0, 1.0), PANEL_ANIM_DURATION)


func _animate_out() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "modulate:a", 0.0, PANEL_ANIM_DURATION)
	_tween.tween_callback(func() -> void: visible = false)

# ── State helpers ─────────────────────────────────────────────────────────────

func _state_key(instance: BuildingRegistry.BuildingInstance) -> String:
	match instance.state:
		BuildingRegistry.BuildingInstance.State.CONSTRUCTING: return "CONSTRUCTING"
		BuildingRegistry.BuildingInstance.State.OPERATING:
			if BuildingRegistry.PRODUCTION_TABLE.has(instance.type):
				if instance.cycle_running:
					return "PRODUCING"
				return "IDLE"
			return "OPERATING"
		BuildingRegistry.BuildingInstance.State.BLOCKED:      return "BLOCKED"
		BuildingRegistry.BuildingInstance.State.STALLED:      return "STALLED"
		BuildingRegistry.BuildingInstance.State.DEMOLISHED:   return "IDLE"
	return "IDLE"


func _state_text(instance: BuildingRegistry.BuildingInstance) -> String:
	match instance.state:
		BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
			var total: int = instance.build_time
			var current: int = mini(instance.accumulated_ticks, total)
			var pct: int = int(float(current) / float(total) * 100.0) if total > 0 else 100
			return "Constructing — %d/%d ticks (%d%%)" % [current, total, pct]
		BuildingRegistry.BuildingInstance.State.OPERATING:
			if BuildingRegistry.PRODUCTION_TABLE.has(instance.type):
				if instance.cycle_running:
					return "Producing"
				return "Idle — %s" % _production_idle_reason(instance)
			return "Operating"
		BuildingRegistry.BuildingInstance.State.BLOCKED:
			return "Blocked — No NPC assigned"
		BuildingRegistry.BuildingInstance.State.STALLED:
			return "Stalled — Output buffer full"
		BuildingRegistry.BuildingInstance.State.DEMOLISHED:
			return "Demolished"
	return "Unknown"


func _production_idle_reason(instance: BuildingRegistry.BuildingInstance) -> String:
	if instance.assigned_npc_id == &"":
		return "No NPC assigned"
	var table_entry: Dictionary = BuildingRegistry.PRODUCTION_TABLE.get(instance.type, {})
	var buffered_total: int = 0
	for qty: int in instance.buffered_output.values():
		buffered_total += qty
	if buffered_total >= table_entry.get("output_capacity", 0):
		return "Output full"
	return "No input"

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_apply_panel_style(_panel)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	_build_header_zone(vbox)
	_build_separator(vbox)
	_build_progress_zone(vbox)
	_build_storage_zone(vbox)
	_build_npc_zone(vbox)
	_build_production_zone(vbox)
	_build_transport_zone(vbox)

	_build_demolish_dialog()
	_build_npc_popup()


func _build_header_zone(parent: VBoxContainer) -> void:
	var zone := VBoxContainer.new()
	zone.name = "HeaderZone"
	zone.add_theme_constant_override("separation", 4)
	parent.add_child(zone)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	zone.add_child(header_row)

	_name_label = Label.new()
	_name_label.text = "Building"
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", COLOR_TEXT)
	header_row.add_child(_name_label)

	_demolish_btn = Button.new()
	_demolish_btn.name = "DemolishBtn"
	_demolish_btn.text = "🗑"
	_demolish_btn.custom_minimum_size = Vector2(28, 28)
	_demolish_btn.focus_mode = Control.FOCUS_ALL
	_demolish_btn.tooltip_text = "Demolish building"
	_demolish_btn.pressed.connect(_on_demolish_pressed)
	_apply_secondary_btn_style(_demolish_btn)
	header_row.add_child(_demolish_btn)

	var close_btn := Button.new()
	close_btn.name = "CloseBtn"
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.tooltip_text = "Close"
	close_btn.pressed.connect(close)
	_apply_secondary_btn_style(close_btn)
	header_row.add_child(close_btn)

	var state_row := HBoxContainer.new()
	state_row.add_theme_constant_override("separation", 6)
	zone.add_child(state_row)

	_state_dot = ColorRect.new()
	_state_dot.custom_minimum_size = Vector2(10, 10)
	_state_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	state_row.add_child(_state_dot)

	_state_label = Label.new()
	_state_label.text = "—"
	_state_label.add_theme_font_size_override("font_size", 14)
	_state_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	state_row.add_child(_state_label)


func _build_progress_zone(parent: VBoxContainer) -> void:
	_progress_zone = VBoxContainer.new()
	_progress_zone.name = "ProgressZone"
	_progress_zone.add_theme_constant_override("separation", 4)
	_progress_zone.visible = false
	parent.add_child(_progress_zone)

	var bar_bg := Control.new()
	bar_bg.name = "ProgressBarBg"
	bar_bg.custom_minimum_size = Vector2(0, 12)

	var bg_rect := ColorRect.new()
	bg_rect.color = COLOR_PROGRESS_BG
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_bg.add_child(bg_rect)

	_progress_bar_fill = ColorRect.new()
	_progress_bar_fill.name = "Fill"
	_progress_bar_fill.color = COLOR_PROGRESS_FG
	_progress_bar_fill.position = Vector2.ZERO
	_progress_bar_fill.size = Vector2(0, 12)
	bar_bg.add_child(_progress_bar_fill)
	_progress_zone.add_child(bar_bg)

	_progress_label = Label.new()
	_progress_label.text = "0/0 ticks (0%)"
	_progress_label.add_theme_font_size_override("font_size", 13)
	_progress_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_progress_zone.add_child(_progress_label)
	_build_separator(parent)


func _build_storage_zone(parent: VBoxContainer) -> void:
	_storage_zone = VBoxContainer.new()
	_storage_zone.name = "StorageZone"
	_storage_zone.add_theme_constant_override("separation", 6)
	_storage_zone.visible = false
	parent.add_child(_storage_zone)

	var cap_row := HBoxContainer.new()
	cap_row.add_theme_constant_override("separation", 8)
	_storage_zone.add_child(cap_row)

	_storage_capacity_label = Label.new()
	_storage_capacity_label.name = "StorageCapacityLabel"
	_storage_capacity_label.text = "Storage: 0 / 0  0%"
	_storage_capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_capacity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_storage_capacity_label.add_theme_font_size_override("font_size", 13)
	_storage_capacity_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	cap_row.add_child(_storage_capacity_label)

	var bar_outer := Control.new()
	bar_outer.name = "StorageCapBarOuter"
	bar_outer.custom_minimum_size = Vector2(80, 8)
	bar_outer.size_flags_horizontal = Control.SIZE_SHRINK_END
	bar_outer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap_row.add_child(bar_outer)

	var bar_bg := ColorRect.new()
	bar_bg.color = Color("#333333")
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_outer.add_child(bar_bg)

	_storage_bar_fill = ColorRect.new()
	_storage_bar_fill.name = "StorageCapFill"
	_storage_bar_fill.color = COLOR_CAP_GREEN
	_storage_bar_fill.anchor_left = 0.0
	_storage_bar_fill.anchor_right = 0.0
	_storage_bar_fill.anchor_top = 0.0
	_storage_bar_fill.anchor_bottom = 1.0
	_storage_bar_fill.offset_right = 0
	_storage_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_outer.add_child(_storage_bar_fill)

	_storage_item_grid = ItemGrid.new()
	_storage_item_grid.name = "StorageItemGrid"
	_storage_item_grid.item_drag_started.connect(_on_storage_item_drag_started)
	_storage_zone.add_child(_storage_item_grid)

	_build_separator(parent)


func _build_production_zone(parent: VBoxContainer) -> void:
	_production_zone = VBoxContainer.new()
	_production_zone.name = "ProductionZone"
	_production_zone.add_theme_constant_override("separation", 6)
	_production_zone.visible = false
	parent.add_child(_production_zone)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 0)
	_production_zone.add_child(cols)

	var input_col := VBoxContainer.new()
	input_col.name = "InputCol"
	input_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_col.add_theme_constant_override("separation", 4)
	input_col.mouse_filter = Control.MOUSE_FILTER_STOP
	var input_header := Label.new()
	input_header.text = "Input"
	input_header.add_theme_font_size_override("font_size", 12)
	input_header.add_theme_color_override("font_color", COLOR_LINK)
	input_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	input_col.add_child(input_header)
	_input_grid = ItemGrid.new()
	_input_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_grid.center = true
	_input_grid.hide_empty = true
	_input_grid.item_drag_started.connect(_on_input_item_drag_started)
	input_col.add_child(_input_grid)
	_input_rate_label = Label.new()
	_input_rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input_rate_label.add_theme_font_size_override("font_size", 12)
	_input_rate_label.add_theme_color_override("font_color", COLOR_LINK)
	input_col.add_child(_input_rate_label)
	cols.add_child(input_col)
	_input_drop_zone = input_col
	_input_drop_zone.set_drag_forwarding(
		func(_pos: Vector2) -> Variant: return null,
		func(_pos: Vector2, data: Variant) -> bool: return _can_accept_drop(data),
		func(_pos: Vector2, data: Variant) -> void: _on_input_drop(data)
	)

	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 0)
	cols.add_child(sep)

	var output_col := VBoxContainer.new()
	output_col.name = "OutputCol"
	output_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_col.add_theme_constant_override("separation", 4)
	var output_header := Label.new()
	output_header.text = "Output"
	output_header.add_theme_font_size_override("font_size", 12)
	output_header.add_theme_color_override("font_color", COLOR_LINK)
	output_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	output_col.add_child(output_header)
	_output_grid = ItemGrid.new()
	_output_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output_grid.center = true
	_output_grid.hide_empty = true
	_output_grid.item_drag_started.connect(_on_output_item_drag_started)
	output_col.add_child(_output_grid)
	_output_rate_label = Label.new()
	_output_rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_output_rate_label.add_theme_font_size_override("font_size", 12)
	_output_rate_label.add_theme_color_override("font_color", COLOR_LINK)
	output_col.add_child(_output_rate_label)
	cols.add_child(output_col)

	_build_separator(parent)


func _build_npc_zone(parent: VBoxContainer) -> void:
	_npc_zone = VBoxContainer.new()
	_npc_zone.name = "NpcZone"
	_npc_zone.add_theme_constant_override("separation", 6)
	parent.add_child(_npc_zone)

	# Inline row: NPC label + release icon button (visible when NPC assigned).
	var npc_row := HBoxContainer.new()
	npc_row.add_theme_constant_override("separation", 6)
	_npc_zone.add_child(npc_row)

	_npc_label = Label.new()
	_npc_label.text = "No NPC assigned"
	_npc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_npc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_npc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_npc_label.add_theme_font_size_override("font_size", 14)
	_npc_label.add_theme_color_override("font_color", COLOR_WARN)
	npc_row.add_child(_npc_label)

	_release_npc_btn = Button.new()
	_release_npc_btn.name = "ReleaseNpcBtn"
	_release_npc_btn.text = "🧑"
	_release_npc_btn.custom_minimum_size = Vector2(28, 28)
	_release_npc_btn.visible = false
	_release_npc_btn.focus_mode = Control.FOCUS_ALL
	_release_npc_btn.tooltip_text = "Release NPC"
	_release_npc_btn.pressed.connect(_on_release_npc_pressed)
	_apply_secondary_btn_style(_release_npc_btn)
	npc_row.add_child(_release_npc_btn)

	_assign_npc_btn = Button.new()
	_assign_npc_btn.name = "AssignNpcBtn"
	_assign_npc_btn.text = "Assign NPC"
	_assign_npc_btn.focus_mode = Control.FOCUS_ALL
	_assign_npc_btn.pressed.connect(_on_assign_npc_pressed)
	_apply_primary_btn_style(_assign_npc_btn)
	_npc_zone.add_child(_assign_npc_btn)

	_build_separator(parent)


func _build_transport_zone(parent: VBoxContainer) -> void:
	_transport_zone = VBoxContainer.new()
	_transport_zone.name = "TransportZone"
	_transport_zone.add_theme_constant_override("separation", 6)
	parent.add_child(_transport_zone)

	var section_header := Label.new()
	section_header.text = "Transport"
	section_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section_header.add_theme_font_size_override("font_size", 12)
	section_header.add_theme_color_override("font_color", COLOR_LINK)
	_transport_zone.add_child(section_header)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 0)
	_transport_zone.add_child(cols)

	# Input column — button centered above label
	var input_col := VBoxContainer.new()
	input_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_col.add_theme_constant_override("separation", 4)
	input_col.alignment = BoxContainer.ALIGNMENT_CENTER
	var input_header := Label.new()
	input_header.text = "Input"
	input_header.add_theme_font_size_override("font_size", 12)
	input_header.add_theme_color_override("font_color", COLOR_LINK)
	input_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	input_col.add_child(input_header)
	_carrier_in_btn = Button.new()
	_carrier_in_btn.text = "🧑"
	_carrier_in_btn.custom_minimum_size = Vector2(28, 28)
	_carrier_in_btn.visible = false
	_carrier_in_btn.focus_mode = Control.FOCUS_ALL
	_carrier_in_btn.tooltip_text = "Assign carrier"
	_carrier_in_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_apply_secondary_btn_style(_carrier_in_btn)
	input_col.add_child(_carrier_in_btn)
	_carrier_in_label = Label.new()
	_carrier_in_label.add_theme_font_size_override("font_size", 13)
	_carrier_in_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	input_col.add_child(_carrier_in_label)
	cols.add_child(input_col)

	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 0)
	cols.add_child(sep)

	# Output column — button centered above label
	var output_col := VBoxContainer.new()
	output_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_col.add_theme_constant_override("separation", 4)
	output_col.alignment = BoxContainer.ALIGNMENT_CENTER
	var output_header := Label.new()
	output_header.text = "Output"
	output_header.add_theme_font_size_override("font_size", 12)
	output_header.add_theme_color_override("font_color", COLOR_LINK)
	output_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	output_col.add_child(output_header)
	_carrier_out_btn = Button.new()
	_carrier_out_btn.text = "🧑"
	_carrier_out_btn.custom_minimum_size = Vector2(28, 28)
	_carrier_out_btn.visible = false
	_carrier_out_btn.focus_mode = Control.FOCUS_ALL
	_carrier_out_btn.tooltip_text = "Assign carrier"
	_carrier_out_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_apply_secondary_btn_style(_carrier_out_btn)
	output_col.add_child(_carrier_out_btn)
	_carrier_out_label = Label.new()
	_carrier_out_label.add_theme_font_size_override("font_size", 13)
	_carrier_out_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	output_col.add_child(_carrier_out_label)
	cols.add_child(output_col)


func _build_demolish_dialog() -> void:
	_demolish_dialog = PanelContainer.new()
	_demolish_dialog.name = "DemolishDialog"
	_demolish_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_demolish_dialog.custom_minimum_size = Vector2(300, 0)
	_demolish_dialog.visible = false
	_apply_panel_style(_demolish_dialog)
	add_child(_demolish_dialog)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	_demolish_dialog.add_child(vbox)

	var icon_lbl := Label.new()
	icon_lbl.text = "⚠"
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 32)
	icon_lbl.add_theme_color_override("font_color", COLOR_ERR)
	vbox.add_child(icon_lbl)

	var title_lbl := Label.new()
	title_lbl.name = "Title"
	title_lbl.text = "Demolish Building?"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(title_lbl)

	var warn_lbl := Label.new()
	warn_lbl.text = "This action cannot be undone.\nNo resources will be refunded."
	warn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn_lbl.add_theme_font_size_override("font_size", 12)
	warn_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	vbox.add_child(warn_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var confirm_btn := Button.new()
	confirm_btn.name = "ConfirmBtn"
	confirm_btn.text = "Confirm Demolish"
	confirm_btn.custom_minimum_size = Vector2(140, 30)
	confirm_btn.focus_mode = Control.FOCUS_ALL
	confirm_btn.pressed.connect(_on_confirm_demolish_pressed)
	_apply_destructive_btn_style(confirm_btn)
	btn_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.name = "CancelBtn"
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(90, 30)
	cancel_btn.focus_mode = Control.FOCUS_ALL
	cancel_btn.pressed.connect(_on_cancel_demolish_pressed)
	_apply_secondary_btn_style(cancel_btn)
	btn_row.add_child(cancel_btn)


func _build_npc_popup() -> void:
	_npc_popup = PanelContainer.new()
	_npc_popup.name = "NpcPopup"
	_npc_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_npc_popup.custom_minimum_size = Vector2(240, 0)
	_npc_popup.visible = false
	_apply_panel_style(_npc_popup)
	add_child(_npc_popup)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_npc_popup.add_child(vbox)

	var header := Label.new()
	header.text = "Assign NPC"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(header)

	var placeholder := Label.new()
	placeholder.text = "No NPCs available\n(NPC system pending)"
	placeholder.add_theme_font_size_override("font_size", 13)
	placeholder.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(placeholder)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.focus_mode = Control.FOCUS_ALL
	cancel_btn.pressed.connect(_on_npc_cancel_pressed)
	_apply_secondary_btn_style(cancel_btn)
	vbox.add_child(cancel_btn)

# ── Style helpers ─────────────────────────────────────────────────────────────

func _build_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_SEP
	style.content_margin_top    = 0
	style.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", style)
	parent.add_child(sep)


func _apply_panel_style(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left   = 14
	style.content_margin_right  = 14
	style.content_margin_top    = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)


func _apply_primary_btn_style(btn: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = COLOR_BTN_HOVER if state == "hover" else (
			COLOR_BTN_NORMAL.darkened(0.2) if state == "pressed" else
			COLOR_BTN_NORMAL.darkened(0.4) if state == "disabled" else COLOR_BTN_NORMAL)
		s.corner_radius_top_left     = 3
		s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left  = 3
		s.corner_radius_bottom_right = 3
		s.content_margin_left   = 10
		s.content_margin_right  = 10
		s.content_margin_top    = 5
		s.content_margin_bottom = 5
		btn.add_theme_stylebox_override(state, s)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_font_size_override("font_size", 14)


func _apply_secondary_btn_style(btn: Button) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = COLOR_BTN_HOVER if state == "hover" else (
			COLOR_BTN_NORMAL.darkened(0.2) if state == "pressed" else COLOR_BTN_NORMAL.darkened(0.2))
		s.corner_radius_top_left     = 3
		s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left  = 3
		s.corner_radius_bottom_right = 3
		s.content_margin_left   = 8
		s.content_margin_right  = 8
		s.content_margin_top    = 4
		s.content_margin_bottom = 4
		btn.add_theme_stylebox_override(state, s)
	btn.add_theme_color_override("font_color", COLOR_BTN_TEXT)
	btn.add_theme_font_size_override("font_size", 13)


func _apply_destructive_btn_style(btn: Button) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = COLOR_BTN_DESTRUCT.lightened(0.1) if state == "hover" else (
			COLOR_BTN_DESTRUCT.darkened(0.2) if state == "pressed" else COLOR_BTN_DESTRUCT)
		s.corner_radius_top_left     = 3
		s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left  = 3
		s.corner_radius_bottom_right = 3
		s.content_margin_left   = 10
		s.content_margin_right  = 10
		s.content_margin_top    = 5
		s.content_margin_bottom = 5
		btn.add_theme_stylebox_override(state, s)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_font_size_override("font_size", 14)


func _apply_link_btn_style(btn: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxEmpty.new()
		btn.add_theme_stylebox_override(state, s)
	btn.add_theme_color_override("font_color", COLOR_LINK)
	btn.add_theme_color_override("font_hover_color", COLOR_BTN_HOVER)
	btn.add_theme_font_size_override("font_size", 13)
