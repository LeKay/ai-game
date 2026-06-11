class_name TransportationPanel extends Control
## Transportation Management UI — route creation, editing, deletion.
## UX spec: design/ux/transportation.md
## TR: TR-logistics-014  ADR: ADR-0011
##
## Two views: ActiveRoutesList (default) and RouteDetail (edit/create).
## Detail view uses a horizontal tile row: [From] → [Item] → [To] → [NPC].
## Panel is read-only: all data from LogisticsSystem, BuildingRegistry, NPCSystem, GridMap.
## Route writes go via signals which the parent wires to LogisticsSystem.

# ── Signals ───────────────────────────────────────────────────────────────────

## Fired when the player confirms route creation (RouteDetail → "Create & Close").
## item_id is &"" when the source is not a storage building.
signal route_created(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName)
## Fired when the player saves edits to an existing route.
signal route_updated(route_id: StringName, changes: Dictionary)
## Fired when the player confirms deletion of a route.
signal route_deleted(route_id: StringName)
## Fired when the player activates map-select for From ("from") or To ("to") field.
## Parent should close/hide this panel, enter map-select mode, then call resume_map_select().
signal map_select_requested(step: String)
## Fired on any close (X, Escape, click-outside, save-and-close).
signal panel_closed(changes_made: bool)
## Fired when the panel wants to toggle route active state.
signal route_toggled(route_id: StringName, pause: bool)

# ── Constants ─────────────────────────────────────────────────────────────────

const COLOR_BG           := Color(0.176, 0.176, 0.176, 0.97)  ## #2D2D2D panel bg
const COLOR_PANEL_BG     := Color(0.227, 0.227, 0.227, 1.0)   ## #3A3A3A inner bg
const COLOR_TEXT         := Color(0.941, 0.929, 0.902)         ## #F0EDE6
const COLOR_TEXT_DIM     := Color(0.816, 0.816, 0.816)         ## #D0D0D0
const COLOR_LINK         := Color(0.659, 0.643, 0.612)         ## #A8A49C
const COLOR_BTN_NORMAL   := Color(0.353, 0.353, 0.353)         ## #5A5A5A
const COLOR_BTN_HOVER    := Color(0.290, 0.494, 0.659)         ## #4A7EA8
const COLOR_BTN_TEXT     := Color(0.659, 0.643, 0.612)         ## #A8A49C
const COLOR_BTN_DESTRUCT := Color(0.706, 0.173, 0.173)         ## #B32C2C
const COLOR_SEP          := Color(0.35, 0.35, 0.35, 1.0)
const COLOR_ROW_HOVER    := Color(0.25, 0.25, 0.25, 1.0)
const COLOR_ROW_SEL      := Color(0.29, 0.49, 0.66, 0.3)

## Tile appearance — empty vs filled state.
const COLOR_TILE_EMPTY          := Color(0.20, 0.20, 0.20, 1.0)
const COLOR_TILE_FILLED         := Color(0.22, 0.35, 0.46, 1.0)
const COLOR_TILE_BORDER         := Color(0.40, 0.40, 0.40, 1.0)
const COLOR_TILE_BORDER_HOVER   := Color(0.45, 0.72, 0.95, 1.0)
const COLOR_TILE_BORDER_FILLED  := Color(0.29, 0.49, 0.66, 1.0)

## Status badge colors (dot + text, colorblind-safe via both cues).
const STATUS_COLORS: Dictionary = {
	"transporting": Color(0.298, 0.686, 0.314),  ## green
	"idle":         Color(0.843, 0.627, 0.212),  ## yellow/amber
	"paused":       Color(0.55, 0.55, 0.55),     ## gray
	"deactivated":  Color(0.55, 0.55, 0.55),     ## gray
}
const STATUS_LABELS: Dictionary = {
	"transporting": "Transporting",
	"idle":         "Idle",
	"paused":       "Paused",
	"deactivated":  "Inactive",
}

const PANEL_WIDTH    := 560
const PANEL_HEIGHT   := 440
const TILE_W         := 88   ## Width of each selector tile.
const TILE_H         := 84   ## Height of each selector tile.
const TILE_ARROW_W   := 28   ## Width reserved for "→" labels; must match caption spacers.
const ANIM_DURATION  := 0.15  ## Slide/fade in seconds — instant when reduced_motion active.
const TICKS_PER_DAY  := 1000  ## From TickSystem constant (TR-tick-005).

# ── Node references ───────────────────────────────────────────────────────────

var _panel:       DraggableWindow
var _list_view:   Control
var _detail_view: Control

## List view nodes.
var _route_list:  VBoxContainer
var _empty_label: Label
var _create_btn:  Button

## Detail view header.
var _back_btn:    Button
var _detail_title: Label
var _delete_btn:  Button

## From building tile.
var _from_tile:       PanelContainer
var _from_tile_style: StyleBoxFlat
var _from_tile_icon:  Label
var _from_tile_name:  Label

## Item slot tile.
var _item_slot_tile:  PanelContainer
var _item_slot_style: StyleBoxFlat
var _item_slot_icon:  Label
var _item_slot_qty:   Label
var _item_popup:      Control
var _item_popup_grid: ItemGrid

