class_name RouteEditor extends PanelContainer
## One transport route, rendered inline inside the Transport drawer as a card. It is the single
## unified UI for both viewing and editing a route: a tile row [From] → [Item] → [To] → [Carrier].
##
## Two modes:
##   - locked  : tiles are read-only, the header shows the carrier status and an ✏️ Edit button.
##   - editing : tiles are interactive (click to pick building / item / carrier) and the header shows
##               ✓ Save + ✕ Cancel buttons in place of Edit. For existing routes a 🗑 Delete button
##               is also shown; pressing it arms an inline "Delete? 🗑 ✕" confirm in the same header.
##
## A brand-new route starts in editing mode with empty tiles (init_new()).
##
## Pure renderer of LogisticsSystem / BuildingRegistry / NPCSystem / InventorySystem state
## (see .claude/rules/ui-code.md): it never mutates routes — it emits intent and the drawer/HUD wire
## the writes to LogisticsSystem. Building selection (From/To) goes through map-select, surfaced via
## the map_select_requested signal and completed by resume_map_select().

# --- Palette (matches the Tasks/Transport drawer) ----------------------------
const CARD_COLOR := Color(0.16, 0.17, 0.21, 1.0)
const TILE_EMPTY := Color(0.10, 0.11, 0.14, 1.0)
const TILE_FILLED := Color(0.14, 0.17, 0.22, 1.0)
const TILE_BORDER := Color(0.30, 0.31, 0.36, 1.0)
const TILE_BORDER_HOVER := Color(0.45, 0.72, 0.95, 1.0)
const TILE_BORDER_FILLED := Color(0.29, 0.49, 0.66, 1.0)
const TEXT_COLOR := Color("#F0EDE6")
const MUTED_COLOR := Color(0.6, 0.62, 0.66)
const ACCENT_COLOR := Color("#E8C15A")
const HINT_COLOR := Color(0.95, 0.75, 0.35)

const STATUS_COLORS: Dictionary = {
	"transporting": Color(0.298, 0.686, 0.314),
	"idle":         Color(0.843, 0.627, 0.212),
	"queued":       Color(0.45, 0.58, 0.75),
	"paused":       Color(0.55, 0.55, 0.55),
	"deactivated":  Color(0.55, 0.55, 0.55),
}
const STATUS_LABELS: Dictionary = {
	"transporting": "Transporting",
	"idle":         "Idle",
	"queued":       "Queued",
	"paused":       "Paused",
	"deactivated":  "Inactive",
}

const TILE_W := 80
const TILE_H := 78
const TILE_ARROW_W := 22
const TICKS_PER_DAY := 1000

## Emitted when the player clicks ✏️ Edit on a locked card (drawer switches this card to editing).
signal edit_requested()
## Emitted when the player saves a brand-new route.
signal save_requested(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName)
## Emitted when the player saves edits to an existing route.
signal update_requested(route_id: StringName, changes: Dictionary)
## Emitted when the player cancels editing (discard new entry / revert edits).
signal cancel_requested()
## Emitted when the player taps a building tile and map-select must begin ("from" or "to").
signal map_select_requested(step: String)
## Emitted when the player confirms deleting this (existing) route.
signal delete_requested()

var _route: LogisticsRoute = null   # null = creating a new route
var _locked := true
var _confirm_delete := false        # editing card showing the inline "Delete route?" confirm

var _from: StringName = &""
var _to: StringName = &""
var _npc: StringName = &""
var _item: StringName = &""

# Tile widget refs (rebuilt on each _build()).
var _from_style: StyleBoxFlat
var _from_icon: Control
var _from_name: Label
var _to_style: StyleBoxFlat
var _to_icon: Control
var _to_name: Label
var _item_style: StyleBoxFlat
var _item_icon: Control
var _item_qty: Label
var _npc_style: StyleBoxFlat
var _npc_icon: Control
var _npc_name: Label
var _save_btn: Button
var _hint_label: Label
var _summary_label: Label
var _hint_tween: Tween

