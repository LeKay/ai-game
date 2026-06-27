class_name BuildingsDrawerContent extends DrawerContentBase
## Content node for the Buildings Drawer.
## Manages a view-stack containing:
##   - BuildingListView   (initial, always shown after drawer closes)
##   - BuildPickerView    (pick building type to place — Task B2)
##   - BuildingDetailView (per-building detail — Task B3+)
##
## Implements the DrawerContentBase lifecycle callbacks and exposes public API
## used by BuildingsDrawer (the CanvasLayer wrapper).
##
## See: design/gdd/buildings-drawer.md

## Emitted when the badge text / colour should update on the tab.
## badge_text: number of active (non-constructing) Production+Storage buildings as a string.
signal badge_updated(badge_text: String, badge_color: Color)

## Stub signals — wired up in later tasks (B2+).
signal build_mode_requested(building_type: int)
signal building_rename_requested(building_id: String, new_name: String)
signal building_demolish_requested(building_id: String)
signal demolish_mode_requested()
signal npc_assign_requested(building_id: String)
signal recipe_change_requested(building_id: String, recipe_index: int)

## Forwarded from BuildingDetailView (B3+).
signal rename_building(building_id: String, new_name: String)
signal npc_assigned(building_id: String, npc_id: StringName)
signal npc_recruit_requested(building_id: String, resource_id: StringName)
signal npc_released(building_id: String, npc_id: StringName)
signal npc_detail_requested(npc_id: StringName)
signal construction_work_requested(building_id: String)
## Forwarded from BuildingDetailView — production recipe confirmed.
signal recipe_changed(building_id: String, recipe_id: StringName)
## Forwarded from BuildingDetailView — transport route actions.
signal route_create_requested(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName)
signal route_update_requested(route_id: StringName, changes: Dictionary)
signal route_delete_requested(route_id: StringName)
## Forwarded from BuildingDetailView — map-select pick for route editor.
signal map_select_requested(step: String)
## Forwarded from BuildingDetailView — upgrade install confirmed.
signal upgrade_install_requested(building_id: String, upgrade_id: StringName)
## Forwarded from BuildingDetailView — player saved a production speed change.
signal production_speed_changed(building_id: String, target_efficiency: float)

const BADGE_COLOR := Color(0.298, 0.686, 0.314)   ## green — matches operating state

var _list_view:    BuildingListView
var _detail_view:  BuildingDetailView
var _picker_view:  BuildPickerView
var _current_view: Control
## Set to true before closing for map-select so the view stack is preserved on reopen.
var _skip_close_reset: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_list_view = BuildingListView.new()
	_list_view.name = "BuildingListView"
	_list_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_list_view)
	_list_view.plus_tile_pressed.connect(_on_plus_pressed)
	_list_view.building_tile_pressed.connect(_on_building_pressed)
	_list_view.close_pressed.connect(func() -> void: request_close.emit())

	_detail_view = BuildingDetailView.new()
	_detail_view.name = "BuildingDetailView"
	_detail_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_view.visible = false
	add_child(_detail_view)
	_detail_view.back_pressed.connect(func() -> void: _show_view(_list_view))
	_detail_view.close_pressed.connect(func() -> void: request_close.emit())
	_detail_view.rename_building.connect(func(bid: String, n: String) -> void: rename_building.emit(bid, n))
	_detail_view.npc_assigned.connect(func(bid: String, nid: StringName) -> void: npc_assigned.emit(bid, nid))
	_detail_view.npc_recruit_requested.connect(func(bid: String, rid: StringName) -> void: npc_recruit_requested.emit(bid, rid))
	_detail_view.npc_released.connect(func(bid: String, nid: StringName) -> void: npc_released.emit(bid, nid))
	_detail_view.npc_detail_requested.connect(func(nid: StringName) -> void: npc_detail_requested.emit(nid))
	_detail_view.construction_work_requested.connect(func(bid: String) -> void: construction_work_requested.emit(bid))
	_detail_view.recipe_changed.connect(func(bid: String, rid: StringName) -> void: recipe_changed.emit(bid, rid))
	_detail_view.route_create_requested.connect(
		func(f: StringName, t: StringName, n: StringName, i: StringName) -> void:
			route_create_requested.emit(f, t, n, i))
	_detail_view.route_update_requested.connect(
		func(rid: StringName, changes: Dictionary) -> void:
			route_update_requested.emit(rid, changes))
	_detail_view.route_delete_requested.connect(
		func(rid: StringName) -> void:
			route_delete_requested.emit(rid))
	_detail_view.map_select_requested.connect(
		func(step: String) -> void:
			map_select_requested.emit(step))
	_detail_view.upgrade_install_requested.connect(
		func(bid: String, uid: StringName) -> void:
			upgrade_install_requested.emit(bid, uid))
	_detail_view.production_speed_changed.connect(
		func(bid: String, eff: float) -> void:
			production_speed_changed.emit(bid, eff))

	_picker_view = BuildPickerView.new()
	_picker_view.name = "BuildPickerView"
	_picker_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker_view.visible = false
	add_child(_picker_view)
	_picker_view.back_pressed.connect(func() -> void: _show_view(_list_view))
	_picker_view.close_pressed.connect(func() -> void: request_close.emit())
	_picker_view.building_type_selected.connect(_on_building_type_selected)
	_picker_view.demolish_mode_requested.connect(func() -> void: demolish_mode_requested.emit())

	_show_view(_list_view)


