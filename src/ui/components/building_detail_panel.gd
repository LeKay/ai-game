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
## Fired when the player clicks an existing transport route tile to edit it.
signal transport_route_edit_requested(route: LogisticsRoute)

# ── Constants ─────────────────────────────────────────────────────────────────

const PANEL_WIDTH       := 380
const PANEL_ANIM_DURATION := 0.20  ## 200ms per UX spec
const COLOR_BG          := UiPalette.PANEL_BG  ## #2D2D2D
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
const COLOR_SEP         := UiPalette.SEPARATOR
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
var _output_grid:          ItemGrid

## Placeholder cycle constants until recipe system exists.
const _CYCLE_TICKS  := 120
const _INPUT_QTY    := 1
const _OUTPUT_QTY   := 5

var _npc_zone:              Control
var _npc_worker_col:        Control
var _npc_worker_grid: NpcGrid
var _assign_npc_btn:        Button
var _release_npc_btn:       Button
var _worker_counter_label:  Label
var _npc_resident_grid:     NpcGrid
var _recruit_btn:           Button
var _npc_popup_title_lbl:   Label
var _npc_popup_grid:        NpcGrid

var _recruit_dialog:        Control
var _recruit_food_option:   OptionButton
var _recruit_body_lbl:      Label
var _recruit_confirm_btn:   Button

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
var _storage_config_btn:        Button
var _storage_normal_zone:       Control
var _storage_config_zone:       Control
var _storage_config_toggle:     HBoxContainer
var _storage_config_rows:       VBoxContainer

var _npc_popup:          Control

var _upgrade_btn:        Button
var _upgrade_zone:       Control
var _recipes_btn:        Button
var _content_body:       VBoxContainer
var _recipe_view:        VBoxContainer
var _player:             PlayerCharacter = null

## Separator nodes between zones — hidden when the preceding zone is hidden.
var _sep_progress:   HSeparator
var _sep_storage:    HSeparator
var _sep_npc:        HSeparator
var _sep_production: HSeparator

# ── State ─────────────────────────────────────────────────────────────────────

var _current_building_id: String = ""
var _tween: Tween = null
var _storage_pulse_tween: Tween = null
var _is_storage_pulsing: bool = false
var _storage_config_mode: bool = false
## "min" = editing minimum reserves, "max" = editing delivery caps.
var _storage_limit_mode: String = "max"
var _upgrade_zone_open: bool = false
var _recipe_view_open: bool = false
## True while the forced recipe view is showing (building has no recipe picked yet):
## no recipe is highlighted as active, so every available recipe (including the
## default) is clickable to select.
var _force_recipe_pick: bool = false


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()
	_connect_registry()
	call_deferred("_connect_player")
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
	if BuildingRegistry.building_recipe_changed.is_connected(_on_recipe_changed):
		BuildingRegistry.building_recipe_changed.disconnect(_on_recipe_changed)
	if BuildingRegistry.building_storage_limit_changed.is_connected(_on_storage_limit_changed):
		BuildingRegistry.building_storage_limit_changed.disconnect(_on_storage_limit_changed)
	if BuildingRegistry.building_storage_min_limit_changed.is_connected(_on_storage_min_limit_changed):
		BuildingRegistry.building_storage_min_limit_changed.disconnect(_on_storage_min_limit_changed)
	if BuildingRegistry.upgrade_installed.is_connected(_on_upgrade_installed):
		BuildingRegistry.upgrade_installed.disconnect(_on_upgrade_installed)
	if _player != null:
		if _player.action_started.is_connected(_on_player_action_started):
			_player.action_started.disconnect(_on_player_action_started)
		if _player.action_completed.is_connected(_on_player_action_completed):
			_player.action_completed.disconnect(_on_player_action_completed)
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
		elif _recruit_dialog != null and _recruit_dialog.visible:
			_close_recruit_dialog()
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
		if _recruit_dialog != null and _recruit_dialog.visible:
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
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(building_id)
	# Until the player has picked a recipe, a production building opens straight
	# into the recipe selection view (re-shown on every open until a choice is made).
	var show_recipes := instance != null \
		and BuildingRegistry.is_production_building(instance.type) \
		and not instance.recipe_selected
	_force_recipe_pick = show_recipes
	_recipe_view_open = show_recipes
	_content_body.visible = not show_recipes
	_recipe_view.visible = show_recipes
	_refresh()
	if show_recipes:
		_rebuild_recipe_view(instance)
	var tile := instance.tile if instance != null else Vector2i.ZERO
	building_selected.emit(building_id, tile)
	_animate_in()


## Hides the panel.
func close() -> void:
	if _current_building_id != "":
		building_deselected.emit(_current_building_id)
	_current_building_id = ""
	_storage_config_mode = false
	_storage_limit_mode = "max"
	_recipe_view_open = false
	_force_recipe_pick = false
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
	BuildingRegistry.building_recipe_changed.connect(_on_recipe_changed)
	BuildingRegistry.building_storage_limit_changed.connect(_on_storage_limit_changed)
	BuildingRegistry.building_storage_min_limit_changed.connect(_on_storage_min_limit_changed)
	BuildingRegistry.upgrade_installed.connect(_on_upgrade_installed)
	var npc_sys: Node = NPCSystem
	if npc_sys != null:
		npc_sys.npc_recruited.connect(_on_npc_count_changed_recruited)
		npc_sys.npc_removed.connect(_on_npc_count_changed_removed)
		npc_sys.npc_assigned.connect(_on_npc_assignment_changed)
		npc_sys.npc_released.connect(_on_npc_released_signal)
		npc_sys.npc_renamed.connect(_on_npc_renamed)


func _connect_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player_character") as PlayerCharacter
	if _player == null:
		return
	_player.action_started.connect(_on_player_action_started)
	_player.action_completed.connect(_on_player_action_completed)


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


func _on_production_output_ready(building_id: String, _output: Dictionary, _cycle_ticks: int) -> void:
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


func _on_upgrade_installed(building_id: String, _upgrade_id: StringName) -> void:
	if building_id != _current_building_id or not visible:
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(building_id)
	if instance != null:
		_refresh_header(instance)
		_refresh_upgrade_zone(instance)


