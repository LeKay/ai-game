class_name TaskDialog extends CanvasLayer
## Backward-compatible wrapper that hosts the Delivery Tasks drawer.
##
## hud.gd continues to call open() / close() / toggle() / is_open() without
## changes. Internally, this class instantiates a TasksDrawerContent and an
## EdgeDrawerController and wires them together.
##
## Open/close model (new — click-to-pin only, no hover-opens-panel):
##   - Idle:              Tab sits at the right edge with a hover-nudge.
##   - Click tab:         Panel slides in (pinned).
##   - Click outside:     Panel slides out (event not consumed — passes to map).
##   - ✕ button / ESC:   Panel slides out.
##
## See design/quick-specs/delivery-task-system-2026-06-20.md.

var _content: TasksDrawerContent
var _controller: EdgeDrawerController


func _ready() -> void:
	layer = 21  # above the Progression Tree overlay (layer 20)
	process_mode = Node.PROCESS_MODE_ALWAYS

	_content = TasksDrawerContent.new()
	_content.name = "TasksDrawerContent"

	_controller = EdgeDrawerController.new()
	_controller.name = "EdgeDrawerController"
	add_child(_controller)

	var cfg := EdgeDrawerConfig.new()
	cfg.tab_glyph = "📋"
	cfg.tab_label = "Tasks"
	cfg.tab_top_margin = 104.0
	cfg.panel_width = 520.0
	cfg.layer_index = 21

	_content.badge_updated.connect(_controller.set_badge)

	_controller.setup(_content, cfg, self)


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


## Refreshes the badge. Call after external state changes (e.g. save load).
func refresh() -> void:
	_content.refresh()