# --- DrawerContentBase API ---------------------------------------------------

## Called by EdgeDrawerController each time the panel slides open.
func on_drawer_opened() -> void:
	_list_view.refresh()
	_emit_badge()


## Called by EdgeDrawerController each time the panel slides closed.
## Resets to the list view so the drawer reopens in a clean state.
## Skipped once if [member _skip_close_reset] is set (e.g. during map-select).
func on_drawer_closed() -> void:
	if _skip_close_reset:
		_skip_close_reset = false
		return
	_detail_view.cancel_all_editors()
	if _current_view != _list_view:
		_show_view(_list_view)


## Returns true when the detail view is active and rename mode is open —
## signals to the drawer that ESC should be consumed locally.
func wants_escape_handled() -> bool:
	return _current_view == _detail_view and _detail_view.is_rename_active()


## Cancels an active rename, or falls through to default drawer handling.
func handle_escape() -> bool:
	if _current_view == _detail_view and _detail_view.is_rename_active():
		_detail_view.cancel_rename()
		return true
	return false


# --- Public API ---------------------------------------------------------------

## Opens (or switches to) the detail view for the given building.
func open_for_building(building_id: String) -> void:
	_detail_view.setup(building_id)
	_show_view(_detail_view)


## Opens the build picker directly (e.g. via keyboard shortcut).
func open_build_picker() -> void:
	_on_plus_pressed()


## Forwards a completed map-select result into the embedded TransportSection.
## Called by HUD after the player picks a building on the map.
func resume_map_select(step: String, building_id: StringName) -> void:
	_detail_view.resume_map_select(step, building_id)


## Refreshes the detail view if it is currently visible (e.g. after an upgrade install).
func refresh_detail() -> void:
	if _current_view == _detail_view:
		_detail_view.refresh()


# --- View management ---------------------------------------------------------

func _show_view(view: Control) -> void:
	if _current_view == view:
		return
	if _current_view == _detail_view:
		_detail_view.cancel_all_editors()
	if _current_view != null:
		_current_view.visible = false
	_current_view = view
	if _current_view != null:
		_current_view.visible = true


# --- Badge -------------------------------------------------------------------

func _emit_badge() -> void:
	var count := _count_active_buildings()
	var text  := str(count) if count > 0 else ""
	badge_updated.emit(text, BADGE_COLOR)


func _count_active_buildings() -> int:
	var count := 0
	for instance: BuildingRegistry.BuildingInstance in BuildingRegistry.get_all_buildings():
		if BuildingListView.EXCLUDED_TYPES.has(instance.type):
			continue
		if instance.state != BuildingRegistry.BuildingInstance.State.CONSTRUCTING \
				and instance.state != BuildingRegistry.BuildingInstance.State.DEMOLISHED:
			count += 1
	return count


# --- Signal handlers ---------------------------------------------------------

func _on_plus_pressed() -> void:
	_picker_view.refresh()
	_show_view(_picker_view)


func _on_building_type_selected(building_type: int) -> void:
	_show_view(_list_view)
	build_mode_requested.emit(building_type)


func _on_building_pressed(building_id: String) -> void:
	_detail_view.setup(building_id)
	_show_view(_detail_view)


