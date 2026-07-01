class_name TransportDrawerContent extends DrawerContentBase
## Content node for the Transport Routes edge drawer.
##
## Renders the route list (header + scrollable RouteEditor cards + New Route button) inside
## the panel managed by EdgeDrawerController. This class owns only the content logic —
## no tab, no slide animation, no layer management. Those concerns belong to EdgeDrawerController.
##
## Each route is rendered as an inline RouteEditor card (From → Item → To → Carrier). Cards start
## locked (display + ✏️ Edit); clicking Edit turns that card into the interactive tile editor with
## ✓ Save / ✕ Cancel. A "New Route" button at the bottom appends a blank editor whose tiles you fill
## in place. This is the single unified UI for viewing, creating, and editing routes.
##
## Pure renderer of LogisticsSystem state (see .claude/rules/ui-code.md): the actual route writes
## are delegated to the HUD via route_create_requested / route_update_requested; building selection
## runs through map-select (map_select_requested + resume_map_select). The drawer never mutates routes.

## Emitted when the player saves a brand-new route (HUD performs the LogisticsSystem write).
signal route_create_requested(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName)
## Emitted when the player saves edits to an existing route (HUD performs delete+create).
signal route_update_requested(route_id: StringName, changes: Dictionary)
## Emitted when an editor needs the player to pick a building on the map ("from" or "to").
signal map_select_requested(step: String)
## Emitted when the player confirms deleting an existing route (HUD performs the LogisticsSystem write).
signal route_delete_requested(route_id: StringName)
## Emitted whenever the badge text / colour changes. EdgeDrawerController (or the wrapping
## TransportDrawer) should connect this to controller.set_badge().
signal badge_updated(text: String, color: Color)
## Forwarded from RouteEditor.carrier_hover_changed — drives the map route-line filter.
signal carrier_hover_changed(npc_id: StringName)

# --- Visual constants --------------------------------------------------------

const PANEL_COLOR := Color(0.12, 0.13, 0.16, 1.0)
const TAB_COLOR := Color(0.16, 0.17, 0.21, 1.0)
const TEXT_COLOR := Color("#F0EDE6")
const MUTED_COLOR := Color(0.6, 0.62, 0.66)
const MET_COLOR := Color(0.45, 0.85, 0.45)
const ACCENT_COLOR := Color("#E8C15A")
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)

# --- Content node references -------------------------------------------------

var _route_list: VBoxContainer
var _empty_label: Label
var _scroll: ScrollContainer

# --- Inline-edit state -------------------------------------------------------

var _editing_route_id: StringName = &""   ## id of the existing route currently being edited
var _creating_new := false                ## a blank/prefilled new-route editor is showing
var _new_prefill_from: StringName = &""
var _new_prefill_to: StringName = &""
var _active_editor: RouteEditor = null    ## the one unlocked editor (for the map-select round trip)


# --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	var panel := _build_panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	_connect_signals()
	_update_badge()


# --- DrawerContentBase API ---------------------------------------------------

## Called by EdgeDrawerController when the drawer slides open.
func on_drawer_opened() -> void:
	if not _is_editing():
		_rebuild()


## Called by EdgeDrawerController when the drawer slides closed.
func on_drawer_closed() -> void:
	pass  # no teardown needed


## Returns true while a RouteEditor is in edit/create mode (ESC should cancel it, not close drawer).
func wants_escape_handled() -> bool:
	return _is_editing()


## Cancels the active inline editor when ESC is pressed; returns true so the drawer stays open.
func handle_escape() -> bool:
	if _is_editing():
		_on_editor_cancel()
		return true
	return false


# --- External entry points (from building detail panel, via HUD) -------------

## Opens the drawer and immediately edits the given existing route in place.
func open_for_route(route: LogisticsRoute) -> void:
	_enter_edit(route.id)


## Opens the drawer with a fresh editor pre-filled with `building_id` as source ("from") or
## destination ("to"), matching the building-detail "set up transport" entry points.
func open_for_building(building_id: StringName, role: String) -> void:
	_new_prefill_from = building_id if role != "to" else &""
	_new_prefill_to = building_id if role == "to" else &""
	_creating_new = true
	_editing_route_id = &""
	_rebuild()


# --- Map-select round trip (driven by HUD) -----------------------------------