func _on_player_action_started(action_id: int, _tick_cost: int, _tile: Vector2i) -> void:
	if action_id != PlayerCharacter.ManualActionType.INSTALL_UPGRADE:
		return
	if not visible or not _upgrade_zone_open:
		return
	if _player == null or _player.get_active_building_id() != _current_building_id:
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance != null:
		_refresh_upgrade_zone(instance)


func _on_player_action_completed(action_id: int, _output: Array) -> void:
	if action_id != PlayerCharacter.ManualActionType.INSTALL_UPGRADE:
		return
	if not visible or not _upgrade_zone_open:
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance != null:
		_refresh_upgrade_zone(instance)


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


func _on_npc_renamed(_npc_id: StringName, _new_name: String) -> void:
	if not visible or _current_building_id == "":
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
	var allowed: Array[StringName] = BuildingRegistry.get_active_input_resource_ids(_current_building_id)
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
	_upgrade_zone_open = false
	_upgrade_zone.visible = false
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
	# Storage and residential buildings have no production, so efficiency is meaningless for them.
	var hide_efficiency: bool = instance.type == BuildingRegistry.BuildingType.STORAGE_BUILDING \
		or instance.type == BuildingRegistry.BuildingType.COLLECTION_POINT \
		or instance.type == BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE
	_efficiency_label.visible = not hide_efficiency
	if not hide_efficiency:
		var eff: float = instance.efficiency
		_efficiency_label.text = "Eff: %d%%" % int(eff * 100.0)
		_efficiency_label.tooltip_text = _building_efficiency_tooltip(instance)
		if eff >= 1.0:
			_efficiency_label.add_theme_color_override("font_color", COLOR_CAP_GREEN)
		elif eff >= 0.5:
			_efficiency_label.add_theme_color_override("font_color", COLOR_CAP_AMBER)
		else:
			_efficiency_label.add_theme_color_override("font_color", COLOR_CAP_RED)
	var available_upgrades: Array = BuildingRegistry.get_available_upgrades(instance.building_id)
	var has_upgrades := not available_upgrades.is_empty()
	if _upgrade_btn != null:
		_upgrade_btn.visible = has_upgrades
	if _recipes_btn != null:
		_recipes_btn.visible = BuildingRegistry.is_production_building(instance.type)
		_recipes_btn.text = "✕" if _recipe_view_open else "⚙"


## Hover breakdown for the building efficiency label (additive model):
## base + resource tiles × 5% + assigned worker's efficiency (+ upgrades), clamped at the cap.
func _building_efficiency_tooltip(instance: BuildingRegistry.BuildingInstance) -> String:
	var base: float = EfficiencyFormulas.BUILDING_BASE_EFFICIENCY
	var tiles: int = instance.adjacency_tile_count
	var tile_bonus: float = float(tiles) * EfficiencyFormulas.ADJACENCY_EFFICIENCY_PER_TILE
	var worker_eff: float = 0.0
	var worker_name: String = ""
	if instance.assigned_npc_id != &"":
		var w: Object = NPCSystem.get_npc_instance(instance.assigned_npc_id)
		if w != null:
			worker_eff = w.efficiency
			worker_name = NPCSystem.get_npc_display_name(instance.assigned_npc_id)
	var raw: float = base + tile_bonus + worker_eff + instance.upgrade_bonus

	var lines: PackedStringArray = PackedStringArray()
	lines.append("Efficiency breakdown")
	lines.append("Base: %d%%" % roundi(base * 100.0))
	if tiles > 0:
		lines.append("Resource tiles: %d × 5%% = +%d%%" % [tiles, roundi(tile_bonus * 100.0)])
	if instance.assigned_npc_id != &"":
		lines.append("Worker (%s): +%d%%" % [worker_name, roundi(worker_eff * 100.0)])
	else:
		lines.append("Worker: none (+0%)")
	if instance.upgrade_bonus > 0.0:
		lines.append("Upgrades: +%d%%" % roundi(instance.upgrade_bonus * 100.0))
	var cap: float = EfficiencyFormulas.BUILDING_EFFICIENCY_MAX
	if raw > cap:
		lines.append("= %d%% (capped at %d%%)" % [roundi(cap * 100.0), roundi(cap * 100.0)])
	else:
		lines.append("= %d%%" % roundi(raw * 100.0))
	return "\n".join(lines)


func _refresh_progress(instance: BuildingRegistry.BuildingInstance) -> void:
	var is_constructing := instance.state == BuildingRegistry.BuildingInstance.State.CONSTRUCTING
	var is_producing := (instance.state == BuildingRegistry.BuildingInstance.State.OPERATING
		and (instance.cycle_running or _has_valid_input(instance)))
	_progress_zone.visible = is_constructing or is_producing
	_sep_progress.visible = _progress_zone.visible
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
	_sep_storage.visible = is_storage
	_storage_config_btn.visible = is_storage
	if not is_storage:
		return
	_storage_normal_zone.visible = not _storage_config_mode
	_storage_config_zone.visible = _storage_config_mode
	_storage_config_btn.text = "✕" if _storage_config_mode else "⚙"
	if _storage_config_mode:
		_refresh_storage_config()
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


func _on_storage_config_pressed() -> void:
	_storage_config_mode = not _storage_config_mode
	_storage_limit_mode = "max"
	_storage_config_btn.text = "✕" if _storage_config_mode else "⚙"
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance != null:
		_refresh_storage_zone(instance)