## To building tile.
var _to_tile:       PanelContainer
var _to_tile_style: StyleBoxFlat
var _to_tile_icon:  Label
var _to_tile_name:  Label

## NPC tile.
var _npc_tile:       PanelContainer
var _npc_tile_style: StyleBoxFlat
var _npc_tile_icon:  Label
var _npc_tile_name:  Label
var _npc_popup:      Control
var _npc_popup_list: VBoxContainer

## Route summary zone.
var _summary_zone: Control
var _dist_label:   Label
var _time_label:   Label
var _cap_label:    Label

## Action buttons.
var _confirm_btn: Button

## Delete confirmation popup.
var _delete_dialog: Control

# ── State ─────────────────────────────────────────────────────────────────────

var _editing_route:    LogisticsRoute = null  ## null = creating new route
var _selected_from_id: StringName = &""
var _selected_to_id:   StringName = &""
var _selected_npc_id:  StringName = &""
var _selected_item_id: StringName = &""
var _changes_made:     bool = false
var _tween:            Tween = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()
	visible = false
	modulate.a = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		if _item_popup != null and _item_popup.visible:
			_close_item_popup()
		elif _npc_popup != null and _npc_popup.visible:
			_close_npc_popup()
		elif _delete_dialog != null and _delete_dialog.visible:
			_delete_dialog.visible = false
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		if _item_popup != null and _item_popup.visible:
			if not _item_popup.get_global_rect().has_point(click.global_position):
				_close_item_popup()
			return
		if _npc_popup != null and _npc_popup.visible:
			if not _npc_popup.get_global_rect().has_point(click.global_position):
				_close_npc_popup()
			return
		if _delete_dialog != null and _delete_dialog.visible:
			return
		if not _panel.get_global_rect().has_point(click.global_position):
			close()
			get_viewport().set_input_as_handled()

# ── Public API ────────────────────────────────────────────────────────────────

## Opens the panel showing the Route List. Call with entry_point "hud" or "building_dispatch".
func open(entry_point: String = "hud") -> void:
	_refresh_list()
	_show_view_list()
	_animate_in()


## Opens the panel and navigates to Route Detail with `building_id` pre-filled.
## role "from": building is the source (output carrier). role "to": building is the destination.
func open_for_building(building_id: StringName, role: String = "from") -> void:
	_editing_route = null
	if role == "to":
		_selected_from_id = &""
		_selected_to_id = building_id
	else:
		_selected_from_id = building_id
		_selected_to_id = &""
	_selected_npc_id = &""
	_selected_item_id = &""
	_refresh_detail()
	_show_view_detail()
	_animate_in()


## Called after map-select completes. `building_id` is the selected building (or &"" to cancel).
## `step` is "from" or "to".
func resume_map_select(step: String, building_id: StringName) -> void:
	if step == "from":
		_selected_from_id = building_id
		_selected_npc_id = &""
		_selected_item_id = &""
	elif step == "to":
		_selected_to_id = building_id
	_refresh_detail()
	_show_view_detail()
	_animate_in()


## Hides the panel immediately (used by parent when entering map-select mode).
func hide_for_map_select() -> void:
	visible = false
	modulate.a = 0.0


## Closes the panel with animation.
func close() -> void:
	_animate_out()
	panel_closed.emit(_changes_made)
	_changes_made = false


## Refreshes the route list (call after route state changes externally).
func refresh() -> void:
	if visible and _list_view.visible:
		_refresh_list()

# ── View switching ────────────────────────────────────────────────────────────

func _show_view_list() -> void:
	_list_view.visible = true
	_detail_view.visible = false
	_refresh_list()


func _show_view_detail() -> void:
	_list_view.visible = false
	_detail_view.visible = true
	_refresh_detail()

# ── List view refresh ─────────────────────────────────────────────────────────

func _refresh_list() -> void:
	for child in _route_list.get_children():
		if child != _empty_label:
			child.queue_free()

	var routes: Array = LogisticsSystem.get_active_routes()
	var visible_routes: Array[LogisticsRoute] = []
	for route in routes:
		if route.lifecycle_state != LogisticsRoute.LifecycleState.DEACTIVATED:
			visible_routes.append(route)

	_empty_label.visible = visible_routes.is_empty()

	for route: LogisticsRoute in visible_routes:
		var row := _build_route_row(route)
		_route_list.add_child(row)


