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
signal npc_assigned(building_id: String, npc_id: StringName)
signal npc_released(building_id: String, npc_id: StringName)
signal npc_assignment_cancelled(building_id: String)
signal npc_detail_requested(npc_id: StringName, npc_state: int)
## role is "from" (output carrier — this building is the source) or
## "to" (input carrier — this building is the destination).
signal transport_management_opened(building_id: String, role: String)

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

var _panel:              DraggableWindow
var _state_dot:          ColorRect
var _state_label:        Label
var _efficiency_label:   Label
var _rename_btn:         Button

var _rename_dialog:      Control
var _rename_input:       LineEdit

var _progress_zone:      Control
var _progress_bar_fill:  ColorRect
var _progress_label:     Label

var _production_zone:      Control
var _production_input_col: Control
var _production_vsep:      Control
var _input_grid:           ItemGrid
var _input_drop_zone:      Control
var _input_rate_label:     Label
var _output_grid:          ItemGrid
var _output_rate_label:    Label

## Placeholder cycle constants until recipe system exists.
const _CYCLE_TICKS  := 120
const _INPUT_QTY    := 1
const _OUTPUT_QTY   := 5

var _npc_zone:              Control
var _npc_worker_col:        Control
var _npc_worker_tile:       PanelContainer
var _npc_worker_tile_style: StyleBoxFlat
var _npc_worker_icon_lbl:   Label
var _npc_worker_name_lbl:   Label
var _assign_npc_btn:        Button
var _release_npc_btn:       Button
var _worker_counter_label:  Label
var _npc_resident_grid:     NpcGrid
var _recruit_btn:           Button
var _npc_popup_title_lbl:   Label
var _npc_popup_grid:        NpcGrid

var _transport_zone:      Control
var _carrier_in_col:      Control
var _transport_vsep:      Control
var _carrier_in_flow:     HFlowContainer
var _carrier_in_btn:      Button
var _carrier_out_flow:    HFlowContainer
var _carrier_out_btn:     Button

var _storage_zone:              Control
var _storage_capacity_label:    Label
var _storage_bar_fill:          ColorRect
var _storage_item_grid:         ItemGrid

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
	if BuildingRegistry.building_renamed.is_connected(_on_building_renamed):
		BuildingRegistry.building_renamed.disconnect(_on_building_renamed)
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
	var npc_sys: Node = NPCSystem
	if npc_sys != null:
		if npc_sys.npc_recruited.is_connected(_on_npc_count_changed_recruited):
			npc_sys.npc_recruited.disconnect(_on_npc_count_changed_recruited)
		if npc_sys.npc_removed.is_connected(_on_npc_count_changed_removed):
			npc_sys.npc_removed.disconnect(_on_npc_count_changed_removed)
		if npc_sys.npc_assigned.is_connected(_on_npc_assignment_changed):
			npc_sys.npc_assigned.disconnect(_on_npc_assignment_changed)
		if npc_sys.npc_released.is_connected(_on_npc_released_signal):
			npc_sys.npc_released.disconnect(_on_npc_released_signal)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _current_building_id == "":
		return
	# Escape closes panel.
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		if _rename_dialog != null and _rename_dialog.visible:
			_close_rename_dialog()
		elif _npc_popup != null and _npc_popup.visible:
			_close_npc_popup()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	# Click outside panel closes it (only when no sub-dialog is open).
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		if _rename_dialog != null and _rename_dialog.visible:
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
	BuildingRegistry.building_renamed.connect(_on_building_renamed)
	TickSystem.ticks_advanced.connect(_on_ticks_advanced)
	InventorySystem.storage_changed.connect(_on_storage_changed)
	BuildingRegistry.building_input_changed.connect(_on_input_changed)
	BuildingRegistry.production_output_ready.connect(_on_production_output_ready)
	BuildingRegistry.building_output_changed.connect(_on_output_changed)
	var npc_sys: Node = NPCSystem
	if npc_sys != null:
		npc_sys.npc_recruited.connect(_on_npc_count_changed_recruited)
		npc_sys.npc_removed.connect(_on_npc_count_changed_removed)
		npc_sys.npc_assigned.connect(_on_npc_assignment_changed)
		npc_sys.npc_released.connect(_on_npc_released_signal)


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
		_refresh_transport_zone(instance)
		if instance.type == BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE:
			_refresh_npc_zone(instance)


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