# Popups (created lazily).
var _item_popup: PopupPanel
var _item_grid: ItemGrid
var _npc_popup: PopupPanel
var _npc_list: VBoxContainer


# --- Public API --------------------------------------------------------------

## Initialises the card for an existing route, locked (display) or unlocked (editing).
func init_existing(route: LogisticsRoute, locked: bool) -> void:
	_route = route
	_locked = locked
	_confirm_delete = false
	_from = route.source_building_id
	_to = route.destination_building_id
	_npc = route.npc_id
	_item = route.source_item_id
	_build()


## Initialises the card as a new route in editing mode, optionally pre-filling the source and/or
## destination building (used by the building-detail "set up transport" entry points).
func init_new(prefill_from: StringName = &"", prefill_to: StringName = &"") -> void:
	_route = null
	_locked = false
	_confirm_delete = false
	_from = prefill_from
	_to = prefill_to
	_npc = &""
	_item = &""
	_build()


## Completes a map-select round trip started by this editor. `building_id` is &"" on cancel.
func resume_map_select(step: String, building_id: StringName) -> void:
	if step == "from":
		if building_id != &"" and not _can_be_source(building_id):
			_from = &""
			_refresh()
			_show_hint("This building doesn't produce or store items.")
			return
		_from = building_id
		_npc = &""
		_item = &""
	elif step == "to":
		if building_id != &"" and not _can_accept_item(building_id, _item):
			_to = &""
			_refresh()
			_show_hint("This building can't receive that item.")
			return
		_to = building_id
	_refresh()


# --- Build -------------------------------------------------------------------

func _build() -> void:
	add_theme_stylebox_override("panel", _flat(CARD_COLOR, 8))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c: Node in get_children():
		c.queue_free()

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	vbox.add_child(_build_header())
	vbox.add_child(_build_tile_row())
	vbox.add_child(_build_caption_row())

	if not _locked:
		_hint_label = Label.new()
		_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint_label.add_theme_font_size_override("font_size", 11)
		_hint_label.add_theme_color_override("font_color", HINT_COLOR)
		_hint_label.modulate.a = 0.0
		vbox.add_child(_hint_label)

		_summary_label = Label.new()
		_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_summary_label.add_theme_font_size_override("font_size", 11)
		_summary_label.add_theme_color_override("font_color", MUTED_COLOR)
		vbox.add_child(_summary_label)

	_refresh()


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	if _route != null:
		var status_key := _carrier_status_key(_route)
		var status_color: Color = STATUS_COLORS.get(status_key, MUTED_COLOR)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = status_color
		header.add_child(dot)
		var status_lbl := Label.new()
		status_lbl.text = STATUS_LABELS.get(status_key, "Unknown")
		status_lbl.add_theme_font_size_override("font_size", 13)
		status_lbl.add_theme_color_override("font_color", status_color)
		header.add_child(status_lbl)
	else:
		var title := Label.new()
		title.text = "New Route"
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", TEXT_COLOR)
		header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	if _locked:
		var edit_btn := Button.new()
		edit_btn.text = "✏"
		edit_btn.tooltip_text = "Edit route"
		edit_btn.custom_minimum_size = Vector2(32, 28)
		edit_btn.focus_mode = Control.FOCUS_NONE
		edit_btn.pressed.connect(func() -> void: edit_requested.emit())
		header.add_child(edit_btn)
	elif _confirm_delete:
		var confirm_lbl := Label.new()
		confirm_lbl.text = "Delete?"
		confirm_lbl.add_theme_font_size_override("font_size", 12)
		confirm_lbl.add_theme_color_override("font_color", HINT_COLOR)
		confirm_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(confirm_lbl)

		var yes_btn := Button.new()
		yes_btn.text = "🗑"
		yes_btn.tooltip_text = "Confirm delete"
		yes_btn.custom_minimum_size = Vector2(32, 28)
		yes_btn.focus_mode = Control.FOCUS_NONE
		yes_btn.pressed.connect(func() -> void: delete_requested.emit())
		header.add_child(yes_btn)

		var no_btn := Button.new()
		no_btn.text = "✕"
		no_btn.tooltip_text = "Keep route"
		no_btn.custom_minimum_size = Vector2(32, 28)
		no_btn.focus_mode = Control.FOCUS_NONE
		no_btn.pressed.connect(_on_delete_cancel)
		header.add_child(no_btn)
	else:
		_save_btn = Button.new()
		_save_btn.text = "✓"
		_save_btn.tooltip_text = "Save route"
		_save_btn.custom_minimum_size = Vector2(32, 28)
		_save_btn.focus_mode = Control.FOCUS_NONE
		_save_btn.pressed.connect(_on_save_pressed)
		header.add_child(_save_btn)

		var cancel_btn := Button.new()
		cancel_btn.text = "✕"
		cancel_btn.tooltip_text = "Cancel"
		cancel_btn.custom_minimum_size = Vector2(32, 28)
		cancel_btn.focus_mode = Control.FOCUS_NONE
		cancel_btn.pressed.connect(func() -> void: cancel_requested.emit())
		header.add_child(cancel_btn)

		# Delete is only meaningful for existing routes (a brand-new route has nothing to delete).
		if _route != null:
			var del_btn := Button.new()
			del_btn.text = "🗑"
			del_btn.tooltip_text = "Delete route"
			del_btn.custom_minimum_size = Vector2(32, 28)
			del_btn.focus_mode = Control.FOCUS_NONE
			del_btn.pressed.connect(_on_delete_pressed)
			header.add_child(del_btn)

	return header