func _build_route_row(route: LogisticsRoute) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 52)
	_apply_row_style(row, false)
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	# From→To column
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	hbox.add_child(text_col)

	var from_name := _get_building_name(str(route.source_building_id))
	var to_name   := _get_building_name(str(route.destination_building_id))

	var route_lbl := Label.new()
	route_lbl.text = "%s → %s" % [from_name, to_name]
	route_lbl.add_theme_font_size_override("font_size", 13)
	route_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	route_lbl.clip_text = true
	text_col.add_child(route_lbl)

	var npc_lbl := Label.new()
	var npc_name := NPCSystem.get_npc_display_name(route.npc_id) if route.npc_id != &"" else "—"
	npc_lbl.text = "Carrier: %s" % npc_name
	npc_lbl.add_theme_font_size_override("font_size", 11)
	npc_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	text_col.add_child(npc_lbl)

	# Status badge column
	var badge_col := VBoxContainer.new()
	badge_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge_col.add_theme_constant_override("separation", 2)
	hbox.add_child(badge_col)

	var status_key := _carrier_status_key(route)
	var dot_row := HBoxContainer.new()
	dot_row.add_theme_constant_override("separation", 4)
	badge_col.add_child(dot_row)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = STATUS_COLORS.get(status_key, Color.GRAY)
	dot_row.add_child(dot)

	var badge_lbl := Label.new()
	badge_lbl.text = STATUS_LABELS.get(status_key, "Unknown")
	badge_lbl.add_theme_font_size_override("font_size", 11)
	badge_lbl.add_theme_color_override("font_color", STATUS_COLORS.get(status_key, Color.GRAY))
	dot_row.add_child(badge_lbl)

	# Delete button column
	var del_btn := Button.new()
	del_btn.text = "✕"
	del_btn.custom_minimum_size = Vector2(24, 24)
	del_btn.tooltip_text = "Delete route"
	del_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	del_btn.focus_mode = Control.FOCUS_ALL
	_apply_icon_btn_style(del_btn)
	del_btn.pressed.connect(_on_delete_row_pressed.bind(route.id))
	hbox.add_child(del_btn)

	# Row click → detail
	row.gui_input.connect(_on_row_gui_input.bind(route))

	return row


func _on_row_gui_input(event: InputEvent, route: LogisticsRoute) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_open_detail_for_route(route)


func _on_delete_row_pressed(route_id: StringName) -> void:
	_open_delete_dialog(route_id)

# ── Detail view refresh ───────────────────────────────────────────────────────

func _open_detail_for_route(route: LogisticsRoute) -> void:
	_editing_route = route
	_selected_from_id = route.source_building_id
	_selected_to_id = route.destination_building_id
	_selected_npc_id = route.npc_id
	_selected_item_id = route.source_item_id
	_show_view_detail()


func _refresh_detail() -> void:
	var is_new := _editing_route == null
	_detail_title.text = "New Route" if is_new else "Edit Route"
	_delete_btn.visible = not is_new

	# Auto-fill item when From building has exactly one possible output.
	if _selected_from_id != &"" and _selected_item_id == &"":
		if _is_storage_from():
			var items := _get_storage_items(_selected_from_id)
			if items.size() == 1:
				_selected_item_id = items[0][&"resource_id"]
		else:
			var output_ids := _get_production_output_ids(_selected_from_id)
			if output_ids.size() == 1:
				_selected_item_id = output_ids[0]

	# Update all four tiles.
	_update_building_tile(_from_tile, _from_tile_style, _from_tile_icon, _from_tile_name, _selected_from_id)
	_refresh_item_slot()
	_update_building_tile(_to_tile, _to_tile_style, _to_tile_icon, _to_tile_name, _selected_to_id)
	if _selected_npc_id != &"":
		_update_selector_tile_filled(_npc_tile_style, _npc_tile_icon, _npc_tile_name,
				"👤", NPCSystem.get_npc_display_name(_selected_npc_id))
	else:
		_update_selector_tile_empty(_npc_tile_style, _npc_tile_icon, _npc_tile_name)

	# Route summary — only when both buildings are set.
	var both_set := _selected_from_id != &"" and _selected_to_id != &""
	_summary_zone.visible = both_set
	if both_set:
		_refresh_route_summary()

	# Confirm button state.
	var from_is_storage := _is_storage_from()
	var item_ready := not from_is_storage or _selected_item_id != &""
	var all_set := _selected_from_id != &"" and _selected_to_id != &"" \
			and _selected_npc_id != &"" and item_ready
	_confirm_btn.disabled = not all_set
	_confirm_btn.text = "Create & Close" if is_new else "Save & Close"


func _update_building_tile(
		_tile: PanelContainer, style: StyleBoxFlat, icon_lbl: Label, name_lbl: Label,
		building_id: StringName) -> void:
	if building_id == &"":
		_update_selector_tile_empty(style, icon_lbl, name_lbl)
	else:
		_update_selector_tile_filled(style, icon_lbl, name_lbl,
				_building_icon(building_id), _get_building_name(str(building_id)))


func _update_selector_tile_empty(style: StyleBoxFlat, icon_lbl: Label, name_lbl: Label) -> void:
	style.bg_color = COLOR_TILE_EMPTY
	style.border_color = COLOR_TILE_BORDER
	icon_lbl.text = "+"
	icon_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	name_lbl.text = ""
	name_lbl.visible = false


func _update_selector_tile_filled(
		style: StyleBoxFlat, icon_lbl: Label, name_lbl: Label,
		icon: String, display_name: String) -> void:
	style.bg_color = COLOR_TILE_FILLED
	style.border_color = COLOR_TILE_BORDER_FILLED
	icon_lbl.text = icon
	icon_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	name_lbl.text = display_name
	name_lbl.visible = true


