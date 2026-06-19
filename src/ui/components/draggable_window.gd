class_name DraggableWindow extends PanelContainer
## Shared draggable window frame for floating UI panels.
## ADR-0014. Provides a title bar (✥ drag-hint + title + ✕ close) and a public
## `content` container. The entire title bar is the drag surface; the window
## moves itself via `global_position`, clamped to the viewport.
##
## Usage (owner panel builds its body into `content`):
##   var win := DraggableWindow.new()
##   win.title = "My Window"
##   win.close_requested.connect(my_close_func)
##   win.content.add_child(my_body)
##
## The chrome is built in _init(), so `content` and `title` are usable
## immediately after `.new()` — before the node enters the tree.

## Emitted when the user activates the ✕ close button. Owners connect this to
## their own close()/teardown — the window does not free or hide itself.
signal close_requested

## Visual drag affordance shown at the left of the title bar (four-way arrow).
const DRAG_HINT := "✥"
const CLOSE_GLYPH := "✕"

const COLOR_PANEL_BG    := Color(0.176, 0.176, 0.176, 0.97)  ## #2D2D2D
const COLOR_PANEL_BORDER := Color(0.35, 0.35, 0.35, 1.0)
const COLOR_TITLEBAR_BG := Color(0.227, 0.227, 0.227, 1.0)   ## #3A3A3A
const COLOR_TITLE_TEXT  := Color(0.941, 0.929, 0.902)         ## #F0EDE6
const COLOR_HINT_TEXT   := Color(0.659, 0.643, 0.612)         ## #A8A49C
const COLOR_CLOSE_HOVER := Color(0.55, 0.18, 0.18, 1.0)

## Public container — owner panels add their body nodes here.
var content: VBoxContainer

var _title_bar: PanelContainer
var _title_label: Label
var _close_btn: Button

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO


func _init() -> void:
	_build_chrome()


## Window title shown in the bar.
var title: String = "":
	set(value):
		title = value
		if _title_label != null:
			_title_label.text = value
	get:
		return title


func _build_chrome() -> void:
	add_theme_stylebox_override("panel", _make_panel_style())

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_title_bar = PanelContainer.new()
	_title_bar.add_theme_stylebox_override("panel", _make_titlebar_style())
	_title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_title_bar.gui_input.connect(_on_title_bar_input)
	root.add_child(_title_bar)

	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 8)
	_title_bar.add_child(bar_row)

	var hint := Label.new()
	hint.text = DRAG_HINT
	hint.tooltip_text = "Ziehen zum Verschieben"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_color", COLOR_HINT_TEXT)
	bar_row.add_child(hint)

	_title_label = Label.new()
	_title_label.text = title
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.add_theme_color_override("font_color", COLOR_TITLE_TEXT)
	_title_label.add_theme_font_size_override("font_size", 16)
	bar_row.add_child(_title_label)

	_close_btn = Button.new()
	_close_btn.text = CLOSE_GLYPH
	_close_btn.name = "CloseBtn"
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.custom_minimum_size = Vector2(24, 24)
	_close_btn.tooltip_text = "Schließen"
	_close_btn.add_theme_color_override("font_color", COLOR_HINT_TEXT)
	_close_btn.add_theme_color_override("font_hover_color", COLOR_TITLE_TEXT)
	_close_btn.add_theme_stylebox_override("normal", _make_transparent_style())
	_close_btn.add_theme_stylebox_override("hover", _make_close_hover_style())
	_close_btn.add_theme_stylebox_override("pressed", _make_close_hover_style())
	_close_btn.add_theme_stylebox_override("focus", _make_transparent_style())
	_close_btn.pressed.connect(func() -> void: close_requested.emit())
	bar_row.add_child(_close_btn)

	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)


# ── Drag handling ────────────────────────────────────────────────────────────

## Consume scroll wheel events so they don't propagate to _unhandled_input
## and trigger camera zoom while the mouse is over any DraggableWindow.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP \
				or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			accept_event()


## Drag start is detected on the title bar. Motion/release are handled in
## _input() so the drag survives the cursor leaving the bar (fast drags).
func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_dragging = true
		_drag_offset = get_global_mouse_position() - global_position
		accept_event()


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		var target: Vector2 = get_global_mouse_position() - _drag_offset
		global_position = clamp_position(target, size, get_viewport_rect().size)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed:
		_dragging = false
		get_viewport().set_input_as_handled()


## Pure helper (unit-testable): clamp a window's top-left so the whole window
## stays inside a viewport of the given size. If the window is larger than the
## viewport on an axis, it is pinned to 0 on that axis.
static func clamp_position(pos: Vector2, win_size: Vector2, viewport_size: Vector2) -> Vector2:
	var result := pos
	result.x = clampf(result.x, 0.0, maxf(0.0, viewport_size.x - win_size.x))
	result.y = clampf(result.y, 0.0, maxf(0.0, viewport_size.y - win_size.y))
	return result


# ── Styles ───────────────────────────────────────────────────────────────────

func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_PANEL_BG
	s.border_color = COLOR_PANEL_BORDER
	s.set_border_width_all(1)
	return s


func _make_titlebar_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_TITLEBAR_BG
	s.content_margin_left = 8.0
	s.content_margin_right = 6.0
	s.content_margin_top = 4.0
	s.content_margin_bottom = 4.0
	return s


func _make_transparent_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	return s


func _make_close_hover_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_CLOSE_HOVER
	return s
