class_name BuildingsDrawer extends CanvasLayer
## HUD wrapper for the Buildings Drawer — analogous to TaskDialog.
##
## Instantiates BuildingsDrawerContent and EdgeDrawerController, wires them together,
## and exposes a stable open/close/toggle API to hud.gd.
##
## Layer 23 — above TaskDialog (21) and TransportDrawer (22).
##
## Usage (hud.gd):
##   _buildings_drawer = BuildingsDrawer.new()
##   _buildings_drawer.name = "BuildingsDrawer"
##   _buildings_drawer.visible = false
##   add_child(_buildings_drawer)

var _content:    BuildingsDrawerContent
var _controller: EdgeDrawerController


func _ready() -> void:
	layer = 23
	process_mode = Node.PROCESS_MODE_ALWAYS

	_content = BuildingsDrawerContent.new()
	_content.name = "BuildingsDrawerContent"

	_controller = EdgeDrawerController.new()
	_controller.name = "EdgeDrawerController"
	add_child(_controller)

	var cfg := EdgeDrawerConfig.new()
	cfg.tab_glyph      = "🏛"
	cfg.tab_label      = "Buildings"
	cfg.tab_top_margin = 212.0   ## stacked below TransportDrawer tab
	cfg.panel_width    = 520.0
	cfg.layer_index    = 23

	_content.badge_updated.connect(_controller.set_badge)

	_controller.setup(_content, cfg, self)


# --- Public API (hud.gd interface) -------------------------------------------

## Slides the Buildings panel in and pins it open.
func open() -> void:
	_controller.open()


## Slides the Buildings panel out and unpins it.
func close() -> void:
	_controller.close()


## Toggles the Buildings panel between open and closed.
func toggle() -> void:
	_controller.toggle()


## Returns true when the panel is currently pinned open.
func is_open() -> bool:
	return _controller.is_open()


## Returns true when the panel is open and the mouse cursor is over it.
func is_mouse_over_panel() -> bool:
	return _controller.is_mouse_over_panel()


## Opens the drawer and navigates directly to the detail view for the given building.
func open_for_building(building_id: String) -> void:
	if not _controller.is_open():
		_controller.open()
	_content.open_for_building(building_id)


## Refreshes the badge. Call after external state changes (e.g. save load).
func refresh() -> void:
	_content.refresh()


## Opens the drawer and navigates directly to the build picker.
func open_build_picker() -> void:
	if not _controller.is_open():
		_controller.open()
	_content.open_build_picker()