func _on_building_renamed(building_id: String, _new_name: String) -> void:
	if building_id != _current_building_id or not visible:
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(building_id)
	if instance != null:
		_refresh_header(instance)


func _on_npc_count_changed_recruited(_npc_id: StringName, _home: Vector2i) -> void:
	if not visible or _current_building_id == "":
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance != null and instance.type == BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE:
		_refresh_npc_zone(instance)


func _on_npc_count_changed_removed(_npc_id: StringName) -> void:
	if not visible or _current_building_id == "":
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance != null and instance.type == BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE:
		_refresh_npc_zone(instance)


func _on_npc_assignment_changed(_npc_id: StringName, building_id: StringName) -> void:
	if not visible or str(building_id) != _current_building_id:
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance != null:
		_refresh_npc_zone(instance)


func _on_npc_released_signal(released_npc_id: StringName) -> void:
	if not visible or _current_building_id == "":
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance == null:
		return
	# Only refresh if the released NPC was assigned to the currently displayed building.
	if instance.assigned_npc_id == released_npc_id or instance.assigned_npc_id == &"":
		_refresh_npc_zone(instance)


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
	_panel.title = BuildingRegistry.get_building_display_name(instance.building_id)
	var state_key: String = _state_key(instance)
	var dot_color: Color = STATE_COLORS.get(state_key, Color.GRAY)
	_state_dot.color = dot_color
	_state_label.text = _state_text(instance)
	var eff: float = instance.efficiency
	_efficiency_label.text = "Eff: %d%%" % int(eff * 100.0)
	if eff >= 1.0:
		_efficiency_label.add_theme_color_override("font_color", COLOR_CAP_GREEN)
	elif eff >= 0.5:
		_efficiency_label.add_theme_color_override("font_color", COLOR_CAP_AMBER)
	else:
		_efficiency_label.add_theme_color_override("font_color", COLOR_CAP_RED)


func _refresh_progress(instance: BuildingRegistry.BuildingInstance) -> void:
	var is_constructing := instance.state == BuildingRegistry.BuildingInstance.State.CONSTRUCTING
	var is_producing := (instance.state == BuildingRegistry.BuildingInstance.State.OPERATING
		and (instance.cycle_running or _has_valid_input(instance)))
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
		current = instance.production_cycle_ticks if instance.cycle_running else 0
		label_prefix = "Production"
	var pct: float = float(current) / float(total) if total > 0 else 0.0
	_progress_bar_fill.size.x = _progress_bar_fill.get_parent().size.x * pct
	_progress_label.text = "%s: %d/%d ticks (%d%%)" % [label_prefix, current, total, int(pct * 100.0)]


func _refresh_progress_only() -> void:
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance != null:
		_refresh_progress(instance)


func _refresh_storage_zone(instance: BuildingRegistry.BuildingInstance) -> void:
	var is_storage := (instance.type == BuildingRegistry.BuildingType.COLLECTION_POINT
		or instance.type == BuildingRegistry.BuildingType.STORAGE_BUILDING)
	_storage_zone.visible = is_storage
	if not is_storage:
		return
	var container: InventoryContainer = InventorySystem.get_container(instance.assigned_container_id)
	if container == null:
		_storage_capacity_label.text = "Storage: —"
		_storage_item_grid.populate([])
		return
	var used := container.get_total_quantity() if container.quantity_based else container.get_occupied_count()
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
	var is_production := BuildingRegistry.PRODUCTION_TABLE.has(instance.type)
	_production_zone.visible = is_production
	if not is_production:
		return

	var is_gathering := (instance.type == BuildingRegistry.BuildingType.GATHERING_HUT)
	_production_input_col.visible = not is_gathering
	_production_vsep.visible = not is_gathering

	if not is_gathering:
		var table_entry: Dictionary = BuildingRegistry.PRODUCTION_TABLE.get(instance.type, {})
		var input_items: Array[Dictionary] = []
		var any_input := false
		for input_spec: Dictionary in table_entry.get("inputs", []):
			var res_id: StringName = input_spec["resource_id"]
			var have: int = int(instance.input_buffer.get(res_id, 0.0))
			input_items.append({&"resource_id": res_id, &"quantity": have})
			if have > 0:
				any_input = true
		_input_grid.populate(input_items)
		_input_grid.modulate.a = 1.0 if any_input else 0.35
		var rate_parts: Array[String] = []
		for input_spec: Dictionary in table_entry.get("inputs", []):
			var res_id: StringName = input_spec["resource_id"]
			var qty: int = int(input_spec.get("charge_cost", float(input_spec.get("quantity", 0))))
			rate_parts.append("%d %s" % [qty, str(res_id)])
		_input_rate_label.text = "  ·  ".join(rate_parts) + " / cycle"

	var output_items: Array[Dictionary] = []
	if is_gathering:
		for res_id: StringName in instance.gathering_output:
			output_items.append({&"resource_id": res_id,
				&"quantity": instance.buffered_output.get(res_id, 0)})
	else:
		var table_entry: Dictionary = BuildingRegistry.PRODUCTION_TABLE.get(instance.type, {})
		for res_id: StringName in table_entry.get("output", {}):
			output_items.append({&"resource_id": res_id,
				&"quantity": instance.buffered_output.get(res_id, 0)})
	_output_grid.populate(output_items)
	_output_grid.modulate.a = 1.0 if not instance.buffered_output.is_empty() else 0.35

	if is_gathering:
		if instance.gathering_output.is_empty():
			_output_rate_label.text = "No harvestable terrain"
		else:
			var parts: Array[String] = []
			for res_id: StringName in instance.gathering_output:
				parts.append("%d %s" % [instance.gathering_output[res_id], str(res_id)])
			_output_rate_label.text = "  ·  ".join(parts) + " / cycle"
	else:
		var cycles_per_day: float = float(TickSystem.TICKS_PER_DAY) / float(_CYCLE_TICKS)
		_output_rate_label.text = "%d / cycle  ·  ~%d / day" % [_OUTPUT_QTY, int(cycles_per_day * _OUTPUT_QTY)]