## First 🗑 click in edit mode: arm the inline "Delete?" confirm (avoids accidental deletes).
func _on_delete_pressed() -> void:
	_confirm_delete = true
	_build()


## ✕ on the confirm: keep the route, return to the normal editing header.
func _on_delete_cancel() -> void:
	_confirm_delete = false
	_build()


func _build_tile_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var from_bundle := _make_selector_tile(func() -> void: _on_from_tile())
	_from_style = from_bundle["style"]
	_from_icon = from_bundle["icon"]
	_from_name = from_bundle["name"]
	row.add_child(from_bundle["tile"])
	row.add_child(_make_arrow())

	row.add_child(_make_item_tile())
	row.add_child(_make_arrow())

	var to_bundle := _make_selector_tile(func() -> void: _on_to_tile())
	_to_style = to_bundle["style"]
	_to_icon = to_bundle["icon"]
	_to_name = to_bundle["name"]
	row.add_child(to_bundle["tile"])
	row.add_child(_make_arrow())

	var npc_bundle := _make_selector_tile(func() -> void: _on_npc_tile())
	_npc_style = npc_bundle["style"]
	_npc_icon = npc_bundle["icon"]
	_npc_name = npc_bundle["name"]
	row.add_child(npc_bundle["tile"])

	return row


func _build_caption_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	for cap_txt: String in ["From", "Item", "To", "Carrier"]:
		var cap := Label.new()
		cap.text = cap_txt
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.custom_minimum_size = Vector2(TILE_W, 0)
		cap.add_theme_font_size_override("font_size", 10)
		cap.add_theme_color_override("font_color", MUTED_COLOR)
		row.add_child(cap)
		if cap_txt != "Carrier":
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(TILE_ARROW_W, 0)
			row.add_child(sp)
	return row


## Builds a clickable selector tile. Returns {tile, style, icon, name}. When locked the tile ignores
## input; when editing it highlights on hover and runs `on_click` on left-click.
func _make_selector_tile(on_click: Callable) -> Dictionary:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(TILE_W, TILE_H)
	if _locked:
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style := _tile_style()
	tile.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(vbox)

	var icon := Control.new()
	icon.custom_minimum_size = Vector2(34, 34)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.visible = false
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", TEXT_COLOR)
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	if not _locked:
		tile.mouse_entered.connect(func() -> void: style.border_color = TILE_BORDER_HOVER)
		tile.mouse_exited.connect(func() -> void:
			style.border_color = TILE_BORDER_FILLED if name_lbl.visible else TILE_BORDER)
		tile.gui_input.connect(func(e: InputEvent) -> void:
			var mb := e as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				on_click.call()
		)

	return {"tile": tile, "style": style, "icon": icon, "name": name_lbl}