func _refresh_storage_config() -> void:
	for child in _storage_config_rows.get_children():
		child.queue_free()
	for child in _storage_config_toggle.get_children():
		child.queue_free()
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance == null:
		return
	var cap: int = InventorySystem.get_capacity(instance.assigned_container_id)

	# Mode toggle header — built into the persistent container outside the
	# scroll so it stays pinned above the scrolling resource rows.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_config_toggle.add_child(spacer)

	var min_btn := Button.new()
	min_btn.text = "Min"
	min_btn.custom_minimum_size = Vector2(44, 22)
	min_btn.focus_mode = Control.FOCUS_NONE
	min_btn.tooltip_text = "Set minimum reserve (transport won't take below this)"
	_storage_config_toggle.add_child(min_btn)

	var max_btn := Button.new()
	max_btn.text = "Max"
	max_btn.custom_minimum_size = Vector2(44, 22)
	max_btn.focus_mode = Control.FOCUS_NONE
	max_btn.tooltip_text = "Set delivery cap (transport won't deliver above this)"
	_storage_config_toggle.add_child(max_btn)

	_apply_storage_mode_btn_styles(min_btn, max_btn, _storage_limit_mode)
	min_btn.pressed.connect(func() -> void:
		_storage_limit_mode = "min"
		_refresh_storage_config()
	)
	max_btn.pressed.connect(func() -> void:
		_storage_limit_mode = "max"
		_refresh_storage_config()
	)

	var all_ids: Array[StringName] = ResourceRegistry.get_all_resource_ids()
	for res_id: StringName in all_ids:
		var current_limit: int
		if _storage_limit_mode == "min":
			current_limit = BuildingRegistry.get_storage_min_limit(_current_building_id, res_id)
		else:
			current_limit = BuildingRegistry.get_storage_limit(_current_building_id, res_id)
		var row := _build_limit_row(res_id, current_limit, cap)
		_storage_config_rows.add_child(row)


func _apply_storage_mode_btn_styles(min_btn: Button, max_btn: Button, mode: String) -> void:
	var active_color   := Color(0.290, 0.494, 0.659)   ## COLOR_BTN_HOVER
	var inactive_color := Color(0.353, 0.353, 0.353)   ## COLOR_BTN_NORMAL
	var active_style  := StyleBoxFlat.new()
	active_style.bg_color = active_color
	active_style.corner_radius_top_left = 3
	active_style.corner_radius_top_right = 3
	active_style.corner_radius_bottom_left = 3
	active_style.corner_radius_bottom_right = 3
	active_style.content_margin_left = 6
	active_style.content_margin_right = 6
	var inactive_style := StyleBoxFlat.new()
	inactive_style.bg_color = inactive_color
	inactive_style.corner_radius_top_left = 3
	inactive_style.corner_radius_top_right = 3
	inactive_style.corner_radius_bottom_left = 3
	inactive_style.corner_radius_bottom_right = 3
	inactive_style.content_margin_left = 6
	inactive_style.content_margin_right = 6
	if mode == "min":
		min_btn.add_theme_stylebox_override("normal", active_style)
		min_btn.add_theme_stylebox_override("hover", active_style)
		max_btn.add_theme_stylebox_override("normal", inactive_style)
		max_btn.add_theme_stylebox_override("hover", inactive_style)
	else:
		max_btn.add_theme_stylebox_override("normal", active_style)
		max_btn.add_theme_stylebox_override("hover", active_style)
		min_btn.add_theme_stylebox_override("normal", inactive_style)
		min_btn.add_theme_stylebox_override("hover", inactive_style)


func _build_limit_row(res_id: StringName, current_limit: int, cap: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	# Resource icon
	var icon_container := Control.new()
	icon_container.custom_minimum_size = Vector2(ItemGrid.ICON_SIZE, ItemGrid.ICON_SIZE)
	icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_rect := TextureRect.new()
	icon_rect.texture = ResourceRegistry.get_icon_texture(res_id, ItemGrid.ICON_SIZE / 2)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon_rect)
	row.add_child(icon_container)

	# Resource name
	var name_lbl := Label.new()
	name_lbl.text = str(res_id)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_lbl)

	# − button
	var minus_btn := Button.new()
	minus_btn.text = "−"
	minus_btn.custom_minimum_size = Vector2(22, 22)
	minus_btn.focus_mode = Control.FOCUS_NONE
	_apply_secondary_btn_style(minus_btn)

	var limit_lbl := Label.new()
	limit_lbl.custom_minimum_size = Vector2(32, 0)
	limit_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	limit_lbl.add_theme_font_size_override("font_size", 13)
	limit_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	limit_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# + button
	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(22, 22)
	plus_btn.focus_mode = Control.FOCUS_NONE
	_apply_secondary_btn_style(plus_btn)

	var bid := _current_building_id
	var is_min_mode := (_storage_limit_mode == "min")
	# ∞ label: for Max mode ∞ = no cap; for Min mode ∞ = not applicable, show 0 as default instead
	limit_lbl.text = "∞" if (current_limit < 0 and not is_min_mode) else (str(current_limit) if current_limit >= 0 else "0")
	minus_btn.pressed.connect(func() -> void:
		var step: int = 10 if Input.is_key_pressed(KEY_SHIFT) else 1
		if is_min_mode:
			var cur: int = BuildingRegistry.get_storage_min_limit(bid, res_id)
			var next: int = maxi(0, (cur if cur >= 0 else 0) - step)
			BuildingRegistry.set_storage_min_limit(bid, res_id, next)
			limit_lbl.text = str(next)
		else:
			var cur: int = BuildingRegistry.get_storage_limit(bid, res_id)
			if cur < 0:
				return
			BuildingRegistry.set_storage_limit(bid, res_id, maxi(0, cur - step))
			var next: int = BuildingRegistry.get_storage_limit(bid, res_id)
			limit_lbl.text = "∞" if next < 0 else str(next)
	)
	plus_btn.pressed.connect(func() -> void:
		var step: int = 10 if Input.is_key_pressed(KEY_SHIFT) else 1
		if is_min_mode:
			var cur: int = BuildingRegistry.get_storage_min_limit(bid, res_id)
			var next: int = mini((cur if cur >= 0 else 0) + step, cap)
			BuildingRegistry.set_storage_min_limit(bid, res_id, next)
			limit_lbl.text = str(next)
		else:
			var cur: int = BuildingRegistry.get_storage_limit(bid, res_id)
			var next: int = step if cur < 0 else mini(cur + step, cap)
			BuildingRegistry.set_storage_limit(bid, res_id, next)
			limit_lbl.text = str(next)
	)

	row.add_child(minus_btn)
	row.add_child(limit_lbl)
	row.add_child(plus_btn)
	return row


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
	var is_production := BuildingRegistry.is_production_building(instance.type)
	_production_zone.visible = is_production
	_sep_production.visible = is_production
	if not is_production:
		return

	# Auto-switch GATHERING_HUT when current recipe is no longer terrain-supported.
	var available_indices: Array[int] = BuildingRegistry.get_available_recipe_indices(instance.building_id)
	if instance.type == BuildingRegistry.BuildingType.GATHERING_HUT \
			and not available_indices.is_empty() \
			and instance.active_recipe_index not in available_indices:
		BuildingRegistry.set_active_recipe(instance.building_id, available_indices[0])
		return

	var recipe: Dictionary = BuildingRegistry.get_active_recipe(instance)
	var recipe_inputs: Array = recipe.get("inputs", [])
	var base_ticks: int = recipe.get("base_cycle_ticks", 1)
	var cycles_per_day: float = float(TickSystem.TICKS_PER_DAY) / float(base_ticks)
	_production_input_col.visible = not recipe_inputs.is_empty()
	_production_vsep.visible = not recipe_inputs.is_empty()

	if not recipe_inputs.is_empty():
		var input_items: Array[Dictionary] = []
		var any_input := false
		for input_spec: Dictionary in recipe_inputs:
			var res_id: StringName = input_spec["resource_id"]
			var have: int = int(instance.input_buffer.get(res_id, 0.0))
			var qty_per_cycle: int = int(input_spec.get("charge_cost", float(input_spec.get("quantity", 0))))
			input_items.append({&"resource_id": res_id, &"quantity": have,
				&"subtitle": "%d/day" % int(qty_per_cycle * cycles_per_day)})
			if have > 0:
				any_input = true
		_input_grid.populate(input_items)
		_input_grid.modulate.a = 1.0 if any_input else 0.35

	var output_items: Array[Dictionary] = []
	for res_id: StringName in recipe.get("output", {}):
		var qty_per_cycle: int = recipe["output"][res_id]
		output_items.append({&"resource_id": res_id,
			&"quantity": instance.buffered_output.get(res_id, 0),
			&"subtitle": "~%d/day" % int(qty_per_cycle * cycles_per_day)})
	_output_grid.populate(output_items)
	_output_grid.modulate.a = 1.0 if not instance.buffered_output.is_empty() else 0.35