func _refresh_npc_zone(instance: BuildingRegistry.BuildingInstance) -> void:
	var is_residential := (instance.type == BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE)
	var is_storage := (instance.type == BuildingRegistry.BuildingType.COLLECTION_POINT
					or instance.type == BuildingRegistry.BuildingType.STORAGE_BUILDING)

	_npc_zone.visible = not is_storage

	if is_residential:
		# Show NPC tiles and recruit button; hide production NPC widgets.
		_npc_worker_col.visible = false
		_worker_counter_label.visible = false
		var npc_sys: Node = NPCSystem
		var count: int = npc_sys.get_house_npc_count(instance.tile) if npc_sys != null else 0
		var cap: int = npc_sys.NPC_CAPACITY_PER_HOUSE if npc_sys != null else 2
		if instance.state == BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
			_recruit_btn.visible = false
		else:
			_recruit_btn.visible = count < cap
			_recruit_btn.disabled = false
		_npc_resident_grid.visible = true
		var npc_ids: Array[StringName] = npc_sys.get_house_npcs(instance.tile) if npc_sys != null else []
		var npc_data: Array[Dictionary] = []
		for nid: StringName in npc_ids:
			npc_data.append({&"npc_id": nid, &"state": npc_sys.get_npc_state(nid),
				&"display_name": npc_sys.get_npc_display_name(nid)})
		_npc_resident_grid.populate(npc_data)
		return

	# Production buildings — hide residential widgets.
	_worker_counter_label.visible = false
	_npc_resident_grid.visible = false
	_recruit_btn.visible = false
	_npc_worker_col.visible = true

	var has_npc := instance.assigned_npc_id != &""
	if has_npc:
		_npc_worker_tile.modulate.a = 1.0
		_npc_worker_name_lbl.text = NPCSystem.get_npc_display_name(instance.assigned_npc_id)
		_assign_npc_btn.visible = false
		_release_npc_btn.visible = true
	else:
		_npc_worker_tile.modulate.a = 0.35
		_npc_worker_name_lbl.text = "—"
		_assign_npc_btn.visible = (instance.state != BuildingRegistry.BuildingInstance.State.CONSTRUCTING)
		_release_npc_btn.visible = false


