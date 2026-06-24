class_name TransportDrawer extends CanvasLayer
## Player-facing Transport Routes drawer. A slim tab clings to the right screen edge below the
## Tasks tab; hovering it slides a non-modal panel in from the right (peek), and clicking the tab
## pins it open.
##
## Each route is rendered as an inline RouteEditor card (From → Item → To → Carrier). Cards start
## locked (display + ✏️ Edit); clicking Edit turns that card into the interactive tile editor with
## ✓ Save / ✕ Cancel. A "New Route" button at the bottom appends a blank editor whose tiles you fill
## in place. This is the single unified UI for viewing, creating and editing routes — there is no
## separate list + dialog anymore.
##
## Open/close model: hover-peek + click-pin (non-modal), mirroring the Tasks drawer:
##   - mouse enters tab          -> slide in (peek)
##   - mouse leaves tab+panel     -> slide out after CLOSE_DELAY (unless pinned or editing)
##   - click tab                  -> toggle pin (stays open / closes immediately)
##   - ✕ or Esc                   -> cancel edit if editing, else unpin + close
##
## Pure renderer of LogisticsSystem state (see .claude/rules/ui-code.md): the actual route writes are
## delegated to the HUD via route_create_requested / route_update_requested; building selection runs
## through map-select (map_select_requested + resume_map_select). The drawer never mutates routes.

const PANEL_COLOR := Color(0.12, 0.13, 0.16, 1.0)
const TAB_COLOR := Color(0.16, 0.17, 0.21, 1.0)
const TEXT_COLOR := Color("#F0EDE6")
const MUTED_COLOR := Color(0.6, 0.62, 0.66)
const MET_COLOR := Color(0.45, 0.85, 0.45)
const ACCENT_COLOR := Color("#E8C15A")
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)

# --- Drawer geometry & timing (identical to task_dialog.gd) -------------------
const TAB_WIDTH := 44.0
const TAB_HEIGHT := 96.0
## Distance of the tab's top from the screen top. Sits below the Tasks tab (top 104, height 96)
## with a small gap so the two edge tabs stack without overlapping.
const TAB_TOP_MARGIN := 212.0
const PANEL_WIDTH := 520.0
const SLIDE_TIME := 0.2
const CLOSE_DELAY := 0.25
## Set true to skip the slide animation (motion-accessibility — see ui-code.md).
const REDUCE_MOTION := false

## Emitted when the player saves a brand-new route (HUD performs the LogisticsSystem write).
signal route_create_requested(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName)
## Emitted when the player saves edits to an existing route (HUD performs delete+create).
signal route_update_requested(route_id: StringName, changes: Dictionary)
## Emitted when an editor needs the player to pick a building on the map ("from" or "to").
signal map_select_requested(step: String)
## Emitted when the player confirms deleting an existing route (HUD performs the LogisticsSystem write).
signal route_delete_requested(route_id: StringName)

var _route_list: VBoxContainer
var _empty_label: Label

var _slider: Control          # moving group [tab | panel], anchored to the right edge
var _tab_badge: Label
var _slide := 0.0             # 0 = closed (tab peeks), 1 = open (panel visible)
var _target_open := false    # current slide target (independent of _pinned)
var _pinned := false         # stays open regardless of hover
var _slide_tween: Tween
var _close_timer := 0.0

# --- Inline-edit state -------------------------------------------------------
var _editing_route_id: StringName = &""   # id of the existing route currently being edited
var _creating_new := false                # a blank/prefilled new-route editor is showing
var _new_prefill_from: StringName = &""
var _new_prefill_to: StringName = &""
var _active_editor: RouteEditor = null     # the one unlocked editor (for the map-select round trip)


func _ready() -> void:
	layer = 22  # above the Tasks drawer (layer 21) so an open panel covers its tab cleanly
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true  # the tab is always on screen
	_build_ui()
	_apply_slide(0.0)
	_update_badge()
	_connect_signals()
	set_process(true)


# --- Open / close (pin control) ----------------------------------------------

func open() -> void:
	_pinned = true
	_set_target(true)