func _refresh_route_summary() -> void:
	var from_tile := _get_building_tile(_selected_from_id)
	var to_tile   := _get_building_tile(_selected_to_id)
	if from_tile == Vector2i(-1, -1) or to_tile == Vector2i(-1, -1):
		_dist_label.text = "Distance: —"
		_time_label.text = "Round trip: —"
		_cap_label.text  = "Max: —"
		return

	var dist: int = absi(to_tile.x - from_tile.x) + absi(to_tile.y - from_tile.y)
	const TICKS_PER_TILE: float = 3.0
	var one_way: int = int(floor(float(dist) * TICKS_PER_TILE))
	var round_trip: int = one_way * 2
	var max_per_day: int = TICKS_PER_DAY / round_trip if round_trip > 0 else 0

	_dist_label.text = "Distance: %d tiles" % dist
	_time_label.text = "Round trip: %d ticks" % round_trip
	_cap_label.text  = "Max: %d / day" % max_per_day


func _refresh_npc_picker() -> void:
	for child in _npc_popup_list.get_children():
		child.queue_free()

	var idle_npcs: Array[StringName] = NPCSystem.get_available_npcs()
	if idle_npcs.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No idle carriers available."
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		_npc_popup_list.add_child(empty_lbl)
		return

	for npc_id: StringName in idle_npcs:
		var btn := Button.new()
		btn.text = NPCSystem.get_npc_display_name(npc_id)
		btn.focus_mode = Control.FOCUS_ALL
		btn.toggle_mode = true
		btn.button_pressed = (npc_id == _selected_npc_id)
		_apply_npc_row_style(btn)
		btn.pressed.connect(_on_npc_selected.bind(npc_id))
		_npc_popup_list.add_child(btn)


func _refresh_item_slot() -> void:
	if _selected_from_id == &"":
		# From not yet selected — item tile shows inactive dash.
		_item_slot_style.bg_color = COLOR_TILE_EMPTY
		_item_slot_style.border_color = COLOR_TILE_BORDER
		_item_slot_icon.text = "—"
		_item_slot_icon.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		_item_slot_qty.visible = false
		return

	var is_multi_output := not _is_storage_from() and _is_multi_output_from()
	if _selected_item_id == &"":
		_item_slot_style.bg_color = COLOR_TILE_EMPTY
		_item_slot_style.border_color = COLOR_TILE_BORDER
		_item_slot_icon.text = "*" if is_multi_output else "+"
		_item_slot_icon.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		_item_slot_qty.visible = false
		return

	_item_slot_style.bg_color = COLOR_TILE_FILLED
	_item_slot_style.border_color = COLOR_TILE_BORDER_FILLED
	_item_slot_icon.text = _resource_icon(_selected_item_id)
	_item_slot_icon.add_theme_color_override("font_color", COLOR_TEXT)
	if is_multi_output:
		_item_slot_qty.visible = false
	else:
		var items := _get_storage_items(_selected_from_id)
		var qty := 0
		for item: Dictionary in items:
			if item[&"resource_id"] == _selected_item_id:
				qty = item[&"quantity"]
				break
		_item_slot_qty.text = "×%d" % qty if qty > 0 else "×?"
		_item_slot_qty.visible = true


func _open_item_popup() -> void:
	if _selected_from_id == &"":
		return
	var items: Array[Dictionary] = []
	if not _is_storage_from() and _is_multi_output_from():
		items.append({&"resource_id": &"*", &"quantity": -1})
		for res_id: StringName in _get_production_output_ids(_selected_from_id):
			items.append({&"resource_id": res_id, &"quantity": -1})
	else:
		items = _get_storage_items(_selected_from_id)
	if items.is_empty():
		return
	_item_popup_grid.populate(items)
	_item_popup.visible = true


func _close_item_popup() -> void:
	_item_popup.visible = false


func _on_item_popup_item_clicked(resource_id: StringName) -> void:
	_selected_item_id = &"" if resource_id == &"*" else resource_id
	_close_item_popup()
	_refresh_detail()


func _open_npc_popup() -> void:
	_refresh_npc_picker()
	_npc_popup.visible = true


func _close_npc_popup() -> void:
	_npc_popup.visible = false

# ── Button callbacks ──────────────────────────────────────────────────────────

func _on_from_pressed() -> void:
	hide_for_map_select()
	map_select_requested.emit("from")


func _on_to_pressed() -> void:
	hide_for_map_select()
	map_select_requested.emit("to")


func _on_npc_selected(npc_id: StringName) -> void:
	_selected_npc_id = npc_id
	_close_npc_popup()
	_refresh_detail()


func _on_confirm_pressed() -> void:
	if _editing_route == null:
		route_created.emit(_selected_from_id, _selected_to_id, _selected_npc_id, _selected_item_id)
	else:
		var changes: Dictionary = {}
		if _selected_from_id != _editing_route.source_building_id:
			changes["from"] = _selected_from_id
		if _selected_to_id != _editing_route.destination_building_id:
			changes["to"] = _selected_to_id
		if _selected_npc_id != _editing_route.npc_id:
			changes["npc"] = _selected_npc_id
		if _selected_item_id != _editing_route.source_item_id:
			changes["item"] = _selected_item_id
		if not changes.is_empty():
			route_updated.emit(_editing_route.id, changes)
	_changes_made = true
	close()