func _refresh_transport_zone(instance: BuildingRegistry.BuildingInstance) -> void:
	var is_production := BuildingRegistry.PRODUCTION_TABLE.has(instance.type)
	_transport_zone.visible = is_production
	if not is_production:
		return

	var is_gathering := (instance.type == BuildingRegistry.BuildingType.GATHERING_HUT)
	_carrier_in_col.visible = not is_gathering
	_transport_vsep.visible = not is_gathering

	var bid := StringName(_current_building_id)

	var input_routes: Array[LogisticsRoute] = []
	var output_routes: Array[LogisticsRoute] = []
	for route: LogisticsRoute in LogisticsSystem.get_active_routes():
		if route.route_type == LogisticsRoute.RouteType.INPUT \
				and route.destination_building_id == bid:
			input_routes.append(route)
		elif route.route_type == LogisticsRoute.RouteType.OUTPUT \
				and route.source_building_id == bid:
			output_routes.append(route)

	_populate_transport_flow(_carrier_in_flow, input_routes)
	_carrier_in_btn.visible = input_routes.is_empty()

	_populate_transport_flow(_carrier_out_flow, output_routes)
	_carrier_out_btn.visible = output_routes.is_empty()


func _populate_transport_flow(flow: HFlowContainer, routes: Array[LogisticsRoute]) -> void:
	for child in flow.get_children():
		child.queue_free()
	for route: LogisticsRoute in routes:
		var res_id := _get_route_display_resource(route)
		var per_day := _get_route_trips_per_day(route)
		flow.add_child(_build_transport_route_tile(res_id, per_day, route))


func _build_transport_route_tile(resource_id: StringName, per_day: int, route: LogisticsRoute) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ItemGrid.BLOCK_WIDTH, ItemGrid.BLOCK_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = ItemGrid.COLOR_BLOCK_BG
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color = ItemGrid.COLOR_BLOCK_BORDER
	panel.add_theme_stylebox_override("panel", style)

	var eff: float = LogisticsSystem.get_route_efficiency(route)
	var eff_text: String
	var eff_color: Color
	if eff >= 1.0:
		eff_text = "Efficient"
		eff_color = COLOR_CAP_GREEN
	elif eff >= 0.5:
		eff_text = "Reduced"
		eff_color = COLOR_CAP_AMBER
	else:
		eff_text = "Blocked"
		eff_color = COLOR_CAP_RED
	panel.tooltip_text = "Efficiency: %s (%.0f%%)" % [eff_text, eff * 100.0]

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var icon_container := Control.new()
	icon_container.custom_minimum_size = Vector2(ItemGrid.ICON_SIZE, ItemGrid.ICON_SIZE)
	icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_container)

	var icon_lbl := Label.new()
	icon_lbl.text = _transport_resource_icon(resource_id)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_lbl.add_theme_font_size_override("font_size", 28)
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon_lbl)

	var rate_lbl := Label.new()
	rate_lbl.text = "~%d/day" % per_day if per_day > 0 else "—"
	rate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rate_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate_lbl.add_theme_font_size_override("font_size", 11)
	rate_lbl.add_theme_color_override("font_color", eff_color)
	rate_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rate_lbl)

	panel.mouse_entered.connect(func() -> void: style.border_color = ItemGrid.COLOR_HOVER_BORDER)
	panel.mouse_exited.connect(func() -> void:  style.border_color = ItemGrid.COLOR_BLOCK_BORDER)

	return panel


func _get_route_display_resource(route: LogisticsRoute) -> StringName:
	if route.source_item_id != &"":
		return route.source_item_id
	var instance := BuildingRegistry.get_building_instance(str(route.source_building_id))
	if instance == null:
		return &""
	if instance.type == BuildingRegistry.BuildingType.GATHERING_HUT:
		var keys := instance.gathering_output.keys()
		return keys[0] if not keys.is_empty() else &""
	var table_entry: Dictionary = BuildingRegistry.PRODUCTION_TABLE.get(instance.type, {})
	var out_keys: Array = table_entry.get("output", {}).keys()
	return out_keys[0] if not out_keys.is_empty() else &""


func _get_route_trips_per_day(route: LogisticsRoute) -> int:
	const TICKS_PER_DAY := 1000
	if route.path_valid and route.cached_path_cost > 0.0:
		var round_trip := int(route.cached_path_cost * 2.0)
		return TICKS_PER_DAY / round_trip if round_trip > 0 else 0
	var from_inst := BuildingRegistry.get_building_instance(str(route.source_building_id))
	var to_inst   := BuildingRegistry.get_building_instance(str(route.destination_building_id))
	if from_inst == null or to_inst == null:
		return 0
	var dist := absi(to_inst.tile.x - from_inst.tile.x) + absi(to_inst.tile.y - from_inst.tile.y)
	# Canonical logistics value (no local copy — avoids drift); nominal fed-carrier estimate.
	var round_trip := dist * 2 * int(LogisticsSystem.TICKS_PER_TILE)
	return TICKS_PER_DAY / round_trip if round_trip > 0 else 0