func _make_item_tile() -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(TILE_W, TILE_H)
	if _locked:
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	_item_style = _tile_style()
	tile.add_theme_stylebox_override("panel", _item_style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(vbox)

	_item_icon = Control.new()
	_item_icon.custom_minimum_size = Vector2(34, 34)
	_item_icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_item_icon)

	_item_qty = Label.new()
	_item_qty.visible = false
	_item_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_qty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_qty.add_theme_font_size_override("font_size", 10)
	_item_qty.add_theme_color_override("font_color", TEXT_COLOR)
	_item_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_item_qty)

	if not _locked:
		tile.mouse_entered.connect(func() -> void: _item_style.border_color = TILE_BORDER_HOVER)
		tile.mouse_exited.connect(func() -> void:
			_item_style.border_color = TILE_BORDER_FILLED if _item != &"" else TILE_BORDER)
		tile.gui_input.connect(func(e: InputEvent) -> void:
			var mb := e as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_open_item_popup()
		)

	return tile


func _make_arrow() -> Label:
	var lbl := Label.new()
	lbl.text = "→"
	lbl.custom_minimum_size = Vector2(TILE_ARROW_W, TILE_H)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", MUTED_COLOR)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# --- Refresh (tile visuals + save state) -------------------------------------

func _refresh() -> void:
	# Auto-fill the item when the From building has exactly one possible output.
	if _from != &"" and _item == &"":
		if _is_storage_from():
			var items := _get_storage_items(_from)
			if items.size() == 1:
				_item = items[0][&"resource_id"]
		else:
			var outs := _get_production_output_ids(_from)
			if outs.size() == 1:
				_item = outs[0]
	# Drop a destination that can no longer accept the (maybe just auto-filled) item.
	if _to != &"" and not _can_accept_item(_to, _item):
		_to = &""

	_update_building_tile(_from_style, _from_icon, _from_name, _from)
	_refresh_item_tile()
	_update_building_tile(_to_style, _to_icon, _to_name, _to)

	if _npc != &"":
		_set_tile_filled(_npc_style, _npc_icon, _npc_name, "🧑", NPCSystem.get_npc_display_name(_npc))
	else:
		_set_tile_empty(_npc_style, _npc_icon, _npc_name)

	if _save_btn != null:
		var item_ready := not _is_storage_from() or _item != &""
		_save_btn.disabled = not (_from != &"" and _to != &"" and _npc != &"" and item_ready)

	if _summary_label != null:
		_summary_label.text = _summary_text()


func _update_building_tile(style: StyleBoxFlat, icon: Control, name_lbl: Label, building_id: StringName) -> void:
	if building_id == &"":
		_set_tile_empty(style, icon, name_lbl)
		return
	var instance := BuildingRegistry.get_building_instance(str(building_id))
	var tex: Texture2D = BuildingRegistry.get_building_texture(instance.type if instance != null else -1)
	style.bg_color = TILE_FILLED
	style.border_color = TILE_BORDER_FILLED
	if tex != null:
		_set_icon_texture(icon, tex)
	else:
		_set_icon_text(icon, _building_icon(instance.type if instance != null else -1))
	name_lbl.text = _get_building_name(building_id)
	name_lbl.visible = true


func _refresh_item_tile() -> void:
	if _from == &"":
		_item_style.bg_color = TILE_EMPTY
		_item_style.border_color = TILE_BORDER
		_set_icon_text(_item_icon, "—")
		_item_qty.visible = false
		return
	var is_multi := not _is_storage_from() and _is_multi_output_from()
	if _item == &"":
		_item_style.bg_color = TILE_EMPTY
		_item_style.border_color = TILE_BORDER
		_set_icon_text(_item_icon, "*" if is_multi else "+")
		_item_qty.visible = false
		return
	_item_style.bg_color = TILE_FILLED
	_item_style.border_color = TILE_BORDER_FILLED
	_set_icon_texture(_item_icon, ResourceRegistry.get_icon_texture(_item, 18))
	if is_multi:
		_item_qty.visible = false
	else:
		var qty := 0
		for item: Dictionary in _get_storage_items(_from):
			if item[&"resource_id"] == _item:
				qty = item[&"quantity"]
				break
		_item_qty.text = "×%d" % qty if qty > 0 else "×?"
		_item_qty.visible = true