func _on_back_pressed() -> void:
	_editing_route = null
	_selected_from_id = &""
	_selected_to_id = &""
	_selected_npc_id = &""
	_selected_item_id = &""
	_show_view_list()


func _on_delete_row_pressed_in_detail() -> void:
	if _editing_route != null:
		_open_delete_dialog(_editing_route.id)


func _on_create_btn_pressed() -> void:
	_editing_route = null
	_selected_from_id = &""
	_selected_to_id = &""
	_selected_npc_id = &""
	_selected_item_id = &""
	_show_view_detail()

# ── Delete dialog ─────────────────────────────────────────────────────────────

func _open_delete_dialog(route_id: StringName) -> void:
	if _delete_dialog == null:
		return
	var lbl: Label = _delete_dialog.get_node_or_null("VBox/ConfirmLbl") as Label
	if lbl != null:
		lbl.text = "Delete this route?"
	var confirm_btn: Button = _delete_dialog.get_node_or_null("VBox/BtnRow/ConfirmBtn") as Button
	if confirm_btn != null:
		# Disconnect previous connections to avoid stacking.
		for d in confirm_btn.pressed.get_connections():
			confirm_btn.pressed.disconnect(d.callable)
		confirm_btn.pressed.connect(func() -> void:
			route_deleted.emit(route_id)
			_changes_made = true
			_delete_dialog.visible = false
			_show_view_list()
		)
	_delete_dialog.visible = true

# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_building_name(building_id: String) -> String:
	return BuildingRegistry.get_building_display_name(building_id)


func _get_building_tile(building_id: StringName) -> Vector2i:
	var instance := BuildingRegistry.get_building_instance(str(building_id))
	if instance == null:
		return Vector2i(-1, -1)
	return instance.tile


func _is_storage_from() -> bool:
	if _selected_from_id == &"":
		return false
	var instance := BuildingRegistry.get_building_instance(str(_selected_from_id))
	if instance == null:
		return false
	return BuildingRegistry.STORAGE_CAPACITY.has(instance.type)


## Returns true when From is a production building with more than one possible output type.
func _is_multi_output_from() -> bool:
	if _selected_from_id == &"":
		return false
	return _get_production_output_ids(_selected_from_id).size() > 1


## Returns all resource IDs this production building can output.
## GATHERING_HUT uses the dynamic gathering_output; others use the static PRODUCTION_TABLE.
func _get_production_output_ids(building_id: StringName) -> Array[StringName]:
	var instance := BuildingRegistry.get_building_instance(str(building_id))
	if instance == null:
		return []
	var result: Array[StringName] = []
	if instance.type == BuildingRegistry.BuildingType.GATHERING_HUT:
		for res_id: StringName in instance.gathering_output.keys():
			result.append(res_id)
	else:
		var table_entry: Dictionary = BuildingRegistry.PRODUCTION_TABLE.get(instance.type, {})
		for res_id: StringName in table_entry.get("output", {}).keys():
			result.append(res_id)
	return result


func _get_storage_items(building_id: StringName) -> Array[Dictionary]:
	var instance := BuildingRegistry.get_building_instance(str(building_id))
	if instance == null or instance.assigned_container_id == &"":
		return []
	var container := InventorySystem.get_container(instance.assigned_container_id)
	if container == null:
		return []
	var totals: Dictionary = {}
	for slot: InventorySlot in container.slots:
		if not slot.is_empty() and slot.quantity > 0:
			totals[slot.resource_id] = totals.get(slot.resource_id, 0) + slot.quantity
	var items: Array[Dictionary] = []
	for res_id: StringName in totals:
		items.append({&"resource_id": res_id, &"quantity": totals[res_id]})
	return items


func _get_storage_resource_ids(building_id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	for item: Dictionary in _get_storage_items(building_id):
		ids.append(item[&"resource_id"])
	return ids


func _resource_icon(resource_id: StringName) -> String:
	match resource_id:
		&"*":     return "*"
		&"wood":  return "🪵"
		&"stone": return "🪨"
		&"berry": return "🫐"
		&"fiber": return "🌿"
		&"tool":  return "🪓"
		_:        return "📦"


func _building_icon(building_id: StringName) -> String:
	var instance := BuildingRegistry.get_building_instance(str(building_id))
	if instance == null:
		return "🏠"
	match instance.type:
		BuildingRegistry.BuildingType.COLLECTION_POINT:  return "📥"
		BuildingRegistry.BuildingType.STORAGE_BUILDING:  return "📦"
		BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE: return "🏠"
		BuildingRegistry.BuildingType.LUMBER_CAMP:       return "🪵"
		BuildingRegistry.BuildingType.GATHERING_HUT:     return "🏕"
		BuildingRegistry.BuildingType.STONE_MASON:       return "🪨"
		BuildingRegistry.BuildingType.TOOL_WORKSHOP:     return "🔨"
		_: return "🏠"


func _carrier_status_key(route: LogisticsRoute) -> String:
	if not route.active:
		if route.lifecycle_state == LogisticsRoute.LifecycleState.PAUSED:
			return "paused"
		return "deactivated"
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

# ── Animations ────────────────────────────────────────────────────────────────

func _is_reduced_motion() -> bool:
	return ProjectSettings.get_setting("accessibility/reduced_motion", false)


func _animate_in() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = true
	if _is_reduced_motion():
		modulate.a = 1.0
		position.y = 0.0
		return
	modulate.a = 0.0
	position.y = 20.0
	_tween = create_tween().set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "modulate:a", 1.0, ANIM_DURATION)
	_tween.tween_property(self, "position:y", 0.0, ANIM_DURATION)