func _refresh_npc_zone(instance: BuildingRegistry.BuildingInstance) -> void:
	var is_residential := (instance.type == BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE)
	var is_storage := (instance.type == BuildingRegistry.BuildingType.COLLECTION_POINT
					or instance.type == BuildingRegistry.BuildingType.STORAGE_BUILDING)

	_npc_zone.visible = not is_storage
	# Separator after NPC zone only when production zone will also be visible.
	_sep_npc.visible = (not is_storage) and BuildingRegistry.is_production_building(instance.type)

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
			_recruit_btn.text = "Recruit"
		_npc_resident_grid.visible = true
		var npc_ids: Array[StringName] = npc_sys.get_house_npcs(instance.tile) if npc_sys != null else []
		var npc_data: Array[Dictionary] = []
		for nid: StringName in npc_ids:
			var res_npc: Object = npc_sys.get_npc_instance(nid)
			var res_lvl: int = res_npc.level if res_npc != null else 1
			var res_xp: int = res_npc.xp if res_npc != null else 0
			npc_data.append({&"npc_id": nid, &"state": npc_sys.get_npc_state(nid),
				&"display_name": npc_sys.get_npc_display_name(nid),
				&"level": res_lvl,
				&"xp_into_level": ExperienceFormulas.xp_into_level(res_xp, res_lvl),
				&"xp_span": ExperienceFormulas.xp_span_of_level(res_lvl),
				&"warnings": NpcGrid.build_npc_warnings(nid, res_npc)})
		_npc_resident_grid.populate(npc_data)
		return

	# Production buildings — hide residential widgets.
	_worker_counter_label.visible = false
	_npc_resident_grid.visible = false
	_recruit_btn.visible = false
	_npc_worker_col.visible = true

	var has_npc := instance.assigned_npc_id != &""
	if has_npc:
		var worker_npc: Object = NPCSystem.get_npc_instance(instance.assigned_npc_id)
		var worker_lvl: int = worker_npc.level if worker_npc != null else 1
		var worker_xp: int = worker_npc.xp if worker_npc != null else 0
		_npc_worker_grid.populate([{
			&"npc_id": instance.assigned_npc_id,
			&"state": NPCSystem.get_npc_state(instance.assigned_npc_id),
			&"display_name": NPCSystem.get_npc_display_name(instance.assigned_npc_id),
			&"level": worker_lvl,
			&"xp_into_level": ExperienceFormulas.xp_into_level(worker_xp, worker_lvl),
			&"xp_span": ExperienceFormulas.xp_span_of_level(worker_lvl),
			&"warnings": NpcGrid.build_npc_warnings(instance.assigned_npc_id, worker_npc),
		}])
		_assign_npc_btn.visible = false
		_release_npc_btn.visible = true
	else:
		_npc_worker_grid.populate([])
		_assign_npc_btn.visible = (instance.state != BuildingRegistry.BuildingInstance.State.CONSTRUCTING)
		_release_npc_btn.visible = false


func _refresh_transport_zone(instance: BuildingRegistry.BuildingInstance) -> void:
	var is_production := BuildingRegistry.is_production_building(instance.type)
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

	_populate_transport_flow(_carrier_in_flow, input_routes, "to")
	_carrier_in_btn.visible = input_routes.is_empty()

	_populate_transport_flow(_carrier_out_flow, output_routes, "from")
	_carrier_out_btn.visible = output_routes.is_empty()


func _populate_transport_flow(flow: HFlowContainer, routes: Array[LogisticsRoute], role: String) -> void:
	for child in flow.get_children():
		child.queue_free()
	for route: LogisticsRoute in routes:
		var res_id := _get_route_display_resource(route)
		flow.add_child(_build_transport_route_tile(res_id, route, role))
	var n := routes.size()
	flow.custom_minimum_size.x = n * ItemGrid.BLOCK_WIDTH + maxi(n - 1, 0) * ItemGrid.BLOCK_GAP