func close() -> void:
	_pinned = false
	_set_target(false)


func toggle() -> void:
	if _pinned:
		close()
	else:
		open()


func _is_editing() -> bool:
	return _editing_route_id != &"" or _creating_new


func _unhandled_input(event: InputEvent) -> void:
	if not _target_open:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		if _is_editing():
			_on_editor_cancel()
		else:
			close()
		get_viewport().set_input_as_handled()


# --- Hover / pin interaction -------------------------------------------------

func _on_tab_mouse_entered() -> void:
	_close_timer = 0.0
	if not _target_open:
		_set_target(true)


func _on_tab_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	# Swallow the wheel so scrolling over the tab can't fall through to the camera zoom.
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		get_viewport().set_input_as_handled()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		toggle()
		get_viewport().set_input_as_handled()


## Swallows mouse-wheel events over the panel. Wheel events bubble up through STOP controls until
## accepted; if the list isn't scrollable they would otherwise reach camera_controller's
## _unhandled_input and zoom the map. The ScrollContainer still consumes the wheel when it can scroll.
func _on_panel_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		get_viewport().set_input_as_handled()


## Closes an un-pinned drawer once the mouse has left the tab+panel area for CLOSE_DELAY. Never
## auto-closes while an inline editor is open (that would discard in-progress edits).
func _process(delta: float) -> void:
	if _pinned or not _target_open or _is_editing():
		_close_timer = 0.0
		return
	if _slider.get_global_rect().has_point(get_viewport().get_mouse_position()):
		_close_timer = 0.0
	else:
		_close_timer += delta
		if _close_timer >= CLOSE_DELAY:
			_close_timer = 0.0
			_set_target(false)


# --- Slide animation ---------------------------------------------------------

func _set_target(want_open: bool) -> void:
	_target_open = want_open
	# Don't rebuild while editing — it would destroy the in-progress editor and its unsaved tiles.
	if want_open and not _is_editing():
		_rebuild()
	_animate_slide(1.0 if want_open else 0.0)


func _animate_slide(target: float) -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	if REDUCE_MOTION:
		_apply_slide(target)
		return
	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_method(_apply_slide, _slide, target, SLIDE_TIME)


## Positions the slider so t=0 leaves only the tab peeking past the right edge and t=1 brings
## the full tab+panel on screen. Anchored to the right edge, so this survives window resizing.
func _apply_slide(t: float) -> void:
	_slide = t
	_slider.offset_left = lerp(-TAB_WIDTH, -(TAB_WIDTH + PANEL_WIDTH), t)
	_slider.offset_right = lerp(PANEL_WIDTH, 0.0, t)


# --- External entry points (from building detail panel, via HUD) -------------

## Opens the drawer and immediately edits the given existing route in place.
func open_for_route(route: LogisticsRoute) -> void:
	open()
	_enter_edit(route.id)


## Opens the drawer with a fresh editor pre-filled with `building_id` as source ("from") or
## destination ("to"), matching the building-detail "set up transport" entry points.
func open_for_building(building_id: StringName, role: String) -> void:
	open()
	_new_prefill_from = building_id if role != "to" else &""
	_new_prefill_to = building_id if role == "to" else &""
	_creating_new = true
	_editing_route_id = &""
	_rebuild()


# --- Map-select round trip (driven by HUD) -----------------------------------

## Hides the drawer while the player picks a building on the map. The active editor and its
## in-progress tiles are kept intact (no rebuild) so editing resumes seamlessly.
func hide_for_map_select() -> void:
	visible = false


## Re-shows the drawer after map-select and feeds the chosen building (or &"" on cancel) back into
## the editor that requested it.
func resume_map_select(step: String, building_id: StringName) -> void:
	visible = true
	_pinned = true
	_target_open = true
	_apply_slide(1.0)
	if _active_editor != null:
		_active_editor.resume_map_select(step, building_id)


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


## Public: refresh the badge and (if open) the route list. Call after external route changes.
func refresh() -> void:
	_refresh()