func _set_tile_empty(style: StyleBoxFlat, icon: Control, name_lbl: Label) -> void:
	style.bg_color = TILE_EMPTY
	style.border_color = TILE_BORDER
	_set_icon_text(icon, "+" if not _locked else "—")
	name_lbl.text = ""
	name_lbl.visible = false


func _set_tile_filled(style: StyleBoxFlat, icon: Control, name_lbl: Label, icon_text: String, display: String) -> void:
	style.bg_color = TILE_FILLED
	style.border_color = TILE_BORDER_FILLED
	_set_icon_text(icon, icon_text)
	name_lbl.text = display
	name_lbl.visible = true


func _summary_text() -> String:
	if _from == &"" or _to == &"":
		return ""
	var from_tile := _get_building_tile(_from)
	var to_tile := _get_building_tile(_to)
	if from_tile == Vector2i(-1, -1) or to_tile == Vector2i(-1, -1):
		return ""
	var dist: int = absi(to_tile.x - from_tile.x) + absi(to_tile.y - from_tile.y)
	var one_way: int = int(floor(float(dist) * LogisticsSystem.TICKS_PER_TILE))
	var round_trip: int = one_way * 2
	var per_day: int = TICKS_PER_DAY / round_trip if round_trip > 0 else 0
	return "%d tiles · ~%d / day" % [dist, per_day]


# --- Tile interactions -------------------------------------------------------

func _on_from_tile() -> void:
	map_select_requested.emit("from")


func _on_to_tile() -> void:
	if _is_storage_from() and _item == &"":
		_show_hint("Select an item first.")
		return
	map_select_requested.emit("to")


func _on_npc_tile() -> void:
	_open_npc_popup()


func _on_save_pressed() -> void:
	if _route == null:
		save_requested.emit(_from, _to, _npc, _item)
		return
	var changes: Dictionary = {}
	if _from != _route.source_building_id:
		changes["from"] = _from
	if _to != _route.destination_building_id:
		changes["to"] = _to
	if _npc != _route.npc_id:
		changes["npc"] = _npc
	if _item != _route.source_item_id:
		changes["item"] = _item
	update_requested.emit(_route.id, changes)


# --- Item popup --------------------------------------------------------------

func _open_item_popup() -> void:
	if _from == &"":
		map_select_requested.emit("from")  # nothing to pick yet — send to From first
		return
	var items: Array[Dictionary] = []
	if not _is_storage_from() and _is_multi_output_from():
		items.append({&"resource_id": &"*", &"quantity": -1})
		for res_id: StringName in _get_production_output_ids(_from):
			items.append({&"resource_id": res_id, &"quantity": -1})
	elif _is_storage_from():
		items = _get_all_storage_possible_items(_from)
	else:
		items = _get_storage_items(_from)
	if items.is_empty():
		return
	if _item_popup == null:
		_item_popup = PopupPanel.new()
		_item_grid = ItemGrid.new()
		_item_popup.add_child(_item_grid)
		_item_grid.item_clicked.connect(_on_item_picked)
		add_child(_item_popup)
	_item_grid.populate(items)
	_item_popup.popup(_popup_rect(300))


func _on_item_picked(resource_id: StringName) -> void:
	_item = &"" if resource_id == &"*" else resource_id
	if _to != &"" and not _can_accept_item(_to, _item):
		_to = &""
	if _item_popup != null:
		_item_popup.hide()
	_refresh()


# --- NPC popup ---------------------------------------------------------------