func _transport_resource_icon(resource_id: StringName) -> String:
	match resource_id:
		&"wood":  return "🪵"
		&"stone": return "🪨"
		&"berry": return "🫐"
		&"fiber": return "🌿"
		&"tool":  return "🪓"
		&"":      return "?"
		_:        return "📦"


func _get_building_short_name(building_id: String) -> String:
	return BuildingRegistry.get_building_display_name(building_id)

# ── Button callbacks ──────────────────────────────────────────────────────────

func _on_rename_pressed() -> void:
	_open_rename_dialog()


func _on_assign_npc_pressed() -> void:
	_open_npc_popup()


func _on_release_npc_pressed() -> void:
	var npc_sys: Node = NPCSystem
	var released_id: StringName = &""
	if npc_sys != null:
		released_id = npc_sys.get_assigned_npc(StringName(_current_building_id))
		if released_id != &"":
			npc_sys.release_npc(released_id)
	npc_released.emit(_current_building_id, released_id)
	_refresh()


func _on_recruit_pressed() -> void:
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance == null:
		return
	var npc_sys: Node = NPCSystem
	if npc_sys != null:
		npc_sys.recruit_npc(instance.tile)
	_refresh()



func _on_npc_cancel_pressed() -> void:
	npc_assignment_cancelled.emit(_current_building_id)
	_close_npc_popup()


func _on_resident_npc_clicked(npc_id: StringName) -> void:
	var npc_sys: Node = NPCSystem
	var state: int = npc_sys.get_npc_state(npc_id) if npc_sys != null else 0
	npc_detail_requested.emit(npc_id, state)


func _on_worker_tile_clicked() -> void:
	var npc_id := _get_assigned_npc_id()
	if npc_id == &"":
		return
	var npc_sys: Node = NPCSystem
	var state: int = npc_sys.get_npc_state(npc_id) if npc_sys != null else 0
	npc_detail_requested.emit(npc_id, state)


func _get_assigned_npc_id() -> StringName:
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	return instance.assigned_npc_id if instance != null else &""

# ── Sub-dialogs ───────────────────────────────────────────────────────────────

func _open_rename_dialog() -> void:
	if _rename_dialog == null or _current_building_id == "":
		return
	_rename_input.text = BuildingRegistry.get_building_display_name(_current_building_id)
	_rename_input.select_all()
	_rename_dialog.visible = true
	_rename_input.grab_focus()


func _close_rename_dialog() -> void:
	if _rename_dialog != null:
		_rename_dialog.visible = false


func _on_rename_confirmed() -> void:
	var new_name := _rename_input.text.strip_edges()
	BuildingRegistry.rename_building(_current_building_id, new_name)
	_close_rename_dialog()


func _open_npc_popup() -> void:
	if _npc_popup == null:
		return
	_populate_npc_popup()
	_npc_popup.visible = true


func _populate_npc_popup() -> void:
	if _npc_popup_grid == null:
		return
	var npc_sys: Node = NPCSystem
	var available: Array[StringName] = npc_sys.get_available_npcs() if npc_sys != null else []
	var data: Array[Dictionary] = []
	for npc_id: StringName in available:
		data.append({&"npc_id": npc_id, &"state": NPCSystem.TaskState.IDLE,
			&"display_name": npc_sys.get_npc_display_name(npc_id)})
	_npc_popup_grid.populate(data)


func _on_npc_popup_npc_selected(npc_id: StringName) -> void:
	if _current_building_id == "":
		_close_npc_popup()
		return
	var npc_sys: Node = NPCSystem
	if npc_sys != null:
		var result: int = npc_sys.assign_npc(npc_id, StringName(_current_building_id), &"")
		if result == 0:  # NPCSystem.AssignmentResult.SUCCESS
			npc_assigned.emit(_current_building_id, npc_id)
	_close_npc_popup()
	_refresh()


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
			if instance.type == BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE:
				var npc_sys: Node = NPCSystem
				var count: int = npc_sys.get_house_npc_count(instance.tile) if npc_sys != null else 0
				var cap: int = npc_sys.NPC_CAPACITY_PER_HOUSE if npc_sys != null else 2
				return "%d/%d Villagers" % [count, cap]
			return "Operating"
		BuildingRegistry.BuildingInstance.State.BLOCKED:
			return "Blocked — " + _production_idle_reason(instance)
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