func _build_transport_route_tile(resource_id: StringName, route: LogisticsRoute, _role: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ItemGrid.BLOCK_WIDTH, ItemGrid.BLOCK_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

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

	if resource_id != &"":
		var icon_rect := TextureRect.new()
		icon_rect.texture      = ResourceRegistry.get_icon_texture(resource_id, ItemGrid.ICON_SIZE / 2)
		icon_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_container.add_child(icon_rect)
	else:
		var icon_lbl := Label.new()
		icon_lbl.text                 = "?"
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		icon_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_lbl.add_theme_font_size_override("font_size", 28)
		icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_container.add_child(icon_lbl)

	var rate_lbl := Label.new()
	rate_lbl.text = _get_route_stats_text(route)
	rate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rate_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate_lbl.add_theme_font_size_override("font_size", 11)
	rate_lbl.add_theme_color_override("font_color", eff_color)
	rate_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rate_lbl)

	panel.mouse_entered.connect(func() -> void: style.border_color = ItemGrid.COLOR_HOVER_BORDER)
	panel.mouse_exited.connect(func() -> void:  style.border_color = ItemGrid.COLOR_BLOCK_BORDER)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			transport_route_edit_requested.emit(route)
			get_viewport().set_input_as_handled())

	return panel


## Returns observed last-day stats as a display string.
## Shows "—" until the first complete day has elapsed (stats_data_available == false).
## Format: "3/day  47%" — items delivered and % of the day the carrier was active on this route.
func _get_route_stats_text(route: LogisticsRoute) -> String:
	if not route.stats_data_available:
		return "—"
	return "%d/day" % route.stats_items_last_day


func _get_route_display_resource(route: LogisticsRoute) -> StringName:
	if route.source_item_id != &"":
		return route.source_item_id
	var instance := BuildingRegistry.get_building_instance(str(route.source_building_id))
	if instance == null:
		return &""
	var recipe: Dictionary = BuildingRegistry.get_active_recipe(instance)
	var out_keys: Array = recipe.get("output", {}).keys()
	return out_keys[0] if not out_keys.is_empty() else &""






func _get_building_short_name(building_id: String) -> String:
	return BuildingRegistry.get_building_display_name(building_id)


func _on_recipe_changed(building_id: String, _recipe_index: int) -> void:
	if building_id == _current_building_id and visible:
		var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(building_id)
		if instance != null:
			_refresh_production_zone(instance)


func _on_storage_limit_changed(building_id: String, _resource_id: StringName, _limit: int) -> void:
	if building_id == _current_building_id and visible and _storage_config_mode:
		_refresh_storage_config()


func _on_storage_min_limit_changed(building_id: String, _resource_id: StringName, _limit: int) -> void:
	if building_id == _current_building_id and visible and _storage_config_mode:
		_refresh_storage_config()


func _on_recipes_btn_pressed() -> void:
	_recipe_view_open = not _recipe_view_open
	_content_body.visible = not _recipe_view_open
	_recipe_view.visible = _recipe_view_open
	_recipes_btn.text = "✕" if _recipe_view_open else "⚙"
	if _recipe_view_open:
		var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
		if instance != null:
			_rebuild_recipe_view(instance)


func _rebuild_recipe_view(instance: BuildingRegistry.BuildingInstance) -> void:
	for child in _recipe_view.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "Recipes"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", COLOR_LINK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recipe_view.add_child(title)

	var recipes: Array = BuildingRegistry.get_recipes(instance.type)
	var available: Array[int] = BuildingRegistry.get_available_recipe_indices(_current_building_id)
	var all_available: bool = (instance.type != BuildingRegistry.BuildingType.GATHERING_HUT)
	for i: int in range(recipes.size()):
		var recipe: Dictionary = recipes[i]
		# During a forced first-open pick, no recipe is shown active so the
		# default recipe is also clickable (the click guard skips active cards).
		var is_active: bool = (not _force_recipe_pick) and (i == instance.active_recipe_index)
		var is_available: bool = all_available or (i in available)
		_build_recipe_card(recipe, i, is_active, is_available)


func _build_recipe_card(recipe: Dictionary, recipe_index: int, is_active: bool, is_available: bool) -> void:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	if is_available and not is_active:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	var _border_idle: Color
	if is_active:
		style.bg_color = Color(0.20, 0.20, 0.20)
		_border_idle   = COLOR_PROGRESS_FG
	elif is_available:
		style.bg_color = Color(0.17, 0.17, 0.17)
		_border_idle   = Color(0.30, 0.30, 0.30)
	else:
		style.bg_color = Color(0.14, 0.14, 0.14)
		_border_idle   = Color(0.22, 0.22, 0.22)
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.border_color = _border_idle
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left   = 10
	style.content_margin_right  = 10
	style.content_margin_top    = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)
	_recipe_view.add_child(card)  # in scene tree before inner nodes

	if is_available and not is_active:
		card.mouse_entered.connect(func() -> void:
			style.border_color = COLOR_BTN_HOVER)
		card.mouse_exited.connect(func() -> void:
			style.border_color = _border_idle)
	card.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if is_available and not is_active:
				BuildingRegistry.set_active_recipe(_current_building_id, recipe_index)
				_force_recipe_pick = false
				_recipe_view_open = false
				_recipe_view.visible = false
				_content_body.visible = true
				_recipes_btn.text = "⚙"
				var inst := BuildingRegistry.get_building_instance(_current_building_id)
				if inst != null:
					_refresh_production_zone(inst))

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	card.add_child(inner)

	var name_lbl := Label.new()
	name_lbl.text = recipe.get("label", "Recipe %d" % (recipe_index + 1))
	name_lbl.add_theme_font_size_override("font_size", 14)
	var name_color: Color
	if is_active:
		name_color = COLOR_TEXT
	elif is_available:
		name_color = COLOR_TEXT_DIM
	else:
		name_color = Color(0.45, 0.45, 0.45)
	name_lbl.add_theme_color_override("font_color", name_color)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(name_lbl)

	if not is_available:
		var unavail_lbl := Label.new()
		unavail_lbl.text = "No adjacent terrain"
		unavail_lbl.add_theme_font_size_override("font_size", 11)
		unavail_lbl.add_theme_color_override("font_color", COLOR_ERR)
		unavail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unavail_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(unavail_lbl)

	_add_recipe_formula_row(recipe, inner)

	var ticks: int = recipe.get("base_cycle_ticks", 1)
	var output_parts: Array[String] = []
	for res_id: StringName in recipe.get("output", {}):
		var qty: int = recipe["output"][res_id]
		var cpd: float = float(TickSystem.TICKS_PER_DAY) / float(ticks)
		output_parts.append("%d %s / day" % [int(qty * cpd), str(res_id)])
	var info_lbl := Label.new()
	info_lbl.text = "  ·  ".join(output_parts) if not output_parts.is_empty() else "%d ticks / cycle" % ticks
	info_lbl.add_theme_font_size_override("font_size", 11)
	info_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(info_lbl)