func _open_npc_popup() -> void:
	if _npc_popup == null:
		_npc_popup = PopupPanel.new()
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(220, 140)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_npc_list = VBoxContainer.new()
		_npc_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_npc_list.add_theme_constant_override("separation", 4)
		scroll.add_child(_npc_list)
		_npc_popup.add_child(scroll)
		add_child(_npc_popup)
	_refresh_npc_list()
	_npc_popup.popup(_popup_rect(240))


func _refresh_npc_list() -> void:
	for c: Node in _npc_list.get_children():
		c.queue_free()
	var candidates: Array[StringName] = NPCSystem.get_carrier_candidates()
	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "No carriers available."
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", MUTED_COLOR)
		_npc_list.add_child(lbl)
		return
	var route_count: Dictionary = {}
	for route: LogisticsRoute in LogisticsSystem.get_active_routes():
		if route.npc_id != &"":
			route_count[route.npc_id] = int(route_count.get(route.npc_id, 0)) + 1
	for npc_id: StringName in candidates:
		var btn := Button.new()
		var n: int = int(route_count.get(npc_id, 0))
		var npc: Object = NPCSystem.get_npc_instance(npc_id)
		var lvl: int = npc.level if npc != null else 1
		var label := "Lv %d  %s" % [lvl, NPCSystem.get_npc_display_name(npc_id)]
		if n > 0:
			label += "  (%d route%s)" % [n, "" if n == 1 else "s"]
		btn.text = label
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_npc_picked.bind(npc_id))
		_npc_list.add_child(btn)


func _on_npc_picked(npc_id: StringName) -> void:
	_npc = npc_id
	if _npc_popup != null:
		_npc_popup.hide()
	_refresh()


## Screen rect just below this card for a picker popup of the given width.
func _popup_rect(width: int) -> Rect2i:
	var origin := Vector2i(get_global_rect().position) + Vector2i(20, 40)
	return Rect2i(origin, Vector2i(width, 0))


# --- Validation hint ---------------------------------------------------------

func _show_hint(msg: String) -> void:
	if _hint_label == null:
		return
	_hint_label.text = msg
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_label.modulate.a = 1.0
	_hint_tween = create_tween()
	_hint_tween.tween_interval(1.8)
	_hint_tween.tween_property(_hint_label, "modulate:a", 0.0, 0.4)


# --- Query helpers (ported from transportation_panel.gd) ---------------------

func _is_building_operable(instance: BuildingRegistry.BuildingInstance) -> bool:
	return instance.state != BuildingRegistry.BuildingInstance.State.CONSTRUCTING \
		and instance.state != BuildingRegistry.BuildingInstance.State.DEMOLISHED


func _can_be_source(building_id: StringName) -> bool:
	if building_id == &"":
		return false
	var instance := BuildingRegistry.get_building_instance(str(building_id))
	if instance == null or not _is_building_operable(instance):
		return false
	return BuildingRegistry.STORAGE_CAPACITY.has(instance.type) \
		or BuildingRegistry.is_production_building(instance.type)


func _can_accept_item(building_id: StringName, item_id: StringName) -> bool:
	if building_id == &"":
		return false
	var instance := BuildingRegistry.get_building_instance(str(building_id))
	if instance == null or not _is_building_operable(instance):
		return false
	if BuildingRegistry.STORAGE_CAPACITY.has(instance.type):
		return true
	if item_id == &"":
		return false
	var accepted: Array[StringName] = BuildingRegistry.get_active_input_resource_ids(str(building_id))
	return item_id in accepted


func _is_storage_from() -> bool:
	if _from == &"":
		return false
	var instance := BuildingRegistry.get_building_instance(str(_from))
	if instance == null:
		return false
	return BuildingRegistry.STORAGE_CAPACITY.has(instance.type)


func _is_multi_output_from() -> bool:
	if _from == &"":
		return false
	return _get_production_output_ids(_from).size() > 1