func _has_valid_input(instance: BuildingRegistry.BuildingInstance) -> bool:
	var table_entry: Dictionary = BuildingRegistry.PRODUCTION_TABLE.get(instance.type, {})
	var inputs: Array = table_entry.get("inputs", [])
	if inputs.is_empty():
		return false
	for input_spec: Dictionary in inputs:
		var resource_id: StringName = input_spec["resource_id"]
		var needed: float = input_spec.get("charge_cost", float(input_spec.get("quantity", 0)))
		if instance.input_buffer.get(resource_id, 0.0) < needed:
			return false
	return true

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = DraggableWindow.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.close_requested.connect(close)
	add_child(_panel)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 14)
	body_margin.add_theme_constant_override("margin_right", 14)
	body_margin.add_theme_constant_override("margin_top", 12)
	body_margin.add_theme_constant_override("margin_bottom", 12)
	_panel.content.add_child(body_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	body_margin.add_child(vbox)

	_build_header_zone(vbox)
	_build_separator(vbox)
	_build_progress_zone(vbox)
	_build_storage_zone(vbox)
	_build_npc_zone(vbox)
	_build_production_zone(vbox)
	_build_transport_zone(vbox)

	_build_rename_dialog()
	_build_npc_popup()


func _build_header_zone(parent: VBoxContainer) -> void:
	var zone := VBoxContainer.new()
	zone.name = "HeaderZone"
	zone.add_theme_constant_override("separation", 4)
	parent.add_child(zone)

	# Building name lives in the DraggableWindow title bar (set in _refresh).
	# The header row keeps the rename button, aligned right; the window
	# provides the close (✕) button.
	var header_row := HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_END
	header_row.add_theme_constant_override("separation", 8)
	zone.add_child(header_row)

	_rename_btn = Button.new()
	_rename_btn.name = "RenameBtn"
	_rename_btn.text = "✏"
	_rename_btn.custom_minimum_size = Vector2(28, 28)
	_rename_btn.focus_mode = Control.FOCUS_ALL
	_rename_btn.tooltip_text = "Rename building"
	_rename_btn.pressed.connect(_on_rename_pressed)
	_apply_secondary_btn_style(_rename_btn)
	header_row.add_child(_rename_btn)

	var state_row := HBoxContainer.new()
	state_row.add_theme_constant_override("separation", 6)
	zone.add_child(state_row)

	_state_dot = ColorRect.new()
	_state_dot.custom_minimum_size = Vector2(10, 10)
	_state_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	state_row.add_child(_state_dot)

	_state_label = Label.new()
	_state_label.text = "—"
	_state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state_label.add_theme_font_size_override("font_size", 14)
	_state_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	state_row.add_child(_state_label)

	_efficiency_label = Label.new()
	_efficiency_label.text = "Efficiency: 100%"
	_efficiency_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_efficiency_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_efficiency_label.add_theme_font_size_override("font_size", 12)
	_efficiency_label.add_theme_color_override("font_color", COLOR_CAP_GREEN)
	state_row.add_child(_efficiency_label)


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
	_production_input_col = input_col
	_input_drop_zone.set_drag_forwarding(
		func(_pos: Vector2) -> Variant: return null,
		func(_pos: Vector2, data: Variant) -> bool: return _can_accept_drop(data),
		func(_pos: Vector2, data: Variant) -> void: _on_input_drop(data)
	)

	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 0)
	cols.add_child(sep)
	_production_vsep = sep

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

	# Production building worker tile + action button (centered column).
	_npc_worker_col = VBoxContainer.new()
	_npc_worker_col.name = "NpcWorkerCol"
	_npc_worker_col.add_theme_constant_override("separation", 4)
	_npc_worker_col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_npc_zone.add_child(_npc_worker_col)

	_npc_worker_tile = PanelContainer.new()
	_npc_worker_tile.name = "NpcWorkerTile"
	_npc_worker_tile.custom_minimum_size = Vector2(NpcGrid.BLOCK_WIDTH, NpcGrid.BLOCK_HEIGHT)
	_npc_worker_tile.mouse_filter = Control.MOUSE_FILTER_STOP
	_npc_worker_tile_style = StyleBoxFlat.new()
	_npc_worker_tile_style.bg_color = NpcGrid.COLOR_BLOCK_BG
	_npc_worker_tile_style.border_width_left   = 1
	_npc_worker_tile_style.border_width_right  = 1
	_npc_worker_tile_style.border_width_top    = 1
	_npc_worker_tile_style.border_width_bottom = 1
	_npc_worker_tile_style.border_color = NpcGrid.COLOR_BLOCK_BORDER
	_npc_worker_tile.add_theme_stylebox_override("panel", _npc_worker_tile_style)
	_npc_worker_tile.mouse_entered.connect(func() -> void:
		if _get_assigned_npc_id() != &"":
			_npc_worker_tile_style.border_color = NpcGrid.COLOR_HOVER_BORDER)
	_npc_worker_tile.mouse_exited.connect(func() -> void:
		_npc_worker_tile_style.border_color = NpcGrid.COLOR_BLOCK_BORDER)
	_npc_worker_tile.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_worker_tile_clicked())
	_npc_worker_col.add_child(_npc_worker_tile)

	var tile_vbox := VBoxContainer.new()
	tile_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tile_vbox.add_theme_constant_override("separation", 2)
	_npc_worker_tile.add_child(tile_vbox)

	var icon_container := Control.new()
	icon_container.custom_minimum_size   = Vector2(NpcGrid.ICON_SIZE, NpcGrid.ICON_SIZE)
	icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_container.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	tile_vbox.add_child(icon_container)

	_npc_worker_icon_lbl = Label.new()
	_npc_worker_icon_lbl.text                 = "🧑"
	_npc_worker_icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_npc_worker_icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_npc_worker_icon_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_npc_worker_icon_lbl.add_theme_font_size_override("font_size", 24)
	_npc_worker_icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(_npc_worker_icon_lbl)

	_npc_worker_name_lbl = Label.new()
	_npc_worker_name_lbl.text                  = "—"
	_npc_worker_name_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_npc_worker_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_npc_worker_name_lbl.add_theme_font_size_override("font_size", 11)
	_npc_worker_name_lbl.add_theme_color_override("font_color", NpcGrid.COLOR_TEXT_DIM)
	_npc_worker_name_lbl.clip_text   = true
	_npc_worker_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_vbox.add_child(_npc_worker_name_lbl)

	_assign_npc_btn = Button.new()
	_assign_npc_btn.name = "AssignNpcBtn"
	_assign_npc_btn.text = "Assign"
	_assign_npc_btn.custom_minimum_size = Vector2(NpcGrid.BLOCK_WIDTH, 0)
	_assign_npc_btn.visible = false
	_assign_npc_btn.focus_mode = Control.FOCUS_ALL
	_assign_npc_btn.pressed.connect(_on_assign_npc_pressed)
	_apply_primary_btn_style(_assign_npc_btn)
	_npc_worker_col.add_child(_assign_npc_btn)

	_release_npc_btn = Button.new()
	_release_npc_btn.name = "ReleaseNpcBtn"
	_release_npc_btn.text = "Remove"
	_release_npc_btn.custom_minimum_size = Vector2(NpcGrid.BLOCK_WIDTH, 0)
	_release_npc_btn.visible = false
	_release_npc_btn.focus_mode = Control.FOCUS_ALL
	_release_npc_btn.pressed.connect(_on_release_npc_pressed)
	_apply_destructive_btn_style(_release_npc_btn)
	_npc_worker_col.add_child(_release_npc_btn)

	_worker_counter_label = Label.new()
	_worker_counter_label.name = "WorkerCounterLabel"
	_worker_counter_label.text = "0/2 workers"
	_worker_counter_label.visible = false
	_worker_counter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_worker_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_worker_counter_label.add_theme_font_size_override("font_size", 14)
	_worker_counter_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_npc_zone.add_child(_worker_counter_label)

	_npc_resident_grid = NpcGrid.new()
	_npc_resident_grid.name    = "NpcResidentGrid"
	_npc_resident_grid.center  = true
	_npc_resident_grid.visible = false
	_npc_resident_grid.npc_clicked.connect(_on_resident_npc_clicked)
	_npc_zone.add_child(_npc_resident_grid)

	_recruit_btn = Button.new()
	_recruit_btn.name = "RecruitBtn"
	_recruit_btn.text = "Recruit"
	_recruit_btn.visible = false
	_recruit_btn.focus_mode = Control.FOCUS_ALL
	_recruit_btn.pressed.connect(_on_recruit_pressed)
	_apply_primary_btn_style(_recruit_btn)
	_npc_zone.add_child(_recruit_btn)

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

	# Input column
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
	_carrier_in_flow = HFlowContainer.new()
	_carrier_in_flow.add_theme_constant_override("h_separation", ItemGrid.BLOCK_GAP)
	_carrier_in_flow.add_theme_constant_override("v_separation", ItemGrid.BLOCK_GAP)
	_carrier_in_flow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	input_col.add_child(_carrier_in_flow)
	_carrier_in_btn = Button.new()
	_carrier_in_btn.text = "🧑 Assign"
	_carrier_in_btn.visible = true
	_carrier_in_btn.focus_mode = Control.FOCUS_ALL
	_carrier_in_btn.tooltip_text = "Assign input carrier via Transportation panel"
	_carrier_in_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_carrier_in_btn.pressed.connect(
		func() -> void: transport_management_opened.emit(_current_building_id, "to"))
	_apply_secondary_btn_style(_carrier_in_btn)
	input_col.add_child(_carrier_in_btn)
	cols.add_child(input_col)
	_carrier_in_col = input_col

	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 0)
	cols.add_child(sep)
	_transport_vsep = sep

	# Output column
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
	_carrier_out_flow = HFlowContainer.new()
	_carrier_out_flow.add_theme_constant_override("h_separation", ItemGrid.BLOCK_GAP)
	_carrier_out_flow.add_theme_constant_override("v_separation", ItemGrid.BLOCK_GAP)
	_carrier_out_flow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	output_col.add_child(_carrier_out_flow)
	_carrier_out_btn = Button.new()
	_carrier_out_btn.text = "🧑 Assign"
	_carrier_out_btn.visible = true
	_carrier_out_btn.focus_mode = Control.FOCUS_ALL
	_carrier_out_btn.tooltip_text = "Assign output carrier via Transportation panel"
	_carrier_out_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_carrier_out_btn.pressed.connect(
		func() -> void: transport_management_opened.emit(_current_building_id, "from"))
	_apply_secondary_btn_style(_carrier_out_btn)
	output_col.add_child(_carrier_out_btn)
	cols.add_child(output_col)