func _refresh() -> void:
	_update_badge()
	# Skip the list rebuild while editing — an external signal must not wipe an in-progress editor.
	if _target_open and not _is_editing():
		_rebuild()


# --- Inline edit lifecycle ---------------------------------------------------

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


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	_slider = Control.new()
	_slider.anchor_left = 1.0
	_slider.anchor_right = 1.0
	_slider.anchor_top = 0.0
	_slider.anchor_bottom = 1.0
	_slider.offset_top = 0.0
	_slider.offset_bottom = 0.0
	_slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slider)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	# IGNORE (not PASS): the slider strip spans the full-height right edge, so a hit-testable row
	# would block clicks to whatever is below. Only the tab and panel (both STOP) should catch
	# clicks; children are still hit-tested independently of this IGNORE.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slider.add_child(row)

	row.add_child(_build_tab())
	row.add_child(_build_panel())


## The always-visible edge tab: 🚚 glyph + an active-route-count badge. Hovering opens the drawer,
## clicking pins it. Rounded only on the left so it reads as attached to the screen edge.
## Pinned to the top of the (full-height) holder, just below the Tasks tab.
func _build_tab() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(TAB_WIDTH, 0)
	holder.size_flags_vertical = Control.SIZE_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tab := PanelContainer.new()
	tab.custom_minimum_size = Vector2(TAB_WIDTH, TAB_HEIGHT)
	tab.anchor_left = 0.0
	tab.anchor_right = 1.0
	tab.anchor_top = 0.0
	tab.anchor_bottom = 0.0
	tab.offset_left = 0.0
	tab.offset_right = 0.0
	tab.offset_top = TAB_TOP_MARGIN
	tab.offset_bottom = TAB_TOP_MARGIN + TAB_HEIGHT
	tab.tooltip_text = "Transport routes — hover to peek, click to pin"
	tab.mouse_filter = Control.MOUSE_FILTER_STOP
	tab.add_theme_stylebox_override("panel", _tab_style())
	tab.mouse_entered.connect(_on_tab_mouse_entered)
	tab.gui_input.connect(_on_tab_gui_input)
	holder.add_child(tab)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(vbox)

	var glyph := Label.new()
	glyph.text = "🚚"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 22)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(glyph)

	_tab_badge = Label.new()
	_tab_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tab_badge.add_theme_font_size_override("font_size", 13)
	_tab_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_tab_badge)

	return holder


## The slide-in panel itself (header + scrollable route list + New Route button).
func _build_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_FILL
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks over the panel (non-modal elsewhere)
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.gui_input.connect(_on_panel_gui_input)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	root.add_child(_build_header())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 60.0, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_route_list = VBoxContainer.new()
	_route_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_route_list)

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

	return panel


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
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	return header


# --- Tab badge ---------------------------------------------------------------

## Updates the edge-tab badge with the active-route count, tinted green when any route is currently
## transporting (otherwise muted).
func _update_badge() -> void:
	if _tab_badge == null:
		return
	var routes := _visible_routes()
	if routes.is_empty():
		_tab_badge.visible = false
		_tab_badge.text = ""
		return
	var any_transporting := false
	for route: LogisticsRoute in routes:
		if _carrier_status_key(route) == "transporting":
			any_transporting = true
			break
	_tab_badge.visible = true
	_tab_badge.text = str(routes.size())
	_tab_badge.add_theme_color_override("font_color", MET_COLOR if any_transporting else MUTED_COLOR)


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


# --- Styleboxes (identical to task_dialog.gd) --------------------------------

## Drawer panel: rounded on the left only (attached to the right edge) with a soft drop shadow.
func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.corner_radius_top_left = 12
	sb.corner_radius_bottom_left = 12
	sb.shadow_color = SHADOW_COLOR
	sb.shadow_size = 8
	return sb


## Edge tab: rounded on the left only, matching the panel's attached-to-edge look.
func _tab_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TAB_COLOR
	sb.corner_radius_top_left = 10
	sb.corner_radius_bottom_left = 10
	sb.shadow_color = SHADOW_COLOR
	sb.shadow_size = 6
	return sb