func _get_production_output_ids(building_id: StringName) -> Array[StringName]:
	var instance := BuildingRegistry.get_building_instance(str(building_id))
	if instance == null:
		return []
	var recipe: Dictionary = BuildingRegistry.get_active_recipe(instance)
	var result: Array[StringName] = []
	for res_id: StringName in recipe.get("output", {}).keys():
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


func _get_all_storage_possible_items(building_id: StringName) -> Array[Dictionary]:
	var stored: Dictionary = {}
	var instance := BuildingRegistry.get_building_instance(str(building_id))
	if instance != null and instance.assigned_container_id != &"":
		var container := InventorySystem.get_container(instance.assigned_container_id)
		if container != null:
			for slot: InventorySlot in container.slots:
				if not slot.is_empty() and slot.quantity > 0:
					stored[slot.resource_id] = stored.get(slot.resource_id, 0) + slot.quantity
	var items: Array[Dictionary] = []
	for res_id: StringName in ResourceRegistry.get_all_ids():
		items.append({&"resource_id": res_id, &"quantity": int(stored.get(res_id, 0))})
	return items


func _get_building_name(building_id: StringName) -> String:
	return BuildingRegistry.get_building_display_name(str(building_id))


func _get_building_tile(building_id: StringName) -> Vector2i:
	var instance := BuildingRegistry.get_building_instance(str(building_id))
	if instance == null:
		return Vector2i(-1, -1)
	return instance.tile


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


func _building_icon(building_type: int) -> String:
	match building_type:
		BuildingRegistry.BuildingType.GATHERING_HUT:    return "🏕️"
		BuildingRegistry.BuildingType.COLLECTION_POINT: return "📦"
		BuildingRegistry.BuildingType.STORAGE_BUILDING: return "🏚️"
		BuildingRegistry.BuildingType.LUMBER_CAMP:      return "🌲"
		BuildingRegistry.BuildingType.STONE_MASON:      return "🪨"
		BuildingRegistry.BuildingType.SAWMILL:          return "🪚"
		BuildingRegistry.BuildingType.TOOL_WORKSHOP:    return "🔨"
		BuildingRegistry.BuildingType.WEAVER:           return "🧵"
		BuildingRegistry.BuildingType.TAILOR:           return "🪡"
		BuildingRegistry.BuildingType.HUNTING_LODGE:    return "🦌"
		BuildingRegistry.BuildingType.FARM:             return "🌾"
		BuildingRegistry.BuildingType.MILL:             return "⚙️"
		BuildingRegistry.BuildingType.BAKERY:           return "🥖"
		BuildingRegistry.BuildingType.CLAY_PIT:         return "🧱"
		BuildingRegistry.BuildingType.POTTERY_KILN:     return "🏺"
		BuildingRegistry.BuildingType.TANNERY:           return "🪣"
		BuildingRegistry.BuildingType.BOWYERS_WORKSHOP:  return "🏹"
		BuildingRegistry.BuildingType.CARPENTER:         return "🪑"
		BuildingRegistry.BuildingType.FISHING_HUT:       return "🎣"
		BuildingRegistry.BuildingType.BRICK_KILN:        return "🔥"
		BuildingRegistry.BuildingType.CHARCOAL_KILN:     return "⬛"
		BuildingRegistry.BuildingType.SALT_WORKS:        return "🧂"
		BuildingRegistry.BuildingType.PRESERVATION_HOUSE: return "🥫"
		BuildingRegistry.BuildingType.COOPERAGE:          return "🛢️"
		BuildingRegistry.BuildingType.WHEEL_MAKER:        return "🛞"
		BuildingRegistry.BuildingType.CART_WORKSHOP:      return "🛒"
		_:                                               return "🏠"


func _set_icon_text(slot: Control, text: String) -> void:
	for c in slot.get_children():
		c.queue_free()
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)


func _set_icon_texture(slot: Control, texture: Texture2D) -> void:
	for c in slot.get_children():
		c.queue_free()
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(rect)


# --- Styleboxes --------------------------------------------------------------

func _tile_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TILE_EMPTY
	sb.set_border_width_all(1)
	sb.border_color = TILE_BORDER
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb


func _flat(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	return sb