func _build_rename_dialog() -> void:
	_rename_dialog = PanelContainer.new()
	_rename_dialog.name = "RenameDialog"
	_rename_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_rename_dialog.custom_minimum_size = Vector2(280, 0)
	_rename_dialog.visible = false
	_apply_panel_style(_rename_dialog)
	add_child(_rename_dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_rename_dialog.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "Rename Building"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(title_lbl)

	_rename_input = LineEdit.new()
	_rename_input.name = "RenameInput"
	_rename_input.placeholder_text = "Enter building name..."
	_rename_input.clear_button_enabled = true
	_rename_input.add_theme_font_size_override("font_size", 14)
	_rename_input.text_submitted.connect(func(_t: String) -> void: _on_rename_confirmed())
	vbox.add_child(_rename_input)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var confirm_btn := Button.new()
	confirm_btn.text = "Rename"
	confirm_btn.custom_minimum_size = Vector2(100, 30)
	confirm_btn.focus_mode = Control.FOCUS_ALL
	confirm_btn.pressed.connect(_on_rename_confirmed)
	_apply_primary_btn_style(confirm_btn)
	btn_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(80, 30)
	cancel_btn.focus_mode = Control.FOCUS_ALL
	cancel_btn.pressed.connect(_close_rename_dialog)
	_apply_secondary_btn_style(cancel_btn)
	btn_row.add_child(cancel_btn)


func _build_npc_popup() -> void:
	_npc_popup = PanelContainer.new()
	_npc_popup.name = "NpcPopup"
	_npc_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_npc_popup.custom_minimum_size = Vector2(300, 0)
	_npc_popup.visible = false
	_apply_panel_style(_npc_popup)
	add_child(_npc_popup)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_npc_popup.add_child(vbox)

	_npc_popup_title_lbl = Label.new()
	_npc_popup_title_lbl.name = "NpcPopupTitle"
	_npc_popup_title_lbl.text = "Select Worker"
	_npc_popup_title_lbl.add_theme_font_size_override("font_size", 14)
	_npc_popup_title_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(_npc_popup_title_lbl)

	_npc_popup_grid = NpcGrid.new()
	_npc_popup_grid.name = "NpcPopupGrid"
	_npc_popup_grid.center = true
	_npc_popup_grid.npc_clicked.connect(_on_npc_popup_npc_selected)
	vbox.add_child(_npc_popup_grid)

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