## Appends a formula row (inputs → outputs) to `parent`, which must already be
## in the scene tree so that ItemGrid._ready() runs before populate() is called.
func _add_recipe_formula_row(recipe: Dictionary, parent: Control) -> void:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hbox)

	var inputs_arr: Array = recipe.get("inputs", [])
	if not inputs_arr.is_empty():
		var input_grid := ItemGrid.new()
		input_grid.center = true
		input_grid.hide_empty = true
		hbox.add_child(input_grid)
		var input_items: Array[Dictionary] = []
		for spec: Dictionary in inputs_arr:
			var qty: int = int(spec.get("charge_cost", float(spec.get("quantity", 1))))
			input_items.append({&"resource_id": spec["resource_id"], &"quantity": qty})
		input_grid.populate(input_items)

		var arrow := Label.new()
		arrow.text = "→"
		arrow.add_theme_font_size_override("font_size", 20)
		arrow.add_theme_color_override("font_color", COLOR_LINK)
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(arrow)

	var output_grid := ItemGrid.new()
	output_grid.center = true
	output_grid.hide_empty = true
	hbox.add_child(output_grid)
	var output_items: Array[Dictionary] = []
	for res_id: StringName in recipe.get("output", {}):
		output_items.append({&"resource_id": res_id, &"quantity": recipe["output"][res_id]})
	output_grid.populate(output_items)

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
	_open_recruit_dialog()


func _on_recruit_confirmed() -> void:
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
	if instance == null:
		_close_recruit_dialog()
		return
	var npc_sys: Node = NPCSystem
	if npc_sys != null and _recruit_food_option != null:
		var idx: int = _recruit_food_option.selected
		if idx >= 0 and idx < _recruit_food_option.item_count:
			var resource_id: StringName = _recruit_food_option.get_item_metadata(idx)
			if npc_sys.can_afford_recruit_with(resource_id):
				npc_sys.recruit_npc(instance.tile, resource_id)
	_close_recruit_dialog()
	_refresh()



func _on_npc_cancel_pressed() -> void:
	npc_assignment_cancelled.emit(_current_building_id)
	_close_npc_popup()


func _on_resident_npc_clicked(npc_id: StringName) -> void:
	var npc_sys: Node = NPCSystem
	var state: int = npc_sys.get_npc_state(npc_id) if npc_sys != null else 0
	npc_detail_requested.emit(npc_id, state)


func _on_worker_npc_clicked(npc_id: StringName) -> void:
	var state: int = NPCSystem.get_npc_state(npc_id)
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


func _open_recruit_dialog() -> void:
	if _recruit_dialog == null or _current_building_id == "":
		return
	var npc_sys: Node = NPCSystem
	if npc_sys == null:
		return

	# Populate food picker.
	_recruit_food_option.clear()
	var food_ids: Array[StringName] = ResourceRegistry.get_food_resource_ids()
	for fid: StringName in food_ids:
		var glyph: String = ResourceRegistry.get_glyph(fid)
		_recruit_food_option.add_item("%s %s" % [glyph, str(fid).capitalize()])
		_recruit_food_option.set_item_metadata(_recruit_food_option.item_count - 1, fid)
	# Default to berry if available, otherwise first entry.
	var berry_idx: int = food_ids.find(&"berry")
	_recruit_food_option.selected = maxi(0, berry_idx)

	_refresh_recruit_costs()
	_recruit_dialog.visible = true


func _refresh_recruit_costs() -> void:
	if _recruit_food_option == null or _recruit_body_lbl == null:
		return
	var npc_sys: Node = NPCSystem
	if npc_sys == null:
		return
	var idx: int = _recruit_food_option.selected
	if idx < 0 or idx >= _recruit_food_option.item_count:
		return
	var resource_id: StringName = _recruit_food_option.get_item_metadata(idx)
	var amount: int = npc_sys.get_recruit_amount_for_resource(resource_id)
	var glyph: String = ResourceRegistry.get_glyph(resource_id)
	var have: int = InventorySystem.get_global_quantity(resource_id)
	var can_afford: bool = have >= amount

	var lines: PackedStringArray = []
	lines.append("A new villager will move into this house.")
	lines.append("")
	lines.append("Cost:       %s %d" % [glyph, amount])
	lines.append("In storage: %s %d" % [glyph, have])
	if not can_afford:
		lines.append("")
		lines.append("Not enough food.")
	_recruit_body_lbl.text = "\n".join(lines)
	_recruit_body_lbl.add_theme_color_override(
			"font_color", COLOR_ERR if not can_afford else COLOR_TEXT)
	_recruit_confirm_btn.disabled = not can_afford


func _close_recruit_dialog() -> void:
	if _recruit_dialog != null:
		_recruit_dialog.visible = false


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
		var popup_npc: Object = npc_sys.get_npc_instance(npc_id)
		var popup_lvl: int = popup_npc.level if popup_npc != null else 1
		var popup_xp: int = popup_npc.xp if popup_npc != null else 0
		data.append({&"npc_id": npc_id, &"state": NPCSystem.TaskState.IDLE,
			&"display_name": npc_sys.get_npc_display_name(npc_id),
			&"level": popup_lvl,
			&"xp_into_level": ExperienceFormulas.xp_into_level(popup_xp, popup_lvl),
			&"xp_span": ExperienceFormulas.xp_span_of_level(popup_lvl),
			&"warnings": NpcGrid.build_npc_warnings(npc_id, popup_npc)})
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
			if BuildingRegistry.is_production_building(instance.type):
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
			if BuildingRegistry.is_production_building(instance.type):
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
	var recipe: Dictionary = BuildingRegistry.get_active_recipe(instance)
	var buffered_total: int = 0
	for qty: int in instance.buffered_output.values():
		buffered_total += qty
	if buffered_total >= recipe.get("output_capacity", 0):
		return "Output full"
	return "No input"


