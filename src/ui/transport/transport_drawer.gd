class_name TransportDrawer extends CanvasLayer
## Backward-compatible wrapper that hosts the Transport Routes edge drawer.
##
## hud.gd continues to call open() / close() / toggle() / is_open() /
## open_for_route() / open_for_building() / hide_for_map_select() /
## resume_map_select() / refresh() without changes. Internally, this class
## instantiates a TransportDrawerContent and an EdgeDrawerController and
## wires them together.
##
## Open/close model (click-to-pin, no hover-opens-panel):
##   - Idle:              Tab sits at the right edge with a hover-nudge.
##   - Click tab:         Panel slides in (pinned).
##   - Click outside:     Panel slides out (event not consumed — passes to map).
##   - ✕ button / ESC:   Panel slides out (or cancels inline edit first).

var _content: TransportDrawerContent
var _controller: EdgeDrawerController

## Emitted when the player saves a brand-new route (HUD performs the LogisticsSystem write).
signal route_create_requested(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName)
## Emitted when the player saves edits to an existing route (HUD performs delete+create).
signal route_update_requested(route_id: StringName, changes: Dictionary)
## Emitted when an editor needs the player to pick a building on the map ("from" or "to").
signal map_select_requested(step: String)
## Emitted when the player confirms deleting an existing route (HUD performs the LogisticsSystem write).
signal route_delete_requested(route_id: StringName)


func _ready() -> void:
	layer = 22  # above the Tasks drawer (layer 21) and Buildings drawer (layer 20)
	process_mode = Node.PROCESS_MODE_ALWAYS

	_content = TransportDrawerContent.new()
	_content.name = "TransportDrawerContent"

	_controller = EdgeDrawerController.new()
	_controller.name = "EdgeDrawerController"
	add_child(_controller)

	var cfg := EdgeDrawerConfig.new()
	cfg.tab_glyph = "🚚"
	cfg.tab_label = "Routes"
	cfg.tab_top_margin = 320.0  # below the Tasks tab (104) and the Buildings drawer (212+96 gap)
	cfg.panel_width = 520.0
	cfg.layer_index = 22

	# Connect before setup() so the initial _update_badge() emission in _content._ready()
	# (triggered by panel.add_child inside _build_ui) already has a listener.
	_content.badge_updated.connect(_controller.set_badge)

	_controller.setup(_content, cfg, self)

	# Forward content signals to this wrapper's own signals so hud.gd wiring is unchanged.
	_content.route_create_requested.connect(
		func(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName) -> void:
			route_create_requested.emit(from_id, to_id, npc_id, item_id))
	_content.route_update_requested.connect(
		func(route_id: StringName, changes: Dictionary) -> void:
			route_update_requested.emit(route_id, changes))
	_content.route_delete_requested.connect(
		func(route_id: StringName) -> void:
			route_delete_requested.emit(route_id))
	_content.map_select_requested.connect(
		func(step: String) -> void:
			map_select_requested.emit(step))


# --- Public API (hud.gd interface — do not change signatures) ----------------

## Slides the panel in and pins it open.
func open() -> void:
	_controller.open()


## Slides the panel out and unpins it.
func close() -> void:
	_controller.close()


## Toggles between open and closed.
func toggle() -> void:
	_controller.toggle()


## Returns true when the panel is currently pinned open.
func is_open() -> bool:
	return _controller.is_open()


## Opens the drawer and immediately edits the given existing route in place.
func open_for_route(route: LogisticsRoute) -> void:
	_controller.open()
	_content.open_for_route(route)


## Opens the drawer with a fresh editor pre-filled with `building_id` as source or destination.
func open_for_building(building_id: StringName, role: String) -> void:
	_controller.open()
	_content.open_for_building(building_id, role)


## Hides the drawer while the player picks a building on the map.
## The active editor and its in-progress tiles are kept intact.
func hide_for_map_select() -> void:
	visible = false


## Re-shows the drawer after map-select and feeds the chosen building back into the active editor.
func resume_map_select(step: String, building_id: StringName) -> void:
	visible = true
	if not _controller.is_open():
		_controller.open()
	_content.resume_map_select(step, building_id)


## Refreshes the badge and (if open) the route list. Call after external route changes.
func refresh() -> void:
	_content.refresh()