## Hides the CanvasLayer while the player picks a building on the map. The active editor
## and its in-progress tiles are kept intact (no rebuild) so editing resumes seamlessly.
## Note: visibility is managed on the parent CanvasLayer by TransportDrawer; this method
## is a no-op kept for API symmetry (TransportDrawer.hide_for_map_select sets visible=false).
func hide_for_map_select() -> void:
	pass  # TransportDrawer sets CanvasLayer.visible = false


## Re-shows the drawer after map-select and feeds the chosen building (or &"" on cancel) back into
## the editor that requested it.
func resume_map_select(step: String, building_id: StringName) -> void:
	if _active_editor != null:
		_active_editor.resume_map_select(step, building_id)


# --- Public refresh ----------------------------------------------------------

## Public: refresh the badge and (if the drawer is open) the route list.
## Call after external route changes.
func refresh() -> void:
	_refresh()


# --- Signals -----------------------------------------------------------------

func _connect_signals() -> void:
	if not LogisticsSystem.route_created.is_connected(_on_routes_changed):
		LogisticsSystem.route_created.connect(_on_routes_changed)
	if not LogisticsSystem.route_deleted.is_connected(_on_route_deleted):
		LogisticsSystem.route_deleted.connect(_on_route_deleted)


func _on_routes_changed(_route: LogisticsRoute) -> void:
	_refresh()


func _on_route_deleted(_route_id: StringName) -> void:
	_refresh()


func _refresh() -> void:
	_update_badge()
	# Skip the list rebuild while editing — an external signal must not wipe an in-progress editor.
	if not _is_editing():
		_rebuild()


# --- Inline edit lifecycle ---------------------------------------------------

func _is_editing() -> bool:
	return _editing_route_id != &"" or _creating_new


func _clear_edit_flags() -> void:
	_editing_route_id = &""
	_creating_new = false
	_new_prefill_from = &""
	_new_prefill_to = &""
	_active_editor = null


func _enter_edit(route_id: StringName) -> void:
	_editing_route_id = route_id
	_creating_new = false
	_new_prefill_from = &""
	_new_prefill_to = &""
	_rebuild()


func _start_new_route() -> void:
	_creating_new = true
	_editing_route_id = &""
	_new_prefill_from = &""
	_new_prefill_to = &""
	_rebuild()
	_scroll_to_bottom.call_deferred()


func _scroll_to_bottom() -> void:
	if _scroll:
		_scroll.scroll_vertical = _scroll.get_v_scroll_bar().max_value


func _on_editor_edit(route_id: StringName) -> void:
	_enter_edit(route_id)


func _on_editor_cancel() -> void:
	_clear_edit_flags()
	_rebuild()


func _on_editor_save(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName) -> void:
	_clear_edit_flags()
	route_create_requested.emit(from_id, to_id, npc_id, item_id)
	_rebuild()


func _on_editor_update(route_id: StringName, changes: Dictionary) -> void:
	_clear_edit_flags()
	route_update_requested.emit(route_id, changes)
	_rebuild()


func _on_editor_map_select(step: String, editor: RouteEditor) -> void:
	_active_editor = editor
	map_select_requested.emit(step)


func _on_editor_delete(route_id: StringName) -> void:
	# The deleted route's card is rebuilt away by the resulting LogisticsSystem.route_deleted signal.
	route_delete_requested.emit(route_id)


# --- Tab badge ---------------------------------------------------------------

## Recomputes the edge-tab badge with the active-route count, tinted green when any route is
## currently transporting (otherwise muted). Emits badge_updated for the controller.
func _update_badge() -> void:
	var routes := _visible_routes()
	if routes.is_empty():
		badge_updated.emit("", MUTED_COLOR)
		return
	var any_transporting := false
	for route: LogisticsRoute in routes:
		if _carrier_status_key(route) == "transporting":
			any_transporting = true
			break
	var color := MET_COLOR if any_transporting else MUTED_COLOR
	badge_updated.emit(str(routes.size()), color)


# --- Route list rebuild ------------------------------------------------------