func _animate_out() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _is_reduced_motion():
		visible = false
		modulate.a = 0.0
		return
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "modulate:a", 0.0, ANIM_DURATION * 0.8)
	_tween.tween_callback(func() -> void: visible = false)

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = DraggableWindow.new()
	_panel.name = "Panel"
	_panel.title = "Transportation"
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.position.y += 80
	_panel.close_requested.connect(close)
	add_child(_panel)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 14)
	body_margin.add_theme_constant_override("margin_right", 14)
	body_margin.add_theme_constant_override("margin_top", 12)
	body_margin.add_theme_constant_override("margin_bottom", 12)
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.content.add_child(body_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 0)
	body_margin.add_child(root_vbox)

	_list_view = _build_list_view()
	root_vbox.add_child(_list_view)

	_detail_view = _build_detail_view()
	_detail_view.visible = false
	root_vbox.add_child(_detail_view)

	_build_delete_dialog()
	_build_item_popup()
	_build_npc_popup()


func _build_list_view() -> Control:
	var view := VBoxContainer.new()
	view.name = "ListView"
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.add_theme_constant_override("separation", 8)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.add_child(scroll)

	_route_list = VBoxContainer.new()
	_route_list.name = "RouteList"
	_route_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_route_list)

	_empty_label = Label.new()
	_empty_label.name = "EmptyLabel"
	_empty_label.text = "No routes configured yet."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 13)
	_empty_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_empty_label.visible = true
	_route_list.add_child(_empty_label)

	_build_separator(view)

	_create_btn = Button.new()
	_create_btn.name = "CreateBtn"
	_create_btn.text = "Create New Route"
	_create_btn.focus_mode = Control.FOCUS_ALL
	_create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_btn.pressed.connect(_on_create_btn_pressed)
	_apply_primary_btn_style(_create_btn)
	view.add_child(_create_btn)

	return view


func _build_detail_view() -> Control:
	var view := VBoxContainer.new()
	view.name = "DetailView"
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.add_theme_constant_override("separation", 10)

	# Header with back button
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	view.add_child(header_row)

	_back_btn = Button.new()
	_back_btn.name = "BackBtn"
	_back_btn.text = "← Back"
	_back_btn.focus_mode = Control.FOCUS_ALL
	_back_btn.pressed.connect(_on_back_pressed)
	_apply_link_btn_style(_back_btn)
	header_row.add_child(_back_btn)

	_detail_title = Label.new()
	_detail_title.name = "DetailTitle"
	_detail_title.text = "New Route"
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_title.add_theme_font_size_override("font_size", 15)
	_detail_title.add_theme_color_override("font_color", COLOR_TEXT)
	header_row.add_child(_detail_title)

	_delete_btn = Button.new()
	_delete_btn.name = "DeleteBtn"
	_delete_btn.text = "✕ Delete"
	_delete_btn.focus_mode = Control.FOCUS_ALL
	_delete_btn.visible = false
	_delete_btn.pressed.connect(_on_delete_row_pressed_in_detail)
	_apply_icon_btn_style(_delete_btn)
	header_row.add_child(_delete_btn)

	_build_separator(view)

	# ── Tile row: [From] → [Item] → [To] → [Carrier] ─────────────────────────
	# All four tiles always visible. TILE_ARROW_W must match spacers in cap_row.
	var tile_row := HBoxContainer.new()
	tile_row.name = "TileRow"
	tile_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tile_row.add_theme_constant_override("separation", 0)
	tile_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_child(tile_row)

	var from_bundle := _build_selector_tile_bundle()
	_from_tile = from_bundle["tile"]
	_from_tile_style = from_bundle["style"]
	_from_tile_icon = from_bundle["icon"]
	_from_tile_name = from_bundle["name"]
	_from_tile.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_from_pressed()
	)
	tile_row.add_child(_from_tile)
	tile_row.add_child(_build_tile_arrow())

	_item_slot_tile = _build_item_slot_tile()
	tile_row.add_child(_item_slot_tile)
	tile_row.add_child(_build_tile_arrow())

	var to_bundle := _build_selector_tile_bundle()
	_to_tile = to_bundle["tile"]
	_to_tile_style = to_bundle["style"]
	_to_tile_icon = to_bundle["icon"]
	_to_tile_name = to_bundle["name"]
	_to_tile.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_to_pressed()
	)
	tile_row.add_child(_to_tile)
	tile_row.add_child(_build_tile_arrow())

	var npc_bundle := _build_selector_tile_bundle()
	_npc_tile = npc_bundle["tile"]
	_npc_tile_style = npc_bundle["style"]
	_npc_tile_icon = npc_bundle["icon"]
	_npc_tile_name = npc_bundle["name"]
	_npc_tile.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_open_npc_popup()
	)
	tile_row.add_child(_npc_tile)

	# Caption row — widths match tile_row (TILE_W per tile, TILE_ARROW_W per arrow).
	var cap_row := HBoxContainer.new()
	cap_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cap_row.add_theme_constant_override("separation", 0)
	view.add_child(cap_row)

	for cap_txt: String in ["From", "Item", "To", "Carrier"]:
		var cap := _build_tile_caption(cap_txt)
		cap.custom_minimum_size = Vector2(TILE_W, 0)
		cap_row.add_child(cap)
		if cap_txt != "Carrier":
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(TILE_ARROW_W, 0)
			cap_row.add_child(sp)

	# ── Route summary (visible when both buildings are set) ────────────────────
	_summary_zone = VBoxContainer.new()
	_summary_zone.name = "SummaryZone"
	_summary_zone.visible = false
	_summary_zone.add_theme_constant_override("separation", 3)
	view.add_child(_summary_zone)

	_build_separator(_summary_zone)

	var summary_hdr := Label.new()
	summary_hdr.text = "Route Summary"
	summary_hdr.add_theme_font_size_override("font_size", 12)
	summary_hdr.add_theme_color_override("font_color", COLOR_LINK)
	_summary_zone.add_child(summary_hdr)

	_dist_label = Label.new()
	_dist_label.add_theme_font_size_override("font_size", 12)
	_dist_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_summary_zone.add_child(_dist_label)

	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 12)
	_time_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_summary_zone.add_child(_time_label)

	_cap_label = Label.new()
	_cap_label.add_theme_font_size_override("font_size", 12)
	_cap_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_summary_zone.add_child(_cap_label)

	_build_separator(view)

	_confirm_btn = Button.new()
	_confirm_btn.name = "ConfirmBtn"
	_confirm_btn.text = "Create & Close"
	_confirm_btn.focus_mode = Control.FOCUS_ALL
	_confirm_btn.disabled = true
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	_apply_primary_btn_style(_confirm_btn)
	view.add_child(_confirm_btn)

	return view


