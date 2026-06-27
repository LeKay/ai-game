class_name TransportSection extends VBoxContainer
## Displays incoming and outgoing transport routes for a building inside the Buildings Drawer.
## Each sub-section shows a header label, a flow of RouteTiles, and a plus tile for adding routes.
## Clicking a plus tile opens an embedded RouteEditorView for a new route.
## Clicking a RouteTile opens the editor in edit mode.
## Spec: design/gdd/buildings-drawer.md §5.1 B6

# ── Signals ───────────────────────────────────────────────────────────────────

## Forwarded from RouteEditorView — player confirmed a new route creation.
signal route_create_requested(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName)
## Forwarded from RouteEditorView — player saved edits to an existing route.
signal route_update_requested(route_id: StringName, changes: Dictionary)
## Forwarded from RouteEditorView — player confirmed deletion of an existing route.
signal route_delete_requested(route_id: StringName)
## Forwarded from RouteEditorView — player wants to pick a building via map-select.
signal map_select_requested(step: String)

# ── Constants ─────────────────────────────────────────────────────────────────

const COLOR_TEXT_DIM := Color(0.55, 0.55, 0.60, 1.0)
const COLOR_HEADER   := Color(0.85, 0.85, 0.85, 1.0)

# ── Node refs ─────────────────────────────────────────────────────────────────

var _incoming_header: Label
var _outgoing_header: Label
var _incoming_flow: TileFlowContainer
var _outgoing_flow: TileFlowContainer
var _incoming_pad: MarginContainer  ## header row for the incoming sub-section
var _outgoing_pad: MarginContainer  ## header row for the outgoing sub-section
var _route_list: VBoxContainer    ## the scrollable list view (hidden while editor is open)
var _editor_view: RouteEditorView ## embedded editor (hidden while list is shown)

# ── State ─────────────────────────────────────────────────────────────────────

var _building_id: String = ""

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)

	# ── Section header ────────────────────────────────────────────────────────
	var pad_h := MarginContainer.new()
	pad_h.add_theme_constant_override("margin_left",  12)
	pad_h.add_theme_constant_override("margin_right", 12)
	pad_h.add_theme_constant_override("margin_top",    6)
	pad_h.add_theme_constant_override("margin_bottom", 6)
	add_child(pad_h)

	var section_label := Label.new()
	section_label.name = "SectionHeader"
	section_label.text = "Transport"  # TODO: localize
	section_label.add_theme_font_size_override("font_size", 12)
	section_label.add_theme_color_override("font_color", COLOR_HEADER)
	pad_h.add_child(section_label)

	# ── Route list view ───────────────────────────────────────────────────────
	_route_list = VBoxContainer.new()
	_route_list.name = "RouteList"
	_route_list.add_theme_constant_override("separation", 4)
	add_child(_route_list)

	# Incoming sub-section.
	var incoming_pad := MarginContainer.new()
	_incoming_pad = incoming_pad
	incoming_pad.add_theme_constant_override("margin_left",  12)
	incoming_pad.add_theme_constant_override("margin_right", 12)
	incoming_pad.add_theme_constant_override("margin_top",    4)
	incoming_pad.add_theme_constant_override("margin_bottom", 2)
	_route_list.add_child(incoming_pad)

	_incoming_header = Label.new()
	_incoming_header.name = "IncomingHeader"
	_incoming_header.text = "Incoming (0)"  # TODO: localize
	_incoming_header.add_theme_font_size_override("font_size", 11)
	_incoming_header.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	incoming_pad.add_child(_incoming_header)

	_incoming_flow = TileFlowContainer.new()
	_incoming_flow.name = "IncomingFlow"
	_route_list.add_child(_incoming_flow)

	# Outgoing sub-section.
	var outgoing_pad := MarginContainer.new()
	_outgoing_pad = outgoing_pad
	outgoing_pad.add_theme_constant_override("margin_left",  12)
	outgoing_pad.add_theme_constant_override("margin_right", 12)
	outgoing_pad.add_theme_constant_override("margin_top",    6)
	outgoing_pad.add_theme_constant_override("margin_bottom", 2)
	_route_list.add_child(outgoing_pad)

	_outgoing_header = Label.new()
	_outgoing_header.name = "OutgoingHeader"
	_outgoing_header.text = "Outgoing (0)"  # TODO: localize
	_outgoing_header.add_theme_font_size_override("font_size", 11)
	_outgoing_header.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	outgoing_pad.add_child(_outgoing_header)

	_outgoing_flow = TileFlowContainer.new()
	_outgoing_flow.name = "OutgoingFlow"
	_route_list.add_child(_outgoing_flow)

	# ── Embedded RouteEditorView (hidden by default) ───────────────────────────
	_editor_view = RouteEditorView.new()
	_editor_view.name = "RouteEditorView"
	_editor_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_view.visible = false
	add_child(_editor_view)
	_connect_editor_signals()


# ── Public API ────────────────────────────────────────────────────────────────