func _has_valid_input(instance: BuildingRegistry.BuildingInstance) -> bool:
	var recipe: Dictionary = BuildingRegistry.get_active_recipe(instance)
	var inputs: Array = recipe.get("inputs", [])
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
	_build_upgrade_zone(vbox)

	_content_body = VBoxContainer.new()
	_content_body.name = "ContentBody"
	_content_body.add_theme_constant_override("separation", 6)
	_content_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_content_body)

	_build_progress_zone(_content_body)
	_sep_progress = _build_separator(_content_body)
	_build_storage_zone(_content_body)
	_sep_storage = _build_separator(_content_body)
	_build_npc_zone(_content_body)
	_sep_npc = _build_separator(_content_body)
	_build_production_zone(_content_body)
	_sep_production = _build_separator(_content_body)
	_build_transport_zone(_content_body)

	_recipe_view = VBoxContainer.new()
	_recipe_view.name = "RecipeView"
	_recipe_view.add_theme_constant_override("separation", 10)
	_recipe_view.visible = false
	vbox.add_child(_recipe_view)

	_build_rename_dialog()
	_build_npc_popup()
	_build_recruit_dialog()


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

	_recipes_btn = Button.new()
	_recipes_btn.name = "RecipesBtn"
	_recipes_btn.text = "⚙"
	_recipes_btn.custom_minimum_size = Vector2(28, 28)
	_recipes_btn.focus_mode = Control.FOCUS_ALL
	_recipes_btn.tooltip_text = "Show all recipes"
	_recipes_btn.visible = false
	_recipes_btn.pressed.connect(_on_recipes_btn_pressed)
	_apply_secondary_btn_style(_recipes_btn)
	header_row.add_child(_recipes_btn)

	_storage_config_btn = Button.new()
	_storage_config_btn.name = "StorageConfigBtn"
	_storage_config_btn.text = "⚙"
	_storage_config_btn.custom_minimum_size = Vector2(28, 28)
	_storage_config_btn.focus_mode = Control.FOCUS_ALL
	_storage_config_btn.tooltip_text = "Set delivery limits"
	_storage_config_btn.visible = false
	_storage_config_btn.pressed.connect(_on_storage_config_pressed)
	_apply_secondary_btn_style(_storage_config_btn)
	header_row.add_child(_storage_config_btn)

	_upgrade_btn = Button.new()
	_upgrade_btn.name = "UpgradeBtn"
	_upgrade_btn.text = "↑"
	_upgrade_btn.custom_minimum_size = Vector2(28, 28)
	_upgrade_btn.focus_mode = Control.FOCUS_ALL
	_upgrade_btn.tooltip_text = "Building upgrades"
	_upgrade_btn.visible = false
	_upgrade_btn.pressed.connect(_on_upgrade_btn_pressed)
	_apply_secondary_btn_style(_upgrade_btn)
	header_row.add_child(_upgrade_btn)

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
	_efficiency_label.mouse_filter = Control.MOUSE_FILTER_STOP  # needed for the hover tooltip
	state_row.add_child(_efficiency_label)


func _build_upgrade_zone(parent: VBoxContainer) -> void:
	_upgrade_zone = VBoxContainer.new()
	_upgrade_zone.name = "UpgradeZone"
	_upgrade_zone.add_theme_constant_override("separation", 6)
	_upgrade_zone.visible = false
	parent.add_child(_upgrade_zone)


func _refresh_upgrade_zone(instance: BuildingRegistry.BuildingInstance) -> void:
	for child in _upgrade_zone.get_children():
		child.queue_free()
	var upgrades: Array = BuildingRegistry.get_available_upgrades(instance.building_id)
	if upgrades.is_empty():
		_upgrade_zone.visible = false
		_upgrade_zone_open = false
		return
	var title := Label.new()
	title.text = "Upgrades"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_upgrade_zone.add_child(title)
	for upg: Dictionary in upgrades:
		var uid: StringName = upg.get(&"id", &"")
		var installed := instance.has_upgrade(uid)
		var tile := _make_upgrade_tile(instance.building_id, upg, installed)
		_upgrade_zone.add_child(tile)
	_build_separator(_upgrade_zone)


func _make_upgrade_tile(building_id: String, upg: Dictionary, installed: bool) -> Control:
	var uid: StringName = upg.get(&"id", &"")
	var display_name: String = upg.get(&"display_name", str(uid))
	var cost: Dictionary = upg.get(&"cost", {})
	var tick_cost: int = upg.get(&"tick_cost", 0)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var name_lbl := Label.new()
	name_lbl.text = display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(name_lbl)

	var cost_parts: PackedStringArray = []
	for res_id: StringName in cost:
		cost_parts.append("%s %d" % [ResourceRegistry.get_glyph(res_id), cost[res_id]])
	cost_parts.append("%d ticks" % tick_cost)
	var cost_lbl := Label.new()
	cost_lbl.text = " · ".join(cost_parts)
	cost_lbl.add_theme_font_size_override("font_size", 11)
	cost_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	hbox.add_child(cost_lbl)

	# Check if this upgrade is currently being installed by the player.
	var player: PlayerCharacter = get_tree().get_first_node_in_group(&"player_character") as PlayerCharacter
	var is_building := player != null \
		and player.get_active_action_id() == PlayerCharacter.ManualActionType.INSTALL_UPGRADE \
		and player.get_active_building_id() == building_id \
		and player.get_active_upgrade_id() == uid

	var can_afford := true
	var missing_parts: PackedStringArray = []
	for res_id: StringName in cost:
		var have: int = InventorySystem.get_global_quantity(res_id)
		var need: int = cost[res_id]
		if have < need:
			can_afford = false
			missing_parts.append("%s %d/%d" % [ResourceRegistry.get_glyph(res_id), have, need])

	var btn := Button.new()
	if installed:
		btn.text = "✓ Installed"
		btn.disabled = true
	elif is_building:
		btn.text = "Building…"
		btn.disabled = true
	elif not can_afford:
		btn.text = "Install"
		btn.disabled = true
		btn.tooltip_text = "Missing: %s" % ", ".join(missing_parts)
	else:
		btn.text = "Install"
		btn.pressed.connect(func() -> void: _on_install_upgrade_pressed(building_id, uid))
	_apply_secondary_btn_style(btn)
	hbox.add_child(btn)
	return hbox