func _rebuild() -> void:
	if _route_list == null:
		return
	for child: Node in _route_list.get_children():
		if child != _empty_label:
			child.queue_free()
	_active_editor = null

	var routes := _visible_routes()
	_empty_label.visible = routes.is_empty() and not _creating_new

	for route: LogisticsRoute in routes:
		var editor := RouteEditor.new()
		_route_list.add_child(editor)
		editor.init_existing(route, route.id != _editing_route_id)
		_wire_editor(editor, route)
		if route.id == _editing_route_id:
			_active_editor = editor

	if _creating_new:
		var editor := RouteEditor.new()
		_route_list.add_child(editor)
		editor.init_new(_new_prefill_from, _new_prefill_to)
		_wire_editor(editor, null)
		_active_editor = editor


## Connects an editor card's intent signals. `route` is null for the new-route editor.
func _wire_editor(editor: RouteEditor, route: LogisticsRoute) -> void:
	editor.map_select_requested.connect(_on_editor_map_select.bind(editor))
	editor.cancel_requested.connect(_on_editor_cancel)
	editor.carrier_hover_changed.connect(func(npc_id: StringName) -> void: carrier_hover_changed.emit(npc_id))
	if route != null:
		editor.edit_requested.connect(_on_editor_edit.bind(route.id))
		editor.update_requested.connect(_on_editor_update)
		editor.delete_requested.connect(_on_editor_delete.bind(route.id))
	else:
		editor.save_requested.connect(_on_editor_save)


## Active routes shown in the list (everything except fully deactivated routes).
func _visible_routes() -> Array[LogisticsRoute]:
	var out: Array[LogisticsRoute] = []
	for route: LogisticsRoute in LogisticsSystem.get_active_routes():
		if route.lifecycle_state != LogisticsRoute.LifecycleState.DEACTIVATED:
			out.append(route)
	return out


## Resolves the carrier status key for a route (mirrors transportation_panel.gd / route_editor.gd so
## the badge reads identically: queued when the shared carrier is busy on another route).
func _carrier_status_key(route: LogisticsRoute) -> String:
	if not route.active:
		if route.lifecycle_state == LogisticsRoute.LifecycleState.PAUSED:
			return "paused"
		return "deactivated"
	var active_route: LogisticsRoute = LogisticsSystem.get_active_route_for_npc(route.npc_id)
	if active_route != null and active_route.id != route.id:
		return "queued"
	match route.carrier_state:
		LogisticsRoute.CarrierState.IDLE:
			return "idle"
		LogisticsRoute.CarrierState.TRAVEL_TO_SOURCE, \
		LogisticsRoute.CarrierState.AT_SOURCE, \
		LogisticsRoute.CarrierState.TRAVEL_TO_DESTINATION, \
		LogisticsRoute.CarrierState.AT_DESTINATION, \
		LogisticsRoute.CarrierState.RETURN_HOME:
			return "transporting"
		LogisticsRoute.CarrierState.WAITING_SOURCE, \
		LogisticsRoute.CarrierState.WAITING_DESTINATION:
			return "idle"
	return "idle"


# --- UI construction ---------------------------------------------------------

## The slide-in panel content: header + scrollable route list + New Route button.
## No tab, no slider — those belong to EdgeDrawerController.
func _build_panel() -> Control:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	root.add_child(_build_header())

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 0)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	_route_list = VBoxContainer.new()
	_route_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route_list.add_theme_constant_override("separation", 12)
	_scroll.add_child(_route_list)

	_empty_label = Label.new()
	_empty_label.text = "No transport routes yet. Add one to move goods between buildings."
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.add_theme_color_override("font_color", MUTED_COLOR)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_route_list.add_child(_empty_label)

	var create_btn := Button.new()
	create_btn.text = "+ New Route"
	create_btn.custom_minimum_size = Vector2(0, 34)
	create_btn.focus_mode = Control.FOCUS_NONE
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_btn.pressed.connect(_start_new_route)
	root.add_child(create_btn)

	return margin


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "Transport"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.tooltip_text = "Close (Esc)"
	close_btn.custom_minimum_size = Vector2(36, 30)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void: request_close.emit())
	header.add_child(close_btn)

	return header


# --- Styleboxes --------------------------------------------------------------

## Builds a flat rounded stylebox for use in the panel or tab.
func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.corner_radius_top_left = 12
	sb.corner_radius_bottom_left = 12
	sb.shadow_color = SHADOW_COLOR
	sb.shadow_size = 8
	return sb