## Initialises the section for [param building_id] and subscribes to LogisticsSystem signals.
func setup(building_id: String) -> void:
	_building_id = building_id
	if not LogisticsSystem.route_created.is_connected(_on_route_changed):
		LogisticsSystem.route_created.connect(_on_route_changed)
	if not LogisticsSystem.route_deleted.is_connected(_on_route_deleted):
		LogisticsSystem.route_deleted.connect(_on_route_deleted)
	refresh()


## Re-reads all routes from LogisticsSystem and rebuilds both tile flows.
func refresh() -> void:
	if _building_id == "":
		return
	var bid := StringName(_building_id)
	var all_routes: Array[LogisticsRoute] = LogisticsSystem.get_active_routes()

	var incoming: Array[LogisticsRoute] = []
	var outgoing: Array[LogisticsRoute] = []
	for route: LogisticsRoute in all_routes:
		if route.destination_building_id == bid:
			incoming.append(route)
		elif route.source_building_id == bid:
			outgoing.append(route)

	# Determine which sections are relevant based on recipe in/out.
	var has_inputs: bool = true
	var has_outputs: bool = true
	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance != null and not BuildingRegistry.STORAGE_CAPACITY.has(instance.type):
		var recipe: Dictionary = BuildingRegistry.get_active_recipe(instance)
		if not recipe.is_empty():
			has_inputs  = not recipe.get("inputs", []).is_empty()
			has_outputs = not recipe.get("output", {}).is_empty()

	_incoming_pad.visible  = has_inputs
	_incoming_flow.visible = has_inputs
	_outgoing_pad.visible  = has_outputs
	_outgoing_flow.visible = has_outputs

	_incoming_header.text = "Incoming (%d)" % incoming.size()  # TODO: localize
	_outgoing_header.text = "Outgoing (%d)" % outgoing.size()  # TODO: localize

	if has_inputs:
		_rebuild_flow(_incoming_flow, incoming, "to")
	if has_outputs:
		_rebuild_flow(_outgoing_flow, outgoing, "from")


## Forwards a map-select completion back into the embedded RouteEditorView.
## Called by BuildingDetailView after the player picks a building on the map.
func resume_map_select(step: String, building_id: StringName) -> void:
	_editor_view.resume_map_select(step, building_id)


# ── Internal ──────────────────────────────────────────────────────────────────

func _rebuild_flow(flow: TileFlowContainer, routes: Array[LogisticsRoute], role: String) -> void:
	flow.clear_tiles()

	for route: LogisticsRoute in routes:
		var tile := RouteTile.new()
		tile.edit_requested.connect(_on_route_edit_requested)
		flow.add_tile(tile)
		tile.setup(route)

	# Plus tile — always present so the player can add a route.
	var plus_tile := DrawerTile.new()
	var captured_role: String = role
	plus_tile.pressed.connect(func() -> void: _open_new_route_editor(captured_role))
	plus_tile.set_icon_glyph("+")
	plus_tile.set_label("Add")  # TODO: localize
	plus_tile.set_state(DrawerTile.TileState.NORMAL)
	flow.add_tile(plus_tile)


func _open_new_route_editor(role: String) -> void:
	_editor_view.setup(_building_id, role)
	_route_list.visible = false
	_editor_view.visible = true


func _open_edit_route_editor(route: LogisticsRoute) -> void:
	_editor_view.setup_edit(route)
	_route_list.visible = false
	_editor_view.visible = true


func _close_editor() -> void:
	_editor_view.visible = false
	_route_list.visible = true
	refresh()


## Closes the route editor without saving. No-op if the editor is not open.
func cancel_editor() -> void:
	if _editor_view.visible:
		_close_editor()


func _on_route_edit_requested(route_id: StringName) -> void:
	var route: LogisticsRoute = _find_route(route_id)
	if route != null:
		_open_edit_route_editor(route)


func _find_route(route_id: StringName) -> LogisticsRoute:
	for route: LogisticsRoute in LogisticsSystem.get_active_routes():
		if route.id == route_id:
			return route
	return null


func _connect_editor_signals() -> void:
	_editor_view.route_create_requested.connect(
		func(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName) -> void:
			route_create_requested.emit(from_id, to_id, npc_id, item_id)
			_close_editor()
	)
	_editor_view.route_update_requested.connect(
		func(route_id: StringName, changes: Dictionary) -> void:
			route_update_requested.emit(route_id, changes)
			_close_editor()
	)
	_editor_view.route_delete_requested.connect(
		func(route_id: StringName) -> void:
			route_delete_requested.emit(route_id)
			_close_editor()
	)
	_editor_view.cancelled.connect(func() -> void: _close_editor())
	_editor_view.map_select_requested.connect(
		func(step: String) -> void: map_select_requested.emit(step)
	)


# ── LogisticsSystem signal handlers ───────────────────────────────────────────

func _on_route_changed(_route: LogisticsRoute) -> void:
	if _route_list.visible:
		refresh()


func _on_route_deleted(_route_id: StringName) -> void:
	if _route_list.visible:
		refresh()