func _on_upgrade_btn_pressed() -> void:
	_upgrade_zone_open = not _upgrade_zone_open
	_upgrade_zone.visible = _upgrade_zone_open
	if _upgrade_zone_open:
		var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(_current_building_id)
		if instance != null:
			_refresh_upgrade_zone(instance)


func _on_install_upgrade_pressed(building_id: String, upgrade_id: StringName) -> void:
	var player: PlayerCharacter = get_tree().get_first_node_in_group(&"player_character") as PlayerCharacter
	if player == null:
		return
	player.try_start_upgrade(building_id, upgrade_id)


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


func _build_storage_zone(parent: VBoxContainer) -> void:
	_storage_zone = VBoxContainer.new()
	_storage_zone.name = "StorageZone"
	_storage_zone.add_theme_constant_override("separation", 6)
	_storage_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_storage_zone.visible = false
	parent.add_child(_storage_zone)

	# ── Normal view (capacity bar + item grid) ────────────────────────────────
	_storage_normal_zone = VBoxContainer.new()
	_storage_normal_zone.name = "StorageNormalZone"
	_storage_normal_zone.add_theme_constant_override("separation", 6)
	_storage_zone.add_child(_storage_normal_zone)

	var cap_row := HBoxContainer.new()
	cap_row.add_theme_constant_override("separation", 8)
	_storage_normal_zone.add_child(cap_row)

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
	_storage_normal_zone.add_child(_storage_item_grid)

	# ── Config view (per-resource limit spinners) ─────────────────────────────
	_storage_config_zone = VBoxContainer.new()
	_storage_config_zone.name = "StorageConfigZone"
	_storage_config_zone.add_theme_constant_override("separation", 4)
	_storage_config_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_storage_config_zone.visible = false
	_storage_zone.add_child(_storage_config_zone)

	var config_header := Label.new()
	config_header.text = "Delivery Limits"
	config_header.add_theme_font_size_override("font_size", 12)
	config_header.add_theme_color_override("font_color", COLOR_LINK)
	config_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_storage_config_zone.add_child(config_header)

	# Min/Max mode toggle — lives OUTSIDE the scroll container so it stays
	# pinned while the resource rows scroll.
	_storage_config_toggle = HBoxContainer.new()
	_storage_config_toggle.name = "StorageConfigToggle"
	_storage_config_toggle.add_theme_constant_override("separation", 4)
	_storage_config_zone.add_child(_storage_config_toggle)

	var config_scroll := ScrollContainer.new()
	config_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	config_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	config_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_storage_config_zone.add_child(config_scroll)

	_storage_config_rows = VBoxContainer.new()
	_storage_config_rows.name = "StorageConfigRows"
	_storage_config_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_config_rows.add_theme_constant_override("separation", 2)
	config_scroll.add_child(_storage_config_rows)
	_storage_config_rows.minimum_size_changed.connect(func() -> void:
		config_scroll.custom_minimum_size.y = minf(
			_storage_config_rows.get_combined_minimum_size().y, 220.0))


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
	cols.add_child(output_col)


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

	_npc_worker_grid = NpcGrid.new()
	_npc_worker_grid.name   = "NpcWorkerGrid"
	_npc_worker_grid.center = true
	_npc_worker_grid.npc_clicked.connect(_on_worker_npc_clicked)
	_npc_worker_col.add_child(_npc_worker_grid)

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


func _build_recruit_dialog() -> void:
	_recruit_dialog = PanelContainer.new()
	_recruit_dialog.name = "RecruitDialog"
	_recruit_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_recruit_dialog.custom_minimum_size = Vector2(280, 0)
	_recruit_dialog.visible = false
	_apply_panel_style(_recruit_dialog)
	add_child(_recruit_dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_recruit_dialog.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "Recruit Villager"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(title_lbl)

	var food_row := HBoxContainer.new()
	food_row.add_theme_constant_override("separation", 8)
	food_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(food_row)

	var pay_lbl := Label.new()
	pay_lbl.text = "Pay with:"
	pay_lbl.add_theme_font_size_override("font_size", 13)
	pay_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	food_row.add_child(pay_lbl)

	_recruit_food_option = OptionButton.new()
	_recruit_food_option.name = "RecruitFoodOption"
	_recruit_food_option.custom_minimum_size = Vector2(130, 0)
	_recruit_food_option.focus_mode = Control.FOCUS_ALL
	_recruit_food_option.item_selected.connect(func(_idx: int) -> void: _refresh_recruit_costs())
	food_row.add_child(_recruit_food_option)

	_recruit_body_lbl = Label.new()
	_recruit_body_lbl.name = "RecruitBody"
	_recruit_body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recruit_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_recruit_body_lbl.add_theme_font_size_override("font_size", 13)
	_recruit_body_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(_recruit_body_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	_recruit_confirm_btn = Button.new()
	_recruit_confirm_btn.text = "Recruit"
	_recruit_confirm_btn.custom_minimum_size = Vector2(100, 30)
	_recruit_confirm_btn.focus_mode = Control.FOCUS_ALL
	_recruit_confirm_btn.pressed.connect(_on_recruit_confirmed)
	_apply_primary_btn_style(_recruit_confirm_btn)
	btn_row.add_child(_recruit_confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(80, 30)
	cancel_btn.focus_mode = Control.FOCUS_ALL
	cancel_btn.pressed.connect(_close_recruit_dialog)
	_apply_secondary_btn_style(cancel_btn)
	btn_row.add_child(cancel_btn)

# ── Style helpers ─────────────────────────────────────────────────────────────

func _build_separator(parent: VBoxContainer) -> HSeparator:
	var sep := StyleFactory.separator(COLOR_SEP)
	parent.add_child(sep)
	return sep


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