## Builds a selector tile (building or NPC slot). Returns {tile, style, icon, name} refs.
## Hover border effect is wired inside using captured local refs.
func _build_selector_tile_bundle() -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(TILE_W, TILE_H)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_TILE_EMPTY
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color = COLOR_TILE_BORDER
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	var icon_lbl := Label.new()
	icon_lbl.text = "+"
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_lbl.add_theme_font_size_override("font_size", 22)
	icon_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.text = ""
	name_lbl.visible = false
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	panel.mouse_entered.connect(func() -> void:
		style.border_color = COLOR_TILE_BORDER_HOVER
	)
	panel.mouse_exited.connect(func() -> void:
		style.border_color = COLOR_TILE_BORDER_FILLED if name_lbl.visible else COLOR_TILE_BORDER
	)

	return {"tile": panel, "style": style, "icon": icon_lbl, "name": name_lbl}


func _build_tile_arrow() -> Label:
	var lbl := Label.new()
	lbl.text = "→"
	lbl.custom_minimum_size = Vector2(TILE_ARROW_W, TILE_H)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	return lbl


func _build_tile_caption(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", COLOR_LINK)
	return lbl


func _build_item_slot_tile() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "ItemSlotTile"
	panel.custom_minimum_size = Vector2(TILE_W, TILE_H)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	_item_slot_style = StyleBoxFlat.new()
	_item_slot_style.bg_color = COLOR_TILE_EMPTY
	_item_slot_style.border_width_left   = 1
	_item_slot_style.border_width_right  = 1
	_item_slot_style.border_width_top    = 1
	_item_slot_style.border_width_bottom = 1
	_item_slot_style.border_color = COLOR_TILE_BORDER
	_item_slot_style.corner_radius_top_left     = 4
	_item_slot_style.corner_radius_top_right    = 4
	_item_slot_style.corner_radius_bottom_left  = 4
	_item_slot_style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", _item_slot_style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	var icon_container := Control.new()
	icon_container.custom_minimum_size = Vector2(36, 36)
	icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_container)

	_item_slot_icon = Label.new()
	_item_slot_icon.text = "+"
	_item_slot_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_slot_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_item_slot_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_item_slot_icon.add_theme_font_size_override("font_size", 22)
	_item_slot_icon.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_item_slot_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(_item_slot_icon)

	_item_slot_qty = Label.new()
	_item_slot_qty.text = ""
	_item_slot_qty.visible = false
	_item_slot_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_slot_qty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_slot_qty.add_theme_font_size_override("font_size", 10)
	_item_slot_qty.add_theme_color_override("font_color", ItemGrid.COLOR_QTY_TEXT)
	_item_slot_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_item_slot_qty)

	panel.mouse_entered.connect(func() -> void:
		_item_slot_style.border_color = COLOR_TILE_BORDER_HOVER)
	panel.mouse_exited.connect(func() -> void:
		_item_slot_style.border_color = \
				COLOR_TILE_BORDER_FILLED if _selected_item_id != &"" else COLOR_TILE_BORDER)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_open_item_popup()
	)

	return panel


