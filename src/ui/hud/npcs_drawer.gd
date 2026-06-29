class_name NpcsDrawer extends CanvasLayer
## HUD wrapper for the NPCs (Workers) Drawer — analogous to BuildingsDrawer.
##
## Instantiates NpcsDrawerContent and EdgeDrawerController, wires them together, and exposes a
## stable open/close/toggle API to hud.gd.
##
## Layer 24 — above BuildingsDrawer (23), TransportDrawer (22), TaskDialog (21).
##
## Usage (hud.gd):
##   _npcs_drawer = NpcsDrawer.new()
##   _npcs_drawer.name = "NpcsDrawer"
##   _npcs_drawer.visible = false
##   add_child(_npcs_drawer)

var _content:    NpcsDrawerContent
var _controller: EdgeDrawerController


func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS

	_content = NpcsDrawerContent.new()
	_content.name = "NpcsDrawerContent"

	_controller = EdgeDrawerController.new()
	_controller.name = "EdgeDrawerController"
	add_child(_controller)

	var cfg := EdgeDrawerConfig.new()
	cfg.tab_glyph      = "🧑"
	cfg.tab_label      = "Workers"
	cfg.tab_top_margin = 428.0   ## stacked below the Routes tab (320)
	cfg.panel_width    = 520.0
	cfg.layer_index    = 24

	_content.badge_updated.connect(_controller.set_badge)

	_controller.setup(_content, cfg, self)


# --- Public API (hud.gd interface) -------------------------------------------

## Slides the NPCs panel in and pins it open.
func open() -> void:
	_controller.open()


## Slides the NPCs panel out and unpins it.
func close() -> void:
	_controller.close()


## Toggles the NPCs panel between open and closed.
func toggle() -> void:
	_controller.toggle()


## Returns true when the panel is currently pinned open.
func is_open() -> bool:
	return _controller.is_open()


## Returns true when the panel is open and the mouse cursor is over it.
func is_mouse_over_panel() -> bool:
	return _controller.is_mouse_over_panel()


## Opens the drawer and navigates directly to the detail view for the given worker.
func open_for_npc(npc_id: StringName) -> void:
	if not _controller.is_open():
		_controller.open()
	_content.open_for_npc(npc_id)


## Refreshes the badge / list. Call after external state changes (e.g. save load).
func refresh() -> void:
	_content.refresh()
