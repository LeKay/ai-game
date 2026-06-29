class_name EdgeDrawerTab extends Control
## Standalone visual tab that clings to the right screen edge.
##
## Renders a glyph, an optional badge count, and handles hover/click input.
## The tab is intentionally dumb — it emits signals and lets EdgeDrawerController
## decide what those interactions mean (hover = nudge only; click = toggle panel).
##
## Layout (right-edge attached, rounded on the left only):
##   ┌──────┐
##   │  🏛  │  ← glyph_label
##   │  3   │  ← badge_label (hidden when empty)
##   └──────┘
##
## Usage:
##   var tab := EdgeDrawerTab.new()
##   tab.setup(config)
##   add_child(tab)
##   tab.hover_entered.connect(...)
##   tab.hover_exited.connect(...)
##   tab.pressed.connect(...)

## Emitted when the mouse enters the tab area.
signal hover_entered()
## Emitted when the mouse leaves the tab area.
signal hover_exited()
## Emitted on left-mouse-button press over the tab.
signal pressed()

const TAB_WIDTH := 44.0
const TAB_HEIGHT := 96.0

const TAB_COLOR := Color(0.16, 0.17, 0.21, 1.0)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const TEXT_COLOR := Color("#F0EDE6")

var _panel_container: PanelContainer
var _glyph_label: Label
var _badge_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Initialises geometry and style from an EdgeDrawerConfig.
## Call once after adding the tab to the scene tree.
func setup(config: EdgeDrawerConfig) -> void:
	# Full-height holder — only the PanelContainer is hit-testable.
	custom_minimum_size = Vector2(TAB_WIDTH, 0)
	size_flags_vertical = Control.SIZE_FILL

	_panel_container = PanelContainer.new()
	_panel_container.custom_minimum_size = Vector2(TAB_WIDTH, TAB_HEIGHT)
	_panel_container.anchor_left = 0.0
	_panel_container.anchor_right = 1.0
	_panel_container.anchor_top = 0.0
	_panel_container.anchor_bottom = 0.0
	_panel_container.offset_left = 0.0
	# Bleed past the tab's right edge by the full peek distance so the tab always
	# connects to the screen border, even when nudged left at maximum hover offset.
	_panel_container.offset_right = config.hover_peek_distance
	_panel_container.offset_top = config.tab_top_margin
	_panel_container.offset_bottom = config.tab_top_margin + TAB_HEIGHT
	_panel_container.tooltip_text = config.tab_label + " — click to open"
	_panel_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_container.add_theme_stylebox_override("panel", _build_tab_style())
	_panel_container.mouse_entered.connect(_on_mouse_entered)
	_panel_container.mouse_exited.connect(_on_mouse_exited)
	_panel_container.gui_input.connect(_on_gui_input)
	add_child(_panel_container)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_container.add_child(vbox)

	_glyph_label = Label.new()
	_glyph_label.text = config.tab_glyph
	_glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph_label.add_theme_font_size_override("font_size", 22)
	_glyph_label.add_theme_color_override("font_color", TEXT_COLOR)
	_glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_glyph_label)

	_badge_label = Label.new()
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.add_theme_font_size_override("font_size", 13)
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_label.visible = false
	vbox.add_child(_badge_label)


## Updates the badge text and colour. Pass an empty string to hide the badge.
func set_badge(text: String, color: Color) -> void:
	if _badge_label == null:
		return
	if text.is_empty():
		_badge_label.visible = false
		_badge_label.text = ""
	else:
		_badge_label.visible = true
		_badge_label.text = text
		_badge_label.add_theme_color_override("font_color", color)


## Returns the global rect of the underlying PanelContainer (used for
## click-outside detection in the controller).
func get_panel_rect() -> Rect2:
	if _panel_container == null:
		return Rect2()
	return _panel_container.get_global_rect()


func _on_mouse_entered() -> void:
	hover_entered.emit()


func _on_mouse_exited() -> void:
	hover_exited.emit()


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	# Swallow scroll events so they don't reach camera zoom beneath the tab.
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		get_viewport().set_input_as_handled()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		get_viewport().set_input_as_handled()


func _build_tab_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TAB_COLOR
	sb.corner_radius_top_left = 10
	sb.corner_radius_bottom_left = 10
	sb.shadow_color = SHADOW_COLOR
	sb.shadow_size = 6
	return sb