func _build_item_popup() -> void:
	_item_popup = PanelContainer.new()
	_item_popup.name = "ItemPickerPopup"
	_item_popup.custom_minimum_size = Vector2(300, 0)
	_item_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_item_popup.visible = false
	_apply_panel_style(_item_popup)
	add_child(_item_popup)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_item_popup.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Select Item"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.pressed.connect(_close_item_popup)
	_apply_icon_btn_style(close_btn)
	header.add_child(close_btn)

	_build_separator(vbox)

	_item_popup_grid = ItemGrid.new()
	_item_popup_grid.name = "ItemPickerGrid"
	vbox.add_child(_item_popup_grid)
	_item_popup_grid.item_clicked.connect(_on_item_popup_item_clicked)


func _build_npc_popup() -> void:
	_npc_popup = PanelContainer.new()
	_npc_popup.name = "NpcPickerPopup"
	_npc_popup.custom_minimum_size = Vector2(240, 0)
	_npc_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_npc_popup.visible = false
	_apply_panel_style(_npc_popup)
	add_child(_npc_popup)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_npc_popup.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Assign Carrier"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.pressed.connect(_close_npc_popup)
	_apply_icon_btn_style(close_btn)
	header.add_child(close_btn)

	_build_separator(vbox)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_npc_popup_list = VBoxContainer.new()
	_npc_popup_list.name = "NpcList"
	_npc_popup_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_npc_popup_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_npc_popup_list)


func _build_delete_dialog() -> void:
	_delete_dialog = PanelContainer.new()
	_delete_dialog.name = "DeleteDialog"
	_delete_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_delete_dialog.custom_minimum_size = Vector2(280, 0)
	_delete_dialog.visible = false
	_apply_panel_style(_delete_dialog)
	add_child(_delete_dialog)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	_delete_dialog.add_child(vbox)

	var lbl := Label.new()
	lbl.name = "ConfirmLbl"
	lbl.text = "Delete this route?"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(lbl)

	var sub := Label.new()
	sub.text = "The carrier will complete its\ncurrent leg then return home."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	vbox.add_child(sub)

	var btn_row := HBoxContainer.new()
	btn_row.name = "BtnRow"
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var confirm := Button.new()
	confirm.name = "ConfirmBtn"
	confirm.text = "Delete"
	confirm.custom_minimum_size = Vector2(100, 30)
	confirm.focus_mode = Control.FOCUS_ALL
	_apply_destructive_btn_style(confirm)
	btn_row.add_child(confirm)

	var cancel := Button.new()
	cancel.name = "CancelBtn"
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(80, 30)
	cancel.focus_mode = Control.FOCUS_ALL
	cancel.pressed.connect(func() -> void: _delete_dialog.visible = false)
	_apply_secondary_btn_style(cancel)
	btn_row.add_child(cancel)

# ── Style helpers ─────────────────────────────────────────────────────────────

func _build_separator(parent: Control) -> void:
	var sep := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_SEP
	style.content_margin_top = 0
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


func _apply_row_style(panel: PanelContainer, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_ROW_SEL if selected else COLOR_ROW_HOVER
	style.corner_radius_top_left     = 3
	style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left  = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left   = 8
	style.content_margin_right  = 8
	style.content_margin_top    = 6
	style.content_margin_bottom = 6
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
		s.bg_color = COLOR_BTN_HOVER if state == "hover" else COLOR_BTN_NORMAL.darkened(0.2)
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


func _apply_icon_btn_style(btn: Button) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = COLOR_BTN_HOVER if state == "hover" else COLOR_BTN_NORMAL.darkened(0.2)
		s.corner_radius_top_left     = 3
		s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left  = 3
		s.corner_radius_bottom_right = 3
		s.content_margin_left   = 5
		s.content_margin_right  = 5
		s.content_margin_top    = 4
		s.content_margin_bottom = 4
		btn.add_theme_stylebox_override(state, s)
	btn.add_theme_color_override("font_color", COLOR_BTN_TEXT)
	btn.add_theme_font_size_override("font_size", 13)


func _apply_link_btn_style(btn: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxEmpty.new()
		btn.add_theme_stylebox_override(state, s)
	btn.add_theme_color_override("font_color", COLOR_LINK)
	btn.add_theme_color_override("font_hover_color", COLOR_BTN_HOVER)
	btn.add_theme_font_size_override("font_size", 13)


func _apply_npc_row_style(btn: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "toggled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = COLOR_ROW_SEL if state == "toggled" else (
			COLOR_BTN_HOVER if state == "hover" else COLOR_PANEL_BG)
		s.corner_radius_top_left     = 3
		s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left  = 3
		s.corner_radius_bottom_right = 3
		s.content_margin_left   = 8
		s.content_margin_right  = 8
		s.content_margin_top    = 5
		s.content_margin_bottom = 5
		btn.add_theme_stylebox_override(state, s)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_font_size_override("font_size", 13)
